-- =====================================================================
-- OpeLat Wallet relational schema (PostgreSQL 14)
-- Portfolio 1: Database Design and Modelling
-- Run: psql opelatwallet -f portfolio-1-database-design/schema.sql
-- =====================================================================

DROP SCHEMA IF EXISTS olw CASCADE;
CREATE SCHEMA olw;
SET search_path TO olw;

-- ---------- Staff who review KYC, AML flags and reconciliations ----------
CREATE TABLE staff (
    staff_id     SERIAL PRIMARY KEY,
    full_name    VARCHAR(120) NOT NULL,
    email        VARCHAR(160) NOT NULL UNIQUE,
    role         VARCHAR(20)  NOT NULL
                 CHECK (role IN ('support', 'compliance', 'finance', 'auditor')),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------- Customers (one row per person) ----------
CREATE TABLE customers (
    customer_id    BIGSERIAL PRIMARY KEY,
    phone          VARCHAR(14)  NOT NULL UNIQUE
                   CHECK (phone ~ '^\+234[789][01][0-9]{8}$'),      -- Nigerian mobile format
    first_name     VARCHAR(60)  NOT NULL,
    last_name      VARCHAR(60)  NOT NULL,
    date_of_birth  DATE         NOT NULL
                   CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years'),
    bvn            CHAR(11)     UNIQUE CHECK (bvn ~ '^[0-9]{11}$'), -- made-up values only
    email          VARCHAR(160) UNIQUE,
    state          VARCHAR(30)  NOT NULL,
    kyc_tier       SMALLINT     NOT NULL DEFAULT 1 CHECK (kyc_tier BETWEEN 1 AND 3),
    status         VARCHAR(12)  NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active', 'suspended', 'closed')),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------- KYC documents (a customer can have many) ----------
CREATE TABLE kyc_documents (
    document_id    BIGSERIAL PRIMARY KEY,
    customer_id    BIGINT      NOT NULL REFERENCES customers (customer_id) ON DELETE CASCADE,
    doc_type       VARCHAR(20) NOT NULL
                   CHECK (doc_type IN ('nin', 'voters_card', 'passport', 'drivers_licence', 'utility_bill')),
    doc_number     VARCHAR(30) NOT NULL,
    verified_by    INT         REFERENCES staff (staff_id) ON DELETE SET NULL,
    verified_at    TIMESTAMPTZ,
    UNIQUE (doc_type, doc_number),
    CHECK ((verified_by IS NULL) = (verified_at IS NULL))      -- both set or both empty
);

-- ---------- Wallets: customer, agent float, or internal system wallets ----------
CREATE TABLE wallets (
    wallet_id      BIGSERIAL PRIMARY KEY,
    wallet_type    VARCHAR(10)   NOT NULL CHECK (wallet_type IN ('customer', 'agent', 'system')),
    customer_id    BIGINT        REFERENCES customers (customer_id) ON DELETE RESTRICT,
    label          VARCHAR(60),                                  -- name of a system wallet
    currency       CHAR(3)       NOT NULL DEFAULT 'NGN',
    balance        NUMERIC(18,2) NOT NULL DEFAULT 0,
    daily_limit    NUMERIC(18,2) NOT NULL DEFAULT 50000 CHECK (daily_limit > 0),
    status         VARCHAR(10)   NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active', 'frozen', 'closed')),
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- customer wallets must belong to a customer; system wallets must not
    CHECK ((wallet_type = 'customer') = (customer_id IS NOT NULL)),
    -- only internal settlement wallets may go below zero
    CHECK (balance >= 0 OR wallet_type = 'system'),
    UNIQUE (customer_id, currency)
);

-- ---------- Agents (cash-in / cash-out points) ----------
CREATE TABLE agents (
    agent_id       SERIAL PRIMARY KEY,
    business_name  VARCHAR(120) NOT NULL,
    phone          VARCHAR(14)  NOT NULL UNIQUE,
    state          VARCHAR(30)  NOT NULL,
    lga            VARCHAR(60)  NOT NULL,
    wallet_id      BIGINT       NOT NULL UNIQUE REFERENCES wallets (wallet_id),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------- Billers (electricity, TV, airtime, ...) ----------
CREATE TABLE billers (
    biller_id      SERIAL PRIMARY KEY,
    name           VARCHAR(80) NOT NULL UNIQUE,
    category       VARCHAR(12) NOT NULL
                   CHECK (category IN ('electricity', 'tv', 'airtime', 'data', 'water', 'internet'))
);

-- ---------- Transactions (one row per business event) ----------
CREATE TABLE transactions (
    txn_id           BIGSERIAL PRIMARY KEY,
    reference        UUID          NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    txn_type         VARCHAR(12)   NOT NULL
                     CHECK (txn_type IN ('deposit', 'withdrawal', 'transfer', 'bill_payment', 'reversal')),
    status           VARCHAR(10)   NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'successful', 'failed', 'reversed')),
    channel          VARCHAR(6)    NOT NULL CHECK (channel IN ('app', 'ussd', 'agent')),
    amount           NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    fee              NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (fee >= 0),
    source_wallet_id BIGINT        REFERENCES wallets (wallet_id),
    dest_wallet_id   BIGINT        REFERENCES wallets (wallet_id),
    biller_id        INT           REFERENCES billers (biller_id),
    agent_id         INT           REFERENCES agents (agent_id),
    reversal_of      BIGINT        REFERENCES transactions (txn_id),
    narration        VARCHAR(140),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    completed_at     TIMESTAMPTZ,
    -- shape rules for each transaction type
    CHECK (txn_type <> 'transfer'     OR (source_wallet_id IS NOT NULL AND dest_wallet_id IS NOT NULL
                                          AND source_wallet_id <> dest_wallet_id)),
    CHECK (txn_type <> 'bill_payment' OR (source_wallet_id IS NOT NULL AND biller_id IS NOT NULL)),
    CHECK (txn_type <> 'deposit'      OR dest_wallet_id IS NOT NULL),
    CHECK (txn_type <> 'withdrawal'   OR source_wallet_id IS NOT NULL),
    CHECK (txn_type <> 'reversal'     OR reversal_of IS NOT NULL),
    CHECK (completed_at IS NULL OR completed_at >= created_at)
);

-- ---------- Double-entry ledger: every money movement is a debit and a credit ----------
CREATE TABLE ledger_entries (
    entry_id       BIGSERIAL PRIMARY KEY,
    txn_id         BIGINT        NOT NULL REFERENCES transactions (txn_id),
    wallet_id      BIGINT        NOT NULL REFERENCES wallets (wallet_id),
    direction      CHAR(1)       NOT NULL CHECK (direction IN ('D', 'C')),
    amount         NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    balance_after  NUMERIC(18,2) NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------- Anti-money-laundering flags ----------
CREATE TABLE aml_flags (
    flag_id        BIGSERIAL PRIMARY KEY,
    txn_id         BIGINT       NOT NULL REFERENCES transactions (txn_id),
    rule_code      VARCHAR(20)  NOT NULL,      -- e.g. VELOCITY_1H, STRUCTURING, NEW_DEVICE_HIGH_VALUE
    risk_score     SMALLINT     NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    status         VARCHAR(12)  NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open', 'cleared', 'escalated')),
    reviewed_by    INT          REFERENCES staff (staff_id),
    reviewed_at    TIMESTAMPTZ,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (txn_id, rule_code)
);

-- ---------- Audit log (who changed what) ----------
CREATE TABLE audit_log (
    audit_id       BIGSERIAL PRIMARY KEY,
    actor          VARCHAR(60) NOT NULL,
    action         VARCHAR(30) NOT NULL,
    table_name     VARCHAR(40) NOT NULL,
    record_id      BIGINT,
    details        JSONB,
    logged_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- Foreign-key indexes (PostgreSQL does not create these automatically) ----------
CREATE INDEX ix_kyc_customer      ON kyc_documents (customer_id);
CREATE INDEX ix_ledger_txn        ON ledger_entries (txn_id);
CREATE INDEX ix_aml_txn           ON aml_flags (txn_id);

-- ---------- Audit trigger: any change to a wallet's status is logged ----------
CREATE FUNCTION log_wallet_status() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO audit_log (actor, action, table_name, record_id, details)
        VALUES (current_user, 'wallet_status_change', 'wallets', NEW.wallet_id,
                jsonb_build_object('from', OLD.status, 'to', NEW.status));
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_wallet_status
AFTER UPDATE OF status ON wallets
FOR EACH ROW EXECUTE FUNCTION log_wallet_status();

-- ---------- Integrity view: every transaction's debits must equal its credits ----------
CREATE VIEW v_unbalanced_transactions AS
SELECT txn_id,
       SUM(amount) FILTER (WHERE direction = 'D') AS total_debits,
       SUM(amount) FILTER (WHERE direction = 'C') AS total_credits
FROM ledger_entries
GROUP BY txn_id
HAVING SUM(amount) FILTER (WHERE direction = 'D')
    IS DISTINCT FROM SUM(amount) FILTER (WHERE direction = 'C');
