-- Portfolio 1: each test tries to insert bad data and is EXPECTED to be rejected.
-- Every test runs in its own transaction and is rolled back, so the database stays clean.
SET search_path TO olw;
\set ON_ERROR_STOP off
\echo '=== Test 1: phone not in Nigerian format (expected: rejected)'
BEGIN;
INSERT INTO customers (phone, first_name, last_name, date_of_birth, state) VALUES ('08031234567','Bad','Phone','1990-01-01','Lagos');
ROLLBACK;
\echo '=== Test 2: customer under 18 (expected: rejected)'
BEGIN;
INSERT INTO customers (phone, first_name, last_name, date_of_birth, state) VALUES ('+2348031234568','Young','User',CURRENT_DATE - INTERVAL '10 years','Oyo');
ROLLBACK;
\echo '=== Test 3: duplicate phone number (expected: rejected)'
BEGIN;
INSERT INTO customers (phone, first_name, last_name, date_of_birth, state) VALUES ('+2348031234567','Ada','Okeke','1995-04-02','Lagos'); INSERT INTO customers (phone, first_name, last_name, date_of_birth, state) VALUES ('+2348031234567','Copy','Cat','1990-01-01','Kano');
ROLLBACK;
\echo '=== Test 4: customer wallet with a negative balance (expected: rejected)'
BEGIN;
INSERT INTO customers (customer_id, phone, first_name, last_name, date_of_birth, state) VALUES (900001,'+2348031234569','Ada','Okeke','1995-04-02','Lagos'); INSERT INTO wallets (wallet_type, customer_id, balance) VALUES ('customer', 900001, -500);
ROLLBACK;
\echo '=== Test 5: customer wallet with no owner (expected: rejected)'
BEGIN;
INSERT INTO wallets (wallet_type, balance) VALUES ('customer', 100);
ROLLBACK;
\echo '=== Test 6: transfer from a wallet to itself (expected: rejected)'
BEGIN;
INSERT INTO wallets (wallet_id, wallet_type, label) VALUES (900001,'system','test'); INSERT INTO transactions (txn_type, channel, amount, source_wallet_id, dest_wallet_id) VALUES ('transfer','app',1000,900001,900001);
ROLLBACK;
\echo '=== Test 7: transaction with a zero amount (expected: rejected)'
BEGIN;
INSERT INTO wallets (wallet_id, wallet_type, label) VALUES (900002,'system','test'); INSERT INTO transactions (txn_type, channel, amount, dest_wallet_id) VALUES ('deposit','app',0,900002);
ROLLBACK;
\echo '=== Test 8: ledger entry pointing to a transaction that does not exist (expected: rejected)'
BEGIN;
INSERT INTO wallets (wallet_id, wallet_type, label) VALUES (900003,'system','test'); INSERT INTO ledger_entries (txn_id, wallet_id, direction, amount, balance_after) VALUES (999999999, 900003, 'C', 100, 100);
ROLLBACK;
\echo '=== Test 9: unknown KYC document type (expected: rejected)'
BEGIN;
INSERT INTO customers (customer_id, phone, first_name, last_name, date_of_birth, state) VALUES (900002,'+2348031234570','Tunde','Bello','1988-06-12','Ogun'); INSERT INTO kyc_documents (customer_id, doc_type, doc_number) VALUES (900002,'school_id','X123');
ROLLBACK;
