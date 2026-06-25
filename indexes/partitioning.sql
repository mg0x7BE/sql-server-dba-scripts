/*
    Indexes / Partitioning
    Inspect partitioned tables and indexes: rows and space per partition, partition metadata, $PARTITION routing.
*/

USE [YourDatabase];
GO

-- Partition function/scheme metadata: boundary values and which filegroup each range lands on.
-- Use to understand the partition layout before touching data.
SELECT
    pf.name              AS partition_function,
    ps.name              AS partition_scheme,
    pf.type_desc         AS range_type,
    pf.boundary_value_on_right,
    rv.boundary_id,
    rv.value             AS boundary_value,
    fg.name              AS filegroup_name
FROM sys.partition_functions pf
JOIN sys.partition_schemes ps
    ON ps.function_id = pf.function_id
JOIN sys.destination_data_spaces dds
    ON dds.partition_scheme_id = ps.data_space_id
JOIN sys.filegroups fg
    ON fg.data_space_id = dds.data_space_id
LEFT JOIN sys.partition_range_values rv
    ON rv.function_id = pf.function_id
   AND rv.boundary_id = dds.destination_id - 1
ORDER BY pf.name, ps.name, dds.destination_id;

-- Row count per non-empty partition for one or more tables/indexes.
-- Quick check for partition-level skew.
SELECT
    OBJECT_NAME(p.object_id) AS object_name,
    p.partition_number,
    SUM(p.rows)              AS [rows]
FROM sys.partitions p
WHERE p.object_id IN (OBJECT_ID(N'dbo.YourTable'), OBJECT_ID(N'dbo.YourOtherTable'))
  AND p.rows > 0
GROUP BY OBJECT_NAME(p.object_id), p.partition_number
ORDER BY object_name, p.partition_number;

-- Rows and reserved space per partition for a table and its indexes/indexed views.
-- Shows distribution across index_id and filegroup; uses dm_db_partition_stats for page counts.
SELECT
    OBJECT_NAME(p.object_id)      AS object_name,
    p.index_id,
    i.name                        AS index_name,
    p.partition_number,
    ps.row_count,
    ps.reserved_page_count * 8    AS reserved_kb,
    ps.used_page_count * 8        AS used_kb,
    FILEGROUP_NAME(au.data_space_id) AS filegroup_name
FROM sys.partitions p
JOIN sys.dm_db_partition_stats ps
    ON ps.partition_id = p.partition_id
JOIN sys.allocation_units au
    ON au.container_id = p.hobt_id
   AND au.type = 1                              -- IN_ROW_DATA; drop this filter to include LOB/overflow
LEFT JOIN sys.indexes i
    ON i.object_id = p.object_id
   AND i.index_id = p.index_id
WHERE p.object_id IN (OBJECT_ID(N'dbo.YourTable'), OBJECT_ID(N'dbo.YourIndexedView'))
ORDER BY object_name, p.index_id, p.partition_number;

-- Map a single value to its partition number using the partition function directly.
-- Useful to confirm where a given key would land. Replace YourPartitionFunction and set @Value.
DECLARE @Value sql_variant = NULL;
SELECT $PARTITION.YourPartitionFunction(@Value) AS partition_number;
GO

-- Row count per partition computed via $PARTITION on the partitioning column.
-- Cross-check against sys.partitions, or use when the partitioning column is what you care about.
SELECT
    $PARTITION.YourPartitionFunction(PartitionColumn) AS partition_number,
    COUNT(*)                                          AS [rows]
FROM dbo.YourTable
GROUP BY $PARTITION.YourPartitionFunction(PartitionColumn)
ORDER BY partition_number;

-- Return all rows from one specific partition.
-- Replace 5 with the target partition number from the queries above.
SELECT *
FROM dbo.YourTable
WHERE $PARTITION.YourPartitionFunction(PartitionColumn) = 5;
