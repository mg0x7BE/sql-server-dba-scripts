# Vendor scripts

Third party scripts kept here as-is. They are not my work. Original headers,
copyright, and license terms are preserved inside each file. Use at your own risk.

## glenn-berry-diagnostic-queries-2025.sql

SQL Server 2025 Diagnostic Information Queries by Glenn Berry.
The standard DMV based health check for the box product (on-prem SQL Server).

- Author: Glenn Berry
- Site: https://glennsqlperformance.com/
- License: free for non-commercial use, keep the copyright header and give credit.

Only the SQL Server 2025 (box product) edition is kept here. The Azure SQL Database
and Azure SQL Managed Instance editions were removed because this repo targets
SQL Server 2025 Enterprise only. Get them from the author's site if you need them.

## sp_whoisactive.sql

sp_WhoIsActive by Adam Machanic. Live activity monitoring stored procedure
(sessions, blocking, waits, plans). Installs dbo.sp_WhoIsActive.

- Author: Adam Machanic
- Site: http://whoisactive.com/
- License: free for personal, educational, and internal corporate use; keep the
  header; redistribution or sale needs the author's written consent.

Note: the vendored copy is v11.32 (2018). Check the site for a newer release
before relying on it on SQL Server 2025.
