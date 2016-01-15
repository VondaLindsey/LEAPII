CREATE OR REPLACE PACKAGE BODY SMR_MASS_RTV_SQL AS
----------------------------------------------------------------------------------------------------
-- Module Name: SMR_MASS_RTV_SQL.pls
-- Description: Custom package to perform operations needed for the custom smr_rtv form
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== ==========================================================
-- 1.00    20-Jun-11 H.Jonas     ENH033   Initial version.
-- 1.01    17-Aug-11 H.Jonas     SIR017   Fixed defects raised by SIR017.
-- 1.02    22-Sep-11 H.Jonas     SIR020   Fixed defects raised by SIR020.
--                                        Note: During the design of ENH033, an assumption that all
--                                        items in SMR are ranged to every store was made. However,
--                                        this assumption is no longer valid, changing the main logic
--                                        of this package. Instead of inserting and commenting out
--                                        pieces of code, functions that hold this assumption have
--                                        been commented out, and re-coded for ease of reading.
-- 1.03    10-Nov-11 S.Jain     SIR051    Fixed defects raised by SIR051
-- 1.04    05-Mar-12 S.Videtto            RTVs with no freight (restock_cost null fail in the RIB,
--                                        base RTVs are created with zero restock_cost instead of null).
-- 1.05    05-Mar-12 H.Jonas    SIR065    Added new function VALIDATE_ITEM_DEPT which will validate
--                                        items entered against the dept entered through a new
--                                        dept field on the form.
-- 1.06    14-Mar-12 H.Jonas    SIR067    Added functionality for the new column SELLING_UNIT_RETAIL
--                                        om the temp table SMR_RTV_ITEM_LOCATIONS_TEMP
-- 1.07    22-Sep-12 Murali     Leap 2    The package SMR_MASS_RTV_SQL was modified to remove the hard 
--                                        coding of the RTV reason code and populate it same as the 
--                                        reason code selected on the screen . The reason code is also 
--                                        populated into RTV_HEAD.ITEM field.
--
----------------------------------------------------------------------------------------------------

  TYPE loc_REC IS RECORD (loc      ITEM_LOC.LOC%TYPE,
                          loc_desc SMR_RTV_ITEM_LOCATIONS_TEMP.LOC_DESC%TYPE,
                          loc_type ITEM_LOC.LOC_TYPE%TYPE);
  TYPE loc_TBL IS TABLE OF loc_REC;

  /* LP_locs loc_TBL := loc_TBL();    -- OLR Vs 1.02 Removed */

  TYPE item_REC IS RECORD (item     ITEM_MASTER.ITEM%TYPE,
                           pack_ind ITEM_MASTER.PACK_IND%TYPE);
  TYPE item_TBL IS TABLE OF item_REC;

  TYPE rtv_order_no_TBL IS TABLE OF RTV_HEAD.RTV_ORDER_NO%TYPE INDEX BY BINARY_INTEGER;

--------------------------------------------------------------------------------------------------
-- Function Name: INSERT_SMR_RTV_ITEMS_TEMP
-- Purpose: Private function that will insert an item into the SMR_RTV_ITEMS_TEMP table.
--------------------------------------------------------------------------------------------------
FUNCTION INSERT_SMR_RTV_ITEMS_TEMP (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                                    I_item             IN     ITEM_MASTER.ITEM%TYPE,
                                    I_item_desc        IN     ITEM_MASTER.ITEM_DESC%TYPE,
                                    I_soh_default_ind  IN     SMR_RTV_ITEMS_TEMP.SOH_DEFAULT_IND%TYPE)
RETURN BOOLEAN IS

  L_program   VARCHAR2(50) := 'SMR_MASS_RTV_SQL.INSERT_SMR_RTV_ITEMS_TEMP';

BEGIN

  insert into SMR_RTV_ITEMS_TEMP(ITEM,
                                 ITEM_DESC,
                                 SOH_DEFAULT_IND)
                          values(I_item,
                                 I_item_desc,
                                 I_soh_default_ind);
  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END INSERT_SMR_RTV_ITEMS_TEMP;

--------------------------------------------------------------------------------------------------
-- Function Name: INSERT_SMR_RTV_ITEM_LOCS_TEMP
-- Purpose: Private function that will insert an item into the SMR_RTV_ITEM_LOCATIONS_TEMP table.
--------------------------------------------------------------------------------------------------
FUNCTION INSERT_SMR_RTV_ITEM_LOCS_TEMP (O_error_message       IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                                        I_item                IN     ITEM_MASTER.ITEM%TYPE,
                                        I_loc                 IN     ITEM_LOC.LOC%TYPE,
                                        I_loc_desc            IN     SMR_RTV_ITEM_LOCATIONS_TEMP.LOC_DESC%TYPE,
                                        I_loc_type            IN     ITEM_LOC.LOC_TYPE%TYPE,
                                        I_stock_on_hand       IN     ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                                        I_orig_unit_cost      IN     RTV_DETAIL.ORIGINAL_UNIT_COST%TYPE,
                                        I_selling_unit_retail IN     SMR_RTV_ITEM_LOCATIONS_TEMP.SELLING_UNIT_RETAIL%TYPE, /* OLR Vs 1.06 Inserted */
                                        I_qty_requested       IN     RTV_DETAIL.QTY_REQUESTED%TYPE)
RETURN BOOLEAN IS

  L_program   VARCHAR2(50) := 'SMR_MASS_RTV_SQL.INSERT_SMR_RTV_ITEM_LOCS_TEMP';

BEGIN

  insert into SMR_RTV_ITEM_LOCATIONS_TEMP(LOC,
                                          LOC_DESC,
                                          LOC_TYPE,
                                          ITEM,
                                          STOCK_ON_HAND,
                                          AVAIL_STOCK_ON_HAND,  /* OLR Vs 1.01 Inserted */
                                          ORIG_UNIT_COST,
                                          SELLING_UNIT_RETAIL,  /* OLR Vs 1.06 Inserted */
                                          QTY_REQUESTED)
                                   values(I_loc,
                                          I_loc_desc,
                                          I_loc_type,
                                          I_item,
                                          I_stock_on_hand,
                                          I_qty_requested,       /* OLR Vs 1.01 Inserted */
                                          I_orig_unit_cost,
                                          I_selling_unit_retail, /* OLR Vs 1.06 Inserted */
                                          I_qty_requested);
  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END INSERT_SMR_RTV_ITEM_LOCS_TEMP;

/* OLR Vs 1.02 Inserted -- Start */
--------------------------------------------------------------------------------------------------
-- Function Name: VALID_RTV_ITEM_QTY
-- Purpose: Private function that replicates the base package function
--          RTV_VALIDATE_SQL.VALID_RTV_ITEM_QTY. This function will calculate the SOH for
--          an item/location and if the SOH is invalid, it will return a status of FALSE instead
--          of aborting as it currently does in base.
--------------------------------------------------------------------------------------------------
FUNCTION VALID_RTV_ITEM_QTY(O_error_message           IN OUT     RTK_ERRORS.RTK_TEXT%TYPE,
                            O_valid_soh               IN OUT     BOOLEAN,
                            O_qty_requested           IN OUT     RTV_DETAIL.QTY_REQUESTED%TYPE,
                            I_item                    IN         RTV_DETAIL.ITEM%TYPE,
                            I_location                IN         ITEM_LOC.LOC%TYPE,
                            I_loc_type                IN         ITEM_LOC.LOC_TYPE%TYPE,
                            I_physical_wh_ind         IN         VARCHAR2,
                            I_reason                  IN         RTV_DETAIL.REASON%TYPE,
                            I_default_soh_ind         IN         VARCHAR2,
                            I_uot_size                IN         ITEM_SUPP_COUNTRY.SUPP_PACK_SIZE%TYPE)
RETURN BOOLEAN IS

  L_program                     VARCHAR2(50) := 'SMR_MASS_RTV_SQL.VALID_RTV_ITEM_QTY';
  L_available_qty               ITEM_LOC_SOH.STOCK_ON_HAND%TYPE     := 0;
  L_unavailable_qty             ITEM_LOC_SOH.STOCK_ON_HAND%TYPE     := 0;
  L_total_available_qty         RTV_DETAIL.QTY_REQUESTED%TYPE       := 0;
  L_total_unavailable_qty       RTV_DETAIL.QTY_REQUESTED%TYPE       := 0;
  L_non_sellable_qty            ITEM_LOC_SOH.NON_SELLABLE_QTY%TYPE;
  L_dummy                       VARCHAR2(255);
  L_group_type                  CODE_DETAIL.CODE%TYPE;
  L_cust_ord_resv_qty           ITEM_LOC_SOH.STOCK_ON_HAND%TYPE     := 0;
  L_tsf_reserved_qty            ITEM_LOC_SOH.NON_SELLABLE_QTY%TYPE;
  L_customer_resv               ITEM_LOC_SOH.NON_SELLABLE_QTY%TYPE;
  L_customer_backorder          ITEM_LOC_SOH.NON_SELLABLE_QTY%TYPE;

  cursor C_INV_ST_QTY IS
    select NVL(qty,0) cust_ord_resv_qty
      from inv_status_qty
     where loc_type   = I_loc_type
       and location   = I_location
       and item       = I_item
       and inv_status = 2;

BEGIN

  --Initialise SOH indicator to true and if any validation fails, this will be set
  --to false and the function will exit (i.e. return true).
  O_valid_soh := TRUE;

  if RTV_VALIDATE_SQL.GET_TOTAL_RTV_QTYS(O_error_message,
                                        L_total_available_qty,
                                        L_total_unavailable_qty,
                                        I_item,
                                        I_location) = FALSE then
    return FALSE;
  end if;

  if I_physical_wh_ind = 'Y' then
    L_group_type := 'PW';
    if ITEMLOC_QUANTITY_SQL.GET_ITEM_GROUP_QTYS(O_error_message,
                                                L_available_qty,      --O_stock_on_hand,
                                                L_dummy,              --O_pack_comp_soh,
                                                L_dummy,              --O_in_transit_qty,
                                                L_dummy,              --O_pack_comp_intran,
                                                L_tsf_reserved_qty,   --O_tsf_reserved_qty,
                                                L_dummy,              --O_pack_comp_resv,
                                                L_dummy,              --O_tsf_expected_qty,
                                                L_dummy,              --O_pack_comp_exp,
                                                L_dummy,              --O_rtv_qty,
                                                L_non_sellable_qty,   --O_non_sellable_qty
                                                L_customer_resv,      --O_customer_resv,
                                                L_customer_backorder, --O_customer_backorder,
                                                L_dummy,              --O_pack_comp_cust_resv,
                                                L_dummy,              --O_pack_comp_cust_back,
                                                I_item,
                                                I_location,           --I_group_id
                                                L_group_type) = FALSE then
       return FALSE;
    end if;
  else
    if ITEMLOC_QUANTITY_SQL.GET_ITEM_LOC_QTYS(O_error_message,
                                              L_available_qty,      --O_stock_on_hand,
                                              L_dummy,              --O_pack_comp_soh,
                                              L_dummy,              --O_in_transit_qty,
                                              L_dummy,              --O_pack_comp_intran,
                                              L_tsf_reserved_qty,   --O_tsf_reserved_qty,
                                              L_dummy,              --O_pack_comp_resv,
                                              L_dummy,              --O_tsf_expected_qty,
                                              L_dummy,              --O_pack_comp_exp,
                                              L_dummy,              --O_rtv_qty,
                                              L_non_sellable_qty,
                                              L_customer_resv,      --O_customer_resv,
                                              L_customer_backorder, --O_customer_backorder,
                                              L_dummy,              --O_pack_comp_cust_resv,
                                              L_dummy,              --O_pack_comp_cust_back,
                                              I_item,
                                              I_location,
                                              I_loc_type) = FALSE then
       return FALSE;
    end if;
  end if;

  if I_loc_type = 'S' then
    open C_INV_ST_QTY;
    fetch C_INV_ST_QTY into L_cust_ord_resv_qty;
    close C_INV_ST_QTY;

    L_non_sellable_qty := L_non_sellable_qty - L_cust_ord_resv_qty;
  end if;

  L_available_qty   := L_available_qty - (L_tsf_reserved_qty + L_total_available_qty + L_non_sellable_qty + L_customer_resv + L_customer_backorder);
  L_unavailable_qty := (L_non_sellable_qty - L_total_unavailable_qty);

  if I_default_soh_ind = 'Y' then
    if I_reason = 'U' then
      if L_unavailable_qty <= 0 then
        O_valid_soh := FALSE;
        return TRUE;
      else
        O_qty_requested := trunc(L_unavailable_qty/I_uot_size);
      end if;
    elsif I_reason != 'U' then
      if L_available_qty <= 0 then
        O_valid_soh := FALSE;
        return TRUE;
      else
        O_qty_requested := trunc(L_available_qty/I_uot_size);
      end if;
    end if;
  elsif I_default_soh_ind = 'N' then
    if I_reason = 'U' then
      if L_unavailable_qty < round(O_qty_requested * I_uot_size) then
        O_valid_soh := FALSE;
        return TRUE;
      else
        return TRUE;
      end if;
    elsif I_reason != 'U' then
      if L_available_qty < round(O_qty_requested * I_uot_size) then
        O_valid_soh := FALSE;
        return TRUE;
      else
        return TRUE;
      end if;
    end if;
  end if;

  return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := sql_lib.create_msg('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
      return FALSE;

END VALID_RTV_ITEM_QTY;

--------------------------------------------------------------------------------------------------
-- Function Name: SET_RANGED_LOCS
-- Purpose: Private function that will collect all the locations an item is ranged to for the
--          locations that have been selected for the Mass RTV.
--------------------------------------------------------------------------------------------------
FUNCTION SET_RANGED_LOCS (O_error_message  IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                          O_locs           IN OUT loc_TBL,
                          I_supplier       IN     SUPS.SUPPLIER%TYPE,
                          I_item           IN     ITEM_MASTER.ITEM%TYPE)

RETURN BOOLEAN AS

  L_program          VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.SET_RANGED_LOCS';
  L_store            STORE.STORE%TYPE;
  L_wh               WH.WH%TYPE;
  L_is_valid         BOOLEAN;

BEGIN

  --Loop through each location and collect all the locations the item is ranged to.
  for i in 1..O_locs.count loop
    if O_locs(i).loc_type = 'W' then
      L_store := -1;
      L_wh    := O_locs(i).loc;
    else
      L_wh    := -1;
      L_store := O_locs(i).loc;
    end if;

    L_is_valid := TRUE;

    --Validate that the Item/Loc/Supplier combo is valid
    if RTV_VALIDATE_SQL.INVENTORY_ITEM(O_error_message,
                                       I_item,
                                       I_supplier,
                                       L_store,
                                       L_wh,
                                       L_is_valid) = FALSE then
      return FALSE;
    end if;

    if not L_is_valid then
      --If the item is not ranged to this location, remove it from the collection
      O_locs.DELETE(i);
    end if;
  end loop;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END SET_RANGED_LOCS;

--------------------------------------------------------------------------------------------------
-- Function Name: PROCESS_ITEM
-- Purpose: Private function that will perform validations against an item before inserting into
--          the SMR_RTV_ITEMS_TEMP and SMR_RTV_ITEM_LOCATIONS_TEMP temp tables.
--------------------------------------------------------------------------------------------------
FUNCTION PROCESS_ITEM (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                       O_applied_ind      IN OUT VARCHAR2,
                       I_supplier         IN     SUPS.SUPPLIER%TYPE,
                       I_item             IN     ITEM_MASTER.ITEM%TYPE,
                       I_item_desc        IN     ITEM_MASTER.ITEM_DESC%TYPE,
                       I_soh_default_ind  IN     VARCHAR2,
                       I_physical_wh_ind  IN     VARCHAR2,
                       I_inventory_ind    IN     VARCHAR2)
RETURN BOOLEAN IS

  L_program             VARCHAR2(50)                     := 'SMR_MASS_RTV_SQL.PROCESS_ITEM';
  L_unit_cost           ITEM_LOC_SOH.UNIT_COST%TYPE;
  L_unit_cost_loc       SHIPSKU.UNIT_COST%TYPE           := 0;
  L_stock_on_hand       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE  := 0;
  L_qty_requested       RTV_DETAIL.QTY_REQUESTED%TYPE    := 0;
  L_invalid_soh_count   NUMBER(10)                       := 0;
  L_index               NUMBER(10);
  L_valid_soh           BOOLEAN;
  L_locs                loc_TBL;
  L_curr_loc            SMR_RTV_ITEM_LOCATIONS_TEMP.LOC%TYPE;
  L_selling_unit_retail SMR_RTV_ITEM_LOCATIONS_TEMP.SELLING_UNIT_RETAIL%TYPE;

  --Cursor that will get all locations that has been applied to the Mass RTV
  --Note: During the initial process of adding locations into the SMR_RTV_ITEM_LOCATIONS_TEMP table,
  --      only the locations were added with no items. Therefore, records exists in this table with
  --      only location information for the purpose of adding new items.
  cursor C_get_all_locs is
    select loc,
           loc_desc,
           loc_type
      from smr_rtv_item_locations_temp
     where item is null;

  /* OLR Vs 1.06 Inserted -- Start */
  --Cursor to get the selling_unit_retail for the item/loc
  cursor C_get_selling_unit_retail is
    select selling_unit_retail
      from item_loc
     where item = I_item
       and loc  = L_curr_loc;
  /* OLR Vs 1.06 Inserted -- End */

BEGIN

  L_locs        := loc_TBL();
  O_applied_ind := 'N';

  --Get all the locations that have been selected for the Mass RTV
  open C_get_all_locs;
  fetch C_get_all_locs BULK COLLECT INTO L_locs;
  close C_get_all_locs;

  --Call the following function to filter the collection LP_locs of any locations
  --that the item is not ranged to
  if SET_RANGED_LOCS(O_error_message,
                     L_locs,
                     I_supplier,
                     I_item) = FALSE then
    return FALSE;
  end if;

  L_index := L_locs.FIRST;

  while L_index is not null loop
    --Get the Stock On Hand for the item/location
    if ITEMLOC_QUANTITY_SQL.GET_STOCK_ON_HAND(O_error_message,
                                              L_stock_on_hand,
                                              I_item,
                                              L_locs(L_index).loc,
                                              L_locs(L_index).loc_type) = FALSE then
       return FALSE;
    end if;

    if I_inventory_ind = 'Y' then
      if VALID_RTV_ITEM_QTY(O_error_message,
                            L_valid_soh,
                            L_qty_requested,
                            I_item,
                            L_locs(L_index).loc,
                            L_locs(L_index).loc_type,
                            I_physical_wh_ind,
                            'O',             --Overstock
                            'Y',             --Always default quantity requested to the Available Qty
                            1) = FALSE then  --UOT will be 1 for Mass RTV
        return FALSE;
      end if;
    end if;

    if not L_valid_soh then
      L_invalid_soh_count := L_invalid_soh_count + 1;
    else
      --Get the Unit Cost based on the item/loc/supplier
      if RTV_SQL.DETERMINE_RTV_COST(O_error_message,
                                     L_unit_cost_loc,  --does not get used
                                     L_unit_cost,      --supplier unit cost
                                     I_item,
                                     L_locs(L_index).loc,
                                     L_locs(L_index).loc_type,
                                     I_supplier) = FALSE then
        return FALSE;
      end if;

      /* OLR Vs 1.06 Inserted -- Start */
      L_curr_loc := L_locs(L_index).loc;

      open C_get_selling_unit_retail;
      fetch C_get_selling_unit_retail into L_selling_unit_retail;
      close C_get_selling_unit_retail;
      /* OLR Vs 1.06 Inserted -- End */

      --Insert Item/Loc record
      if INSERT_SMR_RTV_ITEM_LOCS_TEMP(O_error_message,
                                       I_item,
                                       L_locs(L_index).loc,
                                       L_locs(L_index).loc_desc,
                                       L_locs(L_index).loc_type,
                                       L_stock_on_hand,
                                       L_unit_cost,
                                       L_selling_unit_retail,  /* OLR Vs 1.06 Inserted */
                                       L_qty_requested) = FALSE then
        return FALSE;
      end if;
    end if;

    L_index := L_locs.next(L_index);
  end loop;

  --Determine if how many locations item was applied
  if L_invalid_soh_count = L_locs.count then
    O_applied_ind := 'N';    --Non applied
  else
    if L_invalid_soh_count = 0 then
      O_applied_ind := 'A';  -- All applied
    elsif L_invalid_soh_count <> 0 and L_invalid_soh_count < L_locs.count then
      O_applied_ind := 'S';  --Some applied
    end if;

    --insert item into SMR_RTV_ITEMS_TEMP
    if INSERT_SMR_RTV_ITEMS_TEMP(O_error_message,
                                 I_item,
                                 I_item_desc,
                                 I_soh_default_ind) = FALSE then
      return FALSE;
    end if;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END PROCESS_ITEM;

--------------------------------------------------------------------------------------------------
-- Function Name: PROCESS_ITEM_LIST
-- Purpose: Private function that will perform validations against each item in the item list
--          before inserting into the SMR_RTV_ITEMS_TEMP and SMR_RTV_ITEM_LOCATIONS_TEMP temp
--          tables.
--------------------------------------------------------------------------------------------------
FUNCTION PROCESS_ITEM_LIST (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                            O_applied_ind      IN OUT VARCHAR2,
                            I_supplier         IN     SUPS.SUPPLIER%TYPE,
                            I_item_list        IN     ITEM_MASTER.ITEM%TYPE,
                            I_soh_default_ind  IN     VARCHAR2,
                            I_physical_wh_ind  IN     VARCHAR2)
RETURN BOOLEAN IS

  L_program               VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.PROCESS_ITEM_LIST';
  L_exists                BOOLEAN        := FALSE;
  L_items                 item_TBL;
  L_invalid_item_count    NUMBER(10)     := 0;
  L_semivalid_item_count  NUMBER(10)     := 0;

  L_item_master_row       V_ITEM_MASTER%ROWTYPE;
  L_valid                 BOOLEAN;
  L_all_locs_ranged       BOOLEAN;
  L_item_applied_ind      VARCHAR2(1);
  L_item_count            NUMBER(10);

  --Cursor that will get all the items in the pack item
  cursor C_get_items is
    select item,
           pack_ind
      from skulist_detail
     where skulist    = I_item_list
       and item_level = tran_level;

BEGIN

  --get the items in the itemlist
  open C_get_items;
  fetch C_get_items BULK COLLECT INTO L_items;
  close C_get_items;

  --get the number of items in the item list
  L_item_count := L_items.count;

  --loop through each item in the itemlist and only add items that
  --pass validation. Items that do not pass validation are skipped
  for i in 1..L_items.count loop
    --check that the item has not yet been added to the RTV
    if ITEM_EXISTS(O_error_message,
                   L_exists,
                   L_items(i).item) = FALSE then
      return FALSE;
    end if;

    if L_exists then
      GOTO end_item_loop;
    end if;

    --Get item information
    if FILTER_LOV_VALIDATE_SQL.VALIDATE_ITEM_MASTER(O_error_message,
                                                    L_valid,
                                                    L_item_master_row,
                                                    L_items(i).item) = FALSE then
      return FALSE;
    end if;

    if L_item_master_row.inventory_ind <> 'Y' then
      L_invalid_item_count := L_invalid_item_count + 1;
      GOTO end_item_loop;
    end if;

    if L_item_master_row.orderable_ind <> 'Y' then
      L_invalid_item_count := L_invalid_item_count + 1;
      GOTO end_item_loop;
    end if;

    if L_item_master_row.status != 'A' then
      L_invalid_item_count := L_invalid_item_count + 1;
      GOTO end_item_loop;
    end if;

    --Validate the item/location/supplier combo
    if VALIDATE_ITEM(O_error_message,
                     L_valid,
                     L_all_locs_ranged,
                     L_items(i).item,
                     I_supplier,
                     L_item_master_row.pack_ind,
                     I_physical_wh_ind) = FALSE then
      return FALSE;
    end if;

    if L_valid = FALSE then
      L_invalid_item_count := L_invalid_item_count + 1;
      GOTO end_item_loop;
    end if;

    if PROCESS_ITEM(O_error_message,
                    L_item_applied_ind,
                    I_supplier,
                    L_items(i).item,
                    L_item_master_row.item_desc,
                    I_soh_default_ind,
                    I_physical_wh_ind,
                    L_item_master_row.inventory_ind) = FALSE then
      return FALSE;
    end if;

    --increment invalid and semi valid counters
    if L_item_applied_ind = 'N' then
      L_invalid_item_count := L_invalid_item_count + 1;
    elsif L_item_applied_ind = 'S' or not L_all_locs_ranged then
      L_semivalid_item_count := L_semivalid_item_count + 1;
    end if;

    <<end_item_loop>>
    null;
  end loop;

  if L_invalid_item_count = L_item_count then
    O_applied_ind := 'N';  --Non applied
  --elsif L_semivalid_item_count > 0 then --OLR Vs 1.03 Deleted
    elsif L_semivalid_item_count > 0 or  L_invalid_item_count > 0 then --OLR Vs 1.03 Added
    O_applied_ind := 'S';  --Some applied
  else
    O_applied_ind := 'A';  -- All applied
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END PROCESS_ITEM_LIST;
/* OLR Vs 1.02 Inserted -- End */

--------------------------------------------------------------------------------------------------

/* OLR Vs 1.02 Removed -- Start
-- OLR Vs 1.01 Inserted -- Start
FUNCTION SET_RANGED_LOCS (O_error_message  IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                          I_supplier       IN     SUPS.SUPPLIER%TYPE,
                          I_item           IN     ITEM_MASTER.ITEM%TYPE)

RETURN BOOLEAN AS

  L_program          VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.SET_RANGED_LOCS';
  L_store            STORE.STORE%TYPE;
  L_wh               WH.WH%TYPE;
  L_is_valid         BOOLEAN;

BEGIN

  --Loop through each location and collect all the locations the item is ranged to.
  for i in 1..LP_locs.count loop
    if LP_locs(i).loc_type = 'W' then
      L_store := -1;
      L_wh    := LP_locs(i).loc;
    else
      L_wh    := -1;
      L_store := LP_locs(i).loc;
    end if;

    L_is_valid := TRUE;

    --Validate that the Item/Loc/Supplier combo is valid
    if RTV_VALIDATE_SQL.INVENTORY_ITEM(O_error_message,
                                       I_item,
                                       I_supplier,
                                       L_store,
                                       L_wh,
                                       L_is_valid) = FALSE then
      return FALSE;
    end if;

    if not L_is_valid then
      --If the item is not ranged to this location, remove it from the collection
      LP_locs.DELETE(i);
    end if;
  end loop;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END SET_RANGED_LOCS;
-- OLR Vs 1.01 Inserted -- End

--------------------------------------------------------------------------------------------------

FUNCTION PROCESS_ITEM (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                       I_supplier         IN     SUPS.SUPPLIER%TYPE,
                       I_item             IN     ITEM_MASTER.ITEM%TYPE,
                       I_item_desc        IN     ITEM_MASTER.ITEM_DESC%TYPE,
                       I_soh_default_ind  IN     VARCHAR2,
                       I_physical_wh_ind  IN     VARCHAR2,
                       I_inventory_ind    IN     VARCHAR2)
RETURN BOOLEAN IS

  L_program             VARCHAR2(50)                     := 'SMR_MASS_RTV_SQL.PROCESS_ITEM';
  L_stock_on_hand       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE  := 0;
  L_qty_requested       RTV_DETAIL.QTY_REQUESTED%TYPE    := 0;
  L_unit_cost_loc       SHIPSKU.UNIT_COST%TYPE           := 0;
  L_unit_cost           ITEM_LOC_SOH.UNIT_COST%TYPE;
  L_index               NUMBER(10);  -- OLR Vs 1.01 Inserted

BEGIN

  -- OLR Vs 1.01 Inserted -- Start
  L_index := LP_locs.FIRST;

  while L_index is not null loop
   --Get the Stock On Hand for the item/location
    if ITEMLOC_QUANTITY_SQL.GET_STOCK_ON_HAND(O_error_message,
                                              L_stock_on_hand,
                                              I_item,
                                              LP_locs(L_index).loc,
                                              LP_locs(L_index).loc_type) = FALSE then
       return FALSE;
    end if;

    if I_inventory_ind = 'Y' then
      if RTV_VALIDATE_SQL.VALID_RTV_ITEM_QTY(O_error_message,
                                             L_qty_requested,
                                             I_item,
                                             LP_locs(L_index).loc,
                                             LP_locs(L_index).loc_type,
                                             I_physical_wh_ind,
                                             'O',             --Overstock
                                             'Y',             --Always default quantity requested to the Available Qty
                                             1) = FALSE then  --UOT will be 1 for Mass RTV
        return FALSE;
      end if;
    end if;

    --Get the Unit Cost based on the item/loc/supplier
    if RTV_SQL.DETERMINE_RTV_COST(O_error_message,
                                   L_unit_cost_loc,  --does not get used
                                   L_unit_cost,      --supplier unit cost
                                   I_item,
                                   LP_locs(L_index).loc,
                                   LP_locs(L_index).loc_type,
                                   I_supplier) = FALSE then
      return FALSE;
    end if;

    --Insert Item/Loc record
    if INSERT_SMR_RTV_ITEM_LOCS_TEMP(O_error_message,
                                     I_item,
                                     LP_locs(L_index).loc,
                                     LP_locs(L_index).loc_desc,
                                     LP_locs(L_index).loc_type,
                                     L_stock_on_hand,
                                     L_unit_cost,
                                     L_qty_requested) = FALSE then
      return FALSE;
    end if;

    L_index := LP_locs.next(L_index);
  end loop;

  --insert item into SMR_RTV_ITEMS_TEMP
  if INSERT_SMR_RTV_ITEMS_TEMP(O_error_message,
                               I_item,
                               I_item_desc,
                               I_soh_default_ind) = FALSE then
    return FALSE;
  end if;
  -- OLR Vs 1.01 Inserted -- End

  -- OLR Vs 1.01 Removed -- Start
  for i in 1..LP_locs.count loop
    --Get the Stock On Hand for the item/location
    if ITEMLOC_QUANTITY_SQL.GET_STOCK_ON_HAND(O_error_message,
                                              L_stock_on_hand,
                                              I_item,
                                              LP_locs(i).loc,
                                              LP_locs(i).loc_type) = FALSE then
       return FALSE;
    end if;

    if I_inventory_ind = 'Y' then
      if RTV_VALIDATE_SQL.VALID_RTV_ITEM_QTY(O_error_message,
                                             L_qty_requested,
                                             I_item,
                                             LP_locs(i).loc,
                                             LP_locs(i).loc_type,
                                             I_physical_wh_ind,
                                             'O',             --Overstock
                                             'Y',             --Always default quantity requested to the Available Qty
                                             1) = FALSE then  --UOT will be 1 for Mass RTV
        return FALSE;
      end if;
    end if;

    --Get the Unit Cost based on the item/loc/supplier
    if RTV_SQL.DETERMINE_RTV_COST(O_error_message,
                                   L_unit_cost_loc,  --does not get used
                                   L_unit_cost,      --supplier unit cost
                                   I_item,
                                   LP_locs(i).loc,
                                   LP_locs(i).loc_type,
                                   I_supplier) = FALSE then
      return FALSE;
    end if;

    --Insert Item/Loc record
    if INSERT_SMR_RTV_ITEM_LOCS_TEMP(O_error_message,
                                     I_item,
                                     LP_locs(i).loc,
                                     LP_locs(i).loc_desc,
                                     LP_locs(i).loc_type,
                                     L_stock_on_hand,
                                     L_unit_cost,
                                     L_qty_requested) = FALSE then
      return FALSE;
    end if;

  end loop;

  --insert item into SMR_RTV_ITEMS_TEMP
  if INSERT_SMR_RTV_ITEMS_TEMP(O_error_message,
                               I_item,
                               I_item_desc,
                               I_soh_default_ind) = FALSE then
    return FALSE;
  end if;
  -- OLR VS 1.01 Removed -- End
  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END PROCESS_ITEM;

--------------------------------------------------------------------------------------------------

FUNCTION PROCESS_ITEM_LIST (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                            O_all_applied      IN OUT BOOLEAN,
                            I_supplier         IN     SUPS.SUPPLIER%TYPE,
                            I_item_list        IN     ITEM_MASTER.ITEM%TYPE,
                            I_soh_default_ind  IN     VARCHAR2,
                            I_physical_wh_ind  IN     VARCHAR2)
RETURN BOOLEAN IS

  L_program             VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.PROCESS_ITEM_LIST';
  L_exists              BOOLEAN        := FALSE;
  L_items               item_TBL;
  L_invalid_count       NUMBER(10)     := 0;

  L_item_master_row     V_ITEM_MASTER%ROWTYPE;
  L_valid               BOOLEAN;
  L_all_locs_ranged     BOOLEAN;  -- OLR VS 1.01 Inserted

  --Cursor that will get all the items in the pack item
  cursor C_get_items is
    select item,
           pack_ind
      from skulist_detail
     where skulist    = I_item_list
       and item_level = tran_level;

BEGIN

  --get the items in the itemlist
  open C_get_items;
  fetch C_get_items BULK COLLECT INTO L_items;
  close C_get_items;

  --loop through each item in the itemlist and only add items that
  --pass validation. Items that do not pass validation are skipped
  for i in 1..L_items.count loop
    --check that the item has not yet been added to the RTV
    if ITEM_EXISTS(O_error_message,
                   L_exists,
                   L_items(i).item) = FALSE then
      return FALSE;
    end if;

    if L_exists then
      GOTO end_item_loop;
    end if;

    --Get item information
    if FILTER_LOV_VALIDATE_SQL.VALIDATE_ITEM_MASTER(O_error_message,
                                                    L_valid,
                                                    L_item_master_row,
                                                    L_items(i).item) = FALSE then
      return FALSE;
    end if;

    if L_item_master_row.inventory_ind <> 'Y' then
      L_invalid_count := L_invalid_count + 1;
      GOTO end_item_loop;
    end if;

    if L_item_master_row.orderable_ind <> 'Y' then
      L_invalid_count := L_invalid_count + 1;
      GOTO end_item_loop;
    end if;

    if L_item_master_row.status != 'A' then
      L_invalid_count := L_invalid_count + 1;
      GOTO end_item_loop;
    end if;

    --Validate the item/location/supplier combo
    if VALIDATE_ITEM(O_error_message,
                     L_valid,
                     L_all_locs_ranged,  -- OLR Vs 1.01 Inserted
                     L_items(i).item,
                     I_supplier,
                     L_item_master_row.pack_ind,
                     I_physical_wh_ind) = FALSE then
      return FALSE;
    end if;

    if L_valid = FALSE then
      L_invalid_count := L_invalid_count + 1;
      GOTO end_item_loop;
    end if;

    if PROCESS_ITEM(O_error_message,
                    I_supplier,
                    L_items(i).item,
                    L_item_master_row.item_desc,
                    I_soh_default_ind,
                    I_physical_wh_ind,
                    L_item_master_row.inventory_ind) = FALSE then
      return FALSE;
    end if;

    <<end_item_loop>>
    null;
  end loop;

  if L_invalid_count > 0 then
    O_all_applied := FALSE;
  else
    O_all_applied := TRUE;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END PROCESS_ITEM_LIST;
OLR Vs 1.02 Removed -- End */

--------------------------------------------------------------------------------------------------
-- Function Name: LOCATION_EXISTS
-- Purpose: Function that will check if a location has already been added to the Mass RTV
--
--    NOTE: If I_loc_type 'S' - Validation for Stores
--          IF I_loc_type 'W' - Validation for Stores
--------------------------------------------------------------------------------------------------
FUNCTION LOCATION_EXISTS (O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                          O_exists        IN OUT BOOLEAN,
                          I_loc_type      IN     VARCHAR2,
                          I_loc           IN     ITEM_LOC.LOC%TYPE)

RETURN BOOLEAN AS

  L_program   VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.LOCATION_EXISTS';

  L_dummy     VARCHAR2(1);

  cursor C_exists is
    select 1
      from SMR_RTV_ITEM_LOCATIONS_TEMP
     where loc      = I_loc
       and loc_type = I_loc_type;

BEGIN

  O_exists := FALSE;

  open C_exists;
  fetch C_exists into L_dummy;
  if C_exists%FOUND then
    O_exists := TRUE;
  end if;
  close C_exists;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END LOCATION_EXISTS;

--------------------------------------------------------------------------------------------------
-- Function Name: ITEM_EXISTS
-- Purpose: Function that will check if the Item already exists in the Mass RTV
--------------------------------------------------------------------------------------------------
FUNCTION ITEM_EXISTS(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                     O_exists        IN OUT BOOLEAN,
                     I_item          IN     ITEM_MASTER.ITEM%TYPE)
RETURN BOOLEAN IS

  L_program   VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.ITEM_EXISTS';
  L_dummy     VARCHAR2(1);

  cursor C_item_exists is
    select 'Y'
      from smr_rtv_items_temp
     where item = I_item;

BEGIN

  O_exists := FALSE;

  open C_item_exists;
  fetch C_item_exists into L_dummy;
  if C_item_exists%FOUND then
    O_exists := TRUE;
  end if;
  close C_item_exists;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END ITEM_EXISTS;
--------------------------------------------------------------------------------------------------
-- Function Name: VALIDATE_ITEM_LIST
-- Purpose: Function that will validate if the item list entered through the SMR Mass RTV form is
--          a valid item list.
--------------------------------------------------------------------------------------------------
FUNCTION VALIDATE_ITEM_LIST (O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                             O_is_valid      IN OUT BOOLEAN,
                             I_item_list     IN     SKULIST_HEAD.SKULIST%TYPE)
RETURN BOOLEAN IS

  L_program   VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.VALIDATE_ITEM_LIST';
  L_dummy     VARCHAR2(1);


  cursor C_NON_ORDER_PACK_IN_LIST is
    select 'x'
      from item_master im,
           skulist_detail s
     where s.skulist        = I_item_list
       and im.pack_ind      = 'Y'
       and im.item          = s.item
       and im.orderable_ind = 'N';

BEGIN

  O_is_valid := TRUE;

  open  C_NON_ORDER_PACK_IN_LIST;
  fetch C_NON_ORDER_PACK_IN_LIST into L_dummy;
  if C_NON_ORDER_PACK_IN_LIST%FOUND then
    O_is_valid := FALSE;
  end if;
  close C_NON_ORDER_PACK_IN_LIST;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END VALIDATE_ITEM_LIST;

--------------------------------------------------------------------------------------------------
-- Function Name: VALIDATE_ITEM
-- Purpose: Function that will validate if the item entered through the SMR Mass RTV form is
--          a valid item.
--------------------------------------------------------------------------------------------------
/* OLR Vs 1.02 Inserted -- Start */
FUNCTION VALIDATE_ITEM (O_error_message     IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                        O_is_valid          IN OUT BOOLEAN,
                        O_all_locs_ranged   IN OUT BOOLEAN,
                        I_item              IN     ITEM_MASTER.ITEM%TYPE,
                        I_supplier          IN     SUPS.SUPPLIER%TYPE,
                        I_pack_ind          IN     VARCHAR2,
                        I_physical_wh_ind   IN     VARCHAR2)
RETURN BOOLEAN AS

  L_program              VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.VALIDATE_ITEM';
  L_receive_as_type      ITEM_LOC.RECEIVE_AS_TYPE%TYPE;
  L_mass_rtv_loc_count   NUMBER(10);
  L_index                NUMBER(10);
  L_locs                 loc_TBL;

  --Cursor that will get all locations that has been applied to the Mass RTV
  --Note: During the initial process of adding locations into the SMR_RTV_ITEM_LOCATIONS_TEMP table,
  --	    only the locations were added with no items. Therefore, records exists in this table with
  --      only location information for the purpose of adding new items.
  cursor C_get_all_locs is
    select loc,
           loc_desc,
           loc_type
      from smr_rtv_item_locations_temp
     where item is null;

BEGIN

  O_is_valid := TRUE;

  if I_physical_wh_ind = 'Y' then
      if SUPP_ITEM_SQL.EXIST (O_error_message,
                              O_is_valid,
                              I_item,
                              I_supplier) = FALSE then
      return FALSE;
    end if;

    if O_is_valid = FALSE then
      O_error_message := SQL_LIB.CREATE_MSG('ITEM_SUP_NOT_EXIST',
                                            I_supplier,
                                            I_item,
                                            NULL);
    end if;
  end if;

  if O_is_valid then
    L_locs            := null;
    O_all_locs_ranged := TRUE;

    --Store all the locations that have been selected for the Mass RTV
    open C_get_all_locs;
    fetch C_get_all_locs BULK COLLECT INTO L_locs;
    close C_get_all_locs;

    L_mass_rtv_loc_count := L_locs.count;

    --Call the following function to filter the collection LP_locs of any locations
    --that the item is not ranged to
    if SET_RANGED_LOCS(O_error_message,
                       L_locs,
                       I_supplier,
                       I_item) = FALSE then
      return FALSE;
    end if;

    if L_locs.count = 0 then
      O_is_valid      := FALSE;
      O_error_message := SQL_LIB.CREATE_MSG('CANT_RETURN_SKU',
                                            I_item,
                                            NULL,
                                            NULL);
    else
      --Check if the item was ranged to all the locations for the Mass RTV
      if L_locs.count < L_mass_rtv_loc_count then
        O_all_locs_ranged := FALSE;
        O_error_message := SQL_LIB.CREATE_MSG('SMR_NOT_ALL_APPLIED',
                                              I_item,
                                              NULL,
                                              NULL);
      end if;

      L_index := L_locs.FIRST;

      while L_index is not null loop
        --if processing a store and the item is a pack, return as
        --invalid since pack items are not kept in stores.
        if L_locs(L_index).loc_type = 'S' and I_pack_ind = 'Y' then
          O_is_valid      := FALSE;
          O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_ST',
                                                I_item,
                                                NULL,
                                                NULL);
          exit;
        end if;

        --If processing for warehouses, check that the receive type is pack and not eaches.
        if L_locs(L_index).loc_type = 'W' and I_pack_ind = 'Y' then
          if ITEMLOC_ATTRIB_SQL.GET_RECEIVE_AS_TYPE(O_error_message,
                                                    L_receive_as_type,
                                                    I_item,
                                                    L_locs(L_index).loc) = FALSE then
            return FALSE;
          end if;

          if NVL(L_receive_as_type,'P') = 'E' then
            O_is_valid      := FALSE;
            O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_WH',
                                                  I_item,
                                                  L_locs(L_index).loc,
                                                  NULL);
            exit;
          end if;
        end if;

        L_index := L_locs.next(L_index);
      end loop;
    end if;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END VALIDATE_ITEM;
/* OLR Vs 1.02 Inserted -- End */

--------------------------------------------------------------------------------------------------

/* OLR Vs 1.01 Removed -- Start
FUNCTION VALIDATE_ITEM (O_error_message     IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                        O_is_valid          IN OUT BOOLEAN,
                        O_all_locs_ranged   IN OUT BOOLEAN,  -- OLR Vs 1.01 Inserted --
                        I_item              IN     ITEM_MASTER.ITEM%TYPE,
                        I_supplier          IN     SUPS.SUPPLIER%TYPE,
                        I_pack_ind          IN     VARCHAR2,
                        I_physical_wh_ind   IN     VARCHAR2)
RETURN BOOLEAN AS

  L_program              VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.VALIDATE_ITEM';
  L_receive_as_type      ITEM_LOC.RECEIVE_AS_TYPE%TYPE;
  L_mass_rtv_loc_count   NUMBER(10);  -- OLR Vs 1.01 Inserted
  L_index                NUMBER(10);  -- OLR Vs 1.01 Inserted

  --Cursor that will get all locations that has been applied to the Mass RTV
  --Note: During the initial process of adding locations into the SMR_RTV_ITEM_LOCATIONS_TEMP table,
  --	    only the locations were added with no items. Therefore, records exists in this table with
  --      only location information for the purpose of adding new items.
  cursor C_get_all_locs is
    select loc,
           loc_desc,
           loc_type
      from smr_rtv_item_locations_temp
     where item is null;

BEGIN

  -- OLR Vs 1.01 Inserted -- Start
  O_is_valid := TRUE;

  if I_physical_wh_ind = 'Y' then
      if SUPP_ITEM_SQL.EXIST (O_error_message,
                              O_is_valid,
                              I_item,
                              I_supplier) = FALSE then
      return FALSE;
    end if;

    if O_is_valid = FALSE then
      O_error_message := SQL_LIB.CREATE_MSG('ITEM_SUP_NOT_EXIST',
                                            I_supplier,
                                            I_item,
                                            NULL);
    end if;
  end if;

  if O_is_valid then
    LP_locs           := null;
    O_all_locs_ranged := TRUE;

    --Store all the locations that have been selected for the Mass RTV
    open C_get_all_locs;
    fetch C_get_all_locs BULK COLLECT INTO LP_locs;
    close C_get_all_locs;

    L_mass_rtv_loc_count := LP_locs.count;

    --Call the following function to filter the collection LP_locs of any locations
    --that the item is not ranged to
    if SET_RANGED_LOCS(O_error_message,
                       I_supplier,
                       I_item) = FALSE then
      return FALSE;
    end if;

    if LP_locs.count = 0 then
      O_is_valid      := FALSE;
      O_error_message := SQL_LIB.CREATE_MSG('CANT_RETURN_SKU',
                                            I_item,
                                            NULL,
                                            NULL);
    else
      --Check if the item was ranged to all the locations for the Mass RTV
      if LP_locs.count < L_mass_rtv_loc_count then
        O_all_locs_ranged := FALSE;
        O_error_message := SQL_LIB.CREATE_MSG('SMR_NOT_ALL_APPLIED',
                                              I_item,
                                              NULL,
                                              NULL);
      end if;

      L_index := LP_locs.FIRST;

      while L_index is not null loop
        --if processing a store and the item is a pack, return as
        --invalid since pack items are not kept in stores.
        if LP_locs(L_index).loc_type = 'S' and I_pack_ind = 'Y' then
          O_is_valid      := FALSE;
          O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_ST',
                                                I_item,
                                                NULL,
                                                NULL);
          exit;
        end if;

        --If processing for warehouses, check that the receive type is pack and not eaches.
        if LP_locs(L_index).loc_type = 'W' and I_pack_ind = 'Y' then
          if ITEMLOC_ATTRIB_SQL.GET_RECEIVE_AS_TYPE(O_error_message,
                                                    L_receive_as_type,
                                                    I_item,
                                                    LP_locs(L_index).loc) = FALSE then
            return FALSE;
          end if;

          if NVL(L_receive_as_type,'P') = 'E' then
            O_is_valid      := FALSE;
            O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_WH',
                                                  I_item,
                                                  LP_locs(L_index).loc,
                                                  NULL);
            exit;
          end if;
        end if;

        L_index := LP_locs.next(L_index);
      end loop;
    end if;
  end if;
  -- OLR Vs 1.01 Inserted -- End

  -- OLR Vs 1.01 Removed -- Start
  O_is_valid := TRUE;
  LP_locs    := null;

  --store all locations into an array that will be used for processing the item
  open C_get_all_locs;
  fetch C_get_all_locs BULK COLLECT INTO LP_locs;
  close C_get_all_locs;

  if I_physical_wh_ind = 'Y' then
      if SUPP_ITEM_SQL.EXIST (O_error_message,
                              O_is_valid,
                              I_item,
                              I_supplier) = FALSE then
      return FALSE;
    end if;

    if O_is_valid = FALSE then
      O_error_message := SQL_LIB.CREATE_MSG('ITEM_SUP_NOT_EXIST',
                                            I_supplier,
                                            I_item,
                                            NULL);
    end if;
  end if;

  --loop through each loc to validate the item against the
  --supplier/location combo.
  for i in 1..LP_locs.count loop
    if LP_locs(i).loc_type = 'W' then
      L_store := -1;
      L_wh    := LP_locs(i).loc;
    else
      L_wh    := -1;
      L_store := LP_locs(i).loc;
    end if;

    --if processing a store and the item is a pack, return as
    --invalid since pack items are not kept in stores.
    if LP_locs(i).loc_type = 'S' and I_pack_ind = 'Y' then
      O_is_valid      := FALSE;
      O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_ST',
                                            I_item,
                                            NULL,
                                            NULL);
      exit;
    end if;

    --Validate that the Item/Loc/Supplier combo is valid
    if RTV_VALIDATE_SQL.INVENTORY_ITEM(O_error_message,
                                       I_item,
                                       I_supplier,
                                       L_store,
                                       L_wh,
                                       O_is_valid) = FALSE then
      return FALSE;
    end if;

    if O_is_valid = FALSE then
      exit; --stop validating since item has already failed for at least one location
    end if;

    --If processing for warehouses, check that the receive type is pack and not eaches.
    if LP_locs(i).loc_type = 'W' and I_pack_ind = 'Y' then
      if ITEMLOC_ATTRIB_SQL.GET_RECEIVE_AS_TYPE(O_error_message,
                                                L_receive_as_type,
                                                I_item,
                                                L_wh) = FALSE then
        return FALSE;
      end if;
      ---
      if NVL(L_receive_as_type,'P') = 'E' then
        O_is_valid      := FALSE;
        O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_WH',
                                              I_item,
                                              L_wh,
                                              NULL);
        return FALSE;
      end if;
    end if;
  end loop;
  -- OLR Vs 1.01 Removed

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END VALIDATE_ITEM;

--------------------------------------------------------------------------------------------------
-- Function Name: VALIDATE_RECEIVE_AS_TYPE
-- Purpose: Function that will call the ITEMLOC_ATTRIB_SQL.GET_RECEIVE_AS_TYPE to validate that an
--          item has a valid receive type for the warehouses in the Mass RTV
--------------------------------------------------------------------------------------------------
FUNCTION VALIDATE_RECEIVE_AS_TYPE (O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                                   O_is_valid      IN OUT BOOLEAN,
                                   I_item          IN     ITEM_MASTER.ITEM%TYPE)
RETURN BOOLEAN AS

  L_program          VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.VALIDATE_RECEIVE_AS_TYPE';
  L_receive_as_type  ITEM_LOC.RECEIVE_AS_TYPE%TYPE;

BEGIN

  O_is_valid := TRUE;

  for i in 1..LP_locs.count loop
    if ITEMLOC_ATTRIB_SQL.GET_RECEIVE_AS_TYPE(O_error_message,
                                              L_receive_as_type,
                                              I_item,
                                              LP_locs(i).loc) = FALSE then
       return FALSE;
    end if;
    ---
    if NVL(L_receive_as_type,'P') = 'E' then
      O_is_valid := FALSE;

      O_error_message := SQL_LIB.CREATE_MSG('RTV_PACK_WH',
                                            I_item,
                                            LP_locs(i).loc,
                                            NULL);
      exit;
    end if;
  end loop;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END VALIDATE_RECEIVE_AS_TYPE;
OLR Vs 1.02 Removed -- End */

--------------------------------------------------------------------------------------------------
-- Function Name: APPLY_LOCATIONS
-- Purpose: Function that will create a record in the SMR_RTV_ITEM_LOCATIONS_TEMP for each location
--          in the Mass RTV.
--
--    NOTE: If I_loc_type 'A' - All stores are inserted
--          If I_loc_type 'S' - Inserting a store
--          IF I_loc_type 'W' - Inserting a warehouse
--------------------------------------------------------------------------------------------------
FUNCTION APPLY_LOCATIONS (O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                          I_loc_type      IN     VARCHAR2,
                          I_loc           IN     ITEM_LOC.LOC%TYPE)
RETURN BOOLEAN AS

  L_program   VARCHAR2(50)   := 'SMR_MASS_RTV_SQL.APPLY_LOCATIONS';

  L_loc_desc  STORE.STORE_NAME%TYPE;

BEGIN

  --If processing for All stores, then insert all stores
  --Note that some stores may have initially been added by the user before
  --electing to apply all stores.
  if I_loc_type = 'A' then
    insert into SMR_RTV_ITEM_LOCATIONS_TEMP(LOC,
                                            LOC_DESC,
                                            LOC_TYPE)
                                     select st.store,
                                            st.store_name,
                                            'S'
                                       from store st
                                      where not exists (select 1
                                                          from smr_rtv_item_locations_temp tmp
                                                         where tmp.loc      = st.store
                                                           and tmp.loc_type = 'S');
  else
    --If processing for Store, get store name
    if I_loc_type = 'S' then
      if STORE_ATTRIB_SQL.GET_NAME(O_error_message,
                                   I_loc,
                                   L_loc_desc) = FALSE then
        return FALSE;
      end if;
    else
      --Processing for wh, get wh name
      if WH_ATTRIB_SQL.GET_NAME(O_error_message,
                                I_loc,
                                L_loc_desc) = FALSE then
        return FALSE;
      end if;
    end if;

    if INSERT_SMR_RTV_ITEM_LOCS_TEMP(O_error_message,
                                     null,
                                     I_loc,
                                     L_loc_desc,
                                     I_loc_type,
                                     null,
                                     null,
                                     null,  /* OLR Vs 1.06 Inserted */
                                     null) = FALSE then
      return FALSE;
    end if;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END APPLY_LOCATIONS;

--------------------------------------------------------------------------------------------------
-- Function Name: APPLY_ITEMS
-- Purpose: Function that will perform validations and processes on an item or item list and
--          inserts into the SMR_RTV_ITEMS_TEMP and SMR_RTV_ITEM_LOCATIONS_TEMP temp tables.
--------------------------------------------------------------------------------------------------
/* OLR Vs 1.02 Inserted -- Start */
FUNCTION APPLY_ITEMS (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                      O_applied_ind      IN OUT VARCHAR2,
                      I_supplier         IN     SUPS.SUPPLIER%TYPE,
                      I_item             IN     ITEM_MASTER.ITEM%TYPE,
                      I_item_desc        IN     ITEM_MASTER.ITEM_DESC%TYPE,
                      I_item_type        IN     VARCHAR2,
                      I_soh_default_ind  IN     VARCHAR2,
                      I_physical_wh_ind  IN     VARCHAR2)
RETURN BOOLEAN IS

  L_program        VARCHAR2(50) := 'SMR_MASS_RTV_SQL.APPLY_ITEMS';

BEGIN

  if I_item_type = 'SS' then
    if PROCESS_ITEM(O_error_message,
                    O_applied_ind,
                    I_supplier,
                    I_item,
                    I_item_desc,
                    I_soh_default_ind,
                    I_physical_wh_ind,
                    'Y') = FALSE then  --Inventory Ind will always be 'Y for items when performing RTVs
      return FALSE;
    end if;
  else
    if PROCESS_ITEM_LIST(O_error_message,
                         O_applied_ind,
                         I_supplier,
                         I_item,
                         I_soh_default_ind,
                         I_physical_wh_ind) = FALSE then
      return FALSE;
    end if;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END APPLY_ITEMS;
/* OLR Vs 1.02 Inserted -- Start */

--------------------------------------------------------------------------------------------------

/* OLR Vs 1.02 Removed -- Start
FUNCTION APPLY_ITEMS (O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                      O_all_applied      IN OUT BOOLEAN,
                      I_supplier         IN     SUPS.SUPPLIER%TYPE,
                      I_item             IN     ITEM_MASTER.ITEM%TYPE,
                      I_item_desc        IN     ITEM_MASTER.ITEM_DESC%TYPE,
                      I_item_type        IN     VARCHAR2,
                      I_soh_default_ind  IN     VARCHAR2,
                      I_physical_wh_ind  IN     VARCHAR2)
RETURN BOOLEAN IS

  L_program        VARCHAR2(50) := 'SMR_MASS_RTV_SQL.APPLY_ITEMS';

  --Cursor that will get all locations that has been applied to the Mass RTV
  --Note: During the initial process of adding locations into the SMR_RTV_ITEM_LOCATIONS_TEMP table,
  --      only the locations were added with no items. Therefore, records exists in this table with
  --      only location information for the purpose of adding new items.
  cursor C_get_all_locs is
    select loc,
           loc_desc,
           loc_type
      from smr_rtv_item_locations_temp
     where item is null;

BEGIN

  -- OLR VS 1.01 Removed -- Start
  LP_locs := null;

  --store all locations into an array that will be used for processing the item
  open C_get_all_locs;
  fetch C_get_all_locs BULK COLLECT INTO LP_locs;
  close C_get_all_locs;
  -- OLR Vs 1.01 Removed -- End

  --Processing for Items
  if I_item_type = 'SS' then
    -- OLR Vs 1.01 Inserted -- Start
    LP_locs := null;

    --Store all the locations that have been selected for the Mass RTV
    open C_get_all_locs;
    fetch C_get_all_locs BULK COLLECT INTO LP_locs;
    close C_get_all_locs;

    --Call the following function to filter the collection LP_locs of any locations
    --that the item is not ranged to
    if SET_RANGED_LOCS(O_error_message,
                       I_supplier,
                       I_item) = FALSE then
      return FALSE;
    end if;
    -- OLR Vs 1.01 Inserted -- End

    if PROCESS_ITEM(O_error_message,
                    I_supplier,
                    I_item,
                    I_item_desc,
                    I_soh_default_ind,
                    I_physical_wh_ind,
                    'Y') = FALSE then  --Inventory Ind will always be 'Y for items when performing RTVs
      return FALSE;
    end if;
  else
    if PROCESS_ITEM_LIST(O_error_message,
                         O_all_applied,
                         I_supplier,
                         I_item,
                         I_soh_default_ind,
                         I_physical_wh_ind) = FALSE then
      return FALSE;
    end if;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END APPLY_ITEMS;
OLR Vs 1.02 Removed -- End */

--------------------------------------------------------------------------------------------------
-- Function Name: GET_RTV_TOTALS
-- Purpose: Function that will get the running totals for the Mass RTV
--------------------------------------------------------------------------------------------------
FUNCTION GET_RTV_TOTALS (O_error_message     IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                         O_ttl_rtv_units     IN OUT NUMBER,
                         O_ttl_rtv_retail    IN OUT NUMBER,
                         O_ttl_rtv_unit_cost IN OUT NUMBER)
RETURN BOOLEAN IS

  L_program  VARCHAR2(50) := 'SMR_MASS_RTV_SQL.GET_RTV_TOTALS';

  --Cursor to get the total units for the Mass RTV
  cursor C_get_ttl_rtv_units is
    select sum(qty_requested)
      from smr_rtv_item_locations_temp
     where item is not null;

  --Cursor to get the total cost for the Mass RTV
  cursor C_get_ttl_rtv_retail is
    /* select sum(qty_requested * orig_unit_cost)    -- OLR Vs 1.06 Removed */
    select sum(qty_requested * selling_unit_retail)  /* OLR Vs 1.06 inserted */
      from smr_rtv_item_locations_temp
     where item is not null;

  --Cursor to get the total unit cost for the Mass RTV
  --Cursor to get the total cost for the Mass RTV
  cursor C_get_ttl_rtv_unit_cost is
    /* select sum(orig_unit_cost)                    -- OLR VS 1.06 Removed */
    select sum(qty_requested * orig_unit_cost)       /* OLR Vs 1.06 Inserted */
      from smr_rtv_item_locations_temp
     where item is not null;

BEGIN

  open C_get_ttl_rtv_units;
  fetch C_get_ttl_rtv_units into O_ttl_rtv_units;
  close C_get_ttl_rtv_units;

  open C_get_ttl_rtv_retail;
  fetch C_get_ttl_rtv_retail into O_ttl_rtv_retail;
  close C_get_ttl_rtv_retail;

  open C_get_ttl_rtv_unit_cost;
  fetch C_get_ttl_rtv_unit_cost into O_ttl_rtv_unit_cost;
  close C_get_ttl_rtv_unit_cost;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END GET_RTV_TOTALS;

--------------------------------------------------------------------------------------------------
-- Function Name: HAS_LOCS_AND_ITEMS
-- Purpose: Function that will check that locations and items exist for the Mass RTV
--------------------------------------------------------------------------------------------------
FUNCTION HAS_LOCS_AND_ITEMS (O_error_message  IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                             O_has_locs       IN OUT BOOLEAN,
                             O_has_items      IN OUT BOOLEAN)
RETURN BOOLEAN IS

  L_program  VARCHAR2(50) := 'SMR_MASS_RTV_SQL.HAS_LOCS_AND_ITEMS';
  L_dummy    VARCHAR2(1);
  --Cursor that will check that locatiosn have been added
  cursor C_locs_exist is
    select 'X'
      from smr_rtv_item_locations_temp
     where loc is not null
       and rownum = 1;

  --Cursor that will check that items have been added
  cursor C_items_exist is
    select 'X'
      from smr_rtv_items_temp
     where item is not null
       and rownum = 1;


BEGIN
  O_has_locs  := TRUE;
  O_has_items := TRUE;

  open C_locs_exist;
  fetch C_locs_exist into L_dummy;
  if C_locs_exist%NOTFOUND then
    O_has_locs := FALSE;
  end if;
  close C_locs_exist;

  open C_items_exist;
  fetch C_items_exist into L_dummy;
  if C_items_exist%NOTFOUND then
    O_has_items := FALSE;
  end if;
  close C_items_exist;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END HAS_LOCS_AND_ITEMS;

--------------------------------------------------------------------------------------------------
-- Function Name: GET_TTL_COST_OF_SUP_POS
-- Purpose: Function that will get the total retail value of all open approved POs with
--          an OTB_EOW_DATE < today + 60 days for a supplier.
--------------------------------------------------------------------------------------------------
FUNCTION GET_TTL_COST_OF_SUP_POS(O_error_message       IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                                 O_ttl_cost_of_sup_pos IN OUT RTV_DETAIL.UNIT_COST%TYPE,
                                 I_supplier            IN     SUPS.SUPPLIER%TYPE)
RETURN BOOLEAN IS

  L_program             VARCHAR2(50)          := 'SMR_MASS_RTV_SQL.GET_TTL_COST_OF_SUP_POS';
  L_total_cost_ord      ORDLOC.UNIT_COST%TYPE := 0;

  --The following variables are only used to call a package.
  L_prescale_cost_ord   ORDLOC.UNIT_COST%TYPE;
  L_outstand_cost_ord   ORDLOC.UNIT_COST%TYPE;
  L_cancel_cost_ord     ORDLOC.UNIT_COST%TYPE;

  --cursor to get all Open Approved PO's for the supplier
  cursor C_get_pos is
    select order_no
      from ordhead
     where supplier     = I_supplier
       and status       = 'A'
       and otb_eow_date < (sysdate + 60);

BEGIN

  O_ttl_cost_of_sup_pos := 0;

  for rec in C_get_pos loop
    if ORDER_CALC_SQL.TOTAL_COSTS(O_error_message,
                                  L_total_cost_ord,
                                  L_prescale_cost_ord,
                                  L_outstand_cost_ord,
                                  L_cancel_cost_ord,
                                  rec.order_no,
                                  null,              --null item since the entire PO
                                  null) = FALSE then --null location since the entire PO
      return TRUE;
    end if;

    O_ttl_cost_of_sup_pos := O_ttl_cost_of_sup_pos + L_total_cost_ord;

  end loop;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END GET_TTL_COST_OF_SUP_POS;

-------------------------------------------------------------------------------------------------
-- Function Name: CREATE_RTV
-- Purpose: Function that will create the Mass RTVs. Records will be inserted into the
--          appropriate RTV tables
--------------------------------------------------------------------------------------------------
FUNCTION CREATE_RTV (O_error_message      IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                     I_status             IN     NUMBER,
                     I_supplier           IN     SUPS.SUPPLIER%TYPE,
                     I_ship_to_add_1      IN     RTV_HEAD.SHIP_TO_ADD_1%TYPE,
                     I_ship_to_add_2      IN     RTV_HEAD.SHIP_TO_ADD_2%TYPE,
                     I_ship_to_add_3      IN     RTV_HEAD.SHIP_TO_ADD_3%TYPE,
                     I_ship_to_city       IN     RTV_HEAD.SHIP_TO_CITY%TYPE,
                     I_state              IN     RTV_HEAD.STATE%TYPE,
                     I_ship_to_country_id IN     RTV_HEAD.SHIP_TO_COUNTRY_ID%TYPE,
                     I_ship_to_pcode      IN     RTV_HEAD.SHIP_TO_PCODE%TYPE,
                     I_ret_auth_num       IN     RTV_HEAD.RET_AUTH_NUM%TYPE,
                     I_courier            IN     RTV_HEAD.COURIER%TYPE,
                     I_freight            IN     RTV_HEAD.FREIGHT%TYPE,
                     I_created_date       IN     RTV_HEAD.CREATED_DATE%TYPE,
                     I_comment_desc       IN     RTV_HEAD.COMMENT_DESC%TYPE,
                     I_not_after_date     IN     RTV_HEAD.NOT_AFTER_DATE%TYPE,
                     I_restock_pct        IN     RTV_HEAD.RESTOCK_PCT%TYPE,
                     I_rtv_reason         IN     RTV_HEAD.ITEM%TYPE)
RETURN BOOLEAN IS

  L_program            VARCHAR2(50)                := 'SMR_MASS_RTV_SQL.CREATE_RTV';
  L_return             VARCHAR2(10)                := 'TRUE';
  L_curr_loc           ITEM_LOC.LOC%TYPE           := -1;
  L_store              ITEM_LOC.LOC%TYPE           := -1;
  L_wh                 ITEM_LOC.LOC%TYPE           := -1;
  L_curr_seq_no        RTV_DETAIL.SEQ_NO%TYPE      := 0;
  L_curr_restock_cost  RTV_HEAD.RESTOCK_COST%TYPE;
  L_curr_ttl_order_amt RTV_HEAD.TOTAL_ORDER_AMT%TYPE;
  L_curr_rtv_order_no  RTV_HEAD.RTV_ORDER_NO%TYPE;
  L_rtv_order_no_TBL   rtv_order_no_TBL;
  L_index              NUMBER(10)                  := 1;

  --Cursor that will get all item loc records to create the RTVs
  cursor C_get_item_locs is
    select *
      from smr_rtv_item_locations_temp
     where item is not null
     order by loc;

  --cursor that will get the total order amount for a single RTV
  cursor C_get_total_order_amount is
    select sum(qty_requested * orig_unit_cost)
      from smr_rtv_item_locations_temp
     where loc = L_curr_loc;

BEGIN

  for rec in C_get_item_locs loop
    --If a new location, then create a new RTV_HEAD record
    if L_curr_loc <> rec.loc then
      --If the location has changed, then we have to create a new RTV.
      -- generate an Rtv Order No for a new RTV
      NEXT_RTV_ORDER_NO(L_curr_rtv_order_no,
                        L_return,
                        O_error_message);

      if L_return = 'FALSE' then
        return FALSE;
      end if;

      --If the user elected to approve the Mass RTVs, then collect all rtv_order_no's for
      --later processing
      if I_status = 10 then
        L_rtv_order_no_TBL(L_index) := L_curr_rtv_order_no;
        L_index                     := L_index + 1;
      end if;

      L_curr_loc    := rec.loc;
      L_curr_seq_no := 1;

      if rec.loc_type = 'S' then
        L_store := rec.loc;
        L_wh    := -1;
      else
        L_wh    := rec.loc;
        L_store := -1;
      end if;

      open C_get_total_order_amount;
      fetch C_get_total_order_amount into L_curr_ttl_order_amt;
      close C_get_total_order_amount;

      if I_restock_pct is not null then
        L_curr_restock_cost := L_curr_ttl_order_amt * (I_restock_pct/100);
      else
        L_curr_restock_cost := null;
      end if;

      --Create the RTV Head record
      insert into RTV_HEAD(RTV_ORDER_NO,
                           SUPPLIER,
                           STATUS_IND,
                           STORE,
                           WH,
                           TOTAL_ORDER_AMT,
                           SHIP_TO_ADD_1,
                           SHIP_TO_ADD_2,
                           SHIP_TO_ADD_3,
                           SHIP_TO_CITY,
                           STATE,
                           SHIP_TO_COUNTRY_ID,
                           SHIP_TO_PCODE,
                           RET_AUTH_NUM,
                           COURIER,
                           FREIGHT,
                           CREATED_DATE,
                           COMMENT_DESC,
                           NOT_AFTER_DATE,
                           RESTOCK_PCT,
                           RESTOCK_COST,
                           ITEM)
                    values(L_curr_rtv_order_no,
                           I_supplier,
                           5, --Status of input when the RTV is created.
                           L_store,
                           L_wh,
                           L_curr_ttl_order_amt,
                           I_ship_to_add_1,
                           I_ship_to_add_2,
                           I_ship_to_add_3,
                           I_ship_to_city,
                           I_state,
                           I_ship_to_country_id,
                           I_ship_to_pcode,
                           I_ret_auth_num,
                           I_courier,
                           I_freight,
                           I_created_date,
                           I_comment_desc,
                           I_not_after_date,
                           I_restock_pct,
                           nvl(L_curr_restock_cost,0),   -- OLR 1.04 Added nvl function as RIB requires the handling_cost to be present in the message.
                           I_rtv_reason);  --selected rtv reason from form will populate the item field for SMR
      end if;

      --create RTV Detail records
      insert into RTV_DETAIL(RTV_ORDER_NO,
                             SEQ_NO,
                             ITEM,
                             QTY_REQUESTED,
                             UNIT_COST,
                             REASON,
                             PUBLISH_IND,
                             RESTOCK_PCT,
                             ORIGINAL_UNIT_COST,
                             UPDATED_BY_RMS_IND)
                      values(L_curr_rtv_order_no,
                             L_curr_seq_no,
                             rec.item,
                             rec.qty_requested,
                             rec.orig_unit_cost,
                             I_rtv_reason   , --V 1.07
                             --'O',   --'O'verstock reason code for Mass RTVs   --V 1.07
                             'N',   --Publish Ind of No
                             I_restock_pct,
                             rec.orig_unit_cost,
                             'Y');

    --increment Seq No after each detail record
    L_curr_seq_no := L_curr_seq_no + 1;
  end loop;

  --If the user has elected to approve all the RTVs in the Mass RTV, then loop through each created
  --RTV and approve.
  if I_status = 10 then
    for i in 1..L_rtv_order_no_TBL.count loop
      if RTV_SQL.UPD_RTV_QTY(O_error_message,
                             L_rtv_order_no_TBL(i),
                             NULL,
                             'A') = FALSE then   -- I_action_type
        return FALSE;
      end if;

      --Update the RTV to approved
      update rtv_head
         set status_ind = 10
       where rtv_order_no = L_rtv_order_no_TBL(i);
   end loop;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END CREATE_RTV;

/* OLR Vs 1.05 Inserted -- Start */
-------------------------------------------------------------------------------------------------
-- Function Name: VALIDATE_ITEM_DEPT
-- Purpose: Function that will validate that the item entered belongs to the department selected
--          by the user through the form.
--------------------------------------------------------------------------------------------------
FUNCTION VALIDATE_ITEM_DEPT(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                            O_is_valid      IN OUT BOOLEAN,
                            I_item_type     IN     VARCHAR2,
                            I_item          IN     ITEM_MASTER.ITEM%TYPE,
                            I_dept          IN     DEPS.DEPT%TYPE)
RETURN BOOLEAN AS

  L_program   VARCHAR2(50) := 'SMR_MASS_RTV_SQL.VALIDATE_ITEM_DEPT';
  L_dummy     VARCHAR2(1);

  --Cursor to validate if to ensure that all item in the
  --list belongs to the department
  cursor C_validate_skulist is
    select 'X'
      from skulist_dept sd1,
           skulist_dept sd2
     where sd1.dept    = I_dept
       and sd1.skulist = I_item
       and sd2.skulist = sd1.skulist
       and sd2.dept    <> sd1.dept
       and rownum      = 1;

  cursor C_validate_item is
    select 'X'
      from item_master
     where item = I_item
       and dept = I_dept;

BEGIN

  O_is_valid := TRUE;

  --Validate for item list
  if I_item_type = 'IL' then
    open C_validate_skulist;
    fetch C_validate_skulist into L_dummy;
    if C_validate_skulist%FOUND then
      O_is_valid := FALSE;
    end if;
    close C_validate_skulist;
  else
    --validate for item
    open C_validate_item;
    fetch C_validate_item into L_dummy;
    if C_validate_item%NOTFOUND then
      O_is_valid := FALSE;
    end if;
    close C_validate_item;
  end if;

  return TRUE;

EXCEPTION
  when OTHERS then
    O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                           SQLERRM,
                                           L_program,
                                           to_char(SQLCODE));
    return FALSE;

END VALIDATE_ITEM_DEPT;
/* OLR Vs 1.05 Inserted -- End */
--------------------------------------------------------------------------------------------------
END SMR_MASS_RTV_SQL;
/