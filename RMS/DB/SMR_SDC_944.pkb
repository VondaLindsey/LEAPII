CREATE OR REPLACE PACKAGE BODY SMR_SDC_944 IS
-- Module Name: SMR_SDC_944
-- Description: This package will be used to create shipments from the 944 SDC receipt file.
--
-- Modification History
-- Version Date      Developer   Issue      Description
-- ======= ========= =========== ========== =========================================
-- 1.00    20-Jul-11 P.Dinsdale  ENH 38     OLR initial version.
-- 1.02    26-Sep-11 P.Dinsdale             Ignore pre mark indicator - assume always Y
--                                          Update 'Carton already received logic to add
--                                          input shipment existing for different order
-- 1.03    28-Jan-13 P.Dinsdale  IMS142753  Do not assume order is for wh 9401.
-- 1.04    29-Jan-13 P.Dinsdale  IMS147463  Make sure carton is a number
-- 1.05    27-Mar-13 L.Tan       IMS153575  Modified COPY_STORE_ITEM to use the
--                                          REGULAR_UNIT_RETAIL instead of the UNIT_RETAIL
--                                          when creating a new item/loc so that clearance
--                                          retail is not set as regular unit retail
-- 1.06    19-Apr-13 P.Dinsdale  IMS151078  Clean up BOL records once done with them.
--------------------------------------------------------------------------------

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
                       I_store     IN     number) RETURN BOOLEAN IS

   L_program VARCHAR2(61) := 'SMR_SDC_944.CREATE_CARTON';

BEGIN

      INSERT INTO carton
      SELECT DISTINCT I_carton, 'S', I_store
        FROM dual
       WHERE NOT EXISTS (SELECT 1
                           FROM carton
                          WHERE carton = I_carton
                            AND loc_type = 'S'
                            AND location = I_store);

      return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR', SQLERRM,
                                            L_program, to_char(SQLCODE));
      return FALSE;
END CREATE_CARTON;


--------------------------------------------------------------------------------
-- Procedure Name: explode_buyer_pack_allocation
-- Purpose: Creates alloc header and detail records for a buyer pack.
--------------------------------------------------------------------------------
FUNCTION explode_buyer_pack_allocation (O_error_message IN OUT varchar2,
                                        I_ORDER_NO      IN     ordhead.order_no%type,
                                        I_ITEM          IN     item_master.item%type,
                                        I_WH            IN     wh.wh%type,
                                        I_COMMENT       IN     varchar2,
                                        I_store         IN     NUMBER,
                                        I_RCV_QTY       IN     NUMBER)
   return boolean is

   L_program varchar2(61) := 'SMR_SDC_944.EXPLODE_BUYER_PACK_ALLOCATION';

   L_return_code varchar2(10);

   --returns Y if buyer back with allocated qty exists for item.
   cursor c_buyer_pack_exists(I_order_no number
                             ,I_item     varchar2) is
   select 'Y'
     from alloc_header ah,
          alloc_detail ad,
          item_master  im,
          packitem_breakout pb
    where ah.status    in ('A','R','C')
      and ah.alloc_no  = ad.alloc_no
      and ah.order_no  = I_order_no
      and ah.item      = im.item
      and ah.item      = pb.pack_no
      and pb.item      = I_item
      and im.pack_type = 'B'
      and ad.qty_allocated > 0;

   L_buyer_pack_exists varchar2(1);

   --returns all detail records for packs associated with an item
   cursor c_component_details is
   select pb2.item,
          ad.to_loc,
          min(ah.order_type)     order_type,
          min(ah.alloc_method)   alloc_method,
          min(ah.release_date)   release_date,
          sum(ad.qty_allocated * pb2.pack_item_qty) component_qty,
          min(ah.status) status,
          min(ad.in_store_date)  in_store_date,
          min(ad.non_scale_ind)  non_scale_ind,
          min(ad.rush_flag)      rush_flag
     from alloc_header ah,
          alloc_detail ad,
          (select distinct pb.pack_no
             from packitem_breakout pb,
                  item_master im
            where pb.item = I_item
              and im.item = pb.pack_no
              and im.pack_type = 'B') buyer_packs_for_item,
          packitem_breakout pb2
    where ah.alloc_no = ad.alloc_no
      and ah.item = buyer_packs_for_item.pack_no
      and ah.order_no = I_order_no
      and ad.qty_allocated > 0
      and ah.status in ('A','R','C')
      and pb2.pack_no = ah.item
    group by pb2.item,
             ad.to_loc
    order by 1, 2;

   CURSOR c_alloc_no(I_order_no number
                    ,I_item     varchar2)is
   SELECT ah.alloc_no
     FROM alloc_header ah
    WHERE ah.order_no = I_order_no
      AND ah.item = I_item
      and ah.status in ('A','R','C')
   order by decode(ah.status,'A',1,decode(ah.status,'R',2,3));

   L_alloc_no alloc_header.alloc_no%type;

   cursor c_pack_details is
   select distinct ah.alloc_no
     from alloc_header ah,
          alloc_detail ad,
          item_master im,
          packitem_breakout pb
    where ah.status in ('A','R','C')
      and ah.alloc_no = ad.alloc_no
      and ah.item = im.item
      and ah.item = pb.pack_no
      and pb.item = I_item
      and im.pack_type = 'B'
      and ah.order_no = I_order_no
      and ad.qty_allocated > 0;

   cursor c_alloc_header is
   select alloc_no
     from alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.status in ('A','R','C')
    order by decode(ah.status,'A',1,decode(ah.status,'R',2,3));

   cursor c_alloc_header_details is
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
            order by decode(ah.status,'A',1,decode(ah.status,'R',2,3)))
    where rownum < 2;

   cursor c_alloc_detail is
   select ad.alloc_no
     from alloc_detail ad,
          alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.status in ('A','R','C')
      and ad.alloc_no = ah.alloc_no
      and ad.to_loc = I_store;

   L_alloc_detail_alloc_no number;

   cursor c_alloc_detail_details is
   select min(ad.in_store_date)  in_store_date,
          min(ad.non_scale_ind)  non_scale_ind,
          min(ad.rush_flag)      rush_flag
     from alloc_header ah,
          alloc_detail ad
    where ah.status in ('A','R','C')
      and ah.alloc_no = ad.alloc_no
      and ah.order_no = I_order_no;

   begin

   sho(L_program);

   --1 Check if buyer pack with qty exists.
   --2 If it does, explode it.
       --For each component item
           -----if component header does exists, insert it.
           -----if component detail does exists, add to it.
           -----if component detail does not exists, insert it.

   L_alloc_no := null;

   --1 Check if buyer pack with qty exists.

   l_buyer_pack_exists := null;

   open  c_buyer_pack_exists(I_order_no, I_item);
   fetch c_buyer_pack_exists into l_buyer_pack_exists;
   close c_buyer_pack_exists;

   --2 If it does, explode it.
   if nvl(l_buyer_pack_exists,'N') = 'Y' then

      --For each component item/store combination
      for rec in c_component_details loop

         --Check if component header does not exist, and if it does not create it.
         L_alloc_no := null;

         open  c_alloc_no(I_order_no, rec.item);
         fetch c_alloc_no into L_alloc_no;
         close c_alloc_no;

         if L_alloc_no is null then

            NEXT_ALLOC_NO(L_alloc_no,
                          L_return_code,
                          O_error_message);
            ---
            if L_return_code = 'FALSE' then
               return FALSE;
            end if;

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
                             VALUES (L_alloc_no,
                                     I_order_no,
                                     I_wh,
                                     rec.item,
                                     'A',
                                     I_COMMENT,
                                     rec.alloc_method,
                                     rec.order_type,
                                     I_COMMENT,
                                     rec.release_date);

         end if;

         -----If component detail does exists, add to it.
         -----If component detail does not exists, insert it.
         -----Use a merge to do this.
         MERGE INTO alloc_detail
         USING (select rec.to_loc to_loc from dual) dual_rec
            ON (L_alloc_no = alloc_detail.alloc_no and dual_rec.to_loc = alloc_detail.to_loc)
          WHEN MATCHED THEN
               update set qty_allocated = qty_allocated + rec.component_qty,
                          qty_prescaled = qty_prescaled + rec.component_qty
          WHEN NOT MATCHED THEN
               INSERT (alloc_no         ,
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
           values (L_alloc_no,
                   rec.TO_LOC,
                   'S',
                   null              ,
                   rec.component_qty ,
                   rec.component_qty ,
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

      --now remove pack details
      for rec in c_pack_details loop

        update alloc_detail set qty_allocated = 0,
                                qty_distro = 0,
                                qty_transferred = 0,
                                qty_prescaled = 0
         where alloc_no = rec.alloc_no;

      end loop;

   end if;

   --now that we have exploded the buyer pack, check that item exists in alloc header and alloc detail for the store passed in.
   l_alloc_no := null;

   open  c_alloc_header;
   fetch c_alloc_header into l_alloc_no;
   close c_alloc_header;

   if l_alloc_no is null then

      NEXT_ALLOC_NO(L_alloc_no,
                    L_return_code,
                    O_error_message);
      ---
      if L_return_code = 'FALSE' then
         return FALSE;
      end if;

      for rec in c_alloc_header_details loop

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
                          VALUES (L_alloc_no,
                                  I_order_no,
                                  I_wh,
                                  I_item,
                                  'A',
                                  I_COMMENT,
                                  rec.alloc_method,
                                  rec.order_type,
                                  I_COMMENT,
                                  rec.release_date);

      end loop;

   end if;

   --now check alloc detail exists
   open  c_alloc_detail;
   fetch c_alloc_detail into L_alloc_detail_alloc_no;
   close c_alloc_detail;

   if L_alloc_detail_alloc_no is null then

      open  c_alloc_header;
      fetch c_alloc_header into l_alloc_no;
      close c_alloc_header;

      for rec in c_alloc_detail_details loop

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
               values (L_alloc_no,
                       I_STORE,
                       'S',
                       null,
                       I_RCV_QTY ,
                       I_RCV_QTY ,
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

   return true;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR', SQLERRM,
                                            L_program, to_char(SQLCODE));
      return FALSE;
END;

---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
-- Function : MAKE_ITEM_LOC
-- Purpose  : This function will make the entered item/location relationship in RMS
---------------------------------------------------------------------------------------------
function make_item_loc(O_error_message IN OUT VARCHAR2,
                       I_item          IN     VARCHAR2,
                       I_loc           IN     NUMBER,
                       I_loc_type      IN     VARCHAR2)
RETURN BOOLEAN is

   L_program VARCHAR2(64) := 'SMR_SDC_944.MAKE_ITEM_LOC';
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
              and wh in (9521,9531,9541)
              and il.loc_type = 'W'
              and rownum < 2
            UNION
           select il.loc
             from item_loc il,
                  wh wh
            where il.item = I_item
              and wh.wh = il.loc
              and il.loc_type = 'W'
              and wh in (9401)
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

      if L_new_wh = 952 or L_new_wh = 953 or L_new_wh = 954 then
         L_new_wh := L_new_wh * 10 + 1;
      end if;

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
                             values(I_shipment);
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
                      I_bol_no          IN       BOL_SHIPMENT.BOL_NO%TYPE)
   RETURN BOOLEAN IS

   L_program              VARCHAR2(50) := package_name||'.SHIP_DISTROS';
   L_from_loc             BOL_SHIPMENT.FROM_LOC%TYPE;
   L_to_loc               BOL_SHIPMENT.TO_LOC%TYPE;
   L_from_loc_orig        BOL_SHIPMENT.FROM_LOC%TYPE;
   L_to_loc_orig          BOL_SHIPMENT.TO_LOC%TYPE;
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
        from bol_shipment bol_sh
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
        from bol_shipsku bol_sku,
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
        from bol_shipsku bol_sku,
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
                from bol_shipment bs,
                     bol_shipsku bk
               where bs.bol_no = I_bol_no
                 and bs.bol_no = bk.bol_no
                 and bk.distro_type = 'A') bol_sku,
             (select ad.alloc_no,
                     ad.qty_allocated - ad.qty_transferred available_qty
                from bol_shipment bs,
                     bol_shipsku bk,
                     wh,
                     alloc_detail ad
               where bs.bol_no = I_bol_no
                 and bk.bol_no = bs.bol_no
                 and bk.distro_no = ad.alloc_no
                 and bs.to_loc = wh.physical_wh
                 and wh.wh = ad.to_loc
                 and ad.to_loc_type = 'W'
               union all
              select ad.alloc_no,
                     ad.qty_allocated - ad.qty_transferred available_qty
                from bol_shipment bs,
                     bol_shipsku bk,
                     alloc_detail ad
               where bs.bol_no = I_bol_no
                 and bk.bol_no = bs.bol_no
                 and bk.distro_no = ad.alloc_no
                 and bs.to_loc = ad.to_loc
                 and ad.to_loc_type = 'S') ad,
             (select ah.alloc_no,
                     ah.item,
                     wh.physical_wh wh
                from bol_shipment bs,
                     bol_shipsku bk,
                     wh,
                     alloc_header ah
               where bs.bol_no = I_bol_no
                 and bs.bol_no = bk.bol_no
                 and bs.from_loc = wh.physical_wh
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

   if L_bol_exist = TRUE then
      O_error_message := SQL_LIB.CREATE_MSG('DUP_BOL',
                                            I_bol_no,
                                            L_program,
                                            NULL);
        return FALSE;
   end if;
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

      if L_bol_shipsku_tbl(a).ship_qty > L_bol_shipsku_tbl(a).available_qty then

         O_error_message := SQL_LIB.CREATE_MSG('1INV_TSF_ALLOC_QTY',
                                               L_bol_shipsku_tbl(a).distro_no,
                                               L_bol_shipsku_tbl(a).item,
                                               NULL);
         return FALSE;
      end if;
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
            END LOOP;

            if BOL_SQL.PROCESS_ALLOC(O_error_message) = FALSE then
               return FALSE;
            end if;
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
     FROM smr_944_sqlload_data_use ssd,
          ordhead oh
    WHERE ssd.order_no = oh.order_no
      AND oh.status in ('W','C');

   INSERT INTO smr_944_sqlload_ari
   SELECT DISTINCT 'Item '||ssd.sku_char||' quantity received greater than left to receive against order '||ssd.order_no||', location '||oh.LOCATION ,
          'N'
     FROM smr_944_sqlload_data_use ssd,
          ordhead oh,
          ordloc ol
    WHERE ssd.order_no = oh.order_no
      AND oh.order_no = ol.order_no
      AND ssd.sku_char = ol.item
      AND (ssd.qty_to_be_received) > (qty_ordered - nvl(qty_received,0));

   INSERT INTO smr_944_sqlload_ari
   SELECT DISTINCT 'Item '||ssd.sku_char||' added to order '||ssd.order_no||', location '||oh.LOCATION,
          'N'
     FROM smr_944_sqlload_data_use ssd,
          ordhead oh
    WHERE ssd.order_no = oh.order_no
      AND EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.sku_char,' ') and isp.supplier = nvl(ssd.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.sku_char,' ') and ol.order_no = nvl(ssd.order_no,-1));

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
     FROM smr_944_sqlload_err ssd,
          ordhead oh
    WHERE ssd.carton_id = O_carton
      AND ssd.order_no = oh.order_no
      AND oh.status in ('W','C');

   INSERT into smr_944_sqlload_ari
   SELECT distinct 'Item '||ssd.sku_char||' quantity received greater than left to receive against order '||ssd.order_no||', location '||oh.LOCATION ,
          'N'
     FROM smr_944_sqlload_err ssd,
          ordhead oh,
          ordloc ol
    WHERE ssd.carton_id = O_carton
      AND ssd.order_no = oh.order_no
      AND oh.order_no = ol.order_no
      AND ssd.sku_char = ol.item
      AND (ssd.qty_to_be_received) > (qty_ordered - nvl(qty_received,0));

   INSERT into smr_944_sqlload_ari
   SELECT distinct 'Item '||ssd.sku_char||' added to order '||ssd.order_no||', location '||oh.LOCATION,
          'N'
     FROM smr_944_sqlload_err ssd,
          ordhead oh
    WHERE ssd.carton_id = O_carton
      AND ssd.order_no = oh.order_no
      AND EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.sku_char,' ') and isp.supplier = nvl(ssd.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.sku_char,' ') and ol.order_no = nvl(ssd.order_no,-1));

   return true;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_GENERATE_ARI_MESSAGES_CARTON;
------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------
--PUBLIC FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
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
   L_dc_dest_id              NUMBER(10)     ;
   L_po_nbr                  NUMBER(10)      ;
   L_item_id                 VARCHAR2(25)   ;
   L_unit_qty                NUMBER(12,4)   ;
   L_receipt_xactn_type      VARCHAR2(255)  ;
   L_receipt_date            DATE           ;
   L_receipt_nbr             VARCHAR2(17)   ;
   L_asn_nbr                 VARCHAR2(30)   ;
   L_appt_nbr                NUMBER(9)      ;
   L_container_id            VARCHAR2(20)   ;
   L_distro_doc_type         VARCHAR2(255)  ;
   L_distro_nbr              NUMBER(10)     ;
   L_dest_id                 NUMBER(10)     ;
   L_to_disposition          VARCHAR2(10)   ;
   L_from_disposition        NUMBER(20,4)   ;
   L_unit_cost               NUMBER(12,4)   ;
   L_shipped_qty             NUMBER(12,4)   ;
   L_weight                  VARCHAR2(4)    ;
   L_weight_uom              VARCHAR2(255)  ;

   L_bol_no        VARCHAR2(30);
   L_return_code   VARCHAR2(30);
   L_alloc_no      NUMBER(10);
   L_qty_available NUMBER;
   L_qty_shipped   NUMBER;
   L_new_wh        NUMBER;

   --Get valid receipt details
   CURSOR c_receipts IS
   SELECT ssd.whse_location L_dc_dest_id
         ,ssd.order_no      L_po_nbr
         ,ssd.sku_char      L_item_id
         ,NVL(ssd.qty_to_be_received,0) L_unit_qty
         ,'R'               L_receipt_xactn_type
         ,ssd.rcv_date      L_receipt_date
         ,ssd.whse_receiver L_receipt_nbr
         ,ssd.carton_id     L_asn_nbr
         ,NULL              L_appt_nbr
         ,ssd.carton_id     L_container_id
         ,NULL              L_distro_doc_type
         ,NULL              L_distro_nbr
         ,ssd.store         L_dest_id
         ,NULL              L_to_disposition
         ,NULL              L_from_disposition
         ,ssd.units_shipd   L_shipped_qty
         ,NULL              L_weight
         ,NULL              L_weight_uom
    FROM smr_944_sqlload_data_use ssd
   WHERE NVL(ssd.qty_to_be_received,0) >  0
   ORDER BY 2, 10, 13, 3;

   CURSOR c_adjustments IS
   SELECT (ssd.whse_location) * 10 + 1 wh
         ,ssd.order_no      order_no
         ,ssd.sku_char      item
         ,NVL(ssd.exception_qty,0) adj_qty
         ,ssd.rcv_date      rcv_date
         ,ssd.vendor_performance_code
    FROM smr_944_sqlload_data_use ssd
   WHERE NVL(ssd.exception_qty,0) >  0
   ORDER BY 2, 1, 3, 5;

  cursor c_unit_cost(I_order_no number,
                     I_item     varchar2)is
  select unit_cost
    from ordloc
   where order_no = I_order_no
     and item = I_item;

   --get all receipt records from which we need to make shipments.
   CURSOR c_bol_shipment is
   SELECT distinct
          ssd.rcv_date      ship_date
         ,ssd.whse_location FROM_loc
         ,'W'               FROM_loc_type
         ,ssd.store         to_loc
         ,'S'               to_loc_type
         ,NULL              courier
         ,NULL              no_boxes
         ,NULL              comments
         ,ssd.carton_id     carton_id
    FROM smr_944_sqlload_data_use ssd,
         ordhead oh
   WHERE oh.order_no = ssd.order_no
--     AND oh.pre_mark_ind = 'Y' --Only do for orders with allocations.  --OLR V1.02 Deleted
     AND NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0) >  0
   ORDER BY ssd.carton_id;

   --get all receipt records from which we need to make shipsku records .
  CURSOR c_bol_shipsku(I_carton varchar2) is
   SELECT ssd.order_no      order_no
         ,ssd.sku_char      item
         ,ssd.upc_char      ref_item
         ,ssd.carton_id     carton_id
         ,sum(NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0)) ship_qty
         ,sysdate           last_update_datetime
     FROM smr_944_sqlload_data_use ssd
    WHERE ssd.carton_id = I_carton
    group by ssd.order_no
         ,ssd.sku_char
         ,ssd.upc_char
         ,ssd.carton_id
   ORDER BY ssd.order_no, ssd.sku_char;

  --get the allocation number associated with an order/item/store
  CURSOR c_distro_no(I_order_no number
                    ,I_item     varchar2
                    ,I_store    number)is
  SELECT ad.alloc_no, ad.qty_allocated - nvl(ad.qty_transferred,0) qty_available
    FROM alloc_header ah,
         alloc_detail ad
   WHERE ah.status in ('A','R','C')
     and ah.alloc_no = ad.alloc_no
     AND ah.order_no = I_order_no
     AND ah.item = I_item
     AND ad.to_loc = I_store
   order by decode(ah.status,'A',1,decode(ah.status,'R',2,3));

   CURSOR c_to_be_shipped(I_order_no number,
                          I_item varchar2,
                          I_store number,
                          I_wh number) IS
  SELECT sum(NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0)) to_be_shipped
    FROM smr_944_sqlload_data_use ssd
   WHERE NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0) >  0
     and sku_char = I_item
     and order_no = I_order_no
     and store = I_store;

  cursor c_pre_mark_ind(I_order_no number) is
  select pre_mark_ind
    from ordhead
   where order_no = I_order_no;

  L_pre_mark_ind varchar2(1);

  cursor c_multiple_upc is
  select order_no, sku_char item, carton_id, count(distinct nvl(upc_char,' '))
    from smr_944_sqlload_data_use
   group by order_no, sku_char, carton_id
  having count(distinct nvl(upc_char,' ')) > 1;

  cursor c_order_ref_item(I_order_no number,
                          I_item     varchar2) is
  select ref_item
    from ordsku
   where order_no = I_order_no
     and item = I_item;

BEGIN

   sho(L_program);

   --set this so that trigger will not fire for the session running this program
   SMR_SDC_944.pv_alloc_no := -1;

   /*
   --preprocess by cleaning out records in custom table where they are no longer relevant.
   delete from smr_944_new_alloc_detail sad
    where not exists ( select ah.alloc_no
                        from alloc_detail ah
                       where ah.alloc_no = sad.alloc_no);
   */

   --ignore supplier in file and take supplier from RMS
   update smr_944_sqlload_data_use ssu
      set ssu.vendor = nvl((select oh.supplier
                              from ordhead oh
                             where oh.order_no = ssu.order_no),ssu.vendor);

   delete from smr_944_sqlload_data_use where nvl(QTY_TO_BE_RECEIVED,0) = 0 and nvl(EXCEPTION_QTY,0) = 0;

   IF F_VALIDATE_FILE(O_error_message) = FALSE THEN
      return false;
   END IF;

   IF F_GENERATE_ARI_MESSAGES(O_error_message) = FALSE THEN
      return false;
   END IF;

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

   sho('=========================================================================================================');
   sho('PRE receipt loop');
   sho('=========================================================================================================');

   FOR rec in c_receipts loop

--      sho('Receipt Process carton/'||L_container_id||' ord/'||rec.L_po_nbr||' item/'||rec.L_item_id||' loc/'||rec.L_dest_id);

      smr_order_rcv_sql.p_bill_to_loc := rec.L_dest_id;

      L_unit_cost := null;

      open  c_unit_cost(rec.L_po_nbr,
                        rec.L_item_id);
      fetch c_unit_cost into L_unit_cost;
      close c_unit_cost;

      if make_item_loc(O_error_message,
                       rec.L_item_id,
                       rec.L_dest_id ,
                       'S') = false then
          return false;
      end if;

      if make_item_loc(O_error_message,
                       rec.L_item_id,
                       rec.L_dc_dest_id ,
                       'W') = false then
          return false;
      end if;

      if CREATE_CARTON(O_error_message,
                       rec.L_container_id,
                       rec.L_dest_id) = false then
          return false;
      end if;

      L_distro_doc_type := NULL;
      L_distro_nbr := NULL;

      open  C_pre_mark_ind(rec.L_po_nbr);
      fetch C_pre_mark_ind into L_pre_mark_ind;
      close C_pre_mark_ind;

      L_pre_mark_ind := 'Y';  --OLR V1.02 INSERT

      -----------------------------------------------------------------------------------------------------------------------
      --If this is a pre mark order, make sure allocation is set-up.
      -----------------------------------------------------------------------------------------------------------------------
      IF L_pre_mark_ind = 'Y' THEN

         L_distro_doc_type := 'A';

         --
         IF explode_buyer_pack_allocation(O_error_message,
                                          rec.L_po_nbr,
                                          rec.L_item_id,
                                          9401,
                                          'Created for custom 944 receiving.',
                                          rec.L_dest_id,
                                          rec.L_unit_qty) = FALSE THEN
            return false;
         END IF;

         --check amount available and amount on receipt and allow more shipped than originally allocated

         open c_distro_no(rec.L_po_nbr
                         ,rec.L_item_id
                         ,rec.L_dest_id);
         fetch c_distro_no into L_distro_nbr, L_qty_available;
         close c_distro_no;

         open  c_to_be_shipped(rec.L_po_nbr,
                               rec.L_item_id,
                               rec.L_dest_id,
                               rec.L_dc_dest_id);
         fetch c_to_be_shipped into L_qty_shipped;
         close c_to_be_shipped;

         IF L_qty_shipped > L_qty_available THEN

            UPDATE alloc_detail
               SET qty_allocated = qty_allocated + (L_qty_shipped - L_qty_available),
                   qty_prescaled = qty_prescaled + (L_qty_shipped - L_qty_available)
             WHERE alloc_no = L_distro_nbr
               AND to_loc = rec.L_dest_id;

         END IF;


      END IF;

      update alloc_header
         set wh = (rec.L_dc_dest_id*10) + 1
       where alloc_no = L_distro_nbr;


      IF SMR_ORDER_RCV_SQL.PO_LINE_ITEM(O_error_message,
                                        rec.L_dc_dest_id,
                                        rec.L_po_nbr,
                                        rec.L_item_id,
                                        rec.L_unit_qty,
                                        rec.L_receipt_xactn_type,
                                        rec.L_receipt_date,
                                        rec.L_receipt_nbr,
                                        rec.L_asn_nbr,
                                        rec.L_appt_nbr,
                                        rec.L_container_id,
                                        L_distro_doc_type,
                                        to_number(L_distro_nbr),
                                        rec.L_dest_id,
                                        NVL(rec.L_to_disposition,
                                            rec.L_from_disposition),
                                        L_unit_cost,
                                        rec.L_shipped_qty,
                                        rec.L_weight,
                                        rec.L_weight_uom,
                                        'N') = FALSE then

         dbms_output.put_line('rec.L_dc_dest_id='||rec.L_dc_dest_id);
         dbms_output.put_line('rec.L_po_nbr='||rec.L_po_nbr);
         dbms_output.put_line('rec.L_item_id='||rec.L_item_id);
         dbms_output.put_line('rec.L_dest_id='||rec.L_dest_id);

         return false;
      END IF;

      IF L_distro_nbr is not NULL then

         update alloc_header
          --set wh = 9401 --OLR V1.03 deleted.
            set wh = nvl((select location from ordhead where order_no = alloc_header.order_no),9401) --OLR V1.03 inserted.
          where alloc_no = L_distro_nbr;

      END IF;

   END LOOP;
   --- Wrap up global/bulk processing
   IF SMR_ORDER_RCV_SQL.FINISH_PO_ASN_LOC_GROUP(O_error_message,
                                                L_rib_otb_tbl) = FALSE THEN
      return false;
   END IF;
   ---
   IF STOCK_ORDER_RCV_SQL.FINISH_TSF_ALLOC_GROUP(O_error_message) = FALSE THEN
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
   sho('PRE ADJUSTMENTS');
   sho('=========================================================================================================');

   --empty out cache of tran_data inserts
   if INVADJ_SQL.INIT_ALL (O_error_message) = FALSE then
      return false;
   end if;

   FOR rec in c_adjustments loop

--      sho('Adjust '||rec.vendor_performance_code||'/'||rec.wh||'/'||rec.item||'/'||rec.vendor_performance_code||'/'||rec.adj_qty||'/'||rec.order_no);

      if INVADJ_SQL.BUILD_PROCESS_INVADJ(O_error_message,
                                         rec.wh,
                                         rec.item,
                                         rec.vendor_performance_code, --I_reason
                                         rec.adj_qty,
                                         null,     --adj_weight
                                         null,     --I_adj_weight_uom
                                         'ATS',    --I_from_disposition,
                                         null,     --I_to_disposition,
                                         user,     --I_user_id,
                                         rec.rcv_date,
                                         rec.order_no,
                                         'P',
                                         NULL,     --I_wac
                                         NULL) = FALSE then --I_unit_retail
         return false;
      end if;

   END LOOP;

   --call flush
   if INVADJ_SQL.FLUSH_ALL (O_error_message) = FALSE then
      return false;
   end if;

   sho('=========================================================================================================');
   sho('PRE BOL');
   sho('=========================================================================================================');

   for rec_outer in c_multiple_upc loop
   --order_no, sku_char item, carton_id
      for rec_inner in c_order_ref_item(rec_outer.order_no,
                                        rec_outer.item) loop

          if rec_inner.ref_item is not null then

             update smr_944_sqlload_data_use ssd
                set upc_char  = rec_inner.ref_item
              where carton_id = rec_outer.carton_id
                and sku_char  = rec_outer.item;

          else

             update smr_944_sqlload_data_use ssd
                set upc_char  = (select min(ssd2.upc_char)
                                   from smr_944_sqlload_data_use ssd2
                                  where carton_id = rec_outer.carton_id
                                    and sku_char  = rec_outer.item
                                    and upc_char is not null)
              where carton_id = rec_outer.carton_id
                and sku_char  = rec_outer.item;

          end if;

      end loop;

   end loop;

   --create AND ship SDC ASNs
   for rec_shipment in c_bol_shipment loop

       --sho('Process carton/'||rec_shipsku.carton_id||' item/'||rec_shipsku.item||' loc/'||rec_shipment.to_loc||' wh/'||rec_shipment.from_loc);
--       sho('ship carton '||rec_shipment.carton_id);

       NEXT_BILL_OF_LADING(O_ERROR_MESSAGE
                          ,L_bol_no
                          ,L_return_code);

       IF L_return_code = 'FALSE' THEN
          RETURN FALSE;
       END IF;

--       sho('Insert BOL '||L_bol_no);

       INSERT INTO BOL_SHIPMENT (bol_no
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
                                ,rec_shipment.courier
                                ,rec_shipment.no_boxes
                                ,rec_shipment.comments);

      FOR rec_shipsku in c_bol_shipsku(rec_shipment.carton_id) LOOP

         L_distro_doc_type := NULL;
         L_distro_nbr := NULL;

         OPEN c_distro_no(rec_shipsku.order_no
                         ,rec_shipsku.item
                         ,rec_shipment.to_loc);
         FETCH c_distro_no INTO L_distro_nbr, L_qty_available;
         CLOSE c_distro_no;

         IF L_distro_nbr is not NULL then
            L_distro_doc_type := 'A';
         ELSE
            O_ERROR_MESSAGE := 'No allocation found for order '||rec_shipsku.order_no ||' Item '||rec_shipsku.item||' store '||rec_shipment.to_loc;
            RETURN FALSE;
         END IF;

         INSERT INTO bol_shipsku (BOL_NO
                                 ,DISTRO_NO
                                 ,DISTRO_TYPE
                                 ,ITEM
                                 ,REF_ITEM
                                 ,CARTON
                                 ,SHIP_QTY
                                 ,WEIGHT_EXPECTED
                                 ,WEIGHT_EXPECTED_UOM
                                 ,LAST_UPDATE_DATETIME)
                          VALUES (L_bol_no
                                 ,L_distro_nbr
                                 ,L_distro_doc_type
                                 ,rec_shipsku.item
                                 ,rec_shipsku.ref_item
                                 ,rec_shipment.carton_id
                                 ,rec_shipsku.ship_qty
                                 ,NULL
                                 ,NULL
                                 ,rec_shipsku.LAST_UPDATE_DATETIME);

         UPDATE alloc_header
            SET wh = (rec_shipment.FROM_loc * 10 + 1)
          WHERE alloc_no = L_distro_nbr;

      END LOOP;

      IF SHIP_DISTROS(O_ERROR_MESSAGE,
                      L_bol_no) = FALSE THEN
        return false;
      END IF;

      --OLR V1.06 Insert START
      delete from bol_shipsku where bol_no = L_bol_no;
      delete from bol_shipment where bol_no = L_bol_no;
      --OLR V1.06 Insert END

      --reset the allocation wh after we temporarily changed it to process this file.
      /*OLR V1.03 Delete START
      UPDATE alloc_header
         SET wh = 9401
       WHERE wh in (9521,9531,9541);
      --OLR V1.03 Delete END */

      --OLR V1.03 Insert START
      UPDATE alloc_header
         SET wh = nvl((select oh.location
                         from ordhead oh,
                              smr_944_sqlload_data_use ssu
                        where oh.order_no = ssu.order_no
                          and ssu.carton_id = rec_shipment.carton_id
                          and rownum < 2), 9401)
       WHERE wh in (9521,9531,9541)
         AND ORDER_NO = (select oh.order_no
                           from ordhead oh,
                                smr_944_sqlload_data_use ssu
                          where oh.order_no = ssu.order_no
                            and ssu.carton_id = rec_shipment.carton_id
                            and rownum < 2);
      --OLR V1.03 Insert END

   END LOOP;


   sho('=========================================================================================================');
   sho('update alc_alloc');
   sho('=========================================================================================================');

    UPDATE ALC_ALLOC SET STATUS = '3'
    WHERE status = '2'
      and ALLOC_ID IN (select aa.alloc_id
                         from alc_xref  ax,
                              alc_alloc aa,
                              smr_944_sqlload_data_use ssd
                        where ssd.order_no = ax.order_no
                          and ssd.sku_char = ax.item_id
                          and ax.alloc_id = aa.alloc_id
                       union
                       select aa.alloc_id
                         from smr_944_sqlload_data_use ssd,
                              alc_alloc aa,
                              alc_xref  ax,
                              packitem_breakout pb,
                              item_master im
                        where ax.alloc_id = aa.alloc_id
                          and ssd.order_no = ax.order_no
                          and ssd.sku_char = pb.item
                          and pb.pack_no   = ax.item_id
                          and pb.pack_no   = im.item
                          and im.pack_type = 'B');

   sho('=========================================================================================================');
   sho('Delete smr_944_sqlload_data_use');
   sho('=========================================================================================================');

   DELETE FROM smr_944_sqlload_data_use;

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
END F_PROCESS_RECEIPTS;
------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------
FUNCTION F_PROCESS_CARTON(O_error_message IN OUT VARCHAR2,
                          I_carton_id     IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_CARTON';

   --variables used to consume OTB table
   L_status_code      varchar2(255);
   L_rib_otb_tbl      "RIB_OTB_TBL"     := NULL;
   L_rib_otbdesc_rec  "RIB_OTBDesc_REC" := NULL;
   L_MESSAGE_TYPE     varchar2(255);
   --
   L_dc_dest_id              NUMBER(10)     ;
   L_po_nbr                  NUMBER(10)      ;
   L_item_id                 VARCHAR2(25)   ;
   L_unit_qty                NUMBER(12,4)   ;
   L_receipt_xactn_type      VARCHAR2(255)  ;
   L_receipt_date            DATE           ;
   L_receipt_nbr             VARCHAR2(17)   ;
   L_asn_nbr                 VARCHAR2(30)   ;
   L_appt_nbr                NUMBER(9)      ;
   L_container_id            VARCHAR2(20)   ;
   L_distro_doc_type         VARCHAR2(255)  ;
   L_distro_nbr              NUMBER(10)     ;
   L_dest_id                 NUMBER(10)     ;
   L_to_disposition          VARCHAR2(10)   ;
   L_from_disposition        NUMBER(20,4)   ;
   L_unit_cost               NUMBER(12,4)   ;
   L_shipped_qty             NUMBER(12,4)   ;
   L_weight                  VARCHAR2(4)    ;
   L_weight_uom              VARCHAR2(255)  ;

   L_bol_no        VARCHAR2(30);
   L_return_code   VARCHAR2(30);
   L_alloc_no      NUMBER(10);
   L_qty_available NUMBER;
   L_qty_shipped   NUMBER;
   L_new_wh        NUMBER;

   --Get valid receipt details
   CURSOR c_receipts IS
   SELECT ssd.whse_location L_dc_dest_id
         ,ssd.order_no      L_po_nbr
         ,ssd.sku_char      L_item_id
         ,NVL(ssd.qty_to_be_received,0) L_unit_qty
         ,'R'               L_receipt_xactn_type
         ,ssd.rcv_date      L_receipt_date
         ,ssd.whse_receiver L_receipt_nbr
         ,ssd.carton_id     L_asn_nbr
         ,NULL              L_appt_nbr
         ,ssd.carton_id     L_container_id
         ,NULL              L_distro_doc_type
         ,NULL              L_distro_nbr
         ,ssd.store         L_dest_id
         ,NULL              L_to_disposition
         ,NULL              L_from_disposition
         ,ssd.units_shipd   L_shipped_qty
         ,NULL              L_weight
         ,NULL              L_weight_uom
    FROM smr_944_sqlload_err ssd
   WHERE NVL(ssd.qty_to_be_received,0) > 0
     AND ssd.carton_id = I_carton_id
  ORDER BY 3;

   CURSOR c_adjustments IS
   SELECT (ssd.whse_location) * 10 + 1 wh
         ,ssd.order_no      order_no
         ,ssd.sku_char      item
         ,NVL(ssd.exception_qty,0) adj_qty
         ,ssd.rcv_date      rcv_date
         ,ssd.vendor_performance_code
    FROM smr_944_sqlload_err ssd
   WHERE NVL(ssd.exception_qty,0) >  0
     AND ssd.carton_id = I_carton_id
   ORDER BY 2, 1, 3, 5;

  cursor c_unit_cost(I_order_no number,
                     I_item     varchar2)is
  select unit_cost
    from ordloc
   where order_no = I_order_no
     and item = I_item;

   --get all receipt records from which we need to make shipments.
   CURSOR c_bol_shipment is
   SELECT distinct
          ssd.rcv_date      ship_date
         ,ssd.whse_location FROM_loc
         ,'W'               FROM_loc_type
         ,ssd.store         to_loc
         ,'S'               to_loc_type
         ,NULL              courier
         ,NULL              no_boxes
         ,NULL              comments
         ,ssd.carton_id     carton_id
    FROM smr_944_sqlload_err ssd,
         ordhead oh
   WHERE oh.order_no = ssd.order_no
--     AND oh.pre_mark_ind = 'Y' --Only do for orders with allocations. --OLR V1.02 Deleted
     AND SSD.CARTON_ID = I_carton_id
     AND NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0) > 0
   ORDER BY ssd.carton_id;

   --get all receipt records from which we need to make shipsku records .
  CURSOR c_bol_shipsku(I_carton varchar2) is
   SELECT ssd.order_no      order_no
         ,ssd.sku_char      item
         ,ssd.upc_char      ref_item
         ,ssd.carton_id     carton_id
         ,sum(NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0)) ship_qty
         ,sysdate           last_update_datetime
     FROM smr_944_sqlload_err ssd
    WHERE ssd.carton_id = I_carton
    group by ssd.order_no
         ,ssd.sku_char
         ,ssd.upc_char
         ,ssd.carton_id
   ORDER BY ssd.order_no, ssd.sku_char;

  --get the allocation number associated with an order/item/store
  CURSOR c_distro_no(I_order_no number
                    ,I_item     varchar2
                    ,I_store    number)is
  SELECT ad.alloc_no, ad.qty_allocated - nvl(ad.qty_transferred,0) qty_available
    FROM alloc_header ah,
         alloc_detail ad
   WHERE ah.status in ('A','R','C')
     and ah.alloc_no = ad.alloc_no
     AND ah.order_no = I_order_no
     AND ah.item = I_item
     AND ad.to_loc = I_store
   order by decode(ah.status,'A',1,decode(ah.status,'R',2,3));

   CURSOR c_to_be_shipped(I_order_no number,
                          I_item varchar2,
                          I_store number,
                          I_wh number) IS
   SELECT sum(NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0)) to_be_shipped
     FROM smr_944_sqlload_err ssd
    WHERE NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0) >  0
      and ssd.carton_id = I_carton_id
      AND sku_char = I_item
      and order_no = I_order_no
      and store = I_store;

  cursor c_pre_mark_ind(I_order_no number) is
  select pre_mark_ind
    from ordhead
   where order_no = I_order_no;

  L_pre_mark_ind varchar2(1);

  cursor c_multiple_upc is
  select order_no, sku_char item, carton_id, count(distinct nvl(upc_char,' '))
    from smr_944_sqlload_err
   group by order_no, sku_char, carton_id
  having count(distinct nvl(upc_char,' ')) > 1;

  cursor c_order_ref_item(I_order_no number,
                          I_item     varchar2) is
  select ref_item
    from ordsku
   where order_no = I_order_no
     and item = I_item;

BEGIN

   sho(L_program);

   --set this so that trigger will not fire for the session running this program
   SMR_SDC_944.pv_alloc_no := -1;

   --No call to F_VALIDATE_CARTON, this is handled in calling form

   IF F_GENERATE_ARI_MESSAGES_CARTON(O_error_message,
                                     I_carton_id) = FALSE THEN
      return false;
   END IF;

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

   sho('=========================================================================================================');
   sho('PRE receipt loop');
   sho('=========================================================================================================');

   FOR rec in c_receipts loop

      sho('Receipt Process carton/'||L_container_id||' ord/'||rec.L_po_nbr||' item/'||rec.L_item_id||' loc/'||rec.L_dest_id);

      smr_order_rcv_sql.p_bill_to_loc := rec.L_dest_id;

      L_unit_cost := null;

      open  c_unit_cost(rec.L_po_nbr,
                        rec.L_item_id);
      fetch c_unit_cost into L_unit_cost;
      close c_unit_cost;

      if make_item_loc(O_error_message,
                       rec.L_item_id,
                       rec.L_dest_id ,
                       'S') = false then
          return false;
      end if;

      if make_item_loc(O_error_message,
                       rec.L_item_id,
                       rec.L_dc_dest_id ,
                       'W') = false then
          return false;
      end if;

      if CREATE_CARTON(O_error_message,
                       rec.L_container_id,
                       rec.L_dest_id) = false then
          return false;
      end if;

      L_distro_doc_type := NULL;
      L_distro_nbr := NULL;

      open  C_pre_mark_ind(rec.L_po_nbr);
      fetch C_pre_mark_ind into L_pre_mark_ind;
      close C_pre_mark_ind;

      L_pre_mark_ind := 'Y';  --OLR V1.02 INSERT

      IF L_pre_mark_ind = 'Y' THEN

         L_distro_doc_type := 'A';

         --
         IF explode_buyer_pack_allocation(O_error_message,
                                          rec.L_po_nbr,
                                          rec.L_item_id,
                                          9401,
                                          'Created for custom 944 receiving.',
                                          rec.L_dest_id,
                                          rec.L_unit_qty) = FALSE THEN
            return false;
         END IF;

         --check amount available and amount on receipt and allow more shipped than originally allocated
         open c_distro_no(rec.L_po_nbr
                         ,rec.L_item_id
                         ,rec.L_dest_id);
         fetch c_distro_no into L_distro_nbr, L_qty_available;
         close c_distro_no;

         open  c_to_be_shipped(rec.L_po_nbr,
                               rec.L_item_id,
                               rec.L_dest_id,
                               rec.L_dc_dest_id);
         fetch c_to_be_shipped into L_qty_shipped;
         close c_to_be_shipped;


         IF L_qty_shipped > L_qty_available THEN

            UPDATE alloc_detail
               SET qty_allocated = qty_allocated + (L_qty_shipped - L_qty_available),
                   qty_prescaled = qty_prescaled + (L_qty_shipped - L_qty_available)
             WHERE alloc_no = L_distro_nbr
               AND to_loc = rec.L_dest_id;

         END IF;


      END IF;

      update alloc_header
         set wh = (rec.L_dc_dest_id*10) + 1
       where alloc_no = L_distro_nbr;

      IF SMR_ORDER_RCV_SQL.PO_LINE_ITEM(O_error_message,
                                        rec.L_dc_dest_id,
                                        rec.L_po_nbr,
                                        rec.L_item_id,
                                        rec.L_unit_qty,
                                        rec.L_receipt_xactn_type,
                                        rec.L_receipt_date,
                                        rec.L_receipt_nbr,
                                        rec.L_asn_nbr,
                                        rec.L_appt_nbr,
                                        rec.L_container_id,
                                        L_distro_doc_type,
                                        to_number(L_distro_nbr),
                                        rec.L_dest_id,
                                        NVL(rec.L_to_disposition,
                                            rec.L_from_disposition),
                                        L_unit_cost,
                                        rec.L_shipped_qty,
                                        rec.L_weight,
                                        rec.L_weight_uom,
                                        'N') = FALSE then
         return false;
      END IF;

      IF L_distro_nbr is not NULL then

         update alloc_header
          --set wh = 9401 --OLR V1.03 deleted.
            set wh = nvl((select location from ordhead where order_no = alloc_header.order_no),9401) --OLR V1.03 inserted.
          where alloc_no = L_distro_nbr;

      END IF;

   END LOOP;

   --- Wrap up global/bulk processing
   IF SMR_ORDER_RCV_SQL.FINISH_PO_ASN_LOC_GROUP(O_error_message,
                                                L_rib_otb_tbl) = FALSE THEN
      return false;
   END IF;
   ---
   IF STOCK_ORDER_RCV_SQL.FINISH_TSF_ALLOC_GROUP(O_error_message) = FALSE THEN
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
   sho('PRE ADJUSTMENTS');
   sho('=========================================================================================================');

   --empty out cache of tran_data inserts
   if INVADJ_SQL.INIT_ALL (O_error_message) = FALSE then
      return false;
   end if;

   FOR rec in c_adjustments loop

      sho(' '||rec.vendor_performance_code||'/'||rec.wh||'/'||rec.item||'/'||rec.vendor_performance_code||'/'||rec.adj_qty||'/'||rec.order_no);

      if INVADJ_SQL.BUILD_PROCESS_INVADJ(O_error_message,
                                         rec.wh,
                                         rec.item,
                                         rec.vendor_performance_code, --I_reason
                                         rec.adj_qty,
                                         null,     --adj_weight
                                         null,     --I_adj_weight_uom
                                         'ATS',    --I_from_disposition,
                                         null,     --I_to_disposition,
                                         user,     --I_user_id,
                                         rec.rcv_date,
                                         rec.order_no,
                                         'P',
                                         NULL,     --I_wac
                                         NULL) = FALSE then --I_unit_retail

         return false;
      end if;

   END LOOP;

   --call flush
   if INVADJ_SQL.FLUSH_ALL (O_error_message) = FALSE then
      return false;
   end if;

   sho('=========================================================================================================');
   sho('PRE BOL');
   sho('=========================================================================================================');

   for rec_outer in c_multiple_upc loop
   --order_no, sku_char item, carton_id
      for rec_inner in c_order_ref_item(rec_outer.order_no,
                                        rec_outer.item) loop

          if rec_inner.ref_item is not null then

             update smr_944_sqlload_err ssd
                set upc_char  = rec_inner.ref_item
              where carton_id = rec_outer.carton_id
                and sku_char  = rec_outer.item;

          else

             update smr_944_sqlload_err ssd
                set upc_char  = (select min(ssd2.upc_char)
                                   from smr_944_sqlload_err ssd2
                                  where carton_id = rec_outer.carton_id
                                    and sku_char  = rec_outer.item
                                    and upc_char is not null)
              where carton_id = rec_outer.carton_id
                and sku_char  = rec_outer.item;

          end if;

      end loop;

   end loop;

   --create AND ship SDC ASNs
   for rec_shipment in c_bol_shipment loop

       NEXT_BILL_OF_LADING(O_ERROR_MESSAGE
                          ,L_bol_no
                          ,L_return_code);

       IF L_return_code = 'FALSE' THEN
          RETURN FALSE;
       END IF;

       sho('Insert BOL '||L_bol_no);

       INSERT INTO BOL_SHIPMENT (bol_no
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
                                ,rec_shipment.courier
                                ,rec_shipment.no_boxes
                                ,rec_shipment.comments);

      FOR rec_shipsku in c_bol_shipsku(rec_shipment.carton_id) LOOP

         L_distro_doc_type := NULL;
         L_distro_nbr := NULL;

         OPEN c_distro_no(rec_shipsku.order_no
                         ,rec_shipsku.item
                         ,rec_shipment.to_loc);
         FETCH c_distro_no INTO L_distro_nbr, L_qty_available;
         CLOSE c_distro_no;

         IF L_distro_nbr is not NULL then
            L_distro_doc_type := 'A';
         ELSE
            O_ERROR_MESSAGE := 'No allocation found for order '||rec_shipsku.order_no ||' Item '||rec_shipsku.item||' store '||rec_shipment.to_loc;
            RETURN FALSE;
         END IF;

         INSERT INTO bol_shipsku (BOL_NO
                                 ,DISTRO_NO
                                 ,DISTRO_TYPE
                                 ,ITEM
                                 ,REF_ITEM
                                 ,CARTON
                                 ,SHIP_QTY
                                 ,WEIGHT_EXPECTED
                                 ,WEIGHT_EXPECTED_UOM
                                 ,LAST_UPDATE_DATETIME)
                          VALUES (L_bol_no
                                 ,L_distro_nbr
                                 ,L_distro_doc_type
                                 ,rec_shipsku.ITEM
                                 ,rec_shipsku.REF_ITEM
                                 ,rec_shipment.CARTON_id
                                 ,rec_shipsku.SHIP_QTY
                                 ,NULL
                                 ,NULL
                                 ,rec_shipsku.LAST_UPDATE_DATETIME);

         UPDATE alloc_header
            SET wh = (rec_shipment.FROM_loc * 10 + 1)
          WHERE alloc_no = L_distro_nbr;

      sho('shipment Process carton/'||rec_shipsku.carton_id||' item/'||rec_shipsku.item||' loc/'||rec_shipment.to_loc||' wh/'||rec_shipment.from_loc);

      END LOOP;

      IF SHIP_DISTROS(O_ERROR_MESSAGE,
                      L_bol_no) = FALSE THEN
        return false;
      END IF;

      --OLR V1.06 Insert START
      delete from bol_shipsku where bol_no = L_bol_no;
      delete from bol_shipment where bol_no = L_bol_no;
      --OLR V1.06 Insert END


      --reset the allocation wh after we temporarily changed it to process this file.
      /*OLR V1.03 Deleted START
      UPDATE alloc_header
       SET wh = 9401
       WHERE wh in (9521,9531,9541);
      */

      --OLR V1.03 Insert START
      UPDATE alloc_header
         SET wh = nvl((select oh.location
                         from ordhead oh,
                              smr_944_sqlload_err sse
                        where oh.order_no = sse.order_no
                          and sse.carton_id = I_carton_id
                          and rownum < 2), 9401)
       WHERE wh in (9521,9531,9541)
         AND ORDER_NO = (select oh.order_no
                           from ordhead oh,
                                smr_944_sqlload_err sse
                          where oh.order_no = sse.order_no
                            and sse.carton_id = I_carton_id
                            and rownum < 2);
      --OLR V1.03 Insert END


   END LOOP;

   sho('=========================================================================================================');
   sho('update alc_alloc');
   sho('=========================================================================================================');

   UPDATE ALC_ALLOC SET STATUS = '3'
    WHERE status = '2'
      and ALLOC_ID IN (select aa.alloc_id
                         from alc_xref  ax,
                              alc_alloc aa,
                              smr_944_sqlload_err ssd
                        where ssd.order_no = ax.order_no
                          and ssd.sku_char = ax.item_id
                          and ax.alloc_id = aa.alloc_id
                          and ssd.carton_id = I_carton_id
                       union
                       select aa.alloc_id
                         from smr_944_sqlload_err ssd,
                              alc_alloc aa,
                              alc_xref  ax,
                              packitem_breakout pb,
                              item_master im
                        where ax.alloc_id = aa.alloc_id
                          and ssd.order_no = ax.order_no
                          and ssd.sku_char = pb.item
                          and pb.pack_no   = ax.item_id
                          and pb.pack_no   = im.item
                          and im.pack_type = 'B'
                          and ssd.carton_id = I_carton_id);

   sho('=========================================================================================================');
   sho('Delete smr_944_sqlload_err');
   sho('=========================================================================================================');

   DELETE FROM smr_944_sqlload_err
    WHERE carton_id = I_carton_id;

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
END F_PROCESS_CARTON;

------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA IN THE 944 FILE AS LOADED INTO TABLE smr_944_sqlload_data
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_FILE(O_error_message IN OUT VARCHAR2)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_FILE';

BEGIN

   sho(L_program);

   --Invalid Order
   INSERT INTO smr_944_sqlload_err
   SELECT ssd.*, null, '01-Jan-1900'
     FROM smr_944_sqlload_data_use ssd
    WHERE( NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = nvl(ssd.order_no,-1) and oh.status in ('A','C')))
       OR( NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item = nvl(ssd.sku_char,' '))
           AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item_parent = nvl(ssd.sku_char,' ') AND im.item = ssd.upc_char and ssd.upc_char is not null))
     --OR( NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = nvl(ssd.order_no,-1) and oh.supplier = nvl(ssd.vendor,-1)))
       OR( NOT EXISTS (SELECT 'X' FROM store st WHERE st.store = nvl(ssd.store,-1)))

       OR( NOT EXISTS (SELECT 'X' FROM store st WHERE st.store = nvl(ssd.store,-1)))
       OR( EXISTS (SELECT 'X'
                     FROM store st
                    WHERE st.store = nvl(ssd.store,-1)
                      and store_close_date is not null
                      and nvl(store_close_date, ssd.rcv_date ) - nvl(stop_order_days,0) <= ssd.rcv_date))
       OR( EXISTS (SELECT 'x'
                     FROM ordhead oh
                    WHERE ssd.order_no = oh.order_no
                      --AND oh.pre_mark_ind = 'Y' --OLR V1.02 Deleted
                      AND NOT EXISTS (SELECT 'x'
                                        from alloc_header ah
                                       where ah.order_no = ssd.order_no
                                         and ah.status in ('A','R','C'))))
       OR( NOT EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.sku_char,' ') and isp.supplier = nvl(ssd.vendor,-1))
           AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.sku_char,' ') and ol.order_no = nvl(ssd.order_no,-1)))
       OR( nvl(ssd.qty_to_be_received,-1) <= 0)
       OR( nvl(ssd.qty_to_be_received,-1) < nvl(ssd.exception_qty,0))
       OR( exists (select oh.order_no
                     from ordhead oh
                    where oh.order_no = ssd.order_no
                      and ssd.rcv_date > (oh.not_after_date + (select nvl(RECEIPT_AFTER_DAYS,0) from smr_system_options))))
       OR ( not exists (select 'x' from item_loc where item = ssd.sku_char and loc_type = 'S' and rownum < 2))
       OR ( exists (select 'x' from item_loc il where il.item = ssd.sku_char and il.loc = (ssd.whse_location*10+1))
            and not exists (select 'x' from item_loc_soh ils where ils.item = ssd.sku_char and ils.loc = (ssd.whse_location*10+1)))
       OR (exists (select 'x' from carton where carton = ssd.carton_id and location != ssd.store))
       OR (exists (select 'x'
                     from shipment sh
                    where asn = ssd.carton_id
                      and (
                           (sh.ship_origin = 6 and sh.status_code = 'R' and sh.ship_date > (get_vdate - 365) )
                           or
                           (sh.ship_origin = 4 and sh.ship_date > (get_vdate - 365))
                           or
                           (sh.ship_origin = 6 and sh.status_code = 'I' and sh.order_no != ssd.order_no)
                          )
                   ))
       OR (length(ssd.carton_id) != 20)
       OR SMR_CARTON_INT(ssd.carton_id) = 0 --OLR V1.04 INSERTED
       OR (not exists (select il.loc
                         from item_loc il,
                              wh wh
                        where il.item = nvl(ssd.sku_char,' ')
                          and wh.wh = il.loc
                          and wh in (9521,9531,9541,9401)
                          and il.loc_type = 'W'
                          and rownum < 2))
       OR EXISTS (select 'x'
                    from smr_944_sqlload_data_use ssd2
                   where ssd2.carton_id = ssd.carton_id
                   group by ssd2.carton_id
                  having count(distinct ssd2.rcv_date      ) > 1
                      or count(distinct ssd2.whse_location ) > 1
                      or count(distinct ssd2.store         ) > 1);

    IF SQL%ROWCOUNT = 0 then
       sho('no errors');
       return true;
    end if;

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = nvl(ssd.order_no,-1) and oh.status in ('A','C'));

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item = nvl(ssd.sku_char,' '))
      AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item_parent = nvl(ssd.sku_char,' ') AND im.item = ssd.upc_char and ssd.upc_char is not null);

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE NOT EXISTS (SELECT 'X' FROM store st WHERE st.store = nvl(ssd.store,-1));

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE EXISTS (SELECT 'X'
                    FROM store st
                   WHERE st.store = nvl(ssd.store,-1)
                     and store_close_date is not null
                     and nvl(store_close_date, ssd.rcv_date ) - nvl(stop_order_days,0) <= ssd.rcv_date);


   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE EXISTS (SELECT 'x'
                    FROM ordhead oh
                   WHERE ssd.order_no = oh.order_no
                     --AND oh.pre_mark_ind = 'Y' --OLR V1.02 Deleted
                     AND NOT EXISTS (SELECT 'x'
                                       from alloc_header ah
                                      where ah.order_no = ssd.order_no
                                        and ah.status in ('A','R','C'))
                     AND rownum = 1);

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE NOT EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = nvl(ssd.sku_char,' ') and isp.supplier = nvl(ssd.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = nvl(ssd.sku_char,' ') and ol.order_no = nvl(ssd.order_no,-1));

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE nvl(ssd.qty_to_be_received,-1) <= 0;

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE nvl(ssd.qty_to_be_received,-1) < nvl(ssd.exception_qty,0);

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE exists (select oh.order_no
                    from ordhead oh
                   where oh.order_no = ssd.order_no
                     and ssd.rcv_date > (oh.not_after_date + (select nvl(RECEIPT_AFTER_DAYS,0) from smr_system_options)));

    DELETE FROM smr_944_sqlload_data_use ssd
     WHERE not exists (select 'x' from item_loc where item = ssd.sku_char and loc_type = 'S' and rownum < 2);

    DELETE FROM smr_944_sqlload_data_use ssd
      where ( exists (select 'x' from item_loc il where il.item = ssd.sku_char and il.loc = (ssd.whse_location*10+1))
            and not exists (select 'x' from item_loc_soh ils where ils.item = ssd.sku_char and ils.loc = (ssd.whse_location*10+1)));

    DELETE FROM smr_944_sqlload_data_use ssd
     where (exists (select 'x' from carton where carton = ssd.carton_id and location != ssd.store));

    DELETE FROM smr_944_sqlload_data_use ssd
     where (exists (select 'x'
                      from shipment sh
                     where asn = ssd.carton_id
                       and (
                            (sh.ship_origin = 6 and sh.status_code = 'R' and sh.ship_date > (get_vdate - 365) )
                            or
                            (sh.ship_origin = 4 and sh.ship_date > (get_vdate - 365))
                            or
                            (sh.ship_origin = 6 and sh.status_code = 'I' and sh.order_no != ssd.order_no)
                           )
                   ));

    DELETE FROM smr_944_sqlload_data_use ssd
     where length(ssd.carton_id) != 20
        OR SMR_CARTON_INT(ssd.carton_id) = 0;  --OLR V1.04 INSERTED

    DELETE FROM smr_944_sqlload_data_use ssd
     where not exists (select il.loc
                         from item_loc il,
                              wh wh
                        where il.item = nvl(ssd.sku_char,' ')
                          and wh.wh = il.loc
                          and wh in (9521,9531,9541,9401)
                          and il.loc_type = 'W'
                          and rownum < 2);

    DELETE FROM smr_944_sqlload_data_use ssd
     where  EXISTS (select 'x'
                      from smr_944_sqlload_data_use ssd2
                     where ssd2.carton_id = ssd.carton_id
                     group by ssd2.carton_id
                    having count(distinct ssd2.rcv_date      ) > 1
                        or count(distinct ssd2.whse_location ) > 1
                        or count(distinct ssd2.store         ) > 1);

   INSERT INTO smr_944_sqlload_err
   SELECT ssd.*, null, '01-Jan-1900'
     FROM smr_944_sqlload_data_use ssd
    WHERE exists (select 'x'
                    from smr_944_sqlload_err sse
                   where sse.carton_id = ssd.carton_id);

   DELETE FROM smr_944_sqlload_data_use ssd
    WHERE exists (select 'x'
                    from smr_944_sqlload_err sse
                   where sse.carton_id = ssd.carton_id
                     and ERROR_DATE = '01-Jan-1900');

   --Invalid Order
   UPDATE smr_944_sqlload_err sse
      SET error_msg = 'Invalid Order'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = NVL(sse.order_no,-1) and oh.status in ('A','C'));

   --Invalid SKU
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,error_msg,error_msg||';') || 'Invalid Item'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item = NVL(sse.sku_char,' '))
      AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item_parent = NVL(sse.sku_char,' ') AND im.item = sse.upc_char and sse.upc_char is not null);

   --Invalid Store
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Store'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM store st WHERE st.store = NVL(sse.store,-1));

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Store Closing'
    WHERE error_date = '01-Jan-1900'
      AND EXISTS (SELECT 'X'
                    FROM store st
                   WHERE st.store = nvl(sse.store,-1)
                     and store_close_date is not null
                     and nvl(store_close_date, sse.rcv_date ) - nvl(stop_order_days,0) <= sse.rcv_date);

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'No allocation for order.'
    WHERE error_date = '01-Jan-1900'
      AND EXISTS (SELECT 'x'
                    FROM ordhead oh
                   WHERE sse.order_no = oh.order_no
                     --AND oh.pre_mark_ind = 'Y' --OLR V1.02 Deleted
                     AND NOT EXISTS (SELECT 'x'
                                       from alloc_header ah
                                      where ah.order_no = sse.order_no
                                        and ah.status in ('A','R','C'))
                     AND rownum = 1);

   --Invalid SKU for PO and supplier - already checked above that sku is valid in RMS
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Item for Order and supplier'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = NVL(sse.sku_char,' ') and isp.supplier = NVL(sse.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = NVL(sse.sku_char,' ') and ol.order_no = NVL(sse.order_no,-1) and ol.location = 9401);

   --Received QTY <= 0
   UPDATE smr_944_sqlload_err
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid quantity received'
    WHERE error_date = '01-Jan-1900'
      AND NVL(qty_to_be_received,-1) <= 0;

   --Exception QTY > qty_to_be_received
   UPDATE smr_944_sqlload_err
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Adjustment ('||exception_qty||') greater than receipt ('||qty_to_be_received||')'
    WHERE error_date = '01-Jan-1900'
      AND nvl(qty_to_be_received,0) < nvl(exception_qty,0);

   --Too long after not after date
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Receive Date'
    WHERE error_date = '01-Jan-1900'
      AND exists (select oh.order_no
                    from ordhead oh
                   where oh.order_no = sse.order_no
                     and sse.rcv_date > (oh.not_after_date + (select NVL(RECEIPT_AFTER_DAYS,0) from smr_system_options)));

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Item not at any store.'
    WHERE error_date = '01-Jan-1900'
      AND not exists (select 'x' from item_loc where item = sse.sku_char and loc_type = 'S' and rownum < 2);

  --missing rms item_loc_soh
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Missing item_loc_soh'
    WHERE error_date = '01-Jan-1900'
      AND ( exists (select 'x' from item_loc il where il.item = sse.sku_char and il.loc = (sse.whse_location*10+1))
            and not exists (select 'x' from item_loc_soh ils where ils.item = sse.sku_char and ils.loc = (sse.whse_location*10+1)));

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Carton exists at other store'
    WHERE error_date = '01-Jan-1900'
      AND (exists (select 'x' from carton where carton = sse.carton_id and location != sse.store));

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Carton already received/loaded'
    where error_date = '01-Jan-1900'
      AND (exists (select 'x'
                     from shipment sh
                    where asn = sse.carton_id
                      and (
                           (sh.ship_origin = 6 and sh.status_code = 'R' and sh.ship_date > (get_vdate - 365) )
                           or
                           (sh.ship_origin = 4 and sh.ship_date > (get_vdate - 365))
                           or
                           (sh.ship_origin = 6 and sh.status_code = 'I' and sh.order_no != sse.order_no)
                          )
                   ));

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Carton'
    WHERE error_date = '01-Jan-1900'
    --AND length(carton_id) != 20;            --OLR V1.04 Deleted
      AND (length(carton_id) != 20            --OLR V1.04 Inserted
           OR SMR_CARTON_INT(carton_id) = 0); --OLR V1.04 Inserted

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Item not at any valid wh'
    where error_date = '01-Jan-1900'
      AND not exists (select il.loc
                        from item_loc il,
                             wh wh
                       where il.item = nvl(sse.sku_char,' ')
                         and wh.wh = il.loc
                         and wh in (9521,9531,9541,9401)
                         and il.loc_type = 'W'
                         and rownum < 2);

   UPDATE smr_944_sqlload_err sse
      SET error_msg = 'Warehouse/Receipt date/store not unique for carton - contact support.'
    WHERE error_date = '01-Jan-1900'
      AND EXISTS (select 'x'
                   from smr_944_sqlload_err sse2
                  where sse2.carton_id = sse.carton_id
                    and sse2.error_date = '01-Jan-1900'
                  group by sse2.carton_id
                 having count(distinct sse2.rcv_date      ) > 1
                     or count(distinct sse2.whse_location ) > 1
                     or count(distinct sse2.store         ) > 1);

   UPDATE smr_944_sqlload_err sse
      SET error_msg = 'Other item in carton failed'
    WHERE error_date = '01-Jan-1900'
      AND error_msg is null
      AND exists (select 'x'
                    from smr_944_sqlload_err sse2
                   where sse2.carton_id = sse.carton_id
                     and sse2.error_msg is not null);

   UPDATE smr_944_sqlload_err sse
      SET error_date = get_vdate
    WHERE error_date = '01-Jan-1900';

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_VALIDATE_FILE;

-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_CARTON
-- Purpose:  USED TO VALIDATE THE DATA IN one carton in the error table
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_CARTON(O_error_message IN OUT VARCHAR2,
                           I_carton        IN OUT VARCHAR2,
                           O_valid         IN OUT BOOLEAN)
 RETURN boolean IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_CARTON';

BEGIN

   sho(L_program);

   O_valid := true;

   UPDATE smr_944_sqlload_err
      SET error_msg = NULL,
          error_date = NULL
    WHERE carton_id = I_carton;

   update smr_944_sqlload_err ssu
      set ssu.vendor = nvl((select oh.supplier
                              from ordhead oh
                             where oh.order_no = ssu.order_no),ssu.vendor)
    where carton_id = I_carton;

   --Invalid Order
   UPDATE smr_944_sqlload_err sse
      SET error_msg = 'Invalid Order'
    WHERE carton_id = I_carton
      AND NOT EXISTS (SELECT 'X' FROM ordhead oh WHERE oh.order_no = NVL(sse.order_no,-1) and oh.status in ('A','C'));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Invalid SKU
   UPDATE smr_944_sqlload_err sse
   SET error_msg = decode(error_msg,null,error_msg,error_msg||';') || 'Invalid Item'
    WHERE carton_id = I_carton
      AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item = NVL(sse.sku_char,' '))
      AND NOT EXISTS (SELECT 'X' FROM item_master im WHERE im.item_parent = NVL(sse.sku_char,' ') AND im.item = sse.upc_char and sse.upc_char is not null);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Invalid Store
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Store'
    WHERE carton_id = I_carton
      AND NOT EXISTS (SELECT 'X' FROM store st WHERE st.store = NVL(sse.store,-1));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Store Closing'
    WHERE carton_id = I_carton
      AND EXISTS ( SELECT 'X'
                    FROM store st
                   WHERE st.store = nvl(sse.store,-1)
                     and store_close_date is not null
                     and nvl(store_close_date, sse.rcv_date ) - nvl(stop_order_days,0) <= sse.rcv_date);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'No allocation for order'
    WHERE carton_id = I_carton
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
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Item for Order and supplier'
    WHERE carton_id = I_carton
      AND NOT EXISTS (SELECT 'X' FROM item_supplier isp where isp.item = NVL(sse.sku_char,' ') and isp.supplier = NVL(sse.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ordloc ol where ol.item = NVL(sse.sku_char,' ') and ol.order_no = NVL(sse.order_no,-1) and ol.location = 9401);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Received QTY <= 0
   UPDATE smr_944_sqlload_err
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid quantity received'
    WHERE carton_id = I_carton
      AND NVL(qty_to_be_received,-1) <= 0;

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Exception QTY > qty_to_be_received
   UPDATE smr_944_sqlload_err
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Adjustment ('||exception_qty||') greater than receipt ('||qty_to_be_received||')'
    WHERE carton_id = I_carton
      AND nvl(qty_to_be_received,0) < nvl(exception_qty,0);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   --Too long after not after date
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Receive Date'
    WHERE carton_id = I_carton
      AND exists (select oh.order_no
                    from ordhead oh
                   where oh.order_no = sse.order_no
                     and sse.rcv_date > (oh.not_after_date + (select NVL(RECEIPT_AFTER_DAYS,0) from smr_system_options)));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Item not at any store.'
    WHERE carton_id = I_carton
      AND not exists (select 'x' from item_loc where item = sse.sku_char and loc_type = 'S' and rownum < 2);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

  --missing rms item_loc_soh
   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Missing item_loc_soh'
    WHERE carton_id = I_carton
      AND ( exists (select 'x' from item_loc il where il.item = sse.sku_char and il.loc = (sse.whse_location*10+1))
            and not exists (select 'x' from item_loc_soh ils where ils.item = sse.sku_char and ils.loc = (sse.whse_location*10+1)));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Carton exists at other store'
    WHERE carton_id = I_carton
      AND (exists (select 'x' from carton where carton = sse.carton_id and location != sse.store));

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Carton already received/loaded'
    WHERE carton_id = I_carton
      AND (exists (select 'x'
                     from shipment sh
                    where asn = sse.carton_id
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

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Invalid Carton'
    WHERE carton_id = I_carton
    --AND length(carton_id) != 20;            --OLR V1.04 Deleted
      AND (length(carton_id) != 20            --OLR V1.04 Inserted
           OR SMR_CARTON_INT(carton_id) = 0); --OLR V1.04 Inserted

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = decode(error_msg,null,'',error_msg||';') || 'Item not at any valid wh'
    where carton_id = I_carton
      and not exists (select il.loc
                        from item_loc il,
                             wh wh
                       where il.item = nvl(sse.sku_char,' ')
                         and wh.wh = il.loc
                         and wh in (9521,9531,9541,9401)
                         and il.loc_type = 'W'
                         and rownum < 2);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = 'Warehouse/Receipt date/store not unique for carton - contact support.'
    WHERE carton_id = I_carton
      AND EXISTS (select 'x'
                   from smr_944_sqlload_err sse2
                  where sse2.carton_id = sse.carton_id
                  group by sse2.carton_id
                 having count(distinct sse2.rcv_date      ) > 1
                     or count(distinct sse2.whse_location ) > 1
                     or count(distinct sse2.store         ) > 1);

   IF SQL%ROWCOUNT > 0 THEN
      O_valid := FALSE;
   END IF;

   UPDATE smr_944_sqlload_err sse
      SET error_msg = 'Other item in carton failed'
    WHERE carton_id = I_carton
      AND error_msg is null
      AND exists (select 'x'
                    from smr_944_sqlload_err sse2
                   where sse2.carton_id = sse.carton_id
                     and sse2.error_msg is not null);

   update smr_944_sqlload_err
      set error_date = get_vdate
    where carton_id = I_carton
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

-------------------------------------------------------------------------------------------
-- FUNCTION: F_ONLY_CARTON_ERROR_IS_RCPT_DT
-- Purpose:  O_valid = true if only error is rcpt_date
--------------------------------------------------------------------------------------------
FUNCTION F_ONLY_CARTON_ERROR_IS_RCPT_DT(O_error_message IN OUT VARCHAR2,
                                        I_carton        IN OUT VARCHAR2,
                                        O_valid         IN OUT BOOLEAN)

RETURN BOOLEAN IS
  L_program VARCHAR2(61) := package_name || '.F_ONLY_CARTON_ERROR_IS_RCPT_DT';
  l_errors number := 0;

  CURSOR c_errors is
  SELECT count(*)
    FROM smr_944_sqlload_err
   WHERE carton_id = I_carton
     AND error_msg not in ('Invalid Receive Date','Other item in carton failed');

BEGIN

   open  c_errors;
   fetch c_errors into l_errors;
   close c_errors;

   if l_errors = 0 then
      O_valid := true;
   else
      O_valid := false;
   end if;

   return true;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('ERR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END F_ONLY_CARTON_ERROR_IS_RCPT_DT;

---------------------------------------------------------------------------------------------
-- Function : GET_NOT_AFTER_DATE
-- Purpose  : This function will return the not after date for a given order number.
---------------------------------------------------------------------------------------------
FUNCTION GET_NOT_AFTER_DATE(O_error_message   IN OUT  VARCHAR2,
                            O_not_after_date  IN OUT  ORDHEAD.NOT_AFTER_DATE%TYPE,
                            I_order_no        IN      ORDHEAD.ORDER_NO%TYPE)
   RETURN BOOLEAN IS
   L_program VARCHAR2(61) := package_name || '.GET_NOT_AFTER_DATE';

   CURSOR c_receipt_dates is
   SELECT not_after_date
     FROM ordhead
    WHERE order_no = I_order_no;

BEGIN

   open  C_RECEIPT_DATES;
   fetch C_RECEIPT_DATES into O_not_after_date;
   close C_RECEIPT_DATES;
   ---
   return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      return FALSE;
END GET_NOT_AFTER_DATE;
END;
/