/**********************************************************************************************/
-- Display CLR information

-- Returns a row for each application domain in the server.
select * from sys.dm_clr_appdomains

-- Returns a row for each managed user assembly loaded into the server address space
select * from sys.dm_clr_loaded_assemblies

-- Returns a row for each property related to SQL Server CLR integration, including the version and the state of the hosted CLR.
select * from sys.dm_clr_properties

-- Returns a row for all CLR tasks currently running.
select * from sys.dm_clr_tasks

-- more insight into the operation and execution of CLR assemblies
select * from sys.dm_exec_query_stats           -- contains a row per query statement within the cached plan
select * from sys.dm_exec_cached_plans			-- can be used to view a cached query plan for a CLR query

/**********************************************************************************************/
-- Example create a .NET class library:

/*
using System;
using System.Data;
using Microsoft.SqlServer.Server;
using System.Data.SqlTypes;
using System.Data.SqlClient;
using System.Text;

public class NextCharacter
{
    [SqlFunction(DataAccess = DataAccessKind.None)]
    public static string Replace(string inputString)
    {
        StringBuilder output = new StringBuilder();
        char[] charTable = inputString.ToCharArray();

        foreach (char c in charTable)
        {
            char x;
            switch (c)
            {
                case '9':
                    x = '0';
                    break;
                case 'Z':
                    x = 'A';
                    break;
                case 'z':
                    x = 'a';
                    break;
                default:
                    x = (char)(Convert.ToUInt16(c) + 1);
                    break;
            }
            output.Append(x);
        }
        return output.ToString();
    }
}
*/

-- next, enable CLR integration on the instance
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'clr enabled', 1;
GO
RECONFIGURE;
GO

-- then deploy the assembly to the database:
CREATE ASSEMBLY NextCharacter from 'C:\NextCharacter.dll'
GO

CREATE FUNCTION NextCharacter(@input nvarchar(max))
RETURNS nvarchar(max)
AS EXTERNAL NAME NextCharacter.NextCharacter.Replace; 
GO

-- will work just like a regular function:
SELECT dbo.NextCharacter('test');
GO

UPDATE dbo.YourTable SET 
     [Name] = dbo.NextCharacter([Name])  
    ,[Passport No.] = dbo.NextCharacter([Passport No.]);
GO

/**********************************************************************************************/