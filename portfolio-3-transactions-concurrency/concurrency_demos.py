"""Portfolio 3, part 2: concurrency problems and the controls that fix them.

Two real PostgreSQL sessions (S1 and S2) run side by side. Every step is printed with the
time since the demo started, so you can see who waited for whom.

  Demo A  Lost update with a naive read-then-write (READ COMMITTED)
  Demo B  Fix 1: pessimistic locking with SELECT ... FOR UPDATE
  Demo C  Fix 2: REPEATABLE READ detects the conflict, the app retries
  Demo D  Non-repeatable read: READ COMMITTED vs REPEATABLE READ
  Demo E  Deadlock from opposite lock order, and the fix (transfer_funds locks in id order)
  Demo F  Stress test: 16 threads x 250 random transfers through transfer_funds

Usage (after transfer_function.sql):
    python3 portfolio-3-transactions-concurrency/concurrency_demos.py
"""
import random
import threading
import time
from decimal import Decimal

import psycopg2
from psycopg2 import errors
from psycopg2.extensions import ISOLATION_LEVEL_READ_COMMITTED, ISOLATION_LEVEL_REPEATABLE_READ

DSN = "dbname=moniwallet options='-c search_path=mw'"
T0 = time.time()


def log(who, msg):
    print(f"[{time.time() - T0:6.2f}s] {who:<3} {msg}", flush=True)


def connect(level=ISOLATION_LEVEL_READ_COMMITTED):
    c = psycopg2.connect(DSN)
    c.set_isolation_level(level)
    return c


def wallet(name):
    with connect() as c, c.cursor() as cur:
        cur.execute("SELECT wallet_id FROM demo_wallets WHERE customer = %s", (name,))
        return cur.fetchone()[0]


def set_balance(wid, amount):
    with connect() as c, c.cursor() as cur:
        cur.execute("UPDATE wallets SET balance = %s WHERE wallet_id = %s", (amount, wid))


def balance(wid):
    with connect() as c, c.cursor() as cur:
        cur.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,))
        return cur.fetchone()[0]


def header(title):
    global T0
    T0 = time.time()
    print("\n" + "=" * 78 + f"\n=== {title}\n" + "=" * 78, flush=True)


# ---------------------------------------------------------------- Demo A
def demo_a(wid):
    header("Demo A: LOST UPDATE with a naive read-then-write (READ COMMITTED)")
    set_balance(wid, 10000)
    log("", "Halima's wallet starts at 10,000. Two cash-outs of 7,000 arrive at the same moment.")
    s1, s2 = connect(), connect()
    c1, c2 = s1.cursor(), s2.cursor()
    c1.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,)); b1 = c1.fetchone()[0]
    log("S1", f"reads balance = {b1}")
    c2.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,)); b2 = c2.fetchone()[0]
    log("S2", f"reads balance = {b2}")
    if b1 >= 7000:
        c1.execute("UPDATE wallets SET balance = %s WHERE wallet_id = %s", (b1 - 7000, wid))
        log("S1", f"enough money, writes balance = {b1 - 7000}")
    s1.commit(); log("S1", "COMMIT")
    if b2 >= 7000:
        c2.execute("UPDATE wallets SET balance = %s WHERE wallet_id = %s", (b2 - 7000, wid))
        log("S2", f"enough money (based on its OLD read), writes balance = {b2 - 7000}")
    s2.commit(); log("S2", "COMMIT")
    final = balance(wid)
    log("", f"RESULT: 14,000 was paid out but the balance shows {final}. S1's update was LOST.")
    s1.close(); s2.close()


# ---------------------------------------------------------------- Demo B
def demo_b(wid):
    header("Demo B: FIX 1, pessimistic locking with SELECT ... FOR UPDATE")
    set_balance(wid, 10000)
    log("", "Same two 7,000 cash-outs, but each session locks the row before reading it.")
    s1, s2 = connect(), connect()

    def session(conn, who, delay):
        time.sleep(delay)
        cur = conn.cursor()
        t = time.time()
        log(who, "SELECT balance ... FOR UPDATE")
        cur.execute("SELECT balance FROM wallets WHERE wallet_id = %s FOR UPDATE", (wid,))
        b = cur.fetchone()[0]
        waited = time.time() - t
        log(who, f"got the lock after {waited:.2f}s, reads balance = {b}")
        if b >= 7000:
            cur.execute("UPDATE wallets SET balance = balance - 7000 WHERE wallet_id = %s", (wid,))
            log(who, f"writes balance = {b - 7000}")
            time.sleep(1.0)            # simulate slow work while holding the lock
            log(who, "COMMIT (releases the lock)"); conn.commit()
        else:
            conn.rollback(); log(who, "REJECTED: insufficient funds, ROLLBACK")

    th = [threading.Thread(target=session, args=(s1, "S1", 0)),
          threading.Thread(target=session, args=(s2, "S2", 0.2))]
    [t.start() for t in th]; [t.join() for t in th]
    log("", f"RESULT: balance = {balance(wid)}. S2 waited for S1's lock, saw 3,000 and correctly refused.")
    s1.close(); s2.close()


# ---------------------------------------------------------------- Demo C
def demo_c(wid):
    header("Demo C: FIX 2, REPEATABLE READ detects the conflict and the app retries")
    set_balance(wid, 10000)
    s1 = connect(ISOLATION_LEVEL_REPEATABLE_READ)
    s2 = connect(ISOLATION_LEVEL_REPEATABLE_READ)
    c1, c2 = s1.cursor(), s2.cursor()
    c1.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,)); b1 = c1.fetchone()[0]
    log("S1", f"(REPEATABLE READ) reads balance = {b1}")
    c2.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,)); b2 = c2.fetchone()[0]
    log("S2", f"(REPEATABLE READ) reads balance = {b2}")
    c1.execute("UPDATE wallets SET balance = balance - 7000 WHERE wallet_id = %s", (wid,))
    log("S1", "UPDATE balance = balance - 7000")
    s1.commit(); log("S1", "COMMIT")
    try:
        c2.execute("UPDATE wallets SET balance = balance - 7000 WHERE wallet_id = %s", (wid,))
        s2.commit()
        log("S2", "COMMIT (unexpected)")
    except errors.SerializationFailure as e:
        log("S2", f"ERROR {e.pgcode}: {str(e).strip()}")
        s2.rollback(); log("S2", "ROLLBACK, then RETRY in a new transaction")
        c2.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,)); b = c2.fetchone()[0]
        log("S2", f"retry reads balance = {b}")
        if b >= 7000:
            c2.execute("UPDATE wallets SET balance = balance - 7000 WHERE wallet_id = %s", (wid,)); s2.commit()
        else:
            s2.rollback(); log("S2", "REJECTED: insufficient funds")
    log("", f"RESULT: balance = {balance(wid)}. No lost update; the conflict was detected instead of hidden.")
    s1.close(); s2.close()


# ---------------------------------------------------------------- Demo D
def demo_d(wid):
    header("Demo D: NON-REPEATABLE READ, READ COMMITTED vs REPEATABLE READ")
    for name, level in [("READ COMMITTED", ISOLATION_LEVEL_READ_COMMITTED),
                        ("REPEATABLE READ", ISOLATION_LEVEL_REPEATABLE_READ)]:
        set_balance(wid, 10000)
        print(f"--- S1 runs a report at {name}", flush=True)
        s1, s2 = connect(level), connect()
        c1, c2 = s1.cursor(), s2.cursor()
        c1.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,))
        log("S1", f"first read  = {c1.fetchone()[0]}")
        c2.execute("UPDATE wallets SET balance = balance + 5000 WHERE wallet_id = %s", (wid,)); s2.commit()
        log("S2", "deposits 5,000 and COMMITs")
        c1.execute("SELECT balance FROM wallets WHERE wallet_id = %s", (wid,))
        log("S1", f"second read = {c1.fetchone()[0]}  (same transaction)")
        s1.commit(); s1.close(); s2.close()
    log("", "RESULT: READ COMMITTED saw two different values; REPEATABLE READ kept one consistent snapshot.")


# ---------------------------------------------------------------- Demo E
def demo_e(a, b):
    header("Demo E: DEADLOCK from opposite lock order, then the fix")
    set_balance(a, 10000); set_balance(b, 10000)
    s1, s2 = connect(), connect()
    barrier = threading.Barrier(2)

    def naive(conn, who, first, second):
        cur = conn.cursor()
        try:
            cur.execute("UPDATE wallets SET balance = balance - 100 WHERE wallet_id = %s", (first,))
            log(who, f"locked wallet {first}")
            barrier.wait()
            log(who, f"now wants wallet {second} ...")
            cur.execute("UPDATE wallets SET balance = balance + 100 WHERE wallet_id = %s", (second,))
            conn.commit(); log(who, "COMMIT")
        except errors.DeadlockDetected as e:
            log(who, f"ERROR {e.pgcode}: deadlock detected, PostgreSQL killed this transaction")
            conn.rollback()

    print("--- naive code: S1 transfers Ada->Tunde, S2 transfers Tunde->Ada, each locks its source first", flush=True)
    th = [threading.Thread(target=naive, args=(s1, "S1", a, b)),
          threading.Thread(target=naive, args=(s2, "S2", b, a))]
    [t.start() for t in th]; [t.join() for t in th]

    print("--- fixed code: both call transfer_funds(), which always locks the lower wallet_id first", flush=True)
    set_balance(a, 10000); set_balance(b, 10000)
    barrier2 = threading.Barrier(2)

    def safe(conn, who, src, dst):
        cur = conn.cursor()
        barrier2.wait()
        cur.execute("SELECT transfer_funds(%s, %s, 100, 'app', 'Deadlock-safe demo')", (src, dst))
        time.sleep(0.5)
        conn.commit(); log(who, f"transfer {src}->{dst} COMMIT")

    th = [threading.Thread(target=safe, args=(s1, "S1", a, b)),
          threading.Thread(target=safe, args=(s2, "S2", b, a))]
    [t.start() for t in th]; [t.join() for t in th]
    log("", "RESULT: no deadlock. The second session simply waited for the first.")
    s1.close(); s2.close()


# ---------------------------------------------------------------- Demo F
def demo_f():
    header("Demo F: STRESS TEST, 16 threads x 250 random transfers through transfer_funds")
    with connect() as c, c.cursor() as cur:
        cur.execute("""SELECT wallet_id FROM wallets WHERE wallet_type = 'customer'
                       AND daily_limit = 5000000 ORDER BY wallet_id LIMIT 40""")   # tier-3 wallets
        ids = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT sum(balance) FROM wallets WHERE wallet_id = ANY(%s) OR wallet_id = 2", (ids,))
        total_before = cur.fetchone()[0]
    log("", f"40 wallets + fee wallet hold {total_before:,} in total before the test")
    ok, rejected, other = [0], {"insufficient funds": 0, "daily limit": 0}, []
    lock = threading.Lock()

    def worker(seed):
        rnd = random.Random(seed)
        conn = connect()
        cur = conn.cursor()
        for _ in range(250):
            src, dst = rnd.sample(ids, 2)
            amt = Decimal(rnd.choice([500, 2000, 8000, 30000, 120000]))
            try:
                cur.execute("SELECT transfer_funds(%s, %s, %s, 'app', 'Stress test')", (src, dst, amt))
                conn.commit()
                with lock: ok[0] += 1
            except psycopg2.Error as e:
                conn.rollback()
                with lock:
                    reason = next((r for r in rejected if r in str(e)), None)
                    if reason:
                        rejected[reason] += 1
                    else:
                        other.append(str(e).splitlines()[0])
        conn.close()

    start = time.time()
    th = [threading.Thread(target=worker, args=(i,)) for i in range(16)]
    [t.start() for t in th]; [t.join() for t in th]
    secs = time.time() - start
    with connect() as c, c.cursor() as cur:
        cur.execute("SELECT sum(balance) FROM wallets WHERE wallet_id = ANY(%s) OR wallet_id = 2", (ids,))
        total_after = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM wallets WHERE balance < 0 AND wallet_type <> 'system'")
        negatives = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM v_unbalanced_transactions")
        unbalanced = cur.fetchone()[0]
    n_rej = sum(rejected.values())
    log("", f"{ok[0]} transfers committed, {n_rej} correctly rejected "
            f"({rejected['insufficient funds']} insufficient funds, {rejected['daily limit']} daily limit), "
            f"{len(other)} other errors")
    log("", f"{ok[0] + n_rej} attempts in {secs:.1f}s ({(ok[0] + n_rej) / secs:.0f} attempts per second)")
    log("", f"total money before = {total_before:,}   after = {total_after:,}   "
            f"{'CONSERVED' if total_before == total_after else 'NOT CONSERVED'}")
    log("", f"negative customer balances = {negatives}, unbalanced ledger transactions = {unbalanced}")
    if other:
        log("", f"first unexpected error: {other[0]}")


if __name__ == "__main__":
    halima, ada, tunde = wallet("Halima"), wallet("Ada"), wallet("Tunde")
    demo_a(halima)
    demo_b(halima)
    demo_c(halima)
    demo_d(wallet("Ngozi"))
    demo_e(ada, tunde)
    demo_f()
