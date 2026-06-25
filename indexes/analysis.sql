/*
    Indexes / Analysis
    Missing, unused, and duplicate index detection.
*/

-- Caveats for every script below:
--   Missing-index DMVs reset on instance restart, ignore column order, and do not
--   account for indexes that already exist - treat them as hints, not orders.
--   Usage stats (sys.dm_db_index_usage_stats) reset on restart and on index rebuild,
--   so a short uptime makes everything look unused.
--   Confirm against durable evidence in performance/query-store.sql before acting.

-- List all indexes on user tables with type.
-- Quick inventory - start here to see what exists before judging it.
USE [YourDatabase];
GO
SELECT t.name AS table_name,
       i.name AS index_name,
       i.type_desc AS index_type,
       i.is_unique,
       i.is_primary_key
FROM sys.indexes AS i
JOIN sys.tables AS t ON i.object_id = t.object_id
WHERE i.name IS NOT NULL
ORDER BY t.name, i.index_id;

-- Missing index suggestions for the current database, ranked by estimated impact.
-- Generates a CREATE statement; review and rename before running, do not apply blindly.
-- estimated_improvement is unitless - high values (millions+) since last restart are worth a look.
USE [YourDatabase];
GO
SELECT ROUND(gs.avg_total_user_cost * gs.avg_user_impact * (gs.user_seeks + gs.user_scans), 0) AS estimated_improvement,
       gs.avg_user_impact AS avg_impact_pct,
       gs.user_seeks,
       gs.user_scans,
       d.statement AS [table],
       d.equality_columns,
       d.inequality_columns,
       d.included_columns,
       'CREATE NONCLUSTERED INDEX [IX_'
           + LEFT(PARSENAME(d.statement, 1), 32) + '_'
           + CONVERT(varchar, mig.index_group_handle) + '_' + CONVERT(varchar, d.index_handle) + ']'
           + ' ON ' + d.statement
           + ' (' + ISNULL(d.equality_columns, '')
           + CASE WHEN d.equality_columns IS NOT NULL AND d.inequality_columns IS NOT NULL THEN ',' ELSE '' END
           + ISNULL(d.inequality_columns, '') + ')'
           + ISNULL(' INCLUDE (' + d.included_columns + ')', '') + ';' AS create_index_statement
FROM sys.dm_db_missing_index_groups AS mig
JOIN sys.dm_db_missing_index_group_stats AS gs ON gs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details AS d ON mig.index_handle = d.index_handle
WHERE d.database_id = DB_ID()
ORDER BY estimated_improvement DESC;

-- Unused indexes: never touched since stats were last reset.
-- Index has no row in sys.dm_db_index_usage_stats at all - candidate for cleanup.
-- Excludes heaps/clustered (index_id > 1); verify uptime before deleting anything.
USE [YourDatabase];
GO
SELECT OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
       OBJECT_NAME(i.object_id) AS table_name,
       i.name AS index_name,
       i.type_desc AS index_type
FROM sys.indexes AS i
JOIN sys.objects AS o ON i.object_id = o.object_id
WHERE o.type = 'U'
  AND i.index_id > 1
  AND i.name IS NOT NULL
  AND NOT EXISTS (SELECT 1
                  FROM sys.dm_db_index_usage_stats AS us
                  WHERE us.object_id = i.object_id
                    AND us.index_id = i.index_id
                    AND us.database_id = DB_ID())
ORDER BY schema_name, table_name, index_name;

-- Write-only indexes: maintained on every write but never read by the optimizer.
-- Zero seeks/scans/lookups with non-zero updates - costs more than the unused list above.
-- High user_writes here is wasted maintenance; strong drop candidates.
USE [YourDatabase];
GO
SELECT OBJECT_SCHEMA_NAME(o.object_id) AS schema_name,
       o.name AS table_name,
       i.name AS index_name,
       us.user_seeks + us.user_scans + us.user_lookups AS user_reads,
       us.user_updates AS user_writes,
       SUM(p.rows) AS total_rows
FROM sys.dm_db_index_usage_stats AS us
JOIN sys.indexes AS i ON us.object_id = i.object_id AND us.index_id = i.index_id
JOIN sys.partitions AS p ON us.object_id = p.object_id AND us.index_id = p.index_id
JOIN sys.objects AS o ON us.object_id = o.object_id
WHERE us.database_id = DB_ID()
  AND o.type = 'U'
  AND us.index_id > 0
GROUP BY o.object_id, o.name, i.name, us.user_seeks, us.user_scans, us.user_lookups, us.user_updates
HAVING us.user_seeks + us.user_scans + us.user_lookups = 0
ORDER BY us.user_updates DESC, schema_name, table_name;

-- Indexes on one table with key columns, included columns, and usage.
-- Eyeball this to spot duplicates and near-duplicates on a single table.
USE [YourDatabase];
GO
DECLARE @SchemaName sysname = 'dbo', @TableName sysname = 'YourTable';
SELECT i.name AS index_name,
       i.is_unique,
       ISNULL(us.user_seeks, 0) AS user_seeks,
       ISNULL(us.user_scans, 0) AS user_scans,
       ISNULL(us.user_updates, 0) AS user_updates,
       STUFF((SELECT ', ' + c.name
              FROM sys.index_columns AS ic
              JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                AND ic.is_included_column = 0
              ORDER BY ic.key_ordinal
              FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, '') AS key_columns,
       STUFF((SELECT ', ' + c.name
              FROM sys.index_columns AS ic
              JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                AND ic.is_included_column = 1
              ORDER BY c.name
              FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, '') AS included_columns
FROM sys.indexes AS i
JOIN sys.objects AS o ON i.object_id = o.object_id
JOIN sys.schemas AS s ON o.schema_id = s.schema_id
LEFT JOIN sys.dm_db_index_usage_stats AS us ON i.object_id = us.object_id
     AND i.index_id = us.index_id
     AND us.database_id = DB_ID()
WHERE o.name = @TableName
  AND s.name = @SchemaName
  AND i.name IS NOT NULL
ORDER BY key_columns, included_columns;

-- Duplicate / overlapping indexes across the whole database.
-- Exact duplicates share identical key columns (same order); review before dropping the redundant one.
-- Included-column lists may still differ - check the previous per-table script before acting.
USE [YourDatabase];
GO
WITH index_cols AS (
    SELECT i.object_id,
           i.index_id,
           i.name AS index_name,
           STRING_AGG(CASE WHEN ic.is_included_column = 0 THEN c.name END, ',')
               WITHIN GROUP (ORDER BY ic.key_ordinal) AS key_columns,
           STRING_AGG(CASE WHEN ic.is_included_column = 1 THEN c.name END, ',')
               WITHIN GROUP (ORDER BY c.name) AS included_columns
    FROM sys.indexes AS i
    JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    JOIN sys.objects AS o ON i.object_id = o.object_id
    WHERE o.type = 'U' AND i.index_id > 0
    GROUP BY i.object_id, i.index_id, i.name
)
SELECT OBJECT_SCHEMA_NAME(a.object_id) AS schema_name,
       OBJECT_NAME(a.object_id) AS table_name,
       a.index_name AS index_a,
       b.index_name AS index_b,
       a.key_columns,
       a.included_columns AS included_a,
       b.included_columns AS included_b
FROM index_cols AS a
JOIN index_cols AS b ON a.object_id = b.object_id
     AND a.key_columns = b.key_columns
     AND a.index_id < b.index_id
ORDER BY schema_name, table_name, a.key_columns;
