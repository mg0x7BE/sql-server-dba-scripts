/**********************************************************************************************/
-- file locations
select * from [AdventureWorks2012].sys.database_files

/**********************************************************************************************/
-- database size
    exec sp_spaceused

/**********************************************************************************************/
-- log size and log space used
    DBCC SQLPERF(LOGSPACE);

/**********************************************************************************************/
-- check file growth settings
SELECT
    DB_NAME(database_id) AS database_name,
    type_desc,
    CASE
        WHEN is_percent_growth = 1 THEN CAST(growth AS VARCHAR(10)) + '%'
        ELSE CAST(CAST(growth AS BIGINT) * 8 / 1024 AS VARCHAR(20)) + ' MB'
        END AS growth_mb,
    CASE
        WHEN max_size = -1 THEN 'Unlimited'
        WHEN max_size = 0 THEN 'No growth'
        WHEN type_desc = 'LOG' THEN CAST(CAST(max_size AS BIGINT) * 8 / 1024 / 1024 / 1024 AS VARCHAR(20)) + ' TB'
        ELSE CAST(CAST(max_size AS BIGINT) * 8 / 1024 / 1024 AS VARCHAR(20)) + ' GB'
        END AS max_size,
    is_percent_growth
FROM sys.master_files
ORDER BY
    CASE
        WHEN database_id IN (1,2,3,4) THEN 0
        ELSE 1
        END,
    DB_NAME(database_id),
    type_desc

/**********************************************************************************************/
-- find biggest DBs on specific drive
select db_name(database_id) as [DB_Name], ROUND(SUM(mf.size) * 8 / 1024, 0) Size_MBs
from sys.master_files mf
where physical_name like 'H:%' and db_name(database_id) not in ('master','model','msdb')
group by db_name(database_id) order by 2 desc

/**********************************************************************************************/
-- list logical names and order just like GUI does
select DB_NAME(database_id) as db_name, file_id, type_desc, data_space_id,
       name, physical_name from sys.master_files mf
where database_id = DB_ID('my_database_name') order by mf.type, (CASE WHEN file_id = 1 THEN 0 ELSE 1 END), mf.name

/**********************************************************************************************/
-- LUN names used by instance
select distinct SUBSTRING(physical_name,0,CHARINDEX('\',physical_name,6)) from sys.master_files

/**********************************************************************************************/
-- log_reuse_wait
SELECT name, log_reuse_wait_desc FROM sys.databases

-- get size of all databases
SELECT  d.name,
        ROUND(SUM(mf.size) * 8 / 1024, 0) Size_MBs
FROM    sys.master_files mf
            INNER JOIN sys.databases d ON d.database_id = mf.database_id
WHERE   d.database_id > 4 -- Skip system databases
GROUP BY d.name
ORDER BY d.name

/**********************************************************************************************/
-- space used by files
select
    FILEID
     ,NAME
     ,FILENAME
     ,FILE_SIZE_MB
     ,SPACE_USED_MB
     ,convert(int,([SPACE_USED_MB]/[FILE_SIZE_MB])*100) as PERCENT_USED
     ,FREE_SPACE_MB
from
    (
        select
            a.FILEID,
            [FILE_SIZE_MB] =
            convert(decimal(15,2),round(a.size/128.000,2)),
            [SPACE_USED_MB] =
            convert(decimal(15,2),round(fileproperty(a.name,'SpaceUsed')/128.000,2)),
            [FREE_SPACE_MB] =
            convert(decimal(15,2),round((a.size-fileproperty(a.name,'SpaceUsed'))/128.000,2)) ,
            NAME = a.NAME,
            FILENAME = a.FILENAME
        from
            dbo.sysfiles a
    ) x   order by 2

/**********************************************************************************************/
-- some LUNs getting full?
    sp_msforeachdb '
use [?]
SELECT
    name,
    size/128 AS ''size'',
    FILEPROPERTY(name, ''spaceused'')/128 AS ''spaceused'',
    size/128-FILEPROPERTY(name, ''spaceused'')/128 AS ''spaceunused'',
    CAST ((FILEPROPERTY(name, ''spaceused'')*100)/size AS float(1)) AS ''percent_full''
FROM
[?].sys.database_files
ORDER BY spaceunused DESC'

/**********************************************************************************************/
-- specific LUNs getting full?
sp_msforeachdb '
use [?]
SELECT
    name,
    size/128 AS ''size'',
    FILEPROPERTY(name, ''spaceused'')/128 AS ''spaceused'',
    size/128-FILEPROPERTY(name, ''spaceused'')/128 AS ''spaceunused'',
    CAST ((FILEPROPERTY(name, ''spaceused'')*100)/size AS float(1)) AS ''percent_full'',
    physical_name
FROM
[?].sys.database_files
where physical_name like ''O:\server_userdbs_oltp_0[1234]%''
ORDER BY spaceunused DESC'


/**********************************************************************************************/
-- monitor tempdb size - This query identifies and expresses tempdb space used (in KBs)
-- by internal objects, free space, version store, and user objects
-- It is recommended that this is run every week, at a minimum.
select
    sum(internal_object_reserved_page_count)*8 as internal_objects_kb,
    sum(unallocated_extent_page_count)*8 as freespace_kb,
    sum(version_store_reserved_page_count)*8 as version_store_kb,
    sum(user_object_reserved_page_count)*8 as user_objects_kb
from sys.dm_db_file_space_usage
where database_id = 2

/**********************************************************************************************/
-- number of rows and the size the tables in your database
SELECT
    t.NAME AS TableName,
    SUM(p.rows) AS RowCounts,
    SUM(a.total_pages) * 8 AS TotalSpaceKB,
    SUM(a.used_pages) * 8 AS UsedSpaceKB,
    (SUM(a.total_pages) - SUM(a.used_pages)) * 8 AS UnusedSpaceKB
FROM
    sys.tables t
        INNER JOIN
    sys.indexes i ON t.OBJECT_ID = i.object_id
        INNER JOIN
    sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
        INNER JOIN
    sys.allocation_units a ON p.partition_id = a.container_id
WHERE
    t.NAME NOT LIKE 'dt%'
  AND t.is_ms_shipped = 0
  AND i.OBJECT_ID > 255
GROUP BY
    t.Name
ORDER BY
    4 desc

/**********************************************************************************************/
-- Get allocation units by file and partition
select
    OBJECT_NAME(p.object_id) as my_table_name,
    u.type_desc,
    f.file_id,
    f.name,
    f.physical_name,
    f.size,
    f.max_size,
    f.growth,
    u.total_pages,
    u.used_pages,
    u.data_pages,
    p.partition_id,
    p.rows
from sys.allocation_units u
         join sys.database_files f on u.data_space_id = f.data_space_id
         join sys.partitions p on u.container_id = p.hobt_id
where
    u.type in (1, 3) -- and
--OBJECT_NAME(p.object_id) = 'PageSplits'
order by
    p.rows desc
/**********************************************************************************************/