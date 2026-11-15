-- Portfolio 4: export OpeLat Wallet data from PostgreSQL as JSON lines for MongoDB.
-- Output goes to ../.lab/ (not committed). Run from the repository root:
--   psql opelatwallet -f portfolio-4-nosql/export_from_postgres.sql
SET search_path TO olw;
SELECT setseed(0.4);

-- 1. Customer profiles: one document per customer with an embedded array of devices
\copy (SELECT json_build_object('_id', c.customer_id, 'phone', c.phone, 'name', json_build_object('first', c.first_name, 'last', c.last_name), 'state', c.state, 'kycTier', c.kyc_tier, 'walletId', w.wallet_id, 'createdAt', json_build_object('$date', to_char(c.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), 'devices', (SELECT json_agg(json_build_object('deviceId', 'dev-' || c.customer_id || '-' || d, 'os', split_part(p.pair, '|', 1), 'model', split_part(p.pair, '|', 2), 'trusted', d = 1, 'firstSeen', json_build_object('$date', to_char((c.created_at + d * interval '40 days') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))) FROM generate_series(1, 1 + (random()*2)::int) d, LATERAL (SELECT (ARRAY['Android|Tecno Spark 10','Android|Infinix Hot 30','Android|Samsung Galaxy A14','iOS|iPhone 13','KaiOS|itel A70','Android|Redmi 12'])[1 + (random()*5)::int] || left(d::text, 0) AS pair) p), 'notifications', json_build_object('sms', true, 'push', random() < 0.7, 'email', c.email IS NOT NULL)) FROM customers c JOIN wallets w ON w.customer_id = c.customer_id WHERE c.phone NOT LIKE '+23480999000%' ORDER BY c.customer_id) TO '.lab/customer_profiles.json'

-- 2. Transfer edges for the graph model: who sent money to whom in the last 30 days of data
\copy (SELECT json_build_object('_id', t.txn_id, 'from', t.source_wallet_id, 'to', t.dest_wallet_id, 'amount', t.amount, 'at', json_build_object('$date', to_char(t.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))) FROM transactions t WHERE t.txn_type = 'transfer' AND t.status = 'successful' AND t.created_at >= TIMESTAMPTZ '2026-10-14' AND t.created_at < TIMESTAMPTZ '2026-11-14' ORDER BY t.txn_id) TO '.lab/transfer_edges.json'
