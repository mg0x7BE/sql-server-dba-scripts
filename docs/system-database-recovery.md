# System database recovery

Runbook: restoring system databases (master, model, msdb, tempdb, resource).

## Overview

Each system database has its own recovery path. Order matters: get the instance startable first, then restore the rest.

| Database | Purpose | Recovery method |
| --- | --- | --- |
| master | Instance-level configuration, logins, database catalog | Single-user mode (`-m`) restore |
| model | Template for all new databases | Start with trace flag 3608, then `RESTORE DATABASE` |
| msdb | SQL Server Agent jobs, alerts, schedules, history | Standard `RESTORE DATABASE` |
| resource | Read-only copies of all system objects | File-level restore or rerun setup |
| tempdb | Temporary and intermediate result sets | Recreated automatically on startup |

## model

Template for all databases. A healthy model is required for the instance to start, since tempdb is built from it at startup.

- Start the instance with trace flag 3608. This starts master only and does not auto-recover model or other databases.
- Restore model with a normal `RESTORE DATABASE`.

Start with the trace flag (command line):

```cmd
sqlservr.exe -c -T3608
```

Restore:

```sql
RESTORE DATABASE [model]
FROM DISK = N'C:\Backup\model.bak'
WITH REPLACE;
```

Stop the instance, remove the trace flag, and start normally.

## msdb

Used by SQL Server Agent for scheduling jobs and alerts, and for recording operation history. If msdb is corrupt, SQL Server Agent will not start.

- Stop SQL Server Agent.
- Restore like any user database.

```sql
RESTORE DATABASE [msdb]
FROM DISK = N'C:\Backup\msdb.bak'
WITH REPLACE;
```

Restart SQL Server Agent.

## resource

Read-only database holding copies of all system objects. It has no backup of its own.

- Recover by file-level restore (mssqlsystemresource.mdf and .ldf) from a known-good copy, or
- Rerun SQL Server setup for the instance.

The resource database version must match the instance build. Do not copy files across builds.

## tempdb

Workspace for temporary and intermediate result sets. No backup operations are possible.

- Recreated every time the instance starts, using model as the template.
- To recover, fix model if needed, then restart the instance.

If tempdb cannot be created (for example, a missing or invalid file path), correct the path in single-user mode:

```sql
ALTER DATABASE [tempdb]
MODIFY FILE (NAME = tempdev, FILENAME = N'D:\tempdb\tempdb.mdf');
```

Restart the instance to recreate the files.

## master

Holds all instance-level configuration. The instance will not start without a usable master.

### 1. Provide a startable master

Some version of master must exist before the instance will start at all. Use one of:

- Rerun SQL Server setup from the setup Bootstrap folder for your build (`...\Setup Bootstrap\...\setup.exe`). Note: setup overwrites all system databases.
- A file-level backup of master (taken while SQL Server was offline, or via VSS).
- A template master.mdf from the Templates folder under the instance's `MSSQL\Binn` folder.

### 2. Restore the correct master

With a startable master in place:

- Start the instance in single-user mode (`-m`).

```cmd
sqlservr.exe -c -m
```

- Restore the full master backup. Use sqlcmd; a single-user instance accepts only one connection.

```sql
RESTORE DATABASE [master]
FROM DISK = N'C:\Backup\master.bak'
WITH REPLACE;
```

- The instance shuts down automatically after master is restored.
- Remove the `-m` parameter.
- Restart SQL Server normally.

## Recovery order

1. master (single-user restore) if the instance will not start.
2. model (trace flag 3608) if model is corrupt.
3. tempdb is recreated automatically once master and model are healthy.
4. msdb.
5. resource (file-level or setup) if its objects are damaged.
