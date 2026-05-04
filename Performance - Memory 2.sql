/**********************************************************************************************/
/*
	Get total buffer usage by database

	This query rolls up buffer pool usage by database. It allows you to determine how 
	much memory each database is using in the buffer pool. It could help you to decide how 
	to deploy databases in a consolidation or scale-out effort.
*/

SELECT DB_NAME(database_id) AS [Database Name] ,
COUNT(*) * 8 /1024.0 AS [Cached Size (MB)]
FROM  sys.dm_os_buffer_descriptors
WHERE database_id > 4 -- exclude system databases
AND database_id <> 32767 -- exclude ResourceDB
GROUP BY DB_NAME(database_id)
ORDER BY [Cached Size (MB)] DESC ;

/**********************************************************************************************/
/*
	Breaks down buffers by object (table, index) in the buffer pool

	This query tells you which objects are using the most memory in your buffer pool, 
	and is filtered by the current database. It shows the table or indexed view name, the index 
	ID (which will be zero for a heap table), and the amount of memory used in the buffer 
	pool for that object. It is also a good way to see the effectiveness of data compression
*/

SELECT OBJECT_NAME(p.[object_id]) AS [ObjectName] ,
p.index_id ,
COUNT(*) /128 AS [Buffer size(MB)] ,
COUNT(*) AS [Buffer_count]
FROM  sys.allocation_units AS a
INNER JOIN sys.dm_os_buffer_descriptors
AS b ON a.allocation_unit_id = b.allocation_unit_id
INNER JOIN sys.partitions AS p ON a.container_id = p.hobt_id
WHERE b.database_id = DB_ID()
AND p.[object_id] > 100 -- exclude system objects
GROUP BY p.[object_id] ,
p.index_id
ORDER BY buffer_count DESC ;

/**********************************************************************************************/
/* 
	Shows the memory required by both running (non-null grant_time) 
	and waiting queries (null grant_time)

	This DMV allows you to check for queries that are waiting (or have recently had to wait) 
    for a memory grant

	You should periodically run this query multiple times in succession; ideally, you would 
	want to see few, if any, rows returned each time. If you do see a lot of rows returned each 
	time, this could be an indication of internal memory pressure.

	This query would also help you identify queries that are requesting relatively large 
	memory grants, perhaps because they are poorly written or because there are missing 
	indexes that make the query more expensive.
*/

SELECT DB_NAME(st.dbid) AS [DatabaseName] ,
mg.requested_memory_kb ,
mg.ideal_memory_kb ,
mg.request_time ,
mg.grant_time ,
mg.query_cost ,
mg.dop ,
st.[text]
FROM  sys.dm_exec_query_memory_grants AS mg
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS st
WHERE mg.request_time < COALESCE(grant_time, '99991231')
ORDER BY mg.requested_memory_kb DESC ;

/**********************************************************************************************/
/*
	DBCC MEMORYSTATUS
	http://support.microsoft.com/kb/907877/en-us
*/

DBCC MEMORYSTATUS

/**********************************************************************************************/
select * FROM sys.dm_os_performance_counters
where counter_name like 'Total Server Memory (KB)%'
