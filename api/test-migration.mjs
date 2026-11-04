import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { Client } from "pg";
import { setTimeout as delay } from "node:timers/promises";

const sourceDatabaseUrl = process.env.DATABASE_URL;
const sessionSecret = process.env.SESSION_SECRET;
if (!sourceDatabaseUrl || !sessionSecret) throw new Error("DATABASE_URL and SESSION_SECRET are required");

const databaseName = "amar_hisab_migration_" + process.pid + "_" + Date.now();
const adminUrl = new URL(sourceDatabaseUrl);
const adminClient = new Client({ connectionString: sourceDatabaseUrl });
const apiProcesses = [];
let migrationUrl;

async function waitForHealth(port, child) {
  let lastError;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error("Migration API exited early: " + child.output);
    }
    try {
      const response = await fetch("http://127.0.0.1:" + port + "/health");
      if (response.ok) return;
      lastError = new Error("Health endpoint returned " + response.status);
    } catch (error) {
      lastError = error;
    }
    await delay(500);
  }
  throw new Error("Migration API did not become healthy: " + (lastError?.message || child.output));
}

function startApi(port) {
  const child = spawn(process.execPath, ["server.mjs"], {
    env: {
      ...process.env,
      DATABASE_URL: migrationUrl,
      PORT: String(port),
      ADMIN_EMAIL: "",
      ADMIN_PASSWORD: ""
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  child.output = "";
  child.stdout.on("data", chunk => { child.output += chunk.toString(); });
  child.stderr.on("data", chunk => { child.output += chunk.toString(); });
  apiProcesses.push(child);
  return child;
}

async function stopApi(child) {
  if (!child || child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise(resolve => child.once("exit", resolve)),
    delay(5000)
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

try {
  await adminClient.connect();
  await adminClient.query('CREATE DATABASE "' + databaseName + '"');
  const dbUrl = new URL(sourceDatabaseUrl);
  dbUrl.pathname = "/" + databaseName;
  migrationUrl = dbUrl.toString();

  const legacyClient = new Client({ connectionString: migrationUrl });
  await legacyClient.connect();
  await legacyClient.query(`
    CREATE TABLE app_users (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      mobile TEXT NOT NULL DEFAULT '',
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin','user')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE user_finance_data (
      user_id BIGINT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      collection TEXT NOT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, collection)
    );
  `);
  await legacyClient.query(
    "INSERT INTO app_users(id,name,email,password_hash) VALUES (101,'Legacy One','legacy-one@example.test','unused'),(102,'Legacy Two','legacy-two@example.test','unused')"
  );
  await legacyClient.query(
    `INSERT INTO user_finance_data(user_id,collection,payload) VALUES
      (101,'transactions',$1::jsonb),
      (101,'settings',$2::jsonb),
      (101,'categories','[]'::jsonb),
      (102,'transactions',$3::jsonb)`,
    [
      JSON.stringify([
        { id: 41, _syncId: "legacy-stable-transaction", description: "Keep existing sync id", amount: 120 },
        { id: 42, description: "Generate sync id", amount: 80 }
      ]),
      JSON.stringify({ currency: "BDT", theme: "dark" }),
      JSON.stringify([{ id: 51, description: "Second user's record", amount: 30 }])
    ]
  );
  await legacyClient.end();

  // Two API instances racing through startup must migrate each legacy collection once.
  const first = startApi(3110);
  const second = startApi(3111);
  await Promise.all([waitForHealth(3110, first), waitForHealth(3111, second)]);

  const verify = new Client({ connectionString: migrationUrl });
  await verify.connect();
  const migrated = await verify.query(
    "SELECT user_id,collection,record_id,legacy_id,payload,version FROM user_finance_records ORDER BY user_id,collection,legacy_id"
  );
  assert.equal(migrated.rowCount, 4, "all legacy records migrate, including records for multiple users");

  const stable = migrated.rows.find(row => row.legacy_id === "41");
  assert.ok(stable, "legacy id is retained");
  assert.equal(stable.record_id, "legacy-stable-transaction", "existing _syncId is preserved");
  assert.equal(stable.payload._syncId, "legacy-stable-transaction", "payload keeps existing _syncId");
  assert.equal(Number(stable.version), 1, "migrated record starts at version one");

  const generated = migrated.rows.find(row => row.legacy_id === "42");
  assert.ok(generated, "record without _syncId migrates");
  assert.match(generated.record_id, /^[0-9a-f]{8}-[0-9a-f-]{27}$/i, "missing _syncId is generated as UUID");
  assert.equal(generated.payload._syncId, generated.record_id, "generated id is stored in payload");

  const settings = migrated.rows.find(row => row.user_id === "101" && row.collection === "settings");
  assert.ok(settings, "settings object migrates as a single record");
  assert.equal(settings.payload.currency, "BDT", "settings payload is preserved");
  assert.equal(migrated.rows.filter(row => row.user_id === "102").length, 1, "second user's data remains isolated");

  const events = await verify.query("SELECT user_id,collection,record_id,version,operation,payload FROM user_sync_events ORDER BY event_id");
  assert.equal(events.rowCount, 4, "one initial upsert event is created per migrated record");
  assert.ok(events.rows.every(event => event.operation === "upsert" && Number(event.version) === 1), "migration events are initial upserts at version one");
  assert.equal(events.rows.filter(event => event.user_id === "101" && event.collection === "categories").length, 0, "empty legacy collections do not create phantom events");

  await stopApi(first);
  await stopApi(second);
  const restarted = startApi(3112);
  await waitForHealth(3112, restarted);

  const afterRestart = await verify.query("SELECT COUNT(*)::int AS count FROM user_finance_records");
  const eventsAfterRestart = await verify.query("SELECT COUNT(*)::int AS count FROM user_sync_events");
  assert.equal(afterRestart.rows[0].count, 4, "restarting migration does not duplicate records");
  assert.equal(eventsAfterRestart.rows[0].count, 4, "restarting migration does not duplicate events");

  await verify.end();
  console.log("PASS: legacy migration preserves IDs and payloads, generates missing UUIDs, handles settings and multiple users, skips empty collections, emits initial events, and remains idempotent across concurrent startup and restart.");
} finally {
  await Promise.all(apiProcesses.map(stopApi));
  if (adminClient._connected) {
    await adminClient.query('DROP DATABASE IF EXISTS "' + databaseName + '" WITH (FORCE)').catch(() => {});
    await adminClient.end().catch(() => {});
  }
}
