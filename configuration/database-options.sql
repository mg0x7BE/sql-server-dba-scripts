/*
    Configuration / Database options
    Per-database options and scoped configurations: isolation (RCSI), stats, recovery, compat.
*/

-- Key options per online database. Watch for: RCSI off (readers block writers, SELECTs
-- time out behind INSERT/DELETE), async stats off (stats refresh stalls compiles),
-- AUTO_CLOSE/AUTO_SHRINK on, PAGE_VERIFY not CHECKSUM.
SELECT name,
       state_desc,
       recovery_model_desc,
       compatibility_level,
       is_read_committed_snapshot_on,
       snapshot_isolation_state_desc,
       is_auto_create_stats_on,
       is_auto_update_stats_on,
       is_auto_update_stats_async_on,
       is_auto_close_on,
       is_auto_shrink_on,
       page_verify_option_desc,
       collation_name
FROM sys.databases
WHERE state_desc = 'ONLINE'
ORDER BY name;

-- Database scoped configurations for one database.
-- Watch MAXDOP, LEGACY_CARDINALITY_ESTIMATION, PARAMETER_SNIFFING, QUERY_OPTIMIZER_HOTFIXES,
-- and the 2022+ feedback knobs: CE_FEEDBACK, DOP_FEEDBACK, MEMORY_GRANT_FEEDBACK_PERCENTILE.
-- is_value_default = 0 marks settings that were changed from the default.
USE [YourDatabase];
GO
SELECT configuration_id,
       name,
       value,
       value_for_secondary,
       is_value_default
FROM sys.database_scoped_configurations
ORDER BY name;

-- Change key options. Intrusive: RCSI and snapshot isolation need a brief moment with no other
-- active transactions in the database; the WITH ROLLBACK clause kicks open transactions off.
-- Review impact, then uncomment the one you need.
USE [YourDatabase];
GO
/*
-- Read Committed Snapshot: readers use row versioning instead of shared locks,
-- so they stop blocking on writers. Adds version-store load in tempdb.
ALTER DATABASE [YourDatabase] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK AFTER 5 SECONDS;

-- Async stats update: query compiles stop waiting on a synchronous stats refresh.
-- Needs AUTO_UPDATE_STATISTICS already ON to have any effect.
ALTER DATABASE [YourDatabase] SET AUTO_UPDATE_STATISTICS_ASYNC ON;

-- Hygiene defaults.
ALTER DATABASE [YourDatabase] SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE [YourDatabase] SET AUTO_CLOSE OFF;
ALTER DATABASE [YourDatabase] SET AUTO_SHRINK OFF;

-- Database scoped configuration example (0 = follow the instance MAXDOP).
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
*/
