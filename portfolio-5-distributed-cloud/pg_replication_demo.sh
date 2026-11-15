#!/bin/bash
# Portfolio 5, part A: PostgreSQL streaming replication for OpeLat Wallet.
# Builds a NEW primary (port 5442) and a hot-standby replica (port 5443) in .lab/,
# separate from the main PostgreSQL server on 5432. Re-running starts from scratch.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$ROOT/.lab"; P="$LAB/pg-primary"; R="$LAB/pg-replica"
CONF="$ROOT/portfolio-5-distributed-cloud/config"
PSQLP="psql -X -q -p 5442 -d opelatwallet"
PSQLR="psql -X -q -p 5443 -d opelatwallet"
step() { echo; echo "=== $*"; }
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

pg_ctl -D "$R" stop -m fast >/dev/null 2>&1; pg_ctl -D "$P" stop -m fast >/dev/null 2>&1
rm -rf "$P" "$R"; mkdir -p "$LAB"

step "STEP 1: create the primary (port 5442) and the replica (port 5443)"
initdb -D "$P" -A trust -U "$USER" >/dev/null
cat "$CONF/primary.conf" >> "$P/postgresql.conf"
echo "host replication all 127.0.0.1/32 trust" >> "$P/pg_hba.conf"
pg_ctl -D "$P" -l "$LAB/pg-primary.log" -o "-p 5442" start -w >/dev/null
createdb -p 5442 opelatwallet
psql -X -q -p 5442 -d opelatwallet -f "$ROOT/portfolio-1-database-design/schema.sql" >/dev/null 2>&1
psql -X -q -p 5442 -d opelatwallet -c "INSERT INTO olw.wallets (wallet_type, label) VALUES ('system','Bank settlement'),('system','Fee income'),('system','Biller settlement')"
psql -X -q -p 5442 -d opelatwallet -f "$ROOT/portfolio-3-transactions-concurrency/transfer_function.sql" >/dev/null 2>&1
pg_basebackup -h 127.0.0.1 -p 5442 -D "$R" -R -X stream -C -S replica1_slot -d "application_name=replica1" >/dev/null
cat "$CONF/replica.conf" >> "$R/postgresql.conf"
pg_ctl -D "$R" -l "$LAB/pg-replica.log" -o "-p 5443" start -w >/dev/null
sleep 1
echo "primary in recovery? $($PSQLP -Atc 'select pg_is_in_recovery()')   replica in recovery? $($PSQLR -Atc 'select pg_is_in_recovery()')"
$PSQLP -c "SELECT application_name, state, sync_state, client_addr FROM pg_stat_replication"

step "STEP 2: a transfer committed on the PRIMARY appears on the REPLICA"
$PSQLP -c "SELECT * FROM olw.demo_wallets WHERE customer IN ('Ada','Tunde')"
ADA=$($PSQLP -Atc "SELECT wallet_id FROM olw.demo_wallets WHERE customer='Ada'")
TUNDE=$($PSQLP -Atc "SELECT wallet_id FROM olw.demo_wallets WHERE customer='Tunde'")
T0=$(ms); TXN=$($PSQLP -Atc "SELECT olw.transfer_funds($ADA, $TUNDE, 2500, 'app', 'Replication test')")
if [ -z "$TXN" ]; then echo "transfer failed on the primary, stopping"; pg_ctl -D "$R" stop -m fast; pg_ctl -D "$P" stop -m fast; exit 1; fi
for i in $(seq 1 500); do
  [ "$($PSQLR -Atc "SELECT count(*) FROM olw.transactions WHERE txn_id = $TXN")" = "1" ] && break
done
T1=$(ms)
echo "transfer $TXN committed on primary; visible on replica after about $((T1 - T0)) ms (includes psql start-up time)"
echo "--- reading the balances FROM THE REPLICA:"
$PSQLR -c "SELECT * FROM olw.demo_wallets WHERE customer IN ('Ada','Tunde')"
$PSQLP -c "SELECT application_name, write_lag, flush_lag, replay_lag FROM pg_stat_replication"

step "STEP 3: the replica is read-only (hot standby)"
$PSQLR -c "SELECT olw.transfer_funds($ADA, $TUNDE, 100)" 2>&1 | head -2

step "STEP 4: asynchronous vs synchronous commit, 300 small transfers each"
bench() {
  python3 - "$ADA" "$TUNDE" <<'PY'
import sys, time, psycopg2
a, t = int(sys.argv[1]), int(sys.argv[2])
c = psycopg2.connect("port=5442 dbname=opelatwallet"); cur = c.cursor()
start = time.time()
for i in range(300):
    src, dst = (a, t) if i % 2 == 0 else (t, a)
    cur.execute("SELECT olw.transfer_funds(%s, %s, 10, 'app', 'Commit timing')", (src, dst)); c.commit()
print(f"average commit time: {(time.time() - start) / 300 * 1000:.2f} ms per transfer")
PY
}
echo "--- synchronous_standby_names = '' (ASYNC: commit returns once the PRIMARY has it on disk)"
bench
$PSQLP -c "ALTER SYSTEM SET synchronous_standby_names = 'replica1'" -c "SELECT pg_reload_conf()" >/dev/null
sleep 1
$PSQLP -c "SELECT application_name, state, sync_state FROM pg_stat_replication"
echo "--- synchronous_standby_names = 'replica1' (SYNC: commit waits until the REPLICA also has it)"
bench

step "STEP 5: CAP in practice. Stop the replica while commits are synchronous"
pg_ctl -D "$R" stop -m fast >/dev/null; echo "replica stopped"
python3 - "$ADA" "$TUNDE" <<'PY'
import sys, time, threading, psycopg2
a, t = int(sys.argv[1]), int(sys.argv[2])
c = psycopg2.connect("port=5442 dbname=opelatwallet"); cur = c.cursor()
cur.execute("SELECT olw.transfer_funds(%s, %s, 50, 'app', 'Sync commit with replica down')", (a, t))
threading.Timer(5, c.cancel).start()          # give up waiting after 5 seconds
start = time.time()
try:
    c.commit()
    print(f"COMMIT was BLOCKED for {time.time() - start:.1f} s waiting for the replica, until the client cancelled the wait")
except Exception as e:
    print(f"COMMIT failed after {time.time() - start:.1f} s: {e}")
for n in c.notices:
    print("server " + n.strip())
PY
echo "--- is the transfer on the primary anyway?"
$PSQLP -c "SELECT txn_id, narration, status FROM olw.transactions WHERE narration = 'Sync commit with replica down'"
echo "--- choose availability instead: go back to asynchronous commit"
$PSQLP -c "ALTER SYSTEM SET synchronous_standby_names = ''" -c "SELECT pg_reload_conf()" >/dev/null
T0=$(ms); $PSQLP -Atc "SELECT olw.transfer_funds($ADA, $TUNDE, 50, 'app', 'Async commit with replica down')" >/dev/null; T1=$(ms)
echo "async commit with the replica down returned in $((T1 - T0)) ms"

step "STEP 6: failover. The primary fails and the replica is promoted"
pg_ctl -D "$R" -l "$LAB/pg-replica.log" -o "-p 5443" start -w >/dev/null; sleep 2
echo "replica restarted and caught up: $($PSQLR -Atc "SELECT count(*) FROM olw.transactions WHERE narration LIKE '%replica down'") of 2 transfers made while it was down"
pg_ctl -D "$P" stop -m immediate >/dev/null; echo "primary on 5442 killed (immediate stop, like a crash)"
T0=$(ms); pg_ctl -D "$R" promote -w >/dev/null; T1=$(ms)
echo "replica promoted in $((T1 - T0)) ms; in recovery now? $($PSQLR -Atc 'select pg_is_in_recovery()')"
$PSQLR -c "SELECT olw.transfer_funds($ADA, $TUNDE, 75, 'app', 'First write after failover') AS new_txn"
$PSQLR -c "SELECT * FROM olw.demo_wallets WHERE customer IN ('Ada','Tunde')"
$PSQLR -Atc "SELECT 'unbalanced ledger transactions after failover: ' || count(*) FROM olw.v_unbalanced_transactions"

pg_ctl -D "$R" stop -m fast >/dev/null 2>&1
echo; echo "lab servers stopped"
