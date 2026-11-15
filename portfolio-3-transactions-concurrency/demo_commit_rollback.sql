-- =====================================================================
-- Portfolio 3, part 1: COMMIT, ROLLBACK and SAVEPOINT
-- Run after transfer_function.sql:
--   psql moniwallet -f portfolio-3-transactions-concurrency/demo_commit_rollback.sql
-- =====================================================================
SET search_path TO mw;
\set ON_ERROR_STOP off
SELECT wallet_id AS ada   FROM demo_wallets WHERE customer = 'Ada'   \gset
SELECT wallet_id AS tunde FROM demo_wallets WHERE customer = 'Tunde' \gset
SELECT wallet_id AS musa  FROM demo_wallets WHERE customer = 'Musa'  \gset

\echo '=== STEP 1: starting balances'
SELECT * FROM demo_wallets WHERE customer IN ('Ada', 'Tunde', 'Musa');

\echo '=== STEP 2: Ada sends 3,000 to Tunde inside BEGIN ... COMMIT'
BEGIN;
SELECT transfer_funds(:ada, :tunde, 3000, 'app', 'Rent share') AS txn_id;
\echo '--- inside the transaction, before COMMIT, Ada sees her new balance:'
SELECT * FROM demo_wallets WHERE customer IN ('Ada', 'Tunde');
COMMIT;
\echo '--- after COMMIT (the change is now permanent and visible to everyone):'
SELECT * FROM demo_wallets WHERE customer IN ('Ada', 'Tunde');

\echo '=== STEP 3: Ada tries to send 50,000 (she has 7,000): the function raises an error'
BEGIN;
SELECT transfer_funds(:ada, :tunde, 50000, 'app', 'Too much');
\echo '--- the transaction is now aborted, so any further statement is refused:'
SELECT 1;
ROLLBACK;
\echo '--- after ROLLBACK: balances unchanged, and no transfer row was written'
SELECT * FROM demo_wallets WHERE customer IN ('Ada', 'Tunde');
SELECT count(*) AS failed_rows_written FROM transactions WHERE narration = 'Too much';

\echo '=== STEP 4: explicit ROLLBACK of a transfer that would have worked'
BEGIN;
SELECT transfer_funds(:tunde, :musa, 1000, 'ussd', 'Cancelled by user') AS txn_id;
SELECT * FROM demo_wallets WHERE customer IN ('Tunde', 'Musa');
ROLLBACK;
\echo '--- after ROLLBACK, the 1,000 transfer is gone:'
SELECT * FROM demo_wallets WHERE customer IN ('Tunde', 'Musa');

\echo '=== STEP 5: SAVEPOINT. A batch of two payments where only the second fails'
BEGIN;
SELECT transfer_funds(:tunde, :musa, 2000, 'app', 'Batch item 1') AS item1_txn;
SAVEPOINT after_item1;
SELECT transfer_funds(:tunde, :musa, 999999, 'app', 'Batch item 2');
\echo '--- item 2 failed; roll back to the savepoint and keep item 1'
ROLLBACK TO SAVEPOINT after_item1;
COMMIT;
SELECT * FROM demo_wallets WHERE customer IN ('Tunde', 'Musa');
SELECT narration, amount, status FROM transactions WHERE narration LIKE 'Batch item%';

\echo '=== STEP 6: integrity check, every transaction still balances (expect 0)'
SELECT count(*) AS unbalanced_transactions FROM v_unbalanced_transactions;
