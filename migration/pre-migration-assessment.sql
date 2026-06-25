/*
    Migration / Pre-migration assessment
    Read-only discovery of a source SQL Server before migrating.
*/

-- Run on the SOURCE instance as sysadmin, or with VIEW SERVER STATE + VIEW ANY DEFINITION.
-- SSMS "Results to Text" is easier to read than the grid for this report.
-- Assumes SQL Server 2016 or later as the source.

SET NOCOUNT ON;
SET ANSI_WARNINGS OFF;  -- silence aggregate NULL-elimination warnings in the size rollups

PRINT '============================================================================';
PRINT ' SECTION 1: SERVER INFO';
PRINT '============================================================================';

SELECT
    @@SERVERNAME                                              AS server_name,
    SERVERPROPERTY('MachineName')                             AS machine_name,
    SERVERPROPERTY('InstanceName')                            AS instance_name,
    SERVERPROPERTY('ProductVersion')                          AS product_version,
    SERVERPROPERTY('ProductLevel')                            AS product_level,
    SERVERPROPERTY('ProductUpdateLevel')                      AS product_update_level,
    SERVERPROPERTY('Edition')                                 AS edition,
    SERVERPROPERTY('EngineEdition')                           AS engine_edition,
    SERVERPROPERTY('Collation')                               AS server_collation,
    SERVERPROPERTY('IsClustered')                             AS is_clustered,
    SERVERPROPERTY('IsHadrEnabled')                           AS is_hadr_enabled,
    SERVERPROPERTY('IsFullTextInstalled')                     AS is_fulltext_installed,
    SERVERPROPERTY('IsIntegratedSecurityOnly')                AS is_integrated_security_only,
    SERVERPROPERTY('LicenseType')                             AS license_type,
    SERVERPROPERTY('NumLicenses')                             AS num_licenses,
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)     AS sql_start_time,
    SYSDATETIME()                                             AS collected_at;

PRINT '';
PRINT '-- OS / hardware (needs VIEW SERVER STATE):';

-- sql_memory_model_desc was added in 2016 SP1; select it dynamically so a
-- 2016 RTM source does not hard-fail on an invalid column name.
DECLARE @sysinfo_sql NVARCHAR(MAX) = N'
SELECT
    cpu_count,
    hyperthread_ratio,
    physical_memory_kb / 1024 / 1024  AS physical_memory_gb,
    virtual_memory_kb  / 1024 / 1024  AS virtual_memory_gb,
    committed_kb       / 1024         AS committed_mb,
    committed_target_kb/ 1024         AS committed_target_mb'
    + CASE WHEN EXISTS (SELECT 1 FROM sys.system_columns
                        WHERE object_id = OBJECT_ID('sys.dm_os_sys_info')
                          AND name = 'sql_memory_model_desc')
           THEN N',
    sql_memory_model_desc'
           ELSE N'' END
    + N'
FROM sys.dm_os_sys_info;';
EXEC sp_executesql @sysinfo_sql;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 2: DATABASES OVERVIEW';
PRINT '============================================================================';

;WITH db_sizes AS (
    SELECT
        database_id,
        SUM(CONVERT(bigint, CASE WHEN type_desc = 'ROWS' THEN size END)) / 128  AS data_mb,
        SUM(CONVERT(bigint, CASE WHEN type_desc = 'LOG'  THEN size END)) / 128  AS log_mb,
        SUM(CONVERT(bigint, size))                                       / 128  AS total_mb
    FROM sys.master_files
    GROUP BY database_id
)
SELECT
    d.database_id,
    d.name                                                                  AS database_name,
    SUSER_SNAME(d.owner_sid)                                                AS db_owner,
    d.state_desc,
    d.recovery_model_desc,
    d.compatibility_level,
    d.collation_name,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.snapshot_isolation_state_desc,
    d.is_read_committed_snapshot_on,
    d.containment_desc,
    d.is_encrypted                                                          AS is_tde_encrypted,
    d.is_published,
    d.is_subscribed,
    d.is_merge_published,
    d.is_distributor,
    d.is_cdc_enabled,
    d.is_broker_enabled,
    CASE WHEN EXISTS (SELECT 1 FROM sys.change_tracking_databases ct
                      WHERE ct.database_id = d.database_id)
         THEN 1 ELSE 0 END                                                  AS is_change_tracking_on,
    s.data_mb,
    s.log_mb,
    s.total_mb,
    d.create_date,
    DATABASEPROPERTYEX(d.name, 'Updateability')                             AS updateability,
    DATABASEPROPERTYEX(d.name, 'UserAccess')                                AS user_access
FROM sys.databases d
LEFT JOIN db_sizes s ON s.database_id = d.database_id
ORDER BY d.database_id;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 3: DATABASE FILES (location, size, autogrowth)';
PRINT '============================================================================';

SELECT
    DB_NAME(mf.database_id)                          AS database_name,
    mf.file_id,
    mf.type_desc,
    mf.name                                          AS logical_name,
    mf.physical_name,
    mf.state_desc,
    mf.size / 128                                    AS size_mb,
    CASE WHEN mf.max_size = -1 THEN NULL
         WHEN mf.max_size =  0 THEN 0
         ELSE mf.max_size / 128 END                  AS max_size_mb,
    CASE WHEN mf.is_percent_growth = 1
         THEN CAST(mf.growth AS VARCHAR(10)) + ' %'
         ELSE CAST(mf.growth / 128 AS VARCHAR(10)) + ' MB' END  AS autogrowth,
    mf.is_read_only
FROM sys.master_files mf
WHERE DB_NAME(mf.database_id) NOT IN ('master','model','msdb','tempdb','distribution')
ORDER BY DB_NAME(mf.database_id), mf.type_desc DESC, mf.file_id;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 4: ALWAYS ON AVAILABILITY GROUPS';
PRINT '============================================================================';

IF SERVERPROPERTY('IsHadrEnabled') = 1
BEGIN
    SELECT
        ag.name                          AS ag_name,
        ag.failure_condition_level,
        ag.health_check_timeout,
        ag.automated_backup_preference_desc,
        ar.replica_server_name,
        ar.availability_mode_desc,
        ar.failover_mode_desc,
        ar.session_timeout,
        ars.role_desc,
        ars.operational_state_desc,
        ars.synchronization_health_desc
    FROM sys.availability_groups ag
    JOIN sys.availability_replicas       ar  ON ar.group_id = ag.group_id
    JOIN sys.dm_hadr_availability_replica_states ars
                                             ON ars.replica_id = ar.replica_id
    ORDER BY ag.name, ar.replica_server_name;

    PRINT '-- AG databases:';
    SELECT
        ag.name                          AS ag_name,
        adc.database_name,
        ar.replica_server_name,
        drs.synchronization_state_desc,
        drs.synchronization_health_desc,
        drs.database_state_desc
    FROM sys.availability_groups ag
    JOIN sys.availability_databases_cluster adc ON adc.group_id = ag.group_id
    JOIN sys.dm_hadr_database_replica_states drs ON drs.group_id = ag.group_id
                                                AND drs.group_database_id = adc.group_database_id
    JOIN sys.availability_replicas ar           ON ar.replica_id = drs.replica_id;
END
ELSE
BEGIN
    PRINT 'Always On AG: not enabled on this instance.';
END

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 5: DATABASE MIRRORING';
PRINT '============================================================================';

IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE mirroring_guid IS NOT NULL)
BEGIN
    SELECT
        DB_NAME(database_id)         AS database_name,
        mirroring_role_desc,
        mirroring_state_desc,
        mirroring_safety_level_desc,
        mirroring_partner_name,
        mirroring_partner_instance,
        mirroring_witness_name,
        mirroring_witness_state_desc
    FROM sys.database_mirroring
    WHERE mirroring_guid IS NOT NULL;
END
ELSE
BEGIN
    PRINT 'Database Mirroring: not configured.';
END

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 6: REPLICATION (publishers, subscribers, distributor)';
PRINT '============================================================================';

IF EXISTS (SELECT 1 FROM sys.databases WHERE is_distributor = 1)
BEGIN
    PRINT 'This instance is a distributor.';
END

IF EXISTS (SELECT 1 FROM sys.databases WHERE is_published = 1 OR is_merge_published = 1 OR is_subscribed = 1)
BEGIN
    SELECT
        name                  AS database_name,
        is_published          AS trans_or_snapshot_publisher,
        is_merge_published    AS merge_publisher,
        is_subscribed         AS subscriber,
        is_distributor
    FROM sys.databases
    WHERE is_published = 1 OR is_merge_published = 1 OR is_subscribed = 1 OR is_distributor = 1;

    PRINT '-- Detailed publication list (from distribution DB if present):';
    IF DB_ID('distribution') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) = N'
            SELECT
                p.publisher_id, p.publisher_db, p.publication, p.publication_type,
                COUNT_BIG(*) AS article_count
            FROM distribution.dbo.MSpublications p
            LEFT JOIN distribution.dbo.MSarticles a ON a.publication_id = p.publication_id
            GROUP BY p.publisher_id, p.publisher_db, p.publication, p.publication_type;';
        EXEC sp_executesql @sql;
    END
END
ELSE
BEGIN
    PRINT 'Replication: no published, merge-published, or subscribed databases.';
END

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 7: LOG SHIPPING';
PRINT '============================================================================';

IF EXISTS (SELECT 1 FROM msdb.sys.tables WHERE name = 'log_shipping_primary_databases')
BEGIN
    SELECT 'PRIMARY' AS role, primary_database, backup_directory, backup_share, monitor_server
    FROM msdb.dbo.log_shipping_primary_databases;

    SELECT 'SECONDARY' AS role,
           sd.secondary_database,
           s.primary_server,
           s.primary_database,
           sd.restore_delay,
           sd.restore_mode,
           sd.disconnect_users
    FROM msdb.dbo.log_shipping_secondary_databases sd
    JOIN msdb.dbo.log_shipping_secondary s ON s.secondary_id = sd.secondary_id;
END
ELSE
BEGIN
    PRINT 'Log shipping tables not found in msdb.';
END

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 8: LINKED SERVERS';
PRINT '============================================================================';

SELECT
    name,
    product,
    provider,
    data_source,
    catalog,
    is_remote_login_enabled,
    is_rpc_out_enabled,
    is_data_access_enabled,
    modify_date
FROM sys.servers
WHERE server_id <> 0
ORDER BY name;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 9: CLR / SQLCLR ASSEMBLIES';
PRINT '============================================================================';

DECLARE @clr_cmd NVARCHAR(MAX) = N'
SELECT
    DB_NAME() AS database_name,
    a.name,
    a.permission_set_desc,
    a.is_visible,
    a.create_date,
    a.modify_date,
    af.file_id,
    DATALENGTH(af.content) / 1024 AS assembly_kb
FROM sys.assemblies a
LEFT JOIN sys.assembly_files af ON af.assembly_id = a.assembly_id
WHERE a.is_user_defined = 1;';

DECLARE @db_name SYSNAME;
DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
      AND HAS_DBACCESS(name) = 1;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @exec_sql NVARCHAR(MAX) = N'USE ' + QUOTENAME(@db_name) + N'; ' + @clr_cmd;
    BEGIN TRY
        EXEC sp_executesql @exec_sql;
    END TRY
    BEGIN CATCH
        PRINT 'CLR scan failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM db_cursor INTO @db_name;
END
CLOSE db_cursor;
DEALLOCATE db_cursor;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 10: FILESTREAM / FILETABLE';
PRINT '============================================================================';

SELECT
    SERVERPROPERTY('FilestreamConfiguredLevel') AS filestream_configured_level,
    SERVERPROPERTY('FilestreamEffectiveLevel')  AS filestream_effective_level,
    SERVERPROPERTY('FilestreamShareName')       AS filestream_share_name;

SELECT
    DB_NAME(database_id) AS database_name,
    name                 AS logical_name,
    physical_name,
    type_desc
FROM sys.master_files
WHERE type_desc IN ('FILESTREAM','MEMORY_OPTIMIZED_DATA');

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 11: IN-MEMORY OLTP, COLUMNSTORE, TEMPORAL, GRAPH (per database)';
PRINT '============================================================================';

DECLARE @db_name SYSNAME;
DECLARE @features_sql NVARCHAR(MAX) = N'
SELECT
    DB_NAME() AS database_name,
    (SELECT COUNT(*) FROM sys.tables WHERE is_memory_optimized = 1)            AS memory_optimized_tables,
    (SELECT COUNT(*) FROM sys.indexes WHERE type IN (5,6))                     AS columnstore_indexes,
    (SELECT COUNT(*) FROM sys.tables WHERE temporal_type <> 0)                 AS temporal_tables,
    (SELECT COUNT(*) FROM sys.tables WHERE is_node = 1 OR is_edge = 1)         AS graph_tables,
    (SELECT COUNT(*) FROM sys.objects WHERE type = ''AF'')                     AS aggregate_functions,
    (SELECT COUNT(*) FROM sys.fulltext_catalogs)                               AS fulltext_catalogs,
    (SELECT COUNT(*) FROM sys.service_queues WHERE is_ms_shipped = 0)          AS user_service_queues,
    (SELECT COUNT(*) FROM sys.partitions WHERE partition_number > 1)           AS partitioned_objects;';

DECLARE feat_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
      AND HAS_DBACCESS(name) = 1;

OPEN feat_cursor;
FETCH NEXT FROM feat_cursor INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @feat_exec NVARCHAR(MAX) = N'USE ' + QUOTENAME(@db_name) + N'; ' + @features_sql;
    BEGIN TRY
        EXEC sp_executesql @feat_exec;
    END TRY
    BEGIN CATCH
        PRINT 'Feature scan failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM feat_cursor INTO @db_name;
END
CLOSE feat_cursor;
DEALLOCATE feat_cursor;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 12: CHANGE DATA CAPTURE / CHANGE TRACKING';
PRINT '============================================================================';

SELECT
    d.name                AS database_name,
    d.is_cdc_enabled,
    CASE WHEN ct.database_id IS NOT NULL THEN 1 ELSE 0 END AS is_change_tracking_on
FROM sys.databases d
LEFT JOIN sys.change_tracking_databases ct ON ct.database_id = d.database_id
WHERE d.is_cdc_enabled = 1 OR ct.database_id IS NOT NULL;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 13: ENCRYPTION (TDE, Always Encrypted, EKM)';
PRINT '============================================================================';

-- encryption_state_desc is computed here; older sources do not expose it as a column.
SELECT
    DB_NAME(dek.database_id) AS database_name,
    dek.encryption_state,
    CASE dek.encryption_state
        WHEN 0 THEN 'No encryption key'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
    END                      AS encryption_state_desc,
    dek.key_algorithm,
    dek.key_length,
    dek.create_date,
    dek.opened_date,
    dek.encryptor_type
FROM sys.dm_database_encryption_keys dek
WHERE dek.database_id <> 2; -- skip tempdb

-- TDE certificates live in master. Export each with its private key before migrating.
PRINT '-- Certificates in master (TDE certs live here):';
SELECT name, subject, expiry_date, pvt_key_encryption_type_desc
FROM master.sys.certificates
WHERE name NOT LIKE '##%';

PRINT '-- EKM providers:';
SELECT * FROM sys.cryptographic_providers;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 14: LOGINS, ROLES, AUDIT';
PRINT '============================================================================';

SELECT
    sp.name,
    sp.type_desc,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date,
    sp.default_database_name,
    sp.default_language_name,
    sl.is_policy_checked,
    sl.is_expiration_checked
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sl.principal_id = sp.principal_id
WHERE sp.type IN ('S','U','G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT %'
ORDER BY sp.type_desc, sp.name;

PRINT '-- Server role membership:';
SELECT
    r.name AS server_role,
    m.name AS member_name,
    m.type_desc
FROM sys.server_role_members srm
JOIN sys.server_principals r ON r.principal_id = srm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = srm.member_principal_id
ORDER BY r.name, m.name;

PRINT '-- Server audits:';
SELECT name, type_desc, on_failure_desc, queue_delay, is_state_enabled, create_date
FROM sys.server_audits;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 15: SQL AGENT JOBS';
PRINT '============================================================================';

IF DB_ID('msdb') IS NOT NULL
BEGIN
    SELECT
        j.job_id,
        j.name,
        j.enabled,
        SUSER_SNAME(j.owner_sid) AS owner,
        c.name                    AS category,
        j.date_created,
        j.date_modified,
        j.description
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    ORDER BY j.name;

    PRINT '-- Job step subsystems used (helps spot SSIS, PowerShell, CmdExec):';
    SELECT subsystem, COUNT(*) AS step_count
    FROM msdb.dbo.sysjobsteps
    GROUP BY subsystem
    ORDER BY step_count DESC;
END

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 16: TRACE FLAGS, SERVER CONFIGURATION (non-default)';
PRINT '============================================================================';

DBCC TRACESTATUS(-1) WITH NO_INFOMSGS;

SELECT name, value, value_in_use, is_dynamic, is_advanced, description
FROM sys.configurations
WHERE CONVERT(BIGINT, value) <> CONVERT(BIGINT, value_in_use)
   OR name IN (
        'max server memory (MB)',
        'min server memory (MB)',
        'max degree of parallelism',
        'cost threshold for parallelism',
        'optimize for ad hoc workloads',
        'remote admin connections',
        'clr enabled',
        'cross db ownership chaining',
        'Database Mail XPs',
        'Ad Hoc Distributed Queries',
        'xp_cmdshell',
        'backup compression default',
        'contained database authentication'
   )
ORDER BY name;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 17: OBJECT COUNTS (per database)';
PRINT '============================================================================';

DECLARE @db_name SYSNAME;
DECLARE @objects_sql NVARCHAR(MAX) = N'
SELECT
    DB_NAME() AS database_name,
    SUM(CASE WHEN type = ''U''    THEN 1 ELSE 0 END) AS user_tables,
    SUM(CASE WHEN type = ''V''    THEN 1 ELSE 0 END) AS views,
    SUM(CASE WHEN type = ''P''    THEN 1 ELSE 0 END) AS stored_procedures,
    SUM(CASE WHEN type IN (''FN'',''IF'',''TF'',''FS'',''FT'')
                                  THEN 1 ELSE 0 END) AS functions,
    SUM(CASE WHEN type IN (''TR'',''TA'')
                                  THEN 1 ELSE 0 END) AS triggers,
    SUM(CASE WHEN type = ''SN''   THEN 1 ELSE 0 END) AS synonyms,
    SUM(CASE WHEN type = ''SQ''   THEN 1 ELSE 0 END) AS service_queues
FROM sys.objects;';

DECLARE obj_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
      AND HAS_DBACCESS(name) = 1;

OPEN obj_cursor;
FETCH NEXT FROM obj_cursor INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @obj_exec NVARCHAR(MAX) = N'USE ' + QUOTENAME(@db_name) + N'; ' + @objects_sql;
    BEGIN TRY
        EXEC sp_executesql @obj_exec;
    END TRY
    BEGIN CATCH
        PRINT 'Object scan failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM obj_cursor INTO @db_name;
END
CLOSE obj_cursor;
DEALLOCATE obj_cursor;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 18: LARGEST TABLES (top 20 per database by reserved size)';
PRINT '============================================================================';

DECLARE @db_name SYSNAME;
-- Size from sys.dm_db_partition_stats, rolled up per table.
-- 8 KB pages, so pages * 8 / 1024.0 gives MB.
DECLARE @top_tables_sql NVARCHAR(MAX) = N'
SELECT TOP 20
    DB_NAME()                                       AS database_name,
    SCHEMA_NAME(t.schema_id)                        AS schema_name,
    t.name                                          AS table_name,
    SUM(ps.row_count)                               AS row_count,
    SUM(ps.reserved_page_count) * 8 / 1024.0        AS reserved_mb,
    SUM(ps.used_page_count)     * 8 / 1024.0        AS used_mb
FROM sys.tables t
JOIN sys.dm_db_partition_stats ps ON ps.object_id = t.object_id
GROUP BY t.schema_id, t.name
ORDER BY SUM(ps.reserved_page_count) DESC;';

DECLARE tbl_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
      AND HAS_DBACCESS(name) = 1;

OPEN tbl_cursor;
FETCH NEXT FROM tbl_cursor INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @tbl_exec NVARCHAR(MAX) = N'USE ' + QUOTENAME(@db_name) + N'; ' + @top_tables_sql;
    BEGIN TRY
        EXEC sp_executesql @tbl_exec;
    END TRY
    BEGIN CATCH
        PRINT 'Top-tables scan failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM tbl_cursor INTO @db_name;
END
CLOSE tbl_cursor;
DEALLOCATE tbl_cursor;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 19: BACKUPS (last full, diff, log per database)';
PRINT '============================================================================';

;WITH last_bk AS (
    SELECT
        database_name,
        type,
        backup_finish_date,
        backup_size / 1024.0 / 1024 AS backup_mb,
        ROW_NUMBER() OVER (PARTITION BY database_name, type
                           ORDER BY backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset
)
SELECT
    database_name,
    MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS last_full,
    MAX(CASE WHEN type = 'I' THEN backup_finish_date END) AS last_diff,
    MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS last_log,
    MAX(CASE WHEN type = 'D' THEN backup_mb           END) AS last_full_mb
FROM last_bk
WHERE rn = 1
GROUP BY database_name
ORDER BY database_name;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' SECTION 20: AZURE-BLOCKING / COMPATIBILITY HINTS';
PRINT '============================================================================';
DECLARE @db_name SYSNAME;
PRINT 'Common blockers and limits when moving to Azure. Tags mark the affected target:';
PRINT '  [SQL DB] Azure SQL Database   [MI] Azure SQL Managed Instance   [VM] SQL Server on Azure VM';
PRINT 'Quick first pass only. For authoritative results run Azure Data Migration';
PRINT 'Assistant (DMA), Azure Migrate, and SqlPackage.';

-- [SQL DB][MI] xp_cmdshell: not supported on SQL DB or MI; native on VM.
SELECT 'xp_cmdshell enabled [SQL DB][MI]' AS check_name,
       CAST(value_in_use AS INT) AS value
FROM sys.configurations WHERE name = 'xp_cmdshell';

-- [SQL DB] Cross-db ownership chaining: SQL DB has no cross-database access at all.
SELECT 'cross db ownership chaining [SQL DB]' AS check_name,
       CAST(value_in_use AS INT) AS value
FROM sys.configurations WHERE name = 'cross db ownership chaining';

-- [SQL DB] Service Broker: SQL DB has no Service Broker; MI/VM support it (MI is intra-instance only).
SELECT 'user Service Broker queues [SQL DB]' AS check_name, COUNT(*) AS value
FROM sys.service_queues WHERE is_ms_shipped = 0;

-- [SQL DB][MI] Mirroring endpoints: database mirroring not available in PaaS (built-in HA instead).
SELECT 'mirroring endpoints [SQL DB][MI]' AS check_name, COUNT(*) AS value
FROM sys.database_mirroring_endpoints;

-- [SQL DB][MI] FILESTREAM: not supported in PaaS.
SELECT 'databases using FILESTREAM [SQL DB][MI]' AS check_name, COUNT(DISTINCT database_id) AS value
FROM sys.master_files WHERE type_desc = 'FILESTREAM';

-- [SQL DB][MI] FileTable and [SQL DB] CLR are database-scoped, so scan each user DB.
-- FileTable depends on FILESTREAM (not supported in PaaS). SQL DB has no SQLCLR; MI and VM do.
DECLARE @filetable_count INT = 0, @clr_count INT = 0;
DECLARE @blk_scan NVARCHAR(MAX);
DECLARE blk_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4 AND HAS_DBACCESS(name) = 1;
OPEN blk_cur;
FETCH NEXT FROM blk_cur INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @blk_scan = N'USE ' + QUOTENAME(@db_name) + N';
            SELECT @ft = @ft + (SELECT COUNT(*) FROM sys.tables WHERE is_filetable = 1),
                   @clr = @clr + (SELECT COUNT(*) FROM sys.assemblies WHERE is_user_defined = 1);';
        EXEC sp_executesql @blk_scan,
            N'@ft INT OUTPUT, @clr INT OUTPUT',
            @ft = @filetable_count OUTPUT, @clr = @clr_count OUTPUT;
    END TRY
    BEGIN CATCH
        PRINT 'FileTable/CLR count failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM blk_cur INTO @db_name;
END
CLOSE blk_cur;
DEALLOCATE blk_cur;
SELECT 'FileTable tables (all user DBs) [SQL DB][MI]' AS check_name, @filetable_count AS value
UNION ALL
SELECT 'user CLR assemblies (all user DBs) [SQL DB]', @clr_count;

-- [SQL DB] Linked servers: SQL DB has no linked servers (use external data sources); MI supports a subset.
SELECT 'linked servers [SQL DB]' AS check_name, COUNT(*) AS value
FROM sys.servers WHERE server_id <> 0;

-- [SQL DB][MI] Windows / AD logins: no Windows auth in PaaS; map to Microsoft Entra ID (SQL auth also works).
SELECT 'Windows / AD logins (type G/U) [SQL DB][MI]' AS check_name, COUNT(*) AS value
FROM sys.server_principals
WHERE type IN ('G','U') AND name NOT LIKE 'NT %' AND name NOT LIKE '##%';

-- [SQL DB][MI] Database Mail: instance-level on MI/VM, not available on SQL DB.
SELECT 'Database Mail enabled [SQL DB]' AS check_name,
       CAST(ISNULL((SELECT value_in_use FROM sys.configurations WHERE name = 'Database Mail XPs'), 0) AS INT) AS value;
IF DB_ID('msdb') IS NOT NULL
BEGIN
    SELECT 'Database Mail profiles [SQL DB]' AS check_name, COUNT(*) AS value
    FROM msdb.dbo.sysmail_profile;
END

-- [SQL DB] SQL Agent jobs: no SQL Agent on SQL DB (use elastic jobs); native on MI/VM.
IF DB_ID('msdb') IS NOT NULL
BEGIN
    SELECT 'SQL Agent jobs [SQL DB]' AS check_name, COUNT(*) AS value
    FROM msdb.dbo.sysjobs;
END

-- [SQL DB] Cross-database references: SQL DB blocks 3-part-name queries across databases
-- (USE/three-part names, synonyms targeting other DBs). MI/VM keep intra-instance cross-db.
-- Heuristic only: scan module text for 3-part names and count cross-db synonyms.
DECLARE @xdb_refs INT = 0, @xdb_syn INT = 0;
DECLARE @xdb_scan NVARCHAR(MAX);
DECLARE xdb_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4 AND HAS_DBACCESS(name) = 1;
OPEN xdb_cur;
FETCH NEXT FROM xdb_cur INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @xdb_scan = N'USE ' + QUOTENAME(@db_name) + N';
            SELECT @r = @r + (SELECT COUNT(*) FROM sys.sql_modules
                              WHERE definition LIKE ''%].[%].[%''),
                   @s = @s + (SELECT COUNT(*) FROM sys.synonyms
                              WHERE PARSENAME(base_object_name, 3) IS NOT NULL);';
        EXEC sp_executesql @xdb_scan,
            N'@r INT OUTPUT, @s INT OUTPUT',
            @r = @xdb_refs OUTPUT, @s = @xdb_syn OUTPUT;
    END TRY
    BEGIN CATCH
        PRINT 'Cross-db scan failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM xdb_cur INTO @db_name;
END
CLOSE xdb_cur;
DEALLOCATE xdb_cur;
SELECT 'modules with 3-part names (heuristic) [SQL DB]' AS check_name, @xdb_refs AS value
UNION ALL
SELECT 'cross-db synonyms [SQL DB]', @xdb_syn;

-- [SQL DB][MI] Server-collation differences: PaaS instances default to SQL_Latin1_General_CP1_CI_AS.
-- tempdb / cross-db joins use the instance collation; a mismatch can break code. VM keeps source collation.
SELECT 'server collation differs from PaaS default [SQL DB][MI]' AS check_name,
       CASE WHEN CONVERT(SYSNAME, SERVERPROPERTY('Collation')) = 'SQL_Latin1_General_CP1_CI_AS'
            THEN 0 ELSE 1 END AS value;

-- [SQL DB][MI][VM] Heaps: allowed everywhere but a clustered index is recommended; flag for review, not a blocker.
DECLARE @heaps INT = 0;
DECLARE @heap_scan NVARCHAR(MAX);
DECLARE heap_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4 AND HAS_DBACCESS(name) = 1;
OPEN heap_cur;
FETCH NEXT FROM heap_cur INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @heap_scan = N'USE ' + QUOTENAME(@db_name) + N';
            SELECT @h = @h + (SELECT COUNT(*) FROM sys.indexes i
                              JOIN sys.tables t ON t.object_id = i.object_id
                              WHERE i.type = 0);';
        EXEC sp_executesql @heap_scan, N'@h INT OUTPUT', @h = @heaps OUTPUT;
    END TRY
    BEGIN CATCH
        PRINT 'Heap count failed for ' + @db_name + ': ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM heap_cur INTO @db_name;
END
CLOSE heap_cur;
DEALLOCATE heap_cur;
SELECT 'heap tables (review, not a blocker) [SQL DB][MI][VM]' AS check_name, @heaps AS value;

-- [SQL DB][MI] Legacy compatibility level (<130): plan a compat bump and regression test.
SELECT 'databases with compat level < 130 [SQL DB][MI]' AS check_name, COUNT(*) AS value
FROM sys.databases WHERE compatibility_level < 130 AND database_id > 4;

PRINT '';
GO
PRINT '============================================================================';
PRINT ' END OF ASSESSMENT';
PRINT '============================================================================';
