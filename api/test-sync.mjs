import assert from "node:assert/strict";

const baseUrl = process.env.TEST_API_URL || "http://127.0.0.1:3100";
const setupKey = process.env.ADMIN_SETUP_KEY;

async function request(path, { method = "GET", body, cookie, headers = {} } = {}) {
  const response = await fetch(baseUrl + path, {
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

console.log("PASS: PostgreSQL startup, auth, push/pull, idempotency, conflict, tombstone, legacy snapshot, and restore revival.");
