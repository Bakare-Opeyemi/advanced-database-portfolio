#!/bin/bash
# Portfolio 5, part B: MongoDB replica set replication, automatic failover and the CAP trade-off.
# Needs start_mongo_replicaset.sh (3 nodes on 27031-27033).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; LAB="$ROOT/.lab"
URI="mongodb://127.0.0.1:27031,127.0.0.1:27032,127.0.0.1:27033/opelatwallet?replicaSet=olwrs"
step() { echo; echo "=== $*"; }
members() { mongosh --quiet "$URI" --eval 'rs.status().members.forEach(m => print(`${m.name}  ${m.stateStr.padEnd(10)}  health=${m.health}  lastApplied=${m.optimeDate ? m.optimeDate.toISOString() : "-"}`))'; }
primary() { for p in 27031 27032 27033; do r=$(mongosh --quiet --port $p --eval 'db.hello().isWritablePrimary' 2>/dev/null); [ "$r" = "true" ] && { echo $p; return; }; done; echo none; }
stopnode() { mongosh --quiet --port $1 --eval 'db.getSiblingDB("admin").shutdownServer({force: true})' >/dev/null 2>&1; }
startnode() { mongod --config "$LAB/mongod-$1.conf" >/dev/null; }

step "STEP 1: replica set members"
members

step "STEP 2: write with w:majority on the primary, read it back from a SECONDARY"
mongosh --quiet "$URI" --eval '
db.failover_test.drop();
const r = db.failover_test.insertOne({ n: 0, note: "replication check" }, { writeConcern: { w: "majority" } });
print("inserted with w:majority (acknowledged by at least 2 of 3 nodes): " + r.acknowledged);'
mongosh --quiet --port 27032 --eval 'db.getMongo().setReadPref("secondary"); print("read on 27032 (secondary): " + EJSON.stringify(db.getSiblingDB("opelatwallet").failover_test.findOne({n: 0}, {_id: 0})))'
mongosh --quiet "$URI" --eval 'rs.printSecondaryReplicationInfo()' | grep -E "source|behind"

step "STEP 3: automatic failover. A client writes every 100 ms; after 5 s the primary is shut down"
OLD=$(primary); echo "current primary: $OLD"
mongosh --quiet "$URI" "$ROOT/portfolio-5-distributed-cloud/mongo_writer.js" > "$LAB/writer.log" 2>&1 &
WRITER=$!
sleep 5
echo "shutting down primary $OLD at $(date +%T)"
T0=$(python3 -c 'import time; print(int(time.time()*1000))')
stopnode $OLD
for i in $(seq 1 60); do NEW=$(primary); [ "$NEW" != "none" ] && [ "$NEW" != "$OLD" ] && break; sleep 0.5; done
# read the election timing recorded by the new primary itself
mongosh --quiet --port $NEW --eval "
const m = rs.status().electionCandidateMetrics;
print('new primary 127.0.0.1:$NEW, election reason: ' + m.lastElectionReason);
print('elected ' + ((m.lastElectionDate - $T0) / 1000).toFixed(1) + ' s after the shutdown command; '
      + 'majority writes available again after ' + ((m.wMajorityWriteAvailabilityDate - $T0) / 1000).toFixed(1) + ' s');"
wait $WRITER
python3 - "$LAB/writer.log" <<'PY'
import sys
ok, fail, times = 0, 0, []
for line in open(sys.argv[1]):
    p = line.split()
    if not p: continue
    if p[0] == "ok": ok += 1; times.append(float(p[2]))
    elif p[0] == "fail": fail += 1; print("  " + line.strip())
gaps = [b - a for a, b in zip(times, times[1:])]
print(f"writer: {ok} writes succeeded, {fail} failed; longest pause between two successful writes = {max(gaps):.1f} s")
PY
members

step "STEP 4: the old primary comes back and rejoins as a secondary"
startnode $OLD; sleep 4
members

step "STEP 5: CAP. Two of three nodes down: no majority, so no primary"
N1=$(primary); stopnode $N1
OTHER=$(for p in 27031 27032 27033; do [ "$p" != "$N1" ] && mongosh --quiet --port $p --eval 1 >/dev/null 2>&1 && echo $p; done | head -1)
stopnode $OTHER
LAST=$(for p in 27031 27032 27033; do mongosh --quiet --port $p --eval 1 >/dev/null 2>&1 && echo $p; done | head -1)
echo "stopped $N1 and $OTHER; only $LAST is running"
sleep 12
mongosh --quiet --port $LAST --eval 'print("node " + db.hello().me + " state: " + rs.status().members.find(m => m.self).stateStr)'
echo "--- try to WRITE on the surviving node:"
mongosh --quiet --port $LAST --eval '
try { db.getSiblingDB("opelatwallet").failover_test.insertOne({ n: -1, note: "write with no majority" }); print("write succeeded (unexpected)") }
catch (e) { print("WRITE REFUSED: " + (e.codeName || e.name) + ": " + e.message.split("\n")[0].slice(0, 110)) }'
echo "--- try to READ with readPreference=secondaryPreferred:"
mongosh --quiet --port $LAST --eval '
db.getMongo().setReadPref("secondaryPreferred");
const d = db.getSiblingDB("opelatwallet");
print("READ OK from the surviving secondary: " + d.failover_test.countDocuments() + " test docs, "
      + d.customer_profiles.countDocuments() + " customer profiles (data may be slightly stale)")'

step "STEP 6: restore all three nodes"
startnode $N1; startnode $OTHER
for i in $(seq 1 40); do [ "$(primary)" = "27031" ] && break; sleep 1; done
members
echo "primary is now $(primary): node 27031 has priority 2, so once it has caught up it takes the primary role back"
