// Writes one "transfer request" document every 100 ms for 25 s and reports every success or failure.
// Run against the replica set URI; the driver finds the new primary by itself after a failover.
db = db.getSiblingDB("moniwallet");
const t0 = Date.now();
let n = 0;
while (Date.now() - t0 < 25000) {
  n++;
  const t = ((Date.now() - t0) / 1000).toFixed(2);
  try {
    db.failover_test.insertOne({ n, at: new Date(), note: "write during failover test" },
                               { writeConcern: { w: "majority", wtimeout: 3000 } });
    print(`ok   ${n} ${t}`);
  } catch (e) {
    print(`fail ${n} ${t} ${e.codeName || e.name}`);
  }
  sleep(100);
}
