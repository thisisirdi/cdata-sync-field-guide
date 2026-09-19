# Directory layout

What is on disk, what you will actually touch, and what to collect when something breaks.

## Installation directory

`C:\Program Files\CData\CData Sync` on Windows, `/opt/sync` on Linux.

Replaced on upgrade. Do not keep anything of your own here.

```
{installDirectory}/
├── help/               Offline documentation
├── jre/                Bundled Java runtime — Sync does not use a system JVM
├── lib/                Extra libraries; often empty
├── webapp/
│   └── sync.war        The web UI, deployable to your own servlet container
├── readme.md           Install notes and version info
├── restart.bat         Restart helper (Windows)
├── sync.exe            Windows launcher
├── sync.exe.config     JVM parameters — you will edit this
├── sync.jar            The engine: replication, scheduling, job execution
├── sync.properties     Main configuration — you will edit this
├── sync.InstallLog     Installer output; read this when an install fails
├── sync.InstallState   Installer bookkeeping; do not edit
├── upgrade.bat         Upgrade helper (Windows)
└── Uninstall.exe
```

### The three files that matter

**`sync.exe.config`** holds JVM parameters: heap size, garbage collector, encoding. Every memory problem is solved here. See [JVM tuning and sizing](05-jvm-tuning-and-sizing.md).

**`sync.properties`** holds application configuration: ports, TLS, LDAP, application database location, the application directory path. **It does not exist after a fresh install.** Generate it:

```bash
java -jar sync.jar -GenerateProperties
```

Once generated, upgrades leave it alone. Full contents in the [sync.properties reference](04-sync-properties-reference.md).

**`sync.InstallLog`** is the first thing to read when an installation fails, and the last thing anyone remembers to check.

### Foreground vs service mode

Running `sync.jar` directly starts Sync in the foreground with a console window attached. Useful for a first look or for watching startup errors that never reach a log file.

Service mode is what you run in production: starts with the host, survives logout, no console. Just make sure the service account has the permissions the foreground user had, which is the trap described in [Installation and licensing](02-installation-and-licensing.md#the-service-account-which-is-where-installs-go-wrong).

## Application directory

`C:\ProgramData\CData\sync` on Windows, `/opt/sync` on Linux by default — override it with `cdata.app.directory`.

Preserved across upgrades. This is what you back up.

```
{appDirectory}/
├── admin/          Internal administrative data
├── api/            Metadata and temp files behind the REST API
├── connections/    Connection definitions, encrypted at rest
├── data/           Scratch space for running jobs: cache, staging, temp output
├── db/             The embedded application database, if you have not moved it.
│                   Also holds licence state.
├── downloads/      Downloaded artifacts, mainly connector .jar files
├── Jobs/           One folder per job: task definitions, REPLICATE queries, metadata
├── libs/           Custom or additional JDBC drivers you have added
├── locks/          Lock files coordinating concurrent access
├── logs/           Application, access and audit logs
├── settings/       Miscellaneous feature and configuration settings
└── .cdata          Marker file recording that the directory is initialised
```

### The ones worth knowing

**`Jobs/`** contains your job definitions as files. This is genuinely useful: you can diff them, grep them, and read the actual `REPLICATE` query a task is running when the UI is being unclear. It is also why filesystem-level backup of the application directory captures your work.

**`libs/`** is where additional JDBC drivers go. If you are writing an event script that connects to a database, the driver `.jar` has to be here. See [Events and environment variables](10-events-and-environment-variables.md).

**`data/`** can grow large during big loads and is safe to clear when Sync is stopped. If a job died and left staging files behind, this is where they are.

**`db/`** holds both the embedded application database and licence state. Two consequences: back it up, and understand that restoring an old copy rewinds your replication positions along with everything else.

**`locks/`** prevents overlapping execution. Stale lock files after an unclean shutdown can stop a job from starting. Clearing them is a legitimate recovery step, but only with Sync stopped, and only after confirming nothing is actually running.

**`logs/`** fills up faster than anyone expects, especially at raised verbosity. Configure archival or deletion. Sync can archive to local disk or an S3 bucket.

## Clustering

Clustered nodes share an application directory on shared storage and an external application database:

```properties
cdata.app.directory=/mnt/shared/sync
cdata.app.db=jdbc:cdata:postgresql:server=dbhost;port=5432;database=syncmeta;user=...;password=...
```

The shared filesystem has to genuinely support concurrent access with working file locking. NFS with the wrong mount options will produce intermittent, hard-to-diagnose failures that look like Sync bugs. Verify locking behaviour before blaming the application.

## What to collect when something breaks

Support, or future you, will want:

| Problem | Collect |
|---|---|
| Install failed | `sync.InstallLog`, `sync.properties` with secrets removed |
| Service will not start | Application logs from `logs/`, `sync.properties`, `sync.exe.config`, directory ownership |
| Job fails | Job logs at raised verbosity, the job's folder from `Jobs/`, Sync version |
| Connection fails | Connection-level logs, connector version, the connection config with credentials removed |
| Out of memory | `sync.exe.config`, application logs around the crash, heap and thread settings |
| Data mismatch | Source and destination row counts, the task's `REPLICATE` query, job logs at Verbose |

Scrub credentials before sharing anything. Raising verbosity to Transfer or Verbose puts **actual replicated data** in the log file. Passwords are masked; your customer records are not.

---

**Next:** [sync.properties reference](04-sync-properties-reference.md)
