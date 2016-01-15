CREATE OR REPLACE PACKAGE BODY SMR_CUSTOM_RCA IS
-- Module Name: SMR_CUSTOM_RCA
-- Description: This package will be used for custom receipt adjustments.
--              It is called from the base Receipt Unit Adjustment form.
--
-- Modification History
-- Version Date      Developer   Issue     Description
-- ======= ========= =========== ========  =========================================
-- 1.00    19-Mar-12 P.Dinsdale  ENH 38    Original.
-- 1.01    14-Nov-12 P.Dinsdale  IMS135350 Added TC13 to cover scenario where item
--                                         has gone on clearance since original shipment
-- 1.02    02-Jan-13 P.Dinsdale  IMS142106 Consider UP charges
-- 1.03    20-Mar-13 P.Dinsdale  IMS151918 Do not allow qty expected and received to go below 0
                                           --for c_driving_cursor in F_PROCESS_ADJUSTMENT,
                                           --replace all references to rec.adj_qty with L_new_adj_qty
                                           --so we can reset it at the top if adj qty is less
                                           --than SDC to store expected qty * -1
-- 1.04    23-APR-13 S.Sadineni  IMS158839 Fix to Update item_loc_soh statements to update
--                                         last_update_datetime
-- 1.05    21-May-13 S.Peterson  IMS162932 If shipsku records were created as part of adjustment processing,
--                                         only update qty_received; else update qty_expected and received.
-- 1.06    06-Jun-13 S.Peterson  IMS164687 Update alloc_detail quantities for adjustments
-- 1.07    11-Jun-13 S.Peterson  IMS159256 Merge code from R.Singh:
--                                         Fix includes updating the item- WH SOH based on the condition- if a
--										   -recent stock count already accounted the inventory, then no
--										   -updates to SOH
-- 1.08    28-Jun-13 S.Peterson  IMS159256 Additional fixes to consider correct warehouse
-- 1.09    02-Jul-13 S.Peterson  IMS159256 If stockcount exists, delete any 22 created by base RMS
-- 1.10    10-Jul-13 S.Peterson  IMS459256 Handle alloc_detail update when qty_transferred is null
-- 1.11    06-Mar-14 L.Tan       IMS187278 Modified function F_PROCESS_ADJUSTMENT so that TC22 record written
--                                         when a proessed stock count coincides with the RCA uses the correct
--                                         TOTAL_RETAIL (not the TOTAL_COST).
-- 1.12    28-Jan-14 R.Samy      ME313598  Incorrect Location Type is populated while inserting
--                               tran code 13 in tran_data for WH.
-- 1.13    22-Sep-14  Murali	 ME391566  Modified function to fetch Unit_cost and retail from Ordloc
--                                         against the wh 9541 ,9521,9531 if no already fetched.
-- 1.14    22-May-15  Murali	 Leap 2    Made Modification to Support Leap2 Changes.
/*
Description :
    The Package smr_custom_rca was modifed to make Changes to the custom RUA packages to adjust the the shipment to the store 
	in case a Xdoc PO Reciept is adjusted. The final destination of a Carton in Xdoc PO can be identified based on the to_loc in the Carton table or the actual_receiving_store in shipsku table.  The Script also Updates the SOH in SIM tables using a DB link.

Algorithm
    - When a RUA is a done for a Xdoc PO the function is SMR_CUSTOM_RCA.F_PROCESS_ADJUSTMENT is invoked.
    - The function F_PROCESS_ADJUSTMENT reverses the store shipment and posts reversal for tran code 30 and 32
    - The function also updates the SOH in SIM using DB link.
    - In case the store shipment does not exist in SIM the RUA for XDOC PO is not done.  */
------------------------------------------------------------------------

------------------------------------------------------------------------
------------------------------------------------------------------------
--PRIVATE Procedures and functions
------------------------------------------------------------------------
------------------------------------------------------------------------
--Used for debug purposes
procedure sho(O_message varchar2) is
 L_debug_on boolean := true;
begin

   if L_debug_on then
      dbms_output.put_line(O_message);
   end if;

end;

--returns true of I_wh is a valid 9401 order SDC
function valid_wh(O_error_message IN OUT VARCHAR2,
                  I_wh            IN     NUMBER,
                  O_wh            IN OUT NUMBER) return boolean is
Cursor C_get_vwh is
  select wh.wh
    from wh , wh_attributes w
   where wh.wh = w.wh
     and wh.physical_wh = I_wh
     and w.wh_type_code = 'XD';

begin

      if I_wh is null then
         O_error_message := 'Warehouse cannot be null';
         return false;
      -- V1.14 Leap2 Start
      /*
      elsif I_wh = 952 OR
            I_wh = 953 OR
            I_wh = 954 then
         O_wh := (I_wh * 10) + 1;
      ELSE
         O_error_message := 'Invalid Warehouse: '||I_wh;
         return false;  */
      -- V1.14 Leap2 End
      end if;

      -- V1.14 Leap2 Start
      Open C_get_vwh;

      Fetch C_get_vwh into O_wh;

      if C_get_vwh%notfound then
         Close C_get_vwh;
         O_error_message := 'Invalid Warehouse: '||I_wh;
         return false;
      end if;

      Close C_get_vwh;
      -- V1.14 Leap2 End

      return true;

end;

---------------------------------------------------------------------------------------------
-- Function : F_PROCESS_ADJUSTMENT
-- Purpose  : Process adjustment in custom table
---------------------------------------------------------------------------------------------
FUNCTION F_PROCESS_ADJUSTMENT(O_error_message      IN OUT VARCHAR2,
                              I_smr_recipt_adj_seq IN     NUMBER)
   RETURN BOOLEAN IS
   L_program VARCHAR2(61) := package_name || '.F_PROCESS_ADJUSTMENT';

   L_wh      number(10);

   --Process record in smr_recipt_adj for parameter I_smr_recipt_adj_seq
   --or Loop through all available records in smr_recipt_adj if I_smr_recipt_adj_seq is null
   cursor c_driving_cursor is
   select smr_recipt_adj_seq,
          wh,
          shipment,
          adj_qty,
          item,
          carton,
          seq_no,
          error_msg
     from smr_recipt_adj sra
    where smr_recipt_adj_seq = nvl(I_smr_recipt_adj_seq,smr_recipt_adj_seq)
    order by 1;

    --get shipment wh to store details for a specific carton/item from a specific wh
    cursor c_alloc_and_store(I_carton varchar2,
                             I_wh     number,
                             I_item   varchar2) is
    select sh.shipment, sk.distro_no, sh.to_loc, sh.bol_no
      from shipsku sk,
           shipment sh
     where sh.shipment = sk.shipment
       and sk.carton = I_carton
       and sh.from_loc = I_wh
       -- V1.14 Leap2 Start
      -- and sh.to_loc in (select bill_to_loc from shipment where asn = I_carton)
      and sh.to_loc in (select c.location from Carton c where c.carton = I_carton)
       -- V1.14 Leap2 End
       and sk.item = I_item;

    L_shipment  shipment.shipment%type;
    L_distro_no shipsku.distro_no%type;
    L_store     store.store%type;
    L_bol_no    shipment.bol_no%type;
    L_return_code varchar2(25);

    --get cost and retail for use in tran code 30/32 transactions.
    cursor c_cost_and_retail(I_adj_qty    number,
                             I_shipment   number,
                             I_carton   varchar2,
                             I_wh         number,
                             I_item     varchar2) is
    select unit_cost * I_adj_qty   total_cost,
           unit_retail * I_adj_qty total_retail
      from shipsku
     where shipment = I_shipment
       and item = I_item
       and carton = I_carton
       and seq_no = (select min(seq_no)
                       from shipsku
                      where shipment = I_shipment
                        and item = I_item);

    L_total_cost  number(12,4);
    L_total_retail number(12,4);

    --OLR V1.01 Insert START
    --get store retail
    cursor c_current_retail_store(I_shipment number,
                                  I_item     varchar2) is
    select unit_retail
      from item_loc
     where item = I_item
       and loc  = (select to_loc from shipment where shipment = I_shipment);

    L_current_retail_store number(12,4);

    cursor c_current_retail_wh(I_wh         number,
                               I_item     varchar2) is
    --get sdc retail
    select unit_retail
      from item_loc
     where item = I_item
       and loc  = I_wh;

    L_current_retail_wh number(12,4);

    L_retail_diff      number;
    --OLR V1.01 Insert END

    --returns a value if wh to store shipment exists
    cursor c_sim_status(I_bol_no VARCHAR2) is
    select status
      from rk_shipments
     where asn_id = I_bol_no;

    L_sim_status varchar2(3);

    --if no details for a specific carton/item from a specific wh can be found,
    --check if shipment exists for carton from store.
    --If it does we will add item to shipment in RMS and SIM.
    cursor c_wh_to_store_ship(I_wh     number,
                              I_carton varchar2) is
    select sh.shipment, sh.bol_no, sh.to_loc store, max(seq_no) seq_no
      from shipment sh,
           shipsku  sk
     where sh.shipment = sk.shipment
       and sh.from_loc = I_wh
       and sk.carton = I_carton
     group by sh.shipment, sh.bol_no, sh.to_loc;

    L_store_shipment number(10);
    L_seq_no         number(10);

    --gets order number for a shipment, used to get order number for
    --shipment from vendor to wh
    cursor c_order_no(I_shipment number) is
    select order_no
      from shipment
     where shipment = I_shipment;

    L_order_no number;

    --gets unit retail for an order/item for use in shipsku creation
    cursor c_unit_and_retail(I_order_no number,
                             I_item     varchar2) is
    select unit_cost,
           unit_retail
      from ordloc
     where order_no = I_order_no
       and item = I_item
       and location = 9401;

    --if item is not on order, then cursor c_unit_and_retail above will return nothing.
    --eg if only item on order is buyer pack and shipment is for component item.
    --SMR have workarounds in place that a buyer pack on an order will be exploded to its components
    --but we will have a second query just in case:
    --Get cost and retail from tran data.
    cursor c_unit_and_retail_2(I_shipment number,
                               I_item     varchar2) is
    select total_cost   / units unit_cost,
           total_retail / units unit_retail
      from tran_data
     where tran_code = 20
       and item = I_item
       and ref_no_2 = I_shipment;

    --Unlikely to every run this query, so it is here just in case.
    --Query will run if item not on order, and receipt adjustment at wh done the day before the wh-store adjustment.
    cursor c_unit_and_retail_3(I_shipment number,
                               I_item     varchar2) is
    select total_cost   / units unit_cost,
           total_retail / units unit_retail
      from tran_data_history
     where tran_code = 20
       and item = I_item
       and ref_no_2 = I_shipment
      order by tran_date desc;

	-- V1.13
    --gets unit retail for an order/item from ordloc
    cursor c_unit_and_retail_4(I_order_no number,
                               I_item     varchar2,
                               I_wh     number) is
    select unit_cost,
           unit_retail
      from ordloc
     where order_no = I_order_no
       and item = I_item
       and location = I_wh;

    L_unit_cost   number;
    L_unit_retail number;

    --Get allocation number for c/store
    cursor c_distro_no(I_order_no number,
                       I_item     varchar2,
                       I_store    number) is
    select ah.alloc_no
      from alloc_header ah,
           alloc_detail ad
     where ah.alloc_no = ad.alloc_no
       and ah.order_no = I_order_no
       and ah.item = I_item
       and ad.to_loc = I_store;

    --get allocation header details for order/item
    CURSOR c_distro_header(I_order_no number,
                           I_item varchar2) is
    SELECT ah.status,
           ah.alloc_method,
           ah.order_type
      FROM alloc_header ah
     where order_no = I_order_no
       --only make a header record if it does not exist.
       and not exists (select 'x' from alloc_header where order_no = I_order_no and item = I_item)
       and rownum < 2;


    --if we did not have to make allocation heder, but will have to make allocation detail,
    --use this cursor to get header allocation number
    CURSOR c_alloc_no(I_order_no number,
                      I_item varchar2) is
    SELECT ah.alloc_no
      FROM alloc_header ah
     where order_no = I_order_no
       and item = I_item
       and rownum < 2;

    /*
    --returns Y if allocation detail is one we manually created
    cursor c_custom_alloc_detail(I_alloc_no number,
                                 I_store    number) is
    select 'Y'
      from smr_944_new_alloc_detail
     where alloc_no = I_alloc_no
       and to_loc = I_store;

    L_custom_alloc_detail varchar2(1);
    */

    --get details for alloc_detail if we have to create it.
    CURSOR c_distro_detail(I_order_no number,
                           I_store    number)is
    SELECT ad.non_scale_ind
      FROM alloc_detail ad,
           alloc_header ah
     where ah.alloc_no = ad.alloc_no
       and ah.order_no = I_order_no
       and ad.to_loc = I_store
       and rownum < 2;


    L_next_rk_shipment_item_seq number;

    --OLR V1.02 Insert START
    cursor c_up_charges(I_adj_qty    number,
                        I_item varchar2,
                        I_wh   number,
                        I_store number) is
    select sum((I_adj_qty / PER_COUNT) * COMP_RATE) up_charge
      from item_chrg_detail icd
     where item = I_item
       and from_loc = I_wh
       and to_loc = I_store;

    L_up_charges number(10,4);
    --OLR V1.02 Insert END

    --OLR V1.03 Insert START
   L_new_adj_qty number;

   --if adjustment to SDC shipment is greater than can be adjusted on SDC to store shipment,
   --then make adjustment amount max available on SDC to store shipment
   cursor c_exp_qty(l_adj_qty  number,
                    I_shipment number,
                     I_item     varchar2) is
   select case when (l_adj_qty < 0) then greatest (l_adj_qty,-1 * qty_expected)
          else l_adj_qty
         end
     from shipsku
    where shipment = I_shipment
      and item = I_item;

   L_exp_qty number;
   --OLR V1.03 Insert END

   --OLR V1.07 Insert START
   --get the PO receipt date for a specific carton/item from a specific wh
    --cursor c_wh_receipt_date(I_carton varchar2,   -- OLR V1.08 Removed
   cursor c_receipt_date (I_carton varchar2,        -- OLR V1.08 Inserted
                          --I_wh     number,        -- OLR V1.08 Removed
                          I_loc      number,        -- OLR V1.08 Inserted
                          I_item     varchar2,
			   		      I_shipment number) is
    select sh.receive_date
      from shipsku sk,
           shipment sh
     where sh.shipment = sk.shipment
	   and sh.shipment = I_shipment
       and sk.carton = I_carton
       --and sh.to_loc = I_wh  -- OLR V1.08 Removed
       and sh.to_loc = I_loc   -- OLR V1.08 Inserted
       and sk.item = I_item;

    L_receipt_date  shipment.receive_date%type;
	--L_stock_count_processed	boolean	:=NULL;  -- OLR v1.09 Removed
	L_stock_count_processed	BOOLEAN	:= FALSE;    -- OLR v1.09 Inserted
	L_cycle_count	stake_head.cycle_count%type;
	--OLR V1.07 Insert END

BEGIN

   --remove unprocess records that can no longer be processed.
   delete from smr_recipt_adj sra
    where not exists (select 'x' from shipment where shipment = sra.shipment);

   --OLR V1.01 Insert START
    delete from smr_recipt_adj sra
    where smr_recipt_adj_seq = nvl(I_smr_recipt_adj_seq,smr_recipt_adj_seq)
      and nvl(adj_qty,0) = 0;
   --OLR V1.01 Insert END

   sho('loop through driving cursor');
   for rec in c_driving_cursor loop

      L_new_adj_qty := rec.adj_qty; --OLR V1.03 Inserted

      if I_smr_recipt_adj_seq is not null then
         savepoint before_wh_to_store_ship_adj;
      end if;

      sho('for '||rec.carton||'/'||rec.wh||'/'||rec.item);

      --reset loop variables
      L_wh                        := null;
      L_shipment                  := null;
      L_distro_no                 := null;
      L_store                     := null;
      L_bol_no                    := null;
      L_return_code               := null;
      L_total_cost                := null;
      L_total_retail              := null;
      L_sim_status                := null;
      L_store_shipment            := null;
      L_seq_no                    := null;
      L_order_no                  := null;
      L_unit_cost                 := null;
      L_unit_retail               := null;
--      L_custom_alloc_detail       := null;
      L_next_rk_shipment_item_seq := null;


      sho('Process '||rec.smr_recipt_adj_seq);

      --reset error message
      update smr_recipt_adj
         set error_msg = null
       where smr_recipt_adj_seq = rec.smr_recipt_adj_seq;

      if valid_wh(O_error_message,
                  rec.wh         ,
                  L_wh) = false then
         return false;
      end if;

      sho('get wh-store shipment info');

      open  c_alloc_and_store(rec.carton, rec.wh, rec.item);
      fetch c_alloc_and_store into L_shipment, L_distro_no, L_store, L_bol_no;
      close c_alloc_and_store;

      --No warehouse to store shipment found for carton/wh/item
      if L_shipment is null then
         sho('No warehouse to store shipment found for wh/carton/item');
         --O_error_message := 'No warehouse to store shipment found for wh '||rec.wh||', carton '||rec.carton||', item '||rec.item;

         --check if wh to store shipment exists
         open c_wh_to_store_ship(rec.wh,
                                 rec.carton);
         fetch c_wh_to_store_ship into L_store_shipment, L_bol_no, L_store, l_seq_no;
         close c_wh_to_store_ship;

         sho('Checking warehouse to store shipment for carton/wh');
         if L_store_shipment is null then

          --OLR V1.03 Insert START
          if L_new_adj_qty < 0 then
               CONTINUE;
         end if;
          --OLR V1.03 Insert END

            O_error_message := 'No shipment exists for carton '||rec.carton||' from wh '||rec.wh;
            return false;
         else
            sho('Found wh to store shipment');

            open  c_sim_status(L_bol_no);
            fetch c_sim_status into L_sim_status;
            close c_sim_status;

            if L_sim_status is null then
               O_error_message := 'Warehouse to store shipment exists but is not in SIM - cannot adjust';
               return false;
            else

               --shipment exists in SIM
               sho('wh to store shipment exists in SIM - add item to shipment');

               open  c_order_no(rec.shipment);
               fetch c_order_no into L_order_no;
               close c_order_no;

               --get cost from order
               open  c_unit_and_retail(L_order_no,
                                       rec.item);
               fetch c_unit_and_retail into L_unit_cost,L_unit_retail;
               close c_unit_and_retail;

               if L_unit_cost is null then

                  --get cost from tran_data
                  open c_unit_and_retail_2(rec.shipment,
                                           rec.item    );
                  fetch c_unit_and_retail_2 into L_unit_cost,L_unit_retail;
                  close c_unit_and_retail_2;

               end if;

               if L_unit_cost is null then

                  --get cost from tran_data_history
                  open c_unit_and_retail_3(rec.shipment,
                                           rec.item    );
                  fetch c_unit_and_retail_3 into L_unit_cost,L_unit_retail;
                  close c_unit_and_retail_3;

               end if;

               -- V 1.13
               if L_unit_cost is null then
                  --get cost from Ordloc
                  open c_unit_and_retail_4(L_order_no,
                                           rec.item ,
                                           L_wh   );
                  fetch c_unit_and_retail_4 into L_unit_cost,L_unit_retail;
                  close c_unit_and_retail_4;
               end if;

               open c_distro_no(L_order_no,
                                rec.item,
                                L_store);
               fetch c_distro_no into L_distro_no;
               close c_distro_no;

               --if no alloc exists - make it
               if L_distro_no is null then

                  --record returned if header is needed
                  for rec_distro_header in c_distro_header(L_order_no,
                                                           rec.item) loop

                     sho('no allocation found for item - make it');

                     NEXT_ALLOC_NO(L_distro_no,
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
                                              comment_desc)
                                      VALUES (L_distro_no,
                                              L_order_no,
                                              -- V1.14 Leap2 Start
                                               --(rec.wh * 10 + 1),
                                               L_wh,
                                              -- V1.14 Leap2 End
                                              rec.item, --item from adjustment, not from allocation header record copied.
                                              rec_distro_header.status,
                                              'Created for custom receipt adjustment.',
                                              rec_distro_header.alloc_method,
                                              rec_distro_header.order_type,
                                              'Created for custom receipt adjustment.');

                  END LOOP;

                  -- L_distro_no will be null if we did NOT have to make the header record
                  if L_distro_no is null then
                     open c_alloc_no(L_order_no, rec.item);
                     fetch c_alloc_no into L_distro_no;
                     close c_alloc_no;
                  end if;

                  /*
                  --L_custom_alloc_detail = Y if the alloc detail exists and is not base
                  open  c_custom_alloc_detail(L_distro_no,L_store);
                  fetch c_custom_alloc_detail into L_custom_alloc_detail;
                  close c_custom_alloc_detail;
                  */
                  FOR rec_distro_detail in c_distro_detail(L_order_no,
                                                           L_store) LOOP

                     /*
                     IF nvl(L_custom_alloc_detail,'N') = 'Y' then
                        sho('update custom allocation detail');
                        UPDATE alloc_detail
                           SET qty_allocated = qty_allocated + rec.adj_qty,
                               qty_prescaled = qty_prescaled + rec.adj_qty
                         WHERE alloc_no = L_distro_no
                           AND to_loc = L_store;

                     ELSE
                     */
                        sho('create custom allocation detail');
                        INSERT INTO alloc_detail(alloc_no,
                                                 to_loc,
                                                 to_loc_type,
                                                 qty_transferred,
                                                 qty_allocated,
                                                 qty_prescaled,
                                                 non_scale_ind)
                                         VALUES (L_distro_no,
                                                 L_store,
                                                 'S',
                                                 0,
                                                 L_new_adj_qty,
                                                 L_new_adj_qty,
                                                 rec_distro_detail.non_scale_ind);
                     /*
                        INSERT INTO smr_944_new_alloc_detail(alloc_no,
                                                             to_loc)
                                                      values (L_distro_no,
                                                              L_store);

                     END IF;
                     */
                  END LOOP;


                  if L_distro_no is null then
                     O_error_message := 'Unable to make allocation for order ' ||L_order_no||', item '||rec.item||', store '||L_store;
                     return false;
                  end if;

               end if;  --if L_distro_no is null then

               sho('insert shipsku '||L_store_shipment);

               insert into shipsku (shipment         ,
                                    seq_no           ,
                                    item             ,
                                    distro_no        ,
                                    distro_type      ,
                                    carton           ,
                                    inv_status       ,
                                    status_code      ,
                                    unit_cost        ,
                                    unit_retail      ,
                                    qty_expected     ,
                                    invc_match_status)
                            VALUES (L_store_shipment,
                                    l_seq_no + 1,
                                    rec.item,
                                    L_distro_no,
                                    'A',
                                    rec.carton,
                                    -1,
                                    'A',
                                    L_unit_cost,
                                    L_unit_retail,
                                    L_new_adj_qty,
                                    'U');

               --now that we have made shipsku records, get shipment details
               open  c_alloc_and_store(rec.carton, rec.wh, rec.item);
               fetch c_alloc_and_store into L_shipment, L_distro_no, L_store, L_bol_no;
               close c_alloc_and_store;

               --Do SIM insert
               select RK_SHIPMENT_ITEM_SEQ.nextval into L_next_rk_shipment_item_seq from dual;

               sho('insert rk_shipment_item '||L_next_rk_shipment_item_seq);

               insert into rk_shipment_item
               select L_next_rk_shipment_item_seq ID,
                      rsc.SHIPMENT_ID              SHIPMENT_ID,
                      rsc.CARTON_ID                CARTON_ID,
                      rec.item                     ITEM_ID,
                      0                            QUANTITY_EXPECTED,
                      null                         QUANTITY_RECEIVED,
                      0                            QUANTITY_DAMAGED,
                      os.supp_pack_size            PACK_SIZE,
                      null                         UNIT_COST,
                      L_distro_no                  RECEIPT_DOC_ID,
                      'A'                          RECEIPT_DOC_TYPE,
                      'Inserted by '||L_program    COMMENT_DESC,
                      null                         QUANTITY_RECEIVED_DISCREPANT,
                      null                         QUANTITY_DAMAGED_DISCREPANT,
                      null                         RECEIPT_PARENT_DOC_ID
                 from rk_shipment_carton rsc,
                      rk_shipments       rs,
                      ordsku             os
                where rs.shipment_id = rsc.shipment_id
                  and rsc.carton_id = rec.carton
                  and os.order_no = L_order_no
                  and os.item = rec.item;

            end if; --if L_sim_status is null then

         end if; --if L_store_shipment is null then

      end if; --if L_shipment is null then

      --OLR V1.03 Insert START
      sho('set L_new_adj_qty for '||L_shipment||'/'||rec.item||'/'||L_new_adj_qty);

     open  c_exp_qty(L_new_adj_qty,
                     L_shipment,
                     rec.item);
     fetch c_exp_qty into L_new_adj_qty;
     close c_exp_qty;

     --L_new_adj_qty := L_exp_qty;

      sho('set L_new_adj_qty='||L_new_adj_qty);
      --OLR V1.03 Insert END

      --get cost and retail for tran data insert
      open c_cost_and_retail(L_new_adj_qty,
                             L_shipment,
                             rec.carton,
                             rec.wh,
                             rec.item);
      fetch c_cost_and_retail into L_total_cost, L_total_retail;
      close c_cost_and_retail;

      if L_total_cost is null then
         O_error_message := 'No cost information found for shipment '||L_shipment||', wh '||rec.wh||', carton '||rec.carton||', item '||rec.item;
         return false;
      end if;

      --OLR V1.01 Insert START
      open c_current_retail_store(L_shipment,
                            rec.item);
      fetch c_current_retail_store into L_current_retail_store;
      close c_current_retail_store;

      -- V1.14 Leap2 Start   
      open c_current_retail_wh(L_wh,
      -- V1.14 Leap2 End
                               rec.item);
      fetch c_current_retail_wh into L_current_retail_wh;
      close c_current_retail_wh;
       --OLR V1.01 Insert END

      open  c_sim_status(L_bol_no);
      fetch c_sim_status into L_sim_status;
      close c_sim_status;

      if L_sim_status is null then

         sho('Shipment not in SIM');
         rollback to before_wh_to_store_ship_adj;

         update smr_recipt_adj
            set error_msg = 'Shipment not in SIM'
          where smr_recipt_adj_seq = rec.smr_recipt_adj_seq;

         if I_smr_recipt_adj_seq is not null then
            O_error_message := 'Unable to process corresponding warehouse to store shipment. Shipment will be processed once it is in SIM';
            return true;
          end if;

      else
         sho('Shipment in SIM');

          sho('create tran data records');

          --OLR V1.02 Insert START
          L_up_charges := null;

          OPEN  c_up_charges(L_new_adj_qty,
                               rec.item,
                               -- V1.14 Leap2 Start
                                 --(rec.wh * 10 + 1),
                                 L_wh,
                               -- V1.14 Leap2 End
                               L_store);
          FETCH c_up_charges INTO L_up_charges ;
          CLOSE c_up_charges;

            L_up_charges := nvl(L_up_charges,0);

            sho('L_up_charges='||L_up_charges);
          --OLR V1.02 Insert END

            --Transfer Out of WH
            insert into tran_data
            select IM.ITEM                 ITEM
                  ,im.dept                 DEPT
                  ,im.class                CLASS
                  ,im.subclass             SUBCLASS
                  ,null                    PACK_IND
                  ,'W'                     LOC_TYPE
                  ,L_wh                    LOCATION
                  ,get_vdate               TRAN_DATE
                  ,32                      TRAN_CODE
                  ,null                    ADJ_CODE
                  ,L_new_adj_qty             UNITS
                --,L_total_cost            TOTAL_COST      --OLR V1.02 Deleted
                  ,L_total_cost - L_up_charges TOTAL_COST  --OLR V1.02 Inserted
                  ,L_total_retail          TOTAL_RETAIL
                  ,L_distro_no             REF_NO_1
                  ,L_shipment              REF_NO_2
                  ,null                    GL_REF_NO
                  ,null                    OLD_UNIT_RETAIL
                  ,null                    NEW_UNIT_RETAIL
                  ,L_program               PGM_NAME
                  ,NULL                    SALES_TYPE
                  ,NULL                    VAT_RATE
                  ,NULL                    AV_COST
                  ,SYSDATE                 TIMESTAMP
                  ,NULL                    REF_PACK_NO
                  ,NULL                    TOTAL_COST_EXCL_ELC
              FROM item_master IM
             WHERE IM.ITEM = rec.item;

            --Transfer in to store
            insert into tran_data
            select IM.ITEM                 ITEM
                  ,im.dept                 DEPT
                  ,im.class                CLASS
                  ,im.subclass             SUBCLASS
                  ,null                    PACK_IND
                  ,'S'                     LOC_TYPE
                  ,L_store                 LOCATION
                  ,get_vdate               TRAN_DATE
                  ,30                      TRAN_CODE
                  ,null                    ADJ_CODE
                  ,L_new_adj_qty             UNITS
                --,L_total_cost            TOTAL_COST      --OLR V1.02 Deleted
                  ,L_total_cost - L_up_charges TOTAL_COST  --OLR V1.02 Inserted
                  ,L_total_retail          TOTAL_RETAIL
                  ,L_distro_no             REF_NO_1
                  ,L_shipment              REF_NO_2
                  ,null                    GL_REF_NO
                  ,null                    OLD_UNIT_RETAIL
                  ,null                    NEW_UNIT_RETAIL
                  ,L_program               PGM_NAME
                  ,NULL                    SALES_TYPE
                  ,NULL                    VAT_RATE
                  ,NULL                    AV_COST
                  ,SYSDATE                 TIMESTAMP
                  ,NULL                    REF_PACK_NO
                  ,NULL                    TOTAL_COST_EXCL_ELC
              FROM item_master IM
             WHERE IM.ITEM = rec.item;

            --OLR V1.02 Insert START
            IF L_up_charges != 0 THEN

               insert into tran_data
               select IM.ITEM                 ITEM
                     ,im.dept                 DEPT
                     ,im.class                CLASS
                     ,im.subclass             SUBCLASS
                     ,null                    PACK_IND
                     ,'S'                     LOC_TYPE
                     ,L_store                 LOCATION
                     ,get_vdate               TRAN_DATE
                     ,29                      TRAN_CODE
                     ,null                    ADJ_CODE
                     ,L_new_adj_qty             UNITS
                     ,L_up_charges            TOTAL_COST
                     ,0                       TOTAL_RETAIL
                     ,L_distro_no             REF_NO_1
                     ,null                    REF_NO_2
                     ,null                    GL_REF_NO
                     ,null                    OLD_UNIT_RETAIL
                     ,null                    NEW_UNIT_RETAIL
                     ,L_program               PGM_NAME
                     ,NULL                    SALES_TYPE
                     ,NULL                    VAT_RATE
                     ,NULL                    AV_COST
                     ,SYSDATE                 TIMESTAMP
                     ,NULL                    REF_PACK_NO
                     ,NULL                    TOTAL_COST_EXCL_ELC
                 FROM item_master IM
                WHERE IM.ITEM = rec.item;

            END IF;
            --OLR V1.02 Insert END

            --OLR V1.01 Insert START
            if L_current_retail_store is not null and
               L_current_retail_store != (L_total_retail/L_new_adj_qty) then

               L_retail_diff :=  (L_total_retail - (L_current_retail_store * L_new_adj_qty));

               insert into tran_data
               select IM.ITEM                 ITEM
                     ,im.dept                 DEPT
                     ,im.class                CLASS
                     ,im.subclass             SUBCLASS
                     ,null                    PACK_IND
                     ,'S'                     LOC_TYPE
                     ,L_store                 LOCATION
                     ,get_vdate               TRAN_DATE
                     ,13                      TRAN_CODE
                     ,null                    ADJ_CODE
                     ,L_new_adj_qty             UNITS
                     ,null                    TOTAL_COST
                     ,L_retail_diff           TOTAL_RETAIL
                     ,L_distro_no             REF_NO_1
                     ,L_shipment              REF_NO_2
                     ,null                    GL_REF_NO
                     ,(L_total_retail/L_new_adj_qty)  OLD_UNIT_RETAIL
                     ,L_current_retail_store              NEW_UNIT_RETAIL
                     ,L_program               PGM_NAME
                     ,NULL                    SALES_TYPE
                     ,NULL                    VAT_RATE
                     ,NULL                    AV_COST
                     ,SYSDATE                 TIMESTAMP
                     ,NULL                    REF_PACK_NO
                     ,NULL                    TOTAL_COST_EXCL_ELC
                 FROM item_master IM
                WHERE IM.ITEM = rec.item;

             end if;

             if L_current_retail_wh is not null and
                L_current_retail_wh != (L_total_retail/L_new_adj_qty) then

               L_retail_diff :=  (L_total_retail - (L_current_retail_wh * L_new_adj_qty));

               insert into tran_data
               select IM.ITEM                 ITEM
                     ,im.dept                 DEPT
                     ,im.class                CLASS
                     ,im.subclass             SUBCLASS
                     ,null                    PACK_IND
                     --,'S'                   LOC_TYPE --SMR V1.12 Deleted
                     ,'W'                     LOC_TYPE --SMR V1.12 Inserted
                   --,(rec.wh * 10 + 1)       LOCATION --OLR V1.03 Deleted
                     ,L_wh                    LOCATION --OLR V1.03 Inserted
                     ,get_vdate               TRAN_DATE
                     ,13                      TRAN_CODE
                     ,null                    ADJ_CODE
                     ,-1* L_new_adj_qty         UNITS
                     ,null                    TOTAL_COST
                     ,-1 * L_retail_diff
                     ,L_distro_no             REF_NO_1
                     ,L_shipment              REF_NO_2
                     ,null                    GL_REF_NO
                     ,(L_total_retail/L_new_adj_qty)  OLD_UNIT_RETAIL
                     ,L_current_retail_wh           NEW_UNIT_RETAIL
                     ,L_program               PGM_NAME
                     ,NULL                    SALES_TYPE
                     ,NULL                    VAT_RATE
                     ,NULL                    AV_COST
                     ,SYSDATE                 TIMESTAMP
                     ,NULL                    REF_PACK_NO
                     ,NULL                    TOTAL_COST_EXCL_ELC
                 FROM item_master IM
                WHERE IM.ITEM = rec.item;

             end if;
          --OLR V1.01 Insert END

      --OLR V1.07 Insert START
      sho('Fetch Order Receipt Date from Shipment table');

      /* OLR V1.08 Removed  -- START
      open  c_wh_receipt_date(rec.carton, rec.wh, rec.item, rec.shipment);
      fetch c_wh_receipt_date into L_receipt_date;
      close c_wh_receipt_date;
      OLR V1.08 Removed -- END */

      -- OLR V1.08 Inserted -- START
      L_receipt_date := null;
      L_stock_count_processed  := FALSE; -- OLR v1.09 Inserted
      ---
      open  c_receipt_date(rec.carton, rec.wh, rec.item, rec.shipment);
      fetch c_receipt_date into L_receipt_date;
      close c_receipt_date;
      -- OLR V1.08 Inserted -- END

    --Check for an existing stock count that was completed after the Order was received,
    --if yes, then the receipt unit adjustment has to handled such that the Stock On Hand
    --for the WH is not updated again, since through the completed stock count, the adjustment
    --qty was already accounted for.

      if L_receipt_date is not null then
        if STKCNT_ATTRIB_SQL.STOCK_COUNT_PROCESSED(O_error_message,
                              L_stock_count_processed,
                              L_cycle_count,
                              L_receipt_date,
                              rec.item,
                              'W',
                              -- rec.wh) = FALSE then  -- OLR V1.08 Removed
                              L_wh) = FALSE then       -- OLR V1.08 Inserted
          return FALSE;
        end if;
      end if;

      if L_stock_count_processed = FALSE then
        sho('update stock in hand at wh :'||L_wh||'/'||rec.item||'/'||L_new_adj_qty);
        --update stock on hand at wh
        UPDATE item_loc_soh
           SET stock_on_hand = stock_on_hand - L_new_adj_qty,
                       last_update_datetime = sysdate                   -- OLR SMR V1.05 Added
         WHERE loc = L_wh
           AND item = rec.item;
      end if;
      --OLR V1.07 Insert END

      --OLR v1.09 Insert -- START
      -- If a stockcount existed, base RMS wants to back out any portion of that adjustment equal to this RUA
      -- Due to SMR practice of shipping everything, there would have been no actual quantity to count
      -- Therefore, we need to undo the adjustment that was just made
      if L_stock_count_processed = TRUE then
         delete tran_data
          where tran_code = 22
            and adj_code = 'U'
            and item = rec.item
            and location = L_wh
            and loc_type = 'W'
            and ref_no_1 = (select order_no
                              from shipment
                             where shipment = rec.shipment)
            and units = L_new_adj_qty * -1
            and pgm_name = 'ORDER_RCV_SQL.STOCKLEDGER_INFO';

      end if;
      -- OLR v1.09 Insert -- END

    /* OLR V1.07 Delete START
          sho('update stock in hand at wh :'||L_wh||'/'||rec.item||'/'||L_new_adj_qty);
          --update stock in hand at wh
          UPDATE item_loc_soh
             SET stock_on_hand = stock_on_hand - L_new_adj_qty,
                last_update_datetime = sysdate                    -- OLR SMR V1.04 Added
           WHERE loc = L_wh
             AND item = rec.item;
     OLR V1.07 Delete END */

          --0 = NEW (not received in SIM)
          if L_sim_status = 0 then

             sho('Not received in SIM');

             -- L_store_shipment will be null if we did not need to make the wh-store shipsku record, so we should update it with adjustment
             if L_store_shipment is null then
                sho('update shipsku qty_expected');
                UPDATE shipsku SET
                     --qty_expected = nvl(qty_expected,0) + rec.adj_qty             --OLR V1.03 Deleted
                       qty_expected = greatest(nvl(qty_expected,0) + L_new_adj_qty,0) --OLR V1.03 Inserted
                 WHERE shipment = L_shipment
                   AND item = rec.item
                   AND seq_no = (SELECT MIN(seq_no) FROM shipsku WHERE shipment = L_shipment AND ITEM = rec.item);
             end if;

             sho('update in_transit_qty at store'||l_store||'/'||rec.item||'/'||L_new_adj_qty);
             UPDATE item_loc_soh
                SET in_transit_qty = in_transit_qty + L_new_adj_qty,
                    last_update_datetime = sysdate                       -- OLR SMR V1.04 Added
              WHERE loc = l_store
                AND item = rec.item;

             -- OLR v1.06 Inserted -- START
             UPDATE ALLOC_DETAIL
              --SET QTY_TRANSFERRED = QTY_TRANSFERRED + L_new_adj_qty,         -- OLR v1.10 Removed
                SET QTY_TRANSFERRED = nvl(QTY_TRANSFERRED,0) + L_new_adj_qty,  -- OLR v1.10 Inserted
                    QTY_ALLOCATED = CASE WHEN QTY_ALLOCATED - QTY_TRANSFERRED < L_new_adj_qty THEN
                                              QTY_ALLOCATED + (rec.adj_qty - (QTY_ALLOCATED - QTY_TRANSFERRED))
                                         ELSE QTY_ALLOCATED
                                    END,
                    QTY_PRESCALED = CASE WHEN QTY_ALLOCATED - QTY_TRANSFERRED <L_new_adj_qty THEN
                                              QTY_PRESCALED + (rec.adj_qty - (QTY_ALLOCATED - QTY_TRANSFERRED))
                                         ELSE QTY_PRESCALED
                                    END,
                  --QTY_DISTRO = (QTY_DISTRO - L_new_adj_qty),         -- OLR v1.10 Removed
                    QTY_DISTRO = (nvl(QTY_DISTRO,0) - L_new_adj_qty),  -- OLR v1.10 Inserted
                  --PO_RCVD_QTY = PO_RCVD_QTY + L_new_adj_qty          -- OLR v1.10 Removed
                    PO_RCVD_QTY = nvl(PO_RCVD_QTY,0) + L_new_adj_qty   -- OLR v1.10 Inserted
              WHERE ALLOC_NO =  L_distro_no
                AND TO_LOC = L_store;
             -- OLR v1.06 Inserted -- END

             sho('update rk_shipment_item quantity_expected');
             UPDATE rk_shipment_item
                SET quantity_expected = nvl(quantity_expected,0) + L_new_adj_qty
              WHERE carton_id = rec.carton
                AND item_id = rec.item;

             sho('update rk_store_item_soh in_transit_quantity');
             UPDATE rk_store_item_soh
                SET in_transit_quantity = nvl(in_transit_quantity,0) + L_new_adj_qty
              WHERE id_itm = rec.item
                AND id_str_rt = L_store;

          else --(received in SIM)
             sho('Received in SIM');

             sho('update stock_on_hand at store'||L_store||'/'||rec.item||'/'||L_new_adj_qty);

             -- OLR V1.08 Inserted -- START
             L_receipt_date := null;
             L_stock_count_processed := FALSE;
             ---
             open c_receipt_date(rec.carton, L_store, rec.item, L_shipment);
             fetch c_receipt_date into L_receipt_date;
             close c_receipt_date;
             ---
             if L_receipt_date is not null then
                if STKCNT_ATTRIB_SQL.STOCK_COUNT_PROCESSED(O_error_message,
                               L_stock_count_processed,
                               L_cycle_count,
                               L_receipt_date,
                               rec.item,
                               'S',
                               L_store) = FALSE then       -- OLR V1.08 Inserted
                   return FALSE;
        end if;
      end if;
      ---
      if L_stock_count_processed then
      -- the cycle count would have accounted for the invetory by creating adjustments (22s).
      -- Since we created a tsf in (30) for the store we need to back out the 22 by the same amount
      -- using the snapshot cost/retail
               insert into tran_data
               select IM.ITEM                 ITEM
                     ,im.dept                 DEPT
                     ,im.class                CLASS
                     ,im.subclass             SUBCLASS
                     ,null                    PACK_IND
                     ,'S'                     LOC_TYPE
                     ,L_store                 LOCATION
                     ,get_vdate               TRAN_DATE
                     ,22                      TRAN_CODE
                     ,null                    ADJ_CODE
                     ,L_new_adj_qty * -1      UNITS
                     ,s.snapshot_unit_cost * L_new_adj_qty * -1 TOTAL_COST
                     -- ,s.snapshot_unit_cost * L_new_adj_qty * -1 TOTAL_RETAIL -- OLR V1.11 Removed
                     ,s.snapshot_unit_retail * L_new_adj_qty * -1 TOTAL_RETAIL -- OLR V1.11 Inserted
                     ,L_distro_no             REF_NO_1
                     ,L_shipment              REF_NO_2
                     ,null                    GL_REF_NO
                     ,null                    OLD_UNIT_RETAIL
                     ,null                    NEW_UNIT_RETAIL
                     ,L_program               PGM_NAME
                     ,NULL                    SALES_TYPE
                     ,NULL                    VAT_RATE
                     ,NULL                    AV_COST
                     ,SYSDATE                 TIMESTAMP
                     ,NULL                    REF_PACK_NO
                     ,NULL                    TOTAL_COST_EXCL_ELC
                 FROM item_master IM,
                      stake_sku_loc s
                WHERE IM.ITEM = rec.item
                  and im.item = s.item
                  and s.cycle_count = L_cycle_count
                  and s.location = L_store;
             else
             -- OLR V1.08 Inserted -- END
                UPDATE item_loc_soh
                   SET stock_on_hand = stock_on_hand + L_new_adj_qty,
                       last_update_datetime = sysdate                    -- OLR SMR V1.04 Added
                 WHERE item = rec.item
                   AND loc = L_store;
             end if;  -- OLR V1.08 Inserted

             sho('update total_quantity in rk_store_item_soh'||L_store||'/'||rec.item||'/'||L_new_adj_qty);
             UPDATE rk_store_item_soh
                SET total_quantity = nvl(total_quantity,0) + L_new_adj_qty,
                    delivery_bay_quantity = nvl(delivery_bay_quantity,0) + L_new_adj_qty
              WHERE id_itm = rec.item
                AND id_str_rt = L_store;

             sho('update shipsku '||L_shipment||'/'||rec.item||'/'||L_new_adj_qty);

             if L_store_shipment is null then   -- OLR V1.05 Inserted
                UPDATE shipsku SET
                    --qty_expected = nvl(qty_expected,0) + rec.adj_qty,
                    --qty_received = nvl(qty_received,0) + rec.adj_qty
                      qty_expected = greatest(nvl(qty_expected,0) + L_new_adj_qty,0), --OLR V1.03 Inserted
                      qty_received = greatest(nvl(qty_received,0) + L_new_adj_qty,0)  --OLR V1.03 Inserted
                WHERE shipment = L_shipment
                  AND item = rec.item
                  AND seq_no = (SELECT MIN(seq_no) FROM shipsku WHERE shipment = L_shipment AND ITEM = rec.item);
            -- OLR V1.05 Inserted -- START
             else
               UPDATE shipsku
                  SET qty_received = greatest(nvl(qty_received,0) + L_new_adj_qty,0)
                WHERE shipment = L_shipment
                  AND item = rec.item
                  AND seq_no = (SELECT MIN(seq_no) FROM shipsku WHERE shipment = L_shipment AND ITEM = rec.item);
             end if;
            -- OLR V1.05 Inserted -- END

             sho('update rk_shipment_item '||rec.carton||'/'||rec.item||'/'||L_new_adj_qty);
             UPDATE rk_shipment_item
               SET quantity_expected = nvl(quantity_expected,0) + L_new_adj_qty,
                   quantity_received = nvl(quantity_received,0) + L_new_adj_qty
             WHERE carton_id = rec.carton
               AND item_id = rec.item;

             -- OLR V1.06 Inserted -- START
             UPDATE ALLOC_DETAIL
              --SET QTY_TRANSFERRED = QTY_TRANSFERRED + rec.adj_qty,         -- OLR v1.10 Removed
                SET QTY_TRANSFERRED = nvl(QTY_TRANSFERRED,0) + rec.adj_qty,  -- OLR v1.10 Inserted
                    QTY_ALLOCATED = CASE WHEN QTY_ALLOCATED - QTY_TRANSFERRED < L_new_adj_qty THEN
                                              QTY_ALLOCATED + (rec.adj_qty - (QTY_ALLOCATED - QTY_TRANSFERRED))
                                         ELSE QTY_ALLOCATED
                                    END,
                    QTY_PRESCALED = CASE WHEN QTY_ALLOCATED - QTY_TRANSFERRED < rec.adj_qty THEN
                                              QTY_PRESCALED + (L_new_adj_qty - (QTY_ALLOCATED - QTY_TRANSFERRED))
                                         ELSE QTY_PRESCALED
                                    END,
                  --QTY_DISTRO = (QTY_DISTRO - L_new_adj_qty),         -- OLR v1.10 Removed
                    QTY_DISTRO = (nvl(QTY_DISTRO,0) - L_new_adj_qty),  -- OLR v1.10 Inserted
                  --PO_RCVD_QTY = PO_RCVD_QTY + L_new_adj_qty          -- OLR v1.10 Removed
                    PO_RCVD_QTY = nvl(PO_RCVD_QTY,0) + L_new_adj_qty,  -- OLR v1.10 Inserted
                    QTY_RECEIVED = nvl(QTY_RECEIVED,0) + L_new_adj_qty
              WHERE ALLOC_NO =  L_distro_no
                AND TO_LOC = L_store;
             -- OLR V1.06 Inserted -- END

          end if;  --if L_sim_status = 0 then

         sho('delete from smr_recipt_adj '||rec.smr_recipt_adj_seq);
         delete from smr_recipt_adj
          where smr_recipt_adj_seq = rec.smr_recipt_adj_seq;

      end if;

   end loop;

   ---
   return TRUE;

EXCEPTION
   when OTHERS then

      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
      return FALSE;
END F_PROCESS_ADJUSTMENT;

------------------------------------------------------------------------
------------------------------------------------------------------------
--PUBLIC Procedures and functions
------------------------------------------------------------------------
------------------------------------------------------------------------


---------------------------------------------------------------------------------------------
-- Function : F_SAVE_ADJUSTMENT
-- Purpose  : Save adjustment to custom table
---------------------------------------------------------------------------------------------
FUNCTION F_SAVE_ADJUSTMENT(O_error_message IN OUT VARCHAR2,
                           I_wh            IN     NUMBER,
                           I_shipment      IN     NUMBER,
                           I_item          IN     VARCHAR2,
                           I_seq_no        IN     NUMBER,
                           I_adj_qty       IN     NUMBER,
                           I_carton        IN     VARCHAR2)
   RETURN BOOLEAN IS
   L_program VARCHAR2(61) := package_name || '.F_SAVE_ADJUSTMENT';

   L_next_seq number(10);
   L_wh       number;

BEGIN

   if I_wh       is null then O_error_message := 'Warehouse cannot be null.';            return false; end if;
   if I_shipment is null then O_error_message := 'Shipment cannot be null.';             return false; end if;
   if I_item     is null then O_error_message := 'Item cannot be null.';                 return false; end if;
   if I_seq_no   is null then O_error_message := 'Sequne number cannot be null.';        return false; end if;
   if I_adj_qty  is null then O_error_message := 'Adjustment quantity cannot be null.';  return false; end if;
   if I_carton   is null then O_error_message := 'Carton cannot be null.';               return false; end if;

   if valid_wh(O_error_message,
               I_wh           ,
               L_wh           ) = false then
      return false;
   end if;

   select smr_recipt_adj_seq.nextval into L_next_seq from dual;

   insert into smr_recipt_adj  (smr_recipt_adj_seq,
                                wh       ,
                                shipment ,
                                item     ,
                                seq_no   ,
                                adj_qty  ,
                                carton   ,
                                error_msg)
                        values (L_next_seq ,
                                I_wh       ,
                                I_shipment ,
                                I_item     ,
                                I_seq_no   ,
                                I_adj_qty  ,
                                I_carton   ,
                                null);

   if F_PROCESS_ADJUSTMENT(O_error_message              ,
                           L_next_seq ) = false then
      return false;
   end if;

   ---
   return TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             to_char(SQLCODE));
      return FALSE;
END F_SAVE_ADJUSTMENT;

end;
/