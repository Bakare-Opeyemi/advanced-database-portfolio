# Advanced Database Systems Portfolio (MIT 8103)

| | |
|---|---|
| Student | Abdullateef Opeyemi Bakare |
| Programme | MSc Information Technology, Miva Open University (September 2026 cohort) |
| Course | MIT 8103 Advanced Database Systems, First Semester Continuous Assessment (40 marks) |
| Case study | MoniWallet, a simulated mobile money operator |

## Case study: MoniWallet

- **Organisation:** MoniWallet, a simulated mobile money operator in Nigeria. It is not a real company, and all data in this repository is made up.
- **Nature of the business:** customers hold a digital wallet linked to their phone number. They fund it from a bank account or an agent, send money to other wallets and banks, pay bills (electricity, TV, airtime) and withdraw cash at agents.
- **Users of the database:** customers (mobile app and USSD), agents, customer support staff, compliance officers (KYC and anti-money-laundering checks), finance and reconciliation staff, and auditors working for the regulator.
- **Major data:** customers and KYC records, wallets and balances, transactions (transfers, deposits, withdrawals, bill payments, reversals), a double-entry ledger, billers, agents, devices and login sessions, and audit logs.
- **Key operations:** register and verify a customer, fund a wallet, transfer between wallets, pay a bill, reverse a failed transaction, show a balance and a statement, flag suspicious transactions, and produce daily reconciliation and audit reports.
- **Why it fits this portfolio:** transfers need strict ACID transactions (Portfolio 3), statements and reports need fast queries and good indexes (Portfolio 2), device and session data fit a NoSQL store (Portfolio 4), and a national payment service needs replication and high availability (Portfolio 5).

## Portfolio progress

| Part | Topic | Marks | Folder | Status |
|---|---|---|---|---|
| 1 | Database design and modelling | 7 | [portfolio-1-database-design](portfolio-1-database-design/) | Done, except PNG screenshots (text evidence is in `screenshots/`) |
| 2 | Query processing and optimisation | 7 | [portfolio-2-query-optimisation](portfolio-2-query-optimisation/) | Not started |
| 3 | Transactions and concurrency | 7 | [portfolio-3-transactions-concurrency](portfolio-3-transactions-concurrency/) | Not started |
| 4 | NoSQL and advanced data models | 7 | [portfolio-4-nosql](portfolio-4-nosql/) | Not started |
| 5 | Distributed and cloud database exercise | 6 | [portfolio-5-distributed-cloud](portfolio-5-distributed-cloud/) | Not started |
| Final | Documentation and technical reflection | 6 | [docs](docs/) | Not started |

## Tools

- PostgreSQL (already installed on this computer) for Portfolios 1, 2, 3 and 5
- MongoDB for Portfolio 4 (set up when that part starts)

## How to run

Create the database once:

```bash
createdb moniwallet
```

Then open it:

```bash
psql moniwallet
```

## Submission file names

The LMS asks for this naming, with no spaces:

- Folder: `Surname_Firstname_StudentID`
- Files: `Surname_Firstname_StudentID_DocumentType`, for example `Surname_Firstname_StudentID_README.txt` and `Surname_Firstname_StudentID_Documentation.pdf`

## AI use declaration

| Date | Tool | What it was used for | How I checked the output |
|---|---|---|---|
| 2026-10-24 | Claude Code | Help drafting the Portfolio 1 database design | Ran the SQL and reviewed it |

## References

Add every source, dataset, library and tool you use here.
