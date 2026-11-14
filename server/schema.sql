CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_subject text UNIQUE NOT NULL,
    email text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS plaid_items (
    item_id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    access_token_encrypted text NOT NULL,
    cursor text,
    institution_name text,
    error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS plaid_items_user_id_idx ON plaid_items(user_id);

CREATE TABLE IF NOT EXISTS plaid_transactions (
    transaction_id text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    item_id text NOT NULL REFERENCES plaid_items(item_id) ON DELETE CASCADE,
    transaction_json jsonb NOT NULL,
    pending boolean NOT NULL DEFAULT false,
    transaction_date date NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS plaid_transactions_user_date_idx ON plaid_transactions(user_id, transaction_date DESC);
