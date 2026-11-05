import express from "express";
import pg from "pg";
import { randomBytes, randomUUID, randomInt, scrypt as scryptCallback, timingSafeEqual, createHmac } from "node:crypto";
import nodemailer from "nodemailer";
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
const mailer = process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS ? nodemailer.createTransport({host:process.env.SMTP_HOST,port:Number(process.env.SMTP_PORT||587),secure:Number(process.env.SMTP_PORT||587)===465,auth:{user:process.env.SMTP_USER,pass:process.env.SMTP_PASS}}) : null;
const resetMessage = "অ্যাকাউন্ট থাকলে Email-এ OTP পাঠানো হয়েছে।";

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
  const payload = Buffer.from(JSON.stringify({ id: user.id, role: user.role, tokenVersion: Number(user.token_version || 0), exp: Date.now() + 7 * 86400000 })).toString("base64url");
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
async function getSessionUser(req) { const session=readSession(req); if(!session)return null; const result=await pool.query("SELECT id,name,email,mobile,role,token_version FROM app_users WHERE id=$1",[session.id]); const user=result.rows[0]; return user && Number(session.tokenVersion||0)===Number(user.token_version||0) ? user : null; }
function otpDigest(email,otp){return createHmac("sha256",sessionSecret).update(email.toLowerCase()+":"+otp).digest("hex");}
function safeDigestEqual(a,b){const x=Buffer.from(String(a||""),"hex"),y=Buffer.from(String(b||""),"hex");return x.length===y.length&&x.length>0&&timingSafeEqual(x,y);}
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
  const schemaClient = await pool.connect();
  try {
    await schemaClient.query("BEGIN");
    await schemaClient.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["amar-hisab:schema:init"]);
    await schemaClient.query(`
    CREATE TABLE IF NOT EXISTS app_users (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      mobile TEXT NOT NULL DEFAULT '',
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin','user')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE app_users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;
    CREATE TABLE IF NOT EXISTS password_reset_otps (user_id BIGINT PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE, otp_hash TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
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
    CREATE TABLE IF NOT EXISTS user_finance_records (
      user_id BIGINT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      collection TEXT NOT NULL CHECK (collection IN ('transactions','debts','bills','goals','wallets','settings','categories')),
      record_id TEXT NOT NULL,
      legacy_id TEXT,
      payload JSONB,
      version BIGINT NOT NULL DEFAULT 1,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      deleted_at TIMESTAMPTZ,
      PRIMARY KEY (user_id, collection, record_id)
    );
    CREATE INDEX IF NOT EXISTS user_finance_records_updated_idx
      ON user_finance_records(user_id, updated_at);
    CREATE TABLE IF NOT EXISTS user_sync_events (
      event_id BIGSERIAL PRIMARY KEY,
      user_id BIGINT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      collection TEXT NOT NULL,
      record_id TEXT NOT NULL,
      version BIGINT NOT NULL,
      operation TEXT NOT NULL CHECK (operation IN ('upsert','delete')),
      payload JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS user_sync_events_user_cursor_idx
      ON user_sync_events(user_id, event_id);
    CREATE TABLE IF NOT EXISTS user_sync_operations (
      user_id BIGINT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      operation_id TEXT NOT NULL,
      result JSONB NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, operation_id)
    );
    `);
    await schemaClient.query("COMMIT");
  } catch (error) {
    await schemaClient.query("ROLLBACK");
    throw error;
  } finally {
    schemaClient.release();
  }
  await migrateLegacyFinanceRecords();
async function migrateLegacyFinanceRecords() {
  const legacy = await pool.query(
    "SELECT user_id, collection, payload FROM user_finance_data ORDER BY user_id, collection"
  );
  for (const row of legacy.rows) {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [String(row.user_id) + ":legacy:" + row.collection]
      );
      const existing = await client.query(
        "SELECT 1 FROM user_finance_records WHERE user_id=$1 AND collection=$2 LIMIT 1",
        [row.user_id, row.collection]
      );
      if (existing.rowCount) {
        await client.query("COMMIT");
        continue;
      }

      const source = row.payload;
      const records = row.collection === "settings"
        ? (source && typeof source === "object" && !Array.isArray(source) ? [{ ...source }] : [])
        : (Array.isArray(source) ? source.filter(item => item && typeof item === "object" && !Array.isArray(item)) : []);
      for (const sourceRecord of records) {
        const record = { ...sourceRecord };
        const recordId = typeof record._syncId === "string" && record._syncId
          ? record._syncId
          : randomUUID();
        record._syncId = recordId;
        const legacyId = record.id === undefined || record.id === null ? null : String(record.id);
        const inserted = await client.query(
          `INSERT INTO user_finance_records(user_id,collection,record_id,legacy_id,payload,version)
           VALUES($1,$2,$3,$4,$5::jsonb,1)
           ON CONFLICT(user_id,collection,record_id) DO NOTHING
           RETURNING record_id`,
          [row.user_id, row.collection, recordId, legacyId, JSON.stringify(record)]
        );
        if (!inserted.rowCount) continue;
        await client.query(
          `INSERT INTO user_sync_events(user_id,collection,record_id,version,operation,payload)
           VALUES($1,$2,$3,1,'upsert',$4::jsonb)`,
          [row.user_id, row.collection, recordId, JSON.stringify(record)]
        );
      }
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}

  if (adminEmail && adminPassword) {
    const inserted = await pool.query(
      "INSERT INTO app_users(name,email,mobile,password_hash,role) VALUES($1,$2,'',$3,'admin') ON CONFLICT(email) DO NOTHING RETURNING id",
      [adminName, adminEmail, await hashPassword(adminPassword)]
    );
    if (inserted.rowCount) {
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
  const result = await pool.query("SELECT id,name,email,mobile,password_hash,role,token_version FROM app_users WHERE lower(email)=lower($1) OR mobile=$1 LIMIT 1", [identity]);
  const user = result.rows[0];
  if (!user || !(await verifyPassword(password, user.password_hash))) return res.status(401).json({ error: "Email/Mobile অথবা Password সঠিক নয়।" });
  setSession(res, user);
  res.json({ user: cleanUser(user) });
}));
app.get("/auth/me", asyncRoute(async (req, res) => {
  const user = await getSessionUser(req);
  if (!user) return res.status(401).json({ error: "লগইন প্রয়োজন।" });
  res.json({ user: cleanUser(user) });
}));
app.put("/auth/profile", asyncRoute(async (req, res) => {
  const session = await getSessionUser(req);
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
  const session = await getSessionUser(req);
  if (!session) return res.status(401).json({ error: "লগইন প্রয়োজন।" });
  const currentPassword = String(req.body?.currentPassword || "");
  const newPassword = String(req.body?.newPassword || "");
  if (newPassword.length < 6) return res.status(400).json({ error: "নতুন পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।" });
  const found = await pool.query("SELECT password_hash FROM app_users WHERE id=$1", [session.id]);
  if (!found.rowCount || !(await verifyPassword(currentPassword, found.rows[0].password_hash))) {
    return res.status(400).json({ error: "বর্তমান পাসওয়ার্ড সঠিক নয়।" });
  }
  await pool.query("UPDATE app_users SET password_hash=$1, token_version=token_version+1 WHERE id=$2", [await hashPassword(newPassword), session.id]);
  res.json({ ok: true });
}));
app.post("/auth/password/forgot", asyncRoute(async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(400).json({ error: "সঠিক Email address দিন।" });
  const generic = "অ্যাকাউন্ট থাকলে Email-এ OTP পাঠানো হয়েছে।";
  if (!mailer) {
    console.error("Password reset SMTP is not configured.");
    return res.json({ message: generic });
  }
  const client = await pool.connect();
  let user = null;
  let otp = null;
  try {
    await client.query("BEGIN");
    const found = await client.query("SELECT id,name,email FROM app_users WHERE lower(email)=lower($1) FOR UPDATE", [email]);
    if (found.rowCount) {
      user = found.rows[0];
      const previous = await client.query("SELECT last_sent_at FROM password_reset_otps WHERE user_id=$1 FOR UPDATE", [user.id]);
      if (previous.rowCount && Date.now() - new Date(previous.rows[0].last_sent_at).getTime() < 60000) {
        await client.query("COMMIT");
        return res.json({ message: generic, retryAfter: 60 });
      }
      otp = String(randomInt(100000, 1000000));
      await client.query(
        "INSERT INTO password_reset_otps(user_id,otp_hash,expires_at,attempts,last_sent_at,created_at) VALUES($1,$2,NOW()+INTERVAL '5 minutes',0,NOW(),NOW()) ON CONFLICT(user_id) DO UPDATE SET otp_hash=EXCLUDED.otp_hash,expires_at=EXCLUDED.expires_at,attempts=0,last_sent_at=NOW(),created_at=NOW()",
        [user.id, createHmac("sha256", sessionSecret).update(email + ":" + otp).digest("hex")]
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  if (user && otp) {
    try {
      const safeName = String(user.name || "ব্যবহারকারী").replace(/[&<>"']/g, (char) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
      })[char]);
      const plainText = [
        "প্রিয় " + (user.name || "ব্যবহারকারী") + ",",
        "",
        "আপনার Amar Hisab অ্যাকাউন্টের Password পরিবর্তনের অনুরোধ পাওয়া গেছে।",
        "আপনার ৬ সংখ্যার OTP: " + otp,
        "এই কোডটি ৫ মিনিটের মধ্যে ব্যবহার করুন।",
        "",
        "নিরাপত্তা নির্দেশনা:",
        "• এই OTP কাউকে জানাবেন না।",
        "• আপনি অনুরোধ না করলে এই ইমেইলটি উপেক্ষা করুন।",
        "• Amar Hisab-এর কেউ আপনার OTP চাইবে না।",
        "",
        "এটি একটি স্বয়ংক্রিয় নিরাপত্তা ইমেইল।",
        "Amar Hisab · schome.my.id"
      ].join("\n");
      const html = `<!doctype html>
<html lang="bn">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:24px 12px;background:#f3f6f4;font-family:Arial,'Noto Sans Bengali',sans-serif;color:#24332d;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;">
    <tr><td style="background:#173b32;padding:26px 28px;text-align:center;">
      <div style="font-size:25px;font-weight:700;letter-spacing:-.5px;color:#ffffff;">◈ Amar Hisab</div>
      <div style="margin-top:7px;font-size:10px;letter-spacing:2px;color:#d8e9df;">YOUR PERSONAL FINANCE COMPANION</div>
    </td></tr>
    <tr><td style="padding:30px 28px 12px;text-align:center;">
      <div style="font-size:30px;line-height:1;color:#21845b;">&#10003;</div>
      <h1 style="margin:13px 0 6px;font-size:22px;color:#24332d;">Password Reset Request</h1>
      <p style="margin:0;font-size:14px;line-height:1.7;color:#718078;">আপনার অ্যাকাউন্টের নিরাপত্তা যাচাই</p>
    </td></tr>
    <tr><td style="padding:18px 28px 8px;font-size:15px;line-height:1.8;color:#34443c;">
      <p style="margin:0 0 12px;">প্রিয় <strong>${safeName}</strong>,</p>
      <p style="margin:0;">আপনার Amar Hisab অ্যাকাউন্টের Password পরিবর্তনের অনুরোধ পাওয়া গেছে। অনুরোধটি সম্পন্ন করতে নিচের OTP ব্যবহার করুন।</p>
    </td></tr>
    <tr><td style="padding:18px 28px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f1f6f3;border:1px solid #dce9e1;border-radius:12px;">
        <tr><td style="padding:22px 12px;text-align:center;">
          <div style="font-size:11px;font-weight:700;letter-spacing:1.5px;color:#718078;">YOUR 6-DIGIT VERIFICATION CODE</div>
          <div style="padding:12px 0 8px;font-size:36px;font-weight:700;letter-spacing:10px;color:#173b32;font-family:Arial,sans-serif;">${otp}</div>
          <span style="display:inline-block;padding:6px 12px;background:#fff1d6;border-radius:20px;font-size:12px;font-weight:700;color:#8a5a12;">৫ মিনিটের মধ্যে মেয়াদ শেষ</span>
        </td></tr>
      </table>
    </td></tr>
    <tr><td style="padding:0 28px 22px;font-size:13px;line-height:1.8;color:#53645b;">
      <p style="margin:0 0 8px;"><strong>নিরাপত্তা নির্দেশনা</strong></p>
      <ul style="margin:0;padding-left:20px;">
        <li>এই OTP কাউকে জানাবেন না।</li>
        <li>আপনি অনুরোধ না করলে ইমেইলটি উপেক্ষা করুন।</li>
        <li>Amar Hisab-এর কেউ আপনার OTP চাইবে না।</li>
      </ul>
    </td></tr>
    <tr><td style="padding:18px 28px;background:#f7f9f8;border-top:1px solid #e8eeea;text-align:center;">
      <p style="margin:0 0 6px;font-size:12px;line-height:1.6;color:#718078;">এটি একটি স্বয়ংক্রিয় নিরাপত্তা ইমেইল। এই ইমেইলের উত্তর দেওয়ার প্রয়োজন নেই।</p>
      <p style="margin:0;font-size:11px;color:#8a9890;">© Amar Hisab · schome.my.id</p>
    </td></tr>
  </table>
</body></html>`;
      await mailer.sendMail({
        from: process.env.SMTP_FROM || "Amar Hisab <noreply@schome.my.id>",
        to: user.email,
        subject: "Amar Hisab - Password Reset OTP",
        text: plainText,
        html
      });
    } catch (error) {
      console.error("Password reset email delivery failed:", error?.message || error);
      const hash = createHmac("sha256", sessionSecret).update(email + ":" + otp).digest("hex");
      await pool.query("DELETE FROM password_reset_otps WHERE user_id=$1 AND otp_hash=$2", [user.id, hash]);
    }
  }
  return res.json({ message: generic });
}));

app.post("/auth/password/reset", asyncRoute(async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  const otp = String(req.body?.otp || "").trim();
  const newPassword = String(req.body?.newPassword || "");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !/^\d{6}$/.test(otp)) return res.status(400).json({ error: "Email এবং ৬ সংখ্যার OTP সঠিকভাবে দিন।" });
  if (newPassword.length < 6) return res.status(400).json({ error: "নতুন Password কমপক্ষে ৬ অক্ষরের হতে হবে।" });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const found = await client.query("SELECT id FROM app_users WHERE lower(email)=lower($1) FOR UPDATE", [email]);
    if (!found.rowCount) {
      await client.query("ROLLBACK");
      return res.status(400).json({ error: "OTP ভুল অথবা মেয়াদ শেষ। নতুন OTP নিন।" });
    }
    const userId = found.rows[0].id;
    const result = await client.query("SELECT otp_hash,expires_at,attempts FROM password_reset_otps WHERE user_id=$1 FOR UPDATE", [userId]);
    if (!result.rowCount || new Date(result.rows[0].expires_at).getTime() <= Date.now() || Number(result.rows[0].attempts) >= 5) {
      await client.query("DELETE FROM password_reset_otps WHERE user_id=$1", [userId]);
      await client.query("COMMIT");
      return res.status(400).json({ error: "OTP ভুল অথবা মেয়াদ শেষ। নতুন OTP নিন।" });
    }
    const expected = createHmac("sha256", sessionSecret).update(email + ":" + otp).digest("hex");
    const a = Buffer.from(result.rows[0].otp_hash, "hex");
    const b = Buffer.from(expected, "hex");
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      const attempts = Number(result.rows[0].attempts) + 1;
      if (attempts >= 5) await client.query("DELETE FROM password_reset_otps WHERE user_id=$1", [userId]);
      else await client.query("UPDATE password_reset_otps SET attempts=$1 WHERE user_id=$2", [attempts, userId]);
      await client.query("COMMIT");
      return res.status(400).json({ error: attempts >= 5 ? "অনেকবার ভুল OTP দেওয়া হয়েছে। নতুন OTP নিন।" : "OTP সঠিক নয়। আবার চেষ্টা করুন।" });
    }
    await client.query("UPDATE app_users SET password_hash=$1,token_version=token_version+1 WHERE id=$2", [await hashPassword(newPassword), userId]);
    await client.query("DELETE FROM password_reset_otps WHERE user_id=$1", [userId]);
    await client.query("COMMIT");
    return res.json({ ok: true, message: "Password পরিবর্তন হয়েছে। নতুন Password দিয়ে Login করুন।" });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}));

app.post("/auth/logout", (_req, res) => {
  res.clearCookie(cookieName, { httpOnly: true, secure: cookieSecure, sameSite: "lax", path: "/" });
  res.json({ ok: true });
});
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
  const user = await getSessionUser(req);
  if (!user) { res.status(401).json({ error: "লগইন প্রয়োজন।" }); return null; }
  return user;
}
app.get("/sync/pull", asyncRoute(async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;
  const rawCursor = req.query.cursor ?? "0";
  const cursor = Number(rawCursor);
  if (!Number.isSafeInteger(cursor) || cursor < 0) {
    return res.status(400).json({ error: "Sync cursor সঠিক নয়।" });
  }
  const limit = Math.min(1000, Math.max(1, Number(req.query.limit) || 500));
  const result = await pool.query(
    `SELECT event_id, collection, record_id, version, operation, payload, created_at
     FROM user_sync_events
     WHERE user_id=$1 AND event_id>$2
     ORDER BY event_id ASC
     LIMIT $3`,
    [user.id, cursor, limit]
  );
  const events = result.rows.map(row => ({
    eventId: Number(row.event_id),
    collection: row.collection,
    recordId: row.record_id,
    version: Number(row.version),
    operation: row.operation,
    data: row.payload,
    createdAt: row.created_at
  }));
  const nextCursor = events.length ? events[events.length - 1].eventId : cursor;
  res.set("Cache-Control", "no-store");
  res.json({ events, nextCursor, hasMore: events.length === limit });
}));

app.get("/sync/events", asyncRoute(async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;
  const lastEventId = Number(req.get("last-event-id") || req.query.cursor || 0);
  if (!Number.isSafeInteger(lastEventId) || lastEventId < 0) {
    return res.status(400).json({ error: "Sync event cursor সঠিক নয়।" });
  }
  let cursor = lastEventId;
  if (!req.get("last-event-id") && req.query.cursor === undefined) {
    const latest = await pool.query(
      "SELECT COALESCE(MAX(event_id),0) AS cursor FROM user_sync_events WHERE user_id=$1",
      [user.id]
    );
    cursor = Number(latest.rows[0]?.cursor || 0);
  }
  res.status(200);
  res.set({
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no"
  });
  res.flushHeaders?.();
  res.write("retry: 3000\n\n");
  let closed = false;
  let lastHeartbeat = Date.now();
  res.on("close", () => { closed = true; });
  while (!closed) {
    const result = await pool.query(
      `SELECT event_id,collection,operation
       FROM user_sync_events
       WHERE user_id=$1 AND event_id>$2
       ORDER BY event_id ASC
       LIMIT 100`,
      [user.id, cursor]
    );
    for (const row of result.rows) {
      cursor = Number(row.event_id);
      res.write("id: " + cursor + "\nevent: sync\ndata: " + JSON.stringify({
        eventId: cursor,
        collection: row.collection,
        operation: row.operation
      }) + "\n\n");
    }
    if (Date.now() - lastHeartbeat >= 20000) {
      res.write(": keep-alive\n\n");
      lastHeartbeat = Date.now();
    }
    if (!result.rows.length) {
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
}));

async function refreshLegacyCollectionSnapshot(client, userId, collection) {
  const records = await client.query(
    "SELECT payload FROM user_finance_records WHERE user_id=$1 AND collection=$2 AND deleted_at IS NULL ORDER BY updated_at ASC,record_id ASC",
    [userId, collection]
  );
  const active = records.rows.map(row => row.payload).filter(value => value && typeof value === "object");
  const payload = collection === "settings" ? (active[active.length - 1] || {}) : active;
  await client.query(
    `INSERT INTO user_finance_data(user_id,collection,payload,updated_at)
     VALUES($1,$2,$3::jsonb,NOW())
     ON CONFLICT(user_id,collection) DO UPDATE SET payload=EXCLUDED.payload,updated_at=NOW()`,
    [userId, collection, JSON.stringify(payload)]
  );
}

app.post("/sync/push", asyncRoute(async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;
  const operations = req.body?.operations;
  if (!Array.isArray(operations) || operations.length < 1 || operations.length > 200) {
    return res.status(400).json({ error: "একবারে ১ থেকে ২০০টি Sync operation পাঠাতে হবে।" });
  }
  const allowedTypes = new Set(["upsert", "delete"]);
  const prepared = [];
  for (const operation of operations) {
    const operationId = String(operation?.operationId || "");
    const collection = String(operation?.collection || "");
    const recordId = String(operation?.recordId || "");
    const type = String(operation?.type || "");
    const baseVersion = operation?.baseVersion;
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(operationId) ||
        !financeCollections.has(collection) ||
        !/^[A-Za-z0-9._:-]{1,128}$/.test(recordId) ||
        !allowedTypes.has(type) ||
        !Number.isSafeInteger(baseVersion) || baseVersion < 0) {
      return res.status(400).json({ error: "Sync operation-এর তথ্য সঠিক নয়।" });
    }
    let data = null;
    if (type === "upsert") {
      if (!operation.data || typeof operation.data !== "object" || Array.isArray(operation.data)) {
        return res.status(400).json({ error: "Upsert operation-এর data সঠিক নয়।" });
      }
      data = { ...operation.data, _syncId: recordId };
      const encoded = JSON.stringify(data);
      if (!encoded || Buffer.byteLength(encoded, "utf8") > 1024 * 1024) {
        return res.status(413).json({ error: "একটি Sync record সর্বোচ্চ ১ MB হতে পারবে।" });
      }
    }
    prepared.push({ operationId, collection, recordId, type, baseVersion, data });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const collection of [...new Set(prepared.map(operation => operation.collection))].sort()) {
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [String(user.id) + ":legacy:" + collection]
      );
    }
    const results = [];
    for (const operation of prepared) {
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [String(user.id) + ":" + operation.operationId]
      );
      const replay = await client.query(
        "SELECT result FROM user_sync_operations WHERE user_id=$1 AND operation_id=$2",
        [user.id, operation.operationId]
      );
      if (replay.rowCount) {
        results.push(replay.rows[0].result);
        continue;
      }
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [String(user.id) + ":" + operation.collection + ":" + operation.recordId]
      );
      const current = await client.query(
        `SELECT version,payload,deleted_at FROM user_finance_records
         WHERE user_id=$1 AND collection=$2 AND record_id=$3 FOR UPDATE`,
        [user.id, operation.collection, operation.recordId]
      );
      const currentVersion = current.rowCount ? Number(current.rows[0].version) : 0;
      if (currentVersion !== operation.baseVersion) {
        const conflict = {
          operationId: operation.operationId,
          status: "conflict",
          currentVersion,
          currentData: current.rowCount && !current.rows[0].deleted_at ? current.rows[0].payload : null,
          deleted: current.rowCount ? Boolean(current.rows[0].deleted_at) : false
        };
        await client.query(
          "INSERT INTO user_sync_operations(user_id,operation_id,result) VALUES($1,$2,$3::jsonb)",
          [user.id, operation.operationId, JSON.stringify(conflict)]
        );
        results.push(conflict);
        continue;
      }
      const nextVersion = currentVersion + 1;
      const payload = operation.type === "upsert" ? JSON.stringify(operation.data) : null;
      const saved = await client.query(
        `INSERT INTO user_finance_records(user_id,collection,record_id,legacy_id,payload,version,updated_at,deleted_at)
         VALUES($1,$2,$3,$4,$5::jsonb,$6,NOW(),CASE WHEN $7='delete' THEN NOW() ELSE NULL END)
         ON CONFLICT(user_id,collection,record_id) DO UPDATE SET
           legacy_id=COALESCE(EXCLUDED.legacy_id,user_finance_records.legacy_id),
           payload=EXCLUDED.payload,
           version=EXCLUDED.version,
           updated_at=NOW(),
           deleted_at=EXCLUDED.deleted_at
         RETURNING version`,
        [
          user.id, operation.collection, operation.recordId,
          operation.data?.id === undefined || operation.data?.id === null ? null : String(operation.data.id),
          payload, nextVersion, operation.type
        ]
      );
      const event = await client.query(
        `INSERT INTO user_sync_events(user_id,collection,record_id,version,operation,payload)
         VALUES($1,$2,$3,$4,$5,$6::jsonb) RETURNING event_id`,
        [user.id, operation.collection, operation.recordId, nextVersion, operation.type, payload]
      );
      const accepted = {
        operationId: operation.operationId,
        status: "accepted",
        version: Number(saved.rows[0].version),
        eventId: Number(event.rows[0].event_id)
      };
      await client.query(
        "INSERT INTO user_sync_operations(user_id,operation_id,result) VALUES($1,$2,$3::jsonb)",
        [user.id, operation.operationId, JSON.stringify(accepted)]
      );
      results.push(accepted);
    }
    for (const collection of new Set(prepared.map(operation => operation.collection))) {
      await refreshLegacyCollectionSnapshot(client, user.id, collection);
    }
    await client.query("COMMIT");
    res.set("Cache-Control", "no-store");
    res.json({ results });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}));

async function saveLegacyCollectionWithSync(client, userId, collection, payload) {
  await client.query(
    "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
    [String(userId) + ":legacy:" + collection]
  );
  const current = await client.query(
    "SELECT record_id,legacy_id,payload,version,deleted_at FROM user_finance_records WHERE user_id=$1 AND collection=$2 FOR UPDATE",
    [userId, collection]
  );
  const byRecordId = new Map(current.rows.map(row => [row.record_id, row]));
  const byLegacyId = new Map(current.rows.filter(row => row.legacy_id !== null).map(row => [String(row.legacy_id), row]));
  const sourceRecords = collection === "settings"
    ? (payload && typeof payload === "object" && !Array.isArray(payload) ? [payload] : [])
    : (Array.isArray(payload) ? payload.filter(item => item && typeof item === "object" && !Array.isArray(item)) : []);
  const seen = new Set();
  const savedRecords = [];
  const stableJson = value => {
    if (Array.isArray(value)) return "[" + value.map(stableJson).join(",") + "]";
    if (value && typeof value === "object") {
      return "{" + Object.keys(value).sort().map(key => JSON.stringify(key) + ":" + stableJson(value[key])).join(",") + "}";
    }
    return JSON.stringify(value);
  };

  for (const source of sourceRecords) {
    const legacyId = source.id === undefined || source.id === null ? null : String(source.id);
    const existing = (typeof source._syncId === "string" ? byRecordId.get(source._syncId) : null)
      || (legacyId !== null ? byLegacyId.get(legacyId) : null);
    const recordId = existing?.record_id || (typeof source._syncId === "string" && source._syncId ? source._syncId : randomUUID());
    const record = { ...source, _syncId: recordId };
    const encoded = JSON.stringify(record);
    seen.add(recordId);

    if (!existing) {
      await client.query(
        "INSERT INTO user_finance_records(user_id,collection,record_id,legacy_id,payload,version) VALUES($1,$2,$3,$4,$5::jsonb,1)",
        [userId, collection, recordId, legacyId, encoded]
      );
      await client.query(
        "INSERT INTO user_sync_events(user_id,collection,record_id,version,operation,payload) VALUES($1,$2,$3,1,'upsert',$4::jsonb)",
        [userId, collection, recordId, encoded]
      );
    } else if (existing.deleted_at || stableJson(existing.payload) !== stableJson(record)) {
      const version = Number(existing.version) + 1;
      await client.query(
        "UPDATE user_finance_records SET legacy_id=$4,payload=$5::jsonb,version=$6,updated_at=NOW(),deleted_at=NULL WHERE user_id=$1 AND collection=$2 AND record_id=$3",
        [userId, collection, recordId, legacyId, encoded, version]
      );
      await client.query(
        "INSERT INTO user_sync_events(user_id,collection,record_id,version,operation,payload) VALUES($1,$2,$3,$4,'upsert',$5::jsonb)",
        [userId, collection, recordId, version, encoded]
      );
    }
    savedRecords.push(record);
  }

  for (const row of current.rows) {
    if (seen.has(row.record_id) || row.deleted_at) continue;
    const version = Number(row.version) + 1;
    await client.query(
      "UPDATE user_finance_records SET payload=NULL,version=$4,updated_at=NOW(),deleted_at=NOW() WHERE user_id=$1 AND collection=$2 AND record_id=$3",
      [userId, collection, row.record_id, version]
    );
    await client.query(
      "INSERT INTO user_sync_events(user_id,collection,record_id,version,operation,payload) VALUES($1,$2,$3,$4,'delete',NULL)",
      [userId, collection, row.record_id, version]
    );
  }

  const legacyPayload = payload === null ? null : collection === "settings" ? (savedRecords[0] || {}) : savedRecords;
  const legacy = await client.query(
    `INSERT INTO user_finance_data(user_id,collection,payload,updated_at)
     VALUES($1,$2,$3::jsonb,NOW())
     ON CONFLICT(user_id,collection) DO UPDATE SET payload=EXCLUDED.payload,updated_at=NOW()
     RETURNING updated_at`,
    [userId, collection, JSON.stringify(legacyPayload)]
  );
  return { updatedAt: legacy.rows[0].updated_at, data: legacyPayload };
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
  if (payload !== null && (typeof payload !== "object")) {
    return res.status(400).json({ error: "Data-এর format সঠিক নয়।" });
  }
  const encoded = JSON.stringify(payload);
  if (!encoded || Buffer.byteLength(encoded, "utf8") > 2 * 1024 * 1024) {
    return res.status(413).json({ error: "একবারে সর্বোচ্চ ২ MB data সংরক্ষণ করা যাবে।" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const saved = await saveLegacyCollectionWithSync(client, user.id, collection, payload);
    await client.query("COMMIT");
    res.set("Cache-Control", "no-store");
    res.json({ ok: true, collection, updatedAt: saved.updatedAt });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}));

app.post("/data/restore", asyncRoute(async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;
  const data = req.body?.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return res.status(400).json({ error: "Backup data-এর format সঠিক নয়।" });
  }
  const supplied = Object.keys(data);
  if (supplied.length !== financeCollections.size || supplied.some(key => !financeCollections.has(key))) {
    return res.status(400).json({ error: "Backup-এ প্রয়োজনীয় collection তালিকা সঠিক নয়।" });
  }

  const entries = [];
  let totalBytes = 0;
  for (const collection of financeCollections) {
    if (!Object.prototype.hasOwnProperty.call(data, collection)) {
      return res.status(400).json({ error: collection + " collection backup-এ নেই।" });
    }
    const payload = data[collection];
    if (payload !== null && typeof payload !== "object") {
      return res.status(400).json({ error: collection + " collection-এর format সঠিক নয়।" });
    }
    if (collection === "settings" && payload !== null && Array.isArray(payload)) {
      return res.status(400).json({ error: "settings collection-এর format সঠিক নয়।" });
    }
    if (collection !== "settings" && payload !== null && !Array.isArray(payload)) {
      return res.status(400).json({ error: collection + " collection-এর format সঠিক নয়।" });
    }
    const encoded = JSON.stringify(payload);
    const bytes = Buffer.byteLength(encoded, "utf8");
    if (bytes > 2 * 1024 * 1024) {
      return res.status(413).json({ error: collection + " collection ২ MB সীমা ছাড়িয়েছে।" });
    }
    totalBytes += bytes;
    entries.push([collection, payload]);
  }
  if (totalBytes > 8 * 1024 * 1024) {
    return res.status(413).json({ error: "সম্পূর্ণ backup সর্বোচ্চ ৮ MB হতে পারবে।" });
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const [collection] of entries) {
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [String(user.id) + ":legacy:" + collection]
      );
    }
    for (const [collection, payload] of entries) {
      await saveLegacyCollectionWithSync(client, user.id, collection, payload);
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
  const session = await getSessionUser(req);
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
