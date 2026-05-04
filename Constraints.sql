/**********************************************************************************************/
-- find all database constraints
Use my_database_name;
GO
SELECT OBJECT_NAME(OBJECT_ID) AS NameofConstraint,
SCHEMA_NAME(schema_id) AS SchemaName,
OBJECT_NAME(parent_object_id) AS TableName,
type_desc AS ConstraintType
FROM sys.objects
WHERE type_desc LIKE '%CONSTRAINT'

/**********************************************************************************************/
-- Create a table with a check constraint
CREATE TABLE dbo.TSample 
( TSampleID int NOT NULL,
  TSampleName varchar(10) NOT NULL,
  Salary decimal(18,2) NOT NULL
  CONSTRAINT SalaryCap CHECK (Salary < 100000)
);

/**********************************************************************************************/
-- Disable the constraint 
ALTER TABLE dbo.TSample NOCHECK CONSTRAINT SalaryCap;

/**********************************************************************************************/
-- Re-enable the constraint. Notice that it works even though
-- existing data does not meet the constraint. 
-- Note that NOCHECK is the default. 
ALTER TABLE dbo.TSample CHECK CONSTRAINT SalaryCap;

/**********************************************************************************************/
-- Then check the sys.check_constraints
-- note the check constraint status in the is_not_trusted column.
SELECT name, is_not_trusted FROM sys.check_constraints;

/**********************************************************************************************/
-- Disable the constraint and and enable again but this time use WITH CHECK. 
ALTER TABLE dbo.TSample NOCHECK CONSTRAINT SalaryCap;
ALTER TABLE dbo.TSample WITH CHECK CHECK CONSTRAINT SalaryCap;

/**********************************************************************************************/
