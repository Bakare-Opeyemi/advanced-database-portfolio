-- MoniWallet sample data (Portfolio 1)
-- Run after schema.sql:
--   psql moniwallet -f portfolio-1-database-design/schema.sql
--   psql moniwallet -f portfolio-1-database-design/sample-data.sql
-- All names, numbers and amounts are made up.
-- Each wallet balance equals its credits minus debits in ledger_entry.

BEGIN;

INSERT INTO customer (customer_id, full_name, phone_number, email, date_of_birth, created_at) VALUES
    (1, 'Tunde Adeyemi',   '08031110001', 'tunde@example.com',   '1990-04-12', '2026-09-01 09:00+01'),
    (2, 'Chiamaka Obi',    '08031110002', 'chiamaka@example.com', '1995-07-23', '2026-09-01 10:15+01'),
    (3, 'Musa Ibrahim',    '08031110003', NULL,                   '1988-01-30', '2026-09-02 08:40+01'),
    (4, 'Ngozi Eze',       '08031110004', 'ngozi@example.com',    '2000-11-05', '2026-09-03 14:20+01'),
    (5, 'Bola Akinwale',   '08031110005', NULL,                   '1979-06-18', '2026-09-04 16:05+01');

INSERT INTO kyc_record (customer_id, id_type, id_number, kyc_level, verified_at) VALUES
    (1, 'NIN',      '10000000001', 3, '2026-09-01 09:30+01'),
    (2, 'BVN',      '22000000002', 2, '2026-09-01 10:45+01'),
    (3, 'NIN',      '10000000003', 1, '2026-09-02 09:00+01'),
    (4, 'passport', 'A00000004',   2, '2026-09-03 15:00+01'),
    (5, 'NIN',      '10000000005', 1, NULL);

INSERT INTO wallet (wallet_id, customer_id, currency, balance, created_at) VALUES
    (1, 1, 'NGN', 25000.00, '2026-09-01 09:01+01'),
    (2, 2, 'NGN', 25000.00, '2026-09-01 10:16+01'),
    (3, 3, 'NGN', 17500.00, '2026-09-02 08:41+01'),
    (4, 4, 'NGN',   500.00, '2026-09-03 14:21+01'),
    (5, 5, 'NGN', 12000.00, '2026-09-04 16:06+01');

INSERT INTO agent (agent_id, agent_name, phone_number, location) VALUES
    (1, 'Yaba Cash Point',   '08051110001', 'Yaba, Lagos'),
    (2, 'Wuse Market Agent', '08051110002', 'Wuse, Abuja'),
    (3, 'Sabon Gari POS',    '08051110003', 'Sabon Gari, Kano');

INSERT INTO biller (biller_id, biller_name, category) VALUES
    (1, 'Ikeja Electric', 'electricity'),
    (2, 'StarTV',         'tv'),
    (3, 'QuickAirtime',   'airtime'),
    (4, 'Lagos Water',    'water');

-- Transactions. Deposits and withdrawals touch one wallet; transfers touch two.
-- T8 was reversed by T9. T10 was flagged for review. T11 failed, so it has no ledger lines.
INSERT INTO transaction (transaction_id, type, from_wallet_id, to_wallet_id, agent_id, biller_id,
                         reverses_id, amount, status, flagged, created_at) VALUES
    (1,  'deposit',      NULL, 1,    1,    NULL, NULL, 50000.00, 'success',  FALSE, '2026-10-01 09:00+01'),
    (2,  'deposit',      NULL, 2,    2,    NULL, NULL, 30000.00, 'success',  FALSE, '2026-10-01 09:30+01'),
    (3,  'deposit',      NULL, 3,    1,    NULL, NULL, 20000.00, 'success',  FALSE, '2026-10-01 10:00+01'),
    (4,  'transfer',     1,    4,    NULL, NULL, NULL, 10000.00, 'success',  FALSE, '2026-10-01 11:00+01'),
    (5,  'bill_payment', 2,    NULL, NULL, 1,    NULL,  5000.00, 'success',  FALSE, '2026-10-01 12:00+01'),
    (6,  'transfer',     3,    5,    NULL, NULL, NULL,  2500.00, 'success',  FALSE, '2026-10-02 08:00+01'),
    (7,  'withdrawal',   1,    NULL, 3,    NULL, NULL, 15000.00, 'success',  FALSE, '2026-10-02 13:00+01'),
    (8,  'transfer',     2,    1,    NULL, NULL, NULL,  3000.00, 'reversed', FALSE, '2026-10-03 09:00+01'),
    (9,  'reversal',     1,    2,    NULL, NULL, 8,     3000.00, 'success',  FALSE, '2026-10-03 09:20+01'),
    (10, 'transfer',     4,    5,    NULL, NULL, NULL,  9500.00, 'success',  TRUE,  '2026-10-03 23:50+01'),
    (11, 'bill_payment', 5,    NULL, NULL, 3,    NULL,  1000.00, 'failed',   FALSE, '2026-10-04 07:30+01');

-- Ledger lines. D = money out of the wallet, C = money into the wallet.
INSERT INTO ledger_entry (transaction_id, wallet_id, direction, amount, balance_after, created_at) VALUES
    (1,  1, 'C', 50000.00, 50000.00, '2026-10-01 09:00+01'),
    (2,  2, 'C', 30000.00, 30000.00, '2026-10-01 09:30+01'),
    (3,  3, 'C', 20000.00, 20000.00, '2026-10-01 10:00+01'),
    (4,  1, 'D', 10000.00, 40000.00, '2026-10-01 11:00+01'),
    (4,  4, 'C', 10000.00, 10000.00, '2026-10-01 11:00+01'),
    (5,  2, 'D',  5000.00, 25000.00, '2026-10-01 12:00+01'),
    (6,  3, 'D',  2500.00, 17500.00, '2026-10-02 08:00+01'),
    (6,  5, 'C',  2500.00,  2500.00, '2026-10-02 08:00+01'),
    (7,  1, 'D', 15000.00, 25000.00, '2026-10-02 13:00+01'),
    (8,  2, 'D',  3000.00, 22000.00, '2026-10-03 09:00+01'),
    (8,  1, 'C',  3000.00, 28000.00, '2026-10-03 09:00+01'),
    (9,  1, 'D',  3000.00, 25000.00, '2026-10-03 09:20+01'),
    (9,  2, 'C',  3000.00, 25000.00, '2026-10-03 09:20+01'),
    (10, 4, 'D',  9500.00,   500.00, '2026-10-03 23:50+01'),
    (10, 5, 'C',  9500.00, 12000.00, '2026-10-03 23:50+01');

-- Move the id counters past the rows added above.
SELECT setval('customer_customer_id_seq',       (SELECT MAX(customer_id)    FROM customer));
SELECT setval('wallet_wallet_id_seq',           (SELECT MAX(wallet_id)      FROM wallet));
SELECT setval('agent_agent_id_seq',             (SELECT MAX(agent_id)       FROM agent));
SELECT setval('biller_biller_id_seq',           (SELECT MAX(biller_id)      FROM biller));
SELECT setval('transaction_transaction_id_seq', (SELECT MAX(transaction_id) FROM transaction));

COMMIT;
