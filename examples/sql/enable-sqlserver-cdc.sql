-- Enable SQL Server Change Data Capture
-- Requires sysadmin for database level, db_owner for tables.
-- SQL Server Agent must be running: CDC capture and cleanup are Agent jobs.

------------------------------------------------------------------
-- 1. Enable CDC at the database level (run once per database)
------------------------------------------------------------------
EXEC sys.sp_cdc_enable_db;


------------------------------------------------------------------
-- 2. A demo table, if you want something safe to test against
------------------------------------------------------------------
CREATE TABLE dbo.Employees (
    EmployeeId INT IDENTITY(1,1) PRIMARY KEY,
    FirstName  NVARCHAR(50)  NOT NULL,
    LastName   NVARCHAR(50)  NOT NULL,
    JobTitle   NVARCHAR(50),
    HireDate   DATE          NOT NULL
);


------------------------------------------------------------------
-- 3. Enable CDC on the table
------------------------------------------------------------------
EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Employees',
    @role_name     = NULL;   -- NULL = no gating role; supply one to restrict
                             -- who can read the change tables


------------------------------------------------------------------
-- 4. Verify
------------------------------------------------------------------

-- Database level
SELECT name, is_cdc_enabled
FROM sys.databases
WHERE name = DB_NAME();

-- Table level
SELECT s.name AS schema_name,
       t.name AS table_name,
       t.is_tracked_by_cdc
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_tracked_by_cdc = 1;

-- SQL Server Agent. If this is not running, CDC captures nothing
-- and Sync will correctly report that there are no changes to read.
SELECT servicename, status_desc
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server Agent%';


------------------------------------------------------------------
-- 5. Retention
------------------------------------------------------------------
-- Check the current retention (minutes) for the cleanup job.
-- Default is 4320 minutes = 3 days, which is NOT enough if your
-- team does not work weekends. See docs/08-change-data-capture.md.
EXEC sys.sp_cdc_help_jobs;

-- Raise it, for example to 7 days:
-- EXEC sys.sp_cdc_change_job @job_type = 'cleanup', @retention = 10080;


------------------------------------------------------------------
-- Teardown, if this was a test
------------------------------------------------------------------
-- EXEC sys.sp_cdc_disable_table
--     @source_schema = 'dbo',
--     @source_name   = 'Employees',
--     @capture_instance = 'all';
-- DROP TABLE dbo.Employees;
-- EXEC sys.sp_cdc_disable_db;
