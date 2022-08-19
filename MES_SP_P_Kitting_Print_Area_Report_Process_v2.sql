-- =============================================
-- Author:		<Sean Brittian>
-- Create date: <08/02/22>
-- Description:	<Generate sequence ranges for MES_SP_RPT_Kitting_BOM_Dtl_Report_Process_V2>
-- =============================================

CREATE PROCEDURE [dbo].[MES_SP_P_Kitting_Print_Area_Report_Process_v2]
@Description VARCHAR(100)

AS

    BEGIN
        DECLARE
            @AreaNbr INT = (SELECT Area_Nbr FROM MES_cfg_Kitting_Area WHERE Description = SUBSTRING(@Description, 1, 4)) ,
            @ConveyorLine VARCHAR(10) = (SELECT [Group] FROM MES_cfg_Kitting_Area WHERE Description = SUBSTRING(@Description, 1, 4)),
            @DelPoint VARCHAR(10) = (SELECT Description FROM MES_cfg_Kitting_Area WHERE Description = SUBSTRING(@Description, 1, 4)),
            @LowID INT,
            @HighID INT,
            @Area_Seq_Nbr INT,
            @KPH_ID INT,
            @Count INT

        IF @Description = 'ROW2B'
            GOTO Exit_Success

        DECLARE

            @Tote INT = (SELECT TOP 1 Jobs_per_Tote FROM MES_cfg_Kitting_Delivery_Point WHERE Delivery_Point LIKE CONCAT(@DelPoint, '%'))
            , @LastHighID INT = (SELECT TOP 1 Order_ID_High FROM MES_Kitting_Available_Seq WHERE Description = @Description ORDER BY id desc )

            Begin
               ;WITH results AS
                   (
                       SELECT    TOP (@Tote)  [H].Order_HedrID
                       FROM		  [dbo].[MES_data_Pending_Scheduled_Order_Hedr][H]
                       INNER JOIN [dbo].[MES_data_Pending_Scheduled_Order_Dtl][D] ON [D].Order_HedrID = [H].Order_HedrID
                       WHERE	[Group]			 = 'SEQ'
                       AND      [H].Order_HedrID > @LastHighID
                       AND		Build_Priority	 = 25
                       AND		Order_Type		 = 'S'
                       AND		Item_Type IN (SELECT item FROM dbo.SplitStrings(@ConveyorLine, ','))
                       AND ([D].Item_Nbr IN (SELECT Item FROM LVL_cfg_Kitting_Exceptions))
                       GROUP BY [H].Order_HedrID
                       ORDER BY [H].Order_HedrID

                       )

                    SELECT TOP 1 @LowID =  MIN(a.Order_HedrID), @HighID = HighID, @Count = (SELECT COUNT(*) FROM results) FROM results a
                    OUTER APPLY (SELECT MAX(a.Order_HedrID) as HighID FROM results a) AS B GROUP BY Order_HedrID, HighID

               End


                IF @Count = @Tote
                    Begin
                        IF (@DelPoint LIKE 'ROW2') 

                            begin
                                INSERT INTO MES_Kitting_Available_Seq(Area_Nbr, Area_Seq_Nbr, Order_ID_Low, Order_ID_High, Description, Active)
                                    VALUES (@AreaNbr, @Area_Seq_Nbr, @LowID, @HighID, 'ROW2A', 0)
                                INSERT INTO MES_Kitting_Available_Seq(Area_Nbr, Area_Seq_Nbr, Order_ID_Low, Order_ID_High, Description, Active)
                                    VALUES (@AreaNbr, @Area_Seq_Nbr, @LowID, @HighID, 'ROW2B', 0)
                            end
                        IF (@DelPoint NOT LIKE 'ROW2')
                            begin
                                INSERT INTO MES_Kitting_Available_Seq(Area_Nbr, Area_Seq_Nbr, Order_ID_Low, Order_ID_High, Description, Active)
                                    VALUES (@AreaNbr, @Area_Seq_Nbr, @LowID, @HighID, @DelPoint, 0)
                            end

                        GOTO Exit_Success
                    End
                ELSE
                    GOTO Exit_Fail

                Exit_Success:

                    RETURN

                Exit_Fail:
                    SELECT 'FAILED: Not enough Sequences'
                    RETURN
            END
go

