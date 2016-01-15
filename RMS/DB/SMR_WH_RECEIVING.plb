CREATE OR REPLACE PACKAGE BODY SMR_WH_RECEIVING IS
-- Module Name: SMR_WH_RECEIVING
-- Description: This package will be used for processing WH Recieving into RMS
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    20-Feb-15 Murali      Leap 2   Wh recieving Process for PO and Stock Orders
--------------------------------------------------------------------------------
/*
Description:
   The package SMR_WH_RECEIVING is used to process the WH receipts from WA into RMS.
   The package consists of following Main Functions
   F_INIT_WH_RECEIVING - Function used to load data from Interface table into Receiving staging tables
   F_VALIDATE_RECEIPT - Function used to validate the Receiving data from WA
   F_PROCESS_RECEIPTS - Function to load the WH receipts fro PO and Transfers into RMS  The Functions invokes the base API to   
      process the receipt data.
   F_FINISH_PROCESS - Update the status in the Queue Table.  


Algorithm
   - Call Function F_INIT_WH_RECEIVING to load the Staging table SMR_WH_RECEIVING_DATA from the Interface tables
   - Call function F_VALIDATE_RECEIPT to validate the Receipt data from WA. Insert all errors into SMR_RMS_INT_ERROR table and SMR_WH_RECEIVING_ERROR table.
   - Based on the Shipment Type if Reciept is for PO or Transfer Invoke the base API to receive the shipment.
   - For Xdoc PO receipt update the actual_receiving_store in shipsku with the store the carton is intended for.
   - Call fucntion  F_FINISH_PROCESS to  Update the status in the Interface Queue Table.
   
*/
-----------------------------------------------------------------------------------
--PRIVATE FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Procedure Name: SHO
-- Purpose: Used for debug purposes
--------------------------------------------------------------------------------
PROCEDURE SHO(O_ERROR_MESSAGE IN VARCHAR2) IS
   L_DEBUG_ON BOOLEAN := false; -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
   L_DEBUG_TIME_ON BOOLEAN := false; -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
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
      select distinct ieh.ITEM           item1,
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
             -- il.UNIT_RETAIL, -- OLR V1.05 Removed
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

--------------------------------------------------------------------------------
-- FUNCTION Name: CREATE_CARTON
-- Purpose: Create carton record if it does not exist.
--------------------------------------------------------------------------------
FUNCTION CREATE_CARTON(O_error_message IN OUT varchar2,
                       I_carton    IN     varchar2,
                       I_location     IN     number,
                       I_loc_type  IN varchar2) RETURN BOOLEAN IS

   L_program VARCHAR2(61) := 'SMR_WH_RECEIVING.CREATE_CARTON';

BEGIN

      Merge into Carton c
         using    (select carton 
                from carton where carton = I_carton) cr
       on (c.carton = cr.carton)
      when matched then update set c.location = I_location, c.loc_type = I_loc_type
      when not matched then              
      INSERT (carton,loc_type,location) values(I_carton, I_loc_type, I_location);

      return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR', SQLERRM,
                                            L_program, to_char(SQLCODE));
      return FALSE;
END CREATE_CARTON;

---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
-- Function : MAKE_ITEM_LOC
-- Purpose  : This function will make the entered item/location relationship in RMS
---------------------------------------------------------------------------------------------
function F_MAKE_ITEM_LOC(O_error_message IN OUT VARCHAR2,
                         I_item          IN     VARCHAR2,
                         I_loc           IN     NUMBER,
                         I_loc_type      IN     VARCHAR2)
RETURN BOOLEAN is

   L_program VARCHAR2(64) := 'SMR_WH_RECEIVING.MAKE_ITEM_LOC';
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
           --   and wh in (select wh from wh_attributes w where w.wh_type_code in('XD'))
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
-- Procedure Name: F_GENERATE_ARI_MESSAGES
-- Purpose:
--------------------------------------------------------------------------------
 FUNCTION F_GENERATE_ARI_MESSAGES(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_GENERATE_ARI_MESSAGES';
BEGIN

   sho(L_program);

   INSERT INTO smr_944_sqlload_ari
   SELECT DISTINCT 'Order '||ssd.order_no||' is in a '||decode(oh.status,'W','worksheet',
                                                                         'C','closed')||' status.',
          'N'
     FROM SMR_WH_RECEIVING_DATA ssd,
          ordhead oh
    WHERE ssd.order_no = oh.order_no
      AND oh.status in ('W','C');

   INSERT INTO smr_944_sqlload_ari
   SELECT DISTINCT 'Item '||ssd.item||' quantity received greater than left to receive against order '||ssd.order_no||', location '||oh.LOCATION ,
          'N'
     FROM SMR_WH_RECEIVING_DATA ssd,
          ordhead oh,
          ordloc ol
    WHERE ssd.order_no = oh.order_no
      AND oh.order_no = ol.order_no
      AND ssd.item = ol.item
      AND (ssd.qty_to_be_received) > (qty_ordered - nvl(qty_received,0));

   INSERT INTO smr_944_sqlload_ari
   SELECT DISTINCT 'Item '||ssd.item||' added to order '||ssd.order_no||', location '||oh.LOCATION,
          'N'
     FROM SMR_WH_RECEIVING_DATA ssd,
          ordhead oh
    WHERE ssd.order_no = oh.order_no
      AND EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.item,' ') and isp.supplier = nvl(ssd.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.item,' ') and ol.order_no = nvl(ssd.order_no,-1));

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_GENERATE_ARI_MESSAGES;
------------------------------------------------------------------------------------------------------------------------------------
FUNCTION F_GENERATE_ARI_MESSAGES_CARTON(O_error_message IN OUT VARCHAR2,
                                        O_carton        IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_GENERATE_ARI_MESSAGES_CARTON';
BEGIN

   sho(L_program);

   INSERT into smr_944_sqlload_ari
   SELECT distinct 'Order '||ssd.order_no||' is in a '||decode(oh.status,'W','worksheet',
                                                                         'C','closed')||' status.',
          'N'
     FROM SMR_WH_RECEIVING_DATA ssd,
          ordhead oh
    WHERE ssd.carton = O_carton
      AND ssd.order_no = oh.order_no
      AND oh.status in ('W','C');

   INSERT into smr_944_sqlload_ari
   SELECT distinct 'Item '||ssd.item||' quantity received greater than left to receive against order '||ssd.order_no||', location '||oh.LOCATION ,
          'N'
     FROM SMR_WH_RECEIVING_DATA ssd,
          ordhead oh,
          ordloc ol
    WHERE ssd.carton = O_carton
      AND ssd.order_no = oh.order_no
      AND oh.order_no = ol.order_no
      AND ssd.item = ol.item
      AND (ssd.qty_to_be_received) > (qty_ordered - nvl(qty_received,0));

   INSERT into smr_944_sqlload_ari
   SELECT distinct 'Item '||ssd.item||' added to order '||ssd.order_no||', location '||oh.LOCATION,
          'N'
     FROM SMR_WH_RECEIVING_DATA ssd,
          ordhead oh
    WHERE ssd.carton = O_carton
      AND ssd.order_no = oh.order_no
      AND EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.item,' ') and isp.supplier = nvl(ssd.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.item,' ') and ol.order_no = nvl(ssd.order_no,-1));

   return true;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_GENERATE_ARI_MESSAGES_CARTON;

-----------------------------------------------------------------------------------
--PUBLIC FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_CARTON
-- Purpose:  Function Used to Validate the carton . Invoked from the Form for correcting Receipt Errors
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_CARTON(O_error_message IN OUT VARCHAR2,
                           I_carton        IN OUT VARCHAR2,
                           O_valid         IN OUT BOOLEAN)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_CARTON';

BEGIN

   sho(L_program);

   O_valid := true;

   UPDATE SMR_WH_RECEIVING_ERROR
      SET error_msg = NULL,
          error_date = NULL
    WHERE carton = I_carton;

   update SMR_WH_RECEIVING_ERROR ssu
      set ssu.vendor = nvl((select oh.supplier
                              from ordhead oh
                             where oh.order_no = ssu.order_no),ssu.vendor)
    where carton = I_carton;

   --Invalid Order
   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = 'Invalid Order'
    WHERE carton = I_carton
      AND NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = NVL(sse.order_no,-1) and oh.status in ('A','C'));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Invalid SKU
   UPDATE SMR_WH_RECEIVING_ERROR sse
   SET error_msg = decode(error_msg,null,error_msg,error_msg||';') || 'Invalid Item'
    WHERE carton = I_carton
      AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item = NVL(sse.Item,' '));
      
   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Invalid Store
   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Store'
    WHERE carton = I_carton
      AND NOT EXISTS (SELECT 'X' FROM store st WHERE st.store = NVL(sse.store,-1));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Store Closing'
    WHERE carton = I_carton
      AND EXISTS ( SELECT 'X'
                    FROM store st
                   WHERE st.store = nvl(sse.store,-1)
                     and store_close_date is not null
                     and nvl(store_close_date, sse.rcv_date ) - nvl(stop_order_days,0) <= sse.rcv_date);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'No allocation for order'
    WHERE carton = I_carton
      AND EXISTS (SELECT 'x'
                    FROM ordhead oh
                   WHERE sse.order_no = oh.order_no
                     --AND oh.pre_mark_ind = 'Y' --OLR V1.02 Deleted
                     AND NOT EXISTS (SELECT 'x'
                                       from alloc_header ah
                                      where ah.order_no = sse.order_no
                                        and ah.status in ('A','R','C'))
                     AND rownum = 1);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Invalid SKU for PO and supplier - already checked above that sku is valid in RMS
   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Item for Order and supplier'
    WHERE carton = I_carton
      AND NOT EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = NVL(sse.item,' ') and isp.supplier = NVL(sse.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = NVL(sse.item,' ') and ol.order_no = NVL(sse.order_no,-1) and ol.location = 9401);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Received QTY <= 0
   UPDATE SMR_WH_RECEIVING_ERROR
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid quantity received'
    WHERE carton = I_carton
      AND NVL(qty_to_be_received,-1) <= 0;

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Too long after not after date
   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Receive Date'
    WHERE carton = I_carton
      AND exists (select oh.order_no
                    from ordhead oh
                   where oh.order_no = sse.order_no
                     and sse.rcv_date > (oh.not_after_date + (select NVL(RECEIPT_AFTER_DAYS,0) from smr_system_options)));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Item not at any store.'
    WHERE carton = I_carton
      AND not exists (select 'x' from item_loc where item = sse.item and loc_type = 'S' and rownum < 2);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

  --missing rms item_loc_soh
   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Missing item_loc_soh'
    WHERE carton = I_carton
      AND ( exists (select 'x' from item_loc il, ordhead oh where il.item = sse.item and il.loc = oh.location and oh.order_no = sse.order_no)
            and not exists (select 'x' from item_loc_soh ils, ordhead oh where ils.item = sse.item and ils.loc = oh.location and oh.order_no = sse.order_no ));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Carton exists at other store'
    WHERE carton = I_carton
      AND (exists (select 'x' from carton where carton = sse.carton and location != sse.store));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Carton already received/loaded'
    WHERE carton = I_carton
      AND (exists (select 'x'
                     from shipment sh ,
                          shipsku sk
                    where sk.carton = sse.carton
                      and sk.shipment = sh.shipment 
                      and sh.order_no is not null
                      and (
                           (sh.ship_origin = 6 and sh.status_code = 'R' and sh.ship_date > (get_vdate - 365) )
                           or
                           (sh.ship_origin = 4 and sh.ship_date > (get_vdate - 365))
                           or
                           (sh.ship_origin = 6 and sh.status_code = 'I' and sh.order_no != sse.order_no)
                          )
                   ));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Carton'
    WHERE carton = I_carton            
      AND (length(carton) != 20            
           OR SMR_CARTON_INT(carton) = 0); 

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Item not at any valid wh'
    where carton= I_carton
      and not exists (select il.loc
                        from item_loc il,
                             wh wh
                       where il.item = nvl(sse.item,' ')
                         and wh.wh = il.loc
                         and wh in (9521,9531,9541,9401)
                         and il.loc_type = 'W'
                         and rownum < 2);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = 'Warehouse/Receipt date/store not unique for carton - contact support.'
    WHERE carton = I_carton
      AND EXISTS (select 'x'
                   from SMR_WH_RECEIVING_ERROR sse2
                  where sse2.carton = sse.carton
                  group by sse2.carton
                 having count(distinct sse2.rcv_date      ) > 1
                     or count(distinct sse2.wh ) > 1
                     or count(distinct sse2.store         ) > 1);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE SMR_WH_RECEIVING_ERROR sse
      SET error_msg = 'Other item in carton failed'
    WHERE carton = I_carton
      AND error_msg is null
      AND exists (select 'x'
                    from SMR_WH_RECEIVING_ERROR sse2
                   where sse2.carton = sse.carton
                     and sse2.error_msg is not null);

   update SMR_WH_RECEIVING_ERROR
      set error_date = get_vdate
    where carton = I_carton
      and error_date is null
      and error_msg is not null;

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_VALIDATE_CARTON;

------------------------------------------------------------------
-- FUNCTION: F_INIT_WH_RECEIVING
-- Purpose:  LOAD WH Receipts into SMR_WH_RECEIVING_DATA from Integration Tables
------------------------------------------------------------------
FUNCTION F_INIT_WH_RECEIVING(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_INIT_WH_RECEIVING';
  
   cursor c_group_id is
      select distinct q.GROUP_ID 
       from SMR_RMS_INT_QUEUE q,
            SMR_RMS_INT_TYPE t
     where q.interface_id = t.interface_id
       and q.status = 'N'
       and t.interface_name = 'WH_RECEIPTS' 
       and exists (select 1 
                     from SMR_RMS_INT_RECEIVING_IMP s
                    where s.group_id = q.group_id
                      and s.record_id is null) ;
       
BEGIN

   delete from SMR_WH_RECEIVING_DATA;

   -- Below Logic is to populate the record Id in the Interface table as 
   -- ISB does not populate the record id;
    for c_rec in c_group_id   
    loop 
      merge into SMR_RMS_INT_RECEIVING_IMP s
        using (select group_id , 
                      rowid s_rowid,
                      row_number() over(partition by group_id order by wh,shipment_type ,ORDER_NO, ALLOC_NO, 
                                                  TRANSFER_NO,STORE , ITEM ,CARTON ) record_id
                 from SMR_RMS_INT_RECEIVING_IMP 
               where group_id = c_rec.group_id) sr
        on (s.rowid = sr.s_rowid)
      when matched then update set s.record_id = sr.record_id;            

    end loop;  


   insert into SMR_WH_RECEIVING_DATA (GROUP_ID,RECORD_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                                  ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                                  QTY_TO_BE_RECEIVED, RCV_DATE, CARTON)
   select s.group_id, s.record_id, WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON
   from  SMR_RMS_INT_RECEIVING_IMP s,
         SMR_RMS_INT_QUEUE q,
         SMR_RMS_INT_TYPE t
   where s.group_id = q.group_id
     and q.interface_id = t.interface_id
     and q.status = 'N'
     and t.interface_name = 'WH_RECEIPTS';

    -- Update Order No to 6 digit if PO was created for Wh stocked .
    update SMR_WH_RECEIVING_DATA s
       set order_no = substr(order_no,1,6)       
        where not exists (select 1
                     from ordhead oh where oh.order_no = s.order_no)
          and exists (select 1
                     from ordhead oh 
                    where oh.order_no = substr(s.order_no,1,6)
                      and oh.location in (select wh from wh_attributes w where w.wh_type_code = 'PA'))
          and s.shipment_type = 'P';        

  update SMR_RMS_INT_QUEUE s set status = 'P',
                               PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_WH_RECEIVING_DATA a);


 -- Commit;

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_INIT_WH_RECEIVING;


--------------------------------------------------------------------------------
-- Procedure Name: F_PROCESS_RECEIPTS
-- Purpose: Process files in smr_944_sqlload_data_use
--------------------------------------------------------------------------------
FUNCTION F_PROCESS_RECEIPTS(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_RECEIPTS';

   --variables used to consume OTB table
   L_status_code      varchar2(255);
   L_rib_otb_tbl      "RIB_OTB_TBL"     := NULL;
   L_rib_otbdesc_rec  "RIB_OTBDesc_REC" := NULL;
   L_MESSAGE_TYPE     varchar2(255);
   --
   L_unit_cost     SHIPSKU.UNIT_COST%TYPE;
   L_order_loc     number;
   L_loc_type      varchar2(1);
   L_location      ordloc.location%type;
   L_asn           shipment.asn%type;
   L_pre_mark_ind varchar2(1);
   L_distro_doc_type         VARCHAR2(255)  ;
   L_distro_nbr         shipsku.distro_no%type;
   L_alloc_no_hdr       alloc_header.alloc_no%type;
   L_alloc_no_dtl       alloc_header.alloc_no%type;
   L_return_code varchar2(10);
   L_COMMENT   varchar2(100):='Auto Created based on XDoc shipment from WA';

   L_group_id SMR_WH_RECEIVING_DATA.Group_Id%type;
   L_record_id SMR_WH_RECEIVING_DATA.record_Id%type;   
   --Get valid PO receipt details
   CURSOR c_receipts_po IS
   SELECT swr.wh          location
         ,swr.order_no      order_no
         ,swr.item      item
         ,NVL(swr.qty_to_be_received,0) qty_received
         ,'R'               receipt_xactn_type
         ,swr.rcv_date      receipt_date
         ,swr.whse_receiver receipt_nbr
         ,swr.ASN_NO        asn_nbr
         ,NULL              appt_nbr
         ,swr.carton        container_id
         ,swr.shipment_type distro_type
         ,null distro_nbr
         ,swr.store         dest_id
         ,NULL              to_disposition
         ,NULL              from_disposition
         ,null              shipped_qty
         ,NULL              weight
         ,NULL              weight_uom
         ,group_id
         ,record_id
    FROM SMR_WH_RECEIVING_DATA swr
   where swr.shipment_type = 'P'
   ORDER BY 2, 10 ,3;


   CURSOR c_tsf_alloc_bol IS
   SELECT distinct swr.bol_no
    FROM SMR_WH_RECEIVING_DATA swr
   where swr.shipment_type in ('A','T');

   CURSOR c_tsf_alloc_det(C_bol_no shipment.bol_no%type) IS
   SELECT swr.wh location
         ,swr.order_no      order_no
         ,swr.item           item
         ,NVL(swr.qty_to_be_received,0) qty_received
         ,'R'               receipt_xactn_type
         ,swr.rcv_date      receipt_date
         ,swr.whse_receiver receipt_nbr
         ,swr.ASN_NO        asn_nbr
         ,NULL              appt_nbr
         ,swr.carton     container_id
         ,swr.shipment_type distro_type
         ,decode(swr.shipment_type,'A', swr.alloc_no,'T',swr.transfer_no,null) distro_nbr
         ,swr.store         dest_id
         ,NULL              to_disposition
         ,NULL              from_disposition
         ,null              shipped_qty
         ,NULL              weight
         ,NULL              weight_uom
         ,group_id
         ,record_id         
    FROM SMR_WH_RECEIVING_DATA swr
   where swr.shipment_type in ('A','T')
     and swr.asn_no = C_bol_no
   ORDER BY 1, 8 ,10,3;

  cursor c_order_loc(I_order_no number , I_location number) is
    select distinct o.location
      from ordloc o , wh
    where order_no = I_order_no
      and wh.physical_wh = I_location
      and o.location = wh.wh;

--  select location
--    from ordhead oh
--   where order_no = I_order_no;

  cursor c_get_po_asn(C_order_no number,
                   C_carton carton.carton%type,
                   c_item item_master.item%type) is
  select distinct sh.asn
    from shipment sh,
         shipsku sk
   where sh.shipment = sk.shipment
     and sh.order_no = C_order_no
     and sk.carton = C_carton
     and sk.item = C_item ;

  cursor c_po_no_asn(C_order_no number) is
  select distinct sh.asn
    from shipment sh
   where sh.order_no = C_order_no
     and instr(sh.asn,C_order_no) > 0;

  cursor c_unit_cost(I_order_no number,
                     I_item     varchar2)is
  select unit_cost
    from ordloc
   where order_no = I_order_no
     and item = I_item;

  cursor c_pre_mark_ind(I_order_no number) is
  select 'Y'
    from ordhead oh
   where order_no = I_order_no
     and exists (select 1
                   from alloc_header ah
                    where ah.order_no = oh.order_no);

  --get the allocation number associated with an order/item
   cursor c_alloc_header(I_order_no number,
                         I_item     varchar2)  is
   select alloc_no
     from alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.wh = L_order_loc   
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
      and ah.wh = L_order_loc   
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

/*  CURSOR c_distro_no(I_order_no number
                    ,I_item     varchar2
                    ,I_store    number)is
  SELECT ad.alloc_no
    FROM alloc_header ah,
         alloc_detail ad
   WHERE ah.status in ('A','R','C')
     and ah.alloc_no = ad.alloc_no
     AND ah.order_no = I_order_no
     AND ah.item = I_item
     AND ad.to_loc = I_store
   order by decode(ah.status,'A',1,decode(ah.status,'R',2,3));*/

BEGIN

   sho(L_program);

   IF SMR_WH_RECEIVING.F_INIT_WH_RECEIVING(O_error_message)= false then
      return false;
   END IF;

   IF F_VALIDATE_RECEIPT(O_error_message) = FALSE THEN
      return false;
   END IF;

/*   update SMR_WH_RECEIVING_DATA swr
     set swr.asn_no = nvl((select distinct sh.asn
                          from shipment sh,
                               shipsku sk
                         where sh.shipment = sk.shipment
                           and sh.order_no = swr.order_no
                           and sk.carton = swr.carton_id
                           and sk.item = swr.sku and rownum < 2),swr.asn_no)
    where swr.shipment_type = 'P';*/

   update SMR_WH_RECEIVING_DATA swr
     set swr.bol_no = nvl((select distinct sh.bol_no
                          from shipment sh,
                               shipsku sk
                         where sh.shipment = sk.shipment
                           and sk.carton = swr.carton
                           and sh.from_loc = swr.wh
                           and sk.item = swr.item and rownum < 2),swr.bol_no)
    where swr.shipment_type in ('A','T');


   IF F_GENERATE_ARI_MESSAGES(O_error_message) = FALSE THEN
      return false;
   END IF;

   IF API_LIBRARY.INIT(O_error_message) = FALSE THEN
      return false;
   END IF;

/* First process all PO reciepts in the Interface tables */

   -- Generate ARI alert if the Vendor Pack is Opened .
   insert into SMR_WH_RECEIVING_ARI (order_no,Message,alert_type,create_date,processed)
       select distinct s.order_no,
              'Receipt For Order No: '||s.order_no || 'Contains Component Items of Vendor Pack '|| pb.pack_no,
              1,
              sysdate,
              'N'  
         from SMR_WH_RECEIVING_DATA s ,
              item_master im ,
              packitem_breakout pb,
              ordloc ol 
       where s.order_no = ol.order_no
         and ol.item = pb.pack_no
         and pb.item = s.item 
         and ol.item = im.item
         and im.pack_ind = 'Y'  
         and im.simple_pack_ind = 'N'
         and im.pack_type = 'V'
         and s.shipment_type = 'P'
         and not exists (select 1 
                          from ordloc o
                         where o.order_no = s.order_no
                           and o.item = s.item);

   --- Initialize globals, clear out any leftover OTB info/cache DML
   if ORDER_RCV_SQL.INIT_PO_ASN_LOC_GROUP(O_error_message) = FALSE then
      return FALSE;
   end if;
   ---
   if STOCK_ORDER_RCV_SQL.INIT_TSF_ALLOC_GROUP(O_error_message) = FALSE then
      return FALSE;
   end if;

   sho('=========================================================================================================');
   sho('PRE receipt loop');
   sho('=========================================================================================================');

   FOR c_rec in c_receipts_po loop

      L_asn := null;
      L_distro_doc_type := NULL;
      L_distro_nbr := NULL;
      L_alloc_no_hdr := null;
      L_alloc_no_dtl := null;
      L_pre_mark_ind := 'N';
      
      L_group_id := c_rec.group_id;
      L_record_id := c_rec.record_id;

      open  c_order_loc(c_rec.order_no,c_rec.location);
      fetch c_order_loc into L_order_loc;
      close c_order_loc;

      open  c_get_po_asn(c_rec.order_no, c_rec.container_id, c_rec.item);
      fetch c_get_po_asn into L_asn;
      close c_get_po_asn;

      if L_asn is null then
        open  c_po_no_asn(c_rec.order_no);
        fetch c_po_no_asn into L_asn;
        close c_po_no_asn;
      end if;

      c_rec.asn_nbr  := nvl(L_asn,c_rec.order_no);

      L_unit_cost := null;

      open  c_unit_cost(c_rec.order_no,
                        c_rec.item);
      fetch c_unit_cost into L_unit_cost;
      close c_unit_cost;

      ---
      IF SMR_LEAP_ASN_SQL.VALIDATE_LOCATION(O_error_message,
                                             L_loc_type,
                                             L_order_loc) = FALSE THEN
        RETURN FALSE;
      END IF;
    
      if F_make_item_loc(O_error_message,
                       c_rec.item,
                       L_order_loc ,
                       L_loc_type) = false then
          return false;
      end if;
      
      L_location := nvl(c_rec.dest_id,c_rec.dest_id);
      ---
      IF SMR_LEAP_ASN_SQL.VALIDATE_LOCATION(O_error_message,
                                             L_loc_type,
                                             L_location) = FALSE THEN
        RETURN FALSE;
      END IF;
      
      if CREATE_CARTON(O_error_message,
                       c_rec.container_id,
                       L_location,
                       L_loc_type) = false then
          return false;
      end if;

      open  C_pre_mark_ind(c_rec.order_no);
      fetch C_pre_mark_ind into L_pre_mark_ind;
      close C_pre_mark_ind;

      IF L_pre_mark_ind = 'Y' THEN
         L_distro_doc_type := 'A';

         OPEN c_alloc_header(c_rec.order_no,
                             c_rec.item);
         FETCH c_alloc_header INTO L_alloc_no_hdr;
         CLOSE c_alloc_header;

         L_distro_nbr := L_alloc_no_hdr;

         if c_rec.dest_id is not null then
            IF L_alloc_no_hdr is null then

               NEXT_ALLOC_NO(L_alloc_no_hdr,
                             L_return_code,
                             O_error_message);
               ---
               if L_return_code = 'FALSE' then
                  return FALSE;
               end if;

               L_distro_nbr := L_alloc_no_hdr;
               for rec in c_alloc_header_details(c_rec.order_no,
                                                 c_rec.item) loop
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
                                           c_rec.order_no,
                                           L_order_loc,
                                           c_rec.item,
                                           'A',
                                           L_COMMENT,
                                           rec.alloc_method,
                                           rec.order_type,
                                           L_COMMENT,
                                           rec.release_date);
                end loop;
            End if;

            open  c_alloc_detail(c_rec.order_no,
                                 c_rec.item,
                                 c_rec.dest_id);
            fetch c_alloc_detail into L_alloc_no_dtl;
            close c_alloc_detail;

            if L_alloc_no_dtl is null then

               open  c_alloc_header(c_rec.order_no,
                                    c_rec.item);
               fetch c_alloc_header into L_alloc_no_dtl;
               close c_alloc_header;

               for rec in c_alloc_detail_details(c_rec.order_no)
               loop
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
                              c_rec.dest_id,
                              'S',
                              null,
                              c_rec.qty_received ,
                              c_rec.qty_received ,
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
         else
             L_distro_doc_type  := c_rec.distro_type;
             L_distro_nbr      :=  c_rec.distro_nbr;
         end if;
/*         open c_distro_no(c_rec.order_no
                         ,c_rec.item
                         ,c_rec.dest_id);
         fetch c_distro_no into L_distro_nbr;
         close c_distro_no;*/

      else
        L_distro_doc_type  := c_rec.distro_type;
        L_distro_nbr      :=  c_rec.distro_nbr;
      end if;

        IF ORDER_RCV_SQL.PO_LINE_ITEM(O_error_message,
                                          c_rec.location,
                                          c_rec.order_no,
                                          c_rec.item,
                                          c_rec.qty_received,
                                          c_rec.receipt_xactn_type,
                                          c_rec.receipt_date,
                                          c_rec.receipt_nbr,
                                          c_rec.asn_nbr,
                                          c_rec.appt_nbr,
                                          c_rec.container_id,
                                          L_distro_doc_type,
                                          L_distro_nbr,
                                          c_rec.dest_id,
                                          NVL(c_rec.to_disposition, c_rec.from_disposition),
                                          L_unit_cost,
                                          c_rec.shipped_qty,
                                          c_rec.weight,
                                          c_rec.weight_uom,
                                          'N') = FALSE then

           dbms_output.put_line('c_rec.location='||c_rec.location);
           dbms_output.put_line('c_rec.order_no='||c_rec.order_no);
           dbms_output.put_line('c_rec.item='||c_rec.item);
           dbms_output.put_line('c_rec.distro_nbr='||L_distro_nbr);
           dbms_output.put_line('c_rec.distro_nbr='||L_distro_nbr);

           return false;
        END IF;
    
   END LOOP;
   
   merge /*+ parallel(sk,6) */ into shipsku sk 
      using ( select distinct sh.shipment , sd.carton, sd.item , sd.store
               from SMR_WH_RECEIVING_DATA sd,
                    shipment sh
               where sd.order_no = sh.order_no
            --     and sh.to_loc = sd.wh
                 and sd.shipment_type = 'P') s
      on (sk.shipment = s.shipment         
         and sk.item = s.item
         and sk.carton = s.carton)            
      when matched then update set sk.actual_receiving_store = s.store;

    -- Update allocation Status to 3 so that it cannot be changes after the ASN is received.
    UPDATE ALC_ALLOC SET STATUS = '3'
    WHERE status = '2'
      and ALLOC_ID IN (select distinct aa.alloc_id
                         from alc_xref  ax,
                              alc_alloc aa
                        where ax.alloc_id = aa.alloc_id
                          and ax.order_no in (select distinct substr(order_no,1,6)
                                               from SMR_WH_RECEIVING_DATA
                                              where shipment_type = 'P'));

   --- Wrap up global/bulk processing
   IF ORDER_RCV_SQL.FINISH_PO_ASN_LOC_GROUP(O_error_message,
                                                L_rib_otb_tbl) = FALSE THEN
      return false;
   END IF;

   --- Return OTB info
   IF L_rib_otb_tbl.COUNT > 0 then
      L_rib_otbdesc_rec         := "RIB_OTBDesc_REC"(NULL,NULL);
      L_rib_otbdesc_rec.otb_tbl := L_rib_otb_tbl;

      RMSSUB_OTBMOD.CONSUME(L_status_code,
                            O_error_message,
                            L_rib_otbdesc_rec,
                            L_MESSAGE_TYPE);

   ELSE
      L_rib_otbdesc_rec := NULL;
   END IF;

/* NOW  process all Transfer reciepts in the Interface tables */

   --- Initialize globals, clear out any leftover OTB info/cache DML

   IF STOCK_ORDER_RCV_SQL.INIT_TSF_ALLOC_GROUP(O_error_message) = FALSE THEN
      return false;
   END IF;


   FOR C_bol_rec in c_tsf_alloc_bol loop

     FOR rec in c_tsf_alloc_det(C_bol_rec.Bol_No) loop

      L_group_id := rec.group_id;

      L_record_id := rec.record_id;

        if rec.distro_type = 'A' then
           if STOCK_ORDER_RCV_SQL.ALLOC_LINE_ITEM(O_error_message,           --O_error_message
                                                  rec.location,              --I_loc
                                                  rec.item,                  --I_item
                                                  rec.qty_received,          --I_qty
                                                  rec.weight,                --I_weight
                                                  rec.weight_uom,            --I_weight_uom
                                                  rec.receipt_xactn_type,    --I_transaction_type
                                                  rec.receipt_date,          --I_tran_date
                                                  NULL,                      --I_receipt_number
                                                  rec.asn_nbr,               --I_bol_no
                                                  rec.appt_nbr,              --I_appt
                                                  rec.container_id,          --I_carton
                                                  rec.distro_type,           --I_distro_type
                                                  to_number(rec.distro_nbr), --I_distro_number
                                                  NVL(rec.to_disposition, rec.from_disposition), --I_disp
                                                  NULL,                      --I_tampered_ind
                                                  NULL,                      --I_dummy_carton_ind
                                                  NULL) = FALSE then         --I_function_call_ind

             dbms_output.put_line('rec.location='||rec.location);
             dbms_output.put_line('rec.order_no='||rec.order_no);
             dbms_output.put_line('rec.item='||rec.item);
             dbms_output.put_line('rec.item='||rec.item);
             dbms_output.put_line('rec.Carton='||rec.container_id);

             return false;
           end if;

        elsif rec.distro_type = 'T' then
           if STOCK_ORDER_RCV_SQL.TSF_LINE_ITEM(O_error_message,           --O_error_message
                                                rec.location,              --I_loc
                                                rec.item,                  --I_item
                                                rec.qty_received,          --I_qty
                                                rec.weight,                --I_weight
                                                rec.weight_uom,            --I_weight_uom
                                                rec.receipt_xactn_type,    --I_transaction_type
                                                rec.receipt_date,          --I_tran_date
                                                NULL,                      --I_receipt_number
                                                rec.asn_nbr,               --I_bol_no
                                                rec.appt_nbr,              --I_appt
                                                rec.container_id,          --I_carton
                                                rec.distro_type,           --I_distro_type
                                                to_number(rec.distro_nbr), --I_distro_number
                                                NVL(rec.to_disposition, rec.from_disposition),    --I_disp
                                                NULL,                      --I_tampered_ind
                                                NULL) = FALSE then         --I_dummy_carton_ind

             dbms_output.put_line('rec.location='||rec.location);
             dbms_output.put_line('rec.order_no='||rec.order_no);
             dbms_output.put_line('rec.item='||rec.item);
             dbms_output.put_line('rec.distro_nbr='||rec.distro_nbr);
             dbms_output.put_line('rec.Carton='||rec.container_id);

             return false;
           end if;
        end if;

      END LOOP;
      if STOCK_ORDER_RECONCILE_SQL.APPLY_ADJUSTMENTS(O_error_message,
                                                    NULL,
                                                    C_bol_rec.Bol_No,
                                                    NULL) = FALSE then
        return false;
      end if;

   END LOOP;

   --- Wrap up global/bulk processing

   IF STOCK_ORDER_RCV_SQL.FINISH_TSF_ALLOC_GROUP(O_error_message) = FALSE THEN
      return false;
   END IF;


   sho('=========================================================================================================');
   sho('Delete SMR_WH_RECEIVING_DATA');
   sho('=========================================================================================================');

--   DELETE FROM SMR_WH_RECEIVING_DATA;

   IF SMR_WH_RECEIVING.F_FINISH_PROCESS(O_error_message)= false then
      return false;
   END IF;


   sho('=========================================================================================================');
   sho('DONE');
   sho('=========================================================================================================');

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM ||'L_group_id :' ||L_group_id ||'L_record_id :' ||L_record_id,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_PROCESS_RECEIPTS;

------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------
-- FUNCTION: F_PROCESS_CARTON
-- Purpose:  Process Reciepts from the Error table . Invoked from the Form
--------------------------------------------------------------------------------------------
FUNCTION F_PROCESS_CARTON(O_error_message IN OUT VARCHAR2,
                          I_carton_id     IN OUT VARCHAR2)

RETURN BOOLEAN  IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_RECEIPTS';

   --variables used to consume OTB table
   L_status_code      varchar2(255);
   L_rib_otb_tbl      "RIB_OTB_TBL"     := NULL;
   L_rib_otbdesc_rec  "RIB_OTBDesc_REC" := NULL;
   L_MESSAGE_TYPE     varchar2(255);
   --
   L_unit_cost     SHIPSKU.UNIT_COST%TYPE;
   L_order_loc     number;
   L_loc_type      varchar2(1);
   L_location      ordloc.location%type;
   L_asn           shipment.asn%type;
   L_pre_mark_ind varchar2(1);
   L_distro_doc_type         VARCHAR2(255)  ;
   L_distro_nbr         shipsku.distro_no%type;
   L_alloc_no_hdr       alloc_header.alloc_no%type;
   L_alloc_no_dtl       alloc_header.alloc_no%type;
   L_return_code varchar2(10);
   L_COMMENT   varchar2(100):='Auto Created based on XDoc shipment from WA';

   --Get valid PO receipt details
   CURSOR c_receipts_po IS
   SELECT swr.wh          location
         ,swr.order_no      order_no
         ,swr.item      item
         ,NVL(swr.qty_to_be_received,0) qty_received
         ,'R'               receipt_xactn_type
         ,swr.rcv_date      receipt_date
         ,swr.whse_receiver receipt_nbr
         ,swr.ASN_NO        asn_nbr
         ,NULL              appt_nbr
         ,swr.carton        container_id
         ,swr.shipment_type distro_type
         ,null distro_nbr
         ,swr.store         dest_id
         ,NULL              to_disposition
         ,NULL              from_disposition
         ,null              shipped_qty
         ,NULL              weight
         ,NULL              weight_uom
    FROM SMR_WH_RECEIVING_ERROR swr
   where swr.shipment_type = 'P'
     and swr.carton = I_carton_id
   ORDER BY 2, 10 ,3;



  cursor c_order_loc(I_order_no number , I_location number) is
    select distinct o.location
      from ordloc o , wh
    where order_no = I_order_no
      and wh.physical_wh = I_location
      and o.location = wh.wh;

--  select location
--    from ordhead oh
--   where order_no = I_order_no;

  cursor c_get_po_asn(C_order_no number,
                   C_carton carton.carton%type,
                   c_item item_master.item%type) is
  select distinct sh.asn
    from shipment sh,
         shipsku sk
   where sh.shipment = sk.shipment
     and sh.order_no = C_order_no
     and sk.carton = C_carton
     and sk.item = C_item ;

  cursor c_po_no_asn(C_order_no number) is
  select distinct sh.asn
    from shipment sh
   where sh.order_no = C_order_no
     and instr(sh.asn,C_order_no) > 0;

  cursor c_unit_cost(I_order_no number,
                     I_item     varchar2)is
  select unit_cost
    from ordloc
   where order_no = I_order_no
     and item = I_item;

  cursor c_pre_mark_ind(I_order_no number) is
  select 'Y'
    from ordhead oh
   where order_no = I_order_no
     and exists (select 1
                   from alloc_header ah
                    where ah.order_no = oh.order_no);

  --get the allocation number associated with an order/item
   cursor c_alloc_header(I_order_no number,
                         I_item     varchar2)  is
   select alloc_no
     from alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.wh = L_order_loc   -- Temp
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
      and ah.wh = L_order_loc   -- Temp
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


BEGIN

   sho(L_program);

   --No call to F_VALIDATE_CARTON, this is handled in calling form

   IF F_GENERATE_ARI_MESSAGES_CARTON(O_error_message,
                                     I_carton_id) = FALSE THEN
      return false;
   END IF;
   
   
   IF API_LIBRARY.INIT(O_error_message) = FALSE THEN
      return false;
   END IF;

/* First process all PO reciepts in the Interface tables */

   --- Initialize globals, clear out any leftover OTB info/cache DML
   if ORDER_RCV_SQL.INIT_PO_ASN_LOC_GROUP(O_error_message) = FALSE then
      return FALSE;
   end if;
   ---
   if STOCK_ORDER_RCV_SQL.INIT_TSF_ALLOC_GROUP(O_error_message) = FALSE then
      return FALSE;
   end if;

   sho('=========================================================================================================');
   sho('PRE receipt loop');
   sho('=========================================================================================================');

   FOR c_rec in c_receipts_po loop

      L_asn := null;
      L_distro_doc_type := NULL;
      L_distro_nbr := NULL;
      L_alloc_no_hdr := null;
      L_alloc_no_dtl := null;

      open  c_order_loc(c_rec.order_no,c_rec.location);
      fetch c_order_loc into L_order_loc;
      close c_order_loc;

      open  c_get_po_asn(c_rec.order_no, c_rec.container_id, c_rec.item);
      fetch c_get_po_asn into L_asn;
      close c_get_po_asn;

      if L_asn is null then
        open  c_po_no_asn(c_rec.order_no);
        fetch c_po_no_asn into L_asn;
        close c_po_no_asn;
      end if;

      c_rec.asn_nbr  := nvl(L_asn,c_rec.order_no);

      L_unit_cost := null;

      open  c_unit_cost(c_rec.order_no,
                        c_rec.item);
      fetch c_unit_cost into L_unit_cost;
      close c_unit_cost;

      ---
      IF SMR_LEAP_ASN_SQL.VALIDATE_LOCATION(O_error_message,
                                             L_loc_type,
                                             L_order_loc) = FALSE THEN
        RETURN FALSE;
      END IF;
    
      if F_make_item_loc(O_error_message,
                       c_rec.item,
                       L_order_loc ,
                       L_loc_type) = false then
          return false;
      end if;
      
      L_location := nvl(c_rec.dest_id,c_rec.dest_id);
      ---
      IF SMR_LEAP_ASN_SQL.VALIDATE_LOCATION(O_error_message,
                                             L_loc_type,
                                             L_location) = FALSE THEN
        RETURN FALSE;
      END IF;
      
      if CREATE_CARTON(O_error_message,
                       c_rec.container_id,
                       L_location,
                       L_loc_type) = false then
          return false;
      end if;

      open  C_pre_mark_ind(c_rec.order_no);
      fetch C_pre_mark_ind into L_pre_mark_ind;
      close C_pre_mark_ind;

      IF L_pre_mark_ind = 'Y' THEN
         L_distro_doc_type := 'A';

         OPEN c_alloc_header(c_rec.order_no,
                             c_rec.item);
         FETCH c_alloc_header INTO L_alloc_no_hdr;
         CLOSE c_alloc_header;

         L_distro_nbr := L_alloc_no_hdr;

         if c_rec.dest_id is not null then
            IF L_alloc_no_hdr is null then

               NEXT_ALLOC_NO(L_alloc_no_hdr,
                             L_return_code,
                             O_error_message);
               ---
               if L_return_code = 'FALSE' then
                  return FALSE;
               end if;

               L_distro_nbr := L_alloc_no_hdr;
               for rec in c_alloc_header_details(c_rec.order_no,
                                                 c_rec.item) loop
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
                                           c_rec.order_no,
                                           L_order_loc,
                                           c_rec.item,
                                           'A',
                                           L_COMMENT,
                                           rec.alloc_method,
                                           rec.order_type,
                                           L_COMMENT,
                                           rec.release_date);
                end loop;
            End if;

            open  c_alloc_detail(c_rec.order_no,
                                 c_rec.item,
                                 c_rec.dest_id);
            fetch c_alloc_detail into L_alloc_no_dtl;
            close c_alloc_detail;

            if L_alloc_no_dtl is null then

               open  c_alloc_header(c_rec.order_no,
                                    c_rec.item);
               fetch c_alloc_header into L_alloc_no_dtl;
               close c_alloc_header;

               for rec in c_alloc_detail_details(c_rec.order_no)
               loop
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
                              c_rec.dest_id,
                              'S',
                              null,
                              c_rec.qty_received ,
                              c_rec.qty_received ,
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
         else
             L_distro_doc_type  := c_rec.distro_type;
             L_distro_nbr      :=  c_rec.distro_nbr;
         end if;

      else
        L_distro_doc_type  := c_rec.distro_type;
        L_distro_nbr      :=  c_rec.distro_nbr;
      end if;

        IF ORDER_RCV_SQL.PO_LINE_ITEM(O_error_message,
                                          c_rec.location,
                                          c_rec.order_no,
                                          c_rec.item,
                                          c_rec.qty_received,
                                          c_rec.receipt_xactn_type,
                                          c_rec.receipt_date,
                                          c_rec.receipt_nbr,
                                          c_rec.asn_nbr,
                                          c_rec.appt_nbr,
                                          c_rec.container_id,
                                          L_distro_doc_type,
                                          L_distro_nbr,
                                          c_rec.dest_id,
                                          NVL(c_rec.to_disposition, c_rec.from_disposition),
                                          L_unit_cost,
                                          c_rec.shipped_qty,
                                          c_rec.weight,
                                          c_rec.weight_uom,
                                          'N') = FALSE then

           dbms_output.put_line('c_rec.location='||c_rec.location);
           dbms_output.put_line('c_rec.order_no='||c_rec.order_no);
           dbms_output.put_line('c_rec.item='||c_rec.item);
           dbms_output.put_line('c_rec.distro_nbr='||L_distro_nbr);
           dbms_output.put_line('c_rec.distro_nbr='||L_distro_nbr);

           return false;
        END IF;
    
   END LOOP;
   
   merge into shipsku sk 
      using ( select distinct sh.shipment , sd.carton, sd.item , sd.store
               from SMR_WH_RECEIVING_DATA sd,
                    shipment sh
               where sd.order_no = sh.order_no
                 and sh.to_loc = sd.wh
                 and sd.shipment_type = 'P') s
      on (sk.shipment = s.shipment
         and sk.carton = s.carton
         and sk.item = s.item)            
      when matched then update set sk.actual_receiving_store = s.store;

   --- Wrap up global/bulk processing
   IF ORDER_RCV_SQL.FINISH_PO_ASN_LOC_GROUP(O_error_message,
                                                L_rib_otb_tbl) = FALSE THEN
      return false;
   END IF;

   --- Return OTB info
   IF L_rib_otb_tbl.COUNT > 0 then
      L_rib_otbdesc_rec         := "RIB_OTBDesc_REC"(NULL,NULL);
      L_rib_otbdesc_rec.otb_tbl := L_rib_otb_tbl;

      RMSSUB_OTBMOD.CONSUME(L_status_code,
                            O_error_message,
                            L_rib_otbdesc_rec,
                            L_MESSAGE_TYPE);

   ELSE
      L_rib_otbdesc_rec := NULL;
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
END F_PROCESS_CARTON;

-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA IN THE 944 FILE AS LOADED INTO TABLE smr_944_sqlload_data
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_RECEIPT(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_FILE';

BEGIN

   sho(L_program);

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Order', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE ssd.shipment_type = 'P'
     and ( NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = nvl(ssd.order_no,-1) and oh.status in ('A','C')));


   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Transfer', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE ssd.shipment_type = 'T'
     and ( NOT EXISTS (SELECT 'X' FROM tsfhead th WHERE th.tsf_no = nvl(ssd.transfer_no,-1)));



   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                                  ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                                  QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Item', sysdate  , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE( NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item = nvl(ssd.item,' ')));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'No allocation for order.', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE  ssd.shipment_type = 'P'
     and ( EXISTS (SELECT 'x'
                     FROM ordhead oh
                    WHERE ssd.order_no = oh.order_no
                      AND oh.location in (select wh from wh_attributes w where w.wh_type_code in('XD'))
                      AND NOT EXISTS (SELECT 'x'
                                        from alloc_header ah
                                       where ah.order_no = ssd.order_no
                                         and ah.status in ('A','R','C'))));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ssd.ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, ssd.item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Item for Order and supplier', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd ,
          ordhead oh
    WHERE  ssd.shipment_type = 'P'
     and ssd.order_no = oh.order_no
     and ( NOT EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.item,' ') and isp.supplier = nvl(oh.supplier,-1))
           AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.item,' ') and ol.order_no = nvl(ssd.order_no,-1)));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid quantity received', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE( nvl(ssd.qty_to_be_received,-1) <= 0);

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Receive Date', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE ( exists (select oh.order_no
                     from ordhead oh
                    where oh.order_no = ssd.order_no
                      and ssd.rcv_date > (oh.not_after_date + (select nvl(RECEIPT_AFTER_DAYS,0) from smr_system_options))));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Item not at any store.', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE ( not exists (select 'x' from item_loc where item = ssd.item and loc_type = 'S' and rownum < 2));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, ssd.WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Missing item_loc_soh', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd ,
          WH 
    WHERE ssd.WH = wh.physical_wh
      and ( exists (select 'x' from item_loc il where il.item = ssd.item and il.loc = wh.wh)
            and not exists (select 'x' from item_loc_soh ils where ils.item = ssd.item and ils.loc = wh.wh));


   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,  'Carton exists at other store', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE (exists (select 'x' from carton where carton = ssd.CARTON and location not in (ssd.store,ssd.WH)));


   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Carton already received/loaded', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE (exists (select 'x'
                     from shipment sh , shipsku sk
                    where sh.shipment = sk.shipment
                      and sk.carton = ssd.CARTON
                      and (
                           (sh.ship_origin = 6 and sh.status_code = 'R' and sh.ship_date > (get_vdate - 365) )
                           or
                           (sh.ship_origin = 4 and sh.ship_date > (get_vdate - 365))
                           or
                           (sh.ship_origin = 6 and sh.status_code = 'I' and sh.order_no != ssd.order_no)
                          )
                   ));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Carton', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE (length(ssd.CARTON) != 20);

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Invalid Carton', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE SMR_CARTON_INT(ssd.CARTON) = 0;

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Item not at any valid wh', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE (not exists (select il.loc
                         from item_loc il,
                              wh wh
                        where il.item = nvl(ssd.item,' ')
                          and wh.wh = il.loc
                    --      and wh in (select wh from wh_attributes w where w.wh_type_code not in('DD'))
                          and il.loc_type = 'W'
                          and rownum < 2));

   INSERT INTO SMR_WH_RECEIVING_ERROR (RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
                               ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
                               QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID,ERROR_MSG,ERROR_DATE,D_ROWID)
   SELECT RECORD_ID,GROUP_ID,WHSE_RECEIVER, WH, SHIPMENT_TYPE, ASN_NO, BOL_NO,
          ORDER_NO, ALLOC_NO, TRANSFER_NO, STORE, FILE_DATE, VENDOR, item,
          QTY_TO_BE_RECEIVED, RCV_DATE, CARTON, SHIPMENT_ID, 'Warehouse/Receipt date/store not unique for carton - contact support.', sysdate , ssd.rowid
     FROM SMR_WH_RECEIVING_DATA ssd
    WHERE EXISTS (select 'x'
                    from SMR_WH_RECEIVING_DATA ssd2
                   where ssd2.CARTON = ssd.CARTON
                   group by ssd2.CARTON
                  having count(distinct ssd2.rcv_date      ) > 1
                      or count(distinct ssd2.WH ) > 1
                      or count(distinct ssd2.store         ) > 1);

  -- Insert into Error Table
   INSERT INTO SMR_RMS_INT_ERROR
               (INTERFACE_ERROR_ID,GROUP_ID,RECORD_ID,ERROR_MSG, CREATE_DATETIME)
   SELECT SMR_RMS_INT_ERROR_SEQ.Nextval, s.group_id, s.record_id,
          s.error_msg, sysdate
     FROM SMR_WH_RECEIVING_ERROR s,
          SMR_RMS_INT_QUEUE q,
          SMR_RMS_INT_TYPE t
    where s.group_id = q.group_id
      and q.interface_id = t.interface_id
      and q.status = 'P'
      and t.interface_name = 'WH_RECEIPTS' ;

  update SMR_RMS_INT_RECEIVING_IMP s set ERROR_IND = 'Y' ,
                                    PROCESSED_IND = 'Y',
                                 PROCESSED_DATETIME = sysdate
     where (group_id,record_id) in (select distinct se.group_id,se.record_id
                                     from SMR_WH_RECEIVING_ERROR se,
                                          SMR_RMS_INT_QUEUE q,
                                          SMR_RMS_INT_TYPE t
                                    where se.group_id = q.group_id
                                      and q.interface_id = t.interface_id
                                      and q.status = 'P'
                                      and t.interface_name = 'WH_RECEIPTS');

   -- Remove records with Error
/*   DELETE FROM SMR_WH_RECEIVING_DATA SWR
    WHERE EXISTS (SELECT 'X' FROM SMR_WH_RECEIVING_ERROR SWE
                   WHERE SWE.D_ROWID = swr.rowid);
*/
   DELETE FROM SMR_WH_RECEIVING_DATA SWR
    WHERE (group_id,record_id) in (select distinct se.group_id,se.record_id
                                     from SMR_WH_RECEIVING_ERROR se,
                                          SMR_RMS_INT_QUEUE q,
                                          SMR_RMS_INT_TYPE t
                                    where se.group_id = q.group_id
                                      and q.interface_id = t.interface_id
                                      and q.status = 'P'
                                      and t.interface_name = 'WH_RECEIPTS');

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_VALIDATE_RECEIPT;

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
     where s.group_id in (select distinct a.group_id
                          from SMR_WH_RECEIVING_ERROR a)
          and status = 'P';

  update SMR_RMS_INT_QUEUE s set status = 'C',
                               PROCESSED_DATETIME = sysdate
     where s.status= 'P';

  delete from SMR_WH_RECEIVING_ERROR s where s.shipment_type in ('A','T');

  update SMR_RMS_INT_RECEIVING_IMP s set PROCESSED_IND = 'Y',
                                 PROCESSED_DATETIME = sysdate
     where s.group_id in (select distinct a.group_id
                          from SMR_WH_RECEIVING_DATA a)
      and nvl(s.processed_ind,'N') = 'N' and nvl(s.error_ind,'N') = 'N';


  --Commit;

   return true;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_FINISH_PROCESS;
-------------------------------------------------------------------------------

END SMR_WH_RECEIVING;
/