# Failure modes

Symptom, root cause, fix. These are the failures I saw repeatedly across enterprise Sync deployments. No customer is identified and no environment is described; the patterns are general because they recur everywhere.

Ordered roughly by how often they come up.

---

## Incremental job silently replicates nothing

**Symptom.** The job runs green on schedule. Row counts in the destination stop increasing. Nobody is alerted, because nothing failed.

**Root cause.** The stored high-water mark has jumped ahead of any real data. Usually one of:

- A future-dated row in the check column — data entry error, timezone bug, or a test record with a year 2099 timestamp. Sync stored that as the maximum value seen, and now filters everything below it.
- A timezone offset between the source and the Sync host, so the filter sits hours ahead of the data.
- A schema or source change that altered the check column's semantics.

**Diagnosis.**

```sql
-- Anything in the future?
SELECT MAX(ModifiedAt) FROM SourceTable;
```

Compare that to the current time in the source's timezone, and to the destination's most recent row. A maximum in the future is your answer.

**Fix.** Correct or remove the offending rows, then reset the task's incremental state and re-run. Resetting is required — the poisoned high-water mark lives in Sync's application database, and fixing the source data does not clear it.

**Prevention.** Alert on rows-moved being zero for a period that would be abnormal for that table, not just on job failure. A job that succeeds while doing nothing is invisible otherwise.

---

## Incremental job does a full reload every run

**Symptom.** Every run moves the entire table. Runtime is constant and high. Source load is much higher than it should be.

**Root cause.** The incremental filter is not being applied. Common reasons:

- No check column configured, so the job is effectively a standard full replication
- A custom `REPLICATE` query that omits the incremental predicate
- The task was reset and never re-established a high-water mark
- The check column is nullable and most rows are null, so they fall outside the filter each time and get re-read

**Diagnosis.** Run the job twice with no source changes in between. The second run should move nothing. If it moves everything, the filter is not working. This takes thirty seconds and should be part of commissioning any incremental task.

**Fix.** Confirm the check column is configured and non-nullable. If using a custom query, confirm the `WHERE` clause references `REPLICATE_LASTMODTIME()` or an equivalent. See [Incremental replication](07-incremental-replication.md).

---

## Duplicate rows in the destination

**Symptom.** Destination row count exceeds source row count. Reports double-count. It gets worse over time.

**Root cause.** The primary key does not uniquely identify a row, so upserts insert instead of updating. Either no key was declared, or the declared key is insufficient — a single column where the identity is actually composite.

A specific variant: declaring two columns as inline `PRIMARY KEY` in a `REPLICATE` statement. That does not create a composite key.

**Diagnosis.**

```sql
SELECT KeyColumn, COUNT(*)
FROM DestinationTable
GROUP BY KeyColumn
HAVING COUNT(*) > 1;
```

Then check whether the duplicated keys are genuinely distinct business records, which tells you whether the key is wrong or the source has real duplicates.

**Fix.** Declare a table-level primary key covering every column that forms the identity, then rebuild the destination table. Adding a column to a primary key requires a rebuild; there is no way around it. See [Replication queries](06-replication-queries.md).

---

## Job fails on a large table, succeeds on small ones

**Symptom.** Out-of-memory errors, or the process dying outright, only on the widest or largest tables.

**Root cause.** Batch size multiplied by row width exceeds available heap. It is driven by row *width* more than row count — a table with hundreds of columns, or with large text fields, exhausts heap at row counts that seem modest.

**Fix, in order of what to try first.**

1. **Lower the batch size** on that task. This resolves it outright more often than anything else, usually without measurable throughput loss.
2. **Raise `-Xmx`** in `sync.exe.config`, if the machine has headroom. Restart afterwards.
3. **Split the job** so the problem table runs alone rather than alongside others competing for the same heap.
4. **On 26.2+, try parallel partitioned reads** for supported databases, which splits the table rather than buffering more of it.

See [JVM tuning and sizing](05-jvm-tuning-and-sizing.md).

---

## Sync becomes unresponsive under concurrent load, then recovers

**Symptom.** The UI hangs for tens of seconds. Jobs stall and resume. No errors logged. It correlates with how many jobs are running.

**Root cause.** Usually one of three, and they are distinguishable:

- **Garbage collection pauses.** An oversized heap with the default collector produces long stop-the-world pauses. Switch to G1 and set a pause target.
- **Thread contention.** Worker pool size raised too high, so threads contend rather than work. Symptoms are worst when several parallel-enabled jobs overlap.
- **Application database contention.** If it is still the embedded engine and log verbosity is raised, log writes serialise against everything else.

**Diagnosis.** Take a thread dump while it is stalled, before restarting. Restarting destroys the evidence and guarantees you will be back here next week. Watch the JVM's own metrics, not host-level free memory, which tells you nothing about heap pressure.

**Fix.** Address whichever of the three you found. Move the application database to a real RDBMS regardless — it removes one variable permanently.

---

## CDC position stops advancing

**Symptom.** A CDC job runs successfully but moves no changes, while the source is clearly changing. Often appears right after an upgrade or a restart.

**Root cause.** The stored position — LSN, SCN, sequence number — is not advancing. Either the source's capture process is not running, or the stored position is stale or corrupt.

**Diagnosis.**

- **SQL Server:** is SQL Server Agent running? The capture and cleanup jobs are Agent jobs. Agent stopped means changes are never written to the change tables, and Sync correctly reports that there is nothing to read.
- **Oracle:** is supplemental logging still enabled? Is there a long-running transaction holding changes uncommitted? An overnight batch job that keeps a transaction open will make CDC look frozen until it commits.
- **All sources:** compare the source's current position against Sync's stored position. A static stored position with an advancing source position is the signature.

**Fix.** Restart the source capture process if that is the issue. If the position is genuinely stale or unrecoverable, reset the CDC engine and accept a full reload. Do not reset casually — it costs you a full reload you may not need.

**Prevention.** Monitor the gap between source position and stored position, and alert when it grows. That alert gives you time; discovering it after the retention window closes does not.

---

## CDC breaks after an outage and cannot resume

**Symptom.** After Sync was stopped, or a job failed for several days, CDC cannot restart. Errors reference an unavailable position or missing log data.

**Root cause.** The source discarded the change records Sync needed. SQL Server's cleanup job ran, Oracle's redo retention elapsed. Sync's stored position now points outside the retained window.

**Fix.** There is no recovery other than a full reload of the affected tables, then restarting CDC from a fresh position.

**Prevention.** This is entirely preventable and it is worth the effort:

- Set retention longer than your worst realistic outage. If nobody works weekends, three days is not enough.
- Alert on CDC job failure with an urgency that gets a response inside the retention window.
- Include "CDC position outside retention" in your runbook, because it will happen eventually, and the recovery is much calmer when it is written down.

---

## Rows disappear from the source but stay in the destination

**Symptom.** Destination contains records that were deleted upstream. Counts do not reconcile. Someone in finance notices before you do.

**Root cause.** Working as designed. Incremental replication using a check column cannot detect deletes. Many APIs expose no delete feed at all.

**Fix.** Reconcile with `CHECKCACHE`. For the common case of deletes only:

```sql
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR
SKIP MODIFIED
START LAST_MONTH();
```

Schedule it as a separate job. See [Reconciliation with CHECKCACHE](09-checkcache-reconciliation.md).

**Alternative.** Move to CDC if the source supports it. That is the structural fix; reconciliation is the compensating control.

---

## Replication query rejected: check column not allowed in WHERE

**Symptom.**

```
The column [SystemModstamp] is not allowed in the WHERE clause of a replication
```

**Root cause.** Sync manages filtering on the incremental check column itself, and rejects queries that also filter on it.

**Fix.** Remove the check column from the `SELECT` projection. To get an explicit column list rather than `SELECT *`: open the task, go to column mapping, toggle any one column off and back on. Sync expands the query into an explicit list, which you can then edit in the query tab to drop the check column.

The column continues to be used for incremental tracking. You are only removing it from the projection.

---

## Oracle OCI native library fails to load on Linux

**Symptom.**

```
Can't load binary library: no System.Data.CData.OracleOCIw in java.library.path
libnnz.so: cannot open shared object file: No such file or directory
```

Typically in Docker or on a freshly built VM.

**Root cause.** The OCI-based Oracle driver needs native `.so` libraries in addition to the Java components. One of four things is missing: the libraries themselves, the OS dependencies they link against, a matching CPU architecture, or a loader path that finds them.

**Diagnosis.**

```bash
# Architecture — expect x86_64 and 64
uname -m
getconf LONG_BIT

# Libraries present?
ls -lah {appDirectory}/lib/oracleoci/x64
```

The directory usually ships both x64 and x86 sets. Using the wrong one produces the same error as having none.

**Fix.**

Install the OS dependencies:

```bash
apt-get update
apt-get install -y libaio1 libc6 libstdc++6 zlib1g libgcc-s1
```

> **On Ubuntu 24.04 and later, `libaio1` was renamed `libaio1t64`** as part of the 64-bit time_t transition. `apt-get install libaio1` fails on those releases. Use `libaio1t64`. **`[unverified]`** — flagged from the Debian/Ubuntu package change rather than tested by me on a current Sync build; confirm on your distribution.

Then make the libraries loadable. Preferred:

```bash
export LD_LIBRARY_PATH="{appDirectory}/lib/oracleoci:${LD_LIBRARY_PATH}"
```

Verify nothing is unresolved:

```bash
ldd {appDirectory}/lib/oracleoci/libSystem.Data.CData.OracleOCIw.so | grep -i "not found" || echo "OK"
```

If the Sync runtime does not pick up `LD_LIBRARY_PATH` — which happens depending on how the service is launched — copy the libraries into a default loader path instead:

```bash
cp -v {appDirectory}/lib/oracleoci/*.so* /usr/lib/
ldd /usr/lib/libSystem.Data.CData.OracleOCIw.so | grep -i "not found" || echo "OK"
```

**Restart Sync afterwards.** Native library loader state is established at startup; the fix does nothing until you restart. In Docker, restart the container; in Kubernetes, the pod.

---

## Numeric columns land as strings in the destination

**Symptom.** A source numeric column arrives in the warehouse as `VARCHAR`. Downstream arithmetic and aggregation break, or silently produce wrong answers after implicit casts.

**Root cause.** The source reports precision and scale poorly or not at all — Oracle `NUMBER` without explicit precision is the classic case — and Sync's inferred mapping falls back to a string type to avoid losing data.

**Fix.** Declare the type explicitly in the `REPLICATE` statement:

```sql
REPLICATE [Ledger]
(
    EntryId    INT,
    Amount     DECIMAL(18,2),
    PostedOn   DATE,
    PRIMARY KEY (EntryId)
)
SELECT EntryId, Amount, PostedOn FROM SourceLedger;
```

Do it before the first load. Changing a destination column type afterwards means a rebuild.

**Note.** 26.2 improved precision and scale defaults for Oracle `NUMBER` in CDC. Declaring explicitly is still the reliable answer, because it removes the inference entirely.

---

## Connection worked yesterday, fails today

**Symptom.** A connection that has been stable for months starts failing. Nothing in Sync changed.

**Root cause, in rough order of likelihood.**

- **Expired OAuth token or refresh token.** Many providers expire refresh tokens after a fixed period of use or non-use. Re-authorise the connection.
- **Rotated credentials.** Someone rotated a service account password on a schedule nobody told you about.
- **New IP allowlisting or firewall rule**, often from a network change unrelated to you.
- **Certificate expiry**, on either end.
- **MFA or conditional access newly enforced** on the account Sync uses. This is increasingly common and it breaks service accounts that were previously exempt.
- **Source API version deprecated.** Check the provider's changelog.

**Diagnosis.** Raise **connection-level** verbosity and test the connection. Job logs will not help here. Check the audit log to confirm whether anything in Sync actually changed — usually it did not, which points you outward.

**Prevention.** Use service accounts, not personal accounts. Track credential and certificate expiry somewhere that generates a reminder. Ask to be told about MFA policy changes that affect service accounts, because you will not find out otherwise until something breaks.

---

## Paging errors when reading deleted objects from an API source

**Symptom.** A job reading changes from a SaaS API fails partway with a paging or cursor error, usually when processing deleted or archived records.

**Root cause.** Some APIs handle pagination over deleted-object collections inconsistently, particularly at large page sizes, and the cursor becomes invalid mid-traversal.

**Fix.** Reduce the batch or page size for that task. It is a blunt instrument and it works, at some throughput cost. If the failure is specific to the deleted-objects endpoint, consider handling deletes through periodic reconciliation instead and excluding that path from the incremental job.

---

## Timestamps shift by an hour, twice a year

**Symptom.** Around daylight saving transitions, rows go missing or duplicate. The rest of the year is fine.

**Root cause.** A check column storing local time in a region that observes DST. When clocks go back, an hour of timestamps repeats; rows in that hour can fall below the high-water mark and never replicate. When clocks go forward, an hour does not exist.

**Fix.** Use UTC in the source if you possibly can. If you cannot, set the connection's timezone handling explicitly rather than relying on the default matching, and reconcile the affected tables after each transition.

**Prevention.** Put the two DST dates in the calendar and reconcile deliberately. This is not elegant, and it is cheaper than the alternative.

---

## Job cannot start, no obvious error

**Symptom.** A job will not begin. No useful error. Sometimes follows an unclean shutdown or a host crash.

**Root cause.** A stale lock file in `{appDirectory}/locks/` from a run that never terminated cleanly.

**Fix.** Confirm nothing is genuinely running — check the job history and, in a cluster, every node. Stop Sync. Remove the stale lock. Start Sync.

Only with Sync stopped, and only after confirming nothing is actually running. Removing a live lock in a cluster is how you get two nodes replicating the same table simultaneously.

---

## Everything degrades gradually, restart fixes it

**Symptom.** Performance declines over days or weeks. A restart restores it. The cycle repeats.

**Root cause.** A resource leak — threads, connections, file handles. Or the disk quietly filling with logs.

**Diagnosis.** Before restarting, capture a thread dump and check open file handles and disk usage. Restarting first means you learn nothing and will be back in a fortnight.

**Fix.** Configure log retention and archival. Review connection pool settings. If it is a genuine leak, the thread dump is what gets it diagnosed, which is why capturing it before the restart matters.

---

## A note on diagnosis order

When something breaks, work outward:

1. **Did anything change?** Check the audit log first. Configuration changes, upgrades, credential rotations. It is nearly always this.
2. **Is it the connection or the job?** Raise connection verbosity before job verbosity. Different question, different log.
3. **Is it Sync or the source?** Run the equivalent query directly against the source with the same credentials. If it fails there, it was never a Sync problem.
4. **Is it resource exhaustion?** Heap, disk, threads, connections.
5. **Then look at Sync itself.**

Most escalations that reach a vendor are resolved at step 1 or step 3. Working through them in order is not bureaucracy; it is the fastest path to the answer.

---

**Back to:** [README](../README.md)
