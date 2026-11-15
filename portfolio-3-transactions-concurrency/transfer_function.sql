-- =====================================================================
-- OpeLat Wallet: safe wallet-to-wallet transfer (Portfolio 3)
-- One call = one atomic unit of work. If any check fails, an exception is raised
-- and NOTHING is written (no transaction row, no ledger lines, no balance change).
-- =====================================================================
SET search_path TO olw;

CREATE OR REPLACE FUNCTION transfer_funds(
    p_from      BIGINT,
    p_to        BIGINT,
    p_amount    NUMERIC(18,2),
    p_channel   VARCHAR DEFAULT 'app',
    p_narration VARCHAR DEFAULT 'Transfer'
) RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = olw          -- pin the schema: works from any session, and cannot be hijacked by a
                              -- table of the same name in another schema
AS $$
DECLARE
    v_fee      NUMERIC(18,2) := CASE WHEN p_amount > 5000 THEN 10 ELSE 0 END;
    v_from     wallets%ROWTYPE;
    v_to       wallets%ROWTYPE;
    v_sent     NUMERIC(18,2);
    v_txn      BIGINT;
BEGIN
    IF p_from = p_to THEN
        RAISE EXCEPTION 'cannot transfer to the same wallet';
    END IF;

    -- 1. Lock BOTH wallets, always in wallet_id order. Every session takes the locks in the
    --    same order, so two opposite transfers (A->B and B->A) can never deadlock.
    PERFORM 1 FROM wallets WHERE wallet_id IN (p_from, p_to) ORDER BY wallet_id FOR UPDATE;
    SELECT * INTO v_from FROM wallets WHERE wallet_id = p_from;
    SELECT * INTO v_to   FROM wallets WHERE wallet_id = p_to;

    -- 2. Business checks, made AFTER locking so nobody can change the balance in between
    IF v_from.wallet_id IS NULL OR v_to.wallet_id IS NULL THEN
        RAISE EXCEPTION 'wallet not found';
    END IF;
    IF v_from.status <> 'active' OR v_to.status <> 'active' THEN
        RAISE EXCEPTION 'wallet is not active';
    END IF;
    IF v_from.balance < p_amount + v_fee THEN
        RAISE EXCEPTION 'insufficient funds: balance %, needed %', v_from.balance, p_amount + v_fee
              USING ERRCODE = 'P0001';
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO v_sent
    FROM transactions
    WHERE source_wallet_id = p_from AND status = 'successful'
      AND created_at >= date_trunc('day', now());
    IF v_sent + p_amount > v_from.daily_limit THEN
        RAISE EXCEPTION 'daily limit exceeded: limit %, already sent %', v_from.daily_limit, v_sent;
    END IF;

    -- 3. Write the transaction, the double-entry ledger lines and the new balances
    INSERT INTO transactions (txn_type, status, channel, amount, fee, source_wallet_id, dest_wallet_id,
                              narration, completed_at)
    VALUES ('transfer', 'successful', p_channel, p_amount, v_fee, p_from, p_to, p_narration, clock_timestamp())
    RETURNING txn_id INTO v_txn;

    UPDATE wallets SET balance = balance - (p_amount + v_fee) WHERE wallet_id = p_from;
    UPDATE wallets SET balance = balance + p_amount           WHERE wallet_id = p_to;

    INSERT INTO ledger_entries (txn_id, wallet_id, direction, amount, balance_after)
    VALUES (v_txn, p_from, 'D', p_amount + v_fee, v_from.balance - (p_amount + v_fee)),
           (v_txn, p_to,   'C', p_amount,         v_to.balance + p_amount);

    IF v_fee > 0 THEN
        UPDATE wallets SET balance = balance + v_fee WHERE wallet_id = 2;      -- fee income wallet
        INSERT INTO ledger_entries (txn_id, wallet_id, direction, amount, balance_after)
        SELECT v_txn, 2, 'C', v_fee, balance FROM wallets WHERE wallet_id = 2;
    END IF;

    RETURN v_txn;
END $$;

-- ---------- Five demo customers with known balances (used by the demos) ----------
-- Phones +2348099900001..5. Re-running this file resets them.
CREATE TEMP TABLE demo_txns AS
SELECT t.txn_id FROM transactions t
WHERE t.source_wallet_id IN (SELECT w.wallet_id FROM wallets w JOIN customers c USING (customer_id) WHERE c.phone LIKE '+23480999000%')
   OR t.dest_wallet_id   IN (SELECT w.wallet_id FROM wallets w JOIN customers c USING (customer_id) WHERE c.phone LIKE '+23480999000%');
-- remove the fee income these demo transfers created, then their ledger lines, then the rest
UPDATE wallets SET balance = balance - COALESCE((SELECT sum(amount) FROM ledger_entries
       WHERE wallet_id = 2 AND txn_id IN (SELECT txn_id FROM demo_txns)), 0) WHERE wallet_id = 2;
UPDATE wallets SET balance = balance + COALESCE((SELECT sum(amount) FROM ledger_entries
       WHERE wallet_id = 1 AND direction = 'D' AND txn_id IN (SELECT txn_id FROM demo_txns)), 0) WHERE wallet_id = 1;
DELETE FROM ledger_entries WHERE txn_id IN (SELECT txn_id FROM demo_txns);
DELETE FROM transactions   WHERE txn_id IN (SELECT txn_id FROM demo_txns);
DELETE FROM wallets   WHERE customer_id IN (SELECT customer_id FROM customers WHERE phone LIKE '+23480999000%');
DELETE FROM customers WHERE phone LIKE '+23480999000%';
DROP TABLE demo_txns;

INSERT INTO customers (phone, first_name, last_name, date_of_birth, state, kyc_tier)
VALUES ('+2348099900001', 'Ada',    'Demo', '1990-01-01', 'Lagos', 3),
       ('+2348099900002', 'Tunde',  'Demo', '1990-01-01', 'Lagos', 3),
       ('+2348099900003', 'Musa',   'Demo', '1990-01-01', 'Kano',  3),
       ('+2348099900004', 'Ngozi',  'Demo', '1990-01-01', 'Enugu', 3),
       ('+2348099900005', 'Halima', 'Demo', '1990-01-01', 'Abuja FCT', 3);

INSERT INTO wallets (wallet_type, customer_id, balance, daily_limit)
SELECT 'customer', customer_id, 10000, 5000000 FROM customers WHERE phone LIKE '+23480999000%';

-- Opening deposits so the ledger matches the starting balances
WITH t AS (
  INSERT INTO transactions (txn_type, status, channel, amount, dest_wallet_id, narration, completed_at)
  SELECT 'deposit', 'successful', 'app', 10000, w.wallet_id, 'Demo opening deposit', now()
  FROM wallets w JOIN customers c USING (customer_id) WHERE c.phone LIKE '+23480999000%'
  RETURNING txn_id, dest_wallet_id
)
INSERT INTO ledger_entries (txn_id, wallet_id, direction, amount, balance_after)
SELECT txn_id, 1, 'D', 10000, 0 FROM t
UNION ALL
SELECT txn_id, dest_wallet_id, 'C', 10000, 10000 FROM t;
UPDATE wallets SET balance = balance - 50000 WHERE wallet_id = 1;   -- the bank settlement side of the 5 deposits

CREATE OR REPLACE VIEW demo_wallets AS
SELECT c.first_name AS customer, w.wallet_id, w.balance
FROM wallets w JOIN customers c USING (customer_id)
WHERE c.phone LIKE '+23480999000%'
ORDER BY w.wallet_id;
