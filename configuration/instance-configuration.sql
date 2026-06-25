/*
    Configuration / Instance configuration
    Instance settings via sp_configure (MAXDOP, memory, and more).
*/

-- All current instance settings with running vs configured values.
-- value_in_use lags value until RECONFIGURE runs.
SELECT name, value, value_in_use, is_dynamic, is_advanced, description
FROM sys.configurations
ORDER BY name;

-- Recommended MAXDOP from the current core and NUMA layout.
-- Single NUMA node: cap at logical cores, max 8.
-- Multiple NUMA nodes: cap at cores per node, max 16. SQL Server 2019+ also sets
-- a recommended value at install, so review the current value before changing it.
SELECT
    cpu_count,
    softnuma_configuration_desc,
    cpu_count / NULLIF(numa_node_count, 0)                          AS cores_per_numa_node,
    numa_node_count,
    CASE
        WHEN numa_node_count = 1
            THEN CASE WHEN cpu_count > 8 THEN 8 ELSE cpu_count END
        ELSE CASE
                 WHEN cpu_count / numa_node_count > 16 THEN 16
                 WHEN cpu_count / numa_node_count > 8  THEN 8
                 ELSE cpu_count / numa_node_count
             END
    END                                                            AS recommended_maxdop
FROM
(
    SELECT
        cpu_count,
        softnuma_configuration_desc,
        (SELECT COUNT(DISTINCT memory_node_id)
         FROM sys.dm_os_memory_nodes
         WHERE memory_node_id <> 64)                               AS numa_node_count
    FROM sys.dm_os_sys_info
) AS s;

-- Active trace flags on this instance.
-- -1 reports global flags; without it you only see session flags.
DBCC TRACESTATUS(-1) WITH NO_INFOMSGS;

-- Apply configuration changes. Review the values first, then uncomment.
-- RECONFIGURE applies the change; value_in_use updates afterward.
/*
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

-- Max server memory (MB). Leave headroom for the OS and other services;
-- do not give SQL Server all physical RAM. Set the target value in MB.
EXEC sys.sp_configure 'max server memory (MB)', 0; -- set MB
RECONFIGURE;
GO

-- Cost threshold for parallelism. Default 5 is too low on modern hardware.
EXEC sys.sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
GO

-- MAXDOP. Use the recommended value from the query above (0 = use all cores).
EXEC sys.sp_configure 'max degree of parallelism', 0; -- set MAXDOP
RECONFIGURE;
GO
*/
