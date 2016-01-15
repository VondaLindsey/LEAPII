CREATE OR REPLACE PACKAGE BODY SMR_WH_ADJ_SQL IS
-- Module Name: SMR_WH_ADJ_SQL
-- Description: This package will be used to create WA shipments to stores.
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    15-Mar-15  Murali              LEAP 2 Development
--------------------------------------------------------------------------------
/*
Description:
   The package SMR_WH_ADJ_SQL is used to create Inventory and reciept adjustment from WA into RMS table.
   The package consists of following Main Functions
   F_INIT_WH_ADJ - Function used to load data from Interface table into ASN staging tables
   F_VALIDATE_ADJ - Function used to validate the adjustment data from WA
   F_LOAD_ADJ - Function to load the adjustments into RMS based on the Inventory Status . In case of the Reciept Adustment the 
       adjustments are loaded into staging table in case of any invoice exists for the Order and has been attempted to Match.
   F_FINISH_PROCESS - Update the status in the Interface Queue Table.	   

Algorithm
   - Call Function F_INIT_WH_ADJ to load the Staging table SMR_RMS_ADJ_STAGE from the Interface tables
   - Call function F_VALIDATE_ADJ to validate the Adjustment data from WA. Insert all errors into SMR_RMS_INT_ERROR table.
   - Call function F_LOAD_ADJ to load adjustment data into RMS
   - Based on the adjstment reason code create a Inventory adjusmtent or a Receipt Adjustment in RMS
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
-- Procedure Name: F_LOAD_ASNS
-- Purpose: [Fill in purpose]
--------------------------------------------------------------------------------
FUNCTION F_LOAD_ADJ(O_error_message IN OUT VARCHAR2) RETURN boolean IS

   L_program VARCHAR2(61) := package_name || '.F_LOAD_ADJ';

   L_location        number(10);
   L_tran_code       tran_data_a.tran_code%type;
   L_loc_type        varchar2(1) := 'W';
   L_found           boolean:=true;
   L_total           item_loc_soh.stock_on_hand%type;
   L_stock_on_hand   item_loc_soh.stock_on_hand%type;
   L_exists          varchar2(1) := 'N';
   L_shipment        SHIPMENT.SHIPMENT%TYPE;
   L_asn             SHIPMENT.ASN%TYPE;
   L_seq_no          SHIPSKU.SEQ_NO%TYPE;
   L_rua_wh_auto_process varchar2(1);
   L_wh_type_code     wh_attributes.wh_type_code%type;
   L_store_shipment          varchar2(1);
   L_inv_status      INV_ADJ.Inv_Status%TYPE;

   --get all receipt records from which we need to make shipments.
   CURSOR c_adjustments is
      SELECT sas.record_id,
             sas.group_id,
             adj_id,
             sas.WH,
             sas.location,
             ITEM,
             QTY_ADJUSTED,
             CARTON_ID,
             sas.wa_tran_code wms_reason_code,
             rc.reason_code rms_reason_code,
             rc.inv_status,
             TRAN_DATE,
             ORDER_NO,
             sas.user_id,
             sas.rowid L_rowid
          FROM SMR_RMS_ADJ_STAGE SAS,
              SMR_ADJ_REASON_CODE rc
         where sas.wa_tran_code= rc.wms_reason_code
         ORDER BY SAS.Group_Id,SAS.Record_Id;

     cursor c_rua_wh_auto_process is
     select s.rua_wh_auto_process
       from smr_system_options s;

   CURSOR c_matched_status(C_order_no ordhead.order_no%type) is
      SELECT  'Y'
        from im_doc_head idh
      where idh.order_no = C_order_no
       and idh.status in ('URMTCH','POSTED','MURMTH','MTCH' );

   CURSOR c_get_shipment(C_order_no ordhead.order_no%type,
                         c_carton   carton.carton%type,
                         C_item     item_master.item%type) is
    select distinct sh.shipment , sh.asn ,sk.seq_no
      from shipment sh,
           shipsku sk
     where sh.shipment = sk.shipment
       and sh.order_no = C_order_no
       and sk.carton = C_carton
       and sk.item = C_item;


    Cursor C_get_wh_type(C_order_no ordhead.order_no%type,
                         C_item     item_master.item%type, 
                         C_wh     number)  is
      select wh_type_code
        from wh ,
             wh_attributes w
       where w.wh = wh.wh 
         and wh.physical_wh = C_wh
         and exists (select 1 from ordloc ol 
                      where ol.order_no = C_order_no
                        and ol.item = C_item
                        and ol.location = w.wh);
     
    --In case of Xdoc PO check if shipment exists for carton from WH to store.
    --If an shipment exists for store and is received at store the adjustment
    -- need to be created for wh to store shipment as well .
    -- Below Cusrsor checks if the carton has been shipped to the store
    cursor c_wh_to_store_ship(C_wh     number,
                              C_carton varchar2) is
    select 'X'
      from shipment sh,
           shipsku  sk
     where sh.shipment = sk.shipment
       and sh.from_loc = C_wh
       and sh.to_loc <> C_wh
       and sk.qty_received > 0 
       and sk.carton = C_carton;

Begin

  -- Update The staging table with actual virtual location for creating adjustments

  -- In case of Reciept and inventory Adjustmments with Order No get location from actual Order
  update SMR_RMS_ADJ_STAGE s
         set location = (select oh.location
                           from ordhead oh
                              where oh.order_no = s.order_no)
     where order_no is not null;

 --    s.reason_code in (select WMS_REASON_CODE from SMR_ADJ_REASON_CODE s where s.inv_status in (2));

  -- In case of  inventory adjustment with Null Order no  always use put away wh location
  update SMR_RMS_ADJ_STAGE s
         set location = (select WH
                           from wh
                         where wh.physical_wh = s.wh
                           and wh.wh in (select w.wh
                                           from wh_attributes w
                                         where  w.wh_type_code in ('PA')))
     where order_no is null;

   open c_rua_wh_auto_process;

   fetch c_rua_wh_auto_process into L_rua_wh_auto_process;

   Close c_rua_wh_auto_process;


   for rec_adj in c_adjustments 
   loop

     L_wh_type_code := null;
     L_exists  := null;
     L_store_shipment := null;

     if rec_adj.inv_status in (0,3) then

       ---
       if rec_adj.inv_status = 3 then
          L_inv_status := rec_adj.inv_status;
       else
         L_inv_status := null;
       end if;   
       if INVADJ_SQL.INSERT_INV_ADJ(O_error_message,
                                    rec_adj.item,
                                    L_inv_status,
                                    L_loc_type,
                                    rec_adj.location,
                                    rec_adj.qty_adjusted,
                                    rec_adj.rms_reason_code,
                                    rec_adj.user_id,
                                    rec_adj.tran_date) = FALSE then
          return FALSE;
       end if;
       ---
       if rec_adj.inv_status = 3 then
          L_tran_code := 25;

          -- ADJ_UNAVAILABLE inserts, deletes or updates inv_status_qty depending on the situation
          ---
          if INVADJ_SQL.ADJ_UNAVAILABLE (rec_adj.item,
                                         rec_adj.inv_status,
                                         L_loc_type,
                                         rec_adj.location,
                                         rec_adj.qty_adjusted,
                                         O_error_message,
                                         L_found) = FALSE then
              return false;
          end if;
          ---
          if L_found = FALSE then
            O_error_message := SQL_LIB.CREATE_MSG('NEGATIVE_ADJ_QTY',
                                                  NULL,
                                                  L_program,
                                                  NULL);
             return FALSE;
          end if;
          ---
          -- ADJ_TRAN_DATA calls stkledgr_sql.tran_data_inserts which inserts into tran_data
          --adding in fetch of system ind here to see if it helpd the problem.

          if INVADJ_SQL.ADJ_TRAN_DATA (rec_adj.item,
                                       L_loc_type,
                                       rec_adj.location,
                                       rec_adj.qty_adjusted,
                                       'INVADJST',
                                       rec_adj.tran_date,
                                       L_tran_code,
                                       rec_adj.rms_reason_code,
                                       rec_adj.inv_status,
                                       NULL,
                                       NULL,
                                       O_error_message,
                                       L_found) = FALSE then
              return false;
          end if;
          ---
          if INVADJ_SQL.GET_UNAVAILABLE(rec_adj.item,
                                        L_loc_type,
                                        rec_adj.location,
                                        L_total,
                                        O_error_message,
                                        L_found) = FALSE then
              return false;
         end if;
         ---
         if INVADJ_VALIDATE_SQL.ITEM_LOC_EXIST (rec_adj.item,
                                                rec_adj.location,
                                                L_loc_type,
                                                '0',
                                                L_stock_on_hand,
                                                O_error_message,
                                                L_found) = FALSE then
             return false;
         end if;
          ---

         if L_total > L_stock_on_hand then
            O_error_message := SQL_LIB.CREATE_MSG('TOTAL_UNAVAILABLE',
                                                  NULL,
                                                  L_program,
                                                  NULL);
             return FALSE;
         end if;
          ---
      else
          -- ADJ_STOCK_ON_HAND item_loc_stock_on_hand
         if INVADJ_SQL.ADJ_STOCK_ON_HAND (rec_adj.item,
                                          L_loc_type,
                                          rec_adj.location,
                                          rec_adj.qty_adjusted,
                                          O_error_message,
                                          L_found) = FALSE then
             return false;
         end if;
          ---
          L_tran_code := 22;
          ---
          if INVADJ_SQL.ADJ_TRAN_DATA (rec_adj.item,
                                       L_loc_type,
                                       rec_adj.location,
                                       rec_adj.qty_adjusted,
                                       'INVADJST',
                                       rec_adj.tran_date,
                                       L_tran_code,
                                       rec_adj.rms_reason_code,
                                       NULL,
                                       NULL,
                                       NULL,
                                       O_error_message,
                                       L_found) = FALSE then
              return false;
          end if;
          ---
       end if;
   elsif rec_adj.inv_status in (5) then

       open c_matched_status(rec_adj.order_no);

       fetch c_matched_status into L_exists;

       close  c_matched_status;

       if  L_exists = 'Y'  and L_rua_wh_auto_process = 'N' then

         insert into SMR_RMS_WH_RUA (ADJ_ID ,WA_TRAN_CODE ,WH, ITEM, QTY_ADJUSTED,
                                UOM,  CARTON_ID, REASON_CODE, TRAN_DATE,
                              ORDER_NO,USER_ID,SMRT_MARK_FOR,REASON_DESC,
                              location,processed_ind,processed_datetime)
           select ADJ_ID ,WA_TRAN_CODE, WH, ITEM, QTY_ADJUSTED,
                  UOM,  CARTON_ID, REASON_CODE, TRAN_DATE,
                  ORDER_NO, USER_ID, SMRT_MARK_FOR, REASON_DESC ,
                  location, 'NP', sysdate
             from SMR_RMS_ADJ_STAGE s
           where s.rowid = rec_adj.l_rowid;

       else

         open c_get_shipment(rec_adj.order_no,
                             rec_adj.carton_id,
                             rec_adj.item);

         fetch c_get_shipment into L_shipment, L_asn ,L_seq_no;

         close   c_get_shipment;

         -- adjust the shipment. ReIM RUA will not create new shipments. It will update
         -- the existing shipment. Other RUA may create child shipments if needed.

         if ORDER_RCV_SQL.PO_LINE_ITEM_ONLINE(O_error_message,
                                              rec_adj.wh,           -- loc
                                              rec_adj.order_no,     -- order_no
                                              rec_adj.item,         -- item
                                              rec_adj.qty_adjusted, -- qty
                                              'A'  ,                -- tran_type
                                              rec_adj.tran_date,    -- tran_date
                                              rec_adj.adj_id,       -- receipt_number
                                              L_asn,                 -- asn
                                              NULL,                 -- appt
                                              rec_adj.carton_id,    -- carton
                                              NULL,                 -- distro_type
                                              NULL,                 -- distro_number
                                              NULL,                 -- destination
                                              NULL,                 -- disp
                                              NULL,                 -- unit_cost
                                              'Y',                  -- online_ind
                                              L_shipment,
                                              NULL,                 --adjusted_wt,
                                              NULL) = FALSE then    -- WT UOM
            return FALSE;
         end if;

         insert into SMR_RMS_WH_RUA (ADJ_ID ,WA_TRAN_CODE ,WH, ITEM, QTY_ADJUSTED,
                                UOM,  CARTON_ID, REASON_CODE, TRAN_DATE,
                              ORDER_NO,USER_ID,SMRT_MARK_FOR,REASON_DESC,
                              location,processed_ind,processed_datetime)
           select ADJ_ID ,WA_TRAN_CODE, WH, ITEM, QTY_ADJUSTED,
                  UOM,  CARTON_ID, REASON_CODE, TRAN_DATE,
                  ORDER_NO, USER_ID, SMRT_MARK_FOR, REASON_DESC ,
                  location, 'AP', sysdate
             from SMR_RMS_ADJ_STAGE s
           where s.rowid = rec_adj.l_rowid;
           
          open C_get_wh_type(rec_adj.order_no,
                             rec_adj.item,
                             rec_adj.wh) ;
          fetch C_get_wh_type into L_wh_type_code;
          close C_get_wh_type;
          
          if L_wh_type_code = 'XD' then  
              open c_wh_to_store_ship(rec_adj.wh,
                                      rec_adj.carton_id);
              fetch c_wh_to_store_ship into L_store_shipment;
              
              close c_wh_to_store_ship;
              /* If Wh to store shipment exists for Xdoc Orders then 
                 Call the custom fuction to adjust the store shipment */
              if L_store_shipment is not null then
                if SMR_CUSTOM_RCA.F_SAVE_ADJUSTMENT(O_error_message,
                                                    rec_adj.wh,
                                                    L_shipment,
                                                    rec_adj.item,
                                                    L_seq_no,
                                                    rec_adj.qty_adjusted,
                                                    rec_adj.carton_id ) = false then
                   return FALSE;
                End if;                
              
              end if;  /* if L_store_shipment is not null then  */                      
          
          end if; /* if L_wh_type_code = 'XD' then */
       end if;


    end if;


   END LOOP;

   RETURN TRUE;

EXCEPTION
  WHEN OTHERS THEN
    O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                          SQLERRM,
                                          L_program,
                                          TO_CHAR(SQLCODE));
    RETURN FALSE;
END F_LOAD_ADJ;


-----------------------------------------------------------------------------------
--PUBLIC FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------

------------------------------------------------------------------
-- FUNCTION: F_INIT_WH_ADJ
-- Purpose:  LOAD WH shipment into SMR_WH_ASN from Integration Tables
------------------------------------------------------------------
FUNCTION F_INIT_WH_ADJ(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_INIT_WH_ADJ';

   cursor c_group_id is
      select distinct q.GROUP_ID 
       from SMR_RMS_INT_QUEUE q,
            SMR_RMS_INT_TYPE t
     where q.interface_id = t.interface_id
       and q.status = 'N'
       and t.interface_name = 'WH_ADJUSTMENTS' 
       and exists (select 1 
                     from SMR_RMS_INT_ADJUSTMENTS_IMP s
                    where s.group_id = q.group_id
                      and s.record_id is null) ;
BEGIN

   delete from SMR_RMS_ADJ_STAGE;

   -- Below Logic is to populate the record Id in the Interface table as 
   -- ISB does not populate the record id;
    for c_rec in c_group_id   
    loop
      merge into SMR_RMS_INT_ADJUSTMENTS_IMP s
        using (select group_id , 
                      rowid s_rowid,
                      row_number() over(partition by group_id order by WH ,WA_TRAN_CODE ,ITEM, CARTON, 
                                                  REASON_CODE, TRAN_DATE ,ORDER_NO,USER_ID) record_id
                 from SMR_RMS_INT_ADJUSTMENTS_IMP si 
               where group_id = c_rec.group_id) sr
        on (s.rowid = sr.s_rowid)
      when matched then update set s.record_id = sr.record_id;            

    end loop;  
    
   insert into SMR_RMS_ADJ_STAGE (RECORD_ID, GROUP_ID, ADJ_ID ,WA_TRAN_CODE ,WH, ITEM,
                           QTY_ADJUSTED, UOM,  CARTON_ID, REASON_CODE, TRAN_DATE,
                          ORDER_NO,USER_ID,SMRT_MARK_FOR,REASON_DESC)
   select s.record_id, s.group_id,  ADJ_ID ,WA_TRAN_CODE, WH, ITEM,
           QTY_ADJUSTED, UOM,  CARTON, REASON_CODE, TRAN_DATE,
           ORDER_NO,USER_ID,SMRT_MARK_FOR,REASON_DESC
   from  SMR_RMS_INT_ADJUSTMENTS_IMP s,
         SMR_RMS_INT_QUEUE q,
         SMR_RMS_INT_TYPE t
   where s.group_id = q.group_id
     and q.interface_id = t.interface_id
     and q.status = 'N'
     and t.interface_name = 'WH_ADJUSTMENTS';

  -- Update Order No to 6 digit if PO was created for Wh stocked .
  update SMR_RMS_ADJ_STAGE s
     set order_no = substr(order_no,1,6)       
      where not exists (select 1
                   from ordhead oh where oh.order_no = s.order_no)
        and exists (select 1
                   from ordhead oh 
                  where oh.order_no = substr(s.order_no,1,6)
                    and oh.location in (select wh from wh_attributes w where w.wh_type_code = 'PA'))
        and order_no is not null; 
          
  update SMR_RMS_INT_QUEUE s set status = 'P',
                               PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_RMS_ADJ_STAGE a);


 -- Commit;

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_INIT_WH_ADJ;

--------------------------------------------------------------------------------
-- Procedure Name: F_PROCESS_WH_ASN
-- Purpose: Process Data in smr_wh_asn
--------------------------------------------------------------------------------
FUNCTION F_PROCESS_WH_ADJ(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_WH_SHIPMENTS';

BEGIN

   sho(L_program);


   IF F_VALIDATE_ADJ(O_error_message) = FALSE THEN
      return false;
   END IF;

   IF F_LOAD_ADJ(O_error_message) = false then
     RETURN FALSE;
   END IF;


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
END F_PROCESS_WH_ADJ;
------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA LOADED INTO TABLE smr_wh_asn
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_ADJ(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_SHIPMENTS';

BEGIN

   sho(L_program);

   --Item Does not exist in RMS
   INSERT INTO SMR_RMS_INT_ERROR  (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
     SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, sas.group_id, sas.record_id,
          'Invalid Item', sysdate
     FROM SMR_RMS_ADJ_STAGE sas
    WHERE (sas.item is null
      or NOT EXISTS (SELECT 'X' FROM item_master im
                          WHERE im.item = sas.item
                            and im.status = 'A'));


   --Length of carton is not 20
   INSERT INTO SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, sas.group_id, sas.record_id,
          'Invalid Carton', sysdate
     FROM SMR_RMS_ADJ_STAGE sas
    WHERE sas.carton_id is not null
      and length(sas.carton_id) != 20;

   --Invalid Adjustment Qty
   INSERT INTO  SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, sas.group_id, sas.record_id,
          'Invalid Carton', sysdate
     FROM SMR_RMS_ADJ_STAGE sas
    WHERE  nvl(sas.QTY_ADJUSTED, 0) = 0
     and sas.REASON_CODE in (select WMS_REASON_CODE from SMR_ADJ_REASON_CODE s where s.inv_status in (0,1));


   --Invalid Adjustment Date
   INSERT INTO  SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, sas.group_id, sas.record_id,
          'Invalid Carton', sysdate
     FROM SMR_RMS_ADJ_STAGE sas
    WHERE sas.TRAN_DATE is null or sas.TRAN_DATE > sysdate;

   --Invalid WH Location
   INSERT INTO  SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, sas.group_id, sas.record_id,
          'Invalid Carton', sysdate
     FROM SMR_RMS_ADJ_STAGE sas
    WHERE sas.WH is null
       and sas.WH  not in (select wh.physical_wh from wh , wh_attributes w
                                    where wh.wh = w.wh
                                     and w.wh_type_code in ('XD','PA'));

   --Invalid Order No
   INSERT INTO  SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, sas.group_id, sas.record_id,
          'Invalid Carton', sysdate
     FROM SMR_RMS_ADJ_STAGE sas
    WHERE sas.order_no is not null
      and NOT EXISTS (SELECT 'X' FROM ordhead oh
                          WHERE oh.order_no = sas.order_no and oh.status in ('A','C'));


   -- Remove records with Error

  update SMR_RMS_INT_QUEUE s set status = 'E',
                                 PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from smr_wh_asn_errors a);

  update SMR_RMS_INT_ADJUSTMENTS_IMP s set ERROR_IND = 'Y' ,
                                    PROCESSED_IND = 'Y',
                                 PROCESSED_DATETIME = sysdate
     where (s.group_id,s.record_id) in
                   (select se.group_id,se.record_id
                     from SMR_RMS_INT_ERROR se)
       and nvl(s.PROCESSED_IND,'N') = 'N';


   delete from  SMR_RMS_ADJ_STAGE sas
     where (sas.group_id,sas.record_id) in
                   (select se.group_id,se.record_id
                     from SMR_RMS_INT_ERROR se);


   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_VALIDATE_ADJ;

------------------------------------------------------------------
-- FUNCTION: F_FINISH_PROCESS
-- Purpose:  Finish processing WH shipments and update Integration Tables
------------------------------------------------------------------
FUNCTION F_FINISH_PROCESS(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_FINISH_PROCESS';

BEGIN
  update SMR_RMS_INT_QUEUE s set status = 'E',
                                 PROCESSED_DATETIME = sysdate
     where exists (select 1
                    from SMR_RMS_INT_ERROR se
                    where se.group_id = s.group_id)
      and s.group_id in (select distinct a.group_id
                          from SMR_RMS_ADJ_STAGE a);

  update SMR_RMS_INT_QUEUE s set status = 'C',
                               PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_RMS_ADJ_STAGE a) and status <> 'E';

  update SMR_RMS_INT_ADJUSTMENTS_IMP s set PROCESSED_IND = 'Y',
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

END SMR_WH_ADJ_SQL;
/