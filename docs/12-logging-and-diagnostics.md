# Logging and diagnostics

Sync logs at three levels — connection, job and application — and they answer different questions. Knowing which one to raise saves an afternoon.

## Which log answers which question

| Question | Log |
|---|---|
| Why will this connection not authenticate? | **Connection** |
| Why did this job fail? | **Job** |
| Why did Sync itself misbehave, or my event script do nothing? | **Application** |
| Who called the REST API? | **Access** |
| Who changed this job configuration? | **Audit** |

Job logs tell you almost nothing about a connection that never established. If a connection is failing, raise connection verbosity, not job verbosity. This is the most common wasted step in Sync troubleshooting.

## Verbosity levels

**Connections and jobs:**

| Level | Records |
|---|---|
| None | Nothing |
| Error | Query, row count, execution time, errors |
| Info | Error plus HTTP request timing and replication warnings — the default |
| Transfer | Info plus HTTP headers and transferred data |
| Verbose | Transfer plus replication detail and destination communication |

**The application:**

| Level | Records |
|---|---|
| None | Nothing |
| Error | Errors during processing |
| Warning | Warnings |
| Info | General processing, including errors and warnings |
| Debug | Detailed debugging for successful and failed processing |
| Trace | Full trace — what support will ask for |
| All | Everything available |

### Two warnings about raising verbosity

**Transfer and Verbose put your actual data in the log file.** Passwords are masked. Customer records are not. Before sending a Verbose log to anyone — a vendor, a colleague, a ticket system — read it. If the source contains personal or regulated data, treat those logs as carrying that data, because they do.

**High verbosity costs performance**, and it costs more if the application database is still the embedded engine, because log writes go there. Raise it to diagnose, lower it when you are done. A deployment left on Trace for six months is both slow and sitting on a large volume of data nobody intended to retain.

## Raising verbosity

**Connection level:** open the connection, find the logging section in the basic connection properties, set the verbosity, then click Test to exercise it. Connection logs appear on the connection's own logs tab, filterable by status, downloadable individually or as full history.

**Job level:** open the job, edit settings, set logfile verbosity, save. Run the job. Logs appear under the job's history tab, and under the main jobs history view, which filters by job type, status, source and destination.

**Application level:** settings, advanced, additional settings. Set the application log level. You can also change the log folder location — make sure the service account can write to wherever you point it — and set the subfolder scheme to daily, weekly, monthly or yearly.

> Menu paths above are text rather than screenshots because **26.2 redesigned every page**. Labels and grouping may differ on your version; the concepts do not.

## The three log types

**Application.** Application-level errors and resource requests. Each entry carries timestamp, level, the resource that produced it, the message, and an instance ID. This is where `_log.info` output from event scripts lands — a detail that costs people a lot of time when debugging events, because they look in the job logs.

**Access.** Every request to the REST API: timestamp, authenticated user, HTTP method, remote IP, instance ID. Filterable by remote IP. Useful for confirming whether an automation is actually calling what you think it is, and for spotting a scheduler firing twice.

**Audit.** Configuration changes: timestamp, user, HTTP method, description, instance ID. Filterable by user and time. This is the log that answers "the job worked last week, what changed?" It is underused. Check it early rather than late.

## Log retention

Logs accumulate faster than expected, especially above Info. Sync can archive or hard delete on a schedule, at a time you choose, to local disk or an S3 bucket.

Configure this on install. A production instance that fills its disk with logs fails in a way that looks like a completely different problem — jobs failing to write staging files, the application database refusing writes — and the actual cause is the last thing anyone checks.

## Collecting a useful diagnostic set

When you escalate, internally or to a vendor, include:

- **Sync version** — shown in the UI footer
- **Deployment type** — standalone, clustered, Docker, Kubernetes
- **Connector version**, for connection issues
- **What you expected and what happened**
- **When it started**, and what changed around then
- **Logs at raised verbosity, scrubbed**
- **Screenshots of the error**, if the UI shows something the logs do not

Say what you were trying to achieve in business terms, not just the error. "Replicate daily order data from the CRM to the warehouse every thirty minutes for finance reporting" gets you a better answer than an error string alone, because it tells the reader which failure modes are plausible.

### Escalation templates

**Job failure**

```
Subject: Job failure — [Source] to [Destination]

Job type:         [First run / Incremental / CDC / Reverse ETL]
Source:           [type and connection name]
Destination:      [type and connection name]
Sync version:     [from UI footer]
Deployment:       [standalone / clustered / Docker / Kubernetes]
Error message:    [paste]
Started failing:  [date and time]
Changed recently: [upgrades, schema changes, credential rotations, source maintenance]

Attached:
- Connection logs (verbosity: ...)
- Job logs (verbosity: ...)
- Application logs
- Screenshot of the error

What this pipeline does: [one line, in business terms]
```

**Connection failure**

```
Subject: Connection failure — [connection name]

Connection type:     [source / destination]
Connector + version: [from the connection window]
Error message:       [paste]
Steps to reproduce:  [what you did]
Previously working:  [yes, until <date> / no, new connection]
Sync version:        [...]

Attached:
- Connection-level logs
- Connection configuration with credentials removed

What we are connecting for: [one line]
```

**Application crash**

```
Subject: Application crash

Time of incident:  [timestamp]
Activity at crash: [saving a job / running a sync / idle]
Sync version:      [...]
OS:                [...]
Deployment:        [standalone / clustered / Docker / Kubernetes]
Heap settings:     [-Xms / -Xmx from sync.exe.config]

Attached:
- Application logs around the timestamp
- Access logs
- Audit logs
- sync.exe.config
```

**Missing or duplicated rows**

```
Subject: Data issue — [missing / duplicate] rows in [job name]

Issue:        [missing / duplicate / incorrect values]
Source:       [type and connection name]
Destination:  [type and connection name]
Job type:     [First run / Incremental / CDC / Reverse ETL]
Transformation configured: [yes, describe / no]

Expected:     [what should be in the destination]
Actual:       [what is there]
Row counts:   source [n], destination [n]

Attached:
- The task's REPLICATE query
- Job logs (verbosity: ...)
- Connection logs
- Row count queries from both sides

What this data is used for: [one line]
```

Filling these in usually identifies the problem before you send them. That is the main reason to use them.

---

**Next:** [Failure modes](13-failure-modes.md)
