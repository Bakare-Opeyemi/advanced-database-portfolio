"""Turn the saved evidence files into the PNG images in each screenshots/ folder.

Every image is drawn from real output saved in an evidence/ folder (see render_output.py).
Usage (from the repository root): python3 tools/make_screenshots.py
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENDER = os.path.join(ROOT, "tools", "render_output.py")


def render(src_lines, dst, title):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write("\n".join(src_lines))
    subprocess.run([sys.executable, RENDER, f.name, os.path.join(ROOT, dst), title], check=True,
                   stdout=subprocess.DEVNULL)
    os.unlink(f.name)


def read(path):
    return open(os.path.join(ROOT, path), encoding="utf-8").read().splitlines()


def between(lines, start, end=None):
    """Lines from the first line containing `start` up to (not including) the first later line containing `end`."""
    i = next(n for n, l in enumerate(lines) if start in l)
    j = next((n for n, l in enumerate(lines[i + 1:], i + 1) if end and end in l), len(lines))
    while j > i and not lines[j - 1].strip():
        j -= 1
    return lines[i:j]


# ---------- Portfolio 1
p = "portfolio-1-database-design/"
ct = [l.split(": ", 1)[1] if l.startswith("psql:") else l
      for l in read(p + "evidence/constraint_tests_output.txt") if "===" in l or "ERROR" in l]
render(ct, p + "screenshots/constraint_tests.png", "psql opelatwallet -f constraint_tests.sql")
render(read(p + "evidence/schema_in_postgres.txt")[:46], p + "screenshots/schema_tables.png",
       "psql opelatwallet: \\dt olw.*  and  \\d olw.wallets")

# ---------- Portfolio 2
p = "portfolio-2-query-optimisation/"
render(read(p + "evidence/plans_before/Q1.txt"), p + "screenshots/q1_plan_before.png", "Q1 statement: EXPLAIN (ANALYZE, BUFFERS) BEFORE index")
render(read(p + "evidence/plans_after/Q1.txt"), p + "screenshots/q1_plan_after.png", "Q1 statement: EXPLAIN (ANALYZE, BUFFERS) AFTER ix_ledger_wallet_time")
render(read(p + "evidence/plans_before/Q3.txt"), p + "screenshots/q3_plan_before.png", "Q3 stuck pending: BEFORE")
render(read(p + "evidence/plans_after/Q3.txt"), p + "screenshots/q3_plan_after.png", "Q3 stuck pending: AFTER partial index")
render(read(p + "evidence/brin_vs_btree_output.txt"), p + "screenshots/brin_vs_btree.png", "psql opelatwallet -f brin_vs_btree.sql")
render(read(p + "evidence/results/Q5.txt"), p + "screenshots/q5_aml_result.png", "Q5 AML result")

# ---------- Portfolio 3
p = "portfolio-3-transactions-concurrency/"
cd = read(p + "evidence/concurrency_demos_output.txt")
for key, end, name, title in [
    ("Demo A", "Demo B", "demo_a_lost_update", "python3 concurrency_demos.py  (Demo A)"),
    ("Demo B", "Demo C", "demo_b_for_update", "Demo B: SELECT ... FOR UPDATE"),
    ("Demo C", "Demo D", "demo_c_repeatable_read", "Demo C: REPEATABLE READ + retry"),
    ("Demo D", "Demo E", "demo_d_isolation", "Demo D: isolation levels"),
    ("Demo E", "Demo F", "demo_e_deadlock", "Demo E: deadlock and fix"),
    ("Demo F", None, "demo_f_stress", "Demo F: stress test")]:
    block = between(cd, key, end)
    if end and block and block[-1].startswith("="):
        block = block[:-1]
    render(block, p + f"screenshots/{name}.png", title)
cr = read(p + "evidence/commit_rollback_output.txt")
render(cr[:60], p + "screenshots/commit_rollback.png", "psql opelatwallet -f demo_commit_rollback.sql")
render(cr[60:], p + "screenshots/savepoint.png", "psql opelatwallet -f demo_commit_rollback.sql (continued)")

# ---------- Portfolio 4
p = "portfolio-4-nosql/"
q = [l for l in read(p + "evidence/queries_output.txt") if not l.startswith('{"_id":12345')]
render(between(q, "N1:", "N3:"), p + "screenshots/n1_n2_index.png", "mongosh opelatwallet queries.js (N1, N2)")
render(between(q, "N3:", "N4:"), p + "screenshots/n3_fraud.png", "N3: failed-PIN bursts (time series + $lookup)")
render(between(q, "N4:", "N5:"), p + "screenshots/n4_timeseries.png", "N4: logins per channel per day")
render(between(q, "N5:"), p + "screenshots/n5_to_n8.png", "N5 graph, N6 validation, N7 array update, N8 TTL")
render(read(p + "evidence/timeseries_bucket_experiment_output.txt"), p + "screenshots/timeseries_buckets.png",
       "mongosh timeseries_bucket_experiment.js")

# ---------- Portfolio 5
p = "portfolio-5-distributed-cloud/"
pg = read(p + "evidence/pg_replication_output.txt")
render(between(pg, "STEP 1", "STEP 4"), p + "screenshots/pg_steps_1_3.png", "./pg_replication_demo.sh (steps 1-3)")
render(between(pg, "STEP 4"), p + "screenshots/pg_steps_4_6.png", "./pg_replication_demo.sh (steps 4-6)")
render(read(p + "evidence/mongo_failover_output.txt"), p + "screenshots/mongo_failover.png", "./mongo_failover_demo.sh")
part = [l for l in read(p + "evidence/partitioning_output.txt")
        if not l.startswith(("CREATE", "DO", "SET", "INSERT", "DROP", "ANALYZE")) and "NOTICE" not in l]
render(part, p + "screenshots/partitioning.png", "psql opelatwallet -f partitioning_demo.sql")
print("all screenshots rebuilt")
