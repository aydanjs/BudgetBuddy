import http from "node:http";

const required = ["PLAID_CLIENT_ID", "PLAID_SECRET"];
const missing = required.filter((name) => !process.env[name] || process.env[name].startsWith("PASTE_"));
if (missing.length) {
  console.error(`Missing ${missing.join(", ")} in server/.env`);
  process.exit(1);
}

const port = Number(process.env.PORT || 8080);
const plaidBaseURL = process.env.PLAID_ENV === "production"
  ? "https://production.plaid.com"
  : process.env.PLAID_ENV === "development"
    ? "https://development.plaid.com"
    : "https://sandbox.plaid.com";

let accessToken = null;
let cursor = null;

async function plaid(path, body) {
  const response = await fetch(`${plaidBaseURL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: process.env.PLAID_CLIENT_ID,
      secret: process.env.PLAID_SECRET,
      ...body,
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_message || "Plaid request failed");
  return data;
}

function send(response, status, data) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(data));
}

async function readJSON(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

const server = http.createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") {
      return send(response, 200, { status: "ok", environment: process.env.PLAID_ENV || "sandbox" });
    }

    if (request.method === "POST" && request.url === "/api/create-link-token") {
      const data = await plaid("/link/token/create", {
        user: { client_user_id: "budgetbuddy-local-user" },
        client_name: "BudgetBuddy",
        products: ["transactions"],
        country_codes: ["US"],
        language: "en",
      });
      return send(response, 200, { link_token: data.link_token });
    }

    if (request.method === "POST" && request.url === "/api/exchange-public-token") {
      const body = await readJSON(request);
      const data = await plaid("/item/public_token/exchange", { public_token: body.public_token });
      accessToken = data.access_token;
      cursor = null;
      return send(response, 200, { connected: true, item_id: data.item_id });
    }

    if (request.method === "POST" && request.url === "/api/transactions-sync") {
      if (!accessToken) return send(response, 409, { error: "Connect a Sandbox bank first." });
      const added = [];
      const modified = [];
      const removed = [];
      let hasMore = true;
      while (hasMore) {
        const data = await plaid("/transactions/sync", { access_token: accessToken, cursor });
        added.push(...data.added);
        modified.push(...data.modified);
        removed.push(...data.removed);
        cursor = data.next_cursor;
        hasMore = data.has_more;
      }
      return send(response, 200, { added, modified, removed, next_cursor: cursor });
    }

    send(response, 404, { error: "Not found" });
  } catch (error) {
    console.error(error);
    send(response, 500, { error: error.message });
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`BudgetBuddy Plaid Sandbox server: http://127.0.0.1:${port}`);
});
