# Installation and licensing

Installation is straightforward. The parts that cause trouble are the service account, the application directory, and the licensing rules around virtualised environments.

## Getting the installer

Builds and licence keys come from the [CData Portal](https://portal.cdata.com). Your subscription has to be attached to your portal account before downloads appear; if the portal shows nothing, that attachment is usually what is missing rather than a permissions problem.

Hotfix builds are not always published. If support has told you a fix is in a specific build and you cannot see it, ask them for the link directly.

## Platform choice

| Platform | Good for | Watch out for |
|---|---|---|
| **Windows service** | Simplest path, fine for most single-node deployments | Service account permissions; see below |
| **Linux (systemd)** | Servers, better resource control | Install and application directories default to the same path |
| **Docker** | Reproducible, easy upgrades, natural fit for clustering | Application directory must be on a volume or you lose everything on restart |
| **Kubernetes** | Multi-node, HA | Shared volume for the application directory, external application database required |

### The service account, which is where installs go wrong

Sync normally runs as a dedicated service account. The most common post-install failure is this sequence:

1. Someone runs Sync in foreground mode as themselves to try it out.
2. Sync creates the application directory and its contents owned by that user.
3. Sync is then installed as a service running under a different account.
4. The service cannot write to the directory it needs and fails to start, or starts and behaves strangely.

On Linux, fix it by giving the service account ownership of the application directory:

```bash
sudo chown -R cdatasync:cdatasync /opt/sync
```

On Windows, confirm the service logon account has modify permissions on both `C:\Program Files\CData\CData Sync` and `C:\ProgramData\CData\sync`.

Check this before you conclude anything else is wrong.

### Separate the application directory on Linux

By default both directories are `/opt/sync`. Set them apart in `sync.properties`:

```properties
cdata.app.directory=/var/lib/cdata-sync
```

Do it on day one. It makes upgrades cleaner, backups obvious, and clustering possible. See [sync.properties reference](04-sync-properties-reference.md).

### Docker

Two things, both non-negotiable:

- Mount the application directory as a volume. Without it, every container restart is a fresh install.
- If you use Oracle connections via the OCI-based driver, native `.so` libraries need to load. That has its own set of failures; see [Failure modes](13-failure-modes.md#oracle-oci-native-library-fails-to-load-on-linux).

## Licensing

The rules are simple but the edge cases cost people days.

**Major versions need a new key.** A licence is tied to the major version. Moving from v24 to v25, or v25 to v26, requires a new key. Generate it yourself in the portal, or ask your account manager.

**Minor versions do not.** 25.1 to 25.3 is fine with the existing key.

**Virtualised environments need a cloud licence.** Standard licences bind to the machine's NodeId. In Docker, Kubernetes, autoscaling VMs, or anywhere the underlying host identity changes, the NodeId changes and the licence stops validating. You need a *cloud licence*, which is a different licence type, not a different key of the same type.

You have to ask for it explicitly. The request goes to your account manager, and you have to say the deployment is containerised or virtualised, otherwise a standard licence gets issued and the problem repeats after the next restart. This is worth getting right before go-live rather than during it.

## Upgrades

The order that works:

1. **Read the release notes** for every version you are skipping, not just the target. Behaviour changes accumulate.
2. **Stop CDC engines and let running jobs finish.** Interrupting a CDC job mid-run can leave the stored position ambiguous.
3. **Back up the application database.** All your job definitions live there. If it is still the embedded database, back up the whole application directory.
4. **Back up `sync.properties` and `sync.exe.config`.** Upgrades are not supposed to overwrite them. Verify rather than trust, especially across major versions.
5. **Upgrade.** On Windows a helper script ships in the installation directory, but a clean uninstall and reinstall is more predictable and is what I would do on anything I cared about.
6. **Apply the new licence key** if this is a major version change.
7. **Verify before re-enabling schedules.** Run one job manually. Check the row counts. Then turn the schedules back on.

Step 7 is the one people skip and regret.

### Upgrading to 26.2 specifically

26.2 redesigned the entire UI. Nothing functional breaks, but every internal runbook with a screenshot in it is now wrong, and anyone trained on the old layout will need a few minutes to reorient. If you maintain documentation for your own team, budget for that.

Also in 26.2: application database connection pooling is on by default, which is a behaviour change if you were managing pool sizing yourself, particularly on PostgreSQL. **`[unverified]`** — I have not benchmarked this myself on a current build.

## Verifying the install

Before declaring an installation good:

- [ ] Service starts automatically after a host reboot, not just after a manual start
- [ ] Service account can write to the application directory
- [ ] Application directory is outside the installation directory
- [ ] Licence applied and not expiring within the quarter
- [ ] Application database is a real RDBMS if this is production or clustered
- [ ] TLS configured, plaintext port disabled, if the UI is reachable from anywhere but localhost
- [ ] Log retention and cleanup configured, so the disk does not fill in three months
- [ ] One end-to-end test job runs green

---

**Next:** [Directory layout](03-directory-layout.md)
