CREATE OR REPLACE PACKAGE BODY SMR_LEAP_INTERFACE_SQL as
-------------------------------------------------------------------------------------------------------
-- Procedure Name : SPLIT_TRANSFORM_BULK_ORDER
--
-- Description    : Perform the "Split/Transform" algorthim on a given bulk order-allocation.
--                  Create purchase orders for the actual, correct wh associated with a store.
--                  The "9401" bulk order process remains in place for the buyers and allocators.
--                  The new purchase orders are for the appropriate (actual) wh to receive on.
--                  This eliminates 9401 receiving which, resolves many issues including:
--                  Receiving on 9401 at the wh, then a different PO at the store,
--                  Writing incorrect transactions (over 5 million at this point)
--                  in the stock ledger for 9401 which, then need to be reversed out (the
--                  reversing process itself is also erroneous, requiring many "fixes").
--
-- Algorithm:       1) Select the input order from ordhead,
--                  2) Generate new order_no's based on the default wh (6-digit order_no||3-digit wh),
--                  3) Substitute 9401 for the real cross-dock wh (e.g. 9521,9531,9541),
--                  4) Create as many new orders as are default wh's for stores in the allocation(s),
--                  5) Select a "sample" (1 row) of ordsku, ordloc, alloc_head, alloc_detail,
--                  6) Generate ordsku records related to the new orders,
--                  7) Generate related ordloc recs, spliting order quantities by wh,
--                  8) Generate associated alloc_header records (using the base sequence),
--                  9) Generate alloc_detail records, splitting quantities by item-loc-wh.
--
-- Input Parameters 1) order_no
--
-- Output Parameters - None at this time (error processing is handled through exceptions).
--
-- *Note: No input order/allocation validation is performed here (that is up to the calling procedure).
--
-- Change History:
-- Version Date      Developer  Issue   Description
-- ======= ========= ========== ======= ===============================================================
-- 1.00    02-DEC-14 Steve Fehr         Initial version.
--
-- ======= ========= ========== ======= ===============================================================
PROCEDURE SPLIT_TRANSFORM_BULK_ORDER(I_order_no IN ordhead.order_no%TYPE) IS

  L_item            ITEM_MASTER.ITEM%TYPE := null;
  L_default_wh      STORE.DEFAULT_WH%TYPE := null;
  L_prev_default_wh STORE.DEFAULT_WH%TYPE := 1;
  L_alloc_parent    ALLOC_HEADER.ALLOC_PARENT%TYPE := null;
  L_error_message   RTK_ERRORS.RTK_TEXT%TYPE := null;

/* select "sample" rows to generate new orders and new (rms) allocations based on the input order */
  cursor oh_cur is
    select *
      from ordhead
     where order_no = I_order_no
       and location not in (select wh from wh_attributes where wh_type_code in ('DD','PA'));

  cursor os_cur is
    select *
      from ordsku
     where order_no = I_order_no
       and rownum = 1;

  cursor ol_cur is
    select *
      from ordloc
     where order_no = I_order_no
       and rownum = 1;

  cursor ah_cur is
    select *
      from alloc_header
     where order_no = I_order_no
       and rownum = 1;

  cursor ad_cur is
    select *
      from alloc_detail
     where alloc_no in (select alloc_no from alloc_header where order_no = I_order_no)
       and rownum = 1;

/* Determine the wh's associated with the allocation(s) */
  cursor def_wh_cur is
    select distinct default_wh
      from alc_item_loc a,
           store b
     where alloc_id in (select alloc_id from alc_xref where order_no = I_order_no)
       and a.location_id = b.store
       and default_wh is not null
       and allocated_qty > 0
     order by 1;

/* Determine the item-quantities for each wh */
  cursor alc_item_wh_cur is
    select a.item_id,
           sum(allocated_qty) wh_qty
      from alc_item_loc a,
           store b
     where alloc_id in (select alloc_id from alc_xref where order_no = I_order_no)
       and a.location_id = b.store
       and default_wh is not null
       and allocated_qty > 0
       and default_wh = L_default_wh
     group by a.item_id;

/* Determine the allocated item-loc-wh quantities for alloc details */
  cursor alc_dtl_cur is
    select store,
           sum(allocated_qty) st_qty
      from alc_item_loc a,
           store b
     where alloc_id in (select alloc_id from alc_xref where order_no = I_order_no)
       and a.location_id = b.store
       and default_wh is not null
       and allocated_qty > 0
       and default_wh = L_default_wh
       and a.item_id = L_item
     group by store
     order by 1;

  L_alloc_no ALLOC_HEADER.ALLOC_NO%TYPE;
  firsttime BOOLEAN;

BEGIN
  for oh_rec in oh_cur loop
    for def_wh_rec in def_wh_cur loop
       L_default_wh := def_wh_rec.default_wh;
       insert into ordhead(order_no,
                              order_type,
                              dept,
                              buyer,
                              supplier,
                              supp_add_seq_no,
                              loc_type,
                              location,
                              promotion,
                              qc_ind,
                              written_date,
                              not_before_date,
                              not_after_date,
                              otb_eow_date,
                              earliest_ship_date,
                              latest_ship_date,
                              close_date,
                              terms,
                              freight_terms,
                              orig_ind,
                              cust_order,
                              payment_method,
                              backhaul_type,
                              backhaul_allowance,
                              ship_method,
                              purchase_type,
                              status,
                              orig_approval_date,
                              orig_approval_id,
                              ship_pay_method,
                              fob_trans_res,
                              fob_trans_res_desc,
                              fob_title_pass,
                              fob_title_pass_desc,
                              edi_sent_ind,
                              edi_po_ind,
                              import_order_ind,
                              import_country_id,
                              po_ack_recvd_ind,
                              include_on_order_ind,
                              vendor_order_no,
                              exchange_rate,
                              factory,
                              agent,
                              discharge_port,
                              lading_port,
                              bill_to_id,
                              freight_contract_no,
                              po_type,
                              pre_mark_ind,
                              currency_code,
                              reject_code,
                              contract_no,
                              last_sent_rev_no,
                              split_ref_ordno,
                              pickup_loc,
                              pickup_no,
                              pickup_date,
                              app_datetime,
                              comment_desc,
                              partner_type_1,
                              partner1,
                              partner_type_2,
                              partner2,
                              partner_type_3,
                              partner3,
                              item,
                              import_id,
                              import_type,
                              routing_loc_id,
                              clearing_zone_id)
                       values(oh_rec.order_no||substr(def_wh_rec.default_wh,2,3),
                              oh_rec.order_type,
                              oh_rec.dept,
                              oh_rec.buyer,
                              oh_rec.supplier,
                              oh_rec.supp_add_seq_no,
                              oh_rec.loc_type,
                              def_wh_rec.default_wh,
                              oh_rec.promotion,
                              oh_rec.qc_ind,
                              oh_rec.written_date,
                              oh_rec.not_before_date,
                              oh_rec.not_after_date,
                              oh_rec.otb_eow_date,
                              oh_rec.earliest_ship_date,
                              oh_rec.latest_ship_date,
                              oh_rec.close_date,
                              oh_rec.terms,
                              oh_rec.freight_terms,
                              oh_rec.orig_ind,
                              oh_rec.cust_order,
                              oh_rec.payment_method,
                              oh_rec.backhaul_type,
                              oh_rec.backhaul_allowance,
                              oh_rec.ship_method,
                              oh_rec.purchase_type,
                              oh_rec.status,
                              oh_rec.orig_approval_date,
                              oh_rec.orig_approval_id,
                              oh_rec.ship_pay_method,
                              oh_rec.fob_trans_res,
                              oh_rec.fob_trans_res_desc,
                              oh_rec.fob_title_pass,
                              oh_rec.fob_title_pass_desc,
                              oh_rec.edi_sent_ind,
                              oh_rec.edi_po_ind,
                              oh_rec.import_order_ind,
                              oh_rec.import_country_id,
                              oh_rec.po_ack_recvd_ind,
                              'Y',  /* oh_rec.include_on_order_ind */
                              oh_rec.vendor_order_no,
                              oh_rec.exchange_rate,
                              oh_rec.factory,
                              oh_rec.agent,
                              oh_rec.discharge_port,
                              oh_rec.lading_port,
                              oh_rec.bill_to_id,
                              oh_rec.freight_contract_no,
                              oh_rec.po_type,
                              oh_rec.pre_mark_ind,
                              oh_rec.currency_code,
                              oh_rec.reject_code,
                              oh_rec.contract_no,
                              oh_rec.last_sent_rev_no,
                              oh_rec.split_ref_ordno,
                              oh_rec.pickup_loc,
                              oh_rec.pickup_no,
                              oh_rec.pickup_date,
                              oh_rec.app_datetime,
                              oh_rec.comment_desc,
                              oh_rec.partner_type_1,
                              oh_rec.partner1,
                              oh_rec.partner_type_2,
                              oh_rec.partner2,
                              oh_rec.partner_type_3,
                              oh_rec.partner3,
                              oh_rec.item,
                              oh_rec.import_id,
                              oh_rec.import_type,
                              oh_rec.routing_loc_id,
                              oh_rec.clearing_zone_id);
        for os_rec in os_cur loop
           for ol_rec in ol_cur loop
              for ah_rec in ah_cur loop
                 for ad_rec in ad_cur loop
                    for alc_item_wh_rec in alc_item_wh_cur loop
                       insert into ordsku(order_no,
                                          item,
                                          ref_item,
                                          origin_country_id,
                                          earliest_ship_date,
                                          latest_ship_date,
                                          supp_pack_size,
                                          non_scale_ind,
                                          pickup_loc,
                                          pickup_no)
                                   values(os_rec.order_no||substr(def_wh_rec.default_wh,2,3),
                                          alc_item_wh_rec.item_id,
                                          os_rec.ref_item,
                                          os_rec.origin_country_id,
                                          os_rec.earliest_ship_date,
                                          os_rec.latest_ship_date,
                                          os_rec.supp_pack_size,
                                          os_rec.non_scale_ind,
                                          os_rec.pickup_loc,
                                          os_rec.pickup_no);

                       insert into ordloc(order_no,
                                           item,
                                           location,
                                           loc_type,
                                           unit_retail,
                                           qty_ordered,
                                           qty_prescaled,
                                           qty_received,
                                           last_received,
                                           last_rounded_qty,
                                           last_grp_rounded_qty,
                                           qty_cancelled,
                                           cancel_code,
                                           cancel_date,
                                           cancel_id,
                                           original_repl_qty,
                                           unit_cost,
                                           unit_cost_init,
                                           cost_source,
                                           non_scale_ind,
                                           tsf_po_link_no,
                                           estimated_instock_date)
                                    values(ol_rec.order_no||substr(def_wh_rec.default_wh,2,3),
                                           alc_item_wh_rec.item_id,
                                           def_wh_rec.default_wh,
                                           ol_rec.loc_type,
                                           ol_rec.unit_retail,
                                           alc_item_wh_rec.wh_qty,
                                           alc_item_wh_rec.wh_qty,
                                           ol_rec.qty_received,
                                           ol_rec.last_received,
                                           alc_item_wh_rec.wh_qty,
                                           alc_item_wh_rec.wh_qty,
                                           ol_rec.qty_cancelled,
                                           ol_rec.cancel_code,
                                           ol_rec.cancel_date,
                                           ol_rec.cancel_id,
                                           ol_rec.original_repl_qty,
                                           ol_rec.unit_cost,
                                           ol_rec.unit_cost_init,
                                           ol_rec.cost_source,
                                           ol_rec.non_scale_ind,
                                           ol_rec.tsf_po_link_no,
                                           ol_rec.estimated_instock_date);

                       SMR_LEAP_INTERFACE_SQL.SDC_NEW_ITEM_LOC( L_error_message, alc_item_wh_rec.item_id, def_wh_rec.default_wh );

                       select alloc_order_sequence.nextval into L_alloc_no from dual;
                       /* set the proper alloc_parent for the new wh-based allocs */
                       if ( L_prev_default_wh != L_default_wh ) then
                         L_alloc_parent := null;
                         firsttime := TRUE;
                       else
                         firsttime := FALSE;
                       end if;
                       L_prev_default_wh := L_default_wh;

                       insert into alloc_header(alloc_no,
			      		order_no,
			      		wh,
			      		item,
			      		status,
			      		alloc_desc,
			      		po_type,
			      		alloc_method,
			      		release_date,
			      		order_type,
			      		context_type,
			      		context_value,
			      		comment_desc,
			      		doc,
			      		doc_type,
			      		alloc_parent)
                                    values(L_alloc_no,
			      		ah_rec.order_no||substr(def_wh_rec.default_wh,2,3),
			      		def_wh_rec.default_wh,
			      		alc_item_wh_rec.item_id,
			      		ah_rec.status,
			      		ah_rec.alloc_desc,
			      		ah_rec.po_type,
			      		ah_rec.alloc_method,
			      		ah_rec.release_date,
			      		ah_rec.order_type,
			      		ah_rec.context_type,
			      		ah_rec.context_value,
			      		ah_rec.comment_desc,
			      		ah_rec.doc,
			      		ah_rec.doc_type,
			      		L_alloc_parent);

                       if (firsttime) then
                          L_alloc_parent := L_alloc_no;
                       end if;

                       L_item := alc_item_wh_rec.item_id;
                       for alc_dtl_rec in alc_dtl_cur loop
                          insert into alloc_detail(alloc_no,
                                                   to_loc,
                                                   to_loc_type,
                                                   qty_transferred,
                                                   qty_allocated,
                                                   qty_prescaled,
                                                   qty_distro,
                                                   qty_selected,
                                                   qty_cancelled,
                                                   qty_received,
                                                   qty_reconciled,
                                                   po_rcvd_qty,
                                                   non_scale_ind,
                                                   in_store_date,
                                                   rush_flag)
                                            values(L_alloc_no,
                                                   alc_dtl_rec.store,
                                                   ad_rec.to_loc_type,
                                                   ad_rec.qty_transferred,
                                                   alc_dtl_rec.st_qty,
                                                   alc_dtl_rec.st_qty,
                                                   ad_rec.qty_distro,
                                                   ad_rec.qty_selected,
                                                   ad_rec.qty_cancelled,
                                                   ad_rec.qty_received,
                                                   ad_rec.qty_reconciled,
                                                   ad_rec.po_rcvd_qty,
                                                   ad_rec.non_scale_ind,
                                                   ad_rec.in_store_date,
                                                   ad_rec.rush_flag);

                       end loop;
                    end loop;
                 end loop;
              end loop;
           end loop;
        end loop;
     end loop;
  end loop;
END SPLIT_TRANSFORM_BULK_ORDER;

PROCEDURE SPLIT_TRANSFORM_HOLD_BACK(I_order_no IN ordhead.order_no%TYPE) IS

  L_item            ITEM_MASTER.ITEM%TYPE := null;
  L_default_wh      STORE.DEFAULT_WH%TYPE := null;
  L_prev_default_wh STORE.DEFAULT_WH%TYPE := 1;
  L_alloc_parent    ALLOC_HEADER.ALLOC_PARENT%TYPE  := null;
  L_error_message   RTK_ERRORS.RTK_TEXT%TYPE := null;

/* select "sample" rows to generate new put away orders */
  cursor oh_cur is
    select *
      from ordhead
     where order_no = I_order_no;

  cursor os_cur is
    select *
      from ordsku
     where order_no = I_order_no
       and rownum = 1;

  cursor ol_cur is
    select *
      from ordloc
     where order_no = I_order_no
       and rownum = 1;


/* Determine the wh's associated with the allocation(s) */
  cursor def_wh_cur is
    select default_wh from (
      select sdc1 default_wh, sum(nvl(sdc1_hb_qty,0))
        from smr_alloc_wh_hold_back a
       where a.order_no = I_order_no
       group by sdc1
      having sum(nvl(sdc1_hb_qty,0)) > 0
     union all
      select sdc2 default_wh, sum(nvl(sdc2_hb_qty,0))
        from smr_alloc_wh_hold_back a
       where a.order_no = I_order_no
       group by sdc2
      having sum(nvl(sdc2_hb_qty,0)) > 0
     union all
      select sdc3 default_wh, sum(nvl(sdc3_hb_qty,0))
        from smr_alloc_wh_hold_back a
       where a.order_no = I_order_no
       group by sdc3
      having sum(nvl(sdc3_hb_qty,0)) > 0)
     order by 1;

/* Determine the item-quantities for each wh */
  cursor alc_item_wh_cur is
    select a.item_id,
          (decode(sdc1, L_default_wh, sdc1_hb_qty, 0) +
           decode(sdc2, L_default_wh, sdc2_hb_qty, 0) +
           decode(sdc3, L_default_wh, sdc3_hb_qty, 0)) wh_qty
      from smr_alloc_wh_hold_back a
     where order_no = I_order_no;

BEGIN
  for oh_rec in oh_cur loop
    for def_wh_rec in def_wh_cur loop
       L_default_wh := def_wh_rec.default_wh;
       insert into ordhead(order_no,
                              order_type,
                              dept,
                              buyer,
                              supplier,
                              supp_add_seq_no,
                              loc_type,
                              location,
                              promotion,
                              qc_ind,
                              written_date,
                              not_before_date,
                              not_after_date,
                              otb_eow_date,
                              earliest_ship_date,
                              latest_ship_date,
                              close_date,
                              terms,
                              freight_terms,
                              orig_ind,
                              cust_order,
                              payment_method,
                              backhaul_type,
                              backhaul_allowance,
                              ship_method,
                              purchase_type,
                              status,
                              orig_approval_date,
                              orig_approval_id,
                              ship_pay_method,
                              fob_trans_res,
                              fob_trans_res_desc,
                              fob_title_pass,
                              fob_title_pass_desc,
                              edi_sent_ind,
                              edi_po_ind,
                              import_order_ind,
                              import_country_id,
                              po_ack_recvd_ind,
                              include_on_order_ind,
                              vendor_order_no,
                              exchange_rate,
                              factory,
                              agent,
                              discharge_port,
                              lading_port,
                              bill_to_id,
                              freight_contract_no,
                              po_type,
                              pre_mark_ind,
                              currency_code,
                              reject_code,
                              contract_no,
                              last_sent_rev_no,
                              split_ref_ordno,
                              pickup_loc,
                              pickup_no,
                              pickup_date,
                              app_datetime,
                              comment_desc,
                              partner_type_1,
                              partner1,
                              partner_type_2,
                              partner2,
                              partner_type_3,
                              partner3,
                              item,
                              import_id,
                              import_type,
                              routing_loc_id,
                              clearing_zone_id)
                       values(oh_rec.order_no||substr(def_wh_rec.default_wh,2,3),
                              oh_rec.order_type,
                              oh_rec.dept,
                              oh_rec.buyer,
                              oh_rec.supplier,
                              oh_rec.supp_add_seq_no,
                              oh_rec.loc_type,
                              def_wh_rec.default_wh,
                              oh_rec.promotion,
                              oh_rec.qc_ind,
                              oh_rec.written_date,
                              oh_rec.not_before_date,
                              oh_rec.not_after_date,
                              oh_rec.otb_eow_date,
                              oh_rec.earliest_ship_date,
                              oh_rec.latest_ship_date,
                              oh_rec.close_date,
                              oh_rec.terms,
                              oh_rec.freight_terms,
                              oh_rec.orig_ind,
                              oh_rec.cust_order,
                              oh_rec.payment_method,
                              oh_rec.backhaul_type,
                              oh_rec.backhaul_allowance,
                              oh_rec.ship_method,
                              oh_rec.purchase_type,
                              oh_rec.status,
                              oh_rec.orig_approval_date,
                              oh_rec.orig_approval_id,
                              oh_rec.ship_pay_method,
                              oh_rec.fob_trans_res,
                              oh_rec.fob_trans_res_desc,
                              oh_rec.fob_title_pass,
                              oh_rec.fob_title_pass_desc,
                              oh_rec.edi_sent_ind,
                              oh_rec.edi_po_ind,
                              oh_rec.import_order_ind,
                              oh_rec.import_country_id,
                              oh_rec.po_ack_recvd_ind,
                              'Y',   /* oh_rec.include_on_order_ind */
                              oh_rec.vendor_order_no,
                              oh_rec.exchange_rate,
                              oh_rec.factory,
                              oh_rec.agent,
                              oh_rec.discharge_port,
                              oh_rec.lading_port,
                              oh_rec.bill_to_id,
                              oh_rec.freight_contract_no,
                              oh_rec.po_type,
                              oh_rec.pre_mark_ind,
                              oh_rec.currency_code,
                              oh_rec.reject_code,
                              oh_rec.contract_no,
                              oh_rec.last_sent_rev_no,
                              oh_rec.split_ref_ordno,
                              oh_rec.pickup_loc,
                              oh_rec.pickup_no,
                              oh_rec.pickup_date,
                              oh_rec.app_datetime,
                              oh_rec.comment_desc,
                              oh_rec.partner_type_1,
                              oh_rec.partner1,
                              oh_rec.partner_type_2,
                              oh_rec.partner2,
                              oh_rec.partner_type_3,
                              oh_rec.partner3,
                              oh_rec.item,
                              oh_rec.import_id,
                              oh_rec.import_type,
                              oh_rec.routing_loc_id,
                              oh_rec.clearing_zone_id);
        for os_rec in os_cur loop
           for ol_rec in ol_cur loop
                for alc_item_wh_rec in alc_item_wh_cur loop
                       insert into ordsku(order_no,
                                          item,
                                          ref_item,
                                          origin_country_id,
                                          earliest_ship_date,
                                          latest_ship_date,
                                          supp_pack_size,
                                          non_scale_ind,
                                          pickup_loc,
                                          pickup_no)
                                   values(os_rec.order_no||substr(def_wh_rec.default_wh,2,3),
                                          alc_item_wh_rec.item_id,
                                          os_rec.ref_item,
                                          os_rec.origin_country_id,
                                          os_rec.earliest_ship_date,
                                          os_rec.latest_ship_date,
                                          os_rec.supp_pack_size,
                                          os_rec.non_scale_ind,
                                          os_rec.pickup_loc,
                                          os_rec.pickup_no);

                       insert into ordloc(order_no,
                                           item,
                                           location,
                                           loc_type,
                                           unit_retail,
                                           qty_ordered,
                                           qty_prescaled,
                                           qty_received,
                                           last_received,
                                           last_rounded_qty,
                                           last_grp_rounded_qty,
                                           qty_cancelled,
                                           cancel_code,
                                           cancel_date,
                                           cancel_id,
                                           original_repl_qty,
                                           unit_cost,
                                           unit_cost_init,
                                           cost_source,
                                           non_scale_ind,
                                           tsf_po_link_no,
                                           estimated_instock_date)
                                    values(ol_rec.order_no||substr(def_wh_rec.default_wh,2,3),
                                           alc_item_wh_rec.item_id,
                                           def_wh_rec.default_wh,
                                           ol_rec.loc_type,
                                           ol_rec.unit_retail,
                                           alc_item_wh_rec.wh_qty,
                                           alc_item_wh_rec.wh_qty,
                                           ol_rec.qty_received,
                                           ol_rec.last_received,
                                           alc_item_wh_rec.wh_qty,
                                           alc_item_wh_rec.wh_qty,
                                           ol_rec.qty_cancelled,
                                           ol_rec.cancel_code,
                                           ol_rec.cancel_date,
                                           ol_rec.cancel_id,
                                           ol_rec.original_repl_qty,
                                           ol_rec.unit_cost,
                                           ol_rec.unit_cost_init,
                                           ol_rec.cost_source,
                                           ol_rec.non_scale_ind,
                                           ol_rec.tsf_po_link_no,
                                           ol_rec.estimated_instock_date);
                 SMR_LEAP_INTERFACE_SQL.SDC_NEW_ITEM_LOC( L_error_message, alc_item_wh_rec.item_id, def_wh_rec.default_wh );
              end loop;
           end loop;
        end loop;
     end loop;
  end loop;
END SPLIT_TRANSFORM_HOLD_BACK;

PROCEDURE SDC_NEW_ITEM_LOC( O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                            I_item          IN     ITEM_LOC.ITEM%TYPE,
                            I_wh            IN     ITEM_LOC.LOC%TYPE ) IS

   L_program_name        VARCHAR2(50) := 'SMR_LEAP_INTERFACE_SQL.SDC_NEW_ITEM_LOC';
   L_loc_type            VARCHAR2(1)  := 'W';
   L_il_cnt              NUMBER(10)   := 0;

 BEGIN
 -- Create item_loc for SDC if does not exist

   SELECT count(*)
     INTO L_il_cnt
     FROM item_loc
    WHERE item = I_item
      AND loc  = I_wh
      AND loc_type = L_loc_type;

   if ( L_il_cnt = 0 ) then
     SMR_LEAP_INTERFACE_SQL.SDC_INSERT_ITEM_LOC( O_error_message, I_item, I_wh, L_loc_type );
   end if;

END SDC_NEW_ITEM_LOC;


PROCEDURE SDC_INSERT_ITEM_LOC( O_error_message   IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                               I_item            IN     ITEM_LOC.ITEM%TYPE,
                               I_location        IN     ITEM_LOC.LOC%TYPE,
                               I_loc_type        IN     ITEM_LOC.LOC_TYPE%TYPE) IS

   L_program_name        VARCHAR2(50) := 'SMR_LEAP_INTERFACE_SQL.SDC_INSERT_ITEM_LOC';

BEGIN
   IF NEW_ITEM_LOC( O_error_message,
         I_item,
         I_location,
         NULL,
         NULL,
         I_loc_type,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL,
         NULL) = FALSE THEN
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program_name,
                                             TO_CHAR(SQLCODE));
   END IF;
END SDC_INSERT_ITEM_LOC;

FUNCTION GET_CONSTANT_VALUE(i_constant IN VARCHAR2) RETURN NUMBER deterministic AS
   c_val number; 
BEGIN
   execute immediate 'begin :c_val := '||i_constant||'; end;' using out c_val;     
   RETURN c_val;   
END GET_CONSTANT_VALUE;

FUNCTION GET_ORDER_ITEM_HOLDBACK_QTY(I_order_no ordhead.order_no%TYPE,
                                     I_item item_master.item%TYPE)
RETURN NUMBER IS
  CURSOR hbq_cur is
    select a.hold_back_pct_flag,
           a.hold_back_value,
           a.avail_qty
      from alc_item_source a,
           alc_alloc b
     where a.alloc_id = b.alloc_id
       and b.status = '2'
       and (a.alloc_id,a.item_id) in (select max(alloc_id),item_id from alc_item_source where order_no = a.order_no group by item_id)
       and a.item_id = I_item
       and a.order_no = I_order_no
       and nvl(a.hold_back_value,0) > 0;

  O_holdback_qty       alc_item_source.hold_back_value%TYPE := 0;
  I_hold_back_value    alc_item_source.hold_back_value%TYPE := 0;
  I_avail_qty          alc_item_source.avail_qty%TYPE := 0;
  I_hold_back_pct_flag alc_item_source.hold_back_pct_flag%TYPE := 'N';

BEGIN
  for hbq_rec in hbq_cur loop

    I_hold_back_value :=    hbq_rec.hold_back_value;
    I_avail_qty       :=    hbq_rec.avail_qty;
    I_hold_back_pct_flag := hbq_rec.hold_back_pct_flag;

    /* return holdback qty in units */
    if (I_hold_back_pct_flag = 'Y') then
      O_holdback_qty := O_holdback_qty + (I_hold_back_value/100) * I_avail_qty;
    else
      O_holdback_qty := O_holdback_qty + I_hold_back_value;
    end if;
  end loop;

  return(O_holdback_qty);

EXCEPTION
  when NO_DATA_FOUND then
    return null;
END GET_ORDER_ITEM_HOLDBACK_QTY;

/* called from smr_alc_table_aa_aiur_trg on approval */
PROCEDURE PROCESS_APPROVED_ALLOC(I_order_no ordhead.order_no%TYPE) IS

  I_tot_qty_ordered ordloc.qty_ordered%TYPE := 0;
  I_tot_allocated_qty alc_item_loc.allocated_qty%TYPE := 0;
  I_tot_qty_heldback alc_item_source.hold_back_value%TYPE := 0;

BEGIN

  select sum(nvl(qty_ordered,0) - nvl(qty_cancelled,0))
    into I_tot_qty_ordered
    from ordloc
   where order_no = I_order_no;

  select sum(allocated_qty)
    into I_tot_allocated_qty
    from alc_xref a,
         smr_alc_ext b
   where a.alloc_id = b.alloc_id
     and b.status = '2'
     and a.order_no = b.order_no
     and b.seq_no = (select max(seq_no) from smr_alc_ext where status = '2' and order_no = I_order_no)
     and a.order_no = I_order_no;

  select sum(decode(hold_back_pct_flag,'Y',(nvl(hold_back_value,0)/100) * nvl(avail_qty,0), nvl(hold_back_value,0)))
    into I_tot_qty_heldback
    from alc_item_source a,
         smr_alc_ext b
   where a.alloc_id = b.alloc_id
     and b.status = '2'
     and (a.alloc_id,a.item_id) in (select max(alloc_id),item_id from alc_item_source where order_no = a.order_no group by item_id)
     and b.seq_no in (select seq_no from smr_alc_ext where order_no = I_order_no)
     and a.alloc_id in (select alloc_id from alc_xref where order_no= I_order_no);

  /* check that the numbers match (or do not split/transform) */
  if ( I_tot_qty_ordered = (I_tot_allocated_qty + I_tot_qty_heldback)) then

    if ( I_tot_qty_heldback = 0 ) then  /* if holdback wait for wh allocation approval */

      if ( SMR_LEAP_INTERFACE_SQL.SPLIT_ORDER_EXISTS( I_order_no )) then
        SMR_LEAP_INTERFACE_SQL.REMOVE_SPLIT_ORDERS( I_order_no ); /* alloc was redone */
       /* else order updates are handled through revisions */
      end if;

      SMR_LEAP_INTERFACE_SQL.SPLIT_TRANSFORM_BULK_ORDER( I_order_no );

    end if;
  else
    /* numbers do not match ( e.g. the order is not fully allocated) - write audit rec */
    insert into SMR_BULK_ORDER_NOT_SPLIT values( I_order_no,
                                                 I_tot_qty_ordered,
                                                 I_tot_allocated_qty,
                                                 I_tot_qty_heldback,
                                                 sysdate,
                                                 user);
  end if;

END PROCESS_APPROVED_ALLOC;

FUNCTION SPLIT_ORDER_EXISTS(I_order_no ordhead.order_no%TYPE)
RETURN BOOLEAN IS

  ord_cnt number(10) := 0;

BEGIN
    select count(*)
      into ord_cnt
      from ordhead
     where order_no like I_order_no||'%'
       and length(order_no) = SPLIT_PO_ORDER_LENGTH;

    if (ord_cnt > 0) then
      return( TRUE );
    else
      return( FALSE );
    end if;
END SPLIT_ORDER_EXISTS;

FUNCTION NOT_PACK_ITEM(I_item item_master.item%TYPE)
RETURN BOOLEAN IS

L_item_cnt number(10) := 0; /* exception is not thrown for data not found (is zero) */

BEGIN
  select count(*)
    into L_item_cnt
    from item_master
   where item = I_item
     and pack_type='V';

  if (L_item_cnt > 0) then
    return(FALSE);
  else
    return(TRUE);
  end if;

END NOT_PACK_ITEM;

FUNCTION APPR_HOLDBACK_ORDER_EXISTS(I_order_no ordhead.order_no%TYPE)
RETURN BOOLEAN IS

  ord_cnt number(10) := 0;

BEGIN
    select count(*)
      into ord_cnt
      from ordhead
     where order_no like I_order_no||'%'
       and length(order_no) = SPLIT_PO_ORDER_LENGTH
       and status = 'A';

    if (ord_cnt > 0) then
      return( TRUE );
    else
      return( FALSE );
    end if;
END APPR_HOLDBACK_ORDER_EXISTS;

PROCEDURE REMOVE_SPLIT_ORDERS( I_order_no ordhead.order_no%TYPE) IS

   CURSOR ordcur is
     select order_no
       from ordhead
      where length(order_no) = SPLIT_PO_ORDER_LENGTH
        and order_no like I_order_no||'%';
BEGIN

  for ordrec in ordcur loop
   insert into SMR_REALLOC_ORDHEAD(select a.*,sysdate,user from ordhead a where order_no = ordrec.order_no);
   insert into SMR_REALLOC_ORDSKU (select a.*,sysdate,user from ordsku a where order_no = ordrec.order_no);
   insert into SMR_REALLOC_ORDLOC (select a.*,sysdate,user from ordloc a where order_no = ordrec.order_no);
   insert into SMR_REALLOC_ALLOC_HEADER (select a.*,sysdate,user from alloc_header a where order_no = ordrec.order_no);
   insert into SMR_REALLOC_ALLOC_DETAIL (select a.*,sysdate,user from alloc_detail a where alloc_no in (select alloc_no from alloc_header where order_no = ordrec.order_no));

   insert into SMR_REALLOC_WH_PO_DTL (select a.*,sysdate,user from SMR_RMS_WH_PO_DTL_EXP a where order_no = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'WH_PO')));
   insert into SMR_REALLOC_WH_PO_HDR (select a.*,sysdate,user from SMR_RMS_WH_PO_HDR_EXP a where order_no = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'WH_PO')));
   insert into SMR_REALLOC_EDI_850_860_DTL (select a.*,sysdate,user from SMR_PO_EDI_850_860_DTL_EXP a where po_nmbr = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'EDI_850_860')));
   insert into SMR_REALLOC_EDI_850_860_HDR (select a.*,sysdate,user from SMR_PO_EDI_850_860_HDR_EXP a where po_nmbr = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'EDI_850_860')));

   delete from alloc_detail where alloc_no in (select alloc_no from alloc_header where order_no = ordrec.order_no);
   delete from alloc_header where order_no = ordrec.order_no;

   insert into order_pub_info (select distinct ordrec.order_no,'Y',1,'Y','N/B' from ordloc where order_no = ordrec.order_no and order_no not in (select order_no from order_pub_info));
   delete from ordloc where order_no = ordrec.order_no;
   delete from ordsku where order_no = ordrec.order_no;
   delete from deal_calc_queue where order_no = ordrec.order_no;
   delete from ordhead where order_no = ordrec.order_no;
   delete from smr_ord_extract where order_no = ordrec.order_no;
   delete from order_pub_info where order_no = ordrec.order_no; 

--   delete from SMR_RMS_WH_PO_DTL_EXP where order_no = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'WH_PO'));
--   delete from SMR_RMS_WH_PO_HDR_EXP where order_no = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'WH_PO'));
--   delete from SMR_PO_EDI_850_860_DTL_EXP where po_nmbr = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'EDI_850_860'));
--   delete from SMR_PO_EDI_850_860_HDR_EXP where po_nmbr = ordrec.order_no and group_id in (select group_id from SMR_RMS_INT_QUEUE where status = 'N' and interface_id in (select interface_id from SMR_RMS_INT_TYPE where interface_name = 'EDI_850_860'));

 end loop;

END REMOVE_SPLIT_ORDERS;

PROCEDURE UPDATE_SPLIT_ORDERS(I_order_no               ORDHEAD.ORDER_NO%TYPE ) IS
/***
			      L_supplier               ORDHEAD.SUPPLIER%TYPE,
			      L_fob_title_pass_desc    ORDHEAD.FOB_TITLE_PASS_DESC%TYPE,
			      L_fob_title_pass         ORDHEAD.FOB_TITLE_PASS%TYPE,
			      L_payment_method         ORDHEAD.PAYMENT_METHOD%TYPE,
			      L_dept                   ORDHEAD.DEPT%TYPE,
			      L_buyer                  ORDHEAD.BUYER%TYPE,
			      L_purchase_type          ORDHEAD.PURCHASE_TYPE%TYPE,
			      L_not_after_date         ORDHEAD.NOT_AFTER_DATE%TYPE,
			      L_contract_no            ORDHEAD.CONTRACT_NO%TYPE,
			      L_factory                ORDHEAD.FACTORY%TYPE,
			      L_fob_trans_res          ORDHEAD.FOB_TRANS_RES%TYPE,
			      L_not_before_date        ORDHEAD.NOT_BEFORE_DATE%TYPE,
			      L_pickup_no              ORDHEAD.PICKUP_NO%TYPE,
			      L_exchange_rate          ORDHEAD.EXCHANGE_RATE%TYPE,
			      L_app_datetime           ORDHEAD.APP_DATETIME%TYPE,
			      L_pickup_date            ORDHEAD.PICKUP_DATE%TYPE,
			      L_currency_code          ORDHEAD.CURRENCY_CODE%TYPE,
			      L_ship_pay_method        ORDHEAD.SHIP_PAY_METHOD%TYPE,
			      L_ship_method            ORDHEAD.SHIP_METHOD%TYPE,
			      L_terms                  ORDHEAD.TERMS%TYPE,
			      L_lading_port            ORDHEAD.LADING_PORT%TYPE,
			      L_discharge_port         ORDHEAD.DISCHARGE_PORT%TYPE,
			      L_close_date             ORDHEAD.CLOSE_DATE%TYPE,
			      L_qc_ind                 ORDHEAD.QC_IND%TYPE,
			      L_pre_mark_ind           ORDHEAD.PRE_MARK_IND%TYPE,
			      L_bill_to_id             ORDHEAD.BILL_TO_ID%TYPE,
			      L_comment_desc           ORDHEAD.COMMENT_DESC%TYPE,
			      L_backhaul_allowance     ORDHEAD.BACKHAUL_ALLOWANCE%TYPE,
			      L_otb_eow_date           ORDHEAD.OTB_EOW_DATE%TYPE,
			      L_freight_contract_no    ORDHEAD.FREIGHT_CONTRACT_NO%TYPE,
			      L_latest_ship_date       ORDHEAD.LATEST_SHIP_DATE%TYPE,
			      L_status                 ORDHEAD.STATUS%TYPE,
			      L_cust_order             ORDHEAD.CUST_ORDER%TYPE,
			      L_pickup_loc             ORDHEAD.PICKUP_LOC%TYPE,
			      L_backhaul_type          ORDHEAD.BACKHAUL_TYPE%TYPE,
			      L_agent                  ORDHEAD.AGENT%TYPE,
			      L_freight_terms          ORDHEAD.FREIGHT_TERMS%TYPE,
			      L_po_type                ORDHEAD.PO_TYPE%TYPE,
			      L_order_type             ORDHEAD.ORDER_TYPE%TYPE,
			      L_earliest_ship_date     ORDHEAD.EARLIEST_SHIP_DATE%TYPE,
			      L_vendor_order_no        ORDHEAD.VENDOR_ORDER_NO%TYPE,
			      L_fob_trans_res_desc     ORDHEAD.FOB_TRANS_RES_DESC%TYPE,
			      L_promotion              ORDHEAD.PROMOTION%TYPE
***/
  cursor split_cur is
    select order_no
      from ordhead
     where length(order_no) = SPLIT_PO_ORDER_LENGTH
       and order_no like I_order_no||'%';

BEGIN
  for split_rec in split_cur loop
    null;
  end loop;
END UPDATE_SPLIT_ORDERS;

PROCEDURE UPDATE_ORDER_CREATE_TIME(I_order_no ORDHEAD.ORDER_NO%TYPE ) IS
BEGIN

  update smr_alloc_wh_hold_back
     set sdc_order_create_datetime = sysdate
   where order_no = I_order_no;

END UPDATE_ORDER_CREATE_TIME;

---------------------------------------------------------------------------------------------------
-- Procedure Name : GET_CURR_INTENT_STATE
-- Purpose        : return the state of Allocation Intent for an order
-- Description: Determine current alloc intent state
--     4 cases: (will only be 1 record/order at a time)
--      1. Has been checked, not 'P'rocessed.
--      2. Has been checked, 'P'rocessed.
--      3. Has been unchecked, not 'P'rocessed.
--      4. Has been unchecked, 'P'rocessed.
---------------------------------------------------------------------------------------------------
PROCEDURE GET_CURR_INTENT_STATE(I_order_no          IN number,
                                O_alloc_intent_ind OUT varchar2,
                                O_status           OUT varchar2,
                                O_ARI_sent_ind     OUT varchar2,
                                O_ARI_sent_date    OUT date,
                                O_ship_recvd_ind   OUT varchar2,
                                O_qry_group_id     OUT varchar2) IS
BEGIN

  O_alloc_intent_ind := null;
  O_status           := null;
  O_ARI_sent_ind     := null;
  O_ARI_sent_date    := null;
  O_ship_recvd_ind   := null;

    select a.alloc_intent_ind,
           b.status,
           a.ARI_sent_ind,
           a.ARI_sent_datetime,
           decode(nvl(c.qty_received,0),0,'N','Y'),
           a.group_id
      into O_alloc_intent_ind,
           O_status,
           O_ARI_sent_ind,
           O_ARI_sent_date,
           O_ship_recvd_ind,
           O_qry_group_id
      from smr_ord_alloc_intent a,
           smr_rms_int_queue b,
           (select d.order_no, sum(nvl(e.qty_received,0)) qty_received
              from shipment d,
                   shipsku e
             where e.shipment = d.shipment
             group by d.order_no) c
     where a.order_no = I_order_no
       and b.group_id(+) = a.group_id
       and c.order_no(+) = a.order_no
       and a.create_datetime = (select max(create_datetime) from smr_ord_alloc_intent where order_no = a.order_no);

EXCEPTION
	when NO_DATA_FOUND then
     null;

END GET_CURR_INTENT_STATE;

---------------------------------------------------------------------------------------------------
-- Function Name : WH_PO_EXTRACT
-- Purpose       : Function to extract WH PO's from SMR_RMS_WH_PO_DTL_STG
---------------------------------------------------------------------------------------------------
FUNCTION WH_PO_EXTRACT (O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN is
   L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.WH_PO_EXTRACT';
   L_order_no       ORDHEAD.ORDER_NO%TYPE := NULL;
   L_group_id       SMR_RMS_INT_QUEUE.GROUP_ID%TYPE := NULL;
   L_interface_Id   SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE;
   L_record_id      SMR_RMS_WH_PO_HDR_EXP.RECORD_ID%TYPE;
   L_curr_group_id  SMR_RMS_INT_QUEUE.GROUP_ID%TYPE := '0';
   L_ordcnt number(10) := 0;

   cursor C_get_int_id is
     select s.interface_id
       from SMR_RMS_INT_TYPE s
     where s.interface_name = 'WH_PO';

   cursor rollup_cur is
     select group_id,
            order_no,
            physical_wh,
            item,
            pack_ind,
            sum(qty_ordered) qty_ordered
       from SMR_RMS_WH_PO_DTL_STG
      where processed_ind = 'N'
   group by group_id, order_no, physical_wh, item, pack_ind
     having sum(qty_ordered) > 0
   order by 1,2;

   cursor group_cur is
     select distinct group_id
       from SMR_RMS_WH_PO_DTL_STG
      where processed_ind = 'N';

   cursor exist_group_cur is
     select group_id
       from smr_rms_int_queue
      where status = 'N'
        and group_id in (select group_id from smr_rms_wh_po_hdr_exp where order_no in (
          select order_no from SMR_RMS_WH_PO_HDR_UPD_STG where processed_ind = 'N'));

   cursor upd_group_cur is
     select group_id
       from (select max(group_id) group_id, order_no from SMR_RMS_WH_PO_HDR_UPD_STG
      where processed_ind = 'N'
      group by order_no);

---
BEGIN

   open C_get_int_id;
   fetch C_get_int_id into L_interface_Id;
   close C_get_int_id;

   for rollup_rec in rollup_cur loop

     if ( rollup_rec.group_id != L_curr_group_id ) then
       L_record_id := 0;
     end if;
     L_record_id := L_record_id + 1;

     L_ordcnt := 0;
     L_order_no := rollup_rec.order_no;

/**  back to 9-digit orders for WA..
     select count(*) into L_ordcnt
       from ordhead  where order_no = L_order_no;

     if ( L_ordcnt = 0 ) then
       L_order_no := substr(L_order_no,1,6);
     end if;
**/
     insert into SMR_RMS_WH_PO_DTL_EXP(
         GROUP_ID,
         RECORD_ID,
         order_no,
         physical_wh,
         item,
         pack_ind,
         qty_ordered) values (
         rollup_rec.group_id,
         L_record_id,
         L_order_no,
         rollup_rec.physical_wh,
         rollup_rec.item,
         rollup_rec.pack_ind,
         rollup_rec.qty_ordered);

         L_curr_group_id := rollup_rec.group_id;
    end loop;

    for group_rec in group_cur loop
      if SMR_LEAP_INTERFACE_SQL.ADD_INT_QUEUE(O_error_message,
                         L_interface_Id,
                         group_rec.group_id) = FALSE then
        RETURN FALSE;
      end if;
    end loop;

    update SMR_RMS_WH_PO_DTL_STG
       set processed_ind = 'Y'
     where processed_ind = 'N';


  /* now process updates */
     for exist_group_rec in exist_group_cur loop
        delete from smr_rms_int_queue
         where group_id = exist_group_rec.group_id;

        delete from smr_rms_wh_po_dtl_exp
         where group_id = exist_group_rec.group_id;

        delete from smr_rms_wh_po_hdr_exp
         where group_id = exist_group_rec.group_id;
     end loop;

     insert into SMR_RMS_WH_PO_HDR_EXP(
       group_id,
       record_id,
       ProcessingCode,
       order_no,
       location,
       wh,
       physical_wh,
       po_type,
       order_type,
       status,
       freight_terms,
       supplier,
       Buyer,
       dept,
       earliest_ship_date,
       latest_ship_date,
       not_before_date,
       not_after_date,
       modifyDate ) (select
       group_id,
       record_id,
       ProcessingCode,
       order_no,
       location,
       wh,
       physical_wh,
       po_type,
       order_type,
       Status,
       freight_terms,
       supplier,
       Buyer,
       dept,
       earliest_ship_date,
       latest_ship_date,
       not_before_date,
       not_after_date,
       modifyDate from SMR_RMS_WH_PO_HDR_UPD_STG where processed_ind = 'N' and group_id in (select group_id from (select max(group_id) group_id, order_no from SMR_RMS_WH_PO_HDR_UPD_STG group by order_no)));

    insert into SMR_RMS_WH_PO_DTL_EXP ( select * from SMR_RMS_WH_PO_DTL_UPD_STG where group_id in (
      select group_id from (select max(group_id) group_id, order_no from SMR_RMS_WH_PO_HDR_UPD_STG where processed_ind = 'N' group by order_no)));

    for upd_group_rec in upd_group_cur loop
      if SMR_LEAP_INTERFACE_SQL.ADD_INT_QUEUE(O_error_message,
                         L_interface_Id,
                         upd_group_rec.group_id) = FALSE then
        RETURN FALSE;
      end if;
    end loop;

    update SMR_RMS_WH_PO_HDR_UPD_STG
       set processed_ind = 'Y'
     where processed_ind = 'N';

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END WH_PO_EXTRACT;
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- Function Name : SMR_GENERATE_GROUP_ID
-- Purpose       : Function to generate Group Id for Interface tables
---------------------------------------------------------------------------------------------------
FUNCTION GENERATE_GROUP_ID(O_error_message IN OUT VARCHAR2,
                           I_INTERFACE_ID IN SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE,
                           O_GROUP_ID IN OUT  SMR_RMS_INT_QUEUE.GROUP_ID%TYPE)
RETURN BOOLEAN IS

L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID';

L_seq_no          Number(10);
---
BEGIN
   O_error_message := NULL;

   select smr_rms_int_group_seq.NEXTVAL into L_seq_no
     from dual;

   O_GROUP_ID := I_INTERFACE_ID || '-'||to_char(get_vdate,'YYYYMMDD') ||'-'|| lpad(L_seq_no,10,'0');

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END GENERATE_GROUP_ID;
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- Function Name : ADD_INT_QUEUE
-- Purpose       : Function to generate Group Id for Interface tables
---------------------------------------------------------------------------------------------------
FUNCTION ADD_INT_QUEUE (O_error_message IN OUT VARCHAR2,
                        I_INTERFACE_ID IN SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE,
                        I_GROUP_ID IN  SMR_RMS_INT_QUEUE.GROUP_ID%TYPE)
RETURN BOOLEAN IS

L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.ADD_INT_QUEUE';

BEGIN

   insert into SMR_RMS_INT_QUEUE(INTERFACE_QUEUE_ID,INTERFACE_ID,GROUP_ID,
                                 CREATE_DATETIME,PROCESSED_DATETIME,STATUS)
    select smr_rms_int_queue_seq.nextval,
           I_INTERFACE_ID,
           I_GROUP_ID,
           sysdate ,null ,'N'
       from dual;

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END ADD_INT_QUEUE;

---------------------------------------------------------------------------------------------------
-- Function Name : RTV_EXTRACT
-- Purpose       : Function to extract RTV Data fot WA
---------------------------------------------------------------------------------------------------
FUNCTION RTV_EXTRACT (O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN is
   L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.RTV_EXTRACT';

   L_group_id SMR_RMS_INT_QUEUE.GROUP_ID%TYPE := NULL;
   L_interface_Id  SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE;
   L_exists        varchar2(1):=null;

  Cursor C_rtv_exists is
   select 'X'
   from rtv_head rh, rtv_detail rd , SMR_RMS_RTV_STG s
       where rh.rtv_order_no = rd.rtv_order_no
         and rh.rtv_order_no = s.rtv_order_no
         and s.processed_ind = 'N'
         and rh.wh <> -1;

   Cursor C_get_int_id is
     select s.interface_id
       from SMR_RMS_INT_TYPE s
     where s.interface_name = 'WH_RTV';
---
BEGIN

   open C_rtv_exists;
   fetch C_rtv_exists into L_exists;
   close C_rtv_exists;

   if L_exists is null then
      return True;
   end if;

   open C_get_int_id;
   fetch C_get_int_id into  L_interface_Id;
   close C_get_int_id;

   /* Generate group Id */
   if SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID(O_error_message,
                       L_interface_Id,
                       L_group_id) = FALSE then
      RETURN FALSE;
   end if;

   /* Insert record into Interface queue */
   if SMR_LEAP_INTERFACE_SQL.ADD_INT_QUEUE(O_error_message,
                       L_interface_Id,
                       L_group_id) = FALSE then
      RETURN FALSE;
   end if;

    insert into SMR_RMS_INT_RTV_EXP
    select L_group_id,
           rownum,
           rh.RTV_ORDER_NO,
           SUPPLIER,
           WH,
           SHIP_TO_ADD_1,
           SHIP_TO_ADD_2,
           SHIP_TO_ADD_3,
           SHIP_TO_CITY,
           STATE,
           SHIP_TO_COUNTRY_ID,
           SHIP_TO_PCODE,
           RET_AUTH_NUM,
           COURIER,
           rh.CREATED_DATE,
           NOT_AFTER_DATE,
           rd.ITEM,
           QTY_REQUESTED,
           REASON,
           COMMENT_DESC,
           s.status,
           sysdate
      from rtv_head rh, rtv_detail rd , SMR_RMS_RTV_STG s
     where rh.rtv_order_no = rd.rtv_order_no
       and rh.rtv_order_no = s.rtv_order_no
       and s.processed_ind = 'N'
       and rh.wh <> -1;

    update SMR_RMS_RTV_STG set processed_ind = 'Y'
      where processed_ind = 'N';

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END RTV_EXTRACT;
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- Function Name : RTW_EXTRACT
-- Purpose       : Function to Extract RTW DATA For WA
---------------------------------------------------------------------------------------------------
FUNCTION RTW_EXTRACT (O_error_message IN OUT VARCHAR2)

RETURN BOOLEAN is
   L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.RTW_EXTRACT';

   L_group_id SMR_RMS_INT_QUEUE.GROUP_ID%TYPE := NULL;
	 L_interface_Id  SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE;

   L_exists        varchar2(1):=null;

  Cursor C_rtw_exists is
   select 'X'
   from tsfhead th, SMR_RMS_RTW_STG s,
           shipment sh, shipsku sk
     where th.tsf_no = s.tsf_no
       and sk.distro_no = th.tsf_no
       and sk.distro_type = 'T'
       and sh.shipment = sk.shipment
       and s.processed_ind = 'N';

   Cursor C_get_int_id is
     select s.interface_id
       from SMR_RMS_INT_TYPE s
     where s.interface_name = 'WH_RTW';
---
BEGIN

   open C_rtw_exists;
   fetch C_rtw_exists into L_exists;
   close C_rtw_exists;

   if L_exists is null then
      return True;
   end if;

   open C_get_int_id;
   fetch C_get_int_id into  L_interface_Id;
   close C_get_int_id;

   /* Generate group Id */
   if SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID(O_error_message,
                       L_interface_Id,
                       L_group_id) = FALSE then
      RETURN FALSE;
   end if;

   /* Insert record into Interface queue */
   if SMR_LEAP_INTERFACE_SQL.ADD_INT_QUEUE(O_error_message,
                       L_interface_Id,
                       L_group_id) = FALSE then
      RETURN FALSE;
   end if;

    insert into SMR_RMS_INT_RTW_EXP
    select L_group_id,
           rownum,
           sh.ship_date,
           sh.from_loc,
           sh.from_loc_type,
           sh.to_loc,
           sh.to_loc_type,
           th.tsf_no,
           sh.bol_no,
           sk.carton,
           sk.item,
           sk.qty_expected,
           sh.shipment,
           s.status,
           sysdate
      from tsfhead th, SMR_RMS_RTW_STG s,
           shipment sh, shipsku sk
     where th.tsf_no = s.tsf_no
       and sk.distro_no = th.tsf_no
       and sk.distro_type = 'T'
       and sh.shipment = sk.shipment
       and s.processed_ind = 'N';

    update SMR_RMS_RTW_STG set processed_ind = 'Y'
      where processed_ind = 'N';



   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END RTW_EXTRACT;
---------------------------------------------------------------------------------------------------

-- Function Name : PACK_DTL_EXTRACT
-- Purpose       : Function to Fetch Pack Details from RMS
---------------------------------------------------------------------------------------------------
FUNCTION PACK_DTL_EXTRACT (O_error_message IN OUT VARCHAR2)
RETURN BOOLEAN is
   L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.PACK_DTL_EXTRACT';

   L_group_id SMR_RMS_INT_QUEUE.GROUP_ID%TYPE := NULL;
	 L_interface_Id  SMR_RMS_INT_TYPE.INTERFACE_ID%TYPE;
   L_exists        varchar2(1):=null;

  Cursor C_pack_exists is
   select 'X'
   from packitem pi, item_master im,
           SMR_RMS_PACK_DTL_STG s
     where pi.pack_no = im.item
       and im.item = s.item
       and im.pack_ind = 'Y' and im.simple_pack_ind = 'N'
       and im.pack_type = 'V'
       and s.processed_ind = 'N'
       order by pi.pack_no;

   Cursor C_get_int_id is
     select s.interface_id
       from SMR_RMS_INT_TYPE s
     where s.interface_name = 'VENDOR_PACKS';
---
BEGIN

   open C_pack_exists;
   fetch C_pack_exists into L_exists;
   close C_pack_exists;

   if L_exists is null then
      return True;
   end if;


   open C_get_int_id;
   fetch C_get_int_id into  L_interface_Id;
   close C_get_int_id;

   /* Generate group Id */
   if SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID(O_error_message,
                       L_interface_Id,
                       L_group_id) = FALSE then
      RETURN FALSE;
   end if;

   /* Insert record into Interface queue */
   if SMR_LEAP_INTERFACE_SQL.ADD_INT_QUEUE(O_error_message,
                       L_interface_Id,
                       L_group_id) = FALSE then
      RETURN FALSE;
   end if;

    insert into SMR_RMS_INT_PACK_EXP
    select L_group_id,
           rownum,
           pi.pack_no,
           im.item_desc,
           pi.item,
           pi.pack_qty,
           s.status,
           sysdate
      from packitem pi, item_master im,
           SMR_RMS_PACK_DTL_STG s
     where pi.pack_no = im.item
       and im.item = s.item
       and im.pack_ind = 'Y' and im.simple_pack_ind = 'N'
       and im.pack_type = 'V'
       and s.processed_ind = 'N'
       order by pi.pack_no;

    update SMR_RMS_PACK_DTL_STG set processed_ind = 'Y'
      where processed_ind = 'N';

   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END PACK_DTL_EXTRACT;

---------------------------------------------------------------------------------------------------
-- Function Name : CHECK_CASE_NAME
-- Description   : Check to see if item has a Cased in Box and can be handled in 9522 and 9532 warehouses.
----------------------------------------------------------------------------------------------
FUNCTION CHECK_CASE_NAME(O_error_message IN OUT VARCHAR2,
                         I_Exists   OUT VARCHAR2,
                         I_order_no IN ORDHEAD.ORDER_NO%type,  
                         I_item IN item_master.item%TYPE)
RETURN BOOLEAN is
   L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.CHECK_CASE_NAME';
   
   cursor C_case_name is
     select 'Y'
       from item_supplier isu,
            ordhead oh
     where isu.item = I_item
       and isu.supplier = oh.supplier
       and oh.order_no = I_order_no
       and isu.case_name = 'BX';

   cursor C_supp_pack_size is
     select 'Y'
       from item_supp_country isc,
            ordhead oh
     where isc.item = I_item
       and isc.supplier = oh.supplier
       and oh.order_no = I_order_no
       and isc.supp_pack_size > 1;   
BEGIN
   I_Exists := 'N';
   
   Open C_case_name;
   
   fetch C_case_name into I_Exists;
   
   close C_case_name;
   
   
   
   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END CHECK_CASE_NAME;
----------------------------------------------------------------------------------------------
-- Function Name : CHECK_PACK_SIZE
-- Description   : Check to see if Order contains Items with Pack Size > 1
----------------------------------------------------------------------------------------------
FUNCTION CHECK_PACK_SIZE(O_error_message IN OUT VARCHAR2,
                         I_Exists   OUT VARCHAR2,
                         I_order_no IN ORDHEAD.ORDER_NO%type)
RETURN BOOLEAN is
   L_program        VARCHAR2(64) := 'SMR_LEAP_INTERFACE_SQL.CHECK_CASE_NAME';
   
   cursor C_supp_pack_size is
     select 'Y'
       from item_supp_country isc,
            ordhead oh,
            ordloc ol
     where isc.item = ol.item
       and isc.supplier = oh.supplier
       and oh.order_no = I_order_no
       and oh.order_no = ol.order_no
       and isc.supp_pack_size > 1;   
BEGIN
   I_Exists := 'N';
   
   Open C_supp_pack_size;
   
   fetch C_supp_pack_size into I_Exists;
   
   close C_supp_pack_size;
   
   RETURN TRUE;

EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      RETURN FALSE;
END CHECK_PACK_SIZE;
----------------------------------------------------------------------------------------------


END SMR_LEAP_INTERFACE_SQL;
/