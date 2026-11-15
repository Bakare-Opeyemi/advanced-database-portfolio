# Benchmark results

Median of 7 runs of `EXPLAIN (ANALYZE, BUFFERS)`, PostgreSQL 14, one worker, warm cache.

| Query | Before (ms) | After (ms) | Speed-up | Plan before | Plan after |
|---|---|---|---|---|---|
| Q1: Customer statement (last 20 ledger lines for one wallet) | 53.095 | 0.035 | 1517.0x | Seq Scan on ledger_entries<br>Index Scan transactions_pkey | Index Scan ix_ledger_wallet_time<br>Index Scan transactions_pkey |
| Q2: Support agent finds a caller from the last 6 digits of their phone number | 3.630 | 0.221 | 16.4x | Seq Scan on customers | Bitmap Heap Scan on customers<br>Bitmap Index Scan on ix_customers_phone_trgm |
| Q3: Stuck transactions still pending after 15 minutes (operations alert) | 36.551 | 0.004 | 9137.8x | Seq Scan on transactions | Index Scan ix_txn_pending |
| Q4: Daily volume report for October 2026 by type and channel (finance) | 52.566 | 24.353 | 2.2x | Seq Scan on transactions | Bitmap Heap Scan on transactions<br>Bitmap Index Scan on ix_txn_created_brin |
| Q5: AML check: wallets that sent 3 or more transfers, or 300,000 or more in total, on one day in the last 7 days | 47.879 | 14.362 | 3.3x | Seq Scan on transactions<br>Seq Scan on wallets<br>Index Scan customers_pkey | Bitmap Heap Scan on transactions<br>Bitmap Index Scan on ix_txn_created_brin<br>Seq Scan on wallets<br>Index Scan customers_pkey |
| Q6: Nightly reconciliation: wallets whose stored balance differs from the ledger | 410.685 | 428.785 | 1.0x | Seq Scan on ledger_entries<br>Seq Scan on wallets | Seq Scan on ledger_entries<br>Seq Scan on wallets |
| Q7: Top billers by value in October 2026 | 41.355 | 2.732 | 15.1x | Seq Scan on transactions<br>Seq Scan on billers | Index Only Scan ix_txn_bill_time<br>Seq Scan on billers |
| Q8: Partner bank looks up a transaction by its reference | 0.004 | 0.005 | 0.8x | Index Scan transactions_reference_key | Index Scan transactions_reference_key |

## Index sizes (transactions table = 63 MB)

| Index | Size |
|---|---|
| ix_aml_txn | 320 kB |
| ix_customers_phone_trgm | 1480 kB |
| ix_kyc_customer | 560 kB |
| ix_ledger_txn | 33 MB |
| ix_ledger_wallet_time | 41 MB |
| ix_txn_bill_time | 3592 kB |
| ix_txn_created_brin | 24 kB |
| ix_txn_pending | 16 kB |
