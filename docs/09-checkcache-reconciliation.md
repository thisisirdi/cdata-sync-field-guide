# Reconciliation with CHECKCACHE

Incremental replication cannot see deletes. If a row disappears from the source, nothing in the change feed says so, and the row sits in your destination indefinitely. `CHECKCACHE` is how you find and fix that drift.

Runnable examples: [`examples/sql/checkcache-reconciliation.sql`](../examples/sql/checkcache-reconciliation.sql).

## What it does

`CHECKCACHE` compares the destination table against the live source and, with `WITH REPAIR`, fixes the differences:

- **Inserts** rows present in the source but missing from the destination
- **Updates** rows whose values have diverged
- **Deletes** rows in the destination that no longer exist in the source

It only ever writes to the destination. The source is read, never modified.

## When you need it

**Sources that cannot report deletes.** Many SaaS APIs — CRM and marketing platforms especially — expose modified timestamps but no delete feed. Without reconciliation, your destination accumulates records that were deleted upstream months ago. Those records then show up in reports, and someone eventually asks why the customer count does not match.

**After an incident.** A crash mid-run, a skipped schedule, a job disabled and forgotten. Reconciliation confirms the destination actually matches rather than assuming it does.

**After changing incremental logic.** New check column, timezone correction, altered filter. Anything that changes which rows get selected leaves a window where rows may have been missed. Reconcile the affected tables once afterwards.

**Periodically, as insurance.** Weekly or monthly on tables that matter, so drift is caught by a scheduled job rather than by an executive looking at a dashboard.

## Syntax

### Full validation and repair

```sql
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR;
```

Compares every row. Inserts what is missing, updates what differs, deletes what is gone. Correct, thorough, and expensive on a large table — it reads the entire source.

### Bounded by date range

```sql
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR
START DATEADD(DAY, -3, CURRENT_DATE())
END CURRENT_DATE();
```

Restricts comparison to rows modified in the window. Dramatically cheaper, and appropriate for a frequent scheduled reconciliation.

The trade-off is real: a row deleted outside the window is not detected. Pair a narrow frequent run with an occasional full run.

### Deletes only

```sql
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR
SKIP MODIFIED
START LAST_MONTH();
```

`SKIP MODIFIED` reconciles deletions without re-checking every modified value. This is the efficient answer to the exact problem CHECKCACHE exists for, when incremental replication is already handling inserts and updates correctly and deletes are the only gap.

This is the variant I reach for most often.

### Narrowed to specific columns

```sql
CHECKCACHE Customers
AGAINST (SELECT Id, Name, ModifiedDate FROM [public].[customers])
WITH REPAIR
START '2026-01-01'
END '2026-06-01';
```

Comparing a subset of columns is much cheaper than comparing a wide table in full. Use it when only a few columns matter, or when you specifically want to detect presence and absence rather than value drift.

## Operating it

**It does not run itself.** `CHECKCACHE` is a task you configure and schedule, not a background behaviour.

**Put it in its own job.** Separate from the replication job. Different schedule, different runtime profile, and a reconciliation failure should not mark your replication job red.

**Schedule it off-peak.** It reads the whole source within the window. Running it alongside your replication jobs means competing for the same source and the same connection budget.

**Give it its own alerting.** A reconciliation that repaired an unusually large number of rows is a signal that something upstream is wrong. If nobody looks at the output, you get the cost without the information.

### A schedule that works

| Table profile | Reconciliation |
|---|---|
| Small, critical | Full reconciliation nightly |
| Large, deletes matter | `SKIP MODIFIED` over a recent window daily, full reconciliation monthly |
| Large, deletes rare | `SKIP MODIFIED` over a wide window weekly |
| CDC-sourced | Occasional full reconciliation as an audit; CDC should be handling deletes already |

That last row is worth stating explicitly: if you are on CDC, reconciliation is a check on CDC, not a substitute for it. Finding drift on a CDC-sourced table means investigating why CDC missed it, not just repairing and moving on.

## Costs and cautions

**It reads the entire source within the window.** On a large table against a rate-limited API, this is a serious amount of traffic. Check the source's quota before scheduling a nightly full reconciliation, because the first time you notice is usually when the source starts throttling your replication jobs too.

**`WITH REPAIR` deletes rows.** That is the point, and it is also a real risk. If the source query is wrong — filtered when it should not be, pointed at the wrong environment, run against a source mid-outage returning partial results — reconciliation faithfully deletes everything the source did not return.

Before enabling repair on production data:

1. Run without `REPAIR` first, if you want to see the scope of the difference before acting on it.
2. Confirm the `AGAINST` target is the right table in the right environment.
3. Confirm the source is healthy. A degraded API returning partial results is the dangerous case.
4. Have a way back. For critical tables, a snapshot before the first repair run is cheap insurance.

**It is a repair tool, not a design.** If reconciliation is constantly repairing large numbers of rows, the incremental configuration is wrong. Fix that instead of scheduling reconciliation more often. Recurring large repairs usually mean a bad check column, a timezone offset, or a primary key that does not uniquely identify rows — see [Incremental replication](07-incremental-replication.md) and [Replication queries](06-replication-queries.md).

---

**Next:** [Events and environment variables](10-events-and-environment-variables.md)
