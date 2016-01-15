CREATE OR REPLACE PACKAGE BODY SMR_WH_SHIP_SQL IS
-- Module Name: SMR_WH_SHIP_SQL
-- Description: This package will be used to create WA shipments to stores.
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    15-Feb-15  Murali              LEAP 2 Development
--------------------------------------------------------------------------------
/*
Description:
   The package SMR_WH_SHIP_SQL is used to process the WH Shipments from WA into RMS table.
   The package consists of following Main Functions
   F_INIT_WH_SHIPMENTS - Function used to load data from Interface table into Shipping staging tables
   F_VALIDATE_SHIPMENTS - Function used to validate the Shipping data from WA
   F_PROCESS_WH_SHIPMENTS - Function to load the WH shipment from WA into RMS .
   F_FINISH_PROCESS - Update the status in the Queue Table.     

Algorithm
   - Call Function F_INIT_WH_SHIPMENTS to load the Staging table SMR_WH_ASN_STAGE from the Interface tables
   - Call function F_VALIDATE_SHIPMENTS to validate the Shipment data from WA . Insert all errors into SMR_RMS_INT_ERROR table.
   - Call function F_LOAD_SHIPMENTS to load Shipment data into RMS
   - Based on the Shipment Type identify if the shipment is for Allocation , Transfer or RTV. Invoke the Base API's based on the shipment type.
   - Call fucntion  F_FINISH_PROCESS to  Update the status in the Interface Queue Table.	   

*/
-------------------------------------------------------------------------------------
--PRIVATE FUNCTIONS/PROCEDURES
-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Procedure Name: SHO
-- Purpose: Used for debug purposes
-------------------------------------------------------------------------------------
PROCEDURE SHO(O_ERROR_MESSAGE IN VARCHAR2) IS
   L_DEBUG_ON BOOLEAN := false;            -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
   L_DEBUG_TIME_ON BOOLEAN := false;       -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
BEGIN

   IF L_DEBUG_ON THEN
      dbms_output.put_line('DBG: '||O_ERROR_MESSAGE);
   END IF;
   IF L_DEBUG_TIME_ON THEN
      dbms_output.put_line('DBG: '||to_char(sysdate,'HH24:MI:SS')||O_ERROR_MESSAGE);
   END IF;
END;

--------------------------------------------------------------------------------
-- Function Name: COPY_STORE_ITEM
-- Purpose: Create item X at store 1 like item Y at store 1
--------------------------------------------------------------------------------
FUNCTION COPY_STORE_ITEM(I_like_store       IN      store.store%TYPE,
                         I_new_store        IN      store.store%TYPE,
                         I_item             IN      item_master.item%TYPE,
                         O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
        RETURN BOOLEAN IS
   L_item               ITEM_EXP_HEAD.ITEM%TYPE;
   L_supplier           ITEM_EXP_HEAD.SUPPLIER%TYPE;
   L_seq                ITEM_EXP_HEAD.ITEM_EXP_SEQ%TYPE;
   L_daily_waste_pct    ITEM_LOC.DAILY_WASTE_PCT%TYPE;
   L_elc_ind            SYSTEM_OPTIONS.ELC_IND%TYPE;
   L_program            VARCHAR2(64) := package_name||'.COPY_STORE_ITEM';

   cursor C_ITEM_EXP_HEAD is
      select ieh.ITEM           item1,
             ieh.SUPPLIER     supplier1
        from COST_ZONE_GROUP    czg,
             ITEM_MASTER        im,
             ITEM_EXP_HEAD      ieh
       where ieh.ITEM              = im.ITEM
         and ieh.ZONE_GROUP_ID     = czg.ZONE_GROUP_ID
         and im.COST_ZONE_GROUP_ID = czg.ZONE_GROUP_ID
         and ieh.ITEM_EXP_TYPE     = 'Z'
         and czg.COST_LEVEL        = 'L'
         and ieh.ZONE_ID           = I_like_store
         and im.item               = I_item;

   cursor C_GET_MAX_SEQ is
      select max(item_exp_seq) + 1
        from ITEM_EXP_HEAD
       where ITEM          = L_item
         and SUPPLIER      = L_supplier
         and ITEM_EXP_TYPE = 'Z';

   cursor C_GET_ITEMS is
      select il.ITEM,
             il.LOC_TYPE,
             il.DAILY_WASTE_PCT,
             ils.UNIT_COST,
             --il.UNIT_RETAIL, -- OLR V1.05 Removed
             il.REGULAR_UNIT_RETAIL UNIT_RETAIL, -- OLR V1.05 Inserted
             il.SELLING_UNIT_RETAIL,
             il.SELLING_UOM,
             il.STATUS,
             il.TAXABLE_IND,
             il.TI,
             il.HI,
             il.STORE_ORD_MULT,
             il.MEAS_OF_EACH,
             il.MEAS_OF_PRICE,
             il.UOM_OF_PRICE,
             il.PRIMARY_VARIANT,
             il.PRIMARY_SUPP,
             il.PRIMARY_CNTRY,
             il.LOCAL_ITEM_DESC,
             il.LOCAL_SHORT_DESC,
             il.PRIMARY_COST_PACK,
             il.RECEIVE_AS_TYPE
        from item_loc il,
             item_loc_soh ils,
             item_master im
       where il.loc       = I_like_store
         and il.item      = ils.item(+)
         and il.loc       = ils.loc(+)
         and il.item      = im.item
         and im.item      = I_item
     order by im.pack_ind;

BEGIN

--   sho(L_program ||' Copy '||I_item||' at '||I_new_store||' like '|| I_like_store);

   ------------------------------------------------------
   -- The function SYSTEM_OPTIONS_SQL.GET_ELC_IND define
   -- L_elc_ind - the indicator which determines landed
   -- cost (elc_ind = 'Y') or supplier's cost (elc_ind = 'N')
   -- will be used within the system.
   -- When landed cost is used within the system, markup
   -- percent will be calculated based on landed cost,
   -- instead of supplier's cost,  in the Item Maintenance
   -- and Retail/Cost Change dialogues.
   ------------------------------------------------------
   if not SYSTEM_OPTIONS_SQL.GET_ELC_IND(O_error_message,
                                         L_elc_ind) then
      return FALSE;
   end if;

   if L_elc_ind = 'Y' then
   ---
      for C_ITEM_EXP_HEAD_REC in C_ITEM_EXP_HEAD loop
         L_item := C_ITEM_EXP_HEAD_REC.item1;
         L_supplier := C_ITEM_EXP_HEAD_REC.supplier1;
         SQL_LIB.SET_MARK('OPEN','C_GET_MAX_SEQ','ITEM_EXP_HEAD',NULL);
         open C_GET_MAX_SEQ;
         SQL_LIB.SET_MARK('FETCH','C_GET_MAX_SEQ','ITEM_EXP_HEAD',NULL);
         fetch C_GET_MAX_SEQ into L_seq;
         SQL_LIB.SET_MARK('CLOSE','C_GET_MAX_SEQ','ITEM_EXP_HEAD',NULL);
         close C_GET_MAX_SEQ;
         SQL_LIB.SET_MARK('INSERT',NULL,'ITEM_EXP_HEAD',NULL);
         insert into item_exp_head(item,
                                   supplier,
                                   item_exp_type,
                                   item_exp_seq,
                                   origin_country_id,
                                   zone_id,
                                   lading_port,
                                   discharge_port,
                                   zone_group_id,
                                   base_exp_ind,
                                   last_update_datetime,
                                   create_datetime,
                                   last_update_id)
         select L_item,
                L_supplier,
                'Z',
                L_seq + rownum,
                NULL,
                I_new_store,
                NULL,
                discharge_port,
                zone_group_id,
                'N',
                sysdate,
                sysdate,
                user
           from item_exp_head
          where item     = L_item
            and supplier = L_supplier
            and zone_id  = I_like_store;

         SQL_LIB.SET_MARK('INSERT',NULL,'ITEM_EXP_DETAIL',NULL);
         insert into item_exp_detail(item,
                                     supplier,
                                     item_exp_type,
                                     item_exp_seq,
                                     comp_id,
                                     cvb_code,
                                     comp_rate,
                                     comp_currency,
                                     per_count,
                                     per_count_uom,
                                     est_exp_value,
                                     nom_flag_1,
                                     nom_flag_2,
                                     nom_flag_3,
                                     nom_flag_4,
                                     nom_flag_5,
                                     display_order,
                                     last_update_datetime,
                                     create_datetime,
                                     last_update_id,
                                     defaulted_from,
                                     key_value_1,
                                     key_value_2)
         select ieh.item,
                ieh.supplier,
                'Z',
                ieh.item_exp_seq,
                ied.comp_id,
                ied.cvb_code,
                ied.comp_rate,
                ied.comp_currency,
                ied.per_count,
                ied.per_count_uom,
                ied.est_exp_value,
                ied.nom_flag_1,
                ied.nom_flag_2,
                ied.nom_flag_3,
                ied.nom_flag_4,
                ied.nom_flag_5,
                ied.display_order,
                sysdate,
                sysdate,
                user,
                ied.defaulted_from,
                ied.key_value_1,
                ied.key_value_2
           from item_exp_head ieh,
                item_exp_head ieh2,
                item_exp_detail ied
          where ied.item           = L_item
            and ied.supplier       = L_supplier
            and ied.item_exp_type  = 'Z'
            and ied.item_exp_seq   = ieh2.item_exp_seq
            and ieh2.zone_id       = I_like_store
            and ieh2.item          = L_item
            and ieh2.supplier      = L_supplier
            and ieh2.item_exp_type = 'Z'
            and ieh.zone_id        = I_new_store
            and ieh.item           = L_item
            and ieh.supplier       = L_supplier
            and ieh.item_exp_type  = 'Z';
      end LOOP;
   ---
   end if;
   ---
   for C_GET_ITEMS_REC in C_GET_ITEMS LOOP

      if NEW_ITEM_LOC ( O_error_message,
                        C_GET_ITEMS_REC.ITEM,
                        I_new_store,
                        NULL,
                        NULL,
                        C_GET_ITEMS_REC.LOC_TYPE,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        C_GET_ITEMS_REC.DAILY_WASTE_PCT,
                        NULL,
                        NULL,
                        NULL,
                        NULL,
                        C_GET_ITEMS_REC.UNIT_COST,
                        C_GET_ITEMS_REC.UNIT_RETAIL,
                        C_GET_ITEMS_REC.SELLING_UNIT_RETAIL,
                        C_GET_ITEMS_REC.SELLING_UOM,
                        C_GET_ITEMS_REC.STATUS,
                        C_GET_ITEMS_REC.TAXABLE_IND,
                        C_GET_ITEMS_REC.TI,
                        C_GET_ITEMS_REC.HI,
                        C_GET_ITEMS_REC.STORE_ORD_MULT,
                        C_GET_ITEMS_REC.MEAS_OF_EACH,
                        C_GET_ITEMS_REC.MEAS_OF_PRICE,
                        C_GET_ITEMS_REC.UOM_OF_PRICE,
                        C_GET_ITEMS_REC.PRIMARY_VARIANT,
                        C_GET_ITEMS_REC.PRIMARY_SUPP,
                        C_GET_ITEMS_REC.PRIMARY_CNTRY,
                        C_GET_ITEMS_REC.LOCAL_ITEM_DESC,
                        C_GET_ITEMS_REC.LOCAL_SHORT_DESC,
                        C_GET_ITEMS_REC.PRIMARY_COST_PACK,
                        C_GET_ITEMS_REC.RECEIVE_AS_TYPE,
                        NULL,
                        FALSE) = FALSE then
         return FALSE;
      end if;
   end LOOP;
   ---
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR', SQLERRM,
                                            L_program, to_char(SQLCODE));
      return FALSE;
END COPY_STORE_ITEM;

---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
-- Function : F_MAKE_ITEM_LOC
-- Purpose  : This function will make the entered item/location relationship in RMS
---------------------------------------------------------------------------------------------
function F_MAKE_ITEM_LOC(O_error_message IN OUT VARCHAR2,
                       I_item          IN     VARCHAR2,
                       I_loc           IN     NUMBER,
                       I_loc_type      IN     VARCHAR2)
RETURN BOOLEAN is

   L_program VARCHAR2(64) := 'SMR_WH_ASN_SQL.F_MAKE_ITEM_LOC';
   L_item_loc_exists varchar2(1);
   L_sample_item_loc number(10);
   L_new_wh          number(10);

   CURSOR c_item_loc_exists(I_item varchar2,
                            I_loc  number) is
   select 'x'
     from item_loc
    where item = I_item
      and loc = I_loc;

   CURSOR c_sample_item_loc(I_item varchar2) is
   select il.loc
     from item_loc il,
          store st
    where il.item = I_item
      and il.clear_ind = 'N'
      and st.store = il.loc
      and nvl(st.store_close_date,get_vdate + 1) > get_vdate
      and il.loc_type = 'S'
      and rownum < 2;

   cursor c_sample_item_loc_clear_store(I_item varchar2) is
   select location from (
   select rzl.location
     from item_loc il,
          rpm_zone rz,
          rpm_zone_location rzl
    where il.item = I_item
      and il.loc_type = 'S'
      and rz.zone_group_id = 2
      and il.loc = rzl.location
      and rz.zone_id = rzl.zone_id
    order by BASE_IND desc)
    where rownum < 2;

   CURSOR c_sample_item_loc_wh(I_item varchar2) is
   select loc
     from (select il.loc
             from item_loc il,
                  wh wh
            where il.item = I_item
              and wh.wh = il.loc
              and wh in (select wh from wh_attributes w where w.wh_type_code in('XD'))
              and il.loc_type = 'W'
              and rownum < 2
            )
   order by loc desc;

begin

   L_item_loc_exists := null;
   L_sample_item_loc := null;

   if I_loc_type = 'S' then
      -----------------------------------------------------------------------------------------------------------------------
      --If item_loc for store does not exist, create it.
      -----------------------------------------------------------------------------------------------------------------------

      open  c_item_loc_exists(I_item, I_loc);
      fetch c_item_loc_exists into L_item_loc_exists;
      close c_item_loc_exists;

      IF L_item_loc_exists IS NULL THEN

         open  c_sample_item_loc(I_item);
         fetch c_sample_item_loc into L_sample_item_loc;
         close c_sample_item_loc;

         if L_sample_item_loc is null then
            open  c_sample_item_loc_clear_store(I_item);
            fetch c_sample_item_loc_clear_store into L_sample_item_loc;
            close c_sample_item_loc_clear_store;
         end if;

         IF L_sample_item_loc IS NULL THEN
            O_error_message := 'No other valid store locations for item '||I_item||', store '||I_loc||' could be found.';
            return false;
         ELSE

            IF COPY_STORE_ITEM(L_sample_item_loc,
                               I_loc,
                               I_item,
                               O_error_message)  = FALSE THEN
                RETURN FALSE;
            END IF;

         END IF;

      END IF;

   else

      L_new_wh := I_loc;

      open  c_item_loc_exists(I_item, L_new_wh);
      fetch c_item_loc_exists into L_item_loc_exists;
      close c_item_loc_exists;

      IF L_item_loc_exists IS NULL THEN

         open  c_sample_item_loc_wh(I_item);
         fetch c_sample_item_loc_wh into L_sample_item_loc;
         close c_sample_item_loc_wh;

         IF L_sample_item_loc IS NULL THEN
            O_error_message := 'No other valid SDC locations for item '||I_item||', SDC '||I_loc||' could be found.';
            return false;
         ELSE

            IF COPY_STORE_ITEM(L_sample_item_loc,
                               L_new_wh,
                               I_item,
                               O_error_message)  = FALSE THEN
                RETURN FALSE;
            END IF;

         END IF;

      END IF;

   end if;

   return true;

exception
   when others then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
   return false;
end;

--------------------------------------------------------------------------------
-- Procedure Name: PUB_SHIPMENT
-- Purpose: called by ship_distro
--------------------------------------------------------------------------------
FUNCTION PUB_SHIPMENT(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                      I_to_loc_type   IN     SHIPMENT.TO_LOC_TYPE%TYPE,
                      I_shipment      IN     SHIPMENT.SHIPMENT%TYPE,
                      I_wf_ship_ind   IN     BOOLEAN DEFAULT FALSE)
RETURN BOOLEAN IS

   L_system_options_row   SYSTEM_OPTIONS%ROWTYPE;
   L_program              VARCHAR2(64) := 'SMR_SDC_944.PUB_SHIPMENT';
   L_to_loc               NUMBER;

BEGIN

   if I_shipment is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            'I_shipment',
                                            L_program,
                                            NULL);
      return FALSE;
   end if;

   if I_to_loc_type is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            'I_to_loc_type',
                                            L_program,
                                            NULL);
      return FALSE;
   end if;


   if SYSTEM_OPTIONS_SQL.GET_SYSTEM_OPTIONS(O_error_message,
                                            L_system_options_row) = FALSE then
      return FALSE;
   end if;

   -- Need to publish shipments in following scenarios
   -- 1. Destination is store, ship_rcv_store = 'N' and ship_rcv_wh = 'Y'
   -- 2. Destination is a wh, ship_rcv_wh = 'N' and ship_rcv_store = 'Y'
   -- These indicate that the shipment is to a store and store receiving is happening
   -- in a separate store system (e.g. SIM), or the shipment is to a warehouse and
   -- warehouse receiving is happening in a separate wh system (e.g. RWMS).
   -- Only in these cases, the shipment needs to be published to inform
   -- the receiving location of the coming shipment.
   -- 3. In case of WF Returns, shipments need to be published irrespctive of ship_rcv_wh
   --    and ship_rcv_store ind. So, check the input parameter to be TRUE and insert the record.

   if ((L_system_options_row.ship_rcv_store = 'N' and I_to_loc_type = 'S') and L_system_options_row.ship_rcv_wh    = 'Y') or
      ((L_system_options_row.ship_rcv_wh    = 'N' and I_to_loc_type = 'W') and L_system_options_row.ship_rcv_store = 'Y') or
      I_wf_ship_ind = TRUE then
      ---
      insert into shipment_pub_temp(shipment)
                             select I_shipment
                              from dual
                            where not exists (select 1 from
                                                shipment_pub_temp
                                              where shipment = I_shipment);
      ---
   end if;

   return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      return FALSE;

END PUB_SHIPMENT;
--------------------------------------------------------------------------------
-- Function Name: SHIP_DISTROS
-- Purpose: Same as in SHIPMENT_SQL, EXCEPT CAN SHIP WITH PAST SHIP DATE.
--------------------------------------------------------------------------------
FUNCTION SHIP_DISTROS(O_error_message   IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                      I_bol_no          IN       SMR_BOL_SHIPMENT.BOL_NO%TYPE)
   RETURN BOOLEAN IS

   L_program              VARCHAR2(50) := package_name||'.SHIP_DISTROS';
   L_from_loc             SMR_BOL_SHIPMENT.FROM_LOC%TYPE;
   L_to_loc               SMR_BOL_SHIPMENT.TO_LOC%TYPE;
   L_from_loc_orig        SMR_BOL_SHIPMENT.FROM_LOC%TYPE;
   L_to_loc_orig          SMR_BOL_SHIPMENT.TO_LOC%TYPE;
   L_bol_items_tbl        BOL_SQL.BOL_SHIPSKU_TBL;
   L_item_tbl             BOL_SQL.BOL_SHIPSKU_TBL;
   L_invalid_param        VARCHAR2(30) := NULL;
   L_date                 PERIOD.VDATE%TYPE := GET_VDATE;
   L_next_distro_no       BOL_SHIPSKU.DISTRO_NO%TYPE := -1;
   L_fin_inv_status       INV_STATUS_CODES.INV_STATUS%TYPE;
   L_shipment             SHIPMENT.SHIPMENT%TYPE;
   L_finisher             BOOLEAN := FALSE;
   L_finisher_name        PARTNER.PARTNER_DESC%TYPE := NULL;
   L_tsf_type             TSFHEAD.TSF_TYPE%TYPE;
   L_count                NUMBER;
   L_distro_no            BOL_SHIPSKU.DISTRO_NO%TYPE;
   L_distro_type          BOL_SHIPSKU.DISTRO_TYPE%TYPE;
   L_del_type             ORDCUST.DELIVER_TYPE%TYPE;
   L_finisher_loc_ind     VARCHAR2(1);
   L_finisher_entity_ind  VARCHAR2(1);
   L_bol_exist            BOOLEAN;
   L_ctr                  NUMBER;
   L_new_distro           VARCHAR2(1);
   L_tsfhead_info         V_TSFHEAD%ROWTYPE;

   cursor C_GET_BOL_SHIPMENT is
      select to_loc,
             to_loc_type,
             from_loc,
             from_loc_type,
             ship_date,
             no_boxes,
             courier,
             comments
        from SMR_BOL_SHIPMENT bol_sh
       where bol_sh.bol_no = I_bol_no;

   cursor C_GET_BOL_SHIP_SKU is
      select bol_sku.distro_no,
             thead.tsf_no check_distro,
             bol_sku.distro_type,
             bol_sku.carton,
             bol_sku.item,
             tsf.item check_item,
             bol_sku.ship_qty,
             tsf.tsf_qty - NVL(tsf.ship_qty, 0) available_qty,
             bol_sku.weight_expected,
             bol_sku.weight_expected_uom,
             NVL(tsf.inv_status,-1) inv_status,
             thead.tsf_type,
             thead.from_loc,
             thead.to_loc
        from SMR_BOL_SHIPSKU bol_sku,
             tsfdetail tsf,
             tsfhead thead
       where bol_sku.bol_no = I_bol_no
         and tsf.tsf_no(+) = bol_sku.distro_no
         and tsf.item(+) = bol_sku.item
         and tsf.tsf_qty > 0
         and thead.tsf_no (+) = bol_sku.distro_no
         and bol_sku.distro_type = 'T'
         and not exists (select 'x'
                           from v_tsfhead v
                          where v.tsf_no = thead.tsf_no
                            and v.child_tsf_no is NOT NULL
                            and v.leg_1_status = 'C'
                            and v.leg_2_status in ('A','S')
                            and v.finisher_type = 'I')
       union all
      select thead.child_tsf_no,
             thead.child_tsf_no check_distro,
             bol_sku.distro_type,
             bol_sku.carton,
             bol_sku.item,
             tsf.item check_item,
             bol_sku.ship_qty,
             tsf.tsf_qty - NVL(tsf.ship_qty, 0) available_qty,
             bol_sku.weight_expected,
             bol_sku.weight_expected_uom,
             NVL(tsf.inv_status,-1) inv_status,
             thead.tsf_type,
             thead.finisher,
             thead.to_loc
        from SMR_BOL_SHIPSKU bol_sku,
             tsfdetail tsf,
             v_tsfhead thead
       where bol_sku.bol_no = I_bol_no
         and tsf.item(+) = bol_sku.item
         and tsf.tsf_qty > 0
         and thead.tsf_no (+) = bol_sku.distro_no
         and thead.child_tsf_no = tsf.tsf_no
         and bol_sku.distro_type = 'T'
         and thead.leg_1_status = 'C'
         and thead.leg_2_status in ('A','S')
         and thead.finisher_type = 'I'
       union all
      select bol_sku.distro_no,
             ah.alloc_no check_distro,
             bol_sku.distro_type,
             bol_sku.carton,
             bol_sku.item ,
             decode(ah.alloc_no, ad.alloc_no, ah.item, NULL) check_item,
             bol_sku.ship_qty,
             ad.available_qty,
             bol_sku.weight_expected,
             bol_sku.weight_expected_uom,
             -1,
             NULL,
             NULL,
             NULL
        from (select bs.from_loc,
                     bs.to_loc,
                     bk.*
                from SMR_BOL_SHIPMENT bs,
                     SMR_BOL_SHIPSKU bk
               where bs.bol_no = I_bol_no
                 and bs.bol_no = bk.bol_no
                 and bk.distro_type = 'A') bol_sku,
             (select distinct ad.alloc_no,
                     ad.qty_allocated - ad.qty_transferred available_qty
                from SMR_BOL_SHIPMENT bs,
                     SMR_BOL_SHIPSKU bk,
                     wh,
                     alloc_detail ad
               where bs.bol_no = I_bol_no
                 and bk.bol_no = bs.bol_no
                 and bk.distro_no = ad.alloc_no
--                 and bs.to_loc = wh.physical_wh
                 and wh.wh = ad.to_loc
                 and ad.to_loc_type = 'W'
               union all
              select distinct ad.alloc_no,
                     ad.qty_allocated - ad.qty_transferred available_qty
                from SMR_BOL_SHIPMENT bs,
                     SMR_BOL_SHIPSKU bk,
                     alloc_detail ad
               where bs.bol_no = I_bol_no
                 and bk.bol_no = bs.bol_no
                 and bk.distro_no = ad.alloc_no
                 and bs.to_loc = ad.to_loc
                 and ad.to_loc_type = 'S') ad,
             (select distinct ah.alloc_no,
                     ah.item,
                     wh.physical_wh wh
                from SMR_BOL_SHIPMENT bs,
                     SMR_BOL_SHIPSKU bk,
                     wh,
                     alloc_header ah
               where bs.bol_no = I_bol_no
                 and bs.bol_no = bk.bol_no
--                 and bs.from_loc = wh.physical_wh
                 and bk.distro_no = ah.alloc_no
                 and bk.item = ah.item
                 and wh.wh = ah.wh) ah
       where bol_sku.distro_no = ah.alloc_no (+)
         and bol_sku.distro_no = ad.alloc_no (+)
       order by 1;

   cursor C_SHIPMENT is
      select shipment
        from shipment
       where bol_no = I_bol_no;

   TYPE tsf_rec IS RECORD(tsf_no         SHIPSKU.DISTRO_NO%TYPE,
                          tsf_type       TSFHEAD.TSF_TYPE%TYPE,
                          tsf_item       SHIPSKU.ITEM%TYPE);
   TYPE tsf_rec_item_tbl IS TABLE of tsf_rec index by binary_integer;
   L_ils_item_tbl      tsf_rec_item_tbl;

   TYPE bol_shipsku_tbl IS TABLE of c_get_bol_ship_sku%rowtype index by binary_integer;
   L_bol_shipsku_tbl   bol_shipsku_tbl;

   L_bol_shipment_rec  C_GET_BOL_SHIPMENT%ROWTYPE;

BEGIN
   --- Validate parameters
   if I_bol_no is NULL then
      L_invalid_param := 'I_bol_no';
   end if;
   ---
   if L_invalid_param is NOT NULL then
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            L_invalid_param,
                                            L_program,
                                            NULL);
      return FALSE;
   end if;

   open C_GET_BOL_SHIPMENT;
   fetch C_GET_BOL_SHIPMENT INTO L_bol_shipment_rec;

   if C_GET_BOL_SHIPMENT%NOTFOUND then
      close C_GET_BOL_SHIPMENT;
      O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                            NULL,
                                            L_program,
                                            NULL);
      return FALSE;
   end if;

   close C_GET_BOL_SHIPMENT;

   /* OLR V1.01 Delete START
   if (L_bol_shipment_rec.ship_date < L_date) then
      O_error_message := SQL_LIB.CREATE_MSG('SHIP_DATE_PASSED',
                                            SQLERRM,
                                            L_program,
                                            NULL);
      return FALSE;
   end if;
   -- OLR V1.01 Delete end */

   L_from_loc := L_bol_shipment_rec.from_loc;
   L_to_loc := L_bol_shipment_rec.to_loc;

   open C_GET_BOL_SHIP_SKU;
   fetch C_GET_BOL_SHIP_SKU BULK COLLECT into L_bol_shipsku_tbl;
   close C_GET_BOL_SHIP_SKU;

   if L_bol_shipsku_tbl.first is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                            NULL,
                                            L_program,
                                            NULL);
      return FALSE;
   end if;

   if BOL_SQL.PUT_BOL(O_error_message,
                      L_bol_exist,
                      I_bol_no,
                      L_from_loc,
                      L_to_loc,
                      L_bol_shipment_rec.ship_date,
                      NULL,
                      L_bol_shipment_rec.no_boxes,
                      L_bol_shipment_rec.courier,
                      NULL,
                      L_bol_shipment_rec.comments) = FALSE then

      return FALSE;
   end if;

/*   if L_bol_exist = TRUE then
      O_error_message := SQL_LIB.CREATE_MSG('DUP_BOL',
                                            I_bol_no,
                                            L_program,
                                            NULL);
        return FALSE;
   end if;*/
   ---
   L_from_loc_orig := L_from_loc;
   L_to_loc_orig := L_to_loc;
   ---
   for a in L_bol_shipsku_tbl.first..L_bol_shipsku_tbl.last loop

      if L_bol_shipsku_tbl(a).check_distro is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('INV_DISTRO_TSF_ALLOC',
                                               L_bol_shipsku_tbl(a).distro_no,
                                               L_program,
                                               NULL);
         return FALSE;
      end if;

      if L_bol_shipsku_tbl(a).check_item is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('INV_TSF_ALLOC_ITEM',
                                               L_bol_shipsku_tbl(a).distro_no,
                                               L_bol_shipsku_tbl(a).item,
                                               NULL);
         return FALSE;
      end if;

/*      if L_bol_shipsku_tbl(a).ship_qty > L_bol_shipsku_tbl(a).available_qty then

         O_error_message := SQL_LIB.CREATE_MSG('1INV_TSF_ALLOC_QTY',
                                               L_bol_shipsku_tbl(a).distro_no,
                                               L_bol_shipsku_tbl(a).item,
                                               NULL);
         return FALSE;
      end if;*/
      ---
      L_from_loc := L_from_loc_orig;
      L_to_loc := L_to_loc_orig;
      ---
      if L_bol_shipsku_tbl(a).distro_type = 'T' and
         L_bol_shipment_rec.from_loc_type = 'W' and
         L_new_distro = 'Y' then
         if WH_ATTRIB_SQL.CHECK_FINISHER(O_error_message,
                                         L_finisher,
                                         L_finisher_name,
                                         L_bol_shipsku_tbl(a).from_loc) = FALSE then
            return FALSE;
         end if;

         if L_finisher = TRUE then
            if INVADJ_SQL.GET_INV_STATUS(O_error_message,
                                         L_fin_inv_status,
                                         'ATS') = FALSE THEN
               return FALSE;
            end if;
         else
            L_fin_inv_status := NULL;
         end if;
      else
         L_fin_inv_status := NULL;
      end if;

      L_new_distro := 'N';
      L_count := L_bol_items_tbl.COUNT + 1;
      L_bol_items_tbl(L_count).distro_no              := L_bol_shipsku_tbl(a).distro_no;
      L_bol_items_tbl(L_count).item                   := L_bol_shipsku_tbl(a).item;
      L_bol_items_tbl(L_count).carton                 := L_bol_shipsku_tbl(a).carton;
      L_bol_items_tbl(L_count).ship_qty               := L_bol_shipsku_tbl(a).ship_qty;
      L_bol_items_tbl(L_count).weight                 := L_bol_shipsku_tbl(a).weight_expected;
      L_bol_items_tbl(L_count).weight_uom             := L_bol_shipsku_tbl(a).weight_expected_uom;
      L_bol_items_tbl(L_count).distro_type            := L_bol_shipsku_tbl(a).distro_type;
      L_bol_items_tbl(L_count).inv_status             := NVL(L_fin_inv_status, L_bol_shipsku_tbl(a).inv_status);

      if a < L_bol_shipsku_tbl.last then
         L_next_distro_no := L_bol_shipsku_tbl(a + 1).distro_no;
      end if;

      if a = L_bol_shipsku_tbl.last or (L_bol_shipsku_tbl(a).distro_no != L_next_distro_no) then
         L_new_distro := 'Y';
         --Pass the L_sellable table to BOL_SQL.PROCESS_ITEM
         if BOL_SQL.PROCESS_ITEM(O_error_message,
                                 L_item_tbl,  -- output table
                                 L_bol_items_tbl,
                                 L_from_loc,
                                 L_to_loc) = FALSE then
            return FALSE;
         end if;

         L_distro_no := L_item_tbl(1).distro_no;
         L_distro_type := L_item_tbl(1).distro_type;

         if L_distro_type = 'T' then
            if TRANSFER_SQL.GET_TSFHEAD_INFO(O_error_message,
                                             L_tsfhead_info,
                                             L_distro_no) = FALSE then
               return FALSE;
            end if;

            if L_tsfhead_info.finisher_type = 'I' and
               L_tsfhead_info.leg_1_status = 'C' and
               L_tsfhead_info.leg_2_status in ('A','S') then
               L_distro_no := L_tsfhead_info.child_tsf_no;
            end if;

            L_tsf_type := L_bol_shipsku_tbl(a).tsf_type;
            if BOL_SQL.PUT_TSF(O_error_message,
                               L_bol_shipment_rec.to_loc,
                               L_bol_shipment_rec.from_loc,
                               L_tsf_type,
                               L_del_type,
                               L_distro_no,
                               L_from_loc,
                               L_bol_shipment_rec.from_loc_type,
                               L_to_loc,
                               L_bol_shipment_rec.to_loc_type,
                               L_date,
                               NULL) = FALSE then
              return FALSE;
            end if;

            if TRANSFER_SQL.GET_FINISHER_INFO(O_error_message,
                                              L_finisher_loc_ind,
                                              L_finisher_entity_ind,
                                              L_distro_no)= FALSE THEN
               return FALSE;
            end if;

            for k in L_item_tbl.first..L_item_tbl.last LOOP
               if BOL_SQL.PUT_TSF_ITEM(O_error_message,
                                       L_item_tbl(k).distro_no,
                                       L_item_tbl(k).item,
                                       L_item_tbl(k).carton,
                                       L_item_tbl(k).ship_qty,
                                       L_item_tbl(k).weight,
                                       L_item_tbl(k).weight_uom,
                                       L_item_tbl(k).inv_status,
                                       L_from_loc,
                                       L_bol_shipment_rec.from_loc_type,
                                       L_to_loc,
                                       L_bol_shipment_rec.to_loc_type,
                                       L_bol_shipment_rec.to_loc,
                                       L_bol_shipment_rec.from_loc,
                                       L_tsf_type,
                                       L_del_type,
                                       'Y') = FALSE then
                  return FALSE;
               end if;

               if L_finisher = FALSE then
                  L_ctr := L_ils_item_tbl.COUNT + 1;
                  L_ils_item_tbl(L_ctr).tsf_no   := L_distro_no;
                  L_ils_item_tbl(L_ctr).tsf_type := L_tsf_type;
                  L_ils_item_tbl(L_ctr).tsf_item := L_item_tbl(k).item;
               end if;
            END LOOP;

            if BOL_SQL.PROCESS_TSF(O_error_message) = FALSE then
               return FALSE;
            end if;
         end if;

         if L_distro_type = 'A' then
            for k in L_item_tbl.first..L_item_tbl.last LOOP
               if BOL_SQL.PUT_ALLOC(O_error_message,
                                     L_item_tbl(k).item,
                                     L_bol_shipment_rec.from_loc,
                                     L_distro_no,
                                     L_from_loc, --physical location
                                     --952, --physical location
                                     L_item_tbl(k).item) = FALSE then
                  return FALSE;
               end if;

               if BOL_SQL.PUT_ALLOC_ITEM(O_error_message,
                                         L_item_tbl(k).distro_no,
                                         L_item_tbl(k).item,
                                         L_item_tbl(k).carton,
                                         L_item_tbl(k).ship_qty,
                                         L_item_tbl(k).weight,
                                         L_item_tbl(k).weight_uom,
                                         L_item_tbl(k).inv_status,
                                         L_to_loc,                         -- physical location
                                         L_bol_shipment_rec.to_loc_type,
                                         L_from_loc) = FALSE then          -- physical location
                  return FALSE;
               end if;
               
               if BOL_SQL.PROCESS_ALLOC(O_error_message) = FALSE then
                  return FALSE;
               end if;
            END LOOP;

         end if;

         L_item_tbl.delete;
         L_bol_items_tbl.delete;

      end if;
   END LOOP;

   if BOL_SQL.FLUSH_BOL_PROCESS(O_error_message) = FALSE then
      return FALSE;
   end if;

   open C_SHIPMENT;
   fetch C_SHIPMENT into L_shipment;
   close C_SHIPMENT;
   ---
   if L_ils_item_tbl.first is NOT NULL then
      if L_finisher_loc_ind is NOT NULL then
         for i in L_ils_item_tbl.first..L_ils_item_tbl.last LOOP
            if BOL_SQL.PUT_ILS_AV_RETAIL(O_error_message,
                                         L_bol_shipment_rec.to_loc,
                                         L_bol_shipment_rec.to_loc_type,
                                         L_ils_item_tbl(i).tsf_item,
                                         L_shipment,
                                         L_distro_no,
                                         L_ils_item_tbl(i).tsf_type,
                                         NULL) = FALSE then
               return FALSE;
            end if;
         END LOOP;
      end if;
   end if;

   if PUB_SHIPMENT(O_error_message,
                   L_bol_shipment_rec.to_loc_type,
                   L_shipment) = FALSE then
      return FALSE;
   end if;

   L_ils_item_tbl.delete;
   L_bol_shipsku_tbl.delete;

   return TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END SHIP_DISTROS;

--------------------------------------------------------------------------------
-- Procedure Name: F_LOAD_ASNS
-- Purpose: [Fill in purpose]
--------------------------------------------------------------------------------
FUNCTION F_LOAD_SHIPMENTS(O_error_message IN OUT VARCHAR2) RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_LOAD_SHIPMENTS';

   L_bol_no        VARCHAR2(30);
   L_BOL_COUNT     number(10);
   L_order_loc     ordloc.location%type;
   L_distro_doc_type         VARCHAR2(2)  ;
   L_distro_nbr              shipsku.distro_no%type;
   L_alloc_no_hdr       alloc_header.alloc_no%type;
   L_alloc_no_dtl       alloc_header.alloc_no%type;
   L_return_code varchar2(10);
   L_allocated_qty alloc_detail.qty_allocated%type;
   L_COMMENT   varchar2(100):='Auto Created based on XDoc shipment from WA';

   L_rtv_record      RTV_SQL.RTV_RECORD;
   L_details_rec     RTV_SQL.RTV_DETAIL_REC;
   L_rtv_detail_tbl  RTV_SQL.RTV_DETAIL_TBL;
   L_im_row_TBL      RTV_SQL.ITEM_MASTER_TBL := RTV_SQL.ITEM_MASTER_TBL();
   L_item_rec        ITEM_MASTER%ROWTYPE;
   L_dtl_count       NUMBER(10):= 0;
   L_vdate           PERIOD.VDATE%TYPE := GET_VDATE;
   L_code            INV_STATUS_CODES.INV_STATUS_CODE%TYPE;
   
   --get all receipt records from which we need to make shipments.
   CURSOR c_bol_shipment is
      SELECT DISTINCT
             s.BOL_NO,
             s.ship_date,
             s.from_loc,
             s.from_loc_type,
             s.to_loc,
             s.to_loc_type,
             s.carrier_code,
             '' comments,
             '' no_boxes
          FROM SMR_WH_ASN_STAGE s
         where s.ship_type in ('T','A')
         ORDER BY s.BOL_NO;

   --get all receipt records from which we need to make shipsku records .
  CURSOR c_bol_shipsku(I_bol_no varchar2) is
   SELECT ssd.order_no      order_no
         ,ssd.ship_type     distro_type
         ,decode(ssd.ship_type,'T',ssd.tsf_no, ssd.alloc_no)  distro_no
         ,ssd.item           item
         ,ssd.upc           ref_item
         ,ssd.carton        carton
         ,NVL(ssd.qty_shipped,0) ship_qty
         ,sysdate           last_update_datetime
     FROM SMR_WH_ASN_STAGE ssd
    WHERE ssd.bol_no = I_bol_no
      and ssd.ship_type in ('T','A')
   ORDER BY  1,3,4,6;

   --get all RTV Shipments .
   CURSOR c_rtv_head is
      SELECT *
          FROM rtv_head rh
         where rh.rtv_order_no in (select distinct ssd.order_no
                                     from SMR_WH_ASN_STAGE ssd
                                      where ssd.ship_type = 'R')
         ORDER BY rh.rtv_order_no;

   -- Get RTV shipment details 
   CURSOR c_rtv_details(L_order_no rtv_head.rtv_order_no%type) is
   select rtd.rtv_order_no,
          rtd.seq_no,
          rtd.item,
          rtd.shipment,
          rtd.inv_status,
          rtd.qty_requested,
          s.qty_shipped qty_returned,
          rtd.qty_cancelled,
          rtd.unit_cost,
          rtd.reason,
          rtd.publish_ind,
          rtd.restock_pct,
          rtd.original_unit_cost,
          rtd.updated_by_rms_ind
     from rtv_detail rtd,
          item_master im,
          SMR_WH_ASN_STAGE s
    where rtd.rtv_order_no = L_order_no
      and s.order_no = rtd.rtv_order_no
      and s.item = rtd.item 
      and rtd.item = im.item
      and (NVL(im.deposit_item_type,'E') != 'A')
      order by 1,3;

   cursor C_GET_INV_STATUS_CODE (status_in inv_status_codes.inv_status%TYPE) is
      select inv_status_code
        from inv_status_codes
       where inv_status = status_in;


  cursor c_order_loc(I_order_no number) is
  select location
    from ordhead oh
   where order_no = I_order_no;

  --get the allocation number associated with an order/item
   cursor c_alloc_header(I_order_no number,
                         I_item     varchar2)  is
   select alloc_no
     from alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.status in ('A','R','C')
    order by decode(ah.status,'A',1,'R',2,3);

   cursor c_alloc_header_details(I_order_no number,
                                 I_item     varchar2) is
   select alloc_method,
          order_type,
          release_date
     from (select alloc_method,
                  order_type,
                  release_date
             from alloc_header ah
            where order_no = I_order_no
              and item != I_item
              and ah.status in ('A','R','C')
            order by decode(ah.status,'A',1,'R',2,3))
    where rownum < 2;

   cursor c_alloc_detail(I_order_no number,
                         I_item     varchar2,
                         I_store   number) is
   select ad.alloc_no
     from alloc_detail ad,
          alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.status in ('A','R','C')
      and ad.alloc_no = ah.alloc_no
      and ad.to_loc = I_store;   


   cursor c_alloc_detail_details(I_order_no number) is
   select min(ad.in_store_date)  in_store_date,
          min(ad.non_scale_ind)  non_scale_ind,
          min(ad.rush_flag)      rush_flag
     from alloc_header ah,
          alloc_detail ad
    where ah.status in ('A','R','C')
      and ah.alloc_no = ad.alloc_no
      and ah.order_no = I_order_no;
      
   cursor c_get_alloc_qty(I_order_no number,
                           I_item     varchar2,
                           I_store   number) is
   select sum(s.qty_shipped)
     from SMR_WH_ASN_STAGE s
    where s.order_no = I_order_no
      and s.item = I_item
      and s.to_loc = I_store;   
      
  /* range Item Loc if it does not exists */    
   cursor c_add_item_loc is
     select distinct s.item ,sw.location ,sw.loc_type
       from SMR_WH_ASN_STAGE s ,
            (select store location ,'S' loc_type , null phy_wh
              from store
             union all
             select wh location , 'W' loc_type , wh.physical_wh phy_wh
               from WH
              where wh <> physical_wh) sw
      where s.to_loc = nvl(sw.phy_wh,sw.location)
        and not exists (select 1 
                          from item_loc il
                        where il.item = s.item
                          and il.loc = sw.location)
     union all
     select distinct s.item ,sw.location ,sw.loc_type
       from SMR_WH_ASN_STAGE s ,
            (select store location ,'S' loc_type , null phy_wh
              from store
             union all
             select wh location , 'W' loc_type , wh.physical_wh phy_wh
               from WH
              where wh <> physical_wh) sw
      where s.from_loc = nvl(sw.phy_wh,sw.location)
        and not exists (select 1 
                          from item_loc il
                        where il.item = s.item
                          and il.loc = sw.location);                                   

Begin

   IF API_LIBRARY.INIT(O_error_message) = FALSE THEN
      return false;
   END IF;

   --- Initialize globals, clear out any leftover OTB info/cache DML
   IF SMR_ORDER_RCV_SQL.INIT_PO_ASN_LOC_GROUP(O_error_message) = FALSE THEN
      return false;
   END IF;
   ---
   IF STOCK_ORDER_RCV_SQL.INIT_TSF_ALLOC_GROUP(O_error_message) = FALSE THEN
      return false;
   END IF;

   -- Range any Item loc(either from_loc or To_loc) that is not present in item_loc
   for c_rec in c_add_item_loc loop
     
      if F_make_item_loc(O_error_message,
                       c_rec.item,
                       c_rec.location ,
                       c_rec.loc_type) = false then
          return false;
      end if;          
   
   end loop;
   
   
     --create AND ship SDC ASNs
   for rec_shipment in c_bol_shipment loop

       L_bol_no :=  rec_shipment.bol_no;
       L_BOL_COUNT := 0;

       /* For each BOL from a WA one shiipment record will be created in RMS.
          WA creates seperate BOL records for evenry shipment from a warehouse to a
          particular destination(store) . */
       INSERT INTO SMR_BOL_SHIPMENT (bol_no
                                ,ship_date
                                ,from_loc
                                ,from_loc_type
                                ,to_loc
                                ,to_loc_type
                                ,courier
                                ,no_boxes
                                ,comments)
                         VALUES (L_bol_no
                                ,rec_shipment.ship_date
                                ,rec_shipment.from_loc
                                ,rec_shipment.from_loc_type
                                ,rec_shipment.to_loc
                                ,rec_shipment.to_loc_type
                                ,rec_shipment.carrier_code
                                ,rec_shipment.no_boxes
                                ,rec_shipment.comments);

      /* Process the shipment detail records to create Shipsku records in RMS
         A single shipment from WA to a destination can contain more that one allocation
         or transfer but will carry the same BOl no. */

      FOR rec_shipsku in c_bol_shipsku(L_bol_no) LOOP

         L_BOL_COUNT := L_BOL_COUNT + 1;

         L_distro_doc_type := NULL;
         L_distro_nbr := NULL;
         L_alloc_no_hdr := null;
         L_alloc_no_dtl := null;
         L_allocated_qty := 0;

         if rec_shipsku.distro_type = 'A' then   /* IF shipment is for allocation */

           L_distro_doc_type := rec_shipsku.distro_type;
           L_distro_nbr      := rec_shipsku.distro_no;

           /* For Xdoc PO the shipment for store allocations will not have the alloc_no.
              In such case the alloc_no will need to fetched from RMS .
              If the allocation for an Item or store is missing the record is
              created based on the shipment record  */
           if rec_shipsku.distro_no is null then

             OPEN c_alloc_header(rec_shipsku.order_no
                                 ,rec_shipsku.item);
             FETCH c_alloc_header INTO L_alloc_no_hdr;
             CLOSE c_alloc_header;

             open  c_order_loc(rec_shipsku.order_no);
             fetch c_order_loc into L_order_loc;
             close c_order_loc;

             L_distro_nbr := L_alloc_no_hdr;

             IF L_alloc_no_hdr is null then

                NEXT_ALLOC_NO(L_alloc_no_hdr,
                              L_return_code,
                              O_error_message);
                ---
                if L_return_code = 'FALSE' then
                   return FALSE;
                end if;

                L_distro_nbr := L_alloc_no_hdr;

                for rec in c_alloc_header_details(rec_shipsku.order_no
                                                 ,rec_shipsku.item) loop
                   INSERT INTO alloc_header(alloc_no,
                                            order_no,
                                            wh,
                                            item,
                                            status,
                                            alloc_desc,
                                            alloc_method,
                                            order_type,
                                            comment_desc,
                                            release_date)
                                    VALUES (L_alloc_no_hdr,
                                            rec_shipsku.order_no,
                                            L_order_loc,
                                            rec_shipsku.item,
                                            'A',
                                            L_COMMENT,
                                            rec.alloc_method,
                                            rec.order_type,
                                            L_COMMENT,
                                            rec.release_date);

                end loop;
             End if;

             open  c_alloc_detail(rec_shipsku.order_no,
                                  rec_shipsku.item,
                                  rec_shipment.to_loc);
             fetch c_alloc_detail into L_alloc_no_dtl;
             close c_alloc_detail;

             if L_alloc_no_dtl is null then

                open  c_alloc_header(rec_shipsku.order_no
                                      ,rec_shipsku.item);
                fetch c_alloc_header into L_alloc_no_dtl;
                close c_alloc_header;

                for rec in c_alloc_detail_details(rec_shipsku.order_no) loop

                 -- Get the total shipped  qty for the item and store 
                 -- to populate  qty_allocated     
                    open c_get_alloc_qty(rec_shipsku.order_no,
                                         rec_shipsku.item,
                                         rec_shipment.to_loc) ;
                    
                    fetch c_get_alloc_qty into L_allocated_qty;
                    
                    close c_get_alloc_qty;
                     
                    INSERT into alloc_detail
                                (alloc_no         ,
                                 to_loc           ,
                                 to_loc_type      ,
                                 qty_transferred  ,
                                 qty_allocated    ,
                                 qty_prescaled    ,
                                 qty_distro       ,
                                 qty_selected     ,
                                 qty_cancelled    ,
                                 qty_received     ,
                                 qty_reconciled   ,
                                 po_rcvd_qty      ,
                                 non_scale_ind    ,
                                 in_store_date    ,
                                 rush_flag        )
                         values (L_alloc_no_dtl,
                                 rec_shipment.to_loc,
                                 'S',
                                 null,
                                 L_allocated_qty ,
                                 L_allocated_qty ,
                                 null,
                                 null,
                                 null,
                                 null,
                                 null,
                                 null,
                                 rec.non_scale_ind,
                                 rec.IN_STORE_DATE,
                                 rec.rush_flag);
                end loop;

             end if;
           end if;
         else /* IF shipment is for Transfer */
           L_distro_doc_type := rec_shipsku.distro_type;
           L_distro_nbr := rec_shipsku.distro_no;
         end if;

         INSERT INTO SMR_BOL_SHIPSKU (BOL_NO
                                 ,DISTRO_NO
                                 ,DISTRO_TYPE
                                 ,ITEM
                                 ,REF_ITEM
                                 ,CARTON
                                 ,SHIP_QTY
                                 ,WEIGHT_EXPECTED
                                 ,WEIGHT_EXPECTED_UOM
                                 ,LAST_UPDATE_DATETIME)
                          VALUES (L_bol_no,
                                 L_distro_nbr,
                                 L_distro_doc_type
                                 --,rec_shipsku.distro_no
                                 --,rec_shipsku.distro_type
                                 ,rec_shipsku.item
                                 ,rec_shipsku.ref_item
                                 ,rec_shipsku.carton
                                 ,rec_shipsku.ship_qty
                                 ,NULL
                                 ,NULL
                                 ,rec_shipsku.LAST_UPDATE_DATETIME);


      END LOOP;

      /* Call the SHIP_DISTROS fuction to process the BOL and create the
         shipment records in RMS using base API's */
      IF SHIP_DISTROS(O_ERROR_MESSAGE,
                      L_bol_no) = FALSE THEN
        return false;
      END IF;

      delete from SMR_BOL_SHIPSKU where bol_no = L_bol_no;
      delete from SMR_BOL_SHIPMENT where bol_no = L_bol_no;

   END LOOP;

   /*  Process  RTV shipments if any int he staging table */
   FOR c_rec in c_rtv_head 
   loop 
     
     -- populate the RTV_SQL header record
     L_rtv_record.rtv_order_no  := c_rec.rtv_order_no;
     L_rtv_record.store := c_rec.store;
     L_rtv_record.wh := c_rec.wh;
     if c_rec.store = -1 then
        L_rtv_record.loc := c_rec.wh;
        L_rtv_record.loc_type := 'W';
     else
        L_rtv_record.loc := c_rec.store;
        L_rtv_record.loc_type := 'S';
     end if;
     L_rtv_record.ext_ref_no    := c_rec.ext_ref_no;
     L_rtv_record.ret_auth_num  := c_rec.ret_auth_num;
     L_rtv_record.supplier      := c_rec.supplier;
     L_rtv_record.ship_addr1    := c_rec.ship_to_add_1;
     L_rtv_record.ship_addr2    := c_rec.ship_to_add_2;
     L_rtv_record.ship_addr3    := c_rec.ship_to_add_3;
     L_rtv_record.state         := c_rec.state;
     L_rtv_record.city          := c_rec.ship_to_city;
     L_rtv_record.pcode         := c_rec.ship_to_pcode;
     L_rtv_record.country       := c_rec.ship_to_country_id;
     L_rtv_record.tran_date     := L_vdate;
     L_rtv_record.comments      := c_rec.comment_desc;
     L_rtv_record.total_order_amt_unit_based := c_rec.total_order_amt;
     L_rtv_record.total_order_amt_wgt_based := c_rec.total_order_amt;
     L_rtv_record.ret_courier   := c_rec.courier;
     L_rtv_record.restock_pct   := c_rec.restock_pct;
     L_rtv_record.restock_cost  := c_rec.restock_cost;

     open C_rtv_details(c_rec.rtv_order_no);
     fetch C_rtv_details bulk collect into L_rtv_detail_tbl;
     close C_rtv_details;       
 
   -- initialize detail collection
   L_details_rec.seq_nos := RTV_SQL.SEQ_NO_TBL();
   L_details_rec.items := ITEM_TBL();
   L_details_rec.returned_qtys := QTY_TBL();
   L_details_rec.from_disps := RTV_SQL.INV_STATUS_CODES_TBL();
   L_details_rec.unit_cost_exts := UNIT_COST_TBL();
   L_details_rec.unit_cost_supps := UNIT_COST_TBL();
   L_details_rec.unit_cost_locs := UNIT_COST_TBL();
   L_details_rec.reasons := RTV_SQL.REASON_TBL();
   L_details_rec.restock_pcts := RTV_SQL.RESTOCK_PCT_TBL();
   L_details_rec.inv_statuses := INV_STATUS_TBL();
   L_details_rec.mc_returned_qtys := QTY_TBL();
   L_details_rec.weights := RTV_SQL.WEIGHT_TBL();
   L_details_rec.weight_uoms := RTV_SQL.UOM_CLASS_TBL();
   L_details_rec.weight_cuoms := RTV_SQL.WEIGHT_TBL();
   L_details_rec.mc_weight_cuoms := RTV_SQL.WEIGHT_TBL();
   L_details_rec.cuoms := RTV_SQL.COST_UOM_TBL();
   L_im_row_tbl := RTV_SQL.ITEM_MASTER_TBL();
   
   for i in L_rtv_detail_tbl.FIRST .. L_rtv_detail_tbl.LAST 
   loop
        -- allocate memory
        L_details_rec.seq_nos.EXTEND;
        L_details_rec.items.EXTEND;
        L_details_rec.returned_qtys.EXTEND;
        L_details_rec.from_disps.EXTEND;
        L_details_rec.unit_cost_exts.EXTEND;
        L_details_rec.unit_cost_supps.EXTEND;
        L_details_rec.unit_cost_locs.EXTEND;
        L_details_rec.reasons.EXTEND;
        L_details_rec.restock_pcts.EXTEND;
        L_details_rec.inv_statuses.EXTEND;
        L_details_rec.mc_returned_qtys.EXTEND;
        L_details_rec.weights.EXTEND;
        L_details_rec.weight_uoms.EXTEND;
        L_details_rec.weight_cuoms.EXTEND;
        L_details_rec.mc_weight_cuoms.EXTEND;
        L_details_rec.cuoms.EXTEND;
        L_dtl_count := L_details_rec.items.COUNT;
        -- assign values
        L_details_rec.seq_nos(L_dtl_count)      := L_rtv_detail_tbl(i).seq_no;
        L_details_rec.items(L_dtl_count)        := L_rtv_detail_tbl(i).item;
        L_details_rec.inv_statuses(L_dtl_count) := L_rtv_detail_tbl(i).inv_status;
        L_details_rec.returned_qtys(L_dtl_count)  := NVL(L_rtv_detail_tbl(i).qty_returned, 0);
                                                     /*L_rtv_detail_tbl(i).qty_requested
                                                       - NVL(L_rtv_detail_tbl(i).qty_cancelled, 0)
                                                       - NVL(L_rtv_detail_tbl(i).qty_returned, 0);*/
        if L_details_rec.returned_qtys(L_dtl_count) < 0 then
           L_details_rec.returned_qtys(L_dtl_count) := 0;
        end if;
        if L_rtv_detail_tbl(i).inv_status is NULL then
           L_details_rec.from_disps(L_dtl_count) := 'ATS';
        else
           open C_GET_INV_STATUS_CODE (L_rtv_detail_tbl(i).inv_status);
           fetch C_GET_INV_STATUS_CODE into L_code;
           close C_GET_INV_STATUS_CODE;
           L_details_rec.from_disps(L_dtl_count) := L_code;
        end if;
        L_details_rec.unit_cost_supps(L_dtl_count) := L_rtv_detail_tbl(i).unit_cost; -- unit cost on RTV is in supplier currency
        L_details_rec.reasons(L_dtl_count)        := L_rtv_detail_tbl(i).reason;
        L_details_rec.unit_cost_exts(L_dtl_count) := NULL;  
        L_details_rec.unit_cost_locs(L_dtl_count) := NULL;  
        L_details_rec.weights(L_dtl_count)        := NULL;  
        L_details_rec.weight_uoms(L_dtl_count)    := NULL;  
        -- get the item_master row
        if ITEM_ATTRIB_SQL.GET_ITEM_MASTER(O_error_message,
                                           L_item_rec,
                                           L_rtv_detail_tbl(i).item) = FALSE then
           return FALSE;
        end if;
        L_im_row_tbl.EXTEND;
        L_im_row_tbl(L_dtl_count) := L_item_rec;
     end loop;
    
     L_rtv_record.detail_tbl := L_details_rec;
     L_rtv_record.im_row_tbl := L_im_row_tbl;

     -- ship the RTV
     if RTV_SQL.APPLY_PROCESS(O_error_message,
                              L_rtv_record) = FALSE then
        return FALSE;
     end if;   
   
   end loop;


   RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_LOAD_SHIPMENTS;


-----------------------------------------------------------------------------------
--PUBLIC FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------

------------------------------------------------------------------
-- FUNCTION: F_INIT_WH_SHIPMENTS
-- Purpose:  LOAD WH shipment into SMR_WH_ASN_STAGE from Integration Tables
------------------------------------------------------------------
FUNCTION F_INIT_WH_SHIPMENTS(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_INIT_WH_SHIPMENTS';

   cursor c_group_id is
      select distinct q.GROUP_ID 
       from SMR_RMS_INT_QUEUE q,
            SMR_RMS_INT_TYPE t
     where q.interface_id = t.interface_id
       and q.status = 'N'
       and t.interface_name = 'WH_SHIPMENTS' 
       and exists (select 1 
                     from SMR_RMS_INT_SHIPPING_IMP s
                    where s.group_id = q.group_id
                      and s.record_id is null) ;
BEGIN

   delete from SMR_WH_ASN_STAGE;

   delete from smr_wh_asn_errors;

   -- Below Logic is to populate the record Id in the Interface table as 
   -- ISB does not populate the record id;
    for c_rec in c_group_id   
    loop
      merge into SMR_RMS_INT_SHIPPING_IMP s
        using (select group_id , 
                      rowid s_rowid,
                      row_number() over(partition by group_id order by BOL_NO ,FROM_LOC ,TO_LOC, ALLOC_NO, 
                                                  ORDER_NO, ALLOC_NO, TSF_NO, CARTON, item ) record_id
                 from SMR_RMS_INT_SHIPPING_IMP si 
               where group_id = c_rec.group_id) sr
        on (s.rowid = sr.s_rowid)
      when matched then update set s.record_id = sr.record_id;            

    end loop;  


   insert into SMR_WH_ASN_STAGE (record_id, group_id, BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
                          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE,
                          ORDER_NO, ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED)
   select s.record_id, s.group_id, BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE,
          ORDER_NO, ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED
   from  SMR_RMS_INT_SHIPPING_IMP s,
         SMR_RMS_INT_QUEUE q,
         SMR_RMS_INT_TYPE t
   where s.group_id = q.group_id
     and q.interface_id = t.interface_id
     and q.status = 'N'
     and t.interface_name = 'WH_SHIPMENTS';

  update SMR_RMS_INT_QUEUE s set status = 'P',
                               PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_WH_ASN_STAGE a);


--  Commit;

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_INIT_WH_SHIPMENTS;

--------------------------------------------------------------------------------
-- Procedure Name: F_PROCESS_WH_ASN
-- Purpose: Process Data in smr_wh_asn
--------------------------------------------------------------------------------
FUNCTION F_PROCESS_WH_SHIPMENTS(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_WH_SHIPMENTS';

BEGIN

   sho(L_program);

   --set this so that trigger will not fire for the session running this program
   SMR_SDC_944.pv_alloc_no := -1;

  /* for XDoc shipments to Store the alloc_no needs to be updated based ont he data from RMS*/
   merge into SMR_WH_ASN_STAGE swa
       using(select distinct ah.alloc_no , ah.order_no,
                    wh.physical_wh ,ah.item ,ad.to_loc
               from alloc_header ah,
                    alloc_detail ad ,
                    SMR_WH_ASN_STAGE s,
                    wh
              where ah.order_no = s.order_no
                and ah.item = s.item 
                and ah.alloc_no = ad.alloc_no
                and ad.to_loc = s.to_loc
                and s.ship_type = 'A'
                and ah.wh = wh.wh) sw
      on ( swa.order_no = sw.order_no
          and swa.from_loc = sw.physical_wh
          and swa.to_loc = sw.to_loc
          and swa.item = sw.item
          and swa.ship_type = 'A'
          and swa.order_no is not null)
      when matched then update set swa.alloc_no = sw.alloc_no;


   IF F_VALIDATE_SHIPMENTS(O_error_message) = FALSE THEN
      return false;
   END IF;

   IF F_LOAD_SHIPMENTS(O_error_message) = false then
     RETURN FALSE;
   END IF;

   sho('=========================================================================================================');
   sho('Delete smr_wh_asn');
   sho('=========================================================================================================');

--   DELETE FROM smr_wh_asn;

   --set this so that trigger will not fire for the session running this program
   SMR_SDC_944.pv_alloc_no := null;

   sho('=========================================================================================================');
   sho('DONE');
   sho('=========================================================================================================');

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_PROCESS_WH_SHIPMENTS;
------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA LOADED INTO TABLE smr_wh_asn
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_SHIPMENTS(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_SHIPMENTS';

BEGIN

   sho(L_program);

   --Invalid Bol No
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Bol No', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.bol_no is null;


   --Invalid Shiment Date
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Shiment Date', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.ship_date is null or swa.ship_date > sysdate;

   --Invalid from Location
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid From Location', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.from_loc is null or swa.from_loc_type is null or
          (swa.from_loc,swa.from_loc_type)
                          not in (select store ,'S' from store s
                                 union
                                  select wh.physical_wh,'W' from wh , wh_attributes w
                                    where wh.wh = w.wh
                                     and w.wh_type_code in ('XD','PA'));


   --Invalid To Location
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid To Location', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.ship_type in ('T','A')
      and (swa.to_loc is null or swa.to_loc_type is null or
          (swa.to_loc,swa.to_loc_type)
                          not in (select store ,'S' from store s
                                 union
                                  select wh.physical_wh,'W' from wh , wh_attributes w
                                    where wh.wh = w.wh
                                     and w.wh_type_code in ('XD','PA')));


   --Invalid Order
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Order', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.order_no is not null
      and swa.ship_type in ('T','A')
      and NOT EXISTS (SELECT 'X' FROM ordhead oh
                          WHERE oh.order_no = swa.order_no and oh.status in ('A','C'));

   --Invalid RTV Order
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid RTV Order', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.ship_type in ('R')
      and NOT EXISTS (SELECT 'X' FROM rtv_head rh
                          WHERE rh.rtv_order_no = swa.order_no);



   --Invalid Shipment type
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Shipment Type', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE nvl(swa.ship_type,' ') not in ('A','T','R');


   --Invalid Alloc No
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Alloc No', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.ship_type = 'A'
      and swa.order_no is null
      and not exists (select 1
                       from alloc_header a
                      where nvl(a.order_no,-1) = nvl(swa.order_no,-1)
                        and a.alloc_no = swa.alloc_no
                        and a.status in ('A','R','C'));

   --Invalid Tsf No
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Transfer No', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.ship_type = 'T'
      and not exists (select 1
                       from tsfhead t
                      where t.tsf_no = swa.tsf_no
                        and t.status in ('A','S','C'));

   --Invalid Carton
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Carton', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE length(nvl(carton,' ')) != 20
      and swa.ship_type in ('T','A');

   --Invalid Item
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Item', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE (swa.item is null
      or NOT EXISTS (SELECT 'X' FROM item_master im
                          WHERE im.item = swa.item
                            and im.status = 'A'));

   --Invalid Shipped Qty
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Invalid Shipped Qty', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE  nvl(swa.qty_shipped, 0) <= 0;


   --Carton Already Shipped
   INSERT INTO smr_wh_asn_errors
               (RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
               TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
               ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,ERROR_MSG, ERROR_DATE)
   SELECT RECORD_ID,GROUP_ID,BOL_NO, SHIP_DATE, FROM_LOC, FROM_LOC_TYPE,
          TO_LOC, TO_LOC_TYPE, SHIPMENT, CARRIER_CODE, SHIP_TYPE, ORDER_NO,
          ALLOC_NO, TSF_NO, CARTON, item, UPC, QTY_SHIPPED,
          'Carton Already Shipped', sysdate
     FROM SMR_WH_ASN_STAGE swa
    WHERE swa.ship_type in ('T','A')
      and exists (select 1
                    from shipment sh ,
                         shipsku sk
                   where sh.shipment = sk.shipment
                     and sk.carton = swa.carton
                     and sh.from_loc  = swa.from_loc
                     and sh.to_loc  = swa.to_loc
                     and sk.item = swa.item
                     and sh.order_no is null
                     and sh.status_code <> 'C');


  -- Insert into Error Table
   INSERT INTO SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, s.group_id, s.record_id,
          s.error_msg, sysdate
     FROM smr_wh_asn_errors s ;



  update SMR_RMS_INT_SHIPPING_IMP s set ERROR_IND = 'Y' ,
                                    PROCESSED_IND = 'Y',
                                 PROCESSED_DATETIME = sysdate
     where s.bol_no is null
     or exists (select 1
                     from smr_wh_asn_errors se
                   where se.bol_no = s.bol_no);

   -- Remove records with Error

   delete from  SMR_WH_ASN_STAGE swa
     where swa.bol_no is null
     or exists (select 1
                     from smr_wh_asn_errors se
                   where se.bol_no = swa.bol_no);


   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_VALIDATE_SHIPMENTS;

------------------------------------------------------------------
-- FUNCTION: F_FINISH_PROCESS
-- Purpose:  Finish processing WH shipments and update Integration Tables
------------------------------------------------------------------
FUNCTION F_FINISH_PROCESS(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_INIT_WH_SHIPMENTS';

BEGIN

  update SMR_RMS_INT_QUEUE s set status = 'E',
                                 PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from smr_wh_asn_errors a);

  update SMR_RMS_INT_QUEUE s set status = 'C',
                               PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_WH_ASN_STAGE a) and status <> 'E';


  update SMR_RMS_INT_SHIPPING_IMP s set PROCESSED_IND = 'Y',
                                 PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_WH_ASN_STAGE a)
      and nvl(s.processed_ind,'N') = 'N' and nvl(s.error_ind,'N') = 'N';

 -- Commit;

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_FINISH_PROCESS;

END SMR_WH_SHIP_SQL;
/