# Events and environment variables

Events are hooks in the job lifecycle. They let you run logic before or after a job and, more usefully, compute a value at runtime and feed it into the task queries the job is about to run.

Working example: [`examples/events/before-job-set-env-var.xml`](../examples/events/before-job-set-env-var.xml).

## What events are for

The genuinely useful pattern is **dynamic filtering**. Instead of hardcoding a date cutoff in a task query, a before-job event looks the value up — from an audit table, a control table, an API — stores it in an environment variable, and the task query references that variable.

Other legitimate uses:

- Cancel a job when a precondition is not met, for example the upstream load has not finished
- Notify an external system after completion
- Write a run record to an audit table
- Run a data quality check and fail loudly rather than propagating bad data

What events are not for: business logic of any real complexity. An event script is hard to test, hard to version, and invisible to anyone reading the job configuration. Keep them short and obvious. If a script is growing, move the work to an orchestrator that calls Sync's API instead.

## Scripting options

| Language | Availability | Good for |
|---|---|---|
| XML (`api:` script) | All versions | Database lookups, setting variables, simple flow |
| JavaScript | Recent versions | Logic that XML makes awkward |
| Shell | Recent versions | Invoking external tooling |
| **Python** | 26.2+ | API calls, data quality checks, anything non-trivial |

Python is the significant addition. If you are on 26.2 and writing anything beyond a single lookup, use it — it is testable outside Sync, which XML is not.

The XML form is documented here because it is what works on every version and what you will find in existing deployments.

## Setting a variable in a before-job event

Open the job, go to the events tab, choose the before-run event.

```xml
<api:info title="Before Run" desc="Set environment variables before the job starts">
  <input name="JobName"     required="true" />
  <input name="Source"      required="true" />
  <input name="Destination" required="true" />
  <input name="JobStatus"   required="true" />
  <output name="env:*" />
  <output name="CancelJob" />
</api:info>

<!-- Connection to the lookup database -->
<api:set attr="db.driver" value="cdata.jdbc.sql.SQLDriver" />
<api:set attr="db.conn"   value="jdbc:cdata:sql:Server=dbhost;Database=AuditDb;User=syncsvc;Password=..." />
<api:set attr="db.query"  value="SELECT MAX(LastLoadedAt) AS LastRunTime FROM load_audit WHERE pipeline = 'orders';" />

<api:call op="dbQuery" in="db" out="result">
  <api:set attr="out.env:LastRunTime" value="[result.LastRunTime]" />
  <api:set attr="_log.info" value="Retrieved last run time: [result.LastRunTime]" />
</api:call>
```

Then reference it in the task query:

```sql
REPLICATE [Orders]
SELECT OrderId, CustomerId, OrderTotal, ModifiedAt
FROM Orders
WHERE ModifiedAt >= '{env:LastRunTime}'
```

### The driver has to be present

An event that connects to a database needs the JDBC driver `.jar` in the application directory's `libs` folder:

```
{appDirectory}/libs/cdata.jdbc.mysql.<version>.jar
```

If the driver is missing the script fails in a way that does not obviously say "missing driver". Check this first when a working script stops working after an upgrade or a migration to a new host — `libs` contents are easy to forget when rebuilding a server.

## Cancelling a job

The before-run event can stop the job:

```xml
<api:set attr="out.CancelJob" value="true" />
```

Use this for genuine preconditions: upstream load incomplete, source in maintenance, a control flag set. A cancelled job is visible as cancelled, which is better than a job that runs and produces a partial result nobody notices.

## Debugging event scripts

Event scripts are awkward to debug because there is no interactive mode. The approach that works:

**Log everything while developing.**

```xml
<api:set attr="_log.info" value="LastRunTime resolved to: [result.LastRunTime]" />
```

These land in the Sync **application** logs, not the job logs. See [Logging and diagnostics](12-logging-and-diagnostics.md).

**Test the query outside Sync first.** Run it in a normal SQL client with the same credentials the event uses. Most event failures are query or permission problems, not scripting problems.

**Handle the empty result.** The first time this pipeline runs, the audit table is empty and the lookup returns null. Your task query then filters on an empty string and either fails or, worse, returns nothing and reports success. Decide what should happen — a sensible default, or cancel the job — and write it explicitly.

**Run a full load once before enabling the dynamic filter.** Otherwise the first incremental run has no baseline and you will be reconciling to find out what you missed.

## Practical cautions

**Credentials end up in the script.** Event scripts contain connection strings, and they live in the job definition. Anyone who can read the job can read the credentials. Use a dedicated, minimally privileged account for lookups — read-only on one table is usually enough.

**Events run on every execution.** A slow lookup adds its latency to every run. A lookup against a busy production table on a five-minute schedule is a load source of its own.

**Failure behaviour needs deciding.** Know whether a failing event stops the job or lets it continue with an unset variable. The second is worse, because the job succeeds while doing the wrong thing. Test the failure path, not just the happy path.

**Events are invisible in job exports and hard to review.** They will not show up in a code review and nobody will remember they exist. Document any job that has one, in the job description at minimum.

---

**Next:** [Promoting from dev to prod](11-promoting-dev-to-prod.md)
