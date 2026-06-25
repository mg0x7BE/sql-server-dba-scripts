# DMV reference

Reference: dynamic management view and function families.

DMVs and DMFs live in the `sys` schema and report server, instance, and database
state. Naming convention is `sys.dm_<family>_<object>`. Most require
`VIEW SERVER STATE` (server scope) or `VIEW DATABASE STATE` (database scope).

## sys.dm_exec_* - execution and connections

Connections, sessions, requests, and query execution.

- `sys.dm_exec_sessions` - one row per connected session
- `sys.dm_exec_requests` - currently executing requests
- `sys.dm_exec_connections` - active connections to the instance
- `sys.dm_exec_query_stats` - aggregated stats for cached plans
- `sys.dm_exec_sql_text` - DMF; SQL text for a given `sql_handle`
- `sys.dm_exec_query_plan` - DMF; cached plan for a given `plan_handle`

```sql
-- Currently running requests with their SQL text
SELECT r.session_id, r.status, r.wait_type, r.cpu_time, r.total_elapsed_time,
       t.text
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID;
```

## sys.dm_os_* - SQL OS

SQLOS-level information without reaching for OS tools.

- `sys.dm_os_performance_counters` - SQL Server performance counters
- `sys.dm_os_wait_stats` - aggregated wait statistics since restart
- `sys.dm_os_waiting_tasks` - tasks currently waiting
- `sys.dm_os_memory_clerks` - memory allocation by clerk
- `sys.dm_os_schedulers` - scheduler state and load

```sql
-- Top waits since last restart, signal vs resource
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
FROM sys.dm_os_wait_stats
ORDER BY wait_time_ms DESC;
```

## sys.dm_tran_* - transaction management

Active transactions, locks, and version store.

- `sys.dm_tran_active_transactions` - currently active transactions
- `sys.dm_tran_locks` - current lock manager state
- `sys.dm_tran_session_transactions` - session-to-transaction mapping
- `sys.dm_tran_version_store` - row versions in tempdb

```sql
-- Active transactions and how long they have been open
SELECT at.transaction_id, at.name, at.transaction_begin_time,
       at.transaction_state
FROM sys.dm_tran_active_transactions AS at
ORDER BY at.transaction_begin_time;
```

## sys.dm_io_* - I/O

I/O processes and file performance.

- `sys.dm_io_virtual_file_stats` - DMF; I/O stats per database file
- `sys.dm_io_pending_io_requests` - outstanding I/O requests

```sql
-- Read/write latency per file
SELECT DB_NAME(vfs.database_id) AS db_name, mf.physical_name,
       vfs.num_of_reads, vfs.num_of_writes,
       vfs.io_stall_read_ms, vfs.io_stall_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
JOIN sys.master_files AS mf
  ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;
```

## sys.dm_db_* - database scoped

Database-scoped information; runs in the context of the current database.

- `sys.dm_db_index_usage_stats` - index seek/scan/lookup/update counts
- `sys.dm_db_index_physical_stats` - DMF; fragmentation and page counts
- `sys.dm_db_missing_index_details` - missing index suggestions
- `sys.dm_db_partition_stats` - row and page counts per partition

```sql
-- Index usage for the current database
SELECT OBJECT_NAME(ius.object_id) AS object_name, i.name AS index_name,
       ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates
FROM sys.dm_db_index_usage_stats AS ius
JOIN sys.indexes AS i
  ON ius.object_id = i.object_id AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID();
```

## Query Store

For durable query history, use the Query Store catalog views
(`sys.query_store_*`) as the modern complement to `sys.dm_exec_query_stats`.
DMV plan-cache stats reset on restart or eviction; Query Store persists runtime
stats, plans, and wait categories per database across restarts.

- `sys.query_store_query` - tracked queries
- `sys.query_store_plan` - captured plans per query
- `sys.query_store_runtime_stats` - runtime stats per plan over time

```sql
-- Top queries by total duration from Query Store
SELECT q.query_id, qt.query_sql_text,
       SUM(rs.count_executions) AS executions,
       SUM(rs.avg_duration * rs.count_executions) AS total_duration
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
GROUP BY q.query_id, qt.query_sql_text
ORDER BY total_duration DESC;
```
