#!/bin/bash
# Portfolio 4: build the MoniWallet MongoDB database on the replica set.
# Needs: start_mongo_replicaset.sh running, and export_from_postgres.sql already run.
set -e
cd "$(dirname "$0")/.."
URI="mongodb://127.0.0.1:27031,127.0.0.1:27032,127.0.0.1:27033/moniwallet?replicaSet=mwrs"
mongosh --quiet "$URI" portfolio-4-nosql/create_collections.js
mongoimport --quiet --uri "$URI" --collection customer_profiles --file .lab/customer_profiles.json
mongoimport --quiet --uri "$URI" --collection transfer_edges   --file .lab/transfer_edges.json
mongosh --quiet "$URI" portfolio-4-nosql/generate_activity.js
mongosh --quiet "$URI" --eval 'print("customer_profiles: " + db.customer_profiles.countDocuments() + ", transfer_edges: " + db.transfer_edges.countDocuments())'
