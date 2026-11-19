import crypto from "node:crypto";
import { readFileSync } from "node:fs";
import express from "express";
import { createRemoteJWKSet, decodeProtectedHeader, importJWK, jwtVerify, SignJWT } from "jose";
import pg from "pg";

const { Pool } = pg;
const required = ["PLAID_CLIENT_ID", "PLAID_SECRET", "DATABASE_URL", "TOKEN_ENCRYPTION_KEY", "SESSION_SECRET"];
const missing = required.filter((name) => !process.env[name] || process.env[name].startsWith("PASTE_"));
if (missing.length) {
  console.error(`Missing required environment variables: ${missing.join(", ")}`);
  process.exit(1);
}

const config = {
  port: Number(process.env.PORT || 8080),
  plaidEnvironment: process.env.PLAID_ENV || "sandbox",
  plaidBaseURL: process.env.PLAID_ENV === "production" ? "https://production.plaid.com" : process.env.PLAID_ENV === "development" ? "https://development.plaid.com" : "https://sandbox.plaid.com",
  appBundleID: process.env.APP_BUNDLE_ID || "com.aydanjs.BudgetBuddyFinance",
  redirectURI: process.env.PLAID_REDIRECT_URI,
  webhookURL: process.env.PLAID_WEBHOOK_URL,
  allowDevelopmentLogin: process.env.ALLOW_DEVELOPMENT_LOGIN === "true",
  // Keep portfolio calls off until the Plaid production application approves
  // Investments and Liabilities. Balance works alongside Transactions.
  portfolioProductsEnabled: process.env.PLAID_PORTFOLIO_PRODUCTS_ENABLED === "true",
};

const encryptionKey = crypto.createHash("sha256").update(process.env.TOKEN_ENCRYPTION_KEY).digest();

const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DATABASE_SSL === "false" ? false : { rejectUnauthorized: false } });
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const sessionKey = new TextEncoder().encode(process.env.SESSION_SECRET);
const app = express();
app.use(express.json({
  limit: "128kb",
  verify: (request, _response, buffer) => { request.rawBody = Buffer.from(buffer); },
}));
const webhookKeys = new Map();

function encrypt(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", encryptionKey, iv);
  const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), ciphertext].map((part) => part.toString("base64")).join(".");
}

function decrypt(value) {
  const [iv, tag, ciphertext] = value.split(".").map((part) => Buffer.from(part, "base64"));
  const decipher = crypto.createDecipheriv("aes-256-gcm", encryptionKey, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
}

function calendarDateKey(date, requestedTimeZone) {
  let timeZone = requestedTimeZone || "UTC";
  try {
    // Validate the device-provided IANA identifier before using it.
    new Intl.DateTimeFormat("en-CA", { timeZone }).format(date);
  } catch {
    timeZone = "UTC";
  }
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

async function plaid(path, body) {
  const response = await fetch(`${config.plaidBaseURL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_id: process.env.PLAID_CLIENT_ID, secret: process.env.PLAID_SECRET, ...body }),
  });
  const data = await response.json();
  if (!response.ok) {
    const error = new Error(data.error_message || "Plaid request failed");
    error.status = 502;
    error.plaid = { error_code: data.error_code, error_type: data.error_type, request_id: data.request_id };
    throw error;
  }
  return data;
}

async function issueSession(userID) {
  return new SignJWT({ sub: userID, purpose: "budgetbuddy-session" }).setProtectedHeader({ alg: "HS256" }).setIssuedAt().setExpirationTime("30d").sign(sessionKey);
}

async function requireUser(request, response, next) {
  try {
    const token = request.headers.authorization?.replace(/^Bearer\s+/i, "");
    if (!token) return response.status(401).json({ error: "Sign in is required." });
    const { payload } = await jwtVerify(token, sessionKey, { algorithms: ["HS256"] });
    if (payload.purpose !== "budgetbuddy-session" || !payload.sub) throw new Error("Invalid session");
    request.userID = payload.sub;
    next();
  } catch {
    response.status(401).json({ error: "Your session expired. Please sign in again." });
  }
}

async function verifyPlaidWebhook(request) {
  const signedJWT = request.headers["plaid-verification"];
  if (!signedJWT || !request.rawBody) return false;
  const header = decodeProtectedHeader(signedJWT);
  if (header.alg !== "ES256" || !header.kid) return false;
  let key = webhookKeys.get(header.kid);
  if (!key) {
    const data = await plaid("/webhook_verification_key/get", { key_id: header.kid });
    key = await importJWK(data.key, "ES256");
    webhookKeys.set(header.kid, key);
  }
  const { payload } = await jwtVerify(signedJWT, key, { algorithms: ["ES256"], maxTokenAge: "5 min" });
  const actualHash = crypto.createHash("sha256").update(request.rawBody).digest("hex");
  const claimedHash = payload.request_body_sha256;
  if (typeof claimedHash !== "string" || actualHash.length !== claimedHash.length) return false;
  return crypto.timingSafeEqual(Buffer.from(actualHash), Buffer.from(claimedHash));
}

async function syncItem(item) {
  const accessToken = decrypt(item.access_token_encrypted);
  let cursor = item.cursor;
  let hasMore = true;
  const added = [];
  const modified = [];
  const removed = [];
  while (hasMore) {
    const data = await plaid("/transactions/sync", { access_token: accessToken, cursor });
    added.push(...data.added);
    modified.push(...data.modified);
    removed.push(...data.removed);
    cursor = data.next_cursor;
    hasMore = data.has_more;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const transaction of [...added, ...modified]) {
      await client.query(
        `INSERT INTO plaid_transactions (transaction_id, user_id, item_id, transaction_json, pending, transaction_date, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, now())
         ON CONFLICT (transaction_id) DO UPDATE SET transaction_json = EXCLUDED.transaction_json, pending = EXCLUDED.pending,
         transaction_date = EXCLUDED.transaction_date, updated_at = now()`,
        [transaction.transaction_id, item.user_id, item.item_id, transaction, transaction.pending, transaction.date],
      );
    }
    for (const transaction of removed) await client.query("DELETE FROM plaid_transactions WHERE transaction_id = $1 AND user_id = $2", [transaction.transaction_id, item.user_id]);
    await client.query("UPDATE plaid_items SET cursor = $1, updated_at = now(), error_code = NULL WHERE item_id = $2", [cursor, item.item_id]);
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

function total(values) {
  return values.reduce((sum, value) => sum + (Number(value) || 0), 0);
}

async function liveSummaryForItem(item) {
  const accessToken = decrypt(item.access_token_encrypted);
  const summary = { cash: 0, investments: null, liabilities: null, balanceAvailable: false, investmentsAvailable: false, liabilitiesAvailable: false };

  try {
    const data = await plaid("/accounts/balance/get", { access_token: accessToken });
    summary.cash = total(data.accounts
      .filter((account) => account.type === "depository")
      .map((account) => account.balances?.current ?? account.balances?.available));
    summary.balanceAvailable = true;
  } catch (error) {
    console.error("Balance lookup failed", error.plaid || error.message);
  }

  if (!config.portfolioProductsEnabled) return summary;

  try {
    const data = await plaid("/investments/holdings/get", { access_token: accessToken });
    summary.investments = total(data.holdings.map((holding) => holding.institution_value));
    summary.investmentsAvailable = true;
  } catch (error) {
    // A connected checking account often has no investment data. This is not
    // an error the person needs to see unless they connect a brokerage account.
    console.error("Investments lookup unavailable", error.plaid || error.message);
  }

  try {
    const data = await plaid("/liabilities/get", { access_token: accessToken });
    const liabilities = data.liabilities || {};
    const IDs = new Set([
      ...(liabilities.credit || []),
      ...(liabilities.mortgage || []),
      ...(liabilities.student || []),
    ].map((liability) => liability.account_id));
    summary.liabilities = total(data.accounts
      .filter((account) => IDs.has(account.account_id))
      .map((account) => account.balances?.current));
    summary.liabilitiesAvailable = true;
  } catch (error) {
    console.error("Liabilities lookup unavailable", error.plaid || error.message);
  }

  return summary;
}

app.get("/health", async (_request, response) => {
  await pool.query("SELECT 1");
  response.json({ status: "ok", plaid_environment: config.plaidEnvironment });
});

app.post("/api/auth/apple", async (request, response) => {
  const identityToken = request.body.identity_token;
  if (!identityToken) return response.status(400).json({ error: "Missing Apple identity token." });
  const { payload } = await jwtVerify(identityToken, appleKeys, { issuer: "https://appleid.apple.com", audience: config.appBundleID });
  const result = await pool.query(
    `INSERT INTO users (apple_subject, email) VALUES ($1, $2)
     ON CONFLICT (apple_subject) DO UPDATE SET email = COALESCE(EXCLUDED.email, users.email), updated_at = now() RETURNING id`,
    [payload.sub, payload.email || null],
  );
  response.json({ session_token: await issueSession(result.rows[0].id) });
});

app.post("/api/auth/development", async (_request, response) => {
  if (!config.allowDevelopmentLogin || config.plaidEnvironment === "production") return response.sendStatus(404);
  const result = await pool.query(
    `INSERT INTO users (apple_subject, email) VALUES ('development-user', 'developer@localhost')
     ON CONFLICT (apple_subject) DO UPDATE SET updated_at = now() RETURNING id`,
  );
  response.json({ session_token: await issueSession(result.rows[0].id) });
});

const plaidConsentType = "plaid_data_connection";
const privacyPolicyVersion = "2026-11-15";

app.post("/api/consents/plaid", requireUser, async (request, response) => {
  if (request.body.policy_version !== privacyPolicyVersion) {
    return response.status(400).json({ error: "Please review the current privacy notice before connecting a bank." });
  }
  await pool.query(
    `INSERT INTO consent_records (user_id, consent_type, policy_version)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, consent_type, policy_version) DO NOTHING`,
    [request.userID, plaidConsentType, privacyPolicyVersion],
  );
  response.json({ consented: true, policy_version: privacyPolicyVersion });
});

app.post("/api/create-link-token", requireUser, async (request, response) => {
  const consent = await pool.query(
    "SELECT 1 FROM consent_records WHERE user_id = $1 AND consent_type = $2 AND policy_version = $3",
    [request.userID, plaidConsentType, privacyPolicyVersion],
  );
  if (!consent.rowCount) {
    return response.status(403).json({ error: "Review and agree to the privacy notice before connecting a bank." });
  }
  const body = { user: { client_user_id: request.userID }, client_name: "Turtle Budgeting", products: ["transactions"], country_codes: ["US"], language: "en" };
  if (config.portfolioProductsEnabled) body.additional_consented_products = ["investments", "liabilities"];
  if (config.redirectURI) body.redirect_uri = config.redirectURI;
  if (config.webhookURL) body.webhook = config.webhookURL;
  const data = await plaid("/link/token/create", body);
  response.json({ link_token: data.link_token });
});

app.post("/api/exchange-public-token", requireUser, async (request, response) => {
  if (!request.body.public_token) return response.status(400).json({ error: "Missing public token." });
  const data = await plaid("/item/public_token/exchange", { public_token: request.body.public_token });
  let institutionName = null;
  try {
    const item = await plaid("/item/get", { access_token: data.access_token });
    if (item.item?.institution_id) {
      const institution = await plaid("/institutions/get_by_id", { institution_id: item.item.institution_id, country_codes: ["US"] });
      institutionName = institution.institution?.name || null;
    }
  } catch (error) {
    console.error("Institution name lookup unavailable", error.plaid || error.message);
  }

  const saved = await pool.query(
    `INSERT INTO plaid_items (item_id, user_id, access_token_encrypted, institution_name) VALUES ($1, $2, $3, $4)
     ON CONFLICT (item_id) DO UPDATE SET access_token_encrypted = EXCLUDED.access_token_encrypted,
     institution_name = COALESCE(EXCLUDED.institution_name, plaid_items.institution_name), updated_at = now()
     WHERE plaid_items.user_id = EXCLUDED.user_id RETURNING item_id`,
    [data.item_id, request.userID, encrypt(data.access_token), institutionName],
  );
  if (!saved.rowCount) {
    try { await plaid("/item/remove", { access_token: data.access_token }); } catch { /* Best-effort cleanup. */ }
    return response.status(409).json({ error: "This bank connection belongs to another Turtle Budgeting account." });
  }
  await pool.query("DELETE FROM live_balance_cache WHERE user_id = $1", [request.userID]);
  response.json({ connected: true, item_id: data.item_id });
});

app.get("/api/connections", requireUser, async (request, response) => {
  const result = await pool.query("SELECT item_id, institution_name, error_code, created_at, updated_at FROM plaid_items WHERE user_id = $1 ORDER BY created_at", [request.userID]);
  response.json({
    connections: result.rows.map((item) => ({
      itemID: item.item_id,
      institutionName: item.institution_name,
      errorCode: item.error_code,
      updatedAt: item.updated_at,
    })),
  });
});

app.get("/api/live-summary", requireUser, async (request, response) => {
  const userTimeZone = request.get("X-User-Time-Zone") || "UTC";
  const cached = await pool.query(
    "SELECT summary_json, retrieved_at, user_timezone FROM live_balance_cache WHERE user_id = $1",
    [request.userID],
  );
  const cacheTimeZone = cached.rows[0]?.user_timezone || userTimeZone;
  if (cached.rowCount && calendarDateKey(new Date(cached.rows[0].retrieved_at), cacheTimeZone) === calendarDateKey(new Date(), cacheTimeZone)) {
    return response.json(cached.rows[0].summary_json);
  }

  const items = await pool.query("SELECT * FROM plaid_items WHERE user_id = $1", [request.userID]);
  if (!items.rowCount) return response.status(409).json({ error: "Connect a bank first." });
  const summaries = await Promise.all(items.rows.map(liveSummaryForItem));
  const summary = {
    cash_total: total(summaries.map((summary) => summary.cash)),
    investments_total: summaries.some((summary) => summary.investmentsAvailable) ? total(summaries.map((summary) => summary.investments)) : null,
    liabilities_total: summaries.some((summary) => summary.liabilitiesAvailable) ? total(summaries.map((summary) => summary.liabilities)) : null,
    balance_available: summaries.some((summary) => summary.balanceAvailable),
    investments_available: summaries.some((summary) => summary.investmentsAvailable),
    liabilities_available: summaries.some((summary) => summary.liabilitiesAvailable),
    portfolio_products_enabled: config.portfolioProductsEnabled,
    retrieved_at: new Date().toISOString(),
  };
  if (summary.balance_available) {
    await pool.query(
      `INSERT INTO live_balance_cache (user_id, summary_json, retrieved_at, user_timezone) VALUES ($1, $2, now(), $3)
       ON CONFLICT (user_id) DO UPDATE SET summary_json = EXCLUDED.summary_json, retrieved_at = now(), user_timezone = EXCLUDED.user_timezone`,
      [request.userID, summary, userTimeZone],
    );
  }
  response.json(summary);
});

app.get("/api/live-summary-status", requireUser, async (request, response) => {
  const cached = await pool.query(
    "SELECT summary_json, retrieved_at, user_timezone FROM live_balance_cache WHERE user_id = $1",
    [request.userID],
  );
  if (!cached.rowCount) return response.sendStatus(204);
  const cacheTimeZone = cached.rows[0].user_timezone || "UTC";
  if (calendarDateKey(new Date(cached.rows[0].retrieved_at), cacheTimeZone) !== calendarDateKey(new Date(), cacheTimeZone)) {
    return response.sendStatus(204);
  }
  response.json(cached.rows[0].summary_json);
});

app.post("/api/transactions-sync", requireUser, async (request, response) => {
  const items = await pool.query("SELECT * FROM plaid_items WHERE user_id = $1", [request.userID]);
  if (!items.rowCount) return response.status(409).json({ error: "Connect a bank first." });
  for (const item of items.rows) await syncItem(item);
  const transactions = await pool.query("SELECT transaction_json FROM plaid_transactions WHERE user_id = $1 ORDER BY transaction_date DESC, updated_at DESC LIMIT 1000", [request.userID]);
  response.json({ added: transactions.rows.map((row) => row.transaction_json), modified: [], removed: [] });
});

app.delete("/api/connections/:itemID", requireUser, async (request, response) => {
  const result = await pool.query("SELECT * FROM plaid_items WHERE item_id = $1 AND user_id = $2", [request.params.itemID, request.userID]);
  if (!result.rowCount) return response.sendStatus(404);
  await plaid("/item/remove", { access_token: decrypt(result.rows[0].access_token_encrypted) });
  await pool.query("DELETE FROM plaid_items WHERE item_id = $1 AND user_id = $2", [request.params.itemID, request.userID]);
  await pool.query("DELETE FROM live_balance_cache WHERE user_id = $1", [request.userID]);
  response.sendStatus(204);
});

app.delete("/api/account", requireUser, async (request, response) => {
  const items = await pool.query("SELECT access_token_encrypted FROM plaid_items WHERE user_id = $1", [request.userID]);
  for (const item of items.rows) {
    try { await plaid("/item/remove", { access_token: decrypt(item.access_token_encrypted) }); }
    catch (error) { console.error("Plaid item removal failed during account deletion", error.plaid || error.message); }
  }
  await pool.query("DELETE FROM users WHERE id = $1", [request.userID]);
  response.sendStatus(204);
});

app.post("/api/plaid/webhook", async (request, response) => {
  try {
    if (!await verifyPlaidWebhook(request)) return response.status(401).json({ error: "Invalid Plaid webhook signature." });
  } catch (verificationError) {
    console.error("Webhook verification failed", verificationError.plaid || verificationError.message);
    return response.status(401).json({ error: "Invalid Plaid webhook signature." });
  }
  response.sendStatus(200);
  const { webhook_type: type, webhook_code: code, item_id: itemID, error } = request.body;
  try {
    const result = await pool.query("SELECT * FROM plaid_items WHERE item_id = $1", [itemID]);
    if (!result.rowCount) return;
    if (type === "TRANSACTIONS" && code === "SYNC_UPDATES_AVAILABLE") await syncItem(result.rows[0]);
    if (type === "ITEM" && error?.error_code) await pool.query("UPDATE plaid_items SET error_code = $1, updated_at = now() WHERE item_id = $2", [error.error_code, itemID]);
  } catch (webhookError) {
    console.error("Webhook processing failed", webhookError.plaid || webhookError.message);
  }
});

app.use((error, _request, response, _next) => {
  console.error(error.plaid || error);
  response.status(error.status || 500).json({ error: error.message || "Unexpected server error.", plaid: error.plaid });
});

await pool.query(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));
app.listen(config.port, "0.0.0.0", () => console.log(`BudgetBuddy API listening on port ${config.port} (${config.plaidEnvironment})`));
