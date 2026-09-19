# sync.properties reference

`sync.properties` configures the Sync application itself: where it listens, how it authenticates, where its data lives. It is separate from `sync.exe.config`, which configures the JVM.

An annotated sample is at [`examples/config/sync.properties.example`](../examples/config/sync.properties.example).

## Generating the file

It does not exist after a fresh install. From the installation directory:

```bash
java -jar sync.jar -GenerateProperties
```

Once generated, upgrades will not overwrite it. That is the behaviour you want, and it is also why a setting you added years ago may still be silently in effect after three major upgrades. Read the whole file when you inherit a deployment.

Restart Sync after any change. Nothing here is hot-reloaded.

## Networking

```properties
# HTTP port
cdata.http.port=8181

# UI session timeout, in seconds. Default is 600 (10 minutes).
cdata.session.timeout=1200
```

The session timeout is worth raising. The default logs people out mid-configuration often enough to be a genuine annoyance, and the security value of a ten-minute timeout on an internal tool is small compared to the cost of losing a half-built job.

## TLS

If the UI is reachable from anything other than localhost, configure TLS and turn off plaintext.

```properties
# Disable plaintext by setting the HTTP port to empty
cdata.http.port=

cdata.tls.port=8443
cdata.tls.keyStoreType=PKCS12
cdata.tls.keyStorePath=${cdata.home}/mycertificate.pfx
cdata.tls.keyStorePassword=ChangeMe
```

Notes:

- `keyStoreType` accepts `jks`, `pkcs12` or `jceks`.
- `${cdata.home}` resolves to the installation directory.
- **The certificate file must be readable by the Sync service account.** If you obtained the key externally, change its ownership to the service account (`cdatasync:cdatasync` by default on Linux). A certificate the service cannot read produces a startup failure whose message does not mention permissions.
- Leaving the keystore password in plaintext here is the normal arrangement. Protect the file with filesystem permissions.

## Application directory

```properties
cdata.app.directory=/mnt/shared/sync
```

Set this when you want configuration and data somewhere other than the default: to separate it from the installation directory on Linux, to put it on a shared volume for clustering, or to place it on storage that gets backed up.

Changing it moves data files only, not the binaries. If you change it on an existing install, move the contents of the old directory yourself, with Sync stopped.

**Permissions are the usual failure.** If Sync will not start after changing this, or starts using an unexpected directory, check ownership first:

```bash
sudo chown -R cdatasync:cdatasync /mnt/shared/sync
```

## Application database

Sync stores jobs, tasks, connections, run history, the application log and the audit log in its application database. By default this is an embedded file database in the application directory.

Move it to a real RDBMS for production. Set `cdata.app.db` to a JDBC connection string:

```properties
# SQL Server
cdata.app.db=jdbc:cdata:sql:server=dbhost;database=syncmeta;user=syncsvc;password=...

# PostgreSQL
cdata.app.db=jdbc:cdata:postgresql:server=dbhost;port=5432;database=syncmeta;user=syncsvc;password=...

# MySQL
cdata.app.db=jdbc:cdata:mysql:server=dbhost;port=3306;database=syncmeta;user=syncsvc;password=...
```

**Sync 26.2 added a migration wizard** in the settings UI that does this for you: it verifies no jobs are running and no CDC engines are active, migrates table by table, and supports rollback. Prefer it over hand-editing on 26.2 and later. The manual property still works and is still what you use for a scripted or containerised deployment where the UI is not the source of truth.

26.2 also enables connection pooling for application database connections by default, which mainly benefits PostgreSQL. **`[unverified]`** — not benchmarked by me.

Give the metadata database its own schema or database, not a shared one. It is small, it is chatty, and you do not want it in the middle of an unrelated maintenance window.

### Encrypting the connection string

Avoid leaving database credentials in plaintext:

```bash
java -jar sync.jar -EncryptConnectionString "jdbc:cdata:mysql:Server=localhost;Port=3306;Database=syncmeta;User=syncsvc;Password=..."
```

Put the output in `cdata.app.db` instead of the plaintext string.

## LDAP authentication

Sync can authenticate against LDAP. A matching user must also exist in Sync itself; LDAP handles the password, not the account's existence or its role.

```properties
cdata.loginService.ldap.enabled=true
cdata.loginService.ldap.hostname=ldap.example.com
cdata.loginService.ldap.port=389
cdata.loginService.ldap.authenticationMethod=simple
cdata.loginService.ldap.bindDn=CN=SyncBind,CN=Users,DC=example,DC=com
cdata.loginService.ldap.bindPassword=...
cdata.loginService.ldap.useLdaps=false
cdata.loginService.ldap.forceBindingLogin=true

# User entries
cdata.loginService.ldap.userBaseDn=DC=example,DC=com
cdata.loginService.ldap.userObjectClass=organizationalPerson
cdata.loginService.ldap.userRdnAttribute=cn
cdata.loginService.ldap.userIdAttribute=sAMAccountName
cdata.loginService.ldap.userPasswordAttribute=userPassword

# Role entries
cdata.loginService.ldap.roleBaseDn=DC=example,DC=com
cdata.loginService.ldap.roleObjectClass=group
cdata.loginService.ldap.roleNameAttribute=cn
cdata.loginService.ldap.roleMemberAttribute=member

# Turn on while configuring, off afterwards
cdata.loginService.ldap.debug=true
```

Set `debug=true` while you are getting the DNs right, then turn it off. It is verbose and it logs directory structure.

For SSO via an identity provider rather than direct LDAP, recent versions support mapping IdP groups to Sync roles for just-in-time provisioning. That is configured in the UI, not here.

## Login lockout

Sync locks an account after repeated failed logins. Defaults: six failures within five minutes triggers a thirty minute lockout.

```properties
cdata.initParameters=LockoutFailedAttempts:6,LockoutMinutes:30,LockoutTimeCheckPeriod:5
```

| Parameter | Meaning |
|---|---|
| `LockoutFailedAttempts` | Failures that trigger lockout. `0` disables lockout entirely. |
| `LockoutMinutes` | How long the lockout lasts. |
| `LockoutTimeCheckPeriod` | Window, in minutes, over which failures are counted. |

Setting `LockoutFailedAttempts:0` disables brute-force protection. There is a legitimate reason to do it — an automation account repeatedly locking out a shared service login — but fix the automation instead if you can.

## Password reset

When nobody can log in:

```bash
java -jar sync.jar -ResetPassword -User admin -Password NewPassword -AppDirectory /opt/sync
```

Run it as the service account, or as a user that can write to the application directory. Running it as root and leaving root-owned files behind creates the permissions problem described above.

## Default paths

| Platform | Installation directory |
|---|---|
| Windows | `C:\Program Files\CData\CData Sync` |
| Linux | `/opt/sync` |

---

**Next:** [JVM tuning and sizing](05-jvm-tuning-and-sizing.md)
