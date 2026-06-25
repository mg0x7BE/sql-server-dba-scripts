/*
    Performance / Memory
    Memory health: PLE, buffer pool usage, memory grants, and clerks.
*/

-- OS-level memory. Watch system_memory_state_desc for low/steady, and available_physical_memory.
SELECT total_physical_memory_kb / 1024.0 AS total_physical_memory_mb,
       available_physical_memory_kb / 1024.0 AS available_physical_memory_mb,
       total_page_file_kb / 1024.0 AS total_page_file_mb,
       available_page_file_kb / 1024.0 AS available_page_file_mb,
       system_memory_state_desc
FROM sys.dm_os_sys_memory;

-- SQL Server process memory. process_physical_memory_low / process_virtual_memory_low = 1 means pressure.
SELECT physical_memory_in_use_kb / 1024.0 AS physical_memory_in_use_mb,
       virtual_address_space_committed_kb / 1024.0 AS vas_committed_mb,
       virtual_address_space_available_kb / 1024.0 AS vas_available_mb,
       page_fault_count,
       process_physical_memory_low,
       process_virtual_memory_low
FROM sys.dm_os_process_memory;

-- Total/target server memory. Target much higher than total means SQL wants more RAM.
SELECT RTRIM(counter_name) AS counter_name, cntr_value / 1024.0 AS value_mb
FROM sys.dm_os_performance_counters
WHERE counter_name IN ('Total Server Memory (KB)', 'Target Server Memory (KB)');

-- Page Life Expectancy and buffer cache hit ratio (instance-wide).
-- Low PLE = memory pressure. Rule of thumb ~300s per 4 GB of buffer pool.
SELECT RTRIM(counter_name) AS counter_name, cntr_value, instance_name
FROM sys.dm_os_performance_counters
WHERE counter_name IN ('Page life expectancy', 'Buffer cache hit ratio', 'Buffer cache hit ratio base')
  AND object_name LIKE '%Buffer Manager%';

-- PLE per Buffer Node (per-NUMA). On NUMA the instance-wide PLE above is an average across nodes;
-- one starved node can be masked, so check nodes individually.
SELECT instance_name AS buffer_node,
       cntr_value AS ple_seconds,
       cntr_value / 60 AS ple_minutes
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
  AND object_name LIKE '%Buffer Node%';

-- Buffer pool usage by database (MB). Where the cache is going across databases.
SELECT DB_NAME(database_id) AS database_name,
       COUNT(*) * 8 / 1024.0 AS cached_mb
FROM sys.dm_os_buffer_descriptors
WHERE database_id <> 32767 -- exclude ResourceDB
GROUP BY database_id
ORDER BY cached_mb DESC;

-- Buffer pool usage by object/index in the current database.
-- Top cache consumers; also shows compression effectiveness (3=COLUMNSTORE, 4=COLUMNSTORE_ARCHIVE).
USE [YourDatabase];
GO
SELECT OBJECT_SCHEMA_NAME(p.object_id) AS schema_name,
       OBJECT_NAME(p.object_id) AS object_name,
       p.index_id,
       p.data_compression_desc,
       COUNT(*) / 128.0 AS cached_mb,
       COUNT(*) AS buffer_count
FROM sys.allocation_units AS a
JOIN sys.dm_os_buffer_descriptors AS b ON a.allocation_unit_id = b.allocation_unit_id
JOIN sys.partitions AS p ON a.container_id = p.hobt_id
WHERE b.database_id = DB_ID()
  AND p.object_id > 100 -- exclude system objects
GROUP BY p.object_id, p.index_id, p.data_compression_desc
ORDER BY buffer_count DESC;
GO

-- Query memory grants: granted (grant_time not null) and waiting (grant_time null).
-- Run a few times; many waiting rows = internal memory pressure. Large grants point at bad plans or missing indexes.
SELECT DB_NAME(st.dbid) AS database_name,
       mg.session_id,
       mg.requested_memory_kb,
       mg.granted_memory_kb,
       mg.ideal_memory_kb,
       mg.request_time,
       mg.grant_time,
       mg.query_cost,
       mg.dop,
       st.text AS query_text
FROM sys.dm_exec_query_memory_grants AS mg
OUTER APPLY sys.dm_exec_sql_text(mg.sql_handle) AS st
ORDER BY mg.requested_memory_kb DESC;

-- Memory clerks: which components hold the memory. CACHESTORE_SQLCP / OBJCP = plan cache,
-- MEMORYCLERK_SQLBUFFERPOOL = buffer pool. Replaces DBCC MEMORYSTATUS as the primary breakdown.
SELECT type,
       SUM(pages_kb) / 1024.0 AS pages_mb,
       SUM(virtual_memory_committed_kb) / 1024.0 AS vm_committed_mb
FROM sys.dm_os_memory_clerks
GROUP BY type
ORDER BY pages_mb DESC;

-- Fallback only if a clerk breakdown is not enough; verbose and hard to parse.
-- DBCC MEMORYSTATUS;

-- Advanced: historical memory pressure from the resource monitor ring buffer.
-- Legacy way to see past low-memory events that current-state DMVs above miss.
SELECT DATEADD(ms, rb.timestamp - si.ms_ticks, SYSDATETIME()) AS event_time,
       x.value('(ResourceMonitor/Notification)[1]', 'varchar(50)') AS notification,
       x.value('(ResourceMonitor/IndicatorsProcess)[1]', 'int') AS indicators_process,
       x.value('(ResourceMonitor/IndicatorsSystem)[1]', 'int') AS indicators_system,
       x.value('(MemoryNode/@id)[1]', 'int') AS memory_node_id,
       x.value('(MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') / 1024.0 AS available_physical_memory_mb,
       x.value('(MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') / 1024.0 AS available_vas_mb
FROM sys.dm_os_ring_buffers AS rb
CROSS APPLY (SELECT CAST(rb.record AS xml)) AS r(x)
CROSS JOIN sys.dm_os_sys_info AS si
WHERE rb.ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR'
ORDER BY event_time DESC;
