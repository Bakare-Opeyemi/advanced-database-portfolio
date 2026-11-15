// Portfolio 4: how the choice of metaField changes time-series storage.
// app_events uses meta = {customerId, channel}: 50,000 different values, so almost every bucket holds 1 event.
// Here the same events are copied into a collection whose meta is only {channel} (2 values).
db = db.getSiblingDB("moniwallet");
db.app_events_by_channel.drop();
db.createCollection("app_events_by_channel", { timeseries: { timeField: "ts", metaField: "channel", granularity: "minutes" } });
db.app_events.aggregate([
  { $project: { _id: 0, ts: 1, channel: "$meta.channel", customerId: "$meta.customerId", type: 1, deviceId: 1, appVersion: 1 } },
  { $out: "app_events_tmp" }
]);
db.app_events_by_channel.insertMany(db.app_events_tmp.find().toArray(), { ordered: false });
db.app_events_tmp.drop();
function size(name) {
  const s = db.getCollection("system.buckets." + name).stats();
  return { events: db.getCollection(name).countDocuments(), buckets: db.getCollection("system.buckets." + name).countDocuments(),
           storageKB: Math.round(s.storageSize / 1024) };
}
print("meta = {customerId, channel}: " + EJSON.stringify(size("app_events")));
print("meta = channel only        : " + EJSON.stringify(size("app_events_by_channel")));
