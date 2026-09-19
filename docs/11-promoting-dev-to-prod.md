# Promoting from dev to prod

Four ways to move job configuration between Sync instances. Which one you should use changed in 26.2.

## The short version

**On 26.2 or later, use Git version control.** It is the only option that gives you history, review and rollback. The export-based methods below remain valid and remain necessary on earlier versions, but if you have Git available, the others are a fallback rather than a default.

## Before any method

Connections never come across with credentials. This is by design and it is the single most common cause of "the import worked but every job fails."

Have ready in the target instance:

- Connection credentials for every source and destination
- Any environment-specific values: file paths, endpoints, database names, schemas
- Confirmation that both instances are on compatible versions — importing a newer export into an older instance fails, sometimes unhelpfully

## Method 1: Git version control (26.2+)

Sync integrates natively with GitHub, GitLab, Azure DevOps and Bitbucket, authenticating by OAuth, SSH, HTTP or local Git. Job, connection and pipeline configuration becomes versioned artifacts.

This is a different kind of thing from the export methods. You get:

- **History.** Who changed what, when, and why.
- **Review.** Configuration changes go through the same pull request process as everything else.
- **Rollback.** To a specific commit, not to whatever file someone saved last month.
- **Diffs.** You can see that a batch size changed, rather than discovering it by symptom.

Set it up once and the promotion process becomes the branching model you already use, rather than a manual export ritual that depends on someone remembering the steps.

**`[unverified]`** — I have not configured this on a live deployment myself; it shipped after I stopped working with Sync daily. The capability and the supported providers are from CData's 26.2 release notes. Treat the operational detail as something to validate rather than as tested guidance. The strategic point stands regardless: versioned configuration beats file exports.

## Method 2: Export individual jobs

Best for promoting a small number of specific jobs without touching anything else.

**Export.** In the source instance, go to the jobs page, select the jobs, export. You get a JSON file.

**Import.** In the target instance, go to the jobs page, import, select the file, review the summary, confirm.

**Then, and this is the part that gets skipped:** open each imported job, set the connection credentials for this environment, verify source and destination settings, and run one test execution before enabling any schedule.

Fast — under ten minutes for a handful of jobs — and easy to get wrong precisely because it is fast.

## Method 3: Clone to a workspace, then export the workspace

Best when promoting a related group of jobs and you want them organised as a unit.

1. **Create a workspace** in the source instance for the migration.
2. **Clone the jobs** into it. Note that **connections are not shared across workspaces** — the source and destination connections must already exist in the target workspace, or be cloned there first. Sync will ask you to pick the new source and destination during the clone.
3. **Export the workspace** from workspace settings. You get a ZIP.
4. **Import the workspace** in the target instance, then reconfigure connections.

Workspace exports carry job configuration, schedules and workspace settings. They do not carry working connection credentials.

Slower than method 2, worth it when the jobs belong together and you want that grouping to survive the move.

## Method 4: Full instance export

For initial production setup, disaster recovery, or wholesale environment migration.

From settings, then migration, then export. You choose:

- **Export All** — application settings, users, and every workspace
- **Custom Export** — selected workspaces or jobs, with optional application settings and users

Import in the target with one of two modes:

| Mode | Effect |
|---|---|
| **Merge** | Adds the imported configuration to what is already there |
| **Replace** | Overwrites the target instance's configuration entirely |

**Replace does what it says.** On a populated production instance it will remove configuration that is not in the export. Take a full export of the target before running a replace, every time, without exception.

After importing:

1. Recreate connection credentials
2. Verify each workspace and job
3. Update environment-specific settings
4. Test critical jobs manually
5. Enable schedules only once the above is done

## Choosing

| Method | Scope | Complexity | History | Use when |
|---|---|---|---|---|
| **Git version control** | Anything | Setup cost, then low | Yes | You are on 26.2+ — default choice |
| **Export individual jobs** | Selected jobs | Low | No | Quick promotion of a few jobs, or pre-26.2 |
| **Clone to workspace** | Related job groups | Medium | No | Grouped migration, or pre-26.2 |
| **Full instance export** | Everything | Medium | No | Initial setup, DR, environment migration |

## Post-promotion checklist

- [ ] Connection credentials updated and tested in the target
- [ ] Source and destination settings verified per job
- [ ] Environment-specific values corrected: paths, endpoints, schemas
- [ ] Schedules set for the target environment, not copied from dev
- [ ] One manual test execution per critical job, completed successfully
- [ ] Row counts checked against expectation, not just job status green
- [ ] Notifications and error handling configured in the target
- [ ] Performance settings appropriate for production volume, not dev volume
- [ ] Monitoring in place before schedules are enabled
- [ ] Schedules enabled last

## Common problems

**Jobs fail immediately after import.** Connection credentials not set. Almost always this.

**Import file not recognised.** Version mismatch between instances. Check both versions; upgrade the target if it is behind.

**Jobs missing after import.** Incomplete or corrupted export. Re-export and verify the file before importing again.

**Jobs run but replicate everything.** Replication state does not travel with the job definition. The first run in the new instance is a full load. Expect it, and plan the cutover around it rather than being surprised by a multi-hour initial run in production.

**Cloned job cannot find its connections.** Connections are workspace-scoped. Clone or create them in the target workspace first.

## Practical habits

- **Name exports with dates.** `jobs-export-2026-09-19.json` beats `export (3).json`.
- **Keep a promotion log.** What moved, when, by whom. Twenty minutes of writing saves a day of archaeology.
- **Consider a staging instance** between dev and prod if the pipelines are business-critical.
- **Promote in phases.** Ten jobs at a time, verified, beats a hundred at once.
- **Back up the target before any import that can overwrite.**
- **Tell people.** A promotion that affects live pipelines should not be a surprise to whoever is on call.

---

**Next:** [Logging and diagnostics](12-logging-and-diagnostics.md)
