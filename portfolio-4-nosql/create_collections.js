// Portfolio 4: create the OpeLat Wallet MongoDB collections (run with mongosh against the replica set)
// mongosh "mongodb://127.0.0.1:27031,127.0.0.1:27032,127.0.0.1:27033/opelatwallet?replicaSet=olwrs" create_collections.js
db = db.getSiblingDB("opelatwallet");
db.dropDatabase();

// 1. customer_profiles: one DOCUMENT per customer. Devices and notification settings are
//    embedded because they are always read together with the profile at login.
db.createCollection("customer_profiles", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "phone", "name", "walletId", "devices"],
    properties: {
      phone:   { bsonType: "string", pattern: "^\\+234[789][01][0-9]{8}$" },
      kycTier: { bsonType: "int", minimum: 1, maximum: 3 },
      devices: { bsonType: "array", maxItems: 5, items: {
        bsonType: "object", required: ["deviceId", "os", "trusted"],
        properties: { os: { enum: ["Android", "iOS", "KaiOS"] }, trusted: { bsonType: "bool" } } } }
    } } },
  validationAction: "error"
});

// 2. login_sessions: KEY-VALUE style lookups by session token, removed automatically by a TTL index
db.createCollection("login_sessions");
db.login_sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0, name: "ttl_expiresAt" });

// 3. app_events: a TIME-SERIES collection for app and USSD telemetry (logins, PIN failures, ...)
db.createCollection("app_events", {
  timeseries: { timeField: "ts", metaField: "meta", granularity: "minutes" }
});

// 4. transfer_edges: a GRAPH of who sent money to whom (edges imported from PostgreSQL)
db.createCollection("transfer_edges");

print("collections: " + db.getCollectionNames().sort().join(", "));
