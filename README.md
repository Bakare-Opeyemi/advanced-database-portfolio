# Advanced Database Systems Portfolio (MIT 8103)

| | |
|---|---|
| Student | Abdullateef Opeyemi Bakare |
| Programme | MSc Information Technology, Miva Open University (September 2026 cohort) |
| Course | MIT 8103 Advanced Database Systems, First Semester Continuous Assessment (40 marks) |
| Case study | OpeLat Wallet, a simulated mobile money operator |

## Case study: OpeLat Wallet

- **Organisation:** OpeLat Wallet, a simulated mobile money operator in Nigeria. It is not a real company, and all data in this repository is made up.
- **Nature of the business:** customers hold a digital wallet linked to their phone number. They fund it from a bank account or an agent, send money to other wallets and banks, pay bills (electricity, TV, airtime) and withdraw cash at agents.
- **Users of the database:** customers (mobile app and USSD), agents, customer support staff, compliance officers (KYC and anti-money-laundering checks), finance and reconciliation staff, and auditors working for the regulator.
- **Major data:** customers and KYC records, wallets and balances, transactions (transfers, deposits, withdrawals, bill payments, reversals), a double-entry ledger, billers, agents, devices and login sessions, and audit logs.
- **Key operations:** register and verify a customer, fund a wallet, transfer between wallets, pay a bill, reverse a failed transaction, show a balance and a statement, flag suspicious transactions, and produce daily reconciliation and audit reports.
- **Why it fits this portfolio:** transfers need strict ACID transactions (Portfolio 3), statements and reports need fast queries and good indexes (Portfolio 2), device and session data fit a NoSQL store (Portfolio 4), and a national payment service needs replication and high availability (Portfolio 5).

## Portfolio progress

| Part | Topic | Marks | Folder | Status | Key evidence |
|---|---|---|---|---|---|
| 1 | Database design and modelling | 7 | [portfolio-1-database-design](portfolio-1-database-design/) | Done | 10-table schema, ER diagram, 9 constraint tests, 3NF explanation |
| 2 | Query processing and optimisation | 7 | [portfolio-2-query-optimisation](portfolio-2-query-optimisation/) | Done | 450,000 transactions, 8 queries, plans before/after, Q1 62 ms to 0.033 ms |
| 3 | Transactions and concurrency | 7 | [portfolio-3-transactions-concurrency](portfolio-3-transactions-concurrency/) | Done | Commit/rollback/savepoint, lost update and 3 fixes, deadlock, 16-thread stress test |
| 4 | NoSQL and advanced data models | 7 | [portfolio-4-nosql](portfolio-4-nosql/) | Done | MongoDB document, key-value/TTL, time-series and graph models, 8 queries |
| 5 | Distributed and cloud database exercise | 6 | [portfolio-5-distributed-cloud](portfolio-5-distributed-cloud/) | Done | PostgreSQL replication and failover, MongoDB election in 0.6 s, partitioning, CAP |
| Final | Documentation and technical reflection | 6 | [docs](docs/) | Done | 3-page summary PDF |

## Tools

- PostgreSQL 14.15 (Homebrew) for Portfolios 1, 2, 3 and 5
- MongoDB 7.0.2 and mongosh for Portfolios 4 and 5 (run as local processes; Docker was not used)
- Python 3 with psycopg2 for the benchmark and concurrency scripts, matplotlib and Pillow for diagrams and output images
- [`tools/`](tools/): scripts that draw the ER and architecture diagrams, and turn captured terminal output into the PNG images in each `screenshots/` folder (the text in every image is real output saved in that portfolio's `evidence/` folder)

## How to run everything

One command rebuilds the database, reruns every experiment, and regenerates all evidence files and screenshots (about 6 minutes):

```bash
./tools/run_all.sh
```

The same steps, one by one:

```bash
createdb opelatwallet
psql opelatwallet -f portfolio-1-database-design/schema.sql
psql opelatwallet -f portfolio-1-database-design/constraint_tests.sql
psql opelatwallet -f portfolio-2-query-optimisation/load_data.sql
python3 portfolio-2-query-optimisation/run_benchmark.py
psql opelatwallet -f portfolio-3-transactions-concurrency/transfer_function.sql
psql opelatwallet -f portfolio-3-transactions-concurrency/demo_commit_rollback.sql
python3 portfolio-3-transactions-concurrency/concurrency_demos.py
psql opelatwallet -f portfolio-3-transactions-concurrency/transfer_function.sql   # reset demo wallets
./portfolio-5-distributed-cloud/start_mongo_replicaset.sh
psql opelatwallet -f portfolio-4-nosql/export_from_postgres.sql
./portfolio-4-nosql/setup_mongo.sh
mongosh "mongodb://127.0.0.1:27031,127.0.0.1:27032,127.0.0.1:27033/opelatwallet?replicaSet=olwrs" portfolio-4-nosql/queries.js
./portfolio-5-distributed-cloud/pg_replication_demo.sh
./portfolio-5-distributed-cloud/mongo_failover_demo.sh
psql opelatwallet -f portfolio-5-distributed-cloud/partitioning_demo.sql
```

## Submission file names

The LMS asks for this naming, with no spaces:

- Folder: `Surname_Firstname_StudentID`
- Files: `Surname_Firstname_StudentID_DocumentType`, for example `Surname_Firstname_StudentID_README.txt` and `Surname_Firstname_StudentID_Documentation.pdf`

## AI use declaration

| Date | Tool | What it was used for | How the output was checked |
|---|---|---|---|
| 21 Oct to 15 Nov 2026 | Claude (Anthropic) | Writing the scripts, generating the synthetic data, running the experiments, and drafting the documentation | Every script was run on PostgreSQL 14 and MongoDB 7; all figures come from the saved output in `evidence/`, and the built-in integrity checks pass. I reviewed the work and can explain every part of it. |

## References

- PostgreSQL Global Development Group (2024) *PostgreSQL 14 Documentation*: chapters on Indexes (GIN, BRIN, partial indexes), Concurrency Control (MVCC, isolation levels, explicit locking), Table Partitioning and High Availability (streaming replication, synchronous replication). https://www.postgresql.org/docs/14/
- MongoDB, Inc. (2024) *MongoDB Manual 7.0*: Data Modeling, Schema Validation, Time Series Collections, TTL Indexes, `$graphLookup`, Replication and Sharding. https://www.mongodb.com/docs/v7.0/
- Elmasri, R. and Navathe, S. B. (2016) *Fundamentals of Database Systems*. 7th edn. Pearson.
- Kleppmann, M. (2017) *Designing Data-Intensive Applications*. O'Reilly Media.
- Brewer, E. (2012) "CAP twelve years later: How the 'rules' have changed", *Computer*, 45(2), pp. 23-29.
- Federal Republic of Nigeria (2023) *Nigeria Data Protection Act, 2023*.
- Miva Open University (2026) *MIT 8103 Advanced Database Systems* course materials, Weeks 1 to 6.
- Libraries: psycopg2 (LGPL), matplotlib, Pillow. All data in this repository is generated; no real customer data is used.
