-- MoniWallet relational schema (Portfolio 1)
-- Run with: psql moniwallet -f portfolio-1-database-design/schema.sql
-- All data in this project is made up.

BEGIN;

DROP TABLE IF EXISTS audit_log, ledger_entry, transaction, session, device,
    wallet, agent, biller, kyc_record, customer CASCADE;

-- A person who owns a wallet.
CREATE TABLE customer (
    customer_id   BIGSERIAL PRIMARY KEY,
    full_name     VARCHAR(120) NOT NULL,
    phone_number  VARCHAR(15)  NOT NULL UNIQUE,
    email         VARCHAR(120) UNIQUE,
    date_of_birth DATE         NOT NULL,
    status        VARCHAR(12)  NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'suspended', 'closed')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (phone_number ~ '^\+?[0-9]{10,14}$')
);

-- KYC (identity check) records. One customer can have more than one over time.
CREATE TABLE kyc_record (
    kyc_id       BIGSERIAL PRIMARY KEY,
    customer_id  BIGINT       NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    id_type      VARCHAR(20)  NOT NULL
                 CHECK (id_type IN ('NIN', 'BVN', 'passport', 'drivers_licence')),
    id_number    VARCHAR(30)  NOT NULL,
    kyc_level    SMALLINT     NOT NULL CHECK (kyc_level BETWEEN 1 AND 3),
    verified_at  TIMESTAMPTZ,
    UNIQUE (id_type, id_number)
);

-- A wallet holds money. The balance can never be negative.
CREATE TABLE wallet (
    wallet_id    BIGSERIAL PRIMARY KEY,
    customer_id  BIGINT        NOT NULL REFERENCES customer(customer_id) ON DELETE RESTRICT,
    currency     CHAR(3)       NOT NULL DEFAULT 'NGN',
    balance      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    status       VARCHAR(10)   NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active', 'frozen', 'closed')),
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (customer_id, currency)
);

-- Cash-in and cash-out points.
CREATE TABLE agent (
    agent_id     BIGSERIAL PRIMARY KEY,
    agent_name   VARCHAR(120) NOT NULL,
    phone_number VARCHAR(15)  NOT NULL UNIQUE,
    location     VARCHAR(120) NOT NULL,
    status       VARCHAR(10)  NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active', 'suspended'))
);

-- Companies that receive bill payments (electricity, TV, airtime).
CREATE TABLE biller (
    biller_id    BIGSERIAL PRIMARY KEY,
    biller_name  VARCHAR(80) NOT NULL UNIQUE,
    category     VARCHAR(20) NOT NULL
                 CHECK (category IN ('electricity', 'tv', 'airtime', 'data', 'water'))
);

-- Every money movement. Which side is used depends on the type.
CREATE TABLE transaction (
    transaction_id   BIGSERIAL PRIMARY KEY,
    type             VARCHAR(15)   NOT NULL
                     CHECK (type IN ('transfer', 'deposit', 'withdrawal', 'bill_payment', 'reversal')),
    from_wallet_id   BIGINT REFERENCES wallet(wallet_id) ON DELETE RESTRICT,
    to_wallet_id     BIGINT REFERENCES wallet(wallet_id) ON DELETE RESTRICT,
    agent_id         BIGINT REFERENCES agent(agent_id)   ON DELETE SET NULL,
    biller_id        BIGINT REFERENCES biller(biller_id) ON DELETE SET NULL,
    reverses_id      BIGINT REFERENCES transaction(transaction_id) ON DELETE RESTRICT,
    amount           NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status           VARCHAR(10)   NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'success', 'failed', 'reversed')),
    flagged          BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- A transfer must have two different wallets.
    CHECK (type <> 'transfer' OR (from_wallet_id IS NOT NULL
                                  AND to_wallet_id IS NOT NULL
                                  AND from_wallet_id <> to_wallet_id)),
    -- At least one wallet must be involved.
    CHECK (from_wallet_id IS NOT NULL OR to_wallet_id IS NOT NULL),
    -- Only a reversal points to another transaction.
    CHECK ((type = 'reversal') = (reverses_id IS NOT NULL))
);

-- Double-entry ledger: each transaction has a debit and a credit line.
CREATE TABLE ledger_entry (
    entry_id        BIGSERIAL PRIMARY KEY,
    transaction_id  BIGINT        NOT NULL REFERENCES transaction(transaction_id) ON DELETE RESTRICT,
    wallet_id       BIGINT        NOT NULL REFERENCES wallet(wallet_id) ON DELETE RESTRICT,
    direction       CHAR(1)       NOT NULL CHECK (direction IN ('D', 'C')),
    amount          NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    balance_after   NUMERIC(14,2) NOT NULL CHECK (balance_after >= 0),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (transaction_id, wallet_id, direction)
);

-- Phones and other devices a customer logs in from.
CREATE TABLE device (
    device_id    BIGSERIAL PRIMARY KEY,
    customer_id  BIGINT       NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    device_model VARCHAR(80)  NOT NULL,
    os           VARCHAR(30)  NOT NULL,
    trusted      BOOLEAN      NOT NULL DEFAULT FALSE,
    first_seen   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Login sessions (mobile app or USSD).
CREATE TABLE session (
    session_id   BIGSERIAL PRIMARY KEY,
    customer_id  BIGINT       NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    device_id    BIGINT       REFERENCES device(device_id) ON DELETE SET NULL,
    channel      VARCHAR(10)  NOT NULL CHECK (channel IN ('app', 'ussd')),
    started_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    ended_at     TIMESTAMPTZ,
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- Who did what, for auditors. Rows are kept even if the actor is removed.
CREATE TABLE audit_log (
    audit_id     BIGSERIAL PRIMARY KEY,
    customer_id  BIGINT       REFERENCES customer(customer_id) ON DELETE SET NULL,
    action       VARCHAR(40)  NOT NULL,
    table_name   VARCHAR(40)  NOT NULL,
    record_id    BIGINT,
    details      TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMIT;
