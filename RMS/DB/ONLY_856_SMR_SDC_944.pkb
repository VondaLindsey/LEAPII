CREATE OR REPLACE PACKAGE BODY RMS13.ONLY_856_SMR_SDC_944 IS
-- Module Name: ONLY_856_SMR_SDC_944
-- Description: This package will be used to create shipments from the 944 SDC receipt file.
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== =========================================
-- 1.00    20-Jul-11 P.Dinsdale  ENH 38   OLR initial version.
--------------------------------------------------------------------------------

-----------------------------------------------------------------------------------
--PRIVATE FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Procedure Name: SHO
-- Purpose: Used for debug purposes
--------------------------------------------------------------------------------
PROCEDURE SHO(O_ERROR_MESSAGE IN VARCHAR2) IS
   L_DEBUG_ON BOOLEAN := FALSE; -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
   L_DEBUG_TIME_ON BOOLEAN := FALSE; -- SET TO FALSE TO TURN OFF DEBUG COMMENT.
BEGIN

   IF L_DEBUG_ON THEN
      dbms_output.put_line('DBG: '||O_ERROR_MESSAGE);
   END IF;
   IF L_DEBUG_TIME_ON THEN
      dbms_output.put_line('DBG: '||to_char(sysdate,'HH24:MI')||O_ERROR_MESSAGE);
   END IF;
END;

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
    where ah.status    in ('A', 'R', 'C')
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
      and ah.status in ('A', 'R', 'C')
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
      and ah.status in ('A', 'R', 'C');

   L_alloc_no alloc_header.alloc_no%type;

   cursor c_pack_details is
   select distinct ah.alloc_no
     from alloc_header ah,
          alloc_detail ad,
          item_master im,
          packitem_breakout pb
    where ah.status in ('A', 'R', 'C')
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
      and ah.status in ('A', 'R', 'C');

   cursor c_alloc_header_details is
   select alloc_method,
          order_type,
          release_date
     from alloc_header ah
    where order_no = I_order_no
      and item != I_item
      and ah.status in ('A', 'R','C')
      and rownum < 2;

   cursor c_alloc_detail is
   select ad.alloc_no
     from alloc_detail ad,
          alloc_header ah
    where order_no = I_order_no
      and item = I_item
      and ah.status in ('A', 'R','C')
      and ad.alloc_no = ah.alloc_no
      and ad.to_loc = I_store;

   L_alloc_detail_alloc_no number;

   cursor c_alloc_detail_details is
   select min(ad.in_store_date)  in_store_date,
          min(ad.non_scale_ind)  non_scale_ind,
          min(ad.rush_flag)      rush_flag
     from alloc_header ah,
          alloc_detail ad
    where ah.status in ('A', 'R','C')
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


--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------


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
   L_program              VARCHAR2(64) := 'SMR_SHIPMENT_SQL.PUB_SHIPMENT';
   L_to_loc               NUMBER;

BEGIN

   IF I_shipment IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            'I_shipment',
                                            L_program,
                                            NULL);
      RETURN FALSE;
   END IF;

   IF I_to_loc_type IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            'I_to_loc_type',
                                            L_program,
                                            NULL);
      RETURN FALSE;
   END IF;


   IF SYSTEM_OPTIONS_SQL.GET_SYSTEM_OPTIONS(O_error_message,
                                            L_system_options_row) = FALSE THEN
      RETURN FALSE;
   END IF;

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

   IF ((L_system_options_row.ship_rcv_store = 'N' AND I_to_loc_type = 'S') AND L_system_options_row.ship_rcv_wh    = 'Y') OR
      ((L_system_options_row.ship_rcv_wh    = 'N' AND I_to_loc_type = 'W') AND L_system_options_row.ship_rcv_store = 'Y') OR
      I_wf_ship_ind = TRUE THEN
      ---
      --insert into shipment_pub_temp(shipment) --pdd
      INSERT INTO SHIPMENT_PUB_TEMP(SHIPMENT) --pdd
                             VALUES(I_shipment);
      ---
   END IF;

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;

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

   CURSOR C_GET_BOL_SHIPMENT IS
      SELECT to_loc,
             to_loc_type,
             from_loc,
             from_loc_type,
             ship_date,
             no_boxes,
             courier,
             comments
        FROM BOL_SHIPMENT bol_sh
       WHERE bol_sh.bol_no = I_bol_no;

   CURSOR C_GET_BOL_SHIP_SKU IS
      SELECT bol_sku.distro_no,
             thead.tsf_no check_distro,
             bol_sku.distro_type,
             bol_sku.CARTON,
             bol_sku.item,
             tsf.item check_item,
             bol_sku.ship_qty,
             tsf.tsf_qty - NVL(tsf.ship_qty, 0) available_qty,
             bol_sku.weight_expected,
             bol_sku.weight_expected_uom,
             NVL(tsf.inv_status,-1) inv_status,
             thead.TSF_TYPE,
             thead.from_loc,
             thead.to_loc
        FROM BOL_SHIPSKU bol_sku,
             TSFDETAIL tsf,
             TSFHEAD thead
       WHERE bol_sku.bol_no = I_bol_no
         AND tsf.tsf_no(+) = bol_sku.distro_no
         AND tsf.item(+) = bol_sku.item
         AND tsf.tsf_qty > 0
         AND thead.tsf_no (+) = bol_sku.distro_no
         AND bol_sku.distro_type = 'T'
         AND NOT EXISTS (SELECT 'x'
                           FROM v_tsfhead v
                          WHERE v.tsf_no = thead.tsf_no
                            AND v.child_tsf_no IS NOT NULL
                            AND v.leg_1_status = 'C'
                            AND v.leg_2_status IN ('A','S')
                            AND v.finisher_type = 'I')
       UNION ALL
      SELECT thead.child_tsf_no,
             thead.child_tsf_no check_distro,
             bol_sku.distro_type,
             bol_sku.CARTON,
             bol_sku.item,
             tsf.item check_item,
             bol_sku.ship_qty,
             tsf.tsf_qty - NVL(tsf.ship_qty, 0) available_qty,
             bol_sku.weight_expected,
             bol_sku.weight_expected_uom,
             NVL(tsf.inv_status,-1) inv_status,
             thead.TSF_TYPE,
             thead.finisher,
             thead.to_loc
        FROM BOL_SHIPSKU bol_sku,
             TSFDETAIL tsf,
             v_tsfhead thead
       WHERE bol_sku.bol_no = I_bol_no
         AND tsf.item(+) = bol_sku.item
         AND tsf.tsf_qty > 0
         AND thead.tsf_no (+) = bol_sku.distro_no
         AND thead.child_tsf_no = tsf.tsf_no
         AND bol_sku.distro_type = 'T'
         AND thead.leg_1_status = 'C'
         AND thead.leg_2_status IN ('A','S')
         AND thead.finisher_type = 'I'
       UNION ALL
      SELECT bol_sku.distro_no,
             ah.alloc_no check_distro,
             bol_sku.distro_type,
             bol_sku.CARTON,
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
        FROM (SELECT bs.from_loc,
                     bs.to_loc,
                     bk.*
                FROM BOL_SHIPMENT bs,
                     BOL_SHIPSKU bk
               WHERE bs.bol_no = I_bol_no
                 AND bs.bol_no = bk.bol_no
                 AND bk.distro_type = 'A') bol_sku,
             (SELECT ad.alloc_no,
                     ad.qty_allocated - ad.qty_transferred available_qty
                FROM BOL_SHIPMENT bs,
                     BOL_SHIPSKU bk,
                     WH,
                     ALLOC_DETAIL ad
               WHERE bs.bol_no = I_bol_no
                 AND bk.bol_no = bs.bol_no
                 AND bk.distro_no = ad.alloc_no
                 AND bs.to_loc = WH.physical_wh
                 AND WH.WH = ad.to_loc
                 AND ad.to_loc_type = 'W'
               UNION ALL
              SELECT ad.alloc_no,
                     ad.qty_allocated - ad.qty_transferred available_qty
                FROM BOL_SHIPMENT bs,
                     BOL_SHIPSKU bk,
                     ALLOC_DETAIL ad
               WHERE bs.bol_no = I_bol_no
                 AND bk.bol_no = bs.bol_no
                 AND bk.distro_no = ad.alloc_no
                 AND bs.to_loc = ad.to_loc
                 AND ad.to_loc_type = 'S') ad,
             (SELECT ah.alloc_no,
                     ah.item,
                     WH.physical_wh WH
                FROM BOL_SHIPMENT bs,
                     BOL_SHIPSKU bk,
                     WH,
                     ALLOC_HEADER ah
               WHERE bs.bol_no = I_bol_no
                 AND bs.bol_no = bk.bol_no
                 AND bs.from_loc = WH.physical_wh
                 AND bk.distro_no = ah.alloc_no
                 AND bk.item = ah.item
                 AND WH.WH = ah.WH) ah
       WHERE bol_sku.distro_no = ah.alloc_no (+)
         AND bol_sku.distro_no = ad.alloc_no (+)
       ORDER BY 1;

   CURSOR C_SHIPMENT IS
      SELECT SHIPMENT
        FROM SHIPMENT
       WHERE bol_no = I_bol_no;

   TYPE tsf_rec IS RECORD(tsf_no         SHIPSKU.DISTRO_NO%TYPE,
                          TSF_TYPE       TSFHEAD.TSF_TYPE%TYPE,
                          tsf_item       SHIPSKU.ITEM%TYPE);
   TYPE tsf_rec_item_tbl IS TABLE OF tsf_rec INDEX BY BINARY_INTEGER;
   L_ils_item_tbl      tsf_rec_item_tbl;

   TYPE bol_shipsku_tbl IS TABLE OF c_get_bol_ship_sku%ROWTYPE INDEX BY BINARY_INTEGER;
   L_bol_shipsku_tbl   bol_shipsku_tbl;

   L_bol_shipment_rec  C_GET_BOL_SHIPMENT%ROWTYPE;

BEGIN
   --- Validate parameters
   IF I_bol_no IS NULL THEN
      L_invalid_param := 'I_bol_no';
   END IF;
   ---
   IF L_invalid_param IS NOT NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            L_invalid_param,
                                            L_program,
                                            NULL);
      RETURN FALSE;
   END IF;

   OPEN C_GET_BOL_SHIPMENT;
   FETCH C_GET_BOL_SHIPMENT INTO L_bol_shipment_rec;

   IF C_GET_BOL_SHIPMENT%NOTFOUND THEN
      CLOSE C_GET_BOL_SHIPMENT;
      O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                            NULL,
                                            L_program,
                                            NULL);
      RETURN FALSE;
   END IF;

   CLOSE C_GET_BOL_SHIPMENT;

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

   OPEN C_GET_BOL_SHIP_SKU;
   FETCH C_GET_BOL_SHIP_SKU BULK COLLECT INTO L_bol_shipsku_tbl;
   CLOSE C_GET_BOL_SHIP_SKU;

   IF L_bol_shipsku_tbl.first IS NULL THEN
      O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                            NULL,
                                            L_program,
                                            NULL);
      RETURN FALSE;
   END IF;

   IF BOL_SQL.PUT_BOL(O_error_message,
                      L_bol_exist,
                      I_bol_no,
                      L_from_loc,
                      L_to_loc,
                      L_bol_shipment_rec.ship_date,
                      NULL,
                      L_bol_shipment_rec.no_boxes,
                      L_bol_shipment_rec.courier,
                      NULL,
                      L_bol_shipment_rec.comments) = FALSE THEN

      RETURN FALSE;
   END IF;

   IF L_bol_exist = TRUE THEN
      O_error_message := SQL_LIB.CREATE_MSG('DUP_BOL',
                                            I_bol_no,
                                            L_program,
                                            NULL);
        RETURN FALSE;
   END IF;
   ---
   L_from_loc_orig := L_from_loc;
   L_to_loc_orig := L_to_loc;
   ---
   FOR A IN L_bol_shipsku_tbl.first..L_bol_shipsku_tbl.last LOOP

      IF L_bol_shipsku_tbl(A).check_distro IS NULL THEN
         O_error_message := SQL_LIB.CREATE_MSG('INV_DISTRO_TSF_ALLOC',
                                               L_bol_shipsku_tbl(A).distro_no,
                                               L_program,
                                               NULL);
         RETURN FALSE;
      END IF;

      IF L_bol_shipsku_tbl(A).check_item IS NULL THEN
         O_error_message := SQL_LIB.CREATE_MSG('INV_TSF_ALLOC_ITEM',
                                               L_bol_shipsku_tbl(A).distro_no,
                                               L_bol_shipsku_tbl(A).item,
                                               NULL);
         RETURN FALSE;
      END IF;

      IF L_bol_shipsku_tbl(A).ship_qty > L_bol_shipsku_tbl(A).available_qty THEN

         UPDATE ALLOC_DETAIL set QTY_ALLOCATED = QTY_ALLOCATED + (L_bol_shipsku_tbl(A).ship_qty -  L_bol_shipsku_tbl(A).available_qty),
                                 QTY_PRESCALED = QTY_PRESCALED + (L_bol_shipsku_tbl(A).ship_qty -  L_bol_shipsku_tbl(A).available_qty)
          WHERE alloc_no = L_bol_shipsku_tbl(A).distro_no
            AND to_loc = L_to_loc;

         --pdd O_error_message := SQL_LIB.CREATE_MSG('INV_TSF_ALLOC_QTY',
         --pdd                                       L_bol_shipsku_tbl(a).distro_no,
         --pdd                                       L_bol_shipsku_tbl(a).item,
         --pdd                                       NULL);
         --return FALSE;
      END IF;
      ---
      L_from_loc := L_from_loc_orig;
      L_to_loc := L_to_loc_orig;
      ---
      IF L_bol_shipsku_tbl(A).distro_type = 'T' AND
         L_bol_shipment_rec.from_loc_type = 'W' AND
         L_new_distro = 'Y' THEN
         IF WH_ATTRIB_SQL.CHECK_FINISHER(O_error_message,
                                         L_finisher,
                                         L_finisher_name,
                                         L_bol_shipsku_tbl(A).from_loc) = FALSE THEN
            RETURN FALSE;
         END IF;

         IF L_finisher = TRUE THEN
            IF INVADJ_SQL.GET_INV_STATUS(O_error_message,
                                         L_fin_inv_status,
                                         'ATS') = FALSE THEN
               RETURN FALSE;
            END IF;
         ELSE
            L_fin_inv_status := NULL;
         END IF;
      ELSE
         L_fin_inv_status := NULL;
      END IF;

      L_new_distro := 'N';
      L_count := L_bol_items_tbl.COUNT + 1;
      L_bol_items_tbl(L_count).distro_no              := L_bol_shipsku_tbl(A).distro_no;
      L_bol_items_tbl(L_count).item                   := L_bol_shipsku_tbl(A).item;
      L_bol_items_tbl(L_count).CARTON                 := L_bol_shipsku_tbl(A).CARTON;
      L_bol_items_tbl(L_count).ship_qty               := L_bol_shipsku_tbl(A).ship_qty;
      L_bol_items_tbl(L_count).weight                 := L_bol_shipsku_tbl(A).weight_expected;
      L_bol_items_tbl(L_count).weight_uom             := L_bol_shipsku_tbl(A).weight_expected_uom;
      L_bol_items_tbl(L_count).distro_type            := L_bol_shipsku_tbl(A).distro_type;
      L_bol_items_tbl(L_count).inv_status             := NVL(L_fin_inv_status, L_bol_shipsku_tbl(A).inv_status);

      IF A < L_bol_shipsku_tbl.last THEN
         L_next_distro_no := L_bol_shipsku_tbl(A + 1).distro_no;
      END IF;

      IF A = L_bol_shipsku_tbl.last OR (L_bol_shipsku_tbl(A).distro_no != L_next_distro_no) THEN
         L_new_distro := 'Y';
         --Pass the L_sellable table to BOL_SQL.PROCESS_ITEM
         IF BOL_SQL.PROCESS_ITEM(O_error_message,
                                 L_item_tbl,  -- output table
                                 L_bol_items_tbl,
                                 L_from_loc,
                                 L_to_loc) = FALSE THEN
            RETURN FALSE;
         END IF;

         L_distro_no := L_item_tbl(1).distro_no;
         L_distro_type := L_item_tbl(1).distro_type;

         IF L_distro_type = 'T' THEN
            IF TRANSFER_SQL.GET_TSFHEAD_INFO(O_error_message,
                                             L_tsfhead_info,
                                             L_distro_no) = FALSE THEN
               RETURN FALSE;
            END IF;

            IF L_tsfhead_info.finisher_type = 'I' AND
               L_tsfhead_info.leg_1_status = 'C' AND
               L_tsfhead_info.leg_2_status IN ('A','S') THEN
               L_distro_no := L_tsfhead_info.child_tsf_no;
            END IF;

            L_tsf_type := L_bol_shipsku_tbl(A).TSF_TYPE;
            IF BOL_SQL.PUT_TSF(O_error_message,
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
                               NULL) = FALSE THEN
              RETURN FALSE;
            END IF;

            IF TRANSFER_SQL.GET_FINISHER_INFO(O_error_message,
                                              L_finisher_loc_ind,
                                              L_finisher_entity_ind,
                                              L_distro_no)= FALSE THEN
               RETURN FALSE;
            END IF;

            FOR K IN L_item_tbl.first..L_item_tbl.last LOOP
               IF BOL_SQL.PUT_TSF_ITEM(O_error_message,
                                       L_item_tbl(K).distro_no,
                                       L_item_tbl(K).item,
                                       L_item_tbl(K).CARTON,
                                       L_item_tbl(K).ship_qty,
                                       L_item_tbl(K).weight,
                                       L_item_tbl(K).weight_uom,
                                       L_item_tbl(K).inv_status,
                                       L_from_loc,
                                       L_bol_shipment_rec.from_loc_type,
                                       L_to_loc,
                                       L_bol_shipment_rec.to_loc_type,
                                       L_bol_shipment_rec.to_loc,
                                       L_bol_shipment_rec.from_loc,
                                       L_tsf_type,
                                       L_del_type,
                                       'Y') = FALSE THEN
                  RETURN FALSE;
               END IF;

               IF L_finisher = FALSE THEN
                  L_ctr := L_ils_item_tbl.COUNT + 1;
                  L_ils_item_tbl(L_ctr).tsf_no   := L_distro_no;
                  L_ils_item_tbl(L_ctr).TSF_TYPE := L_tsf_type;
                  L_ils_item_tbl(L_ctr).tsf_item := L_item_tbl(K).item;
               END IF;
            END LOOP;

            IF BOL_SQL.PROCESS_TSF(O_error_message) = FALSE THEN
               RETURN FALSE;
            END IF;
         END IF;

         IF L_distro_type = 'A' THEN
            FOR K IN L_item_tbl.first..L_item_tbl.last LOOP
               IF BOL_SQL.PUT_ALLOC(O_error_message,
                                     L_item_tbl(K).item,
                                     L_bol_shipment_rec.from_loc,
                                     L_distro_no,
                                     L_from_loc, --physical location
                                     L_item_tbl(K).item) = FALSE THEN
                  RETURN FALSE;
               END IF;

               IF BOL_SQL.PUT_ALLOC_ITEM(O_error_message,
                                         L_item_tbl(K).distro_no,
                                         L_item_tbl(K).item,
                                         L_item_tbl(K).CARTON,
                                         L_item_tbl(K).ship_qty,
                                         L_item_tbl(K).weight,
                                         L_item_tbl(K).weight_uom,
                                         L_item_tbl(K).inv_status,
                                         L_to_loc,                         -- physical location
                                         L_bol_shipment_rec.to_loc_type,
                                         L_from_loc) = FALSE THEN          -- physical location
                  RETURN FALSE;
               END IF;
            END LOOP;

            IF BOL_SQL.PROCESS_ALLOC(O_error_message) = FALSE THEN
               RETURN FALSE;
            END IF;
         END IF;

         L_item_tbl.DELETE;
         L_bol_items_tbl.DELETE;

      END IF;
   END LOOP;

   IF BOL_SQL.FLUSH_BOL_PROCESS(O_error_message) = FALSE THEN
      RETURN FALSE;
   END IF;

   OPEN C_SHIPMENT;
   FETCH C_SHIPMENT INTO L_shipment;
   CLOSE C_SHIPMENT;
   ---
   IF L_ils_item_tbl.first IS NOT NULL THEN
      IF L_finisher_loc_ind IS NOT NULL THEN
         FOR i IN L_ils_item_tbl.first..L_ils_item_tbl.last LOOP
            IF BOL_SQL.PUT_ILS_AV_RETAIL(O_error_message,
                                         L_bol_shipment_rec.to_loc,
                                         L_bol_shipment_rec.to_loc_type,
                                         L_ils_item_tbl(i).tsf_item,
                                         L_shipment,
                                         L_distro_no,
                                         L_ils_item_tbl(i).TSF_TYPE,
                                         NULL) = FALSE THEN
               RETURN FALSE;
            END IF;
         END LOOP;
      END IF;
   END IF;

   IF PUB_SHIPMENT(O_error_message,
                   L_bol_shipment_rec.to_loc_type,
                   L_shipment) = FALSE THEN
      RETURN FALSE;
   END IF;

   L_ils_item_tbl.DELETE;
   L_bol_shipsku_tbl.DELETE;

   RETURN TRUE;

EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      RETURN FALSE;
END SHIP_DISTROS;

--------------------------------------------------------------------------------
-- Function Name: COPY_STORE_ITEM
-- Purpose: Create item X at store 1 like item Y at store 1
--------------------------------------------------------------------------------
FUNCTION COPY_STORE_ITEM(I_like_store       IN      STORE.STORE%TYPE,
                         I_new_store        IN      STORE.STORE%TYPE,
                         I_item             IN      ITEM_MASTER.item%TYPE,
                         O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
        RETURN BOOLEAN IS
   L_item               ITEM_EXP_HEAD.ITEM%TYPE;
   L_supplier           ITEM_EXP_HEAD.SUPPLIER%TYPE;
   L_seq                ITEM_EXP_HEAD.ITEM_EXP_SEQ%TYPE;
   L_daily_waste_pct    ITEM_LOC.DAILY_WASTE_PCT%TYPE;
   L_elc_ind            SYSTEM_OPTIONS.ELC_IND%TYPE;
   L_program            VARCHAR2(64) := package_name||'.COPY_STORE_ITEM';

   CURSOR C_ITEM_EXP_HEAD IS
      SELECT ieh.ITEM           item1,
             ieh.SUPPLIER     supplier1
        FROM COST_ZONE_GROUP    czg,
             ITEM_MASTER        im,
             ITEM_EXP_HEAD      ieh
       WHERE ieh.ITEM              = im.ITEM
         AND ieh.ZONE_GROUP_ID     = czg.ZONE_GROUP_ID
         AND im.COST_ZONE_GROUP_ID = czg.ZONE_GROUP_ID
         AND ieh.ITEM_EXP_TYPE     = 'Z'
         AND czg.COST_LEVEL        = 'L'
         AND ieh.ZONE_ID           = I_like_store
         AND im.item               = I_item;

   CURSOR C_GET_MAX_SEQ IS
      SELECT max(item_exp_seq) + 1
        FROM ITEM_EXP_HEAD
       WHERE ITEM          = L_item
         AND SUPPLIER      = L_supplier
         AND ITEM_EXP_TYPE = 'Z';

   CURSOR C_GET_ITEMS IS
      SELECT il.ITEM,
             il.LOC_TYPE,
             il.DAILY_WASTE_PCT,
             ils.UNIT_COST,
             il.UNIT_RETAIL,
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
        FROM ITEM_LOC il,
             ITEM_LOC_SOH ils,
             ITEM_MASTER im
       WHERE il.loc       = I_like_store
         AND il.clear_ind = 'N'
         AND il.item      = ils.item(+)
         AND il.loc       = ils.loc(+)
         AND il.item      = im.item
         AND im.item      = I_item
     ORDER BY im.pack_ind;

BEGIN
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
   IF NOT SYSTEM_OPTIONS_SQL.GET_ELC_IND(O_error_message,
                                         L_elc_ind) THEN
      RETURN FALSE;
   END IF;

   IF L_elc_ind = 'Y' THEN
   ---
      FOR C_ITEM_EXP_HEAD_REC IN C_ITEM_EXP_HEAD LOOP
         L_item := C_ITEM_EXP_HEAD_REC.item1;
         L_supplier := C_ITEM_EXP_HEAD_REC.supplier1;
         SQL_LIB.SET_MARK('OPEN','C_GET_MAX_SEQ','ITEM_EXP_HEAD',NULL);
         OPEN C_GET_MAX_SEQ;
         SQL_LIB.SET_MARK('FETCH','C_GET_MAX_SEQ','ITEM_EXP_HEAD',NULL);
         FETCH C_GET_MAX_SEQ INTO L_seq;
         SQL_LIB.SET_MARK('CLOSE','C_GET_MAX_SEQ','ITEM_EXP_HEAD',NULL);
         CLOSE C_GET_MAX_SEQ;
         SQL_LIB.SET_MARK('INSERT',NULL,'ITEM_EXP_HEAD',NULL);
         INSERT INTO ITEM_EXP_HEAD(item,
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
         SELECT L_item,
                L_supplier,
                'Z',
                L_seq + ROWNUM,
                NULL,
                I_new_store,
                NULL,
                discharge_port,
                zone_group_id,
                'N',
                sysdate,
                sysdate,
                user
           FROM ITEM_EXP_HEAD
          WHERE item     = L_item
            AND supplier = L_supplier
            AND zone_id  = I_like_store;

         SQL_LIB.SET_MARK('INSERT',NULL,'ITEM_EXP_DETAIL',NULL);
         INSERT INTO ITEM_EXP_DETAIL(item,
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
         SELECT ieh.item,
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
           FROM ITEM_EXP_HEAD ieh,
                ITEM_EXP_HEAD ieh2,
                ITEM_EXP_DETAIL ied
          WHERE ied.item           = L_item
            AND ied.supplier       = L_supplier
            AND ied.item_exp_type  = 'Z'
            AND ied.item_exp_seq   = ieh2.item_exp_seq
            AND ieh2.zone_id       = I_like_store
            AND ieh2.item          = L_item
            AND ieh2.supplier      = L_supplier
            AND ieh2.item_exp_type = 'Z'
            AND ieh.zone_id        = I_new_store
            AND ieh.item           = L_item
            AND ieh.supplier       = L_supplier
            AND ieh.item_exp_type  = 'Z';
      END LOOP;
   ---
   END IF;
   ---
   FOR C_GET_ITEMS_REC IN C_GET_ITEMS LOOP
      IF NEW_ITEM_LOC ( O_error_message,
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
                        FALSE) = FALSE THEN
         RETURN FALSE;
      END IF;
   END LOOP;
   ---
   RETURN TRUE;
EXCEPTION
   WHEN OTHERS THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR', SQLERRM,
                                            L_program, to_char(SQLCODE));
      RETURN FALSE;
END COPY_STORE_ITEM;



------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------
--PUBLIC FUNCTIONS/PROCEDURES
-----------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Procedure Name: F_PROCESS_RECEIPTS
-- Purpose: Process files in SMR_856_DATA_CONVERSION_USE
--------------------------------------------------------------------------------
FUNCTION F_PROCESS_RECEIPTS(O_error_message IN OUT VARCHAR2)
 RETURN BOOLEAN IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_RECEIPTS';

   --variables used to consume OTB table
   L_status_code      VARCHAR2(255);
   L_rib_otb_tbl      "RIB_OTB_TBL"     := NULL;
   L_rib_otbdesc_rec  "RIB_OTBDesc_REC" := NULL;
   L_MESSAGE_TYPE     VARCHAR2(255);
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
   L_comment_desc  VARCHAR2(2000);
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
         ,ssd.STORE         L_dest_id
         ,NULL              L_to_disposition
         ,NULL              L_from_disposition
         ,ssd.units_shipd   L_shipped_qty
         ,NULL              L_weight
         ,NULL              L_weight_uom
    FROM SMR_856_DATA_CONVERSION_USE ssd
   WHERE NVL(ssd.qty_to_be_received,0) >  0
   ORDER BY 2, 10, 13, 3;

   CURSOR c_adjustments IS
   SELECT (ssd.whse_location) * 10 + 1 WH
         ,ssd.order_no      order_no
         ,ssd.sku_char      item
         ,NVL(ssd.exception_qty,0) adj_qty
         ,ssd.rcv_date      rcv_date
         ,ssd.vendor_performance_code
    FROM SMR_856_DATA_CONVERSION_USE ssd
   WHERE NVL(ssd.exception_qty,0) >  0
   ORDER BY 2, 1, 3, 5;

  CURSOR c_unit_cost(I_order_no NUMBER,
                     I_item     VARCHAR2)IS
  SELECT unit_cost
    FROM ORDLOC
   WHERE order_no = I_order_no
     AND item = I_item;

   --get all receipt records from which we need to make shipments.
   CURSOR c_bol_shipment IS
   SELECT DISTINCT
          ssd.rcv_date      ship_date
         ,ssd.whse_location FROM_loc
         ,'W'               FROM_loc_type
         ,ssd.STORE         to_loc
         ,'S'               to_loc_type
         ,NULL              courier
         ,NULL              no_boxes
         ,NULL              comments
         ,ssd.carton_id     carton_id
    FROM SMR_856_DATA_CONVERSION_USE ssd,
         ORDHEAD oh
   WHERE oh.order_no = ssd.order_no
     AND oh.pre_mark_ind = 'Y' --Only do for orders with allocations.
     AND NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0) >  0
     and not exists (select 'x' from shipsku where shipsku.carton = ssd.carton_id)
   ORDER BY ssd.carton_id;

   --get all receipt records from which we need to make shipsku records .
  CURSOR c_bol_shipsku(I_carton VARCHAR2) IS
   SELECT ssd.order_no      order_no
         ,ssd.sku_char      item
         ,ssd.upc_char      ref_item
         ,ssd.carton_id     carton_id
         ,sum(NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0)) ship_qty
         ,sysdate           last_update_datetime
     FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE ssd.carton_id = I_carton
    GROUP BY ssd.order_no
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
     AND ad.to_loc = I_store;

   CURSOR c_to_be_shipped(I_order_no NUMBER,
                          I_item VARCHAR2,
                          I_store NUMBER,
                          I_wh NUMBER) IS
   SELECT sum(NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0)) to_be_shipped
    FROM SMR_856_DATA_CONVERSION_USE ssd
   WHERE NVL(ssd.qty_to_be_received,0) - nvl(ssd.exception_qty,0) >  0
     AND sku_char = I_item
     AND order_no = I_order_no
     AND STORE = I_store
     AND WHSE_LOCATION = I_wh;

  CURSOR c_pre_mark_ind(I_order_no NUMBER) IS
  SELECT pre_mark_ind
    FROM ORDHEAD
   WHERE order_no = I_order_no;

  L_pre_mark_ind VARCHAR2(1);

  CURSOR c_distro_header(I_order_no NUMBER,
                         I_item VARCHAR2) IS
  SELECT ah.order_no,
      --   ah.wh,
         ah.status,
         ah.alloc_method,
         ah.order_type
    FROM ALLOC_HEADER ah
   WHERE order_no = I_order_no
     --only make a header record if it does not exist.
     AND NOT EXISTS (SELECT 'x' FROM ALLOC_HEADER WHERE order_no = I_order_no AND item = I_item)
     AND ROWNUM < 2;

  CURSOR c_distro_detail(I_order_no NUMBER,
                         I_store    NUMBER)IS
  SELECT ad.non_scale_ind
    FROM ALLOC_DETAIL ad,
         ALLOC_HEADER ah
   WHERE ah.alloc_no = ad.alloc_no
     AND ah.order_no = I_order_no
     AND ad.to_loc = I_store
     AND ROWNUM < 2;

  CURSOR c_distro_number(I_order_no NUMBER,
                         I_item VARCHAR2) IS
  SELECT ah.alloc_no
    FROM ALLOC_HEADER ah
   WHERE order_no = I_order_no
     AND item = I_item;

   CURSOR c_item_loc_exists(I_item VARCHAR2,
                            I_loc  NUMBER) IS
   SELECT 'x'
     FROM ITEM_LOC
    WHERE item = I_item
      AND loc = I_loc;

   L_item_loc_exists VARCHAR2(1);

   CURSOR c_sample_item_loc(I_item VARCHAR2) IS
   SELECT il.loc
     FROM ITEM_LOC il,
          STORE st
    WHERE il.item = I_item
      AND il.clear_ind = 'N'
      AND st.STORE = il.loc
      AND nvl(st.store_close_date,get_vdate + 1) > get_vdate
      AND ROWNUM < 2;

   CURSOR c_sample_item_loc_wh(I_item VARCHAR2) IS
SELECT loc FROM (
   SELECT il.loc
     FROM ITEM_LOC il,
          WH WH
    WHERE il.item = I_item
      AND il.clear_ind = 'N'
      AND WH.WH = il.loc
      AND WH IN (9521,9531,9541)
      AND ROWNUM < 2
      UNION
   SELECT il.loc
     FROM ITEM_LOC il,
          WH WH
    WHERE il.item = I_item
      AND il.clear_ind = 'N'
      AND WH.WH = il.loc
      AND WH IN (9401)
      )
ORDER BY loc desc;

   L_sample_item_loc ITEM_LOC.loc%TYPE;

  CURSOR c_custom_alloc_detail(I_alloc_no NUMBER,
                               I_store NUMBER) IS
  SELECT 'Y'
    FROM SMR_944_NEW_ALLOC_DETAIL
   WHERE alloc_no = I_alloc_no
     AND to_loc = I_store;

  L_custom_alloc_detail VARCHAR2(1);

  CURSOR c_multiple_upc IS
  SELECT order_no, sku_char item, carton_id, count(DISTINCT nvl(upc_char,' '))
    FROM SMR_856_DATA_CONVERSION_USE
   GROUP BY order_no, sku_char, carton_id
  HAVING count(DISTINCT nvl(upc_char,' ')) > 1;

  CURSOR c_order_ref_item(I_order_no NUMBER,
                          I_item     VARCHAR2) IS
  SELECT ref_item
    FROM ORDSKU
   WHERE order_no = I_order_no
     AND item = I_item;

BEGIN

   smr_sdc_944.pv_alloc_no := -1;

   sho(L_program);

   --preprocess by cleaning out records in custom table where they are no longer relevant.
   DELETE FROM SMR_944_NEW_ALLOC_DETAIL sad
    WHERE NOT EXISTS ( SELECT ah.alloc_no
                        FROM ALLOC_HEADER ah
                       WHERE ah.alloc_no = sad.alloc_no);

   --ignore supplier in file and take supplier from RMS
   UPDATE SMR_856_DATA_CONVERSION_USE ssu
      set ssu.vendor = nvl((SELECT oh.supplier
                              FROM ORDHEAD oh
                             WHERE oh.order_no = ssu.order_no),ssu.vendor);

   DELETE FROM SMR_856_DATA_CONVERSION_USE WHERE nvl(QTY_TO_BE_RECEIVED,0) = 0 AND nvl(EXCEPTION_QTY,0) = 0;

   sho('=========================================================================================================');
   sho('PRE receipt loop');
   sho('=========================================================================================================');


--pdd--
--pdd--              sho('=========================================================================================================');
--pdd--              sho('PRE receipt loop');
--pdd--              sho('=========================================================================================================');
--pdd--
--pdd--              FOR rec in c_receipts loop
--pdd--
--pdd--                 sho('Receipt Process carton/'||L_container_id||' ord/'||rec.L_po_nbr||' item/'||rec.L_item_id||' loc/'||rec.L_dest_id);
--pdd--
--pdd--           --      smr_order_rcv_sql.p_bill_to_loc := rec.L_dest_id;
--pdd--
--pdd--           --      L_unit_cost := null;
--pdd--           --
--pdd--           --      open  c_unit_cost(rec.L_po_nbr,
--pdd--           --                        rec.L_item_id);
--pdd--           --      fetch c_unit_cost into L_unit_cost;
--pdd--           --      close c_unit_cost;
--pdd--
--pdd--                 if SMR_SDC_944.make_item_loc(O_error_message,
--pdd--                                              rec.L_item_id,
--pdd--                                              rec.L_dest_id ,
--pdd--                                              'S') = false then
--pdd--                     return false;
--pdd--                 end if;
--pdd--
--pdd--                 if SMR_SDC_944.make_item_loc(O_error_message,
--pdd--                                              rec.L_item_id,
--pdd--                                              rec.L_dc_dest_id ,
--pdd--                                              'W') = false then
--pdd--                     return false;
--pdd--                 end if;
--pdd--
--pdd--                 if CREATE_CARTON(O_error_message,
--pdd--                                  rec.L_container_id,
--pdd--                                  rec.L_dest_id) = false then
--pdd--                     return false;
--pdd--                 end if;
--pdd--
--pdd--                 L_distro_doc_type := NULL;
--pdd--                 L_distro_nbr := NULL;
--pdd--
--pdd--                 open  C_pre_mark_ind(rec.L_po_nbr);
--pdd--                 fetch C_pre_mark_ind into L_pre_mark_ind;
--pdd--                 close C_pre_mark_ind;
--pdd--
--pdd--                 IF L_pre_mark_ind = 'Y' THEN
--pdd--
--pdd--                    L_distro_doc_type := 'A';
--pdd--
--pdd--                    --
--pdd--                    IF explode_buyer_pack_allocation(O_error_message,
--pdd--                                                     rec.L_po_nbr,
--pdd--                                                     rec.L_item_id,
--pdd--                                                     9401,
--pdd--                                                     'Created for ASN conversion.',
--pdd--                                                     rec.L_dest_id,
--pdd--                                                     rec.L_unit_qty) = FALSE THEN
--pdd--                       return false;
--pdd--                    END IF;
--pdd--
--pdd--                    --check amount available and amount on receipt and allow more shipped than originally allocated
--pdd--                    open c_distro_no(rec.L_po_nbr
--pdd--                                    ,rec.L_item_id
--pdd--                                    ,rec.L_dest_id);
--pdd--                    fetch c_distro_no into L_distro_nbr, L_qty_available;
--pdd--                    close c_distro_no;
--pdd--
--pdd--                    open  c_to_be_shipped(rec.L_po_nbr,
--pdd--                                          rec.L_item_id,
--pdd--                                          rec.L_dest_id,
--pdd--                                          rec.L_dc_dest_id);
--pdd--                    fetch c_to_be_shipped into L_qty_shipped;
--pdd--                    close c_to_be_shipped;
--pdd--
--pdd--                    IF L_qty_shipped > L_qty_available THEN
--pdd--
--pdd--                       UPDATE alloc_detail
--pdd--                          SET qty_allocated = qty_allocated + (L_qty_shipped - L_qty_available),
--pdd--                              qty_prescaled = qty_prescaled + (L_qty_shipped - L_qty_available)
--pdd--                        WHERE alloc_no = L_distro_nbr
--pdd--                          AND to_loc = rec.L_dest_id;
--pdd--
--pdd--                    END IF;
--pdd--
--pdd--
--pdd--                 END IF;
--pdd--
--pdd--              END LOOP;


   sho('=========================================================================================================');
   sho('PRE BOL');
   sho('=========================================================================================================');

   FOR rec_outer IN c_multiple_upc LOOP
   --order_no, sku_char item, carton_id
      FOR rec_inner IN c_order_ref_item(rec_outer.order_no,
                                        rec_outer.item) LOOP

          IF rec_inner.ref_item IS NOT NULL THEN

             UPDATE SMR_856_DATA_CONVERSION_USE ssd
                set upc_char  = rec_inner.ref_item
              WHERE carton_id = rec_outer.carton_id
                AND sku_char  = rec_outer.item;

          ELSE

             UPDATE SMR_856_DATA_CONVERSION_USE ssd
                set upc_char  = (SELECT min(ssd2.upc_char)
                                   FROM SMR_856_DATA_CONVERSION_USE ssd2
                                  WHERE carton_id = rec_outer.carton_id
                                    AND sku_char  = rec_outer.item
                                    AND upc_char IS NOT NULL)
              WHERE carton_id = rec_outer.carton_id
                AND sku_char  = rec_outer.item;

          END IF;

      END LOOP;

   END LOOP;

   --create AND ship SDC ASNs
   FOR rec_shipment IN c_bol_shipment LOOP

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

      FOR rec_shipsku IN c_bol_shipsku(rec_shipment.carton_id) LOOP

         L_distro_doc_type := NULL;
         L_distro_nbr := NULL;

         OPEN c_distro_no(rec_shipsku.order_no
                         ,rec_shipsku.item
                         ,rec_shipment.to_loc);
         FETCH c_distro_no INTO L_distro_nbr, L_qty_available;
         CLOSE c_distro_no;

         IF L_distro_nbr IS NOT NULL THEN
            L_distro_doc_type := 'A';
         ELSE
            O_ERROR_MESSAGE := 'No allocation found for order '||rec_shipsku.order_no ||' Item '||rec_shipsku.item||' store '||rec_shipment.to_loc;
            RETURN FALSE;
         END IF;

         INSERT INTO BOL_SHIPSKU (BOL_NO
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

         UPDATE ALLOC_HEADER
            SET WH = (rec_shipment.FROM_loc * 10 + 1)
          WHERE alloc_no = L_distro_nbr;

      sho('Process carton/'||rec_shipsku.carton_id||' item/'||rec_shipsku.item||' loc/'||rec_shipment.to_loc||' wh/'||rec_shipment.from_loc);

      END LOOP;

      IF SHIP_DISTROS(O_ERROR_MESSAGE,
                      L_bol_no) = FALSE THEN
        RETURN FALSE;
      END IF;

      --reset the allocation wh after we temporarily changed it to process this file.
      UPDATE ALLOC_HEADER
         SET WH = 9401
       WHERE WH IN (9521,9531,9541);

   END LOOP;

   sho('=========================================================================================================');
   sho('update alc_alloc');
   sho('=========================================================================================================');

   UPDATE ALC_ALLOC SET STATUS = '3'
    WHERE status = '2'
      AND ALLOC_ID IN (SELECT DISTINCT ax.alloc_id
                         FROM ALC_XREF ax,
                              SHIPSKU sk,
                              SMR_856_DATA_CONVERSION_USE ssd
                        WHERE ax.xref_alloc_no = sk.distro_no
                          AND ax.item_id       = sk.item
                          AND ax.item_id       = ssd.sku_char
                          AND ax.order_no = ssd.order_no
                          AND ax.order_no IS NOT NULL
                          AND sk.CARTON = ssd.carton_id
                          AND sk.distro_type = 'A');

smr_sdc_944.pv_alloc_no := null;

--pdd   sho('=========================================================================================================');
--pdd   sho('Delete SMR_856_DATA_CONVERSION_USE');
--pdd   sho('=========================================================================================================');
--pdd
--pdd   DELETE FROM SMR_856_DATA_CONVERSION_USE;

   sho('=========================================================================================================');
   sho('DONE');
   sho('=========================================================================================================');

   RETURN TRUE;
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

-------------------------------------------------------------------------------------------
-- FUNCTION: F_VALIDATE_FILE
-- Purpose:  USED TO VALIDATE THE DATA IN THE 944 FILE AS LOADED INTO TABLE smr_944_sqlload_data
--------------------------------------------------------------------------------------------
FUNCTION F_VALIDATE_FILE(O_error_message IN OUT VARCHAR2)
 RETURN BOOLEAN IS
   L_program VARCHAR2(61) := package_name || '.F_VALIDATE_FILE';

BEGIN

   sho(L_program);

   --Invalid Order
   INSERT INTO SMR_856_DATA_CONVERSION_ERR
   SELECT ssd.*, NULL, '01-Jan-1900'
     FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE( NOT EXISTS (SELECT 'X' FROM ORDHEAD oh WHERE oh.order_no = nvl(ssd.order_no,-1) AND oh.status IN ('A','C')))
       OR( NOT EXISTS (SELECT 'X' FROM ITEM_MASTER im WHERE im.item = nvl(ssd.sku_char,' '))
           AND NOT EXISTS (SELECT 'X' FROM ITEM_MASTER im WHERE im.item_parent = nvl(ssd.sku_char,' ') AND im.item = ssd.upc_char AND ssd.upc_char IS NOT NULL))
       OR( NOT EXISTS (SELECT 'X' FROM ORDHEAD oh WHERE oh.order_no = nvl(ssd.order_no,-1) AND oh.supplier = nvl(ssd.vendor,-1)))
       OR( NOT EXISTS (SELECT 'X' FROM STORE st WHERE st.STORE = nvl(ssd.STORE,-1)))
       OR( EXISTS (SELECT 'x'
                     FROM ORDHEAD oh
                    WHERE ssd.order_no = oh.order_no
                      AND oh.pre_mark_ind = 'Y'
                      AND NOT EXISTS (SELECT 'x'
                                        FROM ALLOC_HEADER ah,
                                             ALLOC_DETAIL ad
                                       WHERE ah.order_no = ssd.order_no
                                         AND ah.alloc_no = ad.alloc_no
                                         AND ad.to_loc   = ssd.STORE)))
       OR( NOT EXISTS (SELECT 'X' FROM ITEM_SUPPLIER isp WHERE isp.item = nvl(ssd.sku_char,' ') AND isp.supplier = nvl(ssd.vendor,-1))
           AND NOT EXISTS (SELECT 'X' FROM ORDLOC ol WHERE ol.item = nvl(ssd.sku_char,' ') AND ol.order_no = nvl(ssd.order_no,-1)))
       OR( nvl(ssd.qty_to_be_received,-1) <= 0)
       OR( nvl(ssd.qty_to_be_received,-1) < nvl(ssd.exception_qty,0))
       OR( EXISTS (SELECT oh.order_no
                     FROM ORDHEAD oh
                    WHERE oh.order_no = ssd.order_no
                      AND ssd.rcv_date > (oh.not_after_date + 9999)))
       OR ( NOT EXISTS (SELECT 'x' FROM ITEM_LOC WHERE item = ssd.sku_char AND loc_type = 'S' AND clear_ind = 'N' AND ROWNUM < 2))
       OR ( EXISTS (SELECT 'x' FROM ITEM_LOC il WHERE il.item = ssd.sku_char AND il.loc = (ssd.whse_location*10+1))
            AND NOT EXISTS (SELECT 'x' FROM ITEM_LOC_SOH ils WHERE ils.item = ssd.sku_char AND ils.loc = (ssd.whse_location*10+1)))
       OR (EXISTS (SELECT 'x' FROM CARTON WHERE CARTON = ssd.carton_id AND LOCATION != ssd.STORE))
       OR (length(ssd.carton_id) != 20)
       or exists (select 'x' from store st where st.store = ssd.store and nvl(st.store_close_date,'01-Jan-2999') < get_vdate);

    IF SQL%ROWCOUNT = 0 THEN
       sho('no errors');
       RETURN TRUE;
    END IF;

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE NOT EXISTS (SELECT 'X' FROM ORDHEAD oh WHERE oh.order_no = nvl(ssd.order_no,-1) AND oh.status IN ('A','C'));

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE NOT EXISTS (SELECT 'X' FROM ITEM_MASTER im WHERE im.item = nvl(ssd.sku_char,' '))
      AND NOT EXISTS (SELECT 'X' FROM ITEM_MASTER im WHERE im.item_parent = nvl(ssd.sku_char,' ') AND im.item = ssd.upc_char AND ssd.upc_char IS NOT NULL);

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE NOT EXISTS (SELECT 'X' FROM ORDHEAD oh WHERE oh.order_no = nvl(ssd.order_no,-1) AND oh.supplier = nvl(ssd.vendor,-1));

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE NOT EXISTS (SELECT 'X' FROM STORE st WHERE st.STORE = nvl(ssd.STORE,-1));

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE NOT EXISTS (SELECT 'x'
                        FROM ALLOC_HEADER ah,
                             ALLOC_DETAIL ad
                       WHERE ah.alloc_no = ad.alloc_no
                         AND ah.order_no = ssd.order_no
                         AND ad.to_loc   = ssd.STORE
                         AND ROWNUM = 1);

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE NOT EXISTS (SELECT 'X' FROM ITEM_SUPPLIER isp WHERE isp.item = nvl(ssd.sku_char,' ') AND isp.supplier = nvl(ssd.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ORDLOC ol WHERE ol.item = nvl(ssd.sku_char,' ') AND ol.order_no = nvl(ssd.order_no,-1));

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE nvl(ssd.qty_to_be_received,-1) <= 0;

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE nvl(ssd.qty_to_be_received,-1) < nvl(ssd.exception_qty,0);

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE EXISTS (SELECT oh.order_no
                    FROM ORDHEAD oh
                   WHERE oh.order_no = ssd.order_no
                     AND ssd.rcv_date > (oh.not_after_date + 9999));

    DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
     WHERE NOT EXISTS (SELECT 'x' FROM ITEM_LOC WHERE item = ssd.sku_char AND loc_type = 'S' AND clear_ind = 'N' AND ROWNUM < 2);

    DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
      WHERE ( EXISTS (SELECT 'x' FROM ITEM_LOC il WHERE il.item = ssd.sku_char AND il.loc = (ssd.whse_location*10+1))
            AND NOT EXISTS (SELECT 'x' FROM ITEM_LOC_SOH ils WHERE ils.item = ssd.sku_char AND ils.loc = (ssd.whse_location*10+1)));

    DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
     WHERE (EXISTS (SELECT 'x' FROM CARTON WHERE CARTON = ssd.carton_id AND LOCATION != ssd.STORE));

    DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
     WHERE length(ssd.carton_id) != 20;

    DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
      where exists (select 'x' from store st where st.store = ssd.store and nvl(st.store_close_date,'01-Jan-2999') < get_vdate);

   INSERT INTO SMR_856_DATA_CONVERSION_ERR
   SELECT ssd.*, NULL, '01-Jan-1900'
     FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE EXISTS (SELECT 'x'
                    FROM SMR_856_DATA_CONVERSION_ERR sse
                   WHERE sse.carton_id = ssd.carton_id);

   DELETE FROM SMR_856_DATA_CONVERSION_USE ssd
    WHERE EXISTS (SELECT 'x'
                    FROM SMR_856_DATA_CONVERSION_ERR sse
                   WHERE sse.carton_id = ssd.carton_id
                     AND ERROR_DATE = '01-Jan-1900');

   --Invalid Order
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = 'Invalid Order'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM ORDHEAD oh WHERE oh.order_no = NVL(sse.order_no,-1) AND oh.status IN ('A','C'));

   --Invalid SKU
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,error_msg,error_msg||';') || 'Invalid Item'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM ITEM_MASTER im WHERE im.item = NVL(sse.sku_char,' '))
      AND NOT EXISTS (SELECT 'X' FROM ITEM_MASTER im WHERE im.item_parent = NVL(sse.sku_char,' ') AND im.item = sse.upc_char AND sse.upc_char IS NOT NULL);

   --Invalid supplier
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid supplier'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM ORDHEAD oh WHERE oh.order_no = NVL(sse.order_no,-1) AND oh.supplier = NVL(sse.vendor,-1));

   --Invalid Store
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid Store'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM STORE st WHERE st.STORE = NVL(sse.STORE,-1));

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid Store for allocation'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'x'
                        FROM ALLOC_HEADER ah,
                             ALLOC_DETAIL ad
                       WHERE ah.order_no = sse.order_no
                         AND ah.alloc_no = ad.alloc_no
                         AND ad.to_loc   = sse.STORE
                         AND ROWNUM = 1);

   --Invalid SKU for PO and supplier - already checked above that sku is valid in RMS
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid Item for Order and supplier'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'X' FROM ITEM_SUPPLIER isp WHERE isp.item = NVL(sse.sku_char,' ') AND isp.supplier = NVL(sse.vendor,-1))
      AND NOT EXISTS (SELECT 'X' FROM ORDLOC ol WHERE ol.item = NVL(sse.sku_char,' ') AND ol.order_no = NVL(sse.order_no,-1));

   --Received QTY <= 0
   UPDATE SMR_856_DATA_CONVERSION_ERR
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid quantity received'
    WHERE error_date = '01-Jan-1900'
      AND NVL(qty_to_be_received,-1) <= 0;

   --Exception QTY > qty_to_be_received
   UPDATE SMR_856_DATA_CONVERSION_ERR
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Adjustment ('||exception_qty||') greater than receipt ('||qty_to_be_received||')'
    WHERE error_date = '01-Jan-1900'
      AND nvl(qty_to_be_received,0) < nvl(exception_qty,0);

   --Too long after not after date
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid Receive Date'
    WHERE error_date = '01-Jan-1900'
      AND EXISTS (SELECT oh.order_no
                    FROM ORDHEAD oh
                   WHERE oh.order_no = sse.order_no
                     AND sse.rcv_date > (oh.not_after_date + 9999));

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Item not at any store (excl clearance).'
    WHERE error_date = '01-Jan-1900'
      AND NOT EXISTS (SELECT 'x' FROM ITEM_LOC WHERE item = sse.sku_char AND loc_type = 'S' AND clear_ind = 'N' AND ROWNUM < 2);

  --missing rms item_loc_soh
   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Missing item_loc_soh'
    WHERE error_date = '01-Jan-1900'
      AND ( EXISTS (SELECT 'x' FROM ITEM_LOC il WHERE il.item = sse.sku_char AND il.loc = (sse.whse_location*10+1))
            AND NOT EXISTS (SELECT 'x' FROM ITEM_LOC_SOH ils WHERE ils.item = sse.sku_char AND ils.loc = (sse.whse_location*10+1)));

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Carton already received'
    WHERE error_date = '01-Jan-1900'
      AND (EXISTS (SELECT 'x' FROM CARTON WHERE CARTON = sse.carton_id AND LOCATION != sse.STORE));

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Invalid Carton'
    WHERE error_date = '01-Jan-1900'
      AND length(carton_id) != 20;

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = decode(error_msg,NULL,'',error_msg||';') || 'Store Closed'
    WHERE error_date = '01-Jan-1900'
      and exists (select 'x' from store st where st.store = sse.store and nvl(st.store_close_date,'01-Jan-2999') < get_vdate);

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
      SET error_msg = 'Other item in carton failed'
    WHERE error_date = '01-Jan-1900'
      AND error_msg IS NULL
      AND EXISTS (SELECT 'x'
                    FROM SMR_856_DATA_CONVERSION_ERR sse2
                   WHERE sse2.carton_id = sse.carton_id
                     AND sse2.error_msg IS NOT NULL);

   UPDATE SMR_856_DATA_CONVERSION_ERR sse
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


END;
/