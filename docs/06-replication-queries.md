# Replication queries

Sync generates a `REPLICATE` statement for each task. You can let it do that, or you can write the statement yourself. Writing it yourself is how you control primary keys, destination data types and incremental filtering, and it is the difference between a pipeline that holds up and one that quietly accumulates duplicates.

Runnable examples: [`examples/sql/replicate-primary-keys.sql`](../examples/sql/replicate-primary-keys.sql).

## Why primary keys matter

The destination primary key is what Sync uses to decide whether an incoming row is an insert or an update. Get it wrong and you get:

- Duplicate rows, when the key is not actually unique
- Failed writes, when the key is unique in the source but not in the extract you defined
- Poor upsert performance, when the destination has no usable index
- Broken incremental replication, because there is no stable identity to match on

If the source reports a natural key, Sync uses it. When the source does not — and many APIs, views and custom queries do not — you have to declare one.

## Declaring a primary key

### Table-level, which is what you should use

```sql
REPLICATE [DestinationTable]
(
    OrderRef   VARCHAR(50),
    LineNumber INT,
    UpdatedAt  DATETIME,
    PRIMARY KEY (OrderRef, LineNumber)
)
SELECT OrderRef, LineNumber, UpdatedAt
FROM SourceTable;
```

Table-level declaration supports composite keys and reads unambiguously. Use it by default, even for a single column.

### Inline, single column only

```sql
REPLICATE [DestinationTable]
(
    CustomerRef VARCHAR(50) PRIMARY KEY,
    Email       VARCHAR(255),
    Phone       VARCHAR(50)
)
SELECT CustomerRef, Email, Phone
FROM SourceTable;
```

Inline is shorthand for one column. **You cannot mark two columns `PRIMARY KEY` inline and get a composite key.** That is a common mistake and it does not do what it looks like it does — you are declaring two separate single-column primary keys, which is not a thing. If you need more than one column, use the table-level form.

## Composite keys

Whenever a single column does not uniquely identify a row, name every column that is part of the identity:

```sql
REPLICATE [AccountBalance]
(
    AccountNo  VARCHAR(50),
    BookId     VARCHAR(50),
    PeriodCode VARCHAR(20),
    Balance    DECIMAL(18,2),
    PRIMARY KEY (AccountNo, BookId, PeriodCode)
)
SELECT AccountNo, BookId, PeriodCode, Balance
FROM dbo.LedgerBalance;
```

Think about this before the first load. Adding a column to a primary key afterwards means rebuilding the destination table.

The failure mode when you get it wrong is not an error. It is duplicate rows that nobody notices until a report double-counts something.

## Controlling destination data types

Sync infers destination types from what the source reports. Sources lie, or simply do not know. Common cases:

- An API reports every string field as unbounded, and you get oversized columns everywhere
- A numeric column with unclear precision lands as a string, breaking downstream arithmetic
- A GUID arrives as text rather than a native UUID type
- A date-only value lands as a full timestamp, or vice versa

Declare the types you want:

```sql
REPLICATE [CustomerRecord]
(
    RecordId    UUID,
    CreatedOn   DATE,
    ExternalRef UUID,
    CustomerId  INT,
    Email       VARCHAR(320),
    Balance     DECIMAL(18,2),
    PRIMARY KEY (CustomerId, ExternalRef)
)
SELECT CustomerId, CreatedOn, DisplayName, RecordId, ExternalRef, UpdatedOn
FROM SourceCustomers;
```

Note that `DisplayName` and `UpdatedOn` appear in the `SELECT` but not in the declared column list. That is deliberate: you only declare the columns whose types you want to control, and the rest are inferred as normal. Declaring every column is also fine and is more explicit.

Guidelines:

- **Size strings deliberately.** `VARCHAR(500)` where you need 60 wastes space and index efficiency across millions of rows; `VARCHAR(50)` where you need 200 fails at the worst moment. When in doubt, sample the source for actual maximum length.
- **Use `DECIMAL` with explicit precision for money.** Never float.
- **Prefer native types.** `UUID` over `VARCHAR(36)`, `DATE` over `DATETIME` where there is no time component.
- **Do this before the first load.** Changing a destination column type later means a rebuild.

### Sources that do not report column sizes

Some connectors return string columns with no declared length. Sync has to guess, and it guesses generously. If your destination tables are full of very wide `VARCHAR` columns you did not ask for, this is why. An explicit `REPLICATE` declaration is the fix.

## Batch size and other options

The `WITH` clause carries per-task options:

```sql
REPLICATE [SessionSummary]
(
    ConversationId VARCHAR(100),
    ParticipantId  VARCHAR(100),
    SessionId      VARCHAR(100),
    ProcessedAt    DATETIME,
    PRIMARY KEY (ConversationId, ParticipantId, SessionId)
)
WITH BatchSize='10000', DropTable='false'
SELECT ConversationId, ParticipantId, SessionId, ProcessedAt
FROM SessionSummary
WHERE ProcessedAt >= REPLICATE_LASTMODTIME();
```

| Option | Use |
|---|---|
| `BatchSize` | Rows buffered before writing. Lower it for wide tables under memory pressure; see [JVM tuning and sizing](05-jvm-tuning-and-sizing.md). |
| `DropTable` | Whether to drop and recreate on full reload. `'false'` preserves the destination table. |

## Writing the query

Practical notes:

- **Avoid `SELECT *` in production.** A column added upstream changes your destination schema without warning. Naming columns makes schema changes a deliberate act.
- **Keep the `WHERE` clause cheap.** It runs against the source on every execution. A filter that forces a full scan on a large source table will dominate your run time.
- **Skip `ORDER BY`.** It costs the source work and buys you nothing; Sync does not need ordered input.
- **Index the primary key in the destination.** Upserts match on it. Without an index, performance degrades as the table grows, gradually enough that nobody connects the two.

### The restriction that catches everyone

**You cannot reference the incremental check column in the `WHERE` clause of a replication query.** Sync manages that column's filtering itself, and it rejects queries that also filter on it. The error names the column, for example:

```
The column [SystemModstamp] is not allowed in the WHERE clause of a replication
```

Workaround: exclude the check column from your `SELECT` list. Getting the explicit column list is fiddly through the UI — open the task, go to column mapping, toggle any one column off and back on, and Sync expands `SELECT *` into an explicit list you can then edit in the query tab. Remove the check column from that list.

The column is still used for incremental tracking. You are only removing it from the projection.

---

**Next:** [Incremental replication](07-incremental-replication.md)
