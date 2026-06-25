/*
    Operations / Transaction error handling
    TRY/CATCH template using XACT_STATE() to decide commit vs rollback, re-raising with THROW.
*/

USE [YourDatabase];
GO

-- TRY/CATCH transaction template.
-- XACT_STATE():  1 = open and committable, 0 = no open transaction, -1 = uncommittable (doomed).
-- In CATCH, roll back any open transaction (committable or doomed), then THROW re-raises the original error.
DECLARE @custid    int  = 1;
DECLARE @empid     int  = 1;
DECLARE @orderdate date = SYSDATETIME();

BEGIN TRY
    BEGIN TRANSACTION;

        -- work goes here
        INSERT INTO dbo.SimpleOrders (custid, empid, orderdate)
        VALUES (@custid, @empid, @orderdate);

        INSERT INTO dbo.SimpleOrderDetails (orderid, productid, unitprice, qty)
        VALUES (SCOPE_IDENTITY(), 1, 0.00, 1);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    -- Doomed (-1) must roll back; committable (1) is rolled back here too as the safe default.
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
