-- =====================================================================
-- MoniWallet: Portfolio 2 queries
-- Each query is separated by a line "-- @Qn: title" so run_benchmark.py can run them one by one.
-- Dates are fixed (the data ends on 13 Nov 2026) so the results are repeatable.
-- =====================================================================

-- @Q1: Customer statement (last 20 ledger lines for one wallet)
SELECT l.created_at, t.txn_type, t.reference, l.direction, l.amount, l.balance_after, t.narration
FROM mw.ledger_entries l
JOIN mw.transactions t ON t.txn_id = l.txn_id
WHERE l.wallet_id = 36844
ORDER BY l.created_at DESC, l.entry_id DESC
LIMIT 20;

-- @Q2: Support agent finds a caller from the last 6 digits of their phone number
SELECT customer_id, first_name, last_name, phone, state
FROM mw.customers
WHERE phone LIKE '%012345'
ORDER BY customer_id
LIMIT 25;

-- @Q3: Stuck transactions still pending after 15 minutes (operations alert)
SELECT txn_id, reference, txn_type, amount, created_at
FROM mw.transactions
WHERE status = 'pending'
  AND created_at < TIMESTAMPTZ '2026-11-14 00:00' - INTERVAL '15 minutes'
ORDER BY created_at;

-- @Q4: Daily volume report for October 2026 by type and channel (finance)
SELECT date_trunc('day', created_at)::date AS day, txn_type, channel,
       count(*) AS txns, sum(amount) AS value
FROM mw.transactions
WHERE created_at >= TIMESTAMPTZ '2026-10-01' AND created_at < TIMESTAMPTZ '2026-11-01'
  AND status = 'successful'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- @Q5: AML check: wallets that sent 3 or more transfers, or 300,000 or more in total, on one day in the last 7 days
SELECT t.source_wallet_id, c.first_name || ' ' || c.last_name AS customer,
       date_trunc('day', t.created_at)::date AS day, count(*) AS transfers, sum(t.amount) AS total
FROM mw.transactions t
JOIN mw.wallets w   ON w.wallet_id = t.source_wallet_id
JOIN mw.customers c ON c.customer_id = w.customer_id
WHERE t.txn_type = 'transfer' AND t.status = 'successful'
  AND t.created_at >= TIMESTAMPTZ '2026-11-07' AND t.created_at < TIMESTAMPTZ '2026-11-14'
GROUP BY 1, 2, 3
HAVING count(*) >= 3 OR sum(t.amount) >= 300000
ORDER BY total DESC
LIMIT 20;

-- @Q6: Nightly reconciliation: wallets whose stored balance differs from the ledger
SELECT w.wallet_id, w.balance, s.ledger_balance
FROM mw.wallets w
JOIN (SELECT wallet_id, sum(CASE direction WHEN 'C' THEN amount ELSE -amount END) AS ledger_balance
      FROM mw.ledger_entries GROUP BY wallet_id) s USING (wallet_id)
WHERE w.balance <> s.ledger_balance;

-- @Q7: Top billers by value in October 2026
SELECT b.name, b.category, count(*) AS payments, sum(t.amount) AS value
FROM mw.transactions t
JOIN mw.billers b ON b.biller_id = t.biller_id
WHERE t.txn_type = 'bill_payment' AND t.status = 'successful'
  AND t.created_at >= TIMESTAMPTZ '2026-10-01' AND t.created_at < TIMESTAMPTZ '2026-11-01'
GROUP BY b.name, b.category
ORDER BY value DESC
LIMIT 10;

-- @Q8: Partner bank looks up a transaction by its reference
SELECT txn_id, txn_type, status, amount, created_at
FROM mw.transactions
WHERE reference = '8387e97b-9fbf-4302-bd93-3dc33a754e29';
