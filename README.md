# CData Sync Field Guide

Practitioner notes on running CData Sync in production: configuration, replication query design, CDC, reconciliation, and the failures you actually hit.

Written by [Irdi Duka](https://www.linkedin.com/in/irdi-duka-242128141). I spent four years at CData Software as a Technical Support Engineer, Solutions Engineer and Technical Customer Success Manager, onboarding enterprise customers onto Sync. This is what I learned doing that, rewritten from scratch as an independent reference.

**This is an unofficial guide.** It is not produced, reviewed or endorsed by CData Software. For product documentation, see the [official Sync docs](https://cdn.cdata.com/help/ASN/sync/). Where this guide and the official docs disagree, the official docs are authoritative on *what the product does*; this guide is about *what to do with it*.

---

## Who this is for

You already know what an ETL tool is. You are running Sync, or about to, and you want the parts that the product documentation does not cover: how to size the machine, how to write a replication query that will not silently drop rows, what to do when a CDC job stops advancing, and how to tell the difference between a source problem and a Sync problem.

## Contents

### Setup and configuration

| | |
|---|---|
| [01 · Architecture and concepts](docs/01-architecture-and-concepts.md) | How the pieces fit: connections, jobs, tasks, the application database, the replication engine |
| [02 · Installation and licensing](docs/02-installation-and-licensing.md) | Platform choices, service accounts, upgrades, and the licensing rules that catch people out |
| [03 · Directory layout](docs/03-directory-layout.md) | What lives in the installation and application directories, and which files matter |
| [04 · sync.properties reference](docs/04-sync-properties-reference.md) | Ports, TLS, LDAP, application database, lockout policy, encrypted connection strings |
| [05 · JVM tuning and sizing](docs/05-jvm-tuning-and-sizing.md) | Heap, garbage collection, thread counts, and how to size a box from workload |

### Building pipelines

| | |
|---|---|
| [06 · Replication queries](docs/06-replication-queries.md) | Primary keys, composite keys, destination data types, and the `REPLICATE` syntax |
| [07 · Incremental replication](docs/07-incremental-replication.md) | Check columns, `REPLICATE_LASTMODTIME`, `REPLICATE_NEXTINTERVAL`, and how Sync stores state |
| [08 · Change data capture](docs/08-change-data-capture.md) | When CDC beats incremental, enabling it on SQL Server, and validating that it works |
| [09 · Reconciliation with CHECKCACHE](docs/09-checkcache-reconciliation.md) | Detecting and repairing drift when the source cannot report deletes |
| [10 · Events and environment variables](docs/10-events-and-environment-variables.md) | Pre and post job hooks, and passing runtime values into task queries |

### Operating

| | |
|---|---|
| [11 · Promoting from dev to prod](docs/11-promoting-dev-to-prod.md) | Four methods compared, including Git version control |
| [12 · Logging and diagnostics](docs/12-logging-and-diagnostics.md) | Verbosity levels, the three log types, and what to collect before raising a ticket |
| [13 · Failure modes](docs/13-failure-modes.md) | Symptom, root cause, fix, for the failures that recur across deployments |

### Examples

- [`examples/sql/`](examples/sql/) — runnable SQL for CDC setup, validation, replication queries and reconciliation
- [`examples/config/`](examples/config/) — annotated `sync.properties` and `sync.exe.config` samples
- [`examples/events/`](examples/events/) — a working before-job event script

---

## Version coverage

Written against **CData Sync 25.3.x and 26.2**, September 2026.

Sync 26.2 shipped a full UI redesign, so any walkthrough written against an earlier version now has the wrong screenshots and sometimes the wrong navigation. This guide deliberately contains **no screenshots**. Menu paths are given as text and flagged where 26.2 changed them. Configuration file contents, SQL and directory structures are far more stable than screenshots and are what you need anyway.

Where behaviour differs between 25.x and 26.x, it is called out inline.

## Conventions

- `{appDirectory}` means the Sync application directory: `C:\ProgramData\CData\sync` on Windows, `/opt/sync` on Linux by default.
- `{installDirectory}` means the installation directory: `C:\Program Files\CData\CData Sync` or `/opt/sync`.
- Table and column names in examples are invented. Nothing here is drawn from a real customer environment.
- Anything I have not personally verified on a current build is marked **`[unverified]`**, with a note saying where it came from. Treat those as leads to validate rather than as tested guidance.

## Scope

Everything here is complete. Rather than publish stub pages, I have left out the topics I cannot yet cover properly: connection configuration in depth, high availability and clustering, the Sync API (v2.0 shipped in Q1 2026 and I have not worked with it), security and governance, transformations, reverse ETL, and scheduling patterns.

If you run Sync in production and something here is wrong or missing, open an issue. Corrections with a version number and a reproduction are especially welcome.

## Licence

Documentation is [CC BY 4.0](LICENSE). Example code is MIT. Use it, adapt it, credit it.

"CData", "CData Sync" and related marks belong to CData Software, Inc. Used here only to identify the product this guide is about.
