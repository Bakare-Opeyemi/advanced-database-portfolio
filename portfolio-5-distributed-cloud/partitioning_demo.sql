-- Portfolio 5, part C: horizontal fragmentation of transactions by month (declarative partitioning).
-- Same idea as sharding, inside one server: each month is its own table, and queries only touch the months they need.
-- Run: psql opelatwallet -f portfolio-5-distributed-cloud/partitioning_demo.sql
SET search_path TO olw;
SET max_parallel_workers_per_gather = 0;
DROP TABLE IF EXISTS transactions_by_month CASCADE;

CREATE TABLE transactions_by_month (LIKE transactions INCLUDING DEFAULTS)
PARTITION BY RANGE (created_at);

-- one partition per month of 2026, plus one for older rows (the 2025 opening deposits)
CREATE TABLE transactions_before_2026 PARTITION OF transactions_by_month
    FOR VALUES FROM (MINVALUE) TO ('2026-01-01');
DO $$
DECLARE m DATE := DATE '2026-01-01';
BEGIN
  WHILE m < DATE '2027-01-01' LOOP
    EXECUTE format('CREATE TABLE transactions_%s PARTITION OF transactions_by_month FOR VALUES FROM (%L) TO (%L)',
                   to_char(m, 'YYYY_MM'), m, m + INTERVAL '1 month');
    m := m + INTERVAL '1 month';
  END LOOP;
END $$;

INSERT INTO transactions_by_month SELECT * FROM transactions;
CREATE INDEX ON transactions_by_month (created_at);
ANALYZE transactions_by_month;

\echo '=== Rows in each partition (fragment)'
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM transactions_by_month GROUP BY 1 ORDER BY 1;

\echo '=== Partition pruning: the October report only touches the October partition'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT txn_type, count(*), sum(amount)
FROM transactions_by_month
WHERE created_at >= '2026-10-01' AND created_at < '2026-11-01' AND status = 'successful'
GROUP BY txn_type;

\echo '=== Archiving: detach an old month in milliseconds instead of a huge DELETE'
\timing on
ALTER TABLE transactions_by_month DETACH PARTITION transactions_2026_01;
\timing off
SELECT count(*) AS rows_still_in_partitioned_table FROM transactions_by_month;
SELECT count(*) AS rows_now_in_detached_archive_table FROM transactions_2026_01;
DROP TABLE transactions_by_month CASCADE;
DROP TABLE transactions_2026_01;
