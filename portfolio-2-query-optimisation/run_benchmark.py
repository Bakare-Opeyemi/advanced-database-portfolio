"""Portfolio 2 benchmark: run every query in queries.sql before and after indexes.sql.

For each query it:
  * runs EXPLAIN (ANALYZE, BUFFERS) 7 times and keeps the median execution time,
  * saves the last plan to evidence/plans_before/ or evidence/plans_after/,
  * saves the query result (first 15 rows) to evidence/results/.
Finally it writes evidence/benchmark_results.md with the before/after table.

Usage (from the repository root, after load_data.sql):
    python3 portfolio-2-query-optimisation/run_benchmark.py
"""
import os
import re
import statistics
import psycopg2

HERE = os.path.dirname(os.path.abspath(__file__))
EV = os.path.join(HERE, "evidence")
RUNS = 7
DROP = """DROP INDEX IF EXISTS olw.ix_ledger_wallet_time, olw.ix_customers_phone_trgm, olw.ix_txn_pending,
          olw.ix_txn_created_brin, olw.ix_txn_bill_time;"""


def load_queries():
    text = open(os.path.join(HERE, "queries.sql")).read()
    parts = re.split(r"^-- @(Q\d+): (.*)$", text, flags=re.M)
    return [(parts[i], parts[i + 1].strip(), parts[i + 2].strip()) for i in range(1, len(parts), 3)]


def measure(cur, sql):
    times, plan = [], ""
    for _ in range(RUNS):
        cur.execute("EXPLAIN (ANALYZE, BUFFERS) " + sql)
        plan = "\n".join(r[0] for r in cur.fetchall())
        times.append(float(re.search(r"Execution Time: ([\d.]+) ms", plan).group(1)))
    return statistics.median(times), plan


def main():
    os.makedirs(os.path.join(EV, "plans_before"), exist_ok=True)
    os.makedirs(os.path.join(EV, "plans_after"), exist_ok=True)
    os.makedirs(os.path.join(EV, "results"), exist_ok=True)
    conn = psycopg2.connect(dbname="opelatwallet")
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("SET max_parallel_workers_per_gather = 0")   # one core, so timings compare fairly
    queries = load_queries()

    cur.execute(DROP)
    cur.execute("ANALYZE olw.transactions; ANALYZE olw.ledger_entries; ANALYZE olw.customers;")
    before = {}
    for qid, title, sql in queries:
        before[qid] = measure(cur, sql)
        open(os.path.join(EV, "plans_before", f"{qid}.txt"), "w").write(f"-- {qid}: {title}\n{sql}\n\n{before[qid][1]}\n")
        cur.execute(sql)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        with open(os.path.join(EV, "results", f"{qid}.txt"), "w") as f:
            f.write(f"-- {qid}: {title}\n-- {len(rows)} row(s) returned, first 15 shown\n")
            f.write(" | ".join(cols) + "\n")
            for r in rows[:15]:
                f.write(" | ".join(str(v) for v in r) + "\n")
        print(f"before {qid}: {before[qid][0]:.3f} ms")

    cur.execute(open(os.path.join(HERE, "indexes.sql")).read())
    after = {}
    for qid, title, sql in queries:
        after[qid] = measure(cur, sql)
        open(os.path.join(EV, "plans_after", f"{qid}.txt"), "w").write(f"-- {qid}: {title}\n{sql}\n\n{after[qid][1]}\n")
        print(f"after  {qid}: {after[qid][0]:.3f} ms")

    def scan_type(plan):
        """List every scan node in the plan, e.g. 'Seq Scan on ledger_entries; Index Scan using transactions_pkey'."""
        found = []
        for m in re.finditer(r"(Index Only Scan|Bitmap Index Scan|Bitmap Heap Scan|Index Scan|Seq Scan)"
                             r"(?: Backward)?(?: using (\S+))? on (\S+)", plan):
            label = f"{m.group(1)} " + (m.group(2) if m.group(2) else f"on {m.group(3)}")
            if label not in found:
                found.append(label)
        return "<br>".join(found) or "-"

    cur.execute("""SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
                   FROM pg_stat_user_indexes WHERE schemaname = 'olw' AND indexrelname LIKE 'ix_%'
                   ORDER BY indexrelname""")
    sizes = cur.fetchall()
    cur.execute("SELECT pg_size_pretty(pg_relation_size('olw.transactions'))")
    table_size = cur.fetchone()[0]

    with open(os.path.join(EV, "benchmark_results.md"), "w") as f:
        f.write(f"# Benchmark results\n\nMedian of {RUNS} runs of `EXPLAIN (ANALYZE, BUFFERS)`, PostgreSQL 14, one worker, warm cache.\n\n")
        f.write("| Query | Before (ms) | After (ms) | Speed-up | Plan before | Plan after |\n|---|---|---|---|---|---|\n")
        for qid, title, _ in queries:
            b, a = before[qid][0], after[qid][0]
            f.write(f"| {qid}: {title} | {b:.3f} | {a:.3f} | {b / a:.1f}x | {scan_type(before[qid][1])} | {scan_type(after[qid][1])} |\n")
        f.write(f"\n## Index sizes (transactions table = {table_size})\n\n| Index | Size |\n|---|---|\n")
        for name, size in sizes:
            f.write(f"| {name} | {size} |\n")
    print(open(os.path.join(EV, "benchmark_results.md")).read())


if __name__ == "__main__":
    main()
