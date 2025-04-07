/**********************************************************************************************/
-- script stored procedures from the database
-- v1.0 (2016-09-23)

DECLARE @sql nvarchar(max) = N''

DECLARE @Procedures TABLE (SchemaName nvarchar(255), ProcedureName nvarchar(255));

INSERT INTO @Procedures
SELECT 
	s.name AS 'SchemaName',
	p.name AS 'ProcedureName'
FROM sys.procedures p 
	join sys.schemas s 
	ON s.schema_id = p.schema_id 
WHERE p.type = 'P'

/* alternatively, manually list procedure names
------------------------------------------------------------
DELETE FROM @Procedures
INSERT INTO @Procedures (SchemaName, ProcedureName)
VALUES
     ('reporting', 'sp_APD_information_chd_teen')
    ,('crm', 'SelectBookingTransactionList')
    ,('etl', 'sp_Cancelled_Flight')
------------------------------------------------------------
*/

;WITH cte (CreateSchemas)
AS
(
	SELECT DISTINCT 
		'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''' + SchemaName + ''')
		BEGIN
			EXEC( ''CREATE SCHEMA ' + SchemaName + ''' );
		END; '
	FROM @Procedures
)
SELECT @sql = @sql + CreateSchemas FROM cte

SELECT @sql AS 'Create Schemas'
SELECT OBJECT_DEFINITION(OBJECT_ID(SchemaName + '.' + ProcedureName)) AS 'Create Procedures' FROM @Procedures