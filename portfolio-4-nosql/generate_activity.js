// Portfolio 4: generate login sessions and app telemetry for the MoniWallet customers.
// Uses a seeded random generator so every run produces the same data.
db = db.getSiblingDB("moniwallet");

// mulberry32: a small, good-quality seeded generator (a plain LCG repeated patterns)
let seed = 8103;
function rnd() {
  seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
function pick(a) { return a[Math.floor(rnd() * a.length)]; }

const START = new Date("2026-11-07T00:00:00Z").getTime();
const SPAN = 7 * 24 * 3600 * 1000;                // one week of activity
const channels = ["app", "app", "app", "ussd", "ussd"];

// a few customers behave like an account-takeover attempt: many failed PINs from a new device
const suspicious = new Set([1201, 2402, 3603, 4804, 6005, 7206]);

const events = [];
const sessions = [];
for (let i = 0; i < 160000; i++) {
  const customerId = 1 + Math.floor(rnd() * 50000);
  const channel = pick(channels);
  const ts = new Date(START + Math.floor(rnd() * SPAN));
  const deviceId = "dev-" + customerId + "-" + (1 + Math.floor(rnd() * 2));
  const type = pick(["login_success", "login_success", "balance_check", "balance_check",
                     "transfer_initiated", "bill_payment_initiated", "login_failed_pin"]);
  events.push({ ts, meta: { customerId, channel }, type, deviceId, appVersion: channel === "app" ? pick(["5.2.0", "5.3.1", "5.4.0"]) : null });
  if (type === "login_success" && channel === "app" && sessions.length < 20000) {
    sessions.push({ _id: "sess-" + i, customerId, deviceId, channel, loginAt: ts,
                    expiresAt: new Date(ts.getTime() + 30 * 24 * 3600 * 1000) });   // "remember me" for 30 days
  }
}
// the suspicious pattern: 8 to 15 failed PINs within one hour from a device never seen before
for (const customerId of suspicious) {
  const base = START + SPAN - 6 * 3600 * 1000 + Math.floor(rnd() * 3600 * 1000);
  const n = 8 + Math.floor(rnd() * 8);
  for (let k = 0; k < n; k++) {
    events.push({ ts: new Date(base + k * 180000), meta: { customerId, channel: "app" },
                  type: "login_failed_pin", deviceId: "dev-unknown-" + customerId, appVersion: "5.4.0" });
  }
}
db.app_events.insertMany(events, { ordered: false });
db.login_sessions.insertMany(sessions, { ordered: false });
print("app_events: " + db.app_events.countDocuments() + ", login_sessions: " + db.login_sessions.countDocuments());
