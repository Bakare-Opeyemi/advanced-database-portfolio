# Portfolio 4: NoSQL and Advanced Data Models (7 marks)

## What the brief asks for

A NoSQL model based on the same case study, a document, key-value, column or graph example, implementation evidence, and an explanation of why it suits the data.

## Checklist

- [ ] Choose the NoSQL type and the MoniWallet data it holds (for example customer devices and login sessions as MongoDB documents)
- [ ] Data model with a sample document
- [ ] Scripts that create the collection, insert sample data and run 3 or more queries (`mongosh` scripts in this folder)
- [ ] Index on the field you search most
- [ ] Explanation: why this data fits NoSQL better than the relational design, and what you give up
- [ ] Screenshots in `screenshots/`

## How to run

Start MongoDB when you reach this part. The simplest way is one Docker container:

```bash
docker run -d --name moniwallet-mongo -p 27017:27017 mongo:7
mongosh moniwallet
```

## My work

Write here how you modelled the data and why.
