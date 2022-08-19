-- =============================================
-- Author:		<Sean Brittian>
-- Create date: <08/02/22>
-- Description:	<Generate Kitting Sheets based on sequences >
-- =============================================
ALTER PROCEDURE [dbo].[MES_SP_RPT_Kitting_BOM_Dtl_Report_Process_V2]
@Description		 VARCHAR(100)
AS

BEGIN


    Begin
        EXEC MES_SP_P_Kitting_Print_Area_Report_Process_v2 @Description--Insert Values into log hdr and delete from available seq
    End
    DECLARE
        @ID INT =  (SELECT TOP 1 id From MES_Kitting_Available_Seq WHERE Description = @Description AND Active = 0 ORDER BY id)

	SET NOCOUNT ON;
	DECLARE
        	  @Kit_Page VARCHAR(10)
          ,  @AreaNbr		 VARCHAR(100)
          , @Min_Order_ID  INT
          , @Max_Order_ID  INT
			  , @SKU_Item_Type	varchar(50)

	    SELECT @Kit_Page = Description, @AreaNbr = Area_Nbr, @Min_Order_ID = Order_ID_Low, @Max_Order_ID = Order_ID_High, @SKU_Item_Type = ('SKU-'+ SUBSTRING(Description, 4, 1)) FROM MES_Kitting_Available_Seq WHERE id = @ID

   Declare	@AreaID	        int
          , @Group          varchar(50)
          , @OrderType      char(1)
          , @NbrOfJobs      tinyint
          , @MaxJobs        int
          , @LastOrderID    bigint

	      ,@DeliveryPoint VARCHAR(10) =  (SELECT Description FROM MES_cfg_Kitting_Area WHERE Area_Nbr = @AreaNbr)

     Select @AreaID       = Area_ID
        , @Group        = [Group]
        , @OrderType    = Order_Type
        , @NbrOfJobs    = Nbr_of_Jobs
        , @MaxJobs      = Max_Jobs_Ahead_of_Group
        , @LastOrderID  = Last_Order_ID
   FROM   MES_cfg_Kitting_Area
   WHERE  Area_Nbr      = @AreaNbr

	DECLARE @Orders TABLE (
		KittOrderID   INT IDENTITY
      , Order_ID      INT
      , Order_Nbr     VARCHAR(50)
	  , Item_Nbr	  VARCHAR(50)
	  , VIN_Ref_Nbr	  VARCHAR(50)
    )


   INSERT INTO @Orders (Order_ID, Order_Nbr, Item_Nbr, VIN_Ref_Nbr)
   SELECT     [H].Order_HedrID, Order_Nbr, [sku].Item_Nbr, [H].VIN_Ref_Nbr
   FROM		  [dbo].[MES_data_Pending_Scheduled_Order_Hedr][H]
   INNER JOIN [dbo].[MES_data_Pending_Scheduled_Order_Dtl][D] ON [D].Order_HedrID = [H].Order_HedrID
   OUTER APPLY (
      SELECT Item_Nbr
	  FROM MES_data_Pending_Scheduled_Order_Dtl
	  WHERE Order_HedrID = [h].Order_HedrID AND Item_Type = @SKU_Item_Type
   ) [sku]
   WHERE	[Group]			 = 'SEQ'
   AND      [H].Order_HedrID >= @Min_Order_ID
   AND		[H].Order_HedrID <= @Max_Order_ID
   AND		Build_Priority	 = 25
   AND		Order_Type		 = 'S'
   AND		Item_Type IN (SELECT item FROM dbo.SplitStrings(@Group, ','))
   AND ([D].Item_Nbr IN (SELECT Item FROM LVL_cfg_Kitting_Exceptions))
   GROUP BY [H].Order_HedrID, Order_Nbr, [sku].Item_Nbr, [H].VIN_Ref_Nbr
   ORDER BY [H].Order_HedrID


            DECLARE @ReturnTab TABLE (Order_Nbr VARCHAR(50), VIN_Ref_Nbr VARCHAR(50)
                              , Item_Nbr VARCHAR(50), part_number VARCHAR(50)
                              , [description] VARCHAR(250), qty INT, code VARCHAR(20)
                              , location VARCHAR(20), color VARCHAR(20), kit_page VARCHAR(10))


   BEGIN

	   ;WITH results AS
	   (
            SELECT OrdHDR.Order_HedrID, ORDER_NBR, VIN_Ref_Nbr,IO.Item_Nbr, IO.Option_Nbr
                 , IIF(IO.Value = '1' and IO.Option_Nbr = 865, 'YES', IIF(IO.Value = '1' and IO.Option_Nbr = 876, 'No Arm',IO.Value)) AS Part_Number
                 , IIF(IO.Value = '1' AND IO.Option_Nbr NOT IN (164, 167, 865, 876), 'Lit Buckle?', IIF(IO.Value = 'NO' AND IO.Option_Nbr NOT IN (164, 167, 865, 876), 'Lit Buckle?', description)) AS description
                   , (select Value from ISS_cfg_Item_Option where Item_Nbr=MdPSOD.Item_Nbr and option_nbr=161 AND Item_Type <> @SKU_Item_Type) as code
                   ,qty, location/*, left(right(MdPSOD.Item_Nbr,6),3) as color*/
            FROM MES_data_Pending_Scheduled_Order_Hedr OrdHDR
            JOIN MES_data_Pending_Scheduled_Order_Dtl MdPSOD on OrdHDR.Order_HedrID = MdPSOD.Order_HedrID
            JOIN ISS_cfg_Item_Option IO ON MdPSOD.Item_Nbr = IO.Item_Nbr
            LEFT JOIN LVL_cfg_BOM_Master BOM ON BOM.part_number = REPLACE(Value, ' ', '') OR BOM.part_number = REPLACE(Value, '-', '')
            LEFT JOIN LVL_cfg_BOM_Structure ON BOM.part_number = child and MdPSOD.Item_Nbr = parent


           WHERE (((IO.Option_Nbr IN (164, 167, 865, 876) AND @Kit_Page = 'ROW2B' AND Item_Type LIKE '%2%') OR (IO.Option_Nbr IN (74, 14) AND @Kit_Page = 'ROW2A' AND Item_Type LIKE '%2%')) OR (IO.Option_Nbr IN (15, 74, 189) AND @Kit_Page = 'ROW1'))
           AND [Group] IN (@DeliveryPoint) AND Order_Nbr IN (SELECT DISTINCT Order_Nbr FROM @Orders)
    --ORDER BY Order_Nbr


		)
 INSERT INTO @ReturnTab(order_nbr, vin_ref_nbr, item_nbr, part_number, description, qty, code, location)
		SELECT [r].Order_Nbr, [r].VIN_Ref_Nbr, [o].Item_Nbr, Part_Number, [description], qty, code, location
		FROM results[r]
	   JOIN @Orders [o] ON [r].Order_Nbr = [o].Order_Nbr

            --ADDED BY SEAN BRITTIAN - 3/31/22
            DECLARE @VinTab TABLE (Vin VARCHAR(50))
                INSERT INTO @VinTab(Vin)
                    (SELECT DISTINCT VIN_Ref_Nbr FROM @ReturnTab )

            DECLARE @x INT =(SELECT COUNT(Vin) FROM @VinTab)
   IF @DeliveryPoint IN ('ROW2')
       BEGIN
            WHILE @x > 0
                begin
                    DECLARE @vin VARCHAR(50)
                    , @OrderNbr VARCHAR(50)
                    , @Item_Nbr VARCHAR(50)
                    , @part_number VARCHAR(50)
                    , @description_2 VARCHAR(250)
                    , @qty INT
                    , @code VARCHAR(20)
                    , @location VARCHAR(20)
                    , @kit_page1 VARCHAR(10)

                    SET @vin= (SELECT top 1 Vin FROM @VinTab)

                    SELECT TOP 1 @OrderNbr = Order_Nbr, @Item_Nbr=Item_Nbr,  @qty = qty,  @location = location,  @kit_page1 = kit_page, @code = code FROM @ReturnTab WHERE VIN_Ref_Nbr = @vin

                    SET @part_number = (SELECT TOP 1 Value FROM ISS_cfg_Item_Option a WHERE a.Item_Nbr = @Item_Nbr and Option_Nbr = 390)
                    SET @description_2 = @part_number

                    INSERT INTO @ReturnTab(Order_Nbr, VIN_Ref_Nbr,Item_Nbr, part_number, description, qty, code, location)
                    VALUES (@OrderNbr, @vin,@Item_Nbr, @part_number, 'HOCKEY STICK INFO', @qty, @code, @location)

                    DELETE @VinTab WHERE Vin = @vin
                    SET @x=@x-1

                end
	   end
                UPDATE @ReturnTab
                    SET color = SUBSTRING(Item_Nbr, LEN(Item_Nbr)-6, 3), kit_page =  (CASE WHEN @Kit_Page = 'ROW2A' THEN 'A' WHEN @Kit_Page = 'ROW2B' THEN 'B' ELSE '' END)

	END

        UPDATE MES_Kitting_Available_Seq SET Active = 1 WHERE id = @ID

         SELECT DISTINCT Order_Nbr, VIN_Ref_Nbr, Item_Nbr, part_number, description, qty, code, location, color, kit_page FROM @ReturnTab ORDER BY  Order_Nbr
        RETURN
END
go


