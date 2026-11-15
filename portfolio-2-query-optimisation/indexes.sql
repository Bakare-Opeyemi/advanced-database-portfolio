-- =====================================================================
-- OpeLat Wallet: Portfolio 2 indexes (each one is aimed at a specific query)
-- =====================================================================
SET search_path TO olw;

-- Q1 statement: find one wallet's entries already sorted newest first, stop after 20 rows
CREATE INDEX ix_ledger_wallet_time ON ledger_entries (wallet_id, created_at DESC, entry_id DESC);

-- Q2 search with a wildcard at the START ('%012345'): a normal B-tree cannot help, a trigram GIN index can
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX ix_customers_phone_trgm ON customers USING gin (phone gin_trgm_ops);

-- Q3 stuck transactions: a PARTIAL index that only holds the few pending rows (tiny, always in memory)
CREATE INDEX ix_txn_pending ON transactions (created_at) WHERE status = 'pending';

-- Q4 / Q5 date-range reports: rows are inserted in time order, so a BRIN index
-- (one summary per block range) is enough and is about 400 times smaller than a B-tree (24 kB vs 9.9 MB, see brin_vs_btree.sql)
CREATE INDEX ix_txn_created_brin ON transactions USING brin (created_at) WITH (pages_per_range = 32);

-- Q7 biller report: partial composite index covering only bill payments
CREATE INDEX ix_txn_bill_time ON transactions (created_at, biller_id) INCLUDE (amount)
WHERE txn_type = 'bill_payment' AND status = 'successful';

-- Q6 reconciliation reads every ledger row by design, so no index is added (see README).
-- Q8 is already served by the UNIQUE constraint on reference.

ANALYZE transactions;
ANALYZE ledger_entries;
ANALYZE customers;
