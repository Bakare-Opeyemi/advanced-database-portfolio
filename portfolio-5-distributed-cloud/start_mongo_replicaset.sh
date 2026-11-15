#!/bin/bash
# Start a 3-node MongoDB replica set (ports 27031-27033) on this computer.
# Data goes in .lab/ (ignored by git). Re-running it is safe.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$ROOT/.lab"
mkdir -p "$LAB"
for PORT in 27031 27032 27033; do
  mkdir -p "$LAB/mongo-$PORT"
  sed -e "s#PORT#$PORT#g" -e "s#LAB#$LAB#g" "$ROOT/portfolio-5-distributed-cloud/config/mongod-node.conf.template" > "$LAB/mongod-$PORT.conf"
  if ! mongosh --quiet --port $PORT --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; then
    mongod --config "$LAB/mongod-$PORT.conf" >/dev/null
    echo "started node on port $PORT"
  fi
done
mongosh --quiet --port 27031 --eval '
try { rs.status(); print("replica set already initiated") }
catch (e) {
  rs.initiate({ _id: "mwrs", members: [
    { _id: 0, host: "127.0.0.1:27031", priority: 2 },
    { _id: 1, host: "127.0.0.1:27032", priority: 1 },
    { _id: 2, host: "127.0.0.1:27033", priority: 1 } ] });
  print("replica set initiated");
}'
# wait for a primary
for i in $(seq 1 30); do
  P=$(mongosh --quiet "mongodb://127.0.0.1:27031,127.0.0.1:27032,127.0.0.1:27033/?replicaSet=mwrs" --eval 'db.hello().primary' 2>/dev/null || true)
  if [ -n "$P" ]; then echo "primary is $P"; exit 0; fi
  sleep 1
done
echo "no primary elected"; exit 1
