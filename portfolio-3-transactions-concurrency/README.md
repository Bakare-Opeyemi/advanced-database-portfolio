# Portfolio 3: Transactions and Concurrency (7 marks)

## What the brief asks for

Transaction examples showing commit, rollback, isolation, a concurrency issue or control mechanism, and screenshots or output evidence.

## Checklist

- [ ] A wallet transfer done as one transaction that commits
- [ ] A failing transfer that rolls back (for example not enough balance), with the balances checked before and after
- [ ] An isolation level demo (READ COMMITTED compared with REPEATABLE READ or SERIALIZABLE)
- [ ] A concurrency problem with two sessions side by side (for example a lost update on one wallet)
- [ ] The fix (for example `SELECT ... FOR UPDATE`, or SERIALIZABLE with a retry)
- [ ] Screenshots of both sessions in `screenshots/`

## My work

Write here what each example shows and what you learned.
