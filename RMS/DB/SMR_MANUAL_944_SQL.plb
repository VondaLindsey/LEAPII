CREATE OR REPLACE PACKAGE BODY SMR_MANUAL_944_SQL AS

-------------------------------------------------------------------------------------------
-- Module Name: SMR_MANUAL_944_SQL.pls
-- Description: Package for Location List Upload
--
-- Modification History:
-- Version Date        Developer  Issue     Description
-- ======= =========== ========== ======    ===================
-- 1.00    12-Apr-2012 B.Chin     CR00313   Initial version. (Function PROCESS_CARTON added
--                                          by P.Dinsdale, other minor updates.)
-- 1.01    09-Jul-2012 P.Dinsdale           Added INSERT_USER_RECEIPT_ITEM
-- 1.02    27-Nov-2012 P.Dinsdale           Only get valid items for shipment
-- 1.03    22-Feb-2012 P.Dinsdale IMS150402 Consider carton when inserting into SMR_944_SQLLOAD_ERR
--                                          Consider allocation status in allocation application
-- 1.04    06-Oct-15   Murali     Leap 2    Modified as part of Leap. Remove the hard coded validation
--                                          and replace the same to be based on wh types.
--                                          The Screen allows to recieve a Carton related to PO and also 
--                                          creates a shipment to the store for the same.
-------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------
-- Function    : INSERT_RECEIPT_ITEM
-- Purpose     : This function will populate the multi record block by using the data inserted by the user.
--------------------------------------------------------------------------------------------
FUNCTION INSERT_RECEIPT_ITEM  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                               I_order_no             IN       ORDHEAD.ORDER_NO%TYPE,
                               I_wh                   IN       ALLOC_HEADER.WH%TYPE,
                               I_store                IN       STORE.STORE%TYPE,
                               I_carton               IN       DUMMY_CARTON_STAGE.CARTON%TYPE
                              )
   return BOOLEAN IS

   L_program   VARCHAR2(64)   := 'SMR_MANUAL_944_SQL.INSERT_RECEIPT_ITEM';
   L_qty_ordered NUMBER;

   --OLR V1.02 Inserted START
   --If there are multiple shipments and one is in status I and the other is in status C, only use the shipment in status I.
   CURSOR c_multiple_shipments is
   SELECT asn
     FROM shipment
    WHERE asn is not null
      AND ship_origin = 6
      AND status_code in ('I','C')
      AND asn = I_carton
      AND shipment.to_loc = I_wh
      AND shipment.bill_to_loc = I_store
      AND shipment.order_no = I_order_no
    GROUP BY asn
   HAVING COUNT(DISTINCT status_code) > 1;

   L_multiple_shipments varchar2(30);
   L_status_code_2 varchar2(1) := 'C';
   --OLR V1.02 Inserted START

   cursor C_item is
     select item
          , qty_expected
       from shipsku
           ,shipment --OLR V1.02 Inserted
      where carton = I_carton
        --OLR V1.02 Inserted START
        and shipment.shipment = shipsku.shipment
        and shipment.ship_origin = 6
        and shipment.status_code in ('I',L_status_code_2)
        and shipment.to_loc = I_wh
        and shipment.bill_to_loc = I_store
        and shipment.order_no = I_order_no;
        --OLR V1.02 Inserted END

    /* OLR V1.03 Delete START
    cursor C_qty_ordered(P_item ITEM_MASTER.ITEM%TYPE) is
      select sum(nvl(ail.allocated_qty,0) * nvl(pb.pack_item_qty, 1)) allocated
        from alc_alloc aa
           , alc_item_loc ail
           , (select distinct alloc_id
                from alc_xref
               where order_no = I_order_no) ax
           , store st
           , (select pb.pack_no
                   , pb.item
                   , pb.pack_item_qty
                from item_master im
                   , packitem_breakout pb
               where im.pack_Type = 'B'
                 and im.item = pb.pack_no) pb
--             , (select distinct item
--                  from sdc_po_research_gtt) gtt
         where aa.alloc_id        = ax.alloc_id
           and ail.alloc_id       = aa.alloc_id
           and st.store           = ail.location_id
           and ail.item_id        = pb.pack_no (+)
           and ail.order_no       = I_order_no
           and st.default_wh      = nvl((I_wh*10)+1, st.default_wh)
           and aa.status in ('2', '3', '4')
           and nvl(pb.item
                   , ail.item_id) = P_item
           and ail.location_id    = I_store;
--           and gtt.item           = P_item;
     --OLR V1.03 Delete END */

    -- OLR V1.03 Insert START
    cursor C_QTY_ORDERED(P_item ITEM_MASTER.ITEM%TYPE) is
    select sum(nvl(ail.ALLOCATED_QTY,0) * nvl(pb.pack_item_qty,1)) allocated
      from alc_alloc aa,
           alc_item_loc ail,
           (select distinct alloc_id from alc_xref where order_no = I_order_no) ax,
           store st,
           packitem_breakout pb
     where aa.alloc_id   = ax.alloc_id
       and ail.alloc_id  = aa.alloc_id
       and st.store      = ail.location_id
       and ail.item_id   = pb.pack_no (+)
       and ail.order_no  = I_order_no
       and st.default_wh = nvl((I_wh*10)+1,st.default_wh)
       and ( --Allocation approved/extracted
             aa.status in ('2','3')
             or
             --Allocation closed and shipped against.
             ( aa.status = '4'
               and exists (select 'x'
                             from alc_xref     ax2,
                                  alloc_detail ad
                            where ax2.order_no = I_order_no
                              and ax2.alloc_id = aa.alloc_id
                              and ax2.xref_alloc_no = ad.alloc_no
                              and ad.qty_distro is not null))
             or
             -- allocation closed after order
             ( aa.status = '4'
               and exists (select 'x'
                             from alc_alloc_au a_au,
                                  alc_xref     ax2,
                                  ordhead      oh
                            where ax2.order_no = I_order_no
                              and ax2.alloc_id = aa.alloc_id
                              and ax2.alloc_id = a_au.alloc_id
                              and ax2.order_no = oh.order_no
                              and oh.close_date is not null
                              and a_au.n_status = '4'
                              and a_au.o_status != '4'
                              and a_au.modify_date >= oh.close_date))
           )
       and nvl(pb.item,ail.item_id) = P_item
       and ail.location_id = I_store;
    -- OLR V1.03 Insert END

     cursor C_qty_allocation(P_item ITEM_MASTER.ITEM%TYPE) is
       select sum(nvl(ad.qty_ALLOCATED,0) * nvl(pb.pack_item_qty,1)) allocated
         from alloc_header ah
            , alloc_detail ad
            , store st
            , (select pb.pack_no
                    , pb.item
                    , pb.pack_item_qty
                 from item_master im
                    , packitem_breakout pb
                where im.pack_type = 'B'
                  and im.item = pb.pack_no) pb
--            , (select distinct item
--                 from sdc_po_research_gtt) gtt
        where ah.alloc_no    = ad.alloc_no
          and st.store       = ad.to_loc
          and ah.item        = pb.pack_no (+)
          and ah.order_no    = I_order_no
          and st.default_wh  = nvl((I_wh*10) +1, st.default_wh)
          and ah.status      = 'A'
          and nvl(pb.item
                  , ah.item) = P_item
          and ad.to_loc      = I_store;
--          and gtt.item       = P_item;

   BEGIN

   open  c_multiple_shipments;
   fetch c_multiple_shipments into L_multiple_shipments;
   close c_multiple_shipments;

   if L_multiple_shipments is not null then
      L_status_code_2 := 'I';
   end if;

   --OLR V1.03 Insert START
   delete from smr_manual_944 sm944
    WHERE sm944.carton = I_carton;
   --OLR V1.03 Insert END

   for R_rec_id in C_item loop

     open  C_qty_ordered(R_rec_id.Item);
     fetch C_qty_ordered into L_qty_ordered;
     close C_qty_ordered;

     if nvl(L_qty_ordered,0) = 0 then
       open  C_qty_allocation(R_rec_id.Item);
       fetch C_qty_allocation into L_qty_ordered;
       close C_qty_allocation;
     end if;

     insert into smr_manual_944 (RECEIPT_KEY
                                ,ORDER_NO
                                ,WH
                                ,STORE
                                ,CARTON
                                ,ITEM
                                ,QTY_ORDERED
                                ,QTY_RECEIVED
                                ,QTY_EXPECTED
                                ,QTY_DAMAGED
                                ,DAMAGED_CODE
                                ,RCV_DATE
                                )
                         select smr_receipt_key_seq.nextval
                                ,I_order_no
                                ,I_wh
                                ,I_store
                                ,I_carton
                                ,R_rec_id.item
                                ,L_qty_ordered
                                ,NULL
                                ,R_rec_id.qty_expected
                                ,NULL
                                ,NULL
                                ,SYSDATE
                           from dual;
   end loop;

   return TRUE;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;



END INSERT_RECEIPT_ITEM;

--OLR V1.01 Insert START
--------------------------------------------------------------------------------------------
-- Function    : INSERT_USER_RECEIPT_ITEM
-- Purpose     : This function will populate the multi record block by using the data inserted by the user.
--             : Used when the carton is chosen by the user.
--------------------------------------------------------------------------------------------
FUNCTION INSERT_USER_RECEIPT_ITEM  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                                    I_order_no             IN       ORDHEAD.ORDER_NO%TYPE,
                                    I_wh                   IN       ALLOC_HEADER.WH%TYPE,
                                    I_store                IN       STORE.STORE%TYPE,
                                    I_carton               IN       DUMMY_CARTON_STAGE.CARTON%TYPE
                                   )
   return BOOLEAN IS

   L_program   VARCHAR2(64)   := 'SMR_MANUAL_944_SQL.INSERT_USER_RECEIPT_ITEM';
   L_qty_ordered NUMBER;
   L_qty_transferred number;

   L_dummy varchar2(20);
   L_dummy_num number;

   cursor c_carton_exists is
   select carton
     from carton
    where carton = I_carton;

   cursor C_item is
     select distinct nvl(pb.item,os.item) item
       from ordsku os,
            packitem_breakout pb
      where os.item = pb.pack_no (+)
        and os.order_no = I_order_no;

    /* OLR V1.03 Delete START
    cursor C_qty_ordered(P_item ITEM_MASTER.ITEM%TYPE) is
      select sum(nvl(ail.allocated_qty,0) * nvl(pb.pack_item_qty, 1)) allocated
        from alc_alloc aa
           , alc_item_loc ail
           , (select distinct alloc_id
                from alc_xref
               where order_no = I_order_no) ax
           , store st
           , (select pb.pack_no
                   , pb.item
                   , pb.pack_item_qty
                from item_master im
                   , packitem_breakout pb
               where im.pack_Type = 'B'
                 and im.item = pb.pack_no) pb
--             , (select distinct item
--                  from sdc_po_research_gtt) gtt
         where aa.alloc_id        = ax.alloc_id
           and ail.alloc_id       = aa.alloc_id
           and st.store           = ail.location_id
           and ail.item_id        = pb.pack_no (+)
           and ail.order_no       = I_order_no
           and st.default_wh      = nvl((I_wh*10)+1, st.default_wh)
           and aa.status in ('2', '3', '4')
           and nvl(pb.item
                   , ail.item_id) = P_item
           and ail.location_id    = I_store;
--           and gtt.item           = P_item;
     --OLR V1.03 Delete END */

    -- OLR V1.03 Insert START
    cursor C_QTY_ORDERED(P_item ITEM_MASTER.ITEM%TYPE) is
    select sum(nvl(ail.ALLOCATED_QTY,0) * nvl(pb.pack_item_qty,1)) allocated
      from alc_alloc aa,
           alc_item_loc ail,
           (select distinct alloc_id from alc_xref where order_no = I_order_no) ax,
           store st,
           packitem_breakout pb
     where aa.alloc_id   = ax.alloc_id
       and ail.alloc_id  = aa.alloc_id
       and st.store      = ail.location_id
       and ail.item_id   = pb.pack_no (+)
       and ail.order_no  = I_order_no
       and st.default_wh = nvl((I_wh*10)+1,st.default_wh)
       and ( --Allocation approved/extracted
             aa.status in ('2','3')
             or
             --Allocation closed and shipped against.
             ( aa.status = '4'
               and exists (select 'x'
                             from alc_xref     ax2,
                                  alloc_detail ad
                            where ax2.order_no = I_order_no
                              and ax2.alloc_id = aa.alloc_id
                              and ax2.xref_alloc_no = ad.alloc_no
                              and ad.qty_distro is not null))
             or
             -- allocation closed after order
             ( aa.status = '4'
               and exists (select 'x'
                             from alc_alloc_au a_au,
                                  alc_xref     ax2,
                                  ordhead      oh
                            where ax2.order_no = I_order_no
                              and ax2.alloc_id = aa.alloc_id
                              and ax2.alloc_id = a_au.alloc_id
                              and ax2.order_no = oh.order_no
                              and oh.close_date is not null
                              and a_au.n_status = '4'
                              and a_au.o_status != '4'
                              and a_au.modify_date >= oh.close_date))
           )
       and nvl(pb.item,ail.item_id) = P_item
       and ail.location_id = I_store;
    -- OLR V1.03 Insert END

     cursor C_qty_allocation(P_item ITEM_MASTER.ITEM%TYPE) is
       select sum(nvl(ad.qty_ALLOCATED,0) * nvl(pb.pack_item_qty,1)) allocated,
              sum(nvl(ad.qty_transferred,0) * nvl(pb.pack_item_qty,1)) transferred
         from alloc_header ah
            , alloc_detail ad
            , store st
            , (select pb.pack_no
                    , pb.item
                    , pb.pack_item_qty
                 from item_master im
                    , packitem_breakout pb
                where im.pack_type = 'B'
                  and im.item = pb.pack_no) pb
--            , (select distinct item
--                 from sdc_po_research_gtt) gtt
        where ah.alloc_no    = ad.alloc_no
          and st.store       = ad.to_loc
          and ah.item        = pb.pack_no (+)
          and ah.order_no    = I_order_no
          and st.default_wh  = nvl((I_wh*10) +1, st.default_wh)
          and ah.status      = 'A'
          and nvl(pb.item
                  , ah.item) = P_item
          and ad.to_loc      = I_store;
--          and gtt.item       = P_item;


   --OLR V1.02 Insert START
   CURSOR c_carton_exists_in_err is
   select 'x'
     from SMR_944_SQLLOAD_ERR
    where carton_id = I_carton;

   L_carton_exists_in_err varchar2(255);
   --OLR V1.02 Insert END

BEGIN

   --OLR V1.02 Insert START
   open  c_carton_exists_in_err;
   fetch c_carton_exists_in_err into L_carton_exists_in_err;
   close c_carton_exists_in_err;

   if nvl(L_carton_exists_in_err,' ') = 'x' then
      O_error_message := 'Carton exists in correction table. Please use SMR Receipt Correction form to fix or delete the carton first.';
      return false;
   end if;
   --OLR V1.02 Insert START

   open  c_carton_exists;
   fetch c_carton_exists into L_dummy;
   close c_carton_exists;

   if L_dummy is not null then
      O_error_message := 'Carton already exists';
      return false;
   end if;

   --OLR V1.03 Insert START
   delete from smr_manual_944 sm944
    WHERE sm944.carton = I_carton;
   --OLR V1.03 Insert END

   for R_rec_id in C_item loop

     open  C_qty_ordered(R_rec_id.Item);
     fetch C_qty_ordered into L_qty_ordered;
     close C_qty_ordered;

     if nvl(L_qty_ordered,0) = 0 then
       open  C_qty_allocation(R_rec_id.Item);
       fetch C_qty_allocation into L_qty_ordered, L_qty_transferred;
       close C_qty_allocation;
     else
       open  C_qty_allocation(R_rec_id.Item);
       fetch C_qty_allocation into L_dummy_num, L_qty_transferred;
       close C_qty_allocation;
     end if;

     insert into smr_manual_944 (RECEIPT_KEY
                                ,ORDER_NO
                                ,WH
                                ,STORE
                                ,CARTON
                                ,ITEM
                                ,QTY_ORDERED
                                ,QTY_RECEIVED
                                ,QTY_EXPECTED
                                ,QTY_DAMAGED
                                ,DAMAGED_CODE
                                ,RCV_DATE
                                )
                         select smr_receipt_key_seq.nextval
                                ,I_order_no
                                ,I_wh
                                ,I_store
                                ,I_carton
                                ,R_rec_id.item
                                ,L_qty_ordered
                                ,NULL
                                ,L_qty_ordered - L_qty_transferred
                                ,NULL
                                ,NULL
                                ,SYSDATE
                           from dual;
   end loop;

   return TRUE;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;



END INSERT_USER_RECEIPT_ITEM;
--OLR V1.01 Insert END

--------------------------------------------------------------------------------------------
-- Function    : VALIDATE_ORDER_NO
-- Purpose     : This function will validate the order number. The number must have WHS 9401
--------------------------------------------------------------------------------------------
FUNCTION VALIDATE_ORDER_NO  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                             I_order_no             IN       ORDHEAD.ORDER_NO%TYPE
                            )
   return BOOLEAN IS

   L_program         VARCHAR2(64):= 'SMR_MANUAL_944_SQL.VALIDATE_ORDER_NO';
   L_valid_order_no  VARCHAR2(1) := 'N';

   cursor C_order_no is
     select 'Y'
       from ordloc
      where order_no = I_order_no
   --     and location = '9401'
       and location in (select wh from wh_attributes w where w.wh_type_code in ('BK','PA','XD'))
        and loc_type = 'W';

   BEGIN

    open C_order_no;
   fetch C_order_no into L_valid_order_no;

   if L_valid_order_no = 'N' then
     O_error_message := SQL_LIB.CREATE_MSG('INV_ORDER_NO',
                                             NULL,
                                             NULL,
                                             NULL);
     return FALSE;
   end if;

   return TRUE;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;

END VALIDATE_ORDER_NO;

--------------------------------------------------------------------------------------------
-- Function    : VALIDATE_SDC_LOCATION
-- Purpose     : This function will validate the SDC location. Valid values will be 952, 953, 954
--------------------------------------------------------------------------------------------
FUNCTION VALIDATE_SDC_LOCATION  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                                 I_wh                   IN       WH.WH%TYPE
                                )
   return BOOLEAN IS

   L_program         VARCHAR2(64):= 'SMR_MANUAL_944_SQL.VALIDATE_SDC_LOCATION';

   --V 1.04  Start
   L_exists          Varchar2(1);
   Cursor C_valid_wh is
      select 'X'
        from wh , 
             wh_attributes w 
          where w.wh = wh.wh 
            and w.wh_type_code in ('XD','PA')
            and wh.physical_wh = I_wh;
   --V 1.04 End
   BEGIN
   
   --V 1.04  Start
   open C_valid_wh ;
   
   fetch C_valid_wh into L_exists;
   
   close C_valid_wh;

--   if I_wh not in ('952', '953', '954') then
   if L_exists is null then
   --V 1.04 End  
     O_error_message := SQL_LIB.CREATE_MSG('SMR_INV_SDC',
                                             NULL,
                                             NULL,
                                             NULL);
     return FALSE;
   end if;

   return TRUE;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;

END VALIDATE_SDC_LOCATION;

--------------------------------------------------------------------------------------------
-- Function    : VALIDATE_STORE
-- Purpose     : This function will validate the store.
--               Valid values will have a physical wh equal to the SDC entered
--------------------------------------------------------------------------------------------
FUNCTION VALIDATE_STORE  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                          I_wh                   IN       WH.WH%TYPE,
                          I_store                IN       STORE.STORE%TYPE
                         )
   return BOOLEAN IS

   L_program         VARCHAR2(64):= 'SMR_MANUAL_944_SQL.VALIDATE_STORE';
   L_valid_store     VARCHAR2(1) := 'N';

   cursor C_store is
     select 'Y'
       from store st
          , wh    wh
      where st.default_wh  = wh.wh
        and wh.physical_wh = I_wh
        and st.store       = I_store;

   BEGIN

    open C_store;
   fetch C_store into L_valid_store;
   close C_store;

   if L_valid_store = 'N' then
     O_error_message := SQL_LIB.CREATE_MSG('INV_STORE',
                                             NULL,
                                             NULL,
                                             NULL);
     return FALSE;
   end if;

   return TRUE;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;

END VALIDATE_STORE;

--------------------------------------------------------------------------------------------
-- Function    : VALIDATE_CARTON
-- Purpose     : This function will validate the carton.
--               Valid values will be checked against the other values entered
--------------------------------------------------------------------------------------------
FUNCTION VALIDATE_CARTON (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                          I_order_no             IN       ORDHEAD.ORDER_NO%TYPE,
                          I_wh                   IN       WH.WH%TYPE,
                          I_store                IN       STORE.STORE%TYPE,
                          I_carton               IN       SHIPSKU.CARTON%TYPE
                         )
   RETURN BOOLEAN IS

   L_program         VARCHAR2(64):= 'SMR_MANUAL_944_SQL.VALIDATE_CARTON';

   L_valid_carton    VARCHAR2(1) := 'N';

   cursor C_carton is
     select 'Y'
       from shipsku shk
          , shipment sh
      where sh.shipment         = shk.shipment
        and sh.order_no         = I_order_no
        and sh.to_loc           = I_wh
        and sh.to_loc_type      = 'W'
     --   and sh.bill_to_loc      = I_store -- V 1.04 Start
     --   and sh.bill_to_loc_type = 'S' -- V 1.04 Start
        and shk.actual_receiving_store = I_store -- V 1.04 Start
        and sh.ship_origin      = '6'
      --and sh.status_code      = 'I'        --OLR V1.02 Deleted
        and sh.status_code      in ('I','C') --OLR V1.02 Deleted
        and shk.carton          = I_carton
        and shk.qty_received    is null
        --OLR V1.02 Insert START
        and not exists (select 'x'
                          from shipment sh2,
                               shipsku  sk2
                         where sh2.shipment = sk2.shipment
                           and sh2.order_no = I_order_no
                           and sk2.carton = I_carton
                           and nvl(sk2.qty_received,0) > 0);
        --OLR V1.02 Insert END


   --OLR V1.01 Insert START
   CURSOR c_carton_exists_in_err is
   select 'x'
     from SMR_944_SQLLOAD_ERR
    where carton_id = I_carton
    --V 1.04  Start
    union 
   select 'x'
     from SMR_WH_RECEIVING_ERROR
    where carton = I_carton;
    --V 1.04  End

   L_carton_exists_in_err varchar2(255);
   --OLR V1.01 Insert END

BEGIN

   --OLR V1.01 Insert START
   open  c_carton_exists_in_err;
   fetch c_carton_exists_in_err into L_carton_exists_in_err;
   close c_carton_exists_in_err;

   if nvl(L_carton_exists_in_err,' ') = 'x' then
      O_error_message := 'Carton exists in correction table. Please use SMR Receipt Correction form to fix or delete the carton first.';
      return false;
   end if;
   --OLR V1.01 Insert START

   open  C_carton;
   fetch C_carton into L_valid_carton;
   close C_carton;

   if L_valid_carton = 'N' then
      O_error_message := SQL_LIB.CREATE_MSG('INV_CARTON',
                                             NULL,
                                             NULL,
                                             NULL);
      return FALSE;
   end if;

   return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
   return FALSE;

END VALIDATE_CARTON;

--------------------------------------------------------------------------------------------
-- Function    : VALIDATE_DAMAGE_CODE
-- Purpose     : This function will validate the damage_code.
--               Valid values will be selected from inv_adj_reason
--------------------------------------------------------------------------------------------

FUNCTION VALIDATE_DAMAGE_CODE  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                                I_damaged_code         IN       INV_ADJ_REASON.REASON%TYPE
                         )
   return BOOLEAN IS

   L_program            VARCHAR2(64):= 'SMR_MANUAL_944_SQL.VALIDATE_DAMAGE_CODE';

   L_valid_damage_code  VARCHAR2(1) := 'N';

   cursor C_damage_code is
     select 'Y'
       from inv_adj_reason
      where reason = I_damaged_code
        and reason IN (501,502,503,504,511);

   BEGIN

   open C_damage_code;
   fetch C_damage_code into L_valid_damage_code;
   close C_damage_code;

   if L_valid_damage_code = 'N' then
     O_error_message := SQL_LIB.CREATE_MSG('INVALID DAMAGE CODE',
                                             NULL,
                                             NULL,
                                             NULL);
     return FALSE;
   end if;

   return TRUE;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;

END VALIDATE_DAMAGE_CODE;

--------------------------------------------------------------------------------------------
-- Function    : PROCESS_CARTON
-- Purpose     : This function will process carton I_carton
--------------------------------------------------------------------------------------------
FUNCTION PROCESS_CARTON  (O_error_message        IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                          I_fail                 IN OUT   BOOLEAN,
                          I_carton               IN       DUMMY_CARTON_STAGE.CARTON%TYPE)
   return BOOLEAN is

   L_program VARCHAR2(64):= 'SMR_MANUAL_944_SQL.PROCESS_CARTON';
   L_valid boolean := true;
   L_carton varchar2(20);

   CURSOR c_only_error_is_rcv_date IS
   SELECT count(*)
     FROM SMR_944_SQLLOAD_ERR
    where carton_id = I_carton
      and error_msg != 'Other item in carton failed'
      and error_msg != 'Invalid Receive Date'
    -- V 1.04 Start
   union
   SELECT count(*)
     FROM SMR_WH_RECEIVING_ERROR
    where carton = I_carton
      and error_msg != 'Other item in carton failed'
      and error_msg != 'Invalid Receive Date';
   -- V 1.04 End
   
   L_only_error_is_rcv_date number;

   BEGIN

   L_carton := I_carton;

   INSERT INTO SMR_944_SQLLOAD_ERR
   SELECT sm944.receipt_key  whse_receiver,
          sm944.wh           whse_location,
          sm944.order_no     order_no,
          sm944.store        store,
          NULL               file_date,
          NULL               transaction_number,
          NULL               load_date,
          NULL               physical_adj,
          oh.supplier        vendor,
          sm944.item         sku,
          NULL               upc_article,
          NULL               vpn,
          sm944.qty_received qty_to_be_received,
          get_vdate          rcv_date,
          sm944.carton       carton_id,
          NULL               shipment_id,
          qty_expected       units_shipd,
          NULL               unit_retail,
          NULL               condition_code,
          sm944.damaged_code vendor_performance_code,
          sm944.qty_damaged  exception_qty,
          NULL               po_updated,
          sm944.item         sku_char,
          NULL               upc_char,
          NULL               error_msg,
          NULL               error_date
     FROM smr_manual_944 sm944,
          ordhead oh
    WHERE sm944.order_no = oh.order_no
      AND sm944.carton = L_carton
      AND NVL(sm944.qty_received,0) > 0;

   IF SQL%ROWCOUNT = 0 THEN
      O_error_message := 'No valid receipt qty to process';
      return false;
   END IF;

   IF SMR_SDC_944.F_VALIDATE_CARTON(O_error_message,
                                    L_carton       ,
                                    L_valid        ) = FALSE THEN
      return false;
   END IF;

   IF NOT L_valid THEN
      OPEN  c_only_error_is_rcv_date;
      FETCH c_only_error_is_rcv_date into L_only_error_is_rcv_date;
      CLOSE c_only_error_is_rcv_date;

      IF L_only_error_is_rcv_date = 0 THEN
         L_valid := TRUE;
      END IF;
   END IF;

   IF L_valid THEN
      I_fail := false;

      IF SMR_SDC_944.F_PROCESS_CARTON(O_error_message,
                                      L_carton    ) = FALSE THEN
         return false;
      END IF;

   else
      I_fail := true;
   END IF;

--   DELETE FROM smr_manual_944 WHERE CARTON = L_carton;

   return true;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;

END PROCESS_CARTON;

--------------------------------------------------------------------------------------------
-- Function    : GET_ORDER_QTY
-- Purpose     : Gets the order quantity for an order/wh/store/item combination
--------------------------------------------------------------------------------------------
FUNCTION GET_ORDER_QTY(O_error_message IN OUT varchar2,
                       I_order_no      IN     ordhead.order_no%type,
                       I_wh            IN     wh.wh%type,
                       I_store         IN     store.store%type,
                       I_item          IN     item_master.item%type,
                       O_qty_ordered   IN OUT ordloc.qty_ordered%type) return boolean is

   L_program VARCHAR2(64):= 'SMR_MANUAL_944_SQL.GET_ORDER_QTY';

   L_is_a_e3_ord varchar2(1);

   cursor c_is_a_e3_ord is
   select 'Y'
     from alloc_header ah
    where ah.order_no = I_order_no
      and ah.alloc_desc like 'createordlib%';

   /* OLR V1.03 Delete START
   cursor C_ORDER_QTY is
   select sum(nvl(ail.ALLOCATED_QTY,0) * nvl(pb.pack_item_qty,1)) allocated
     from alc_alloc aa,
          alc_item_loc ail,
          (select distinct alloc_id from alc_xref where order_no = I_order_no) ax,
          store st,
          packitem_breakout pb
    where aa.alloc_id   = ax.alloc_id
      and ail.alloc_id  = aa.alloc_id
      and st.store      = ail.location_id
      and ail.item_id   = pb.pack_no (+)
      and ail.order_no  = I_order_no
      and st.default_wh = (I_wh*10)+1
      and aa.status in ('2','3','4')
      and nvl(pb.item,ail.item_id) = I_item
      and ail.location_id = I_store
    group by I_item;
   --OLR V1.03 Delete END */

    -- OLR V1.03 Insert START
    cursor C_ORDER_QTY is
    select sum(nvl(ail.ALLOCATED_QTY,0) * nvl(pb.pack_item_qty,1)) allocated
      from alc_alloc aa,
           alc_item_loc ail,
           (select distinct alloc_id from alc_xref where order_no = I_order_no) ax,
           store st,
           packitem_breakout pb
     where aa.alloc_id   = ax.alloc_id
       and ail.alloc_id  = aa.alloc_id
       and st.store      = ail.location_id
       and ail.item_id   = pb.pack_no (+)
       and ail.order_no  = I_order_no
       and st.default_wh = nvl((I_wh*10)+1,st.default_wh)
       and ( --Allocation approved/extracted
             aa.status in ('2','3')
             or
             --Allocation closed and shipped against.
             ( aa.status = '4'
               and exists (select 'x'
                             from alc_xref     ax2,
                                  alloc_detail ad
                            where ax2.order_no = I_order_no
                              and ax2.alloc_id = aa.alloc_id
                              and ax2.xref_alloc_no = ad.alloc_no
                              and ad.qty_distro is not null))
             or
             -- allocation closed after order
             ( aa.status = '4'
               and exists (select 'x'
                             from alc_alloc_au a_au,
                                  alc_xref     ax2,
                                  ordhead      oh
                            where ax2.order_no = I_order_no
                              and ax2.alloc_id = aa.alloc_id
                              and ax2.alloc_id = a_au.alloc_id
                              and ax2.order_no = oh.order_no
                              and oh.close_date is not null
                              and a_au.n_status = '4'
                              and a_au.o_status != '4'
                              and a_au.modify_date >= oh.close_date))
           )
       and nvl(pb.item,ail.item_id) = I_item
       and ail.location_id = I_store;
    -- OLR V1.03 Insert END

   cursor C_ORDER_QTY_2 is
   select sum(nvl(ad.qty_ALLOCATED,0) * nvl(pb.pack_item_qty,1)) allocated
     from alloc_header ah,
          alloc_detail ad,
          store st,
          packitem_breakout pb
    where ah.alloc_no   = ad.alloc_no
      and st.store      = ad.to_loc
      and ah.item   = pb.pack_no (+)
      and ah.order_no  = I_order_no
      and st.default_wh = (I_wh*10)+1
      and ah.status ='A'
      and nvl(pb.item,ah.item) = I_item
      and ad.to_loc = I_store
    group by I_item;

begin

   if I_order_no is null then
      O_error_message := 'Order number cannot be null. ('||L_program||')';
      return false;
   end if;

   if I_wh is null then
      O_error_message := 'SDC cannot be null. ('||L_program||')';
      return false;
   end if;

   if I_store is null then
      O_error_message := 'Store cannot be null. ('||L_program||')';
      return false;
   end if;

   if I_item is null then
      O_error_message := 'Item cannot be null. ('||L_program||')';
      return false;
   end if;

   open  c_is_a_e3_ord;
   fetch c_is_a_e3_ord into L_is_a_e3_ord;
   close c_is_a_e3_ord;

   L_is_a_e3_ord := nvl(L_is_a_e3_ord,'N');

   if L_is_a_e3_ord = 'N' then

      open  C_ORDER_QTY;
      fetch C_ORDER_QTY into O_qty_ordered;
      close C_ORDER_QTY ;

   else

      open  C_ORDER_QTY_2;
      fetch C_ORDER_QTY_2 into O_qty_ordered;
      close C_ORDER_QTY_2 ;

   end if;

   O_qty_ordered := nvl(O_qty_ordered,0);

   return true;

   EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;

end GET_ORDER_QTY;

END SMR_MANUAL_944_SQL;
/