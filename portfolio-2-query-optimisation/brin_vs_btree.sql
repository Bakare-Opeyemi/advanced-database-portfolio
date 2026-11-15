-- Portfolio 2: compare a BRIN index with a normal B-tree on the same column (transactions.created_at)
SET search_path TO mw;
SET max_parallel_workers_per_gather = 0;
\timing on
CREATE INDEX ix_tmp_created_btree ON transactions (created_at);
SELECT 'BRIN'  AS index_type, pg_size_pretty(pg_relation_size('ix_txn_created_brin'))  AS size
UNION ALL
SELECT 'B-tree', pg_size_pretty(pg_relation_size('ix_tmp_created_btree'));
\echo '--- Q4 with the B-tree available (planner free to choose)'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT date_trunc('day', created_at)::date, txn_type, channel, count(*), sum(amount)
FROM transactions
WHERE created_at >= TIMESTAMPTZ '2026-10-01' AND created_at < TIMESTAMPTZ '2026-11-01' AND status = 'successful'
GROUP BY 1, 2, 3;
DROP INDEX ix_tmp_created_btree;
