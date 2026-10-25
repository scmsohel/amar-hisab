import express from "express";
import pg from "pg";
import { randomBytes, scrypt as scryptCallback, timingSafeEqual, createHmac } from "node:crypto";
import { promisify } from "node:util";

const scrypt = promisify(scryptCallback);
const app = express();
const port = Number(process.env.PORT || 3000);
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 10 });
const sessionSecret = process.env.SESSION_SECRET;
const cookieSecure = process.env.COOKIE_SECURE === "true";
const adminEmail = (process.env.ADMIN_EMAIL || "").trim().toLowerCase();
const adminPassword = process.env.ADMIN_PASSWORD || "";
const adminName = process.env.ADMIN_NAME || "Amar Hisab Admin";
const setupKey = process.env.ADMIN_SETUP_KEY || "";

if (!process.env.DATABASE_URL || !sessionSecret || sessionSecret.length < 32) {
  throw new Error("DATABASE_URL and SESSION_SECRET (at least 32 characters) are required");
}
if (adminPassword && adminPassword.length < 12) {
  throw new Error("ADMIN_PASSWORD must be at least 12 characters");
}
app.disable("x-powered-by");
app.set("trust proxy", 1);
app.use(express.json({ limit: "10mb" }));

const cookieName = "amar_hisab_session";
const sign = (value) => createHmac("sha256", sessionSecret).update(value).digest("base64url");
function setSession(res, user) {
  const payload = Buffer.from(JSON.stringify({ id: user.id, role: user.role, exp: Date.now() + 7 * 86400000 })).toString("base64url");
  const token = payload + "." + sign(payload);
  res.cookie(cookieName, token, { httpOnly: true, secure: cookieSecure, sameSite: "lax", path: "/", maxAge: 7 * 86400000 });
}
function readSession(req) {
  const raw = (req.headers.cookie || "").split(";").map(v => v.trim()).find(v => v.startsWith(cookieName + "="))?.slice(cookieName.length + 1);
  if (!raw) return null;
  const [payload, signature] = raw.split(".");
  if (!payload || !signature) return null;
  const expected = Buffer.from(sign(payload));
  const actual = Buffer.from(signature);
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) return null;
  try {
    const session = JSON.parse(Buffer.from(payload, "base64url").toString());
    return session.exp > Date.now() ? session : null;
  } catch { return null; }
}
const asyncRoute = fn => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
const cleanUser = ({ id, name, email, mobile, role }) => ({ id, name, email, mobile, role });
async function hashPassword(password) {
  const salt = randomBytes(16).toString("hex");
  const key = await scrypt(password, salt, 64);
  return salt + ":" + Buffer.from(key).toString("hex");
}
async function verifyPassword(password, stored) {
  const [salt, hash] = String(stored || "").split(":");
  if (!salt || !hash) return false;
  const actual = Buffer.from(await scrypt(password, salt, 64));
  const expected = Buffer.from(hash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
async function init() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_users (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      mobile TEXT NOT NULL DEFAULT '',
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin','user')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS user_finance_data (
      user_id BIGINT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      collection TEXT NOT NULL CHECK (collection IN ('transactions','debts','bills','goals','wallets','settings','categories')),
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, collection)
    );
    CREATE TABLE IF NOT EXISTS invitations (
      id BIGSERIAL PRIMARY KEY,
      code_hash TEXT NOT NULL UNIQUE,
      created_by BIGINT REFERENCES app_users(id) ON DELETE SET NULL,
      used_by BIGINT REFERENCES app_users(id) ON DELETE SET NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
  if (adminEmail && adminPassword) {
    const existing = await pool.query("SELECT id FROM app_users WHERE email=$1", [adminEmail]);
    if (!existing.rowCount) {
      await pool.query("INSERT INTO app_users(name,email,mobile,password_hash,role) VALUES($1,$2,'',$3,'admin')",
        [adminName, adminEmail, await hashPassword(adminPassword)]);
      console.log("Initial admin account created from environment configuration.");
    }
  }
}
app.get("/health", asyncRoute(async (_req, res) => {
  await pool.query("SELECT 1");
  res.json({ status: "ok" });
}));
app.post("/auth/login", asyncRoute(async (req, res) => {
  const identity = String(req.body?.identity || "").trim();
  const password = String(req.body?.password || "");
  if (!identity || !password) return res.status(400).json({ error: "Email/Mobile এবং Password দিন।" });
  const result = await pool.query("SELECT id,name,email,mobile,password_hash,role FROM app_users WHERE lower(email)=lower($1) OR mobile=$1 LIMIT 1", [identity]);
  const user = result.rows[0];
  if (!user || !(await verifyPassword(password, user.password_hash))) return res.status(401).json({ error: "Email/Mobile অথবা Password সঠিক নয়।" });
  setSession(res, user);
  res.json({ user: cleanUser(user) });
}));
app.get("/auth/me", asyncRoute(async (req, res) => {
  const session = readSession(req);
  if (!session) return res.status(401).json({ error: "লগইন প্রয়োজন।" });
  const result = await pool.query("SELECT id,name,email,mobile,role FROM app_users WHERE id=$1", [session.id]);
  if (!result.rowCount) return res.status(401).json({ error: "অ্যাকাউন্ট পাওয়া যায়নি।" });
  res.json({ user: cleanUser(result.rows[0]) });
}));
app.put("/auth/profile", asyncRoute(async (req, res) => {
  const session = readSession(req);
  if (!session) return res.status(401).json({ error: "লগইন প্রয়োজন।" });
  const name = String(req.body?.name || "").trim();
  const mobile = String(req.body?.mobile || "").trim();
  if (name.length < 2 || name.length > 100 || mobile.length > 30) {
    return res.status(400).json({ error: "নাম কমপক্ষে ২ অক্ষরের হতে হবে এবং মোবাইল নম্বর সঠিক দিন।" });
  }
  const result = await pool.query("UPDATE app_users SET name=$1,mobile=$2 WHERE id=$3 RETURNING id,name,email,mobile,role", [name, mobile, session.id]);
  if (!result.rowCount) return res.status(404).json({ error: "অ্যাকাউন্ট পাওয়া যায়নি।" });
  res.json({ user: cleanUser(result.rows[0]) });
}));
app.post("/auth/password", asyncRoute(async (req, res) => {
  const session = readSession(req);
  if (!session) return res.status(401).json({ error: "লগইন প্রয়োজন।" });
  const currentPassword = String(req.body?.currentPassword || "");
  const newPassword = String(req.body?.newPassword || "");
  if (newPassword.length < 12) return res.status(400).json({ error: "নতুন পাসওয়ার্ড কমপক্ষে ১২ অক্ষরের হতে হবে।" });
  const found = await pool.query("SELECT password_hash FROM app_users WHERE id=$1", [session.id]);
  if (!found.rowCount || !(await verifyPassword(currentPassword, found.rows[0].password_hash))) {
    return res.status(400).json({ error: "বর্তমান পাসওয়ার্ড সঠিক নয়।" });
  }
  await pool.query("UPDATE app_users SET password_hash=$1 WHERE id=$2", [await hashPassword(newPassword), session.id]);
  res.json({ ok: true });
}));
app.post("/auth/logout", (_req, res) => {
  res.clearCookie(cookieName, { httpOnly: true, secure: cookieSecure, sameSite: "lax", path: "/" });
  res.json({ ok: true });
});
app.post("/auth/invite/verify", asyncRoute(async (req, res) => {
  const invite = String(req.body?.invite || "").trim();
  if (!invite) return res.status(400).json({ error: "ইনভাইট কোড দিন।" });

  const inviteHash = createHmac("sha256", sessionSecret).update(invite).digest("hex");
  const result = await pool.query(
    "SELECT id FROM invitations WHERE code_hash=$1 AND used_by IS NULL AND expires_at>NOW()",
    [inviteHash],
  );
  if (!result.rowCount) {
    return res.status(400).json({ error: "ইনভাইট কোড ভুল, মেয়াদ শেষ, অথবা ব্যবহৃত হয়েছে।" });
  }
  res.json({ valid: true });
}));

app.post("/auth/register", asyncRoute(async (req, res) => {
  const invite = String(req.body?.invite || "").trim();
  const name = String(req.body?.name || "").trim();
  const email = String(req.body?.email || "").trim().toLowerCase();
  const mobile = String(req.body?.mobile || "").trim();
  const password = String(req.body?.password || "");
  if (!invite || !name || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !mobile || password.length < 8) {
    return res.status(400).json({ error: "সব তথ্য সঠিকভাবে দিন; Password কমপক্ষে ৮ অক্ষরের হতে হবে।" });
  }
  const inviteHash = createHmac("sha256", sessionSecret).update(invite).digest("hex");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const inviteResult = await client.query("SELECT id FROM invitations WHERE code_hash=$1 AND used_by IS NULL AND expires_at>NOW() FOR UPDATE", [inviteHash]);
    if (!inviteResult.rowCount) { await client.query("ROLLBACK"); return res.status(400).json({ error: "Invitation code ভুল, মেয়াদ শেষ, অথবা ব্যবহৃত হয়েছে।" }); }
    const duplicate = await client.query("SELECT id FROM app_users WHERE email=$1 OR mobile=$2", [email, mobile]);
    if (duplicate.rowCount) { await client.query("ROLLBACK"); return res.status(409).json({ error: "এই Email বা Mobile দিয়ে account আছে।" }); }
    const inserted = await client.query("INSERT INTO app_users(name,email,mobile,password_hash,role) VALUES($1,$2,$3,$4,'user') RETURNING id,name,email,mobile,role",
      [name, email, mobile, await hashPassword(password)]);
    await client.query("UPDATE invitations SET used_by=$1 WHERE id=$2", [inserted.rows[0].id, inviteResult.rows[0].id]);
    await client.query("COMMIT");
    setSession(res, inserted.rows[0]);
    res.status(201).json({ user: cleanUser(inserted.rows[0]) });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally { client.release(); }
}));

const financeCollections = new Set(["transactions", "debts", "bills", "goals", "wallets", "settings", "categories"]);
async function requireUser(req, res) {
  const session = readSession(req);
  if (!session) {
    res.status(401).json({ error: "লগইন প্রয়োজন।" });
    return null;
  }
  const result = await pool.query("SELECT id,name,email,mobile,role FROM app_users WHERE id=$1", [session.id]);
  if (!result.rowCount) {
    res.status(401).json({ error: "অ্যাকাউন্ট পাওয়া যায়নি।" });
    return null;
  }
  return result.rows[0];
}
app.get("/data/:collection", asyncRoute(async (req, res) => {
  const collection = String(req.params.collection || "");
  if (!financeCollections.has(collection)) return res.status(404).json({ error: "এই data collection পাওয়া যায়নি।" });
  const user = await requireUser(req, res);
  if (!user) return;
  const result = await pool.query(
    "SELECT payload, updated_at FROM user_finance_data WHERE user_id=$1 AND collection=$2",
    [user.id, collection]
  );
  res.set("Cache-Control", "no-store");
  res.json({ collection, data: result.rows[0]?.payload ?? null, updatedAt: result.rows[0]?.updated_at ?? null });
}));
app.put("/data/:collection", asyncRoute(async (req, res) => {
  const collection = String(req.params.collection || "");
  if (!financeCollections.has(collection)) return res.status(404).json({ error: "এই data collection পাওয়া যায়নি।" });
  const user = await requireUser(req, res);
  if (!user) return;
  if (!Object.prototype.hasOwnProperty.call(req.body || {}, "data")) {
    return res.status(400).json({ error: "সংরক্ষণের data দেওয়া হয়নি।" });
  }
  const payload = req.body.data;
  if (payload !== null && !Array.isArray(payload) && (typeof payload !== "object" || payload === null)) {
    return res.status(400).json({ error: "Data-এর format সঠিক নয়।" });
  }
  const encoded = JSON.stringify(payload);
  if (!encoded || Buffer.byteLength(encoded, "utf8") > 2 * 1024 * 1024) {
    return res.status(413).json({ error: "একবারে সর্বোচ্চ ২ MB data সংরক্ষণ করা যাবে।" });
  }
  const result = await pool.query(
    `INSERT INTO user_finance_data(user_id, collection, payload, updated_at)
     VALUES($1,$2,$3::jsonb,NOW())
     ON CONFLICT(user_id, collection) DO UPDATE SET payload=EXCLUDED.payload, updated_at=NOW()
     RETURNING updated_at`,
    [user.id, collection, encoded]
  );
  res.set("Cache-Control", "no-store");
  res.json({ ok: true, collection, updatedAt: result.rows[0].updated_at });
}));

app.post("/data/restore", asyncRoute(async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;
  const data = req.body?.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return res.status(400).json({ error: "Backup data-এর format সঠিক নয়।" });
  }
  const supplied = Object.keys(data);
  if (supplied.length !== financeCollections.size || supplied.some((key) => !financeCollections.has(key))) {
    return res.status(400).json({ error: "Backup-এ প্রয়োজনীয় collection তালিকা সঠিক নয়।" });
  }
  const entries = [];
  let totalBytes = 0;
  for (const collection of financeCollections) {
    if (!Object.prototype.hasOwnProperty.call(data, collection)) {
      return res.status(400).json({ error: collection + " collection backup-এ নেই।" });
    }
    const payload = data[collection];
    if (payload !== null && !Array.isArray(payload) && typeof payload !== "object") {
      return res.status(400).json({ error: collection + " collection-এর format সঠিক নয়।" });
    }
    const encoded = JSON.stringify(payload);
    const bytes = Buffer.byteLength(encoded, "utf8");
    if (bytes > 2 * 1024 * 1024) {
      return res.status(413).json({ error: collection + " collection ২ MB সীমা ছাড়িয়েছে।" });
    }
    totalBytes += bytes;
    entries.push([collection, encoded]);
  }
  if (totalBytes > 8 * 1024 * 1024) {
    return res.status(413).json({ error: "সম্পূর্ণ backup সর্বোচ্চ ৮ MB হতে পারবে।" });
  }
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const [collection, encoded] of entries) {
      await client.query(
        `INSERT INTO user_finance_data(user_id, collection, payload, updated_at)
         VALUES($1,$2,$3::jsonb,NOW())
         ON CONFLICT(user_id, collection) DO UPDATE SET payload=EXCLUDED.payload, updated_at=NOW()`,
        [user.id, collection, encoded]
      );
    }
    await client.query("COMMIT");
    res.set("Cache-Control", "no-store");
    res.json({ ok: true, restoredCollections: entries.length });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}));

app.post("/admin/invitations", asyncRoute(async (req, res) => {
  const session = readSession(req);
  const isAdmin = session?.role === "admin";
  const setupAuthorized = setupKey && req.get("x-admin-setup-key") === setupKey;
  if (!isAdmin && !setupAuthorized) return res.status(403).json({ error: "Admin access required." });
  const code = randomBytes(18).toString("base64url");
  const codeHash = createHmac("sha256", sessionSecret).update(code).digest("hex");
  const createdBy = isAdmin ? session.id : null;
  const result = await pool.query("INSERT INTO invitations(code_hash,created_by,expires_at) VALUES($1,$2,NOW()+INTERVAL '7 days') RETURNING expires_at", [codeHash, createdBy]);
  res.status(201).json({ code, expiresAt: result.rows[0].expires_at });
}));
app.use((err, _req, res, _next) => {
  console.error("API error:", err?.message || err);
  res.status(500).json({ error: "সার্ভারে সমস্যা হয়েছে। পরে আবার চেষ্টা করুন।" });
});
init().then(() => app.listen(port, "0.0.0.0", () => console.log("Amar Hisab API listening on " + port)))
  .catch(error => { console.error("API startup failed:", error); process.exit(1); });
