/*
    Performance / Resource Governor
    Resource Governor pools, workload groups, and classifier.
*/

-- Resource Governor is an Enterprise feature.

-- Resource pools: config and runtime stats.
SELECT *
FROM sys.dm_resource_governor_resource_pools;

-- Workload groups joined to their pool name.
SELECT wg.name AS workload_group,
       rp.name AS resource_pool,
       wg.*
FROM sys.dm_resource_governor_workload_groups AS wg
JOIN sys.dm_resource_governor_resource_pools AS rp
    ON wg.pool_id = rp.pool_id;

-- Classifier function: stored vs active in-memory config.
-- Mismatch means a pending change needs ALTER RESOURCE GOVERNOR RECONFIGURE.
SELECT OBJECT_SCHEMA_NAME(cfg.classifier_function_id) AS stored_classifier_schema,
       OBJECT_NAME(cfg.classifier_function_id)        AS stored_classifier_name,
       OBJECT_SCHEMA_NAME(dm.classifier_function_id)  AS active_classifier_schema,
       OBJECT_NAME(dm.classifier_function_id)         AS active_classifier_name
FROM sys.resource_governor_configuration AS cfg
CROSS JOIN sys.dm_resource_governor_configuration AS dm;
