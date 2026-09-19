# JVM tuning and sizing

Sync is a JVM application. Most "Sync crashed" and "Sync is slow" reports resolve to heap exhaustion, garbage collection pressure, or thread contention. This page covers both the tuning knobs and how to pick a machine in the first place.

An annotated sample is at [`examples/config/sync.exe.config.example`](../examples/config/sync.exe.config.example).

## Where JVM parameters live

Windows: `{installDirectory}\sync.exe.config`.

```xml
<appSettings>
  <add key="JAVA_OPTS"
       value="-Xms2g -Xmx10g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:ParallelGCThreads=4 -Dfile.encoding=UTF-8" />
</appSettings>
```

On Linux and in containers, pass the same options through the service definition or `JAVA_OPTS` environment variable rather than this file.

Three rules:

- **Back the file up before editing.** It is small and easy to get wrong.
- **Restart the service.** Nothing here takes effect until you do.
- **Re-check after every upgrade.** It is supposed to be preserved. Verify it was, especially across major versions.

## Parameters worth setting

| Parameter | What it does | Guidance |
|---|---|---|
| `-Xms` | Initial heap | Set it equal to, or close to, `-Xmx`. Growing the heap under load costs you pauses at exactly the wrong moment. |
| `-Xmx` | Maximum heap | The number that matters. See sizing below. |
| `-XX:+UseG1GC` | G1 garbage collector | Use it for heaps above about 4 GB. Better pause behaviour than the default on large heaps. |
| `-XX:MaxGCPauseMillis=200` | Target pause time | A target, not a guarantee. 200 ms is a sensible default. |
| `-XX:ParallelGCThreads` | GC thread count | Roughly half your vCPU count. Leaving it unset is usually fine. |
| `-Dfile.encoding=UTF-8` | Force UTF-8 | **Set this.** It prevents an entire class of character corruption when source and host locales disagree. |

### Force UTF-8

`-Dfile.encoding=UTF-8` deserves its own note. Locale mismatches between the source database, the Sync host and the destination produce corrupted characters that appear only in some rows, usually in names and addresses, and usually reported weeks later by someone in another team. Setting the JVM encoding explicitly removes one of the three variables. Do it on install, not after the bug report.

Where the source system itself needs a specific locale that differs from the host, set it for the Sync service only rather than changing the machine's locale, which will affect other applications.

## Sizing a machine

There is no substitute for measuring your own workload, but you need a starting point to measure from.

### The method

Four things drive resource use, roughly in order of impact:

1. **Batch size.** Sync buffers a batch in memory before writing. Heap needed scales with batch size times row width. This is the dominant factor and the one people tune last.
2. **Row width, not row count.** A million-row table with six narrow columns is cheap. A hundred-thousand-row table with seven hundred columns, some of them large text, is not. Estimate bytes per row, not rows.
3. **Concurrency.** Jobs running simultaneously, plus tasks running in parallel within a job, multiply the above.
4. **Source behaviour.** An API that streams results in pages behaves very differently from one that materialises a large response before returning it. Some sources will dominate your memory profile regardless of what you do in Sync.

### Starting points

Rules of thumb I use for a first deployment, to be replaced by your own measurements once the pipeline is real:

| Workload | vCPU | RAM | Heap (`-Xmx`) | Concurrent jobs |
|---|---|---|---|---|
| Evaluation, a couple of small jobs | 2 | 4 GB | 2 GB | 1–2 |
| Small production, narrow tables | 4 | 8 GB | 4–6 GB | 2–4 |
| Mixed production, some wide tables | 8 | 16 GB | 10–12 GB | 4–6 |
| High volume, wide tables, CDC | 16 | 32 GB | 20–24 GB | 6–8 |

Leave headroom. **Never set `-Xmx` to the machine's total RAM.** The JVM needs memory outside the heap, and so does the operating system. Allocating roughly two thirds of physical RAM to heap is a reasonable ceiling; beyond that you trade heap exhaustion for swapping, which is worse.

Two threads per core is a sane default for concurrency. Past that you are usually waiting on the source or the destination, not on CPU.

### Bigger heap is not always better

A 32 GB heap collects garbage in longer pauses than a 12 GB heap. If Sync is periodically unresponsive rather than failing, an oversized heap with the wrong collector is a likely cause. Raise heap to fix out-of-memory errors; do not raise it speculatively.

## Tuning throughput before tuning hardware

Cheaper than a bigger machine, and usually more effective:

**Reduce batch size on wide tables.** Counter-intuitive but reliable. Large batches of wide rows are the most common cause of heap exhaustion. Halving the batch size on the offending task often fixes it outright with no measurable throughput loss.

**Split large jobs.** One job with two hundred tasks is harder to schedule, harder to recover, and gives you an all-or-nothing failure surface. Group tasks by size and criticality into separate jobs. Small, fast tables on a tight schedule; the large slow ones on their own, less often.

**Use parallel processing deliberately.** Enabling parallel tasks within a job and raising the worker pool size helps when you are waiting on a slow source. It hurts when the source is rate-limited — you will hit throttling or, with some APIs, errors that look like Sync failures but are the source refusing the concurrency. Raise it in small steps and watch the source's own metrics, not just Sync's.

**Parallel partitioned reads (26.2+).** Large source tables can be split into partitions read concurrently, for SQL Server, Oracle, PostgreSQL, DB2, DB2 i, Informix, MySQL and MariaDB. This is a better answer than raising worker pool size for a single enormous table, because it parallelises within the table rather than across tables. If you are on 26.2 and fighting one huge table, try this before adding hardware. **`[unverified]`** — I have not benchmarked the 5x figure CData cites.

**Move the application database off the embedded engine.** At raised log verbosity the embedded database becomes a bottleneck in its own right. This shows up as general sluggishness rather than job failure, which makes it easy to misattribute.

## Diagnosing memory problems

Symptoms and what they usually mean:

| Symptom | Likely cause |
|---|---|
| Job fails on a large table, succeeds on small ones | Heap too small for batch size times row width |
| Sync becomes unresponsive periodically, recovers | GC pauses; heap too large or wrong collector |
| Crash under concurrent load, fine sequentially | Total heap across concurrent jobs exceeds `-Xmx` |
| Gradual slowdown over days, restart fixes it | Thread or connection leak; capture a thread dump before restarting |
| Host starts swapping | `-Xmx` too close to physical RAM |

Watch the JVM, not just the host. Task Manager showing free RAM tells you nothing about heap pressure inside the JVM. Use `jvisualvm`, `jcmd`, or whatever your monitoring stack can attach to a JVM. In Kubernetes, make sure container memory limits and `-Xmx` are consistent, or the container gets killed before the JVM ever reports a problem.

---

**Next:** [Replication queries](06-replication-queries.md)
