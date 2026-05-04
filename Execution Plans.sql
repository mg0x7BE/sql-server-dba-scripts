/**********************************************************************************************/
-- Get plans from cache
select usecounts, cacheobjtype, objtype, TEXT, query_plan, *
from sys.dm_exec_cached_plans
         cross apply sys.dm_exec_sql_text(plan_handle)
         cross apply sys.dm_exec_query_plan(plan_handle) qp
where qp.objectid in ('1522104463', '816826072')

/**********************************************************************************************/
