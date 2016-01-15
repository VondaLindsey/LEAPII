set echo on
set verify on
set feedback on
set termout on
spool order_no_precision_mod.txt
alter table SMR_856_VENDOR_ITEM	modify(ORDER_NO number(10));
alter table SMR_856_VENDOR_ITEM_2	modify(ORDER_NO number(10));
alter table ALC_COMP_LOC	modify(ORDER_NO number(10));
alter table ALC_HEAD	modify(ORDER_NO number(10));
alter table ALC_HEAD_TEMP	modify(ORDER_NO number(10));
alter table ALLOC_HEADER_TEMP	modify(ORDER_NO number(10));
alter table ALLOC_REV	modify(ORDER_NO number(10));
alter table CE_CHARGES	modify(ORDER_NO number(10));
alter table CE_LIC_VISA	modify(ORDER_NO number(10));
alter table CE_ORD_ITEM	modify(ORDER_NO number(10));
alter table COMP_ITEM_ELC_TEMP	modify(ORDER_NO number(10));
alter table CONTRACT_ORDHEAD	modify(ORDER_NO number(10));
alter table CONTRACT_ORDLOC	modify(ORDER_NO number(10));
alter table CONTRACT_ORDSKU	modify(ORDER_NO number(10));
alter table COST_COMP_EXC_LOG	modify(ORDER_NO number(10));
alter table DEAL_ACTUALS_ITEM_LOC	modify(ORDER_NO number(10));
alter table DEAL_BB_NO_REBATE_TEMP	modify(ORDER_NO number(10));
alter table DEAL_CALC_QUEUE	modify(ORDER_NO number(10));
alter table DEAL_CALC_QUEUE_TEMP	modify(ORDER_NO number(10));
alter table DEAL_HEAD	modify(ORDER_NO number(10));
alter table DISC_OTB_APPLY	modify(ORDER_NO number(10));
alter table FIX_ASN_ALLOC_NO	modify(ORDER_NO number(10));
alter table GTT_COST_COMP_UPD	modify(ORDER_NO number(10));
alter table GTT_DEAL_ITEMLOC	modify(ORDER_NO number(10));
alter table IB_RESULTS	modify(ORDER_NO number(10));
alter table IIF_MATCH_DETAIL	modify(ORDER_NO number(10));
alter table IM_COST_DISCREPANCY	modify(ORDER_NO number(10));
alter table IM_COST_DISCREPANCY_HIST	modify(ORDER_NO number(10));
alter table IM_EDI_REJECT_DOC_HEAD	modify(ORDER_NO number(10));
alter table IM_EDI_REJECT_DOC_HEAD_BAK	modify(ORDER_NO number(10));
alter table IM_ORDLOC_GTT	modify(ORDER_NO number(10));
alter table IM_PARENT_INVOICE	modify(ORDER_NO number(10));
alter table IM_QTY_DISCREPANCY	modify(ORDER_NO number(10));
alter table IM_QTY_DISCREPANCY_HIST	modify(ORDER_NO number(10));
alter table IM_RECEIVER_COST_ADJUST	modify(ORDER_NO number(10));
alter table IM_RECEIVER_COST_ADJUST1	modify(ORDER_NO number(10));
alter table IM_RWO_SHIPMENT_HIST	modify(ORDER_NO number(10));
alter table IM_RWO_SHIPMENT_HIST_AU	modify(N_ORDER_NO number(10));
alter table IM_RWO_SHIPMENT_HIST_AU	modify(O_ORDER_NO number(10));
alter table IM_RWO_SHIPMENT_HIST_AU_BKUP	modify(N_ORDER_NO number(10));
alter table IM_RWO_SHIPMENT_HIST_AU_BKUP	modify(O_ORDER_NO number(10));
alter table IM_RWO_SHIPMENT_HIST_BKUP	modify(ORDER_NO number(10));
alter table IM_TRANSACTIONS_GTT	modify(ORDER_NO number(10));
alter table INVC_XREF	modify(ORDER_NO number(10));
alter table JDE_RECEIPT_DATA	modify(ORDER_NO number(10));
alter table LC_ACTIVITY	modify(ORDER_NO number(10));
alter table LC_AMENDMENTS	modify(ORDER_NO number(10));
alter table LC_DETAIL	modify(ORDER_NO number(10));
alter table LC_ORDAPPLY	modify(ORDER_NO number(10));
alter table LOCATION_DIST_TEMP	modify(ORDER_NO number(10));
alter table MISSING_DOC	modify(ORDER_NO number(10));
alter table MKH_ACCRUAL_QUERY_BY_PO	modify(ORDER_NO number(10));
alter table MKH_RECEIPT_COST_DIFF	modify(ORDER_NO number(10));
alter table MOD_ORDER_ITEM_HTS	modify(ORDER_NO number(10));
alter table ORDAUTO_TEMP	modify(ORDER_NO number(10));
alter table ORDCUST	modify(ORDER_NO number(10));
alter table ORDDIST_ITEM_TEMP	modify(ORDER_NO number(10));
alter table ORDER_MFQUEUE	modify(ORDER_NO number(10));
alter table ORDER_SHIPMENT_TEMP	modify(ORDER_NO number(10));
alter table ORDHEAD	modify(ORDER_NO number(10));
alter table ORDHEAD_AU	modify(ORDER_NO number(10));
alter table ORDHEAD_DISCOUNT	modify(ORDER_NO number(10));
alter table ORDHEAD_LOCK	modify(ORDER_NO number(10));
alter table ORDHEAD_REV	modify(ORDER_NO number(10));
alter table ORDHEAD_REV_AU	modify(ORDER_NO number(10));
alter table ORDITEM_SUM_TEMP	modify(ORDER_NO number(10));
alter table ORDLC	modify(ORDER_NO number(10));
alter table ORDLOC	modify(ORDER_NO number(10));
alter table ORDLOC_AU	modify(ORDER_NO number(10));
alter table ORDLOC_DISCOUNT	modify(ORDER_NO number(10));
alter table ORDLOC_DISCOUNT_BUILD	modify(ORDER_NO number(10));
alter table ORDLOC_DISCOUNT_TEMP	modify(ORDER_NO number(10));
alter table ORDLOC_EXP	modify(ORDER_NO number(10));
alter table ORDLOC_EXP_TEMP	modify(ORDER_NO number(10));
alter table ORDLOC_INVC_COST	modify(ORDER_NO number(10));
alter table ORDLOC_REV	modify(ORDER_NO number(10));
alter table ORDLOC_TEMP	modify(ORDER_NO number(10));
alter table ORDLOC_WKSHT	modify(ORDER_NO number(10));
alter table ORDREDST_TEMP	modify(ORDER_NO number(10));
alter table ORDSKU	modify(ORDER_NO number(10));
alter table ORDSKU_HTS	modify(ORDER_NO number(10));
alter table ORDSKU_HTS_ASSESS	modify(ORDER_NO number(10));
alter table ORDSKU_HTS_ASSESS_TEMP	modify(ORDER_NO number(10));
alter table ORDSKU_HTS_TEMP	modify(ORDER_NO number(10));
alter table ORDSKU_REV	modify(ORDER_NO number(10));
alter table ORDSKU_TEMP	modify(ORDER_NO number(10));
alter table ORD_INV_MGMT	modify(ORDER_NO number(10));
alter table ORD_LC_AMENDMENTS	modify(ORDER_NO number(10));
alter table ORD_PREISSUE	modify(ORDER_NO number(10));
alter table ORD_XDOCK_TEMP	modify(ORDER_NO number(10));
alter table PDD_SMR_EDI_ORD_EXTRACT_HIST	modify(ORDER_NO number(10));
alter table RCA_RIB_INTERFACE	modify(ORDER_NO number(10));
alter table REPL_RESULTS	modify(ORDER_NO number(10));
alter table REPL_RESULTS_TEMP	modify(ORDER_NO number(10));
alter table REV_ORDERS	modify(ORDER_NO number(10));
alter table RPM_DEAL_HEAD	modify(ORDER_NO number(10));
alter table RPM_EVENT_ITEMLOC_DEALS	modify(ORDER_NO number(10));
alter table RUA_MFQUEUE	modify(ORDER_NO number(10));
alter table RUA_RIB_INTERFACE	modify(ORDER_NO number(10));
alter table RWO_RE_PROCESS_SHIPMENTS	modify(ORDER_NO number(10));
alter table SHIPMENT	modify(ORDER_NO number(10));
alter table SHIPMENT_EOY	modify(ORDER_NO number(10));
alter table SMR_850_RESEND	modify(ORDER_NO number(10));
alter table SMR_856_SHIPMENT_TEMP	modify(ORDER_NO number(10));
alter table SMR_856_VENDOR_ARI	modify(ORDER_NO number(10));
alter table SMR_ALC_EXT	modify(ORDER_NO number(10));
alter table SMR_ALC_EXT_CUSTOM	modify(ORDER_NO number(10));
alter table SMR_ALC_EXT_CUSTOM_TEMP	modify(ORDER_NO number(10));
alter table SMR_ALC_EXT_FILE	modify(LINE_ORDER number(10));
alter table SMR_ALC_EXT_TEMP	modify(ORDER_NO number(10));
alter table SMR_DEBMEMREVERSAL_STAGING	modify(ORDER_NO number(10));
alter table SMR_EDI_ORD_EXTRACT_HIST	modify(ORDER_NO number(10));
alter table SMR_IM_RECEIVER_COST_ADJUST	modify(ORDER_NO number(10));
alter table SMR_ORDHEAD	modify(ORDER_NO number(10));
alter table SMR_ORD_EXTRACT	modify(ORDER_NO number(10));
alter table SMR_SHIPMENT_ACCRUAL	modify(ORDER_NO number(10));
alter table SMR_TKT_ORDER_REV	modify(ORDER_NO number(10));
alter table SMR_TKT_ORDER_STG	modify(ORDER_NO number(10));
alter table SMR_TKT_ORDER_STG_TEMP	modify(ORDER_NO number(10));
alter table SMR_TKT_STG_DETAIL	modify(ORDER_NO number(10));
alter table SMR_TKT_STG_HEAD	modify(ORDER_NO number(10));
alter table SMR_TKT_STG_REJECT	modify(ORDER_NO number(10));
alter table SSB_RECEIPT_ACCRUAL	modify(ORDER_NO number(10));
alter table STAGE_COMPLEX_DEAL_DETAIL	modify(ORDER_NO number(10));
alter table STAGE_PURGED_SHIPMENTS	modify(ORDER_NO number(10));
alter table STORE_GRADE_DIST_TEMP	modify(ORDER_NO number(10));
alter table SUPS_MIN_FAIL	modify(ORDER_NO number(10));
alter table TEMP_TRAN	modify(ORDER_NO number(10));
alter table TICKET_REQUEST	modify(ORDER_NO number(10));
alter table TRANSPORTATION	modify(ORDER_NO number(10));
alter table TRANSPORTATION_SHIPMENT	modify(ORDER_NO number(10));
alter table TSFHEAD	modify(ORDER_NO number(10));
alter table VENDINVC_TEMP	modify(ORDER_NO number(10));
alter table WOIN_MFQUEUE	modify(ORDER_NO number(10));
alter table WO_HEAD	modify(ORDER_NO number(10));
alter table WO_HEAD_TEMP	modify(ORDER_NO number(10));
alter table JDE_INVOICE_DATA	modify(ORDER_NO VARCHAR2(10));

----
alter table SMR_856_DATA_CONVERSION_DEL	modify(ORDER_NO number(10));
alter table SMR_856_DATA_CONVERSION_ERR	modify(ORDER_NO number(10));
alter table SMR_856_DATA_CONVERSION_ERR_1	modify(ORDER_NO number(10));
alter table SMR_856_DATA_CONVERSION_USE	modify(ORDER_NO number(10));
alter table SMR_856_DATA_CONVERSION_USE_1	modify(ORDER_NO number(10));
alter table SMR_856_VENDOR_ORDER	modify(ORDER_NO number(10));
alter table SMR_944_SQLLOAD_DATA	modify(ORDER_NO number(10));
alter table SMR_944_SQLLOAD_DATA_USE	modify(ORDER_NO number(10));
alter table SMR_944_SQLLOAD_ERR	modify(ORDER_NO number(10));
alter table SMR_944_SQLLOAD_ERR_AUDIT	modify(NEW_ORDER_NO number(10));
alter table SMR_944_SQLLOAD_ERR_AUDIT	modify(OLD_ORDER_NO number(10));
alter table SMR_944_SQLLOAD_ERR_EOY	modify(OLD_ORDER_NO number(10));

alter table smr_receipt_accrual	modify(ORDER_NO number(10));



spool off;
