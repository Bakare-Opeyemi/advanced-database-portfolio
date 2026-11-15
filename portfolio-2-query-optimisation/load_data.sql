-- =====================================================================
-- MoniWallet: load realistic made-up data (Portfolio 2)
-- 50,000 customers, 400 agents, ~450,000 transactions, ~950,000 ledger entries.
-- All names, phone numbers and BVNs are generated. No real person's data is used.
-- Run after schema.sql:  psql moniwallet -f portfolio-2-query-optimisation/load_data.sql
-- =====================================================================
SET search_path TO mw;
SELECT setseed(0.8103);                       -- same data every run

\echo 'Reference data: staff, billers, system wallets'
INSERT INTO staff (full_name, email, role)
SELECT 'Staff Member ' || g, 'staff' || g || '@moniwallet.example',
       (ARRAY['support','compliance','finance','auditor'])[1 + g % 4]
FROM generate_series(1, 24) g;

INSERT INTO billers (name, category) VALUES
 ('Ikeja Electric','electricity'), ('Eko Electricity','electricity'), ('Abuja Electricity','electricity'),
 ('Port Harcourt Electricity','electricity'), ('DStv','tv'), ('GOtv','tv'), ('StarTimes','tv'),
 ('MTN Airtime','airtime'), ('Airtel Airtime','airtime'), ('Glo Airtime','airtime'),
 ('MTN Data','data'), ('Airtel Data','data'), ('Lagos Water Corporation','water'),
 ('Spectranet','internet'), ('Smile','internet');

INSERT INTO wallets (wallet_type, label, created_at) VALUES
 ('system', 'Bank settlement',   '2025-01-01'),   -- wallet 1: money entering / leaving MoniWallet
 ('system', 'Fee income',        '2025-01-01'),   -- wallet 2: transfer fees
 ('system', 'Biller settlement', '2025-01-01');   -- wallet 3: owed to billers

\echo 'Customers and their wallets'
WITH names AS (
  SELECT ARRAY['Adaeze','Chinedu','Emeka','Ngozi','Tunde','Bola','Yusuf','Aisha','Ibrahim','Fatima',
               'Segun','Funke','Kelechi','Uche','Halima','Musa','Zainab','Olumide','Temitope','Chioma',
               'Ifeanyi','Amaka','Babatunde','Kemi','Sani','Hauwa','Obinna','Nkechi','Femi','Ruth'] AS f,
         ARRAY['Okafor','Adeyemi','Bello','Okonkwo','Abubakar','Eze','Ogunleye','Ibrahim','Nwosu','Lawal',
               'Adebayo','Mohammed','Obi','Balogun','Umar','Chukwu','Akinola','Danjuma','Okeke','Olaniyan',
               'Yakubu','Ezeh','Afolabi','Garba','Nnamdi','Oyelaran','Aliyu','Onyeka','Bakare','Usman'] AS l,
         ARRAY['Lagos','Lagos','Lagos','Abuja FCT','Rivers','Oyo','Kano','Kaduna','Ogun','Enugu','Delta',
               'Anambra','Edo','Kwara','Plateau'] AS st
)
INSERT INTO customers (phone, first_name, last_name, date_of_birth, bvn, email, state, kyc_tier, created_at)
SELECT '+234' || (ARRAY['80','81','70','90','91'])[1 + g % 5] || lpad(g::text, 8, '0'),
       f[1 + (random() * 29)::int], l[1 + (random() * 29)::int],
       DATE '1960-01-01' + (random() * 14600)::int,
       lpad((20000000000 + g)::text, 11, '0'),
       'customer' || g || '@mail.example',
       st[1 + (random() * 14)::int],
       (ARRAY[1,1,1,2,2,3])[1 + (random() * 5)::int],
       TIMESTAMPTZ '2025-01-01' + random() * INTERVAL '364 days'
FROM generate_series(1, 50000) g, names;

INSERT INTO wallets (wallet_type, customer_id, daily_limit, created_at)
SELECT 'customer', customer_id, (ARRAY[50000, 200000, 5000000])[kyc_tier], created_at
FROM customers;

INSERT INTO kyc_documents (customer_id, doc_type, doc_number, verified_by, verified_at)
SELECT customer_id, 'nin', lpad((30000000000 + customer_id)::text, 11, '0'),
       1 + (customer_id % 6) * 4, created_at + INTERVAL '2 hours'
FROM customers WHERE kyc_tier >= 2;

\echo 'Agents and their float wallets'
WITH w AS (
  INSERT INTO wallets (wallet_type, label, created_at)
  SELECT 'agent', 'Agent float ' || g, '2025-01-01' FROM generate_series(1, 400) g
  RETURNING wallet_id
)
INSERT INTO agents (business_name, phone, state, lga, wallet_id)
SELECT 'MoniPoint Agent ' || row_number() OVER (),
       '+23470' || lpad((90000000 + row_number() OVER ())::text, 8, '0'),
       (ARRAY['Lagos','Abuja FCT','Rivers','Oyo','Kano','Kaduna','Ogun','Enugu','Delta','Edo'])[1 + (wallet_id % 10)::int],
       'LGA ' || (1 + wallet_id % 20), wallet_id
FROM w;

-- ---------------------------------------------------------------------
-- Transactions. Built in a staging table, then inserted in time order
-- (like a real append-only system), so txn_id rises with created_at.
-- ---------------------------------------------------------------------
\echo 'Generating 400,000 activity transactions'
CREATE TEMP TABLE cw AS
SELECT row_number() OVER (ORDER BY wallet_id) AS n, wallet_id
FROM wallets WHERE wallet_type = 'customer';
CREATE TEMP TABLE aw AS
SELECT row_number() OVER (ORDER BY agent_id) AS n, agent_id, wallet_id FROM agents;
CREATE INDEX ON cw (n);
CREATE INDEX ON aw (n);
ANALYZE cw; ANALYZE aw;

CREATE TEMP TABLE stage AS
SELECT g,
       CASE WHEN r < 0.22 THEN 'deposit' WHEN r < 0.70 THEN 'transfer'
            WHEN r < 0.93 THEN 'bill_payment' ELSE 'withdrawal' END AS txn_type,
       TIMESTAMPTZ '2026-01-01' + random() * (TIMESTAMPTZ '2026-11-14' - TIMESTAMPTZ '2026-01-01') AS created_at,
       1 + (random() * 49999)::int AS a, 1 + (random() * 49999)::int AS b,
       1 + (random() * 399)::int AS ag, 1 + (random() * 14)::int AS bl,
       random() AS r2, random() AS r3, random() AS r4
FROM (SELECT g, random() AS r FROM generate_series(1, 400000) g) s;

INSERT INTO transactions (txn_type, status, channel, amount, fee, source_wallet_id, dest_wallet_id,
                          biller_id, agent_id, narration, created_at, completed_at)
SELECT s.txn_type,
       CASE WHEN s.created_at > TIMESTAMPTZ '2026-11-14' - INTERVAL '40 minutes' AND s.r3 < 0.30 THEN 'pending'
            WHEN s.r3 < 0.02 THEN 'failed' ELSE 'successful' END,
       CASE WHEN s.txn_type IN ('withdrawal') THEN 'agent'
            WHEN s.txn_type = 'deposit' AND s.r4 < 0.5 THEN 'agent'
            WHEN s.r4 < 0.65 THEN 'app' ELSE 'ussd' END,
       round((CASE s.txn_type WHEN 'transfer' THEN 500 + s.r2 ^ 3 * 250000
                              WHEN 'bill_payment' THEN 100 + s.r2 * 25000
                              WHEN 'deposit' THEN 1000 + s.r2 ^ 2 * 150000
                              ELSE 1000 + s.r2 * 40000 END)::numeric, -2),
       CASE WHEN s.txn_type = 'transfer' THEN 10 ELSE 0 END,
       CASE WHEN s.txn_type IN ('transfer','bill_payment','withdrawal') THEN cwa.wallet_id END,
       CASE WHEN s.txn_type = 'transfer' THEN cwb.wallet_id
            WHEN s.txn_type = 'deposit' THEN cwa.wallet_id END,
       CASE WHEN s.txn_type = 'bill_payment' THEN s.bl END,
       CASE WHEN s.txn_type = 'withdrawal' OR (s.txn_type = 'deposit' AND s.r4 < 0.5) THEN aw.agent_id END,
       initcap(replace(s.txn_type, '_', ' ')),
       s.created_at,
       s.created_at + INTERVAL '2 seconds'
FROM stage s
JOIN cw cwa ON cwa.n = s.a
JOIN cw cwb ON cwb.n = CASE WHEN s.b = s.a THEN 1 + s.a % 49999 ELSE s.b END
JOIN aw ON aw.n = s.ag
ORDER BY s.created_at;

UPDATE transactions SET completed_at = NULL WHERE status = 'pending';

\echo 'Opening deposits: each wallet is funded first, enough to cover all its later spending'
WITH outflow AS (
  SELECT source_wallet_id AS wallet_id, SUM(amount + fee) AS spend
  FROM transactions WHERE status = 'successful' AND source_wallet_id IS NOT NULL
  GROUP BY source_wallet_id
)
INSERT INTO transactions (txn_type, status, channel, amount, source_wallet_id, dest_wallet_id,
                          narration, created_at, completed_at)
SELECT 'deposit', 'successful', 'app',
       round((COALESCE(o.spend, 0) + 5000 + random() * 100000)::numeric, -2),
       NULL, w.wallet_id, 'Opening deposit from bank', w.created_at, w.created_at + INTERVAL '2 seconds'
FROM wallets w LEFT JOIN outflow o USING (wallet_id)
WHERE w.wallet_type = 'customer';

\echo 'Posting the double-entry ledger for every successful transaction'
INSERT INTO ledger_entries (txn_id, wallet_id, direction, amount, balance_after, created_at)
SELECT txn_id, wallet_id, direction, amount, 0, created_at FROM (
  -- debit side
  SELECT txn_id, created_at, 'D' AS direction,
         -- deposits (bank or agent cash) are funded from the bank settlement wallet
         CASE txn_type WHEN 'deposit' THEN 1
                       ELSE source_wallet_id END AS wallet_id,
         amount + fee AS amount
  FROM transactions t WHERE status = 'successful'
  UNION ALL
  -- credit side
  SELECT txn_id, created_at, 'C',
         CASE txn_type WHEN 'transfer' THEN dest_wallet_id
                       WHEN 'deposit' THEN dest_wallet_id
                       WHEN 'bill_payment' THEN 3
                       WHEN 'withdrawal' THEN (SELECT wallet_id FROM agents a WHERE a.agent_id = t.agent_id) END,
         amount
  FROM transactions t WHERE status = 'successful'
  UNION ALL
  -- fee credit
  SELECT txn_id, created_at, 'C', 2, fee FROM transactions t WHERE status = 'successful' AND fee > 0
) e
ORDER BY created_at, txn_id, direction DESC;

\echo 'Running balances and wallet balances'
UPDATE ledger_entries l SET balance_after = r.bal
FROM (SELECT entry_id,
             SUM(CASE direction WHEN 'C' THEN amount ELSE -amount END)
               OVER (PARTITION BY wallet_id ORDER BY created_at, entry_id) AS bal
      FROM ledger_entries) r
WHERE l.entry_id = r.entry_id;

ALTER TABLE wallets DISABLE TRIGGER trg_wallet_status;
UPDATE wallets w SET balance = COALESCE(s.bal, 0)
FROM (SELECT wallet_id, SUM(CASE direction WHEN 'C' THEN amount ELSE -amount END) AS bal
      FROM ledger_entries GROUP BY wallet_id) s
WHERE s.wallet_id = w.wallet_id;
ALTER TABLE wallets ENABLE TRIGGER trg_wallet_status;

\echo 'AML flags from a simple large-transfer rule'
INSERT INTO aml_flags (txn_id, rule_code, risk_score, created_at)
SELECT txn_id, 'LARGE_TRANSFER', 70, created_at
FROM transactions WHERE txn_type = 'transfer' AND amount >= 200000 AND status = 'successful';

ANALYZE;

\echo 'Row counts'
SELECT 'customers' AS table_name, count(*) FROM customers UNION ALL
SELECT 'wallets', count(*) FROM wallets UNION ALL
SELECT 'agents', count(*) FROM agents UNION ALL
SELECT 'transactions', count(*) FROM transactions UNION ALL
SELECT 'ledger_entries', count(*) FROM ledger_entries UNION ALL
SELECT 'aml_flags', count(*) FROM aml_flags;

\echo 'Integrity checks (all three should be 0)'
SELECT (SELECT count(*) FROM v_unbalanced_transactions)                         AS unbalanced_txns,
       (SELECT count(*) FROM wallets WHERE balance < 0 AND wallet_type <> 'system') AS negative_wallets,
       (SELECT count(*) FROM ledger_entries WHERE balance_after < 0
          AND wallet_id NOT IN (SELECT wallet_id FROM wallets WHERE wallet_type = 'system')) AS negative_running_balances;
