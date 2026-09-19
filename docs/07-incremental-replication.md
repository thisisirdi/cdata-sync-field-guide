# Incremental replication

The first run of a job moves everything. Every run after that should move only what changed. Getting that right is most of the work in a production pipeline, and getting it subtly wrong is how rows go missing without anyone noticing.

Runnable examples: [`examples/sql/replicate-incremental.sql`](../examples/sql/replicate-incremental.sql).

## Two mechanisms

**Incremental check columns.** Sync records the highest value it has seen in a nominated column — usually a last-modified timestamp, sometimes an ascending integer — and requests only rows above that on the next run. Works with any source that has such a column. Cannot detect deletes.

**Change data capture.** Sync reads the source's native change stream. Detects inserts, updates and deletes. Requires source support and configuration. Covered in [Change data capture](08-change-data-capture.md).

Use CDC where the source supports it and you need deletes or low latency. Use check columns everywhere else, and add reconciliation to cover deletes; see [Reconciliation with CHECKCACHE](09-checkcache-reconciliation.md).

## The initial load

The first run processes the source's entire history. Sync splits this into windows so that a failure does not mean restarting from the beginning.

**Start date or start integer.** Where replication begins. Left unset, Sync attempts to fetch everything in a single request, which on a large table means one enormous query where any error costs you the whole run. Set it.

Some APIs cannot report their own minimum date or ID, so Sync cannot derive a sensible start. Set it manually per task: open the task, go to the advanced tab, configure incremental replication, tick the option to override job settings, then set the start value.

**Replication interval and unit.** The window size Sync uses to chunk the initial load — 180 days by default. Sync commits progress at each window boundary, so an interrupted load resumes from the last completed window rather than from scratch.

Tune it to your data's density, not to the calendar:

| Data shape | Interval |
|---|---|
| Decades of sparse records | Months or years |
| Steady moderate volume | Weeks to months |
| Millions of rows per month | Days, sometimes hours |

Too large and each window is an enormous query that risks timing out. Too small and you pay per-request overhead thousands of times. If an initial load keeps failing partway, shrink the interval before you touch anything else.

## Steady-state incremental

Once the initial load completes, Sync stores a high-water mark per task and filters on it.

### REPLICATE_LASTMODTIME()

Returns the last successfully replicated timestamp for that task.

```sql
WHERE LastUpdated >= REPLICATE_LASTMODTIME()
```

This is the common case and what you should reach for first.

Note the `>=`. Using `>` risks missing rows sharing the boundary timestamp; using `>=` risks re-reading a few rows, which is harmless because the upsert is idempotent when your primary key is correct. Prefer the harmless failure.

### REPLICATE_NEXTINTERVAL()

Returns the end of the current interval window. Use it when the source expects a bounded range rather than an open-ended "everything since" filter:

```sql
WHERE from_date_prompt = REPLICATE_LASTMODTIME()
  AND to_date_prompt   = REPLICATE_NEXTINTERVAL()
```

This pattern is required by reporting APIs that take explicit from and to parameters. It depends on `ReplicateInterval` and `ReplicateIntervalUnit` being set, since they define the window.

### Combining them

```sql
WHERE ModifiedAt >= REPLICATE_LASTMODTIME()
  AND ModifiedAt <  REPLICATE_NEXTINTERVAL()
```

A closed window. Predictable, and it bounds the size of any single run, which matters when the source is slow or fragile.

## How Sync decides what state to save

This determines whether your incremental filter actually advances, and it is worth understanding rather than discovering:

| Your filter uses | Sync stores | Behaviour |
|---|---|---|
| Only Sync functions | The interval boundary | Most predictable; advances on schedule regardless of data |
| Only source columns | The maximum value seen in that column | Follows the data; standard for `LastModifiedDate` patterns |
| A mix of both | The interval boundary | Consistency wins; the interval governs |

The middle row carries a real hazard. If the filter follows the maximum value seen, and the source contains a row with a far-future timestamp — a data entry error, a timezone bug, a test record — the high-water mark jumps to that future value and **every subsequent run returns nothing**. The job succeeds. The row count stops moving. Nobody gets an alert, because nothing failed.

Check for future-dated rows in any column you are using as a check column, before you rely on it.

## Choosing a check column

The column must be **monotonic**: it never decreases for a given row, and it always increases when the row changes.

Good candidates:

- A database-maintained modified timestamp
- A system change token the platform guarantees to be increasing
- An auto-increment ID, for append-only tables

Bad candidates, and why:

- **An application-set `UpdatedAt`.** Depends on every code path remembering to set it. One that forgets is a silent data loss bug.
- **A business date.** Order date, effective date, invoice date — these get backdated by users. A backdated row is below the high-water mark and will never replicate.
- **Anything nullable.** Null rows fall outside the filter and never move.
- **A local-time timestamp in a region with daylight saving.** Clocks going back means an hour of timestamps that repeat. Rows in that hour can be skipped.

### Timezones

The most common cause of missing rows in incremental replication, and the hardest to see.

Three clocks are involved: the source database, the Sync host, and the destination. If the source writes local time and Sync compares in UTC, your filter is offset by hours. You lose rows at every run boundary, consistently, in a quantity small enough to look like nothing.

- Prefer UTC everywhere. If the source stores UTC, this is not a problem.
- If the source stores local time, be explicit about it in the connection configuration rather than hoping the default matches.
- Daylight saving transitions are where this surfaces first. Test around them deliberately if the source is in a region that observes DST.
- After any change to timezone handling, reconcile the affected tables. See [Reconciliation with CHECKCACHE](09-checkcache-reconciliation.md).

## Resetting incremental state

Sometimes you need to start over: the check column was wrong, a schema change invalidated the history, or a future-dated row poisoned the high-water mark.

Replication state lives in the application database, **not in the destination**. Truncating the destination table does not reset it. The next run will pick up from the stored position and backfill nothing, leaving you with an empty or partial table and a job that reports success.

Reset the task explicitly through the UI, then re-run. Confirm the state has actually reset by checking that the first run after the reset moves the volume you expect.

## Verifying it works

Do this on every new incremental task, before you trust it:

1. **Full load, then count.** Row counts match between source and destination.
2. **Change nothing, run again.** The second run should move zero or near-zero rows. If it moves everything, your incremental filter is not being applied.
3. **Insert a known row, run again.** Only that row moves.
4. **Update a known row, run again.** Only that row moves, and the destination reflects the new values rather than gaining a duplicate. A duplicate here means the primary key is wrong; see [Replication queries](06-replication-queries.md).
5. **Delete a row in the source, run again.** It will still be in the destination. That is expected with check columns, and it is what reconciliation is for.
6. **Check for future-dated rows** in the check column.

Step 2 is the one that catches misconfigured incremental replication, and it takes thirty seconds.

---

**Next:** [Change data capture](08-change-data-capture.md)
