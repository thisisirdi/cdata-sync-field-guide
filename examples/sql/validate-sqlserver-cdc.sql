-- Validate that SQL Server CDC is actually working end to end.
-- Do not skip this. "CDC is enabled" and "CDC is working" are
-- different statements, and the gap between them is usually
-- SQL Server Agent not running.
--
-- The test that matters is step 5: the second Sync run must move
-- only the NEW rows, not the whole table.

------------------------------------------------------------------
-- Step 1: insert 100 rows
------------------------------------------------------------------
DECLARE @i INT = 1;
WHILE @i <= 100
BEGIN
    INSERT INTO dbo.Employees (FirstName, LastName, JobTitle, HireDate)
    VALUES (
        CONCAT('First', @i),
        CONCAT('Last',  @i),
        CASE @i % 3 WHEN 0 THEN 'Engineer'
                    WHEN 1 THEN 'Analyst'
                    ELSE        'Manager' END,
        DATEADD(DAY, @i, '2020-01-01')
    );
    SET @i += 1;
END;

-- Source count: expect 100
SELECT COUNT(*) AS source_rows FROM dbo.Employees;

-- Change table: expect 100 change records.
-- If this is empty, SQL Server Agent is not running.
SELECT COUNT(*) AS captured_changes FROM cdc.dbo_Employees_CT;


------------------------------------------------------------------
-- Step 2: run the Sync job, then confirm 100 rows landed
------------------------------------------------------------------
-- (run in the destination)
-- SELECT COUNT(*) FROM Employees;   -- expect 100


------------------------------------------------------------------
-- Step 3: insert 50 more
------------------------------------------------------------------
DECLARE @j INT = 101;
WHILE @j <= 150
BEGIN
    INSERT INTO dbo.Employees (FirstName, LastName, JobTitle, HireDate)
    VALUES (
        CONCAT('First', @j),
        CONCAT('Last',  @j),
        CASE @j % 3 WHEN 0 THEN 'Senior Engineer'
                    WHEN 1 THEN 'Team Lead'
                    ELSE        'Intern' END,
        DATEADD(DAY, @j, '2022-01-01')
    );
    SET @j += 1;
END;

SELECT COUNT(*) AS captured_changes FROM cdc.dbo_Employees_CT;  -- expect 150


------------------------------------------------------------------
-- Step 4: run the Sync job again
------------------------------------------------------------------
-- THIS IS THE TEST.
-- Sync should report 50 rows moved, not 150.
-- 150 means it is doing a full reload and is not reading the
-- change stream. Stop and fix the job configuration.


------------------------------------------------------------------
-- Step 5: updates and deletes — the reason you chose CDC
------------------------------------------------------------------
UPDATE dbo.Employees SET JobTitle = 'Principal Engineer' WHERE EmployeeId = 1;
DELETE FROM dbo.Employees WHERE EmployeeId = 2;

-- Operation codes in the change table:
--   1 = delete, 2 = insert, 3 = update (before), 4 = update (after)
SELECT __$operation, COUNT(*)
FROM cdc.dbo_Employees_CT
GROUP BY __$operation;

-- Run the job again, then in the destination confirm:
--   - EmployeeId 1 shows 'Principal Engineer'  (update applied, not duplicated)
--   - EmployeeId 2 is gone                     (delete applied)
--
-- A duplicated row instead of an update means the primary key is
-- wrong. See docs/06-replication-queries.md.
