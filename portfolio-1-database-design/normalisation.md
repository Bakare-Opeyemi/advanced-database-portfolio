# Normalisation of the MoniWallet design

This note shows how the MoniWallet schema (`schema.sql`) reaches third normal form (3NF). It then says where the design chooses not to fully normalise, and why. The names and numbers match `sample-data.sql`.

## Starting point: one unnormalised record

Imagine a support officer keeps each customer's activity in one spreadsheet row:

| customer | phone | wallet | balance | transactions |
|---|---|---|---|---|
| Chiamaka Obi | 08031110002 | W2 (NGN) | 25,000 | "T5 bill_payment 5,000 Ikeja Electric (electricity); T8 transfer 3,000 to W1" |

This causes three problems:

- **Update problem:** a biller's category is typed again in every row that pays it. Changing it means finding every copy.
- **Insert problem:** a new biller cannot be stored until someone pays it.
- **Delete problem:** if the only payment to a biller is deleted, we lose the biller too.

## First normal form (1NF)

1NF means every cell holds one value and there are no repeating groups.

The "transactions" cell holds a list. We split it so each transaction is its own row:

| customer | phone | wallet | balance | txn | type | amount | biller | biller category | other wallet |
|---|---|---|---|---|---|---|---|---|---|
| Chiamaka Obi | 08031110002 | W2 | 25,000 | T5 | bill_payment | 5,000 | Ikeja Electric | electricity | |
| Chiamaka Obi | 08031110002 | W2 | 25,000 | T8 | transfer | 3,000 | | | W1 |

Every cell now holds one value. The key is (wallet, txn).

## Second normal form (2NF)

2NF means every non-key column depends on the **whole** key, not just part of it.

- `customer`, `phone` and `balance` depend only on the wallet (part of the key). They move out to `wallet` and `customer`.
- `type`, `amount`, `biller` and `other wallet` depend only on the txn (the other part). They move to `transaction`.

Each table now gets a single primary key, for example `transaction_id`.

## Third normal form (3NF)

3NF means no non-key column depends on another non-key column (no "transitive" dependency).

- In `transaction`, `biller category` depends on the biller, not on the transaction. So it moves to `biller`.
- In `wallet`, `phone` depends on the customer, not on the wallet. So it stays only in `customer`, and `wallet` keeps a `customer_id` foreign key.
- The debit and credit lines of each transaction go into `ledger_entry`, one row per wallet and direction. Its natural key (`transaction_id`, `wallet_id`, `direction`) is kept as a `UNIQUE` constraint.

The result is the schema in `schema.sql`:

```
customer     (customer_id, full_name, phone_number, ...)
wallet       (wallet_id, customer_id -> customer, currency, balance, ...)
biller       (biller_id, biller_name, category)
agent        (agent_id, agent_name, phone_number, location, ...)
transaction  (transaction_id, type, from_wallet_id, to_wallet_id,
              agent_id, biller_id, amount, status, flagged, ...)
ledger_entry (entry_id, transaction_id, wallet_id, direction,
              amount, balance_after, ...)
```

Each fact is now stored once. A biller can exist before anyone pays it, and a phone number change touches one row.

## Where the design chooses not to fully normalise

Some columns can be worked out from other data. Strict 3NF would drop them. MoniWallet keeps them on purpose.

| Column | Could be worked out from | Why it is kept |
|---|---|---|
| `wallet.balance` | Credits minus debits in `ledger_entry` for that wallet | Showing a balance is the most common action. Adding up every ledger row each time would be slow. The `CHECK (balance >= 0)` also blocks overdrafts inside the database, and that needs a stored number. |
| `ledger_entry.balance_after` | Running total of earlier ledger rows for the wallet | A statement can show the balance after each payment without adding up the whole history. It also gives auditors a fixed record of the balance at that moment. |
| `transaction.flagged` | Fraud rules applied to the transaction and its history | The rules change over time. Storing the result keeps a record of what was flagged then, and lets compliance staff filter flagged rows fast. |

**How the copies are kept correct.** The ledger is the source of truth. The stored balance and `balance_after` are only changed inside the same database transaction that writes the ledger rows (Portfolio 3 covers this). A daily reconciliation query checks that they still agree:

```sql
SELECT w.wallet_id, w.balance, COALESCE(SUM(
         CASE l.direction WHEN 'C' THEN l.amount ELSE -l.amount END), 0) AS ledger_balance
FROM wallet w
LEFT JOIN ledger_entry l ON l.wallet_id = w.wallet_id
GROUP BY w.wallet_id, w.balance
HAVING w.balance <> COALESCE(SUM(
         CASE l.direction WHEN 'C' THEN l.amount ELSE -l.amount END), 0);
```

If this returns no rows, every wallet balance matches its ledger. `sample-data.sql` is built so that it returns no rows.
