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
const legacyCreatedEvent = legacyPull.data.events.find(event =>
  event.collection === "transactions" &&
  event.operation === "upsert" &&
  event.data?.id === legacyRecordId
);
assert.ok(legacyCreatedEvent, "legacy PUT creates a sync upsert event");
const stableLegacyRecordId = legacyCreatedEvent.recordId;
assert.ok(stableLegacyRecordId, "legacy bridge assigns a stable sync record id");

// Replacing a legacy record must preserve its sync identity and increment its version.
const legacyUpdate = await request("/data/transactions", {
  method: "PUT",
  cookie: secondCookie,
  body: { data: [{ id: legacyRecordId, description: "legacy bridge updated", amount: 50, type: "income" }] }
});
assert.equal(legacyUpdate.response.status, 200, "legacy update PUT");
const legacyAfterUpdate = await request("/sync/pull?cursor=0&limit=100", { cookie: secondCookie });
const legacyUpdatedEvent = legacyAfterUpdate.data.events.find(event =>
  event.recordId === stableLegacyRecordId && event.operation === "upsert" && event.data?.description === "legacy bridge updated"
);
assert.ok(legacyUpdatedEvent, "legacy update creates an upsert event");
assert.equal(legacyUpdatedEvent.version, legacyCreatedEvent.version + 1, "legacy update increments record version");

// Removing a legacy record from the full collection must create a tombstone.
const legacyDelete = await request("/data/transactions", {
  method: "PUT",
  cookie: secondCookie,
  body: { data: [] }
});
assert.equal(legacyDelete.response.status, 200, "legacy delete PUT");
const legacyAfterDelete = await request("/sync/pull?cursor=0&limit=100", { cookie: secondCookie });
assert.ok(legacyAfterDelete.data.events.some(event =>
  event.recordId === stableLegacyRecordId && event.operation === "delete"
), "legacy collection removal creates a delete event");
const legacySnapshotAfterDelete = await request("/data/transactions", { cookie: secondCookie });
assert.ok(!legacySnapshotAfterDelete.data.data.some(item => item._syncId === stableLegacyRecordId), "legacy snapshot omits deleted record");

// Pull cursors are validated and pagination advances without skipping events.
const firstPage = await request("/sync/pull?cursor=0&limit=1", { cookie: secondCookie });
assert.equal(firstPage.response.status, 200, "first paginated pull");
assert.equal(firstPage.data.events.length, 1, "pull respects requested page size");
assert.equal(firstPage.data.hasMore, true, "pull signals remaining events");
const nextPage = await request("/sync/pull?cursor=" + firstPage.data.nextCursor + "&limit=100", { cookie: secondCookie });
assert.equal(nextPage.response.status, 200, "next paginated pull");
assert.ok(nextPage.data.events.every(event => event.eventId > firstPage.data.nextCursor), "next page contains only later events");
const invalidCursor = await request("/sync/pull?cursor=-1", { cookie: secondCookie });
assert.equal(invalidCursor.response.status, 400, "negative pull cursor is rejected");

// Backup restore must validate the entire payload before changing any collection.
const recoveryRecordId = 765432;
const recoverySeed = await request("/data/transactions", {
  method: "PUT",
  cookie: secondCookie,
  body: { data: [{ id: recoveryRecordId, description: "must survive rejected restore", amount: 77, type: "expense" }] }
});
assert.equal(recoverySeed.response.status, 200, "seed recovery record");
const invalidRestoreData = {
  transactions: [],
  debts: [],
  bills: [],
  goals: [],
  wallets: [],
  settings: {}
};
const invalidRestore = await request("/data/restore", {
  method: "POST",
  cookie: secondCookie,
  body: { data: invalidRestoreData }
});
assert.equal(invalidRestore.response.status, 400, "restore rejects backup missing a required collection");
const afterRejectedRestore = await request("/data/transactions", { cookie: secondCookie });
assert.ok(afterRejectedRestore.data.data.some(item => item.id === recoveryRecordId),
  "rejected restore must not partially clear existing records");

// Re-applying an identical backup is idempotent: no duplicate event or version bump.
// The concurrent-writer test above changed this record, so build the backup from
// the current snapshot rather than reusing the earlier pre-race payload.
const currentTransactions = await request("/data/transactions", { cookie });
assert.equal(currentTransactions.response.status, 200, "read current transactions for idempotent backup");
const idempotentCollections = { ...collections, transactions: currentTransactions.data.data };
const restoreSnapshotBeforeReplay = await request("/sync/pull?cursor=0&limit=1000", { cookie });
const targetBeforeReplay = restoreSnapshotBeforeReplay.data.events
  .filter(event => event.recordId === recordId)
  .sort((a, b) => b.eventId - a.eventId)[0];
assert.ok(targetBeforeReplay, "restored record has a latest event");
const replayedRestore = await request("/data/restore", {
  method: "POST",
  cookie,
  body: { data: idempotentCollections }
});
assert.equal(replayedRestore.response.status, 200, "repeat identical restore");
const restoreSnapshotAfterReplay = await request("/sync/pull?cursor=0&limit=1000", { cookie });
const targetEventsAfterReplay = restoreSnapshotAfterReplay.data.events.filter(event => event.recordId === recordId);
const targetAfterReplay = targetEventsAfterReplay.sort((a, b) => b.eventId - a.eventId)[0];
assert.equal(targetAfterReplay.eventId, targetBeforeReplay.eventId,
  "identical restore must not append another sync event");
assert.equal(targetAfterReplay.version, targetBeforeReplay.version,
  "identical restore must not increment record version");

// A valid empty collection in a backup is an intentional clear and must produce tombstones.
const clearCollections = {
  transactions: [],
  debts: [],
  bills: [],
  goals: [],
  wallets: [],
  settings: {},
  categories: []
};
const clearRestore = await request("/data/restore", {
  method: "POST",
  cookie: secondCookie,
  body: { data: clearCollections }
});
assert.equal(clearRestore.response.status, 200, "restore valid empty collections");
const recoveryPull = await request("/sync/pull?cursor=0&limit=1000", { cookie: secondCookie });
const recoveryCreated = recoveryPull.data.events.find(event =>
  event.collection === "transactions" && event.operation === "upsert" && event.data?.id === recoveryRecordId
);
assert.ok(recoveryCreated, "recovery seed event exists");
assert.ok(recoveryPull.data.events.some(event =>
  event.recordId === recoveryCreated.recordId && event.operation === "delete"
), "restoring an empty collection creates a tombstone for omitted records");
\nconsole.log("PASS: PostgreSQL startup, auth, push/pull pagination, idempotency, conflict, tombstones, legacy create/update/delete bridge, restore revival, multi-instance concurrent version safety, and user isolation.");
