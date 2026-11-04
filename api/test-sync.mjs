import assert from "node:assert/strict";

const baseUrl = process.env.TEST_API_URL || "http://127.0.0.1:3100";
const setupKey = process.env.ADMIN_SETUP_KEY;
const secondApiUrl = process.env.TEST_SECOND_API_URL || baseUrl;

async function requestAt(url, path, { method = "GET", body, cookie, headers = {} } = {}) {
  const response = await fetch(url + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { "content-type": "application/json" }),
      ...(cookie ? { cookie } : {}),
      ...headers
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { response, data, cookie: response.headers.getSetCookie?.()[0]?.split(";")[0] };
}
const request = (path, options) => requestAt(baseUrl, path, options);

const health = await request("/health");
assert.equal(health.response.status, 200, "API health check");

const invitation = await request("/admin/invitations", {
  method: "POST",
  headers: { "x-admin-setup-key": setupKey }
});
assert.equal(invitation.response.status, 201, "create isolated test invitation");

const unique = Date.now().toString();
const registered = await request("/auth/register", {
  method: "POST",
  body: {
    invite: invitation.data.code,
    name: "Sync Test User",
    email: `sync-${unique}@example.test`,
    mobile: `9${unique.slice(-9)}`,
    password: "sync-test-password"
  }
});
assert.equal(registered.response.status, 201, "register isolated test user");
const cookie = registered.cookie;
assert.ok(cookie, "registration must return session cookie");

const recordId = `test-record-${unique}`;
const operationId = `create-op-${unique}`;
const payload = { id: 987654, description: "sync integration test", amount: 125, type: "expense" };

const pushed = await request("/sync/push", {
  method: "POST",
  cookie,
  body: { operations: [{
    operationId, collection: "transactions", recordId, type: "upsert", baseVersion: 0, data: payload
  }] }
});
assert.equal(pushed.response.status, 200, "push upsert");
assert.equal(pushed.data.results[0].status, "accepted", "upsert accepted");
assert.equal(pushed.data.results[0].version, 1, "initial version is one");

const replay = await request("/sync/push", {
  method: "POST",
  cookie,
  body: { operations: [{
    operationId, collection: "transactions", recordId, type: "upsert", baseVersion: 0, data: payload
  }] }
});
assert.equal(replay.response.status, 200, "idempotent replay");
assert.deepEqual(replay.data.results[0], pushed.data.results[0], "replay returns original result");

const legacy = await request("/data/transactions", { cookie });
assert.equal(legacy.response.status, 200, "legacy GET");
assert.ok(legacy.data.data.some(item => item._syncId === recordId), "sync push is visible to legacy GET");

const conflict = await request("/sync/push", {
  method: "POST",
  cookie,
  body: { operations: [{
    operationId: `stale-op-${unique}`, collection: "transactions", recordId, type: "upsert", baseVersion: 0,
    data: { ...payload, description: "stale update" }
  }] }
});
assert.equal(conflict.response.status, 200, "conflict response");
assert.equal(conflict.data.results[0].status, "conflict", "stale version must conflict");
assert.equal(conflict.data.results[0].currentVersion, 1, "conflict reports current version");

const deleted = await request("/sync/push", {
  method: "POST",
  cookie,
  body: { operations: [{
    operationId: `delete-op-${unique}`, collection: "transactions", recordId, type: "delete", baseVersion: 1
  }] }
});
assert.equal(deleted.response.status, 200, "delete push");
assert.equal(deleted.data.results[0].status, "accepted", "delete accepted");
const afterDelete = await request("/data/transactions", { cookie });
assert.ok(!afterDelete.data.data.some(item => item._syncId === recordId), "tombstone is absent from legacy snapshot");

const collections = {
  transactions: [{ ...payload, _syncId: recordId }],
  debts: [],
  bills: [],
  goals: [],
  wallets: [],
  settings: {},
  categories: []
};
const restored = await request("/data/restore", { method: "POST", cookie, body: { data: collections } });
assert.equal(restored.response.status, 200, "restore backup");
const afterRestore = await request("/data/transactions", { cookie });
assert.ok(afterRestore.data.data.some(item => item._syncId === recordId), "restore revives same sync record id");

const pull = await request("/sync/pull?cursor=0&limit=100", { cookie });
assert.equal(pull.response.status, 200, "pull events");
assert.ok(pull.data.events.some(event => event.recordId === recordId && event.operation === "delete"), "pull includes tombstone event");
assert.ok(pull.data.events.some(event => event.recordId === recordId && event.operation === "upsert" && event.version >= 3), "pull includes restored upsert event");


// Concurrent clients on separate API instances must not both commit the same base version.
const restoredEvent = pull.data.events.filter(event => event.recordId === recordId && event.operation === "upsert").sort((a, b) => b.version - a.version)[0];
assert.ok(restoredEvent, "restored record event exists");
const raceBaseVersion = restoredEvent.version;
const raceRequests = await Promise.all([
  requestAt(baseUrl, "/sync/push", { method: "POST", cookie, body: { operations: [{
    operationId: "race-a-" + unique, collection: "transactions", recordId, type: "upsert", baseVersion: raceBaseVersion,
    data: { ...payload, description: "concurrent writer A" }
  }] } }),
  requestAt(secondApiUrl, "/sync/push", { method: "POST", cookie, body: { operations: [{
    operationId: "race-b-" + unique, collection: "transactions", recordId, type: "upsert", baseVersion: raceBaseVersion,
    data: { ...payload, description: "concurrent writer B" }
  }] } })
]);
assert.ok(raceRequests.every(result => result.response.status === 200), "both concurrent API requests return normally");
const raceStatuses = raceRequests.map(result => result.data.results[0].status).sort();
assert.deepEqual(raceStatuses, ["accepted", "conflict"], "only one concurrent writer may win the same base version");
const raceAccepted = raceRequests.find(result => result.data.results[0].status === "accepted");
const raceConflict = raceRequests.find(result => result.data.results[0].status === "conflict");
assert.equal(raceConflict.data.results[0].currentVersion, raceAccepted.data.results[0].version, "losing writer sees winning version");
// A second user must not see the first user's records.
const secondInvite = await request("/admin/invitations", {
  method: "POST",
  headers: { "x-admin-setup-key": setupKey }
});
assert.equal(secondInvite.response.status, 201, "create second test invitation");
const secondRegistered = await request("/auth/register", {
  method: "POST",
  body: {
    invite: secondInvite.data.code,
    name: "Sync Isolation User",
    email: `isolation-${unique}@example.test`,
    mobile: `8${unique.slice(-9)}`,
    password: "sync-test-password"
  }
});
assert.equal(secondRegistered.response.status, 201, "register second isolated user");
const secondCookie = secondRegistered.cookie;
assert.ok(secondCookie, "second user session cookie");
const isolatedRead = await request("/data/transactions", { cookie: secondCookie });
assert.equal(isolatedRead.response.status, 200, "second user's legacy GET");
assert.ok(!isolatedRead.data.data?.some(item => item._syncId === recordId), "first user's record is not visible to second user");
const isolatedPull = await request("/sync/pull?cursor=0", { cookie: secondCookie });
assert.equal(isolatedPull.response.status, 200, "second user's sync pull");
assert.ok(!isolatedPull.data.events.some(event => event.recordId === recordId), "first user's events are not visible to second user");

// Legacy full-collection writes must also produce record-level sync events.
const legacyRecordId = 876543;
const legacyWrite = await request("/data/transactions", {
  method: "PUT",
  cookie: secondCookie,
  body: { data: [{ id: legacyRecordId, description: "legacy bridge test", amount: 45, type: "income" }] }
});
assert.equal(legacyWrite.response.status, 200, "legacy PUT");
const legacyPull = await request("/sync/pull?cursor=0", { cookie: secondCookie });
assert.ok(legacyPull.data.events.some(event =>
  event.collection === "transactions" &&
  event.operation === "upsert" &&
  event.data?.id === legacyRecordId
), "legacy PUT creates a sync upsert event");

console.log("PASS: PostgreSQL startup, auth, push/pull, idempotency, conflict, tombstone, legacy bridge, restore revival, multi-instance concurrent version safety, and user isolation.");
