// Portfolio 4: OpeLat Wallet NoSQL queries with evidence (run with mongosh against the replica set)
db = db.getSiblingDB("opelatwallet");
const line = (t) => print("\n=== " + t);
const show = (o) => print(EJSON.stringify(o, null, 0));
function stats(expl) {
  const s = expl.executionStats;
  let stage = expl.queryPlanner.winningPlan.queryPlan || expl.queryPlanner.winningPlan;   // MongoDB 7 nests the plan
  const names = [];
  while (stage) { names.push(stage.stage); stage = stage.inputStage; }
  return `plan=${names.join(" <- ")}  docsExamined=${s.totalDocsExamined}  keysExamined=${s.totalKeysExamined}  timeMs=${s.executionTimeMillis}`;
}

// ---------------------------------------------------------------------------
line("N1: Login lookup. Find a customer's profile (with embedded devices) by phone");
const phoneQ = { phone: "+2348000012345" };
db.customer_profiles.dropIndexes();
print("BEFORE index: " + stats(db.customer_profiles.find(phoneQ).explain("executionStats")));
db.customer_profiles.createIndex({ phone: 1 }, { unique: true, name: "ux_phone" });
print("AFTER  index: " + stats(db.customer_profiles.find(phoneQ).explain("executionStats")));
show(db.customer_profiles.findOne(phoneQ));

// ---------------------------------------------------------------------------
line("N2: Marketing. Lagos customers who have an iOS device that is not yet trusted (query inside an embedded array)");
db.customer_profiles.createIndex({ state: 1, "devices.os": 1 }, { name: "ix_state_device_os" });   // multikey index
const n2 = { state: "Lagos", devices: { $elemMatch: { os: "iOS", trusted: false } } };
print(stats(db.customer_profiles.find(n2).explain("executionStats")));
print("matching customers: " + db.customer_profiles.countDocuments(n2));

// ---------------------------------------------------------------------------
line("N3: Fraud. Bursts of 5+ failed PINs in the last 24 hours, and whether the device is one we know");
db.app_events.createIndex({ "meta.customerId": 1, ts: -1 }, { name: "ix_customer_ts" });
db.app_events.aggregate([
  { $match: { type: "login_failed_pin", ts: { $gte: ISODate("2026-11-13T00:00:00Z"), $lt: ISODate("2026-11-14T00:00:00Z") } } },
  { $group: { _id: { customerId: "$meta.customerId", deviceId: "$deviceId" },
              failedPins: { $sum: 1 }, first: { $min: "$ts" }, last: { $max: "$ts" } } },
  { $match: { failedPins: { $gte: 5 } } },
  { $lookup: { from: "customer_profiles", localField: "_id.customerId", foreignField: "_id", as: "p" } },
  { $unwind: "$p" },
  { $project: { _id: 0, customerId: "$_id.customerId", name: { $concat: ["$p.name.first", " ", "$p.name.last"] },
                deviceId: "$_id.deviceId", failedPins: 1,
                minutes: { $round: [{ $divide: [{ $subtract: ["$last", "$first"] }, 60000] }, 0] },
                knownDevice: { $in: ["$_id.deviceId", "$p.devices.deviceId"] } } },
  { $sort: { failedPins: -1 } }
]).forEach(show);

// ---------------------------------------------------------------------------
line("N4: Operations. Logins per channel per day (time-series aggregation)");
db.app_events.aggregate([
  { $match: { type: "login_success" } },
  { $group: { _id: { day: { $dateTrunc: { date: "$ts", unit: "day" } }, channel: "$meta.channel" }, logins: { $sum: 1 } } },
  { $sort: { "_id.day": 1, "_id.channel": 1 } },
  { $project: { _id: 0, day: { $dateToString: { date: "$_id.day", format: "%Y-%m-%d" } }, channel: "$_id.channel", logins: 1 } }
]).forEach(show);
const coll = db.getCollectionInfos({ name: "app_events" })[0];
print("app_events is a " + coll.type + " collection; storage buckets: " + db.system.buckets.app_events.countDocuments()
      + " for " + db.app_events.countDocuments() + " events");

// ---------------------------------------------------------------------------
line("N5: AML graph. Follow the money from one wallet for up to 3 hops with $graphLookup");
db.transfer_edges.createIndex({ from: 1 }, { name: "ix_from" });
const start = db.transfer_edges.aggregate([{ $group: { _id: "$from", n: { $sum: 1 } } }, { $sort: { n: -1, _id: 1 } }, { $limit: 1 }]).next()._id;
print("start wallet (most outgoing transfers in the last 30 days): " + start);
db.transfer_edges.aggregate([
  { $match: { from: start } },
  { $limit: 1 },
  { $graphLookup: { from: "transfer_edges", startWith: "$from", connectFromField: "to", connectToField: "from",
                    as: "trail", maxDepth: 2, depthField: "hop" } },
  { $unwind: "$trail" },
  { $group: { _id: { $add: ["$trail.hop", 1] }, transfers: { $sum: 1 },
              wallets: { $addToSet: "$trail.to" }, value: { $sum: "$trail.amount" } } },
  { $project: { _id: 0, hop: "$_id", transfers: 1, walletsReached: { $size: "$wallets" }, value: { $round: ["$value", 2] } } },
  { $sort: { hop: 1 } }
]).forEach(show);

// ---------------------------------------------------------------------------
line("N6: Schema validation. A profile with a badly formatted phone number is rejected");
try {
  db.customer_profiles.insertOne({ _id: 999999, phone: "08031234567", name: { first: "Bad", last: "Phone" }, walletId: 1, devices: [] });
  print("inserted (unexpected)");
} catch (e) { print("REJECTED: " + e.errmsg + " (code " + e.code + ")"); }

// ---------------------------------------------------------------------------
line("N7: Atomic update of one element inside the embedded array (trust a device after OTP check)");
const before = db.customer_profiles.findOne({ _id: 1 }, { devices: 1 });
show(before.devices.map(d => ({ deviceId: d.deviceId, trusted: d.trusted })));
const r = db.customer_profiles.updateOne({ _id: 1, "devices.deviceId": "dev-1-2" }, { $set: { "devices.$.trusted": true } });
print("matched=" + r.matchedCount + " modified=" + r.modifiedCount);
show(db.customer_profiles.findOne({ _id: 1 }, { devices: 1 }).devices.map(d => ({ deviceId: d.deviceId, trusted: d.trusted })));

// ---------------------------------------------------------------------------
line("N8: TTL index. A session that expires in 5 seconds is deleted automatically");
db.login_sessions.insertOne({ _id: "sess-ttl-demo", customerId: 1, deviceId: "dev-1-1", channel: "app",
                              loginAt: new Date(), expiresAt: new Date(Date.now() + 5000) });
print("just inserted, found: " + db.login_sessions.countDocuments({ _id: "sess-ttl-demo" }));
const t0 = Date.now();
while (db.login_sessions.countDocuments({ _id: "sess-ttl-demo" }) > 0 && Date.now() - t0 < 90000) { sleep(2000); }
print("after " + Math.round((Date.now() - t0) / 1000) + " s, found: " + db.login_sessions.countDocuments({ _id: "sess-ttl-demo" })
      + "  (the TTL monitor runs every 60 s)");
