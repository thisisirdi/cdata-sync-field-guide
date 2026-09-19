# Change data capture

CDC reads the source database's own change stream instead of polling for modified rows. That gets you deletes, lower latency, and far less load on the source. It also introduces a component with its own state, its own failure modes, and its own retention window.

Runnable SQL: [`examples/sql/enable-sqlserver-cdc.sql`](../examples/sql/enable-sqlserver-cdc.sql) and [`examples/sql/validate-sqlserver-cdc.sql`](../examples/sql/validate-sqlserver-cdc.sql).

## When CDC is the right call

Use it when:

- You need deletes reflected in the destination
- The source has no reliable modified-timestamp column
- Polling load on the source is a problem
- You need latency measured in minutes rather than hours

Do not use it when:

- The source does not support it, or the DBA will not enable it
- The table is small and a periodic full reload is simpler
- You cannot guarantee the job runs often enough to stay inside the retention window

That last point sinks more CDC deployments than any technical limitation. See [retention](#retention-is-the-thing-that-breaks-cdc) below.

## The general shape

Every CDC implementation has the same three pieces, whatever the source:

1. **The source records changes** into a log or change table — SQL Server change tables, Oracle redo logs, an Informix capture interface.
2. **Sync reads from a stored position** — an LSN, an SCN, a sequence number — and advances it after each successful run.
3. **The source eventually discards old changes.** If your stored position falls behind that boundary, the stream is broken and you need a full reload.

The position lives in Sync's application database. Restoring that database from a backup moves your CDC position, usually to somewhere unhelpful.

## SQL Server CDC

The best-documented implementation and a good one to learn on.

### Prerequisites

- `sysadmin` to enable at database level, `db_owner` for tables
- **SQL Server Agent running and set to start automatically.** CDC capture and cleanup are Agent jobs. No Agent means no capture. This is the single most common cause of "CDC is enabled but nothing arrives."

### Enabling

```sql
-- Database level, once
EXEC sys.sp_cdc_enable_db;

-- Per table
EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Employees',
    @role_name     = NULL;
```

`@role_name = NULL` means no separate gating role, so access is governed by normal table permissions. Supply a role name if you want to restrict who can read the change tables, which you probably should in anything holding personal data.

### Verifying

Database level:

```sql
SELECT name, is_cdc_enabled
FROM sys.databases
WHERE name = DB_NAME();
```

Table level:

```sql
SELECT s.name AS schema_name, t.name AS table_name, t.is_tracked_by_cdc
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_tracked_by_cdc = 1;
```

Agent running:

```sql
SELECT servicename, status_desc
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server Agent%';
```

All three should be satisfied before you configure anything in Sync.

### Validating end to end

Do not assume it works. Prove it, with the script in [`examples/sql/validate-sqlserver-cdc.sql`](../examples/sql/validate-sqlserver-cdc.sql):

1. Insert a known number of rows, say 100.
2. Query the change table `cdc.dbo_Employees_CT` and confirm 100 change records.
3. Run the Sync job. Confirm 100 rows land in the destination.
4. Insert 50 more.
5. Run the job again. Confirm **50** rows move, not 150.

Step 5 is the test. If 150 rows move, Sync is doing a full reload rather than reading the change stream, and something is misconfigured.

Then repeat for updates and deletes, because those are the reason you chose CDC. A delete in the source must disappear from the destination.

### Change tracking as a lighter alternative

SQL Server also offers Change Tracking, which records that a row changed but not what it changed to. Lighter weight, less storage, and enough if you only need to know which rows to re-fetch. Sync supports both. Change Tracking is a reasonable middle ground when full CDC is more than you need and the DBA is resistant to the overhead.

## Oracle CDC

Oracle reads from redo logs, typically via LogMiner. The operational concerns that matter:

- **Supplemental logging must be enabled**, at minimum at database level and usually at table level for the tables you are capturing. Without it the redo entries do not carry enough information to reconstruct a row.
- **Redo retention governs your recovery window.** Same principle as SQL Server retention, with the same consequence.
- **Long-running transactions delay visibility.** A transaction open for hours means its changes are not available until it commits. A batch job that holds a transaction open overnight will make CDC look broken every morning.
- **Temp tablespace matters.** Merge-based replication of large tables consumes temp space; an undersized temp tablespace produces failures during large loads that look like Sync problems.

**In 26.2**, Oracle CDC gained ROWID column replication and the ability to use ROWID as a primary key substitute — useful for tables with no natural key, which previously forced awkward workarounds. Precision and scale defaults for `NUMBER` columns also improved, which matters because an under-specified `NUMBER` landing as a string downstream is a classic and painful Oracle-to-warehouse problem. 26.2 additionally supports private temporary tables (Oracle 18c and later) or global temporary tables for merge-based replication, reducing write amplification.

## Other sources

- **DB2 i** requires journal selection at job creation as of 26.2, with the table list filtered accordingly.
- **Informix** capture has its own configuration surface and some hard limits on concurrent captured objects. Plan table counts per job accordingly rather than discovering the ceiling in production.
- **MySQL** and **DB2 i** gained Enhanced CDC support in 25.3.
- **SAP HANA** gained Enhanced CDC in the Q1 2026 release.

## Retention is the thing that breaks CDC

Every source discards old change records eventually. SQL Server has a cleanup job with a retention setting, Oracle has redo retention, others have equivalents.

If Sync's stored position falls outside the retained window, the change stream is broken. Recovery is a full reload of the affected tables.

This happens when:

- Sync is stopped for maintenance longer than the retention window
- A job is disabled and forgotten
- A job fails repeatedly over a weekend and nobody is watching
- Retention is set to a default nobody reviewed, then a long holiday happens

Mitigations, in order of value:

1. **Set retention deliberately.** Long enough to survive your worst realistic outage. Three days is not enough if your team does not work weekends.
2. **Alert on job failure, not just on job completion.** A CDC job that has not succeeded in two days is an incident, and it should page someone before the retention window closes rather than after.
3. **Monitor the gap** between the current source position and Sync's stored position. Growing gap means you are falling behind and have a deadline.
4. **Monitor change table growth.** Unbounded growth means the cleanup job is not running; the mirror image of the retention problem, and it fills the disk instead.

## CDC engine management

Recent versions expose CDC engine state as a first-class thing rather than a property buried in job settings. As of 26.2 there is a dedicated settings panel, properties become read-only while the engine is running, and the engine can be reset directly from the UI.

Reset when the position is unrecoverable and you have accepted that a full reload is coming. It is not a routine action, and doing it casually will cost you a full reload you did not need.

Stop CDC engines cleanly before upgrades. See [Installation and licensing](02-installation-and-licensing.md#upgrades).

## Operational checklist

- [ ] Source CDC enabled at database and table level, verified by query
- [ ] SQL Server Agent running and set to automatic, where applicable
- [ ] Supplemental logging enabled, for Oracle
- [ ] Retention window longer than your worst realistic outage
- [ ] Insert, update and delete each validated end to end
- [ ] Second run moves only new changes, not the whole table
- [ ] Failure alerting on the job, firing well inside the retention window
- [ ] Position lag monitored
- [ ] Change table growth monitored
- [ ] Runbook exists for "position is outside retention", because one day it will be

---

**Next:** [Reconciliation with CHECKCACHE](09-checkcache-reconciliation.md)
