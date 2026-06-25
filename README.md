![GitHub repo size](https://img.shields.io/github/repo-size/mg0x7BE/sql-server-dba-scripts)
![GitHub License](https://img.shields.io/github/license/mg0x7BE/sql-server-dba-scripts)
![GitHub Created At](https://img.shields.io/github/created-at/mg0x7BE/sql-server-dba-scripts)
![GitHub forks](https://img.shields.io/github/forks/mg0x7BE/sql-server-dba-scripts)
![GitHub Repo stars](https://img.shields.io/github/stars/mg0x7BE/sql-server-dba-scripts)


# SQL Server DBA Scripts

Diagnostic and administration scripts for Microsoft SQL Server 2025 Enterprise.
DMV first, Query Store where it fits, organized by topic.

## Scope

Targets SQL Server 2025 Enterprise, the box product. Not maintained for older
versions or for Azure SQL Database / Managed Instance.

## Layout

| Folder | What is in it |
| --- | --- |
| `performance/` | CPU, memory, wait stats, tempdb, I/O, plan cache, Query Store, active sessions and blocking, Resource Governor |
| `indexes/` | Maintenance, missing/unused/duplicate analysis, compression, partitioning |
| `storage/` | Database files and space, transaction log and VLFs, moving files |
| `backup-restore/` | Backup history and coverage, restore cookbook |
| `security/` | Logins and users, roles, permissions, credentials, audit, ownership, access recovery |
| `agent-jobs/` | Agent jobs, Database Mail |
| `replication/` | Transactional replication monitoring and troubleshooting |
| `configuration/` | Instance configuration, collation |
| `programmability/` | Constraints, triggers, CLR, Service Broker, scripting objects |
| `diagnostics/` | Extended Events, deadlocks, error log, page inspection, object search |
| `data-movement/` | Bulk import and export |
| `operations/` | Decommission, transaction error handling |
| `migration/` | Pre-migration discovery and Azure readiness assessment of a source server |
| `docs/` | Reference notes (DMV families, Extended Events, system database recovery, perfmon) |
| `vendor/` | Third party scripts (Glenn Berry diagnostics, sp_WhoIsActive) |

## Usage

Each file is a set of standalone scripts ordered from basic checks to more
advanced ones. Open the file for your topic and run the part you need. Many
scripts use placeholders like `[YourDatabase]` or `@DatabaseName` that you set
before running.

Read the comments first. Statements that change configuration or drop, detach,
or offline objects are commented out or print only by default.

## Notes

Mixed sources: my own scripts plus material collected over the years. Third
party scripts live in `vendor/` with attribution. If you are the original
author of something here and want credit or removal, open an issue or PR.

Use at your own risk. Test on a non production instance first.

## License

[Unlicense](LICENSE)
