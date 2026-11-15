#!/bin/bash
# Rebuild the whole portfolio from scratch: database, data, every experiment, evidence files and screenshots.
# Needs PostgreSQL 14+ running on port 5432, MongoDB 7 with mongosh, and Python 3 with psycopg2,
# matplotlib and Pillow. Takes about 6 minutes. Run from anywhere: ./tools/run_all.sh
set -e
cd "$(dirname "$0")/.."
DB=opelatwallet
URI="mongodb://127.0.0.1:27031,127.0.0.1:27032,127.0.0.1:27033/$DB?replicaSet=olwrs"
say() { echo; echo ">>> $*"; }

createdb $DB 2>/dev/null || true

say "Portfolio 1: schema and constraint tests"
psql $DB -X -v ON_ERROR_STOP=1 -q -f portfolio-1-database-design/schema.sql
psql $DB -X -c "\dt olw.*" -c "\d olw.wallets" -c "\d olw.transactions" > portfolio-1-database-design/evidence/schema_in_postgres.txt 2>&1
psql $DB -X -f portfolio-1-database-design/constraint_tests.sql > portfolio-1-database-design/evidence/constraint_tests_output.txt 2>&1
python3 tools/draw_er_diagram.py portfolio-1-database-design/er-diagram.png

say "Portfolio 2: data load and benchmark"
psql $DB -X -v ON_ERROR_STOP=1 -f portfolio-2-query-optimisation/load_data.sql > portfolio-2-query-optimisation/evidence/load_data_output.txt 2>&1
rm -rf portfolio-2-query-optimisation/evidence/plans_before portfolio-2-query-optimisation/evidence/plans_after portfolio-2-query-optimisation/evidence/results
python3 portfolio-2-query-optimisation/run_benchmark.py > /dev/null
psql $DB -X -f portfolio-2-query-optimisation/brin_vs_btree.sql > portfolio-2-query-optimisation/evidence/brin_vs_btree_output.txt 2>&1

say "Portfolio 3: transactions and concurrency"
psql $DB -X -v ON_ERROR_STOP=1 -q -f portfolio-3-transactions-concurrency/transfer_function.sql
psql $DB -X -f portfolio-3-transactions-concurrency/demo_commit_rollback.sql > portfolio-3-transactions-concurrency/evidence/commit_rollback_output.txt 2>&1
python3 portfolio-3-transactions-concurrency/concurrency_demos.py > portfolio-3-transactions-concurrency/evidence/concurrency_demos_output.txt 2>&1
psql $DB -X -v ON_ERROR_STOP=1 -q -f portfolio-3-transactions-concurrency/transfer_function.sql   # reset demo wallets

say "Portfolio 4: MongoDB"
./portfolio-5-distributed-cloud/start_mongo_replicaset.sh
psql $DB -X -q -f portfolio-4-nosql/export_from_postgres.sql > /dev/null
./portfolio-4-nosql/setup_mongo.sh
mongosh --quiet "$URI" portfolio-4-nosql/queries.js > portfolio-4-nosql/evidence/queries_output.txt 2>&1
mongosh --quiet "$URI" portfolio-4-nosql/timeseries_bucket_experiment.js > portfolio-4-nosql/evidence/timeseries_bucket_experiment_output.txt 2>&1
mongosh --quiet "$URI" --eval 'printjson(db.customer_profiles.findOne({_id: 12345}))' > portfolio-4-nosql/evidence/sample_document.json

say "Portfolio 5: replication, failover, partitioning"
./portfolio-5-distributed-cloud/pg_replication_demo.sh > portfolio-5-distributed-cloud/evidence/pg_replication_output.txt 2>&1
./portfolio-5-distributed-cloud/mongo_failover_demo.sh > portfolio-5-distributed-cloud/evidence/mongo_failover_output.txt 2>&1
psql $DB -X -f portfolio-5-distributed-cloud/partitioning_demo.sql > portfolio-5-distributed-cloud/evidence/partitioning_output.txt 2>&1
python3 tools/draw_architecture.py portfolio-5-distributed-cloud/architecture.png

say "Screenshots"
python3 tools/make_screenshots.py

say "Final integrity check (both numbers should be 0)"
psql $DB -X -Atc "SELECT 'unbalanced ledger transactions: ' || count(*) FROM olw.v_unbalanced_transactions"
psql $DB -X -Atc "SELECT 'wallets whose balance differs from the ledger: ' || count(*) FROM olw.wallets w JOIN (SELECT wallet_id, sum(CASE direction WHEN 'C' THEN amount ELSE -amount END) b FROM olw.ledger_entries GROUP BY 1) s USING (wallet_id) WHERE w.balance <> s.b"

say "Stopping the MongoDB test nodes"
for p in 27031 27032 27033; do mongosh --quiet --port $p --eval 'db.getSiblingDB("admin").shutdownServer({force:true})' >/dev/null 2>&1 || true; done
echo "done"
