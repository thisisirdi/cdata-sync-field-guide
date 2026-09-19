# Architecture and concepts

CData Sync is a replication engine with a web UI in front of it. Understanding how the parts relate is what makes the rest of this guide useful, because most production problems turn out to be a misunderstanding about where state lives.

## The runtime

Sync is a Java application. On Windows it ships with a native launcher (`sync.exe`) and an embedded JRE; on Linux it runs from `sync.jar`. The web UI is served by an embedded Jetty container out of `sync.war`. You can deploy the WAR into your own servlet container, but almost nobody does and almost nobody should.

Two consequences follow, and they explain a surprising number of support tickets:

- **It is a JVM, so JVM rules apply.** Heap limits, garbage collection pauses, and thread pools all govern how Sync behaves under load. A job that dies on a large table is usually a heap problem, not a connector problem. See [JVM tuning and sizing](05-jvm-tuning-and-sizing.md).
- **It runs as a service account, so filesystem permissions apply.** Most "Sync will not start" incidents are the service account lacking write access to a directory that a human user created while testing in foreground mode.

## Installation directory vs application directory

This distinction matters more than any other in this guide.

| | Installation directory | Application directory |
|---|---|---|
| Holds | Binaries, JRE, WAR, launcher | Your configuration and data |
| Survives upgrade | Replaced | Preserved |
| Windows default | `C:\Program Files\CData\CData Sync` | `C:\ProgramData\CData\sync` |
| Linux default | `/opt/sync` | `/opt/sync` (same by default) |

On Linux the two default to the same path, which is fine until you upgrade or cluster. **Separate them.** Set `cdata.app.directory` in `sync.properties` to somewhere outside the install path. This is the single highest-value configuration change on a new Linux install, and it is the prerequisite for clustering, because multiple nodes sharing an application directory is how clustering works.

Full breakdown in [Directory layout](03-directory-layout.md).

## The application database

Sync stores its own configuration in a database: jobs, tasks, connections, schedules, run history, the application log, and the audit log. It does **not** store your replicated data there.

Out of the box this is an embedded file database in the application directory. For anything beyond a single-node evaluation, move it to a real RDBMS (SQL Server, MySQL, PostgreSQL). Reasons, in order of how likely they are to bite you:

1. **Clustering requires it.** Nodes coordinate through the application database. An embedded file database cannot serve two nodes.
2. **Log verbosity will hurt you.** Raising the application log level writes a lot of rows. On an embedded database that becomes a performance problem quickly.
3. **Backups.** Your team already backs up the RDBMS. It does not back up a file it does not know about.

Sync 26.2 added a guided migration wizard for this (Settings, then the application database section). It checks that no jobs are running and no CDC engines are active, migrates table by table, and can roll back. Before 26.2 you set `cdata.app.db` manually in `sync.properties`; that path still works. Both are covered in the [sync.properties reference](04-sync-properties-reference.md).

> **Naming note.** Older material, including notes of my own, describes the default application database inconsistently as SQLite, Derby or H2. It has been an embedded Java database throughout, and the exact engine has changed across major versions. The practical advice does not depend on which one you have: check yours in the settings UI, and move it to a real RDBMS for production.

## Connections

A connection is a configured connector instance: credentials plus settings. Connections are typed as sources or destinations, and the same underlying connector often appears in both lists with different capabilities.

Two things about connections that are not obvious:

- **Connections are scoped to a workspace.** They are not shared across workspaces. Cloning a job into another workspace requires the connections to exist there first. This surprises people during dev-to-prod promotion; see [Promoting from dev to prod](11-promoting-dev-to-prod.md).
- **Connection-level logging is separate from job-level logging.** When a connection fails to establish, job logs tell you almost nothing useful. You need connection logs. See [Logging and diagnostics](12-logging-and-diagnostics.md).

## Jobs and tasks

A **job** pairs one source connection with one destination connection and contains one or more **tasks**. A task is normally one source table or view, optionally with a custom query.

Job types:

| Type | What it does | Use when |
|---|---|---|
| **Standard** | Each task uses an incremental check column to find new or changed rows | The source exposes a reliable modified timestamp or ascending ID |
| **Change Data Capture** | Each task reads the source's native change stream | The source supports CDC and you need deletes or low latency |
| **Sync All** | Every source table is added automatically, and new tables are picked up on each run | You want a whole schema mirrored and you accept the loss of control |
| **Load Folder** | All files in a folder or container load into one destination table | Ingesting file drops with a consistent shape |

The choice is not purely technical. **Sync All** is convenient and is also the job type most likely to surprise you in six months, when someone adds a table to the source and it silently starts replicating. Prefer explicit task lists in production.

## How replication state is stored

Sync tracks, per task, how far it has replicated. For standard incremental jobs this is a high-water mark: the maximum value seen in the check column, or an interval boundary. For CDC jobs it is a position in the source's change stream — an LSN for SQL Server, an SCN for Oracle.

This state lives in the application database, not in the destination. Three implications:

- Restoring the application database from backup rewinds or fast-forwards your replication position.
- Truncating the destination table does not reset replication state. The next run will not backfill. You have to reset the task explicitly.
- Moving a job between instances moves the job definition but not necessarily its state. Expect a full reload unless you plan for it.

This is the root of a large share of "rows are missing" reports. See [Failure modes](13-failure-modes.md).

## Destinations and schema creation

Sync creates and alters destination tables automatically based on the source schema and your column mappings. It maps source types to destination types using defaults that are usually right and occasionally expensive to get wrong: a source column reported as an unbounded or unknown-length string may land as an oversized `VARCHAR`, and numeric types with poorly reported precision may land wider than necessary or, worse, as strings.

You can override this. Declaring explicit types in a `REPLICATE` query is the reliable way, and it is covered in [Replication queries](06-replication-queries.md). Do it before the first load, not after, because changing a destination column type after the fact means a rebuild.

## Transformations

Sync supports both in-flight (ETL) and post-load (ELT) transformation.

- **In-flight** transformations apply per column during replication, using a small library of SQL functions (masking, trimming, null handling, case conversion). Useful for redaction and light normalisation. Not a place to put business logic.
- **Post-load** transformations run SQL in the destination after a job completes, triggered by job or task completion. This is where real modelling belongs.
- **dbt** projects (Core or Cloud) can be run as a transformation type against supported warehouse destinations, pulled from a local path or a Git repository.

The general rule: transform in the destination, not in flight, unless you are masking something that must never land. In-flight transformation costs you replication throughput and makes the pipeline harder to reason about.

## What changed in 26.2

Worth knowing if your mental model was formed on an earlier version:

- **Git version control.** Jobs, connections and pipeline settings can be versioned in GitHub, GitLab, Azure DevOps or Bitbucket. This changes the right answer for dev-to-prod promotion.
- **Parallel partitioned reads.** Large source tables can be split into partitions read concurrently. Available for SQL Server, Oracle, PostgreSQL, DB2, DB2 i, Informix, MySQL and MariaDB.
- **Python events**, alongside the existing XML, JavaScript and shell options.
- **ClickHouse destination**, with full, incremental and CDC modes.
- **Full UI redesign** across every major page.
- **Connection pooling on by default** for application database connections.

Q1 2026 additionally brought Apache Iceberg destinations, SAP HANA Enhanced CDC, a preview of a visual pipelines UI, Reverse ETL delete operations, and **Sync API 2.0**. If you have automation written against the original REST API, check it.

---

**Next:** [Installation and licensing](02-installation-and-licensing.md)
