# Portfolio 1: Database Design and Modelling (7 marks)

## What the brief asks for

Chosen case study description, ER diagram, relational schema, keys, constraints, and a normalisation explanation.

## Checklist

- [x] Case study description (see the main README)
- [x] ER diagram: export an image to `er-diagram.png` and keep the source file (for example draw.io or dbdiagram.io)
- [x] Relational schema as SQL in `schema.sql` (tables, data types, primary and foreign keys)
- [x] Constraints: NOT NULL, UNIQUE, CHECK (for example no negative balances), foreign keys with ON DELETE rules
- [x] Normalisation explanation (`normalisation.md`): show how the design reaches 3NF, and say where you chose not to normalise and why
- [ ] Screenshot of the schema created in PostgreSQL (for example `\dt` and `\d table_name`) in `screenshots/`
  - Text evidence is done: [screenshots/schema-evidence.txt](screenshots/schema-evidence.txt) has the real `\dt` and `\d` output.
  - **To do (user):** if the brief needs images, take PNG screenshots of `\dt` and `\d customer`, `\d wallet`, `\d transaction`, `\d ledger_entry` in a terminal and save them in `screenshots/`. Then tick this item.

## My work

### What the database is for

MoniWallet is a made-up mobile money service (see the case study in the main README). Customers keep money in a wallet, send it to other wallets, pay bills and cash in or out at agents. So the database must never lose money, never let a balance go below zero, and keep a clear record that auditors can trust.

### Entities

I started from the things the business talks about, and made one table for each:

| Table | What one row is |
|---|---|
| `customer` | A person who uses MoniWallet |
| `kyc_record` | One identity check (NIN, BVN, passport, licence) for a customer |
| `wallet` | A pot of money owned by a customer, in one currency |
| `agent` | A cash-in and cash-out point |
| `biller` | A company that receives bill payments |
| `transaction` | One money movement (transfer, deposit, withdrawal, bill payment, reversal) |
| `ledger_entry` | One debit or credit line on one wallet, for one transaction |
| `device` | A phone or other device a customer logs in from |
| `session` | One login on the app or USSD |
| `audit_log` | A record of who did what, for auditors |

The full picture with all relationships is in the ER diagram: [er-diagram.png](er-diagram.png) (source: [er-diagram.md](er-diagram.md) and [er-diagram.dbml](er-diagram.dbml)).

### Keys

- **Primary keys:** every table has a simple number key (`BIGSERIAL`), for example `customer_id`. These never change, so other tables can point to them safely. `BIGINT` leaves room for many millions of transactions.
- **Natural keys as UNIQUE:** real-world values that must not repeat are kept as `UNIQUE` constraints, not as the primary key. Examples: a customer's `phone_number`, a KYC `(id_type, id_number)`, one wallet per `(customer_id, currency)`, and one ledger line per `(transaction_id, wallet_id, direction)`.
- **Foreign keys:** every link in the ER diagram is a foreign key, for example `wallet.customer_id` points to `customer`.

### Constraints

I put the business rules inside the database, so a bug in the app cannot break them:

- `NOT NULL` on every column that must always have a value.
- `CHECK (balance >= 0)` on `wallet` and `CHECK (balance_after >= 0)` on `ledger_entry`: no overdrafts.
- `CHECK (amount > 0)`: no zero or negative payments.
- `CHECK` lists for status and type columns, so only known values are allowed.
- Rules across columns in `transaction`: a transfer needs two different wallets, every transaction touches at least one wallet, and only a reversal can point to another transaction (`reverses_id`).
- `ON DELETE` rules chosen on purpose:
  - `RESTRICT` for money data (`wallet`, `transaction`, `ledger_entry`). You cannot delete a wallet that has history. Money records must stay.
  - `CASCADE` for data that only makes sense with its customer (`kyc_record`, `device`, `session`).
  - `SET NULL` where the record must stay but the link can go (`audit_log`, and `agent` or `biller` on a transaction).

### Ledger design

Money is tracked in two places that must agree:

1. `transaction` says what happened (for example "transfer 10,000 from wallet 1 to wallet 4").
2. `ledger_entry` says how each wallet changed: `D` (money out) or `C` (money in), with the amount and the balance after.

A transfer writes two ledger lines, one debit and one credit. A deposit, withdrawal or bill payment touches one customer wallet, so it writes one line. A failed transaction writes no lines. A reversal is a new transaction that points back to the old one, so history is never edited or deleted.

The ledger is the source of truth. `wallet.balance` is a stored copy so balances show fast. This is a small, planned break from full normalisation. [normalisation.md](normalisation.md) explains why, and gives a reconciliation query that checks every balance against the ledger.

### Normalisation

[normalisation.md](normalisation.md) walks from one messy spreadsheet row to 1NF, 2NF and 3NF. It also lists the three columns I chose to keep even though they could be worked out (`wallet.balance`, `ledger_entry.balance_after`, `transaction.flagged`), and why.

### Testing the design

I ran [schema.sql](schema.sql) and [sample-data.sql](sample-data.sql) on a throwaway PostgreSQL 14 database. Both ran with no errors. The output of `\dt` and `\d` for the main tables, the row counts, and the reconciliation check (0 rows, so every balance matches the ledger) are in [screenshots/schema-evidence.txt](screenshots/schema-evidence.txt).

## How to run

```bash
psql moniwallet -f portfolio-1-database-design/schema.sql
psql moniwallet -f portfolio-1-database-design/sample-data.sql
```
