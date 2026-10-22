# Portfolio 1: Database Design and Modelling (7 marks)

## What the brief asks for

Chosen case study description, ER diagram, relational schema, keys, constraints, and a normalisation explanation.

## Checklist

- [ ] Case study description (see the main README)
- [x] ER diagram: export an image to `er-diagram.png` and keep the source file (for example draw.io or dbdiagram.io)
- [x] Relational schema as SQL in `schema.sql` (tables, data types, primary and foreign keys)
- [x] Constraints: NOT NULL, UNIQUE, CHECK (for example no negative balances), foreign keys with ON DELETE rules
- [ ] Normalisation explanation: show how the design reaches 3NF, and say where you chose not to normalise and why
- [ ] Screenshot of the schema created in PostgreSQL (for example `\dt` and `\d table_name`) in `screenshots/`

## My work

Write here how you designed the database and why.

## How to run

```bash
psql moniwallet -f portfolio-1-database-design/schema.sql
```
