/**********************************************************************************************/
-- Returns information about the current resource pool state, 
-- the current configuration of resource pools, and resource pool statistics.
select * from sys.dm_resource_governor_resource_pools

/**********************************************************************************************/
-- Returns workload group statistics and the current in-memory configuration of the workload group.
-- This view can be joined with sys.dm_resource_governor_resource_pools to get the resource pool name.
select * from sys.dm_resource_governor_workload_groups

/**********************************************************************************************/
-- Get the stored metadata.
select 
object_schema_name(classifier_function_id) as 'Classifier UDF schema in metadata', 
object_name(classifier_function_id) as 'Classifier UDF name in metadata'
from 
sys.resource_governor_configuration
go

/**********************************************************************************************/
-- Get the in-memory configuration.
select 
object_schema_name(classifier_function_id) as 'Active classifier UDF schema', 
object_name(classifier_function_id) as 'Active classifier UDF name'
from 
sys.dm_resource_governor_configuration
go



