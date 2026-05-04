/**********************************************************************************************/
-- Grant SELECT permission on the Marketing.Salesperson object to the HRApp user
USE MarketDev;
GO

GRANT SELECT ON OBJECT::Marketing.Salesperson
	TO HRApp;
GO

-- Same
GRANT SELECT ON Marketing.Salesperson
	TO HRApp;
GO

/**********************************************************************************************/
-- Column-level Security
GRANT SELECT ON Marketing.Salesperson
	( SalespersonID, EmailAlias )
TO James;
GO


/**********************************************************************************************/
-- Permissions granted with using WITH GRANT OPTION can be 
-- granted to other principals by the grantee
-- In general, WITH GRANT OPTION should be avoided
GRANT UPDATE ON Marketing.Salesperson
TO James
WITH GRANT OPTION;
GO

/**********************************************************************************************/
-- CASCADE is used to also revoke permissions granted by the grantee
-- it can apply to DENY also
REVOKE UPDATE ON Marketing.Salesperson
FROM James
CASCADE;
GO

/**********************************************************************************************/
-- Granting Permissions at the Schema Level
GRANT EXECUTE 
	ON SCHEMA::Marketing
	TO Mod11User;
GO
GRANT SELECT
	ON SCHEMA:DirectMarketing
	TO Mod11User;
GO

DENY SELECT ON SCHEMA::DirectMarketing TO [AdventureWorks\April.Reagan];
GO

GRANT EXECUTE ON SCHEMA::DirectMarketing TO SalesTeam;
GO

GRANT SELECT, UPDATE ON Marketing.SalesPerson TO [AdventureWorks\HumanResources];
GO

GRANT EXECUTE ON Marketing.MoveCampaignBalance TO SalesManagers;
GO

/**********************************************************************************************/
--         Query the full list of server principals. This
--         list includes type C principals (certificate_mapped_logins).
--         These logins are created by SQL Server, have names enclosed
--         in ## and should not be deleted. They are logins that are
--         created from certificates.

SELECT * FROM sys.server_principals;
GO

/**********************************************************************************************/
--         Query the full list of database principals. This
--         list can include windows users, SQL users, database roles,
--         application roles, and users created from certificates.

SELECT * FROM sys.database_principals;
GO

