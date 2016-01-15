CREATE OR REPLACE PACKAGE BODY STOCK_ORDER_RCV_SQL AS
/*=====================================================================================*/
-- Modification History
-- Version Date      Developer   Issue     Description
-- ======= ========= =========== ========= ===============================================
-- 1.01    26-Jun-12 L.Tan       IMS116600 When an Allocation receipt is received from SIM
--                                         for a 9401 order, roll back records created due
--                                         to different from location in Allocation
--                                         (WH=9401) and Shipment (FROM_LOC=952-4) because
--                                         code thinks shipment was sent to wrong location.
--                                         ALLOC_LINE_ITEM modified to not roll back records
--                                         if ALLOC_HEADER.WH = 9401 and the
--                                         SHIPMENT.FROM_LOC = SDC (i.e. 952-4).
-- 1.02    20-Nov-12 L.Tan       IMS129287 Modified code to prevent STAKE_SKU_LOC.SNAPSHOT_IN_TRANSIT_QTY
--                                         from going into the negative.  The snapshot
--                                         in-transit qty is currently being reduced by the quantity
--                                         received (if receipt is before cycle count date).
--                                         it should be reduced by the quantity shipped instead.
--                                         NOTE: This does not cater for over receipts where the
--                                               receiving location is a WH and the Receive As Type = 'P'
--                                               as SMR does not use this feature right now.
-- 1.03    03-Dec-12 L.Tan       IMS124964 Modified UPDATE_ITEM_STOCK to calculate the average
--                                         cost upon over recceipt instead of NULLing
--                                         the average cost.
-- 1.04    20- May-15 Murali     Leap      Populate ref_no_1(Alloc/TSf No) and ref_no_1(shipment)
--                                         field in Tran_data for tran code 44.
-----------------------------------------------------------------------------------------
/*=====================================================================================*/
--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------
LP_system_options_row  SYSTEM_OPTIONS%ROWTYPE;
LP_shipment            SHIPMENT.SHIPMENT%TYPE;
LP_tsf_type            TSFHEAD.TSF_TYPE%TYPE;
-- Data structures for BULK DML:
-- Global cache for appt_detail update
TYPE appt_detail_qty_received_TBL  is table of appt_detail.qty_received%TYPE INDEX BY BINARY_INTEGER;
TYPE appt_detail_receipt_no_TBL    is table of appt_detail.receipt_no%TYPE INDEX BY BINARY_INTEGER;
TYPE appt_detail_rowid_TBL         is table of ROWID INDEX BY BINARY_INTEGER;
---
P_appt_detail_qty_received   appt_detail_qty_received_TBL;
P_appt_detail_receipt_no     appt_detail_receipt_no_TBL;
P_appt_detail_rowid          appt_detail_rowid_TBL;
P_appt_detail_size           BINARY_INTEGER := 0;
-- Global cache for doc_close_queue insert
TYPE doc_close_queue_doc_TBL       is table of doc_close_queue.doc%TYPE INDEX BY BINARY_INTEGER;
TYPE doc_close_queue_doc_type_TBL  is table of doc_close_queue.doc_type%TYPE INDEX BY BINARY_INTEGER;
---
P_doc_close_queue_doc        doc_close_queue_doc_TBL;
P_doc_close_queue_doc_type   doc_close_queue_doc_type_TBL;
P_doc_close_queue_size       BINARY_INTEGER := 0;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Private function prototypes
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION ITEM_CHECK(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                    O_item             IN OUT ITEM_MASTER.ITEM%TYPE,
                    O_ref_item         IN OUT ITEM_MASTER.ITEM%TYPE,
                    O_dept             IN OUT ITEM_MASTER.DEPT%TYPE,
                    O_class            IN OUT ITEM_MASTER.CLASS%TYPE,
                    O_subclass         IN OUT ITEM_MASTER.SUBCLASS%TYPE,
                    O_pack_ind         IN OUT ITEM_MASTER.PACK_IND%TYPE,
                    O_pack_type        IN OUT ITEM_MASTER.PACK_TYPE%TYPE,
                    O_simple_pack_ind  IN OUT  ITEM_MASTER.SIMPLE_PACK_IND%TYPE,  --Catch Weight
                    O_catch_weight_ind IN OUT  ITEM_MASTER.CATCH_WEIGHT_IND%TYPE, --Catch Weight
                    O_sellable_ind     IN OUT  ITEM_MASTER.SELLABLE_IND%TYPE,
                    O_item_xform_ind   IN OUT  ITEM_MASTER.ITEM_XFORM_IND%TYPE,
                    I_item             IN     ITEM_MASTER.ITEM%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION SHIP_CHECK(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                    O_ship_found     IN OUT  BOOLEAN,
                    O_shipment       IN OUT  SHIPMENT.SHIPMENT%TYPE,
                    I_bol_no         IN      SHIPMENT.BOL_NO%TYPE,
                    I_phy_to_loc     IN      ITEM_LOC.LOC%TYPE,
                    I_phy_from_loc   IN      ITEM_LOC.LOC%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
-- The shipment, distro_no, inv_status, and carton fields are passed into
-- this function because the values depend on whether it is called from the
-- tsf/alloc bol_carton functions or the tsf/alloc line_item functions
--------------------------------------------------------------------------------
FUNCTION CHECK_SS(O_error_message           IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                  O_inv_flow_array          IN OUT  STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                  O_ss_unit_cost            IN OUT  ITEM_LOC_SOH.AV_COST%TYPE,
                  O_ss_prev_rcpt_qty        IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                  O_ss_exp_qty              IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                  O_item_rec                IN OUT  STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                  I_shipment                IN      SHIPMENT.SHIPMENT%TYPE,
                  I_distro_no               IN      SHIPSKU.DISTRO_NO%TYPE,
                  I_external_ind            IN      TSFHEAD.TSF_TYPE%TYPE,
                  I_inv_status              IN      SHIPSKU.INV_STATUS%TYPE,
                  I_carton                  IN      SHIPSKU.CARTON%TYPE,
                  I_qty                     IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                  I_weight                  IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                  I_weight_uom              IN      UOM_CLASS.UOM%TYPE,                -- Catch Weight
                  I_tampered_ind            IN      SHIPSKU.TAMPERED_IND%TYPE,
                  I_is_wrong_store          IN      BOOLEAN,
                  I_from_inv_status         IN      TSFDETAIL.INV_STATUS%TYPE,
                  I_store_type              IN      STORE.STORE_TYPE%TYPE := 'C')
RETURN BOOLEAN;
--------------------------------------------------------------------------------
--Catch Weight
FUNCTION DETERMINE_RECEIPT_WEIGHT(O_error_message          IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                                  O_total_overage_qty      IN OUT  SHIPSKU.QTY_EXPECTED%TYPE,
                                  O_total_overage_wgt_cuom IN OUT  SHIPSKU.WEIGHT_EXPECTED%TYPE,
                                  O_total_ss_rcpt_wgt_cuom IN OUT  SHIPSKU.WEIGHT_RECEIVED%TYPE,
                                  O_rcpt_wgt_cuom          IN OUT  SHIPSKU.WEIGHT_RECEIVED%TYPE,
                                  O_cuom                   IN OUT  ITEM_SUPP_COUNTRY.COST_UOM%TYPE,
                                  I_ss_exp_qty             IN      SHIPSKU.QTY_EXPECTED%TYPE,
                                  I_ss_exp_wgt             IN      SHIPSKU.WEIGHT_EXPECTED%TYPE,
                                  I_ss_exp_wgt_uom         IN      SHIPSKU.WEIGHT_EXPECTED_UOM%TYPE,
                                  I_ss_prev_rcpt_qty       IN      SHIPSKU.QTY_EXPECTED%TYPE,
                                  I_ss_prev_rcpt_wgt       IN      SHIPSKU.WEIGHT_RECEIVED%TYPE,
                                  I_ss_prev_rcpt_wgt_uom   IN      SHIPSKU.WEIGHT_RECEIVED_UOM%TYPE,
                                  I_rcpt_qty               IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                                  I_rcpt_wgt               IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,
                                  I_rcpt_wgt_uom           IN      UOM_CLASS.UOM%TYPE,
                                  I_item                   IN      ITEM_MASTER.ITEM%TYPE)
   RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION DIST_QTY_TO_FLOW(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          O_inv_flow_array  IN OUT  STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                          I_item            IN      ITEM_MASTER.ITEM%TYPE,
                          I_shipment        IN      SHIPMENT.SHIPMENT%TYPE,
                          I_ss_seq_no       IN      SHIPSKU.SEQ_NO%TYPE,
                          I_tsf_qty         IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION APPT_CHECK(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                    I_appt           IN      APPT_DETAIL.APPT%TYPE,
                    I_distro         IN      APPT_DETAIL.DOC%TYPE,
                    I_distro_type    IN      APPT_DETAIL.DOC_TYPE%TYPE,
                    I_to_loc_phy     IN      ITEM_LOC.LOC%TYPE,
                    I_item           IN      ITEM_MASTER.ITEM%TYPE,
                    I_asn            IN      APPT_DETAIL.ASN%TYPE,
                    I_receipt_no     IN      APPT_DETAIL.RECEIPT_NO%TYPE,
                    I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION TSF_CHECK(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                   O_tsf_type         IN OUT  TSFHEAD.TSF_TYPE%TYPE,
                   O_tsf_status       IN OUT  TSFHEAD.STATUS%TYPE,
                   O_from_loc_type    IN OUT  ITEM_LOC.LOC_TYPE%TYPE,
                   O_from_loc_distro  IN OUT  ITEM_LOC.LOC%TYPE,
                   O_from_loc_phy     IN OUT  ITEM_LOC.LOC%TYPE,
                   O_from_tsf_entity  IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                   O_from_finisher    IN OUT  VARCHAR2,
                   O_to_loc_type      IN OUT  ITEM_LOC.LOC_TYPE%TYPE,
                   O_to_loc_distro    IN OUT  ITEM_LOC.LOC%TYPE,
                   O_to_loc_phy       IN OUT  ITEM_LOC.LOC%TYPE,
                   O_to_tsf_entity    IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                   O_to_finisher      IN OUT  VARCHAR2,
                   O_tsf_parent_no    IN OUT  TSFHEAD.TSF_PARENT_NO%TYPE,
                   O_mrt_no           IN OUT  TSFHEAD.MRT_NO%TYPE,
                   I_tsf_no           IN      TSFHEAD.TSF_NO%TYPE,
                   I_loc              IN      ITEM_LOC.LOC%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION TSF_DETAIL_CHECK(O_error_message     IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          O_tsf_seq_no        IN OUT  TSFDETAIL.TSF_SEQ_NO%TYPE,
                          O_td_exp_qty        IN OUT  TSFDETAIL.TSF_QTY%TYPE,
                          O_td_prev_rcpt_qty  IN OUT  TSFDETAIL.RECEIVED_QTY%TYPE,
                          O_from_inv_status   IN OUT  TSFDETAIL.INV_STATUS%TYPE,
                          I_tsf_no            IN      TSFHEAD.TSF_NO%TYPE,
                          I_item              IN      ITEM_MASTER.ITEM%TYPE,
                          I_inv_status        IN      TSFDETAIL.INV_STATUS%TYPE,
                          I_recv_qty          IN      TSFDETAIL.RECEIVED_QTY%TYPE,
                          I_is_wrong_store    IN      BOOLEAN)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION ALLOC_CHECK(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                     O_alloc_status     IN OUT  ALLOC_HEADER.STATUS%TYPE,
                     O_from_loc_type    IN OUT  ITEM_LOC.LOC_TYPE%TYPE,
                     O_distro_from_loc  IN OUT  ITEM_LOC.LOC%TYPE,
                     O_from_loc_phy     IN OUT  ITEM_LOC.LOC%TYPE,
                     O_from_tsf_entity  IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                     O_to_tsf_entity    IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                     I_alloc_no         IN      ALLOC_HEADER.ALLOC_NO%TYPE,
                     I_item             IN      ITEM_MASTER.ITEM%TYPE,
                     I_to_loc           IN      ITEM_LOC.LOC%TYPE,
                     I_to_loc_type      IN      ITEM_LOC.LOC_TYPE%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION ALLOC_DETAIL_CHECK(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                            O_qty_allocated   IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                            O_qty_received    IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                            I_alloc_no        IN      ALLOC_HEADER.ALLOC_NO%TYPE,
                            I_to_loc          IN      ITEM_LOC.LOC%TYPE,
                            I_qty             IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                            I_is_wrong_store  IN      BOOLEAN)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION DETAIL_PROCESSING(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_item_rec        IN OUT  STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                           I_values          IN OUT  STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                           I_inv_flow_array  IN OUT  STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                           I_flow_cnt        IN      BINARY_INTEGER,
                           I_distro_no       IN      SHIPSKU.DISTRO_NO%TYPE,
                           I_distro_type     IN      APPT_DETAIL.DOC_TYPE%TYPE,
                           I_from_inv_status IN      TSFDETAIL.INV_STATUS%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION DETAIL_METHOD(O_error_message   IN OUT      RTK_ERRORS.RTK_TEXT%TYPE,
                       I_item_rec        IN OUT      STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                       I_values          IN OUT      STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                       I_inv_flow_array  IN          STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                       I_flow_cnt        IN          BINARY_INTEGER,
                       I_distro_no       IN          SHIPSKU.DISTRO_NO%TYPE,
                       I_distro_type     IN          APPT_DETAIL.DOC_TYPE%TYPE,
                       I_from_inv_status IN          TSFDETAIL.INV_STATUS%TYPE,
                       I_inventory_treatment_ind IN SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE )
RETURN BOOLEAN ;
--------------------------------------------------------------------------------
FUNCTION WF_DETAIL_PROCESSING(O_error_message   IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                              I_item_rec        IN OUT STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                              I_values          IN OUT STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                              I_inv_flow_array  IN     STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                              I_flow_cnt        IN     BINARY_INTEGER,
                              I_distro_no       IN     SHIPSKU.DISTRO_NO%TYPE,
                              I_distro_type     IN     APPT_DETAIL.DOC_TYPE%TYPE,
                              I_from_inv_status IN     TSFDETAIL.INV_STATUS%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION UPDATE_ITEM_STOCK(O_error_message     IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_distro_no         IN      SHIPSKU.DISTRO_NO%TYPE,
                           I_distro_type       IN      APPT_DETAIL.DOC_TYPE%TYPE,
                           I_item              IN      ITEM_MASTER.ITEM%TYPE,
                           I_dept              IN      ITEM_MASTER.DEPT%TYPE,
                           I_class             IN      ITEM_MASTER.CLASS%TYPE,
                           I_subclass          IN      ITEM_MASTER.SUBCLASS%TYPE,
                           I_inv_status        IN      SHIPSKU.INV_STATUS%TYPE,
                           I_pack_ind          IN      ITEM_MASTER.PACK_IND%TYPE,
                           I_pack_no           IN      ITEM_MASTER.ITEM%TYPE,
                           IO_pack_value       IN OUT  ITEM_LOC_SOH.UNIT_COST%TYPE,
                           I_from_loc          IN      ITEM_LOC.LOC%TYPE,
                           I_from_loc_type     IN      ITEM_LOC.LOC_TYPE%TYPE,
                           I_from_loc_wac      IN      ITEM_LOC_SOH.AV_COST%TYPE,         -- Transfer and Item Valuation
                           I_to_loc            IN      ITEM_LOC.LOC%TYPE,
                           I_to_loc_type       IN      ITEM_LOC.LOC_TYPE%TYPE,
                           I_receive_as_type   IN      ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                           I_upd_intran_qty    IN      ITEM_LOC_SOH.IN_TRANSIT_QTY%TYPE,
                           I_upd_av_cost_qty   IN      TSFDETAIL.RECEIVED_QTY%TYPE,
                           I_upd_av_cost_wgt   IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                           I_prim_charge       IN      ITEM_LOC_SOH.AV_COST%TYPE,
                           I_received_qty      IN      TSFDETAIL.RECEIVED_QTY%TYPE,
                           I_received_wgt_cuom IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight: distributed weight
                           I_cuom              IN      ITEM_SUPP_COUNTRY.COST_UOM%TYPE,   -- Catch Weight: distributed weight
                           I_tran_date         IN      PERIOD.VDATE%TYPE,
                           I_intercompany      IN      BOOLEAN)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION UPD_INV_STATUS(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        I_item           IN      ITEM_MASTER.ITEM%TYPE,
                        I_inv_status     IN      SHIPSKU.INV_STATUS%TYPE,
                        I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                        I_loc            IN      ITEM_LOC.LOC%TYPE,
                        I_loc_type       IN      ITEM_LOC.LOC_TYPE%TYPE,
                        I_tran_date      IN      PERIOD.VDATE%TYPE,
                        I_pack_ind       IN      ITEM_MASTER.PACK_IND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION TRANDATA_OVERAGE(O_error_message             IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          IO_total_pack_value         IN OUT  ITEM_LOC_SOH.UNIT_COST%TYPE,
                          I_pack_no                   IN      ITEM_MASTER.ITEM%TYPE,
                          I_item                      IN      ITEM_MASTER.ITEM%TYPE,
                          I_dept                      IN      ITEM_MASTER.DEPT%TYPE,
                          I_class                     IN      ITEM_MASTER.CLASS%TYPE,
                          I_subclass                  IN      ITEM_MASTER.SUBCLASS%TYPE,
                          I_to_loc                    IN      ITEM_LOC.LOC%TYPE,
                          I_to_loc_type               IN      ITEM_LOC.LOC_TYPE%TYPE,
                          I_to_tsf_entity             IN      TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                          I_to_finisher               IN      VARCHAR2,
                          I_from_loc                  IN      ITEM_LOC.LOC%TYPE,
                          I_from_loc_type             IN      ITEM_LOC.LOC_TYPE%TYPE,
                          I_from_tsf_entity           IN      TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                          I_from_finisher             IN      VARCHAR2,
                          I_rcv_qty                   IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                          I_rcv_weight                IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE, -- Catch Weight
                          I_distro_no                 IN      SHIPSKU.DISTRO_NO%TYPE,
                          I_distro_type               IN      VARCHAR2,
                          I_shipment                  IN      SHIPMENT.SHIPMENT%TYPE,
                          I_tran_date                 IN      PERIOD.VDATE%TYPE,
                          I_from_wac                  IN      item_loc_soh.av_cost%TYPE,        -- Transfers and Item Valuation
                          I_profit_chrgs_to_loc       IN      ITEM_LOC_SOH.AV_COST%TYPE,
                          I_exp_chrgs_to_loc          IN      ITEM_LOC_SOH.AV_COST%TYPE,
                          I_intercompany              IN      BOOLEAN,                          -- Transfers and Item Valuation
                          I_inventory_treatment_ind   IN      SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION UPDATE_FROM_OVERAGE(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                             I_item           IN      ITEM_MASTER.ITEM%TYPE,
                             I_comp_ind       IN      VARCHAR2,
                             I_from_loc       IN      ITEM_LOC.LOC%TYPE,
                             I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                             I_weight_cuom    IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                             I_cuom           IN      ITEM_SUPP_COUNTRY.COST_UOM%TYPE)    -- Catch Weight
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION PROC_STK_CNT_TD_WRITE(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                               I_distro_no        IN      SHIPSKU.DISTRO_NO%TYPE,
                               I_cycle_count      IN      STAKE_HEAD.CYCLE_COUNT%TYPE,
                               I_item             IN      ITEM_MASTER.ITEM%TYPE,
                               I_dept             IN      ITEM_MASTER.DEPT%TYPE,
                               I_class            IN      ITEM_MASTER.CLASS%TYPE,
                               I_subclass         IN      ITEM_MASTER.SUBCLASS%TYPE,
                               I_to_loc           IN      ITEM_LOC.LOC%TYPE,
                               I_to_loc_type      IN      ITEM_LOC.LOC_TYPE%TYPE,
                               I_qty              IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                               I_snapshot_retail  IN      ITEM_LOC_SOH.AV_COST%TYPE,
                               I_snapshot_cost    IN      ITEM_LOC.UNIT_RETAIL%TYPE,
                               I_tran_date        IN      PERIOD.VDATE%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION PACK_LEVEL_PROC(O_error_message             IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                         O_receive_as_type           IN OUT   ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                         O_from_pack_av_cost         IN OUT   ITEM_LOC_SOH.AV_COST%TYPE,
                         O_pack_av_cost_ratio        IN OUT   NUMBER,
                         I_distro_no                 IN       SHIPSKU.DISTRO_NO%TYPE,
                         I_pack_no                   IN       ITEM_MASTER.ITEM%TYPE,
                         I_dept                      IN       ITEM_MASTER.DEPT%TYPE,
                         I_class                     IN       ITEM_MASTER.CLASS%TYPE,
                         I_subclass                  IN       ITEM_MASTER.SUBCLASS%TYPE,
                         I_inv_status                IN       SHIPSKU.INV_STATUS%TYPE,
                         I_from_loc                  IN       ITEM_LOC.LOC%TYPE,
                         I_from_loc_type             IN       ITEM_LOC.LOC_TYPE%TYPE,
                         I_from_rcv_as_type          IN       ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                         I_to_loc                    IN       ITEM_LOC.LOC%TYPE,
                         I_to_loc_type               IN       ITEM_LOC.LOC_TYPE%TYPE,
                         I_tran_date                 IN       PERIOD.VDATE%TYPE,
                         I_rcv_qty                   IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_intran_qty                IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_overage_qty               IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_overage_weight_cuom       IN       ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                         I_cuom                      IN       ITEM_SUPP_COUNTRY.COST_UOM%TYPE,    -- CatchWeight
                         I_prim_charge               IN       ITEM_LOC_SOH.AV_COST%TYPE,
                         I_from_loc_av_cost          IN       ITEM_LOC_SOH.AV_COST%TYPE,
                         I_from_inv_status           IN       TSFDETAIL.INV_STATUS%TYPE,
                         I_store_type                IN       STORE.STORE_TYPE%TYPE := 'C',
                         I_inventory_treatment_ind   IN       SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION UPDATE_PACK_STOCK(O_error_message       IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_pack_no             IN      ITEM_MASTER.ITEM%TYPE,
                           I_to_loc              IN      ITEM_LOC.LOC%TYPE,
                           I_stk_cnt_procd       IN      BOOLEAN,
                           I_rcv_qty             IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                           I_intran_qty          IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                           I_overage_qty         IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,   -- Catch Weight
                           I_overage_weight_cuom IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                           I_tran_date           IN      PERIOD.VDATE%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION LOAD_COMPS(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                    O_comp_items     IN OUT  STOCK_ORDER_RCV_SQL.COMP_ITEM_ARRAY,
                    I_pack_no        IN      ITEM_MASTER.ITEM%TYPE,
                    I_from_loc       IN      ITEM_LOC.LOC%TYPE,
                    I_from_loc_type  IN      ITEM_LOC.LOC_TYPE%TYPE,
                    I_to_loc         IN      ITEM_LOC.LOC%TYPE,
                    I_to_loc_type    IN      ITEM_LOC.LOC_TYPE%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION FLUSH_APPT_DETAIL_UPDATE(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION FLUSH_DOC_CLOSE_QUEUE_INSERT(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
-- This function is only here as a debug aid.  It should not be used
-- in production code.
--------------------------------------------------------------------------------
/*
FUNCTION DISPLAY_STRUCT(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        I_item_rec        IN      STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                        I_values          IN      STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                        I_inv_flow_array  IN      STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY)
RETURN BOOLEAN;*/
--------------------------------------------------------------------------------
FUNCTION UPD_SHIPMENT(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                      I_shipment       IN      SHIPMENT.SHIPMENT%TYPE,
                      I_tran_date      IN      PERIOD.VDATE%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
-- This function will check if the Carton is unwanded carton.
-- If the carton does not exist for any shipment in the system (not on shipsku),
-- we assume it is an unwanded carton, i.e. it was physically placed on the
-- truck at the shipping location but never scanned.
--------------------------------------------------------------------------------
FUNCTION UNWANDED_CARTON(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                         O_unwanded       IN OUT  BOOLEAN,
                         I_carton         IN      SHIPSKU.CARTON%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
-- This function will return O_is_walk_through = TRUE if shipment.to_loc is
-- a walk through store for I_rcv_to_loc.
--------------------------------------------------------------------------------
FUNCTION WALK_THROUGH_STORE (O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                             O_is_walk_through  IN OUT  BOOLEAN,
                             O_shipment         IN OUT  SHIPMENT.SHIPMENT%TYPE,
                             O_intended_store   IN OUT  STORE.STORE%TYPE,
                             I_bol_no           IN      SHIPMENT.BOL_NO%TYPE,
                             I_rcv_to_loc       IN      STORE.STORE%TYPE,
                             I_carton           IN      SHIPSKU.CARTON%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
-- This function will reverse shipment transactions to the intended location
-- and create shipment transactions to the actual receiving location.
--------------------------------------------------------------------------------
FUNCTION WRONG_STORE_RECEIPT(O_error_message         IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                             O_shipment              IN OUT  SHIPMENT.SHIPMENT%TYPE,
                             O_intended_to_loc       IN OUT  ITEM_LOC.LOC%TYPE,
                             I_actual_to_loc         IN      ITEM_LOC.LOC%TYPE,
                             I_actual_to_tsf_entity  IN      TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                             I_from_loc              IN      ITEM_LOC.LOC%TYPE,
                             I_from_loc_type         IN      ITEM_LOC.LOC_TYPE%TYPE,
                             I_from_tsf_entity       IN      TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                             I_from_finisher         IN      VARCHAR2,
                             I_item                  IN      ITEM_MASTER.ITEM%TYPE,
                             I_bol_no                IN      SHIPMENT.BOL_NO%TYPE,
                             I_carton                IN      SHIPSKU.CARTON%TYPE,
                             I_distro_type           IN      SHIPSKU.DISTRO_TYPE%TYPE,
                             I_distro_no             IN      SHIPSKU.DISTRO_NO%TYPE,
                             I_dept                  IN      ITEM_MASTER.DEPT%TYPE,
                             I_class                 IN      ITEM_MASTER.CLASS%TYPE,
                             I_subclass              IN      ITEM_MASTER.SUBCLASS%TYPE,
                             I_pack_ind              IN      ITEM_MASTER.PACK_IND%TYPE,
                             I_pack_type             IN      ITEM_MASTER.PACK_TYPE%TYPE,
                             I_tran_date             IN      TRAN_DATA.TRAN_DATE%TYPE,
                             I_tsf_type              IN      TSFHEAD.TSF_TYPE%TYPE)          -- Transfer and Item Valuation
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION UPD_TO_ITEM_LOC(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                         I_distro_no        IN      SHIPSKU.DISTRO_NO%TYPE,
                         I_distro_type      IN      APPT_DETAIL.DOC_TYPE%TYPE,
                         I_item             IN      ITEM_MASTER.ITEM%TYPE,
                         I_pack_no          IN      ITEM_MASTER.ITEM%TYPE,
                         I_percent_in_pack  IN      NUMBER,
                         I_receive_as_type  IN      ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                         I_to_loc           IN      ITEM_LOC.LOC%TYPE,
                         I_to_loc_type      IN      ITEM_LOC.LOC_TYPE%TYPE,
                         I_qty              IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_weight_cuom      IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                         I_cuom             IN      UOM_CLASS.UOM%TYPE,                -- Catch Weight
                         I_from_loc         IN      ITEM_LOC.LOC%TYPE,
                         I_from_loc_type    IN      ITEM_LOC.LOC_TYPE%TYPE,
                         I_from_wac         IN      ITEM_LOC_SOH.AV_COST%TYPE,         -- changed from av_cost to wac for Transfers and Item Valuation
                         I_prim_charge      IN      ITEM_LOC_SOH.AV_COST%TYPE,
                         I_intercompany     IN      BOOLEAN)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
-- This function should be called when receiving at a finisher.  The function
-- will reserve the 'to' item quantity at the finisher and will increment the
-- 'to' item expected qty at the final receiving location.
--------------------------------------------------------------------------------
FUNCTION UPD_ITEM_RESV_EXP(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                             I_item           IN      ITEM_MASTER.ITEM%TYPE,
                             I_tsf_no         IN      TSFHEAD.TSF_NO%TYPE,
                             I_recv_loc       IN      ITEM_LOC.LOC%TYPE,
                             I_recv_loc_type  IN      ITEM_LOC.LOC_TYPE%TYPE,
                             I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION NEW_RECEIPT_ITEM(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          O_item_rec        IN OUT  STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                          I_shipment        IN      SHIPMENT.SHIPMENT%TYPE,
                          I_from_inv_status IN      SHIPSKU.INV_STATUS%TYPE,
                          I_carton          IN      SHIPSKU.CARTON%TYPE,
                          I_qty             IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                          I_weight          IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                          I_weight_uom      IN      UOM_CLASS.UOM%TYPE)                 -- CatchWeight
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION GET_INV_STATUS(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        O_inv_status     IN OUT  SHIPSKU.INV_STATUS%TYPE,
                        I_shipment       IN      SHIPSKU.SHIPMENT%TYPE,
                        I_distro_no      IN      SHIPSKU.DISTRO_NO%TYPE,
                        I_distro_type    IN      SHIPSKU.DISTRO_TYPE%TYPE,
                        I_carton         IN      SHIPSKU.CARTON%TYPE,
                        I_item           IN      SHIPSKU.ITEM%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION MRT_LINE_ITEM(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                       I_mrt_no        IN     MRT_ITEM_LOC.MRT_NO%TYPE,
                       I_item          IN     MRT_ITEM_LOC.ITEM%TYPE,
                       I_location      IN     MRT_ITEM_LOC.LOCATION%TYPE,
                       I_received_qty  IN     MRT_ITEM_LOC.RECEIVED_QTY%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
FUNCTION UPDATE_WF_RETURN(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                          I_item_rec      IN     ITEM_MASTER%ROWTYPE,
                          I_distro_no     IN     SHIPSKU.DISTRO_NO%TYPE,
                          I_distro_type   IN     SHIPSKU.DISTRO_TYPE%TYPE,
                          I_qty           IN     ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
RETURN BOOLEAN;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION INIT_TSF_ALLOC_GROUP(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
return BOOLEAN IS
   L_function           VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.INIT_TSF_ALLOC_GROUP';
BEGIN
   P_appt_detail_size := 0;
   P_doc_close_queue_size := 0;
   if STKLEDGR_SQL.INIT_TRAN_DATA_INSERT(O_error_message) = FALSE then
      return FALSE;
   end if;
   --- The session for this package may stay open for long periods, so
   --- call this function to refresh the system options in case they have changed.
   if SYSTEM_OPTIONS_SQL.POPULATE_SYSTEM_OPTIONS(O_error_message) = FALSE then
      return FALSE;
   end if;
   ---
   if SYSTEM_OPTIONS_SQL.GET_SYSTEM_OPTIONS(O_error_message,
                                            LP_system_options_row) = FALSE then
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_function,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END INIT_TSF_ALLOC_GROUP;
-------------------------------------------------------------------------------
FUNCTION FINISH_TSF_ALLOC_GROUP(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
   return BOOLEAN IS
   L_function           VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.FINISH_TSF_ALLOC_GROUP';
BEGIN
   if FLUSH_APPT_DETAIL_UPDATE(O_error_message) = FALSE then
      return FALSE;
   end if;
   if FLUSH_DOC_CLOSE_QUEUE_INSERT(O_error_message) = FALSE then
      return FALSE;
   end if;
   if STKLEDGR_SQL.FLUSH_TRAN_DATA_INSERT(O_error_message) = FALSE then
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_function,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END FINISH_TSF_ALLOC_GROUP;
-------------------------------------------------------------------------------
FUNCTION TSF_LINE_ITEM(O_error_message     IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                       I_loc               IN      ITEM_LOC.LOC%TYPE,
                       I_item              IN      ITEM_MASTER.ITEM%TYPE,
                       I_qty               IN      TRAN_DATA.UNITS%TYPE,
                       I_weight            IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                       I_weight_uom        IN      UOM_CLASS.UOM%TYPE,                -- Catch Weight
                       I_transaction_type  IN      VARCHAR2, --(ADJ FLAG)
                       I_tran_date         IN      PERIOD.VDATE%TYPE,
                       I_receipt_number    IN      APPT_DETAIL.RECEIPT_NO%TYPE,
                       I_bol_no            IN      SHIPMENT.BOL_NO%TYPE,
                       I_appt              IN      APPT_HEAD.APPT%TYPE,
                       I_carton            IN      SHIPSKU.CARTON%TYPE,
                       I_distro_type       IN      VARCHAR2,
                       I_distro_number     IN      TSFHEAD.TSF_NO%TYPE,
                       I_disp              IN      INV_STATUS_CODES.INV_STATUS_CODE%TYPE,
                       I_tampered_ind      IN      SHIPSKU.TAMPERED_IND%TYPE,
                       I_dummy_carton_ind  IN      SYSTEM_OPTIONS.DUMMY_CARTON_IND%TYPE)
   RETURN BOOLEAN IS
   L_program                VARCHAR2(61) := 'STOCK_ORDER_RCV_SQL.TSF_LINE_ITEM';
   L_invalid_param          VARCHAR2(30);
   L_invalid_value          VARCHAR2(30) := 'NULL';
   L_item_rec               STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD;
   L_values                 STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD;
   L_inv_flow_array         STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY;
   flow_cnt                 BINARY_INTEGER := 1;
   L_current_intran         ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_new_intran             ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_ship_found             BOOLEAN;
   L_is_unwanded            BOOLEAN := FALSE;
   L_is_walk_through        BOOLEAN := FALSE;
   L_is_wrong_store         BOOLEAN := FALSE;
   L_intended_store         ITEM_LOC.LOC%TYPE;
   L_inv_status_code        INV_STATUS_CODES.INV_STATUS_CODE%TYPE;
   L_from_inv_status        TSFDETAIL.INV_STATUS%TYPE;
   L_ss_qty_expected        SHIPSKU.QTY_EXPECTED%TYPE;
   L_ss_qty_received        SHIPSKU.QTY_RECEIVED%TYPE;
   L_rowid_tsfdet           ROWID := NULL;
   L_carton_ind             VARCHAR2(1);
   L_count_open_ship        NUMBER(3);
   L_ship_qty               TSFDETAIL.SHIP_QTY%TYPE;
   L_tsf_qty                TSFDETAIL.TSF_QTY%TYPE;
   L_comp_items             STOCK_ORDER_RCV_SQL.COMP_ITEM_ARRAY;
   L_from_loc               SHIPMENT.FROM_LOC%TYPE;
   L_from_loc_type          SHIPMENT.FROM_LOC_TYPE%TYPE;
   L_store_type             STORE.STORE_TYPE%TYPE;
   L_wf_ind                 SYSTEM_OPTIONS.WHOLESALE_FRANCHISE_IND%TYPE;
   ---
   ROLLBACK_TRAN_DATA       EXCEPTION;
   cursor C_FROM_LOC is
      select NVL(sh.from_loc, -1),
             NVL(sh.from_loc_type, '-1')
        from shipsku sk,shipment sh
       where sk.distro_no = I_distro_number
         and sk.shipment  = sh.shipment
         and sh.bol_no    = I_bol_no;
   cursor C_TSFDETAIL_LOCK is
      select rowid,NVL(ship_qty,0),NVL(tsf_qty,0)
        from tsfdetail
       where tsf_no = I_distro_number
         and item = I_item
         for update nowait;
   cursor C_OPEN_SHIP_COUNT is
      select   count(1)
        from shipment sh
       where sh.status_code = 'I'
         and  sh.shipment in (select shipment
                                from shipsku
                               where distro_no =I_distro_number);
   cursor C_LOCK_ITEM_LOC_SOH(cv_item  ITEM_LOC_SOH.ITEM%TYPE,
                              cv_loc   ITEM_LOC_SOH.LOC%TYPE) is
      select 'X'
        from item_loc_soh
       where item = cv_item
         and loc = cv_loc
         for update nowait;
   cursor C_GET_STORE_TYPE is
     select store_type
       from store
      where store = L_from_loc;
   cursor C_GET_WF_IND is
      select wholesale_franchise_ind
        from system_options;
BEGIN
   open C_GET_WF_IND;
   SQL_LIB.SET_MARK('FETCH','C_GET_WF_IND', 'SYSTEM_OPTIONS', 'WAREHOUSE_FRANCHISE_IND');
   fetch C_GET_WF_IND into L_wf_ind;
   SQL_LIB.SET_MARK('CLOSE','C_GET_WF_IND', 'SYSTEM_OPTIONS', 'WAREHOUSE_FRANCHISE_IND');
   close C_GET_WF_IND;
   if I_bol_no is NOT NULL AND I_distro_number is NOT NULL then
      open C_FROM_LOC;
      SQL_LIB.SET_MARK('FETCH','C_GET_WF_IND', 'SYSTEM_OPTIONS', 'WAREHOUSE_FRANCHISE_IND');
      fetch C_FROM_LOC into L_from_loc,
                            L_from_loc_type;
      SQL_LIB.SET_MARK('CLOSE','C_GET_WF_IND', 'SYSTEM_OPTIONS', 'WAREHOUSE_FRANCHISE_IND');
      close C_FROM_LOC;
   end if;
   if L_wf_ind = 'Y' and L_from_loc_type = 'S' then
      open C_GET_STORE_TYPE;
      SQL_LIB.SET_MARK('FETCH','C_GET_STORE_TYPE', 'STORE', 'STORE: '||I_loc);
      fetch C_GET_STORE_TYPE into L_store_type;
      if C_GET_STORE_TYPE%NOTFOUND then
         SQL_LIB.SET_MARK('CLOSE','C_GET_STORE_TYPE', 'STORE', 'STORE: '||I_loc);
         close C_GET_STORE_TYPE;
         RETURN FALSE;
      else
         SQL_LIB.SET_MARK('CLOSE','C_GET_STORE_TYPE', 'STORE', 'STORE: '||I_loc);
         close C_GET_STORE_TYPE;
      end if;
   end if;
   if I_loc is NULL then
      L_invalid_param := 'I_loc';
   elsif I_item is NULL then
      L_invalid_param := 'I_item';
   elsif I_qty is NULL then
      L_invalid_param := 'I_qty';
   elsif I_transaction_type is NULL then
      L_invalid_param := 'I_transaction_type';
   elsif I_tran_date is NULL then
      L_invalid_param := 'I_tran_date';
   elsif I_bol_no is NULL then
      L_invalid_param := 'I_bol_no';
   elsif I_distro_type is NULL then
      L_invalid_param := 'I_distro_type';
   -- distro_number is not required for items in dummy cartons
   elsif I_distro_number is NULL
   and   NVL(I_dummy_carton_ind,'N') != 'Y' then
      L_invalid_param := 'I_distro_number';
   elsif I_distro_type != 'T' then
      L_invalid_param := 'I_distro_type';
      L_invalid_value := I_distro_type;
   elsif I_transaction_type NOT IN ('R','A','T') then
      L_invalid_param := 'I_transaction_type';
      L_invalid_value := I_transaction_type;
   end if;
   ---
   if L_invalid_param is NOT NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_PARM_PROG',
                                            L_program,
                                            L_invalid_param,
                                            L_invalid_value);
      return FALSE;
   end if;
   if STKLEDGR_SQL.SET_SAVEPOINT (O_error_message) = FALSE then
      return FALSE;
   end if;
   if  LP_system_options_row.dummy_carton_ind = 'Y'
   and NVL(I_dummy_carton_ind,'N') = 'Y' then
      insert into dummy_carton_stage(distro_no,
                                     distro_type,
                                     item,
                                     to_loc,
                                     carton,
                                     bol_no,
                                     qty,
                                     tran_type,
                                     tran_date,
                                     receipt_no,
                                     appt_no,
                                     disposition_code,
                                     tampered_ind,
                                     last_update_datetime)
                              values(I_distro_number,
                                     I_distro_type,
                                     I_item,
                                     I_loc,
                                     I_carton,
                                     I_bol_no,
                                     I_qty,
                                     I_transaction_type,
                                     I_tran_date,
                                     I_receipt_number,
                                     I_appt,
                                     I_disp,
                                     I_tampered_ind,
                                     SYSDATE);
      return TRUE;
   end if;
   L_values.input_qty          := I_qty;
   L_item_rec.tran_date        := I_tran_date;
   L_item_rec.receipt_no       := I_receipt_number;
   L_item_rec.bol_no           := I_bol_no;
   L_item_rec.appt             := I_appt;
   L_item_rec.carton           := I_carton;
   L_item_rec.distro_type      := I_distro_type;
   L_item_rec.tsf_no           := I_distro_number;
   L_item_rec.transaction_type := REPLACE(I_transaction_type,'T','R'); --transshipment is equivalent to receipt
   if STOCK_ORDER_RCV_SQL.ITEM_CHECK(O_error_message,
                                     L_item_rec.item,
                                     L_item_rec.ref_item,
                                     L_item_rec.dept,
                                     L_item_rec.class,
                                     L_item_rec.subclass,
                                     L_item_rec.pack_ind,
                                     L_item_rec.pack_type,
                                     L_item_rec.simple_pack_ind,   --Catch Weight
                                     L_item_rec.catch_weight_ind,  --Catch Weight
                                     L_item_rec.sellable_ind,  -- Break to sell
                                     L_item_rec.item_xform_ind,  -- Break to sell
                                     I_item) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   -- CatchWeight change
   -- Removed call to convert_weight()
   -- for a simple pack catch weight item, if weight is in the message,
   -- convert it from weight_uom to item's CUOM.
   if L_item_rec.simple_pack_ind = 'Y' and
      L_item_rec.catch_weight_ind = 'Y' and
      I_weight is NOT NULL and
      I_weight_uom is NOT NULL then
      -- receiving at the actual weight presently doesn't work
      L_values.weight     := NULL;
      L_values.weight_uom := I_weight_uom;
   end if;
   -- CatchWeight change end
   if STOCK_ORDER_RCV_SQL.TSF_CHECK(O_error_message,
                                    L_item_rec.tsf_type,
                                    L_item_rec.tsf_status,
                                    L_item_rec.from_loc_type,
                                    L_item_rec.distro_from_loc,
                                    L_item_rec.from_loc_phy,
                                    L_item_rec.from_tsf_entity,
                                    L_item_rec.from_finisher,
                                    L_item_rec.to_loc_type,
                                    L_item_rec.distro_to_loc,
                                    L_item_rec.to_loc_phy,
                                    L_item_rec.to_tsf_entity,
                                    L_item_rec.to_finisher,
                                    L_item_rec.tsf_parent_no,
                                    L_item_rec.mrt_no,
                                    L_item_rec.tsf_no,
                                    I_loc) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if L_item_rec.carton IS NOT NULL then
      if STOCK_ORDER_RCV_SQL.UNWANDED_CARTON(O_error_message,
                                             L_is_unwanded,
                                             L_item_rec.carton) = FALSE
         or L_is_unwanded then
         raise ROLLBACK_TRAN_DATA;
      end if;
      if STOCK_ORDER_RCV_SQL.BOL_CHECK(O_error_message,
                                       L_item_rec.bol_no,
                                       L_item_rec.carton,
                                       L_item_rec.tsf_no) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   if STOCK_ORDER_RCV_SQL.SHIP_CHECK(O_error_message,
                                     L_ship_found,
                                     L_item_rec.ship_no,
                                     L_item_rec.bol_no,
                                     L_item_rec.to_loc_phy,
                                     L_item_rec.from_loc_phy) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if L_ship_found = FALSE then
      if L_item_rec.to_loc_type = 'S' and L_item_rec.carton IS NOT NULL then
         if STOCK_ORDER_RCV_SQL.WALK_THROUGH_STORE (O_error_message,
                                                    L_is_walk_through,
                                                    L_item_rec.ship_no,
                                                    L_intended_store,
                                                    L_item_rec.bol_no,
                                                    L_item_rec.to_loc_phy,
                                                    L_item_rec.carton) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         elsif L_is_walk_through = TRUE then
            L_item_rec.to_loc_phy := L_intended_store;
            L_item_rec.distro_to_loc := L_intended_store;
         elsif LP_system_options_row.wrong_st_receipt_ind = 'Y' then
            if STOCK_ORDER_RCV_SQL.WRONG_STORE_RECEIPT(O_error_message,
                                                       L_item_rec.ship_no,
                                                       L_intended_store,
                                                       L_item_rec.to_loc_phy,
                                                       L_item_rec.to_tsf_entity,
                                                       L_item_rec.distro_from_loc,
                                                       L_item_rec.from_loc_type,
                                                       L_item_rec.from_tsf_entity,
                                                       L_item_rec.from_finisher,
                                                       L_item_rec.item,
                                                       L_item_rec.bol_no,
                                                       L_item_rec.carton,
                                                       L_item_rec.distro_type,
                                                       L_item_rec.tsf_no,
                                                       L_item_rec.dept,
                                                       L_item_rec.class,
                                                       L_item_rec.subclass,
                                                       L_item_rec.pack_ind,
                                                       L_item_rec.pack_type,
                                                       L_item_rec.tran_date,
                                                       L_item_rec.tsf_type) = FALSE then      -- Transfer and Item Valuation
               raise ROLLBACK_TRAN_DATA;
            else
               L_is_wrong_store := TRUE;
               L_item_rec.distro_to_loc := L_item_rec.to_loc_phy;
            end if;
         end if;
      else
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   if STOCK_ORDER_RCV_SQL.UPD_SHIPMENT(O_error_message,
                                       L_item_rec.ship_no,
                                       L_item_rec.tran_date) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   -- All inventory that is received at a finisher location will be received
   -- into the available bucket. This is done because there will always be a
   -- second leg for the transfer, and the received inventory will all be
   -- shipped on the second transfer leg. Likewise, upon shipment from a
   -- finisher inventory will be removed from the available inventory bucket
   -- regardless of the disposition specified in the shipment message.
   if L_item_rec.to_finisher = 'Y' then
      L_inv_status_code := 'ATS';
   else
      L_inv_status_code := I_disp;
   end if;
   ---
   if L_inv_status_code is NULL then
      --- If the disposition (inv_status_code) is NULL then go to shipsku to get inv_status
      if STOCK_ORDER_RCV_SQL.GET_INV_STATUS(O_error_message,
                                            L_item_rec.inv_status,
                                            L_item_rec.ship_no,
                                            L_item_rec.tsf_no,
                                            'T',
                                            L_item_rec.carton,
                                            L_item_rec.item) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   else
      --- If the disposition is NOT NULL call get inv_status from disposition (inv_status_code)
      if INVADJ_SQL.GET_INV_STATUS (O_error_message,
                                    L_item_rec.inv_status,
                                    L_inv_status_code) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   ---
   if L_item_rec.inv_status IS NULL then
      L_item_rec.inv_status := -1;
   end if;
   if STOCK_ORDER_RCV_SQL.TSF_DETAIL_CHECK(O_error_message,
                                           L_item_rec.tsf_seq_no,
                                           L_values.td_exp_qty,
                                           L_values.td_prev_rcpt_qty,
                                           L_from_inv_status,
                                           --------------------
                                           L_item_rec.tsf_no,
                                           L_item_rec.item,
                                           L_item_rec.inv_status,
                                           L_values.input_qty,
                                           L_is_wrong_store) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if STOCK_ORDER_RCV_SQL.CHECK_SS(O_error_message,
                                   L_inv_flow_array,
                                   L_values.from_loc_av_cost,
                                   L_values.ss_prev_rcpt_qty,
                                   L_values.ss_exp_qty,
                                   L_item_rec,
                                   L_item_rec.ship_no,
                                   L_item_rec.tsf_no,
                                   L_item_rec.tsf_type,
                                   L_item_rec.inv_status,
                                   L_item_rec.carton,
                                   L_values.input_qty,
                                   L_values.weight,      -- Catch Weight
                                   L_values.weight_uom,  -- Catch Weight
                                   I_tampered_ind,
                                   L_is_wrong_store,
                                   L_from_inv_status,
                                   L_store_type) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if L_item_rec.mrt_no is not null then
      if STOCK_ORDER_RCV_SQL.MRT_LINE_ITEM(O_error_message,
                                           L_item_rec.mrt_no,
                                           L_item_rec.item,
                                           L_item_rec.distro_from_loc,
                                           L_values.input_qty) = FALSE then
         return FALSE;
      end if;
   end if;
   if STOCK_ORDER_RCV_SQL.APPT_CHECK(O_error_message,
                                     I_appt,
                                     L_item_rec.tsf_no,
                                     'T',
                                     L_item_rec.to_loc_phy,
                                     L_item_rec.item,
                                     L_item_rec.bol_no,
                                     L_item_rec.receipt_no,
                                     L_values.input_qty) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   FOR flow_cnt IN L_inv_flow_array.FIRST..L_inv_flow_array.LAST LOOP
      --------------------------------------------------------------------------
      -- Calculate whether or not to updated the in-transit bucket - and how
      -- much to decremented by.  Each time a shipment is made the in-transit
      -- bucket is incremented by the qty shipped.  When we receive as shipment
      -- we want to decrement the in-transit bucket by the qty received with out
      -- taking more out of the bucket that was actually put into when the shipment
      -- was shipped.  (if 100 were shipped and 110 were received, only decrement
      -- in-transit for the 100 that were originally shipped)
      -- current intran qty = exp qty - prev rcpt qty
      -- new intran qty = exp qty - (prev rcpt qty + new rcpt qty)
      -- UPD_INTRAN_QTY equal the difference between current intran and new intran
      --------------------------------------------------------------------------
      L_current_intran := GREATEST( (L_inv_flow_array(flow_cnt).exp_qty -
                                     L_inv_flow_array(flow_cnt).prev_rcpt_qty), 0);
      L_new_intran := GREATEST( LEAST( (L_inv_flow_array(flow_cnt).exp_qty -
                                          (L_inv_flow_array(flow_cnt).prev_rcpt_qty +
                                           L_inv_flow_array(flow_cnt).dist_qty)),
                                        L_inv_flow_array(flow_cnt).exp_qty), 0);
      L_inv_flow_array(flow_cnt).upd_intran_qty := L_current_intran - L_new_intran;
      --perform the receipt
      if L_wf_ind = 'Y' AND
         L_store_type IN ('W', 'F') then
         if STOCK_ORDER_RCV_SQL.WF_DETAIL_PROCESSING(O_error_message,
                                                     L_item_rec,
                                                     L_values,
                                                     L_inv_flow_array,
                                                     flow_cnt,
                                                     L_item_rec.tsf_no,
                                                     'T',
                                                     L_from_inv_status) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         end if;
      else
         if STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING(O_error_message,
                                                  L_item_rec,
                                                  L_values,
                                                  L_inv_flow_array,
                                                  flow_cnt,
                                                  L_item_rec.tsf_no,
                                                  'T',
                                                  L_from_inv_status) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         end if;
      end if;
   END LOOP;
   return TRUE;
EXCEPTION
   when ROLLBACK_TRAN_DATA then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      return FALSE;
   when OTHERS then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END TSF_LINE_ITEM;
------------------------------------------------------------------------------------------
FUNCTION TSF_BOL_CARTON(O_error_message       IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        I_appt                IN      APPT_HEAD.APPT%TYPE,
                        I_shipment            IN      SHIPMENT.SHIPMENT%TYPE,
                        I_to_loc              IN      SHIPMENT.TO_LOC%TYPE,
                        I_bol_no              IN      SHIPMENT.BOL_NO%TYPE,
                        I_receipt_no          IN      APPT_DETAIL.RECEIPT_NO%TYPE,
                        I_disposition         IN      INV_STATUS_CODES.INV_STATUS_CODE%TYPE,
                        I_tran_date           IN      PERIOD.VDATE%TYPE,
                        I_item_table          IN      ITEM_TAB,
                        I_qty_expected_table  IN      QTY_TAB,
                        I_weight              IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                        I_weight_uom          IN      UOM_CLASS.UOM%TYPE,                 -- Catch Weight
                        I_inv_status_table    IN      INV_STATUS_TAB,
                        I_carton_table        IN      CARTON_TAB,
                        I_distro_no_table     IN      DISTRO_NO_TAB,
                        I_tampered_ind_table  IN      TAMPERED_IND_TAB,
                        I_wrong_store_ind     IN      VARCHAR2,
                        I_wrong_store         IN      SHIPMENT.TO_LOC%TYPE)
RETURN BOOLEAN IS
   L_program             VARCHAR2(61) := 'STOCK_ORDER_RCV_SQL.TSF_BOL_CARTON';
   L_invalid_param       VARCHAR2(30);
   L_invalid_value       VARCHAR2(20) := 'NULL';
   ---
   L_item_rec            STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD;
   L_values              STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD;
   L_inv_flow_array      STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY;
   ---
   L_inv_status_code     INV_STATUS_CODES.INV_STATUS_CODE%TYPE := NULL;
   L_inv_status          INV_STATUS_CODES.INV_STATUS%TYPE := NULL;
   L_current_intran      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_new_intran          ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_is_wrong_store      BOOLEAN := FALSE;
   L_intended_store      ITEM_LOC.LOC%TYPE;
   L_total_qty           SHIPSKU.QTY_EXPECTED%TYPE := 0;  -- Catch Weight
   L_from_inv_status     TSFDETAIL.INV_STATUS%TYPE;
   ROLLBACK_TRAN_DATA    EXCEPTION;
   L_rowid_tsfdet        ROWID := NULL;
   L_count_open_ship     NUMBER(3);
   L_ship_qty            TSFDETAIL.SHIP_QTY%TYPE;
   L_tsf_qty             TSFDETAIL.TSF_QTY%TYPE;
   L_comp_items          STOCK_ORDER_RCV_SQL.COMP_ITEM_ARRAY;
   L_store_type          STORE.STORE_TYPE%TYPE;
   L_wf_ind              SYSTEM_OPTIONS.WHOLESALE_FRANCHISE_IND%TYPE;
   cursor C_TSFDETAIL_LOCK is
      select rowid,NVL(ship_qty,0),NVL(tsf_qty,0)
        from tsfdetail
       where tsf_no = L_item_rec.tsf_no
         and item = L_item_rec.item
         for update nowait;
   cursor C_OPEN_SHIP_COUNT is
      select count(1)
        from shipment sh
       where sh.status_code = 'I'
         and sh.shipment in (select shipment
                               from shipsku
                              where distro_no =L_item_rec.tsf_no);
   cursor C_LOCK_ITEM_LOC_SOH(cv_item  ITEM_LOC_SOH.ITEM%TYPE,
                              cv_loc   ITEM_LOC_SOH.LOC%TYPE) is
      select 'X'
        from item_loc_soh
       where item = cv_item
         and loc = cv_loc
         for update nowait;
   cursor C_GET_STORE_TYPE is
      select store_type
        from store
       where store = I_to_loc;
   cursor C_GET_WF_IND is
      select wholesale_franchise_ind
        from system_options;
BEGIN
   open C_GET_WF_IND;
   SQL_LIB.SET_MARK('FETCH','C_GET_WF_IND', 'SYSTEM_OPTIONS', 'WAREHOUSE_FRANCHISE_IND');
   fetch C_GET_WF_IND into L_wf_ind;
   SQL_LIB.SET_MARK('CLOSE','C_GET_WF_IND', 'SYSTEM_OPTIONS', 'WAREHOUSE_FRANCHISE_IND');
   close C_GET_WF_IND;
   open C_GET_STORE_TYPE;
   SQL_LIB.SET_MARK('FETCH','C_GET_STORE_TYPE', 'STORE', 'STORE: '||I_to_loc);
   fetch C_GET_STORE_TYPE into L_store_type;
   if C_GET_STORE_TYPE%NOTFOUND then
      SQL_LIB.SET_MARK('CLOSE','C_GET_STORE_TYPE', 'STORE', 'STORE: '||I_to_loc);
      close C_GET_STORE_TYPE;
      RETURN FALSE;
   else
      SQL_LIB.SET_MARK('CLOSE','C_GET_STORE_TYPE', 'STORE', 'STORE: '||I_to_loc);
      close C_GET_STORE_TYPE;
   end if;
   --- Check required input
   if I_shipment is NULL then
      L_invalid_param := 'I_shipment';
   elsif I_to_loc is NULL then
      L_invalid_param := 'I_to_loc';
   elsif I_bol_no is NULL then
      L_invalid_param := 'I_bol_no';
   elsif I_tran_date is NULL then
      L_invalid_param := 'I_tran_date';
   elsif I_wrong_store_ind is NULL then
      L_invalid_param := 'I_wrong_store_ind';
   elsif I_item_table is NULL or I_item_table.COUNT = 0 then
      L_invalid_param := 'I_item_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_qty_expected_table is NULL or I_qty_expected_table.COUNT = 0 then
      L_invalid_param := 'I_qty_expected_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_inv_status_table is NULL or I_inv_status_table.COUNT = 0 then
      L_invalid_param := 'I_inv_status_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_carton_table is NULL or I_carton_table.COUNT = 0 then
      L_invalid_param := 'I_carton_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_distro_no_table is NULL or I_distro_no_table.COUNT = 0 then
      L_invalid_param := 'I_distro_no_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_tampered_ind_table is NULL or I_tampered_ind_table.COUNT = 0 then
      L_invalid_param := 'I_tampered_ind_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   end if;
   ---
   if L_invalid_param is NOT NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_PARM_PROG',
                                            L_program,
                                            L_invalid_param,
                                            L_invalid_value);
      return FALSE;
   end if;
   --- Update the shipment received date
   if STOCK_ORDER_RCV_SQL.UPD_SHIPMENT(O_error_message,
                                       I_shipment,
                                       I_tran_date) = FALSE then
      return FALSE;
   end if;
   if STKLEDGR_SQL.SET_SAVEPOINT (O_error_message) = FALSE then
      return FALSE;
   end if;
   for i in I_item_table.FIRST..I_item_table.LAST loop
      --- Clean out the global structures
      L_item_rec    := NULL;
      L_values      := NULL;
      L_inv_flow_array.DELETE;
      L_item_rec.ship_no          := I_shipment;
      L_item_rec.bol_no           := I_bol_no;
      L_item_rec.item             := I_item_table(i);
      L_item_rec.carton           := I_carton_table(i);
      L_item_rec.distro_type      := 'T';
      L_item_rec.tsf_no           := I_distro_no_table(i);
      L_item_rec.tran_date        := I_tran_date;
      L_item_rec.transaction_type := 'R';
      L_item_rec.appt             := I_appt;
      L_item_rec.receipt_no       := I_receipt_no;
      ---
      L_values.input_qty          := I_qty_expected_table(i);
      if STOCK_ORDER_RCV_SQL.ITEM_CHECK(O_error_message,
                                        L_item_rec.item,
                                        L_item_rec.ref_item,
                                        L_item_rec.dept,
                                        L_item_rec.class,
                                        L_item_rec.subclass,
                                        L_item_rec.pack_ind,
                                        L_item_rec.pack_type,
                                        L_item_rec.simple_pack_ind,   --Catch Weight
                                        L_item_rec.catch_weight_ind,  --Catch Weight
                                        L_item_rec.sellable_ind,  -- Break to sell
                                        L_item_rec.item_xform_ind,  -- Break to sell
                                        L_item_rec.item) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   -- CatchWeight change
   -- Removed call to convert_weight()
   -- for a simple pack catch weight item, if weight is in the message,
   -- convert it from weight_uom to item's CUOM.
   if I_item_table.COUNT = 1 and
      L_item_rec.simple_pack_ind = 'Y' and
      L_item_rec.catch_weight_ind = 'Y' and
      I_weight is NOT NULL and
      I_weight_uom is NOT NULL then
      -- receiving at the actual weight presently doesn't work
      L_values.weight     := NULL;
      L_values.weight_uom := NULL;
   end if;
   -- CatchWeight change end
      -- Use the actual to loc (I_wrong_store when populated in case of
      -- wrong store receipt).  This will get the correct entity.
      if STOCK_ORDER_RCV_SQL.TSF_CHECK(O_error_message,
                                       L_item_rec.tsf_type,
                                       L_item_rec.tsf_status,
                                       L_item_rec.from_loc_type,
                                       L_item_rec.distro_from_loc,
                                       L_item_rec.from_loc_phy,
                                       L_item_rec.from_tsf_entity,
                                       L_item_rec.from_finisher,
                                       L_item_rec.to_loc_type,
                                       L_item_rec.distro_to_loc,
                                       L_item_rec.to_loc_phy,
                                       L_item_rec.to_tsf_entity,
                                       L_item_rec.to_finisher,
                                       L_item_rec.tsf_parent_no,
                                       L_item_rec.mrt_no,
                                       --------------------
                                       L_item_rec.tsf_no,
                                       NVL(I_wrong_store, I_to_loc)) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      -- All inventory that is received at a finisher location will be received
      -- into the available bucket. This is done because there will always be a
      -- second leg for the transfer, and the received inventory will all be
      -- shipped on the second transfer leg. Likewise, upon shipment from a
      -- finisher inventory will be removed from the available inventory bucket
      -- regardless of the disposition specified in the shipment message.
      -- We only need to get this for the first record since all items in the
      -- BOL/carton have the same to_loc/to_finisher and I_disposition.
      if i = 1 then
         if L_item_rec.to_finisher = 'Y' then
            L_inv_status_code := 'ATS';
         else
            L_inv_status_code := I_disposition;
         end if;
         ---
         if L_inv_status_code is NOT NULL then
            if INVADJ_SQL.GET_INV_STATUS(O_error_message,
                                         L_inv_status,
                                         L_inv_status_code) = FALSE then
               raise ROLLBACK_TRAN_DATA;
            end if;
            if L_inv_status is NULL then
               L_inv_status := -1;
            end if;
         end if;
      end if;
      --- If there is no inv_status (not being received at a finisher and
      --- I_disposition is NULL), then set inv_status to that on the shipsku table.
      L_item_rec.inv_status := NVL(L_inv_status, I_inv_status_table(i));
      if L_wf_ind = 'N' OR L_store_type NOT IN ('W', 'F') then
         if  I_wrong_store_ind = 'Y'
             and LP_system_options_row.wrong_st_receipt_ind = 'Y' then
             if STOCK_ORDER_RCV_SQL.WRONG_STORE_RECEIPT(O_error_message,
                                                        L_item_rec.ship_no,
                                                        L_intended_store,
                                                        I_wrong_store,
                                                        L_item_rec.to_tsf_entity,
                                                        L_item_rec.distro_from_loc,
                                                        L_item_rec.from_loc_type,
                                                        L_item_rec.from_tsf_entity,
                                                        L_item_rec.from_finisher,
                                                        L_item_rec.item,
                                                        L_item_rec.bol_no,
                                                        L_item_rec.carton,
                                                        L_item_rec.distro_type,
                                                        L_item_rec.tsf_no,
                                                        L_item_rec.dept,
                                                        L_item_rec.class,
                                                        L_item_rec.subclass,
                                                        L_item_rec.pack_ind,
                                                        L_item_rec.pack_type,
                                                        L_item_rec.tran_date,
                                                        L_item_rec.tsf_type) = FALSE then      -- Transfer and Item Valuation
               raise ROLLBACK_TRAN_DATA;
            end if;
            L_is_wrong_store := TRUE;
            L_item_rec.distro_to_loc := I_wrong_store;
         end if;
      end if;
      if STOCK_ORDER_RCV_SQL.TSF_DETAIL_CHECK(O_error_message,
                                              L_item_rec.tsf_seq_no,
                                              L_values.td_exp_qty,
                                              L_values.td_prev_rcpt_qty,
                                              L_from_inv_status,
                                              --------------------
                                              L_item_rec.tsf_no,
                                              L_item_rec.item,
                                              L_item_rec.inv_status,
                                              L_values.input_qty,
                                              L_is_wrong_store) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      if STOCK_ORDER_RCV_SQL.CHECK_SS(O_error_message,
                                      L_inv_flow_array,
                                      L_values.from_loc_av_cost,
                                      L_values.ss_prev_rcpt_qty,
                                      L_values.ss_exp_qty,
                                      L_item_rec,
                                      L_item_rec.ship_no,
                                      L_item_rec.tsf_no,
                                      L_item_rec.tsf_type,
                                      L_item_rec.inv_status,
                                      L_item_rec.carton,
                                      I_qty_expected_table(i),
                                      L_values.weight,          -- Catch Weight
                                      L_values.weight_uom,      -- Catch Weight
                                      I_tampered_ind_table(i),
                                      L_is_wrong_store,
                                      L_from_inv_status,
                                      L_store_type) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      if L_item_rec.mrt_no is not null then
         if STOCK_ORDER_RCV_SQL.MRT_LINE_ITEM(O_error_message,
                                              L_item_rec.mrt_no,
                                              L_item_rec.item,
                                              L_item_rec.distro_from_loc,
                                              L_values.input_qty) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         end if;
      end if;
      if STOCK_ORDER_RCV_SQL.APPT_CHECK(O_error_message,
                                        L_item_rec.appt,
                                        L_item_rec.tsf_no,
                                        L_item_rec.distro_type,
                                        L_item_rec.to_loc_phy,
                                        L_item_rec.item,
                                        L_item_rec.bol_no,
                                        L_item_rec.receipt_no,
                                        I_qty_expected_table(i)) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      --------------------------------------------------------------------------
      -- L_inv_flow_array is populated in CHECK_SS.
      --
      -- Calculate whether or not to updated the in-transit bucket - and how
      -- much to decrement it by.  Each time a shipment is made the in-transit
      -- bucket is incremented by the qty shipped.  When we receive a shipment
      -- we want to decrement the in-transit bucket by the qty received with out
      -- taking more out of the bucket that was actually put into when the shipment
      -- was shipped.  (if 100 were shipped and 110 were received, only decrement
      -- in-transit for the 100 that were originally shipped)
      -- current intran qty = exp qty - prev rcpt qty
      -- new intran qty = exp qty - (prev rcpt qty + new rcpt qty)
      -- UPD_INTRAN_QTY equal the difference between current intran and new intran
      --------------------------------------------------------------------------
      FOR j IN L_inv_flow_array.FIRST..L_inv_flow_array.LAST LOOP
         L_current_intran := GREATEST( (L_inv_flow_array(j).exp_qty -
                                        L_inv_flow_array(j).prev_rcpt_qty), 0);
         L_new_intran := GREATEST( LEAST( (L_inv_flow_array(j).exp_qty -
                                             (L_inv_flow_array(j).prev_rcpt_qty +
                                              L_inv_flow_array(j).dist_qty)),
                                           L_inv_flow_array(j).exp_qty), 0);
         L_inv_flow_array(j).upd_intran_qty := L_current_intran - L_new_intran;
         -- Perform the receipt
         if L_wf_ind = 'Y' AND L_store_type IN ('W', 'F') then
            if STOCK_ORDER_RCV_SQL.WF_DETAIL_PROCESSING(O_error_message,
                                                        L_item_rec,
                                                        L_values,
                                                        L_inv_flow_array,
                                                        j,
                                                        L_item_rec.tsf_no,
                                                        L_item_rec.distro_type,
                                                        L_from_inv_status) = FALSE then
               raise ROLLBACK_TRAN_DATA;
            end if;
         else
            if STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING(O_error_message,
                                                     L_item_rec,
                                                     L_values,
                                                     L_inv_flow_array,
                                                     j,
                                                     L_item_rec.tsf_no,
                                                     L_item_rec.distro_type,
                                                     L_from_inv_status) = FALSE then
               raise ROLLBACK_TRAN_DATA;
            end if;
         end if;
      end loop;
   end loop;
   return TRUE;
EXCEPTION
   when ROLLBACK_TRAN_DATA then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      return FALSE;
   when OTHERS then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END TSF_BOL_CARTON;
-------------------------------------------------------------------------------
FUNCTION ALLOC_LINE_ITEM(O_error_message     IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                         I_loc               IN      ITEM_LOC.LOC%TYPE,
                         I_item              IN      ITEM_MASTER.ITEM%TYPE,
                         I_qty               IN      TRAN_DATA.UNITS%TYPE,
                         I_weight            IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,     -- Catch Weight
                         I_weight_uom        IN      UOM_CLASS.UOM%TYPE,                   -- Catch Weight
                         I_transaction_type  IN      VARCHAR2, --(ADJ FLAG)
                         I_tran_date         IN      PERIOD.VDATE%TYPE,
                         I_receipt_number    IN      APPT_DETAIL.RECEIPT_NO%TYPE,
                         I_bol_no            IN      SHIPMENT.BOL_NO%TYPE,
                         I_appt              IN      APPT_HEAD.APPT%TYPE,
                         I_carton            IN      SHIPSKU.CARTON%TYPE,
                         I_distro_type       IN      VARCHAR2,
                         I_distro_number     IN      ALLOC_HEADER.ALLOC_NO%TYPE,
                         I_disp              IN      INV_STATUS_CODES.INV_STATUS_CODE%TYPE,
                         I_tampered_ind      IN      SHIPSKU.TAMPERED_IND%TYPE,
                         I_dummy_carton_ind  IN      SYSTEM_OPTIONS.DUMMY_CARTON_IND%TYPE,
                         I_function_call_ind IN      VARCHAR2 DEFAULT 'R')
   RETURN BOOLEAN IS
   L_program            VARCHAR2(61) := 'STOCK_ORDER_RCV_SQL.ALLOC_LINE_ITEM';
   L_invalid_param      VARCHAR2(30);
   L_invalid_value      VARCHAR2(30) := 'NULL';
   L_item_rec           STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD;
   L_values             STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD;
   L_inv_flow_array     STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY;
   flow_cnt             BINARY_INTEGER := 1;
   L_current_intran     ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_new_intran         ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_ship_found         BOOLEAN;
   L_is_unwanded        BOOLEAN := FALSE;
   L_is_walk_through    BOOLEAN := FALSE;
   L_is_wrong_store     BOOLEAN := FALSE;
   L_intended_store     ITEM_LOC.LOC%TYPE;
   L_to_loc             ITEM_LOC.LOC%TYPE;
   L_to_loc_type        ITEM_LOC.LOC_TYPE%TYPE;
    -- OLR V1.01 Insert START
   L_shipment_no        SHIPMENT.SHIPMENT%TYPE;
   L_sdc                SMR_SDC.WH%TYPE;
   L_ship_from_loc      SHIPMENT.FROM_LOC%TYPE;
   L_alloc_wh           ALLOC_HEADER.WH%TYPE;
    -- OLR V1.01 Insert END
   ---
   ROLLBACK_TRAN_DATA   EXCEPTION;
   cursor C_LOC_ALLOC is
      select to_loc,
             to_loc_type
        from alloc_detail
       where alloc_no = I_distro_number
         and rownum   = 1;
   -- OLR V1.01 Insert START
   cursor C_IS_9401_ORDER(I_alloc_no number) is
   select ah.wh
     from alloc_header ah
    where ah.alloc_no = I_alloc_no;
   cursor C_9401_SHIPMENT(I_s_bol_no varchar2, I_s_phy_to_loc number, I_s_distro_no number) is
      select s.shipment, s.from_loc
        from shipment s,
             shipsku ss
       where s.shipment = ss.shipment
         and ss.distro_no = I_s_distro_no
         and s.bol_no = I_s_bol_no
         and s.to_loc = I_s_phy_to_loc;
   cursor C_IS_SDC(I_from_loc number) is
      select wh
        from smr_sdc
       where wh = I_from_loc;
   -- OLR V1.01 Insert END
BEGIN
   if I_loc is NULL then
      L_invalid_param := 'I_loc';
   elsif I_item is NULL then
      L_invalid_param := 'I_item';
   elsif I_qty is NULL then
      L_invalid_param := 'I_qty';
   elsif I_transaction_type is NULL then
      L_invalid_param := 'I_transaction_type';
   elsif I_tran_date is NULL then
      L_invalid_param := 'I_tran_date';
   elsif I_bol_no is NULL then
      L_invalid_param := 'I_bol_no';
   elsif I_distro_type is NULL then
      L_invalid_param := 'I_distro_type';
   -- distro_number is not required for items in dummy cartons
   elsif I_distro_number is NULL
      and NVL(I_dummy_carton_ind,'N') != 'Y'
      and (NVL(I_tampered_ind, 'N') != 'Y'
           or LP_system_options_row.store_pack_comp_rcv_ind != 'Y') then
      L_invalid_param := 'I_distro_number';
   elsif I_distro_type != 'A' then
      L_invalid_param := 'I_distro_type';
      L_invalid_value := I_distro_type;
   elsif I_transaction_type NOT IN ('R','A','T') then
      L_invalid_param := 'I_transaction_type';
      L_invalid_value := I_transaction_type;
   end if;
   ---
   if L_invalid_param is NOT NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_PARM_PROG',
                                            L_program,
                                            L_invalid_param,
                                            L_invalid_value);
      return FALSE;
   end if;
   if STKLEDGR_SQL.SET_SAVEPOINT (O_error_message) = FALSE then
      return FALSE;
   end if;
   if  LP_system_options_row.dummy_carton_ind = 'Y'
   and NVL(I_dummy_carton_ind,'N') = 'Y'
   and NVL(I_function_call_ind, 'R') = 'R' then
      insert into dummy_carton_stage(distro_no,
                                     distro_type,
                                     item,
                                     to_loc,
                                     carton,
                                     bol_no,
                                     qty,
                                     tran_type,
                                     tran_date,
                                     receipt_no,
                                     appt_no,
                                     disposition_code,
                                     tampered_ind,
                                     dummy_carton_ind,
                                     last_update_datetime)
                              values(I_distro_number,
                                     I_distro_type,
                                     I_item,
                                     I_loc,
                                     I_carton,
                                     I_bol_no,
                                     I_qty,
                                     I_transaction_type,
                                     I_tran_date,
                                     I_receipt_number,
                                     I_appt,
                                     I_disp,
                                     I_tampered_ind,
                                     I_dummy_carton_ind,
                                     SYSDATE);
      return TRUE;
   end if;
   open C_LOC_ALLOC;
   fetch C_LOC_ALLOC into L_to_loc,
                          L_to_loc_type;
   close C_LOC_ALLOC;
   if L_to_loc_type = 'W' then
      L_item_rec.distro_to_loc    := L_to_loc;
      L_item_rec.to_loc_type      := L_to_loc_type;
   else
      L_item_rec.distro_to_loc    := I_loc;
      L_item_rec.to_loc_type      := 'S';
   end if;
   L_item_rec.carton           := I_carton;
   L_item_rec.tran_date        := I_tran_date;
   L_item_rec.distro_type      := I_distro_type;
   L_item_rec.alloc_no         := I_distro_number;
   L_item_rec.appt             := I_appt;
   L_item_rec.receipt_no       := I_receipt_number;
   L_item_rec.bol_no           := I_bol_no;
   L_item_rec.transaction_type := REPLACE(I_transaction_type,'T','R'); --transshipment is equivalent to receipt
   L_item_rec.to_loc_phy       := I_loc;
   L_values.input_qty          := I_qty;
   if STOCK_ORDER_RCV_SQL.ITEM_CHECK(O_error_message,
                                     L_item_rec.item,
                                     L_item_rec.ref_item,
                                     L_item_rec.dept,
                                     L_item_rec.class,
                                     L_item_rec.subclass,
                                     L_item_rec.pack_ind,
                                     L_item_rec.pack_type,
                                     L_item_rec.simple_pack_ind,   --Catch Weight
                                     L_item_rec.catch_weight_ind,  --Catch Weight
                                     L_item_rec.sellable_ind,  -- Break to sell
                                     L_item_rec.item_xform_ind,  -- Break to sell
                                     I_item) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   -- CatchWeight change
   -- Removed call to convert_weight()
   -- for a simple pack catch weight item, if weight is in the message,
   -- convert it from weight_uom to item's CUOM.
   if L_item_rec.simple_pack_ind = 'Y' and
      L_item_rec.catch_weight_ind = 'Y' and
      I_weight is NOT NULL and
      I_weight_uom is NOT NULL then
      -- receiving at the actual weight presently doesn't work
      L_values.weight     := NULL;
      L_values.weight_uom := NULL;
   end if;
   -- CatchWeight change end
   if (NOT(NVL(I_tampered_ind, 'N') = 'Y' and
           LP_system_options_row.store_pack_comp_rcv_ind = 'Y' and
           I_function_call_ind = 'R')) then
      if STOCK_ORDER_RCV_SQL.ALLOC_CHECK(O_error_message,
                                         L_item_rec.alloc_status,
                                         L_item_rec.from_loc_type,
                                         L_item_rec.distro_from_loc,
                                         L_item_rec.from_loc_phy,
                                         L_item_rec.from_tsf_entity,
                                         L_item_rec.to_tsf_entity,
                                         L_item_rec.alloc_no,
                                         L_item_rec.item,
                                         L_item_rec.distro_to_loc,
                                         L_item_rec.to_loc_type) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   if L_item_rec.carton IS NOT NULL then
      if STOCK_ORDER_RCV_SQL.UNWANDED_CARTON(O_error_message,
                                             L_is_unwanded,
                                             L_item_rec.carton) = FALSE
         or L_is_unwanded then
         raise ROLLBACK_TRAN_DATA;
      end if;
      if LP_system_options_row.store_pack_comp_rcv_ind = 'Y'
         and NVL(I_function_call_ind, 'R') = 'R'
         and NVL(I_tampered_ind, 'N') = 'Y' then
         SQL_LIB.SET_MARK('INSERT',
                          NULL,
                          'DUMMY_CARTON_STAGE',
                          'Distro_number: ' || (I_distro_number)   ||
                          ', Distro_type: ' || to_char(I_distro_type));
         insert into dummy_carton_stage(distro_no,
                                        distro_type,
                                        item,
                                        to_loc,
                                        carton,
                                        bol_no,
                                        qty,
                                        tran_type,
                                        tran_date,
                                        receipt_no,
                                        appt_no,
                                        disposition_code,
                                        tampered_ind,
                                        dummy_carton_ind,
                                        last_update_datetime)
                                 values(I_distro_number,
                                        I_distro_type,
                                        I_item,
                                        I_loc,
                                        I_carton,
                                        I_bol_no,
                                        I_qty,
                                        I_transaction_type,
                                        I_tran_date,
                                        I_receipt_number,
                                        I_appt,
                                        I_disp,
                                        I_tampered_ind,
                                        I_dummy_carton_ind,
                                        SYSDATE);
         return TRUE;
      end if;
      if STOCK_ORDER_RCV_SQL.BOL_CHECK(O_error_message,
                                       L_item_rec.bol_no,
                                       L_item_rec.carton,
                                       L_item_rec.alloc_no) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   -- OLR V1.01 Insert START
   L_alloc_wh := NULL;
   OPEN C_IS_9401_ORDER(L_item_rec.alloc_no);
   FETCH C_IS_9401_ORDER into L_alloc_wh;
   CLOSE C_IS_9401_ORDER;
   if L_alloc_wh = 9401 and L_to_loc_type = 'S' then
      OPEN C_9401_SHIPMENT(L_item_rec.bol_no, L_item_rec.to_loc_phy, L_item_rec.alloc_no);
      FETCH C_9401_SHIPMENT into L_shipment_no, L_ship_from_loc;
      CLOSE C_9401_SHIPMENT;
      L_sdc := NULL;
      OPEN C_IS_SDC(L_ship_from_loc);
      FETCH C_IS_SDC INTO L_sdc;
      CLOSE C_IS_SDC;
      if L_sdc is not NULL then
         L_item_rec.from_loc_phy := L_ship_from_loc;
         L_item_rec.ship_no := L_shipment_no;
      end if;
   end if;
   -- OLR V1.01 Insert END
   if STOCK_ORDER_RCV_SQL.SHIP_CHECK(O_error_message,
                                     L_ship_found,
                                     L_item_rec.ship_no,
                                     L_item_rec.bol_no,
                                     L_item_rec.to_loc_phy,
                                     L_item_rec.from_loc_phy) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if L_ship_found = FALSE and L_to_loc_type = 'S' then
      if L_item_rec.carton IS NOT NULL then
         if STOCK_ORDER_RCV_SQL.WALK_THROUGH_STORE (O_error_message,
                                                    L_is_walk_through,
                                                    L_item_rec.ship_no,
                                                    L_intended_store,
                                                    L_item_rec.bol_no,
                                                    L_item_rec.to_loc_phy,
                                                    L_item_rec.carton) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         elsif L_is_walk_through = TRUE then
            L_item_rec.to_loc_phy := L_intended_store;
            L_item_rec.distro_to_loc := L_intended_store;
         elsif LP_system_options_row.wrong_st_receipt_ind = 'Y' then
            if STOCK_ORDER_RCV_SQL.WRONG_STORE_RECEIPT(O_error_message,
                                                       L_item_rec.ship_no,
                                                       L_intended_store,
                                                       L_item_rec.to_loc_phy,
                                                       L_item_rec.to_tsf_entity,
                                                       L_item_rec.distro_from_loc,
                                                       L_item_rec.from_loc_type,
                                                       L_item_rec.from_tsf_entity,
                                                       L_item_rec.from_finisher,  --default N
                                                       L_item_rec.item,
                                                       L_item_rec.bol_no,
                                                       L_item_rec.carton,
                                                       L_item_rec.distro_type,
                                                       L_item_rec.alloc_no,
                                                       L_item_rec.dept,
                                                       L_item_rec.class,
                                                       L_item_rec.subclass,
                                                       L_item_rec.pack_ind,
                                                       L_item_rec.pack_type,
                                                       L_item_rec.tran_date,
                                                       L_item_rec.tsf_type) = FALSE then      -- Transfer and Item Valuation
               raise ROLLBACK_TRAN_DATA;
            else
               L_is_wrong_store := TRUE;
               L_item_rec.distro_to_loc := L_item_rec.to_loc_phy;
            end if;
         end if;
      else
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   if STOCK_ORDER_RCV_SQL.UPD_SHIPMENT(O_error_message,
                                       L_item_rec.ship_no,
                                       L_item_rec.tran_date) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if I_disp is NULL then
      --- If the disposition is NULL then go to shipsku to get inv_status
      if STOCK_ORDER_RCV_SQL.GET_INV_STATUS(O_error_message,
                                            L_item_rec.inv_status,
                                            L_item_rec.ship_no,
                                            L_item_rec.alloc_no,
                                            'A',
                                            L_item_rec.carton,
                                            L_item_rec.item) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   else
      --- If the disposition is NOT NULL call get inv_status from disposition
      if INVADJ_SQL.GET_INV_STATUS(O_error_message,
                                   L_item_rec.inv_status,
                                   I_disp) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   ---
   if L_item_rec.inv_status IS NULL then
      L_item_rec.inv_status := -1;
   end if;
   if L_is_walk_through = TRUE or L_is_wrong_store = TRUE then
      if STOCK_ORDER_RCV_SQL.ALLOC_DETAIL_CHECK(O_error_message,
                                                L_values.ad_exp_qty,
                                                L_values.ad_prev_rcpt_qty,
                                                L_item_rec.alloc_no,
                                                L_intended_store,
                                                L_values.input_qty,
                                                L_is_wrong_store) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   else
      if STOCK_ORDER_RCV_SQL.ALLOC_DETAIL_CHECK(O_error_message,
                                                L_values.ad_exp_qty,
                                                L_values.ad_prev_rcpt_qty,
                                                L_item_rec.alloc_no,
                                                L_item_rec.distro_to_loc,
                                                L_values.input_qty,
                                                L_is_wrong_store) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   end if;
   if STOCK_ORDER_RCV_SQL.CHECK_SS(O_error_message,
                                   L_inv_flow_array,
                                   L_values.from_loc_av_cost,
                                   L_values.ss_prev_rcpt_qty,
                                   L_values.ss_exp_qty,
                                   L_item_rec,
                                   L_item_rec.ship_no,
                                   L_item_rec.alloc_no,
                                   'A',
                                   L_item_rec.inv_status,
                                   L_item_rec.carton,
                                   L_values.input_qty,
                                   L_values.weight,      -- Catch Weight
                                   L_values.weight_uom,  -- Catch Weight
                                   I_tampered_ind,
                                   L_is_wrong_store,
                                   NULL) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   if STOCK_ORDER_RCV_SQL.APPT_CHECK(O_error_message,
                                     I_appt,
                                     L_item_rec.alloc_no,
                                     'A',
                                     L_item_rec.to_loc_phy,
                                     L_item_rec.item,
                                     L_item_rec.bol_no,
                                     L_item_rec.receipt_no,
                                     L_values.input_qty) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   -- Allocations only will ever have one flow.
   flow_cnt := 1;
   -- Set qty to use for in-transit update (see comment in TSF_LINE_ITEM)
   L_current_intran := GREATEST( (L_inv_flow_array(flow_cnt).exp_qty -
                                  L_inv_flow_array(flow_cnt).prev_rcpt_qty), 0);
   L_new_intran := GREATEST( LEAST( (L_inv_flow_array(flow_cnt).exp_qty -
                                       (L_inv_flow_array(flow_cnt).prev_rcpt_qty +
                                        L_inv_flow_array(flow_cnt).dist_qty)),
                                     L_inv_flow_array(flow_cnt).exp_qty) , 0);
   L_inv_flow_array(flow_cnt).upd_intran_qty := L_current_intran - L_new_intran;
   if STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING(O_error_message,
                                            L_item_rec,
                                            L_values,
                                            L_inv_flow_array,
                                            flow_cnt,
                                            L_item_rec.alloc_no,
                                            'A',
                                            NULL) = FALSE then
      raise ROLLBACK_TRAN_DATA;
   end if;
   return TRUE;
EXCEPTION
   when ROLLBACK_TRAN_DATA then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      return FALSE;
   when OTHERS then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END ALLOC_LINE_ITEM;
-------------------------------------------------------------------------------
FUNCTION ALLOC_BOL_CARTON(O_error_message       IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          I_appt                IN      APPT_HEAD.APPT%TYPE,
                          I_shipment            IN      SHIPMENT.SHIPMENT%TYPE,
                          I_to_loc              IN      SHIPMENT.TO_LOC%TYPE,
                          I_bol_no              IN      SHIPMENT.BOL_NO%TYPE,
                          I_receipt_no          IN      APPT_DETAIL.RECEIPT_NO%TYPE,
                          I_disposition         IN      INV_STATUS_CODES.INV_STATUS_CODE%TYPE,
                          I_tran_date           IN      PERIOD.VDATE%TYPE,
                          I_item_table          IN      ITEM_TAB,
                          I_qty_expected_table  IN      QTY_TAB,
                          I_weight              IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                          I_weight_uom          IN      UOM_CLASS.UOM%TYPE,                -- Catch Weight
                          I_inv_status_table    IN      INV_STATUS_TAB,
                          I_carton_table        IN      CARTON_TAB,
                          I_distro_no_table     IN      DISTRO_NO_TAB,
                          I_tampered_ind_table  IN      TAMPERED_IND_TAB,
                          I_wrong_store_ind     IN      VARCHAR2,
                          I_wrong_store         IN      SHIPMENT.TO_LOC%TYPE)
RETURN BOOLEAN IS
   L_program             VARCHAR2(61) := 'STOCK_ORDER_RCV_SQL.ALLOC_BOL_CARTON';
   L_invalid_param       VARCHAR2(30);
   L_invalid_value       VARCHAR2(20) := 'NULL';
   ---
   L_item_rec            STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD;
   L_values              STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD;
   L_inv_flow_array      STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY;
   ---
   L_inv_status_code     INV_STATUS_CODES.INV_STATUS_CODE%TYPE := NULL;
   L_inv_status          INV_STATUS_CODES.INV_STATUS%TYPE := NULL;
   L_current_intran      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_new_intran          ITEM_LOC_SOH.STOCK_ON_HAND%TYPE := 0;
   L_is_wrong_store      BOOLEAN := FALSE;
   L_intended_store      ITEM_LOC.LOC%TYPE;
   L_total_qty           shipsku.qty_expected%TYPE := 0;     -- Catch Weight
   L_unit_weight_cuom    ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;   -- Catch Weight
   L_to_loc              ITEM_LOC.LOC%TYPE;
   L_to_loc_type         ITEM_LOC.LOC_TYPE%TYPE;
   L_alloc_no            ALLOC_HEADER.ALLOC_NO%TYPE;
   ---
   ROLLBACK_TRAN_DATA    EXCEPTION;
-- Rownum = 1 as there will be either 'S' or only 'W' per allocation.
   cursor C_LOC_ALLOC is
      select to_loc,
             to_loc_type
        from alloc_detail
       where alloc_no = L_alloc_no
         and rownum   = 1;
BEGIN
   --- Check required input
   if I_shipment is NULL then
      L_invalid_param := 'I_shipment';
   elsif I_to_loc is NULL then
      L_invalid_param := 'I_to_loc';
   elsif I_bol_no is NULL then
      L_invalid_param := 'I_bol_no';
   elsif I_tran_date is NULL then
      L_invalid_param := 'I_tran_date';
   elsif I_wrong_store_ind is NULL then
      L_invalid_param := 'I_wrong_store_ind';
   elsif I_item_table is NULL or I_item_table.COUNT = 0 then
      L_invalid_param := 'I_item_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_qty_expected_table is NULL or I_qty_expected_table.COUNT = 0 then
      L_invalid_param := 'I_qty_expected_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_inv_status_table is NULL or I_inv_status_table.COUNT = 0 then
      L_invalid_param := 'I_inv_status_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_carton_table is NULL or I_carton_table.COUNT = 0 then
      L_invalid_param := 'I_carton_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_distro_no_table is NULL or I_distro_no_table.COUNT = 0 then
      L_invalid_param := 'I_distro_no_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   elsif I_tampered_ind_table is NULL or I_tampered_ind_table.COUNT = 0 then
      L_invalid_param := 'I_tampered_ind_table';
      L_invalid_value := 'NULL or ZERO COUNT';
   end if;
   ---
   if L_invalid_param is NOT NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_PARM_PROG',
                                            L_program,
                                            L_invalid_param,
                                            L_invalid_value);
      return FALSE;
   end if;
   if I_disposition is NOT NULL then
      if INVADJ_SQL.GET_INV_STATUS(O_error_message,
                                   L_inv_status,
                                   I_disposition) = FALSE then
         return FALSE;
      end if;
      if L_inv_status is NULL then
         L_inv_status := -1;
      end if;
   end if;
   --- Update the shipment received date
   if STOCK_ORDER_RCV_SQL.UPD_SHIPMENT(O_error_message,
                                       I_shipment,
                                       I_tran_date) = FALSE then
      return FALSE;
   end if;
   if STKLEDGR_SQL.SET_SAVEPOINT (O_error_message) = FALSE then
      return FALSE;
   end if;
   for i in I_item_table.FIRST..I_item_table.LAST loop
      --- Clean out the global structures
      L_item_rec    := NULL;
      L_values      := NULL;
      L_inv_flow_array.DELETE;
      L_item_rec.ship_no          := I_shipment;
      L_item_rec.bol_no           := I_bol_no;
      L_item_rec.to_loc_phy       := I_to_loc;
      L_item_rec.item             := I_item_table(i);
      L_item_rec.carton           := I_carton_table(i);
      L_item_rec.distro_type      := 'A';
      L_item_rec.alloc_no         := I_distro_no_table(i);
      L_alloc_no                  := I_distro_no_table(i);
      L_item_rec.tran_date        := I_tran_date;
      L_item_rec.transaction_type := 'R';
      L_item_rec.appt             := I_appt;
      L_item_rec.receipt_no       := I_receipt_no;
      L_item_rec.inv_status       := NVL(L_inv_status, I_inv_status_table(i));
      ---
      L_values.input_qty          := I_qty_expected_table(i);
      open C_LOC_ALLOC;
      fetch C_LOC_ALLOC into L_to_loc,
                             L_to_loc_type;
      close C_LOC_ALLOC;
      if L_to_loc_type = 'W' then
         L_item_rec.distro_to_loc    := L_to_loc;
         L_item_rec.to_loc_type      := L_to_loc_type;
      else
         L_item_rec.distro_to_loc    := I_to_loc;
         L_item_rec.to_loc_type      := 'S';
      end if;
      if STOCK_ORDER_RCV_SQL.ITEM_CHECK(O_error_message,
                                        L_item_rec.item,
                                        L_item_rec.ref_item,
                                        L_item_rec.dept,
                                        L_item_rec.class,
                                        L_item_rec.subclass,
                                        L_item_rec.pack_ind,
                                        L_item_rec.pack_type,
                                        L_item_rec.simple_pack_ind,  --Catch Weight
                                        L_item_rec.catch_weight_ind, --Catch Weight
                                        L_item_rec.sellable_ind,  -- Break to sell
                                        L_item_rec.item_xform_ind,  -- Break to sell
                                        L_item_rec.item) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   -- CatchWeight change
   -- Removed call to convert_weight()
   -- for a simple pack catch weight item, if weight is in the message,
   -- convert it from weight_uom to item's CUOM.
   if L_item_rec.simple_pack_ind = 'Y' and
      L_item_rec.catch_weight_ind = 'Y' and
      I_weight is NOT NULL and
      I_weight_uom is NOT NULL then
      -- receiving at the actual weight presently doesn't work
      L_values.weight     := NULL;
      L_values.weight_uom := NULL;
   end if;
   -- CatchWeight change end
      if STOCK_ORDER_RCV_SQL.ALLOC_CHECK(O_error_message,
                                         L_item_rec.alloc_status,
                                         L_item_rec.from_loc_type,
                                         L_item_rec.distro_from_loc,
                                         L_item_rec.from_loc_phy,
                                         L_item_rec.from_tsf_entity,
                                         L_item_rec.to_tsf_entity,
                                         ---
                                         I_distro_no_table(i),
                                         L_item_rec.item,
                                         NVL(I_wrong_store, L_item_rec.distro_to_loc),
                                         L_item_rec.to_loc_type) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      if  I_wrong_store_ind = 'Y'
      and LP_system_options_row.wrong_st_receipt_ind = 'Y' then
         if STOCK_ORDER_RCV_SQL.WRONG_STORE_RECEIPT(O_error_message,
                                                    L_item_rec.ship_no,
                                                    L_intended_store,
                                                    I_wrong_store,
                                                    L_item_rec.to_tsf_entity,
                                                    L_item_rec.distro_from_loc,
                                                    L_item_rec.from_loc_type,
                                                    L_item_rec.from_tsf_entity,
                                                    L_item_rec.from_finisher,
                                                    L_item_rec.item,
                                                    L_item_rec.bol_no,
                                                    L_item_rec.carton,
                                                    L_item_rec.distro_type,
                                                    L_item_rec.alloc_no,
                                                    L_item_rec.dept,
                                                    L_item_rec.class,
                                                    L_item_rec.subclass,
                                                    L_item_rec.pack_ind,
                                                    L_item_rec.pack_type,
                                                    L_item_rec.tran_date,
                                                    L_item_rec.tsf_type) = FALSE then      -- Transfer and Item Valuation
            raise ROLLBACK_TRAN_DATA;
         end if;
         L_is_wrong_store := TRUE;
         L_item_rec.distro_to_loc := I_wrong_store;
      end if;
      if L_is_wrong_store then
         if STOCK_ORDER_RCV_SQL.ALLOC_DETAIL_CHECK(O_error_message,
                                                   L_values.ad_exp_qty,
                                                   L_values.ad_prev_rcpt_qty,
                                                   L_item_rec.alloc_no,
                                                   L_intended_store,
                                                   I_qty_expected_table(i),
                                                   L_is_wrong_store) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         end if;
      else
         if STOCK_ORDER_RCV_SQL.ALLOC_DETAIL_CHECK(O_error_message,
                                                   L_values.ad_exp_qty,
                                                   L_values.ad_prev_rcpt_qty,
                                                   L_item_rec.alloc_no,
                                                   L_item_rec.distro_to_loc,
                                                   I_qty_expected_table(i),
                                                   L_is_wrong_store) = FALSE then
            raise ROLLBACK_TRAN_DATA;
         end if;
      end if;
      if STOCK_ORDER_RCV_SQL.CHECK_SS(O_error_message,
                                      L_inv_flow_array,
                                      L_values.from_loc_av_cost,
                                      L_values.ss_prev_rcpt_qty,
                                      L_values.ss_exp_qty,
                                      L_item_rec,
                                      L_item_rec.ship_no,
                                      L_item_rec.alloc_no,
                                      NULL,
                                      L_item_rec.inv_status,
                                      L_item_rec.carton,
                                      I_qty_expected_table(i),
                                      L_values.weight,         -- Catch Weight
                                      L_values.weight_uom,     -- Catch Weight
                                      I_tampered_ind_table(i),
                                      L_is_wrong_store,
                                      NULL) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      if STOCK_ORDER_RCV_SQL.APPT_CHECK(O_error_message,
                                        L_item_rec.appt,
                                        L_item_rec.alloc_no,
                                        L_item_rec.distro_type,
                                        L_item_rec.to_loc_phy,
                                        L_item_rec.item,
                                        L_item_rec.bol_no,
                                        L_item_rec.receipt_no,
                                        I_qty_expected_table(i)) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
      --------------------------------------------------------------------------
      -- L_inv_flow_array is populated in CHECK_SS.
      --
      -- Calculate whether or not to updated the in-transit bucket - and how
      -- much to decrement it by.  Each time a shipment is made the in-transit
      -- bucket is incremented by the qty shipped.  When we receive a shipment
      -- we want to decrement the in-transit bucket by the qty received with out
      -- taking more out of the bucket that was actually put into when the shipment
      -- was shipped.  (if 100 were shipped and 110 were received, only decrement
      -- in-transit for the 100 that were originally shipped)
      -- current intran qty = exp qty - prev rcpt qty
      -- new intran qty = exp qty - (prev rcpt qty + new rcpt qty)
      -- UPD_INTRAN_QTY equal the difference between current intran and new intran
      -- Allocations only will ever have one flow, hence index of (1).
      --------------------------------------------------------------------------
      L_current_intran := GREATEST( (L_inv_flow_array(1).exp_qty -
                                     L_inv_flow_array(1).prev_rcpt_qty), 0);
      L_new_intran := GREATEST( LEAST( (L_inv_flow_array(1).exp_qty -
                                          (L_inv_flow_array(1).prev_rcpt_qty +
                                           L_inv_flow_array(1).dist_qty)),
                                        L_inv_flow_array(1).exp_qty) , 0);
      L_inv_flow_array(1).upd_intran_qty := L_current_intran - L_new_intran;
      if STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING(O_error_message,
                                               L_item_rec,
                                               L_values,
                                               L_inv_flow_array,
                                               1,
                                               L_item_rec.alloc_no,
                                               'A',
                                               NULL) = FALSE then
         raise ROLLBACK_TRAN_DATA;
      end if;
   END LOOP;
   return TRUE;
EXCEPTION
   when ROLLBACK_TRAN_DATA then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      return FALSE;
   when OTHERS then
      if STKLEDGR_SQL.ROLLBACK_TO_SAVEPOINT (O_error_message) = FALSE then
         return FALSE;
      end if;
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END ALLOC_BOL_CARTON;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--- Private functions
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
FUNCTION ITEM_CHECK(O_error_message    IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                    O_item             IN OUT ITEM_MASTER.ITEM%TYPE,
                    O_ref_item         IN OUT ITEM_MASTER.ITEM%TYPE,
                    O_dept             IN OUT ITEM_MASTER.DEPT%TYPE,
                    O_class            IN OUT ITEM_MASTER.CLASS%TYPE,
                    O_subclass         IN OUT ITEM_MASTER.SUBCLASS%TYPE,
                    O_pack_ind         IN OUT ITEM_MASTER.PACK_IND%TYPE,
                    O_pack_type        IN OUT ITEM_MASTER.PACK_TYPE%TYPE,
                    O_simple_pack_ind  IN OUT  ITEM_MASTER.SIMPLE_PACK_IND%TYPE,  --Catch Weight
                    O_catch_weight_ind IN OUT  ITEM_MASTER.CATCH_WEIGHT_IND%TYPE, --Catch Weight
                    O_sellable_ind     IN OUT  ITEM_MASTER.SELLABLE_IND%TYPE,
                    O_item_xform_ind   IN OUT  ITEM_MASTER.ITEM_XFORM_IND%TYPE,
                    I_item             IN     ITEM_MASTER.ITEM%TYPE)
   RETURN BOOLEAN IS
   L_item ITEM_MASTER.ITEM%TYPE;   -- CatchWeight
   L_orderable_ind      ITEM_MASTER.ORDERABLE_IND%TYPE;
   L_inventory_ind      ITEM_MASTER.INVENTORY_IND%TYPE;
  -- cursors
   cursor C_ITEM_EXIST is
      select im1.item,
             im1.dept,
             im1.class,
             im1.subclass,
             im1.pack_ind,
             NVL(im1.pack_type, 'N'),
             im1.simple_pack_ind,     -- Catch Weight
             im1.catch_weight_ind,    -- Catch Weight
             im1.sellable_ind,
             im1.orderable_ind,
             im1.inventory_ind,
             im1.item_xform_ind
        from item_master im1,
             item_master im2
       where (im2.item       = I_item and
              im2.item_level = im2.tran_level and
              im1.item       = im2.item)
              -- if item is below the tran level,
              -- get its tran level parent
          or (im2.item       = I_item and
              im2.item_level = im2.tran_level + 1 and
              im1.item      = im2.item_parent);
BEGIN
   open C_ITEM_EXIST;
   fetch C_ITEM_EXIST into O_item,
                           O_dept,
                           O_class,
                           O_subclass,
                           O_pack_ind,
                           O_pack_type,
                           O_simple_pack_ind,  --Catch Weight
                           O_catch_weight_ind, --Catch Weight
                           O_sellable_ind,
                           L_orderable_ind,
                           L_inventory_ind,
                           O_item_xform_ind;
    close C_ITEM_EXIST;
   if O_item is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_ITEM', NULL, NULL, NULL);
      return FALSE;
   end if;
   if L_orderable_ind = 'Y' and
      O_sellable_ind  = 'N' and
      L_inventory_ind = 'N' then
      O_error_message := SQL_LIB.CREATE_MSG('NO_NONINVENT_ITEM', NULL, NULL, NULL);
      return FALSE;
   end if;
   if O_item != I_item then
      O_ref_item := I_item;
   else
      O_ref_item := NULL;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.ITEM_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END ITEM_CHECK;
-------------------------------------------------------------------------------
FUNCTION SHIP_CHECK(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                    O_ship_found     IN OUT  BOOLEAN,
                    O_shipment       IN OUT  SHIPMENT.SHIPMENT%TYPE,
                    I_bol_no         IN      SHIPMENT.BOL_NO%TYPE,
                    I_phy_to_loc     IN      ITEM_LOC.LOC%TYPE,
                    I_phy_from_loc   IN      ITEM_LOC.LOC%TYPE)
   RETURN BOOLEAN IS
   cursor C_SHIP_EXIST is
      select s.shipment
        from shipment s
       where s.bol_no   = I_bol_no
         and s.to_loc   = I_phy_to_loc
         and s.from_loc = I_phy_from_loc;
BEGIN
   -- if this is not the first call, use the cached values
   if (LP_cache_header_info.ship_check_bol_no = I_bol_no AND
       LP_cache_header_info.ship_check_to_loc_phy = I_phy_to_loc AND
       LP_cache_header_info.ship_check_from_loc_phy = I_phy_from_loc) then
      O_shipment   := LP_cache_header_info.ship_check_shipment;
      O_ship_found := TRUE;
      return TRUE;
   end if;
   O_shipment := NULL;
   open C_SHIP_EXIST;
   fetch C_SHIP_EXIST into O_shipment;
   close C_SHIP_EXIST;
   if O_shipment IS NULL then
      O_error_message := SQL_LIB.CREATE_MSG('BOL_NO_SHIP', to_char(I_bol_no),
                                            to_char(I_phy_to_loc), to_char(I_phy_from_loc));
      O_ship_found := FALSE;
      return TRUE;
   end if;
   O_ship_found := TRUE;
   -- this is the first time for this bol/to_loc/from_loc, populated the cache for next call
   LP_cache_header_info.ship_check_bol_no  := I_bol_no;
   LP_cache_header_info.ship_check_to_loc_phy := I_phy_to_loc;
   LP_cache_header_info.ship_check_from_loc_phy := I_phy_from_loc;
   LP_cache_header_info.ship_check_shipment := O_shipment;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.SHIP_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END SHIP_CHECK;
-------------------------------------------------------------------------------
FUNCTION CHECK_SS(O_error_message           IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                  O_inv_flow_array          IN OUT  STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                  O_ss_unit_cost            IN OUT  ITEM_LOC_SOH.AV_COST%TYPE,
                  O_ss_prev_rcpt_qty        IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                  O_ss_exp_qty              IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                  O_item_rec                IN OUT  STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                  I_shipment                IN      SHIPMENT.SHIPMENT%TYPE,
                  I_distro_no               IN      SHIPSKU.DISTRO_NO%TYPE,
                  I_external_ind            IN      TSFHEAD.TSF_TYPE%TYPE,
                  I_inv_status              IN      SHIPSKU.INV_STATUS%TYPE,
                  I_carton                  IN      SHIPSKU.CARTON%TYPE,
                  I_qty                     IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                  I_weight                  IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                  I_weight_uom              IN      UOM_CLASS.UOM%TYPE,                -- Catch Weight
                  I_tampered_ind            IN      SHIPSKU.TAMPERED_IND%TYPE,
                  I_is_wrong_store          IN      BOOLEAN,
                  I_from_inv_status         IN      TSFDETAIL.INV_STATUS%TYPE,
                  I_store_type              IN      STORE.STORE_TYPE%TYPE)
   RETURN BOOLEAN IS
   L_vdate                   DATE := GET_VDATE;
   L_from_loc                item_loc.loc%TYPE;
   L_to_loc                  item_loc.loc%TYPE;
   L_loc_type                VARCHAR2(1);
   L_rcv_increment_qty       item_loc_soh.stock_on_hand%TYPE  := 0;
   L_new_over_qty            item_loc_soh.stock_on_hand%TYPE  := 0;
   L_curr_over_qty           item_loc_soh.stock_on_hand%TYPE  := 0;
   L_overage_qty             item_loc_soh.stock_on_hand%TYPE  := 0;
   L_average_weight          item_loc_soh.average_weight%TYPE := 0;  -- Catch Weight
   L_ss_weight_expected      shipsku.weight_expected%TYPE     := 0;  -- Catch Weight
   L_ss_weight_expected_uom  shipsku.weight_expected_uom%TYPE := 0;  -- Catch Weight
   L_ss_prev_rcpt_weight     shipsku.weight_received%TYPE     := 0;  -- Catch Weight
   L_ss_prev_rcpt_weight_uom shipsku.weight_received_uom%TYPE := 0;  -- Catch Weight
   L_total_overage_qty       shipsku.qty_expected%TYPE        := 0;  -- Catch Weight
   L_total_overage_wgt_cuom  shipsku.weight_expected%TYPE     := 0;  -- Catch Weight
   L_total_ss_rcpt_wgt_cuom  shipsku.weight_received%TYPE     := 0;  -- Catch Weight
   L_weight_cuom             shipsku.weight_received%TYPE     := 0;  -- Catch Weight
   L_cuom                    ITEM_SUPP_COUNTRY.COST_UOM%TYPE;        -- Catch Weight
   L_wf_ind                  SYSTEM_OPTIONS.WHOLESALE_FRANCHISE_IND%TYPE;
   L_store_type              STORE.STORE_TYPE%TYPE            := 'C';
   L_rowid          ROWID;
   L_table          VARCHAR2(30);
   L_key1           VARCHAR2(100);
   L_key2           VARCHAR2(100);
   RECORD_LOCKED    EXCEPTION;
   PRAGMA           EXCEPTION_INIT(Record_Locked, -54);
   flow_cnt         BINARY_INTEGER := 0;
   -- cursors
   cursor C_SHIPSKU_INFO is
      select NVL(ss.qty_received, 0),
             NVL(ss.qty_expected, 0),
             ss.weight_expected,     -- Catch Weight
             ss.weight_expected_uom, -- Catch Weight
             ss.weight_received,     -- Catch Weight
             ss.weight_received_uom, -- Catch Weight
             ss.unit_cost,
             ss.seq_no,
             ss.adjust_type,
             ss.rowid
        from shipsku ss
       where ss.shipment  = I_shipment
         and ss.distro_no = I_distro_no
         and ss.item      = O_item_rec.item
         and NVL(ss.carton, ss.shipment) = NVL(I_carton, ss.shipment)
         for update nowait;
   -- cursor used for new SHIPSKU records created via the NEW_RECEIPT_ITEM functionality
   -- no need to lock the record, as it was just created in the same session
   cursor C_NEW_SHIPSKU_ROW is
      select rowid
        from shipsku
       where shipment  = I_shipment
         and distro_no = I_distro_no
         and item      = O_item_rec.item
         and NVL(carton, shipment) = NVL(I_carton, shipment);
   cursor C_INV_FLOW is
      select NVL(s.tsf_qty,0),
             s.received_qty,
             s.rowid
        from shipitem_inv_flow s,
             shipsku ss
       where s.shipment = O_item_rec.ship_no
         and s.seq_no   = O_item_rec.ss_seq_no
         and s.item     = O_item_rec.item
         and s.shipment = ss.shipment
         and s.seq_no = ss.seq_no
         and s.item = ss.item
         and s.from_loc = L_from_loc
         and s.to_loc   = L_to_loc
         for update nowait;
BEGIN
   if I_store_type is NOT NULL then
      L_store_type := I_store_type;
   end if;
   L_table := 'SHIPSKU';
   L_key1 := TO_CHAR(I_shipment);
   L_key2 := O_item_rec.item;
   O_item_rec.ss_seq_no := NULL;
   SQL_LIB.SET_MARK('OPEN',
                    'C_SHIPSKU_INFO',
                     L_table,
                    'shipment: '||I_shipment||' Distro No: '||I_distro_no||' Item: '||O_item_rec.item);
   open C_SHIPSKU_INFO;
   SQL_LIB.SET_MARK('FETCH',
                    'C_SHIPSKU_INFO',
                     L_table,
                    'shipment: '||I_shipment||' Distro No: '||I_distro_no||' Item: '||O_item_rec.item);
   fetch C_SHIPSKU_INFO into O_ss_prev_rcpt_qty,
                             O_ss_exp_qty,
                             L_ss_weight_expected,
                             L_ss_weight_expected_uom,
                             L_ss_prev_rcpt_weight,
                             L_ss_prev_rcpt_weight_uom,
                             O_ss_unit_cost,
                             O_item_rec.ss_seq_no,
                             O_item_rec.adjust_type,
                             L_rowid;
   SQL_LIB.SET_MARK('CLOSE',
                    'C_SHIPSKU_INFO',
                    L_table,
                    'shipment: '||I_shipment||' Distro No: '||I_distro_no||' Item: '||O_item_rec.item);
   close C_SHIPSKU_INFO;
   L_wf_ind := LP_system_options_row.wholesale_franchise_ind;
   if L_wf_ind != 'Y' OR
      L_store_type NOT IN ('W', 'F') then
      if O_item_rec.ss_seq_no IS NULL then
         if O_item_rec.distro_type = 'T' then
            if NEW_RECEIPT_ITEM(O_error_message,
                                O_item_rec,
                                I_shipment,
                                I_from_inv_status,
                                I_carton,
                                I_qty,
                                I_weight,      -- CatchWeight
                                I_weight_uom   -- CatchWeight
                                ) = FALSE then
               return FALSE;
            end if;
            O_ss_prev_rcpt_qty := 0;
            O_ss_exp_qty       := I_qty;
            O_ss_unit_cost     := 0;
            ----
            --- Since the item was just added to the shipment
            --- the qty_received on the SHIPSKU table has already been set to I_qty.
            --- So, in the SHIPSKU update statement, the qty_received should not
            --- be incremented.
            ----
            L_rcv_increment_qty          := 0;
            ---
            L_ss_weight_expected := I_weight;
            L_ss_weight_expected_uom := I_weight_uom;
            L_ss_prev_rcpt_weight := NULL;
            L_ss_prev_rcpt_weight_uom := NULL;
            ---
            open C_NEW_SHIPSKU_ROW;
            fetch C_NEW_SHIPSKU_ROW into L_rowid;
            close C_NEW_SHIPSKU_ROW;
         else
            O_error_message := SQL_LIB.CREATE_MSG('INV_SHIP_ITEM', O_item_rec.item, I_distro_no, null);
            return FALSE;
         end if;
      else
         L_rcv_increment_qty := I_qty;
      end if;
   end if;
   if LOCATION_ATTRIB_SQL.GET_TYPE(O_error_message,
                                   L_loc_type,
                                   O_item_rec.distro_to_loc)= FALSE then
      return FALSE;
   end if;
   if ((L_loc_type ='S' and LP_system_options_row.tsf_auto_close_store != 'Y') or
       (L_loc_type ='W' and LP_system_options_row.tsf_auto_close_wh != 'Y')) then
      if O_item_rec.adjust_type IS NOT NULL then
         O_error_message := SQL_LIB.CREATE_MSG('SHIP_ITEM_RECONCILED',O_item_rec.item, I_shipment, null);
         return FALSE;
      end if;
   end if;
   -- Catch Weight : determine total overage weight received and overage qty received
   if O_item_rec.simple_pack_ind = 'Y' and
      O_item_rec.catch_weight_ind = 'Y' then
      if DETERMINE_RECEIPT_WEIGHT(O_error_message,
                                  L_total_overage_qty,      -- output
                                  L_total_overage_wgt_cuom, -- output
                                  L_total_ss_rcpt_wgt_cuom, -- output
                                  L_weight_cuom,            -- output
                                  L_cuom,                   -- output
                                  O_ss_exp_qty,
                                  L_ss_weight_expected,
                                  L_ss_weight_expected_uom,
                                  O_ss_prev_rcpt_qty,
                                  L_ss_prev_rcpt_weight,
                                  L_ss_prev_rcpt_weight_uom,
                                  I_qty,
                                  I_weight,
                                  I_weight_uom,
                                  O_item_rec.item) = FALSE then
         return FALSE;
      end if;
   end if;
   if O_item_rec.tsf_type not in ('WR', 'FR') then
      if I_is_wrong_store = TRUE then
         SQL_LIB.SET_MARK('UPDATE',
                           NULL,
                           L_table,
                          'shipment: '||I_shipment||' Distro No: '||I_distro_no||' Item: '||O_item_rec.item);
         update shipsku ss
            set ss.qty_received        = NVL(ss.qty_received, 0) + L_rcv_increment_qty,
                actual_receiving_store = O_item_rec.distro_to_loc,
                reconcile_user_id      = USER,
                reconcile_date         = L_vdate,
                tampered_ind           = I_tampered_ind,
                weight_received        = L_total_ss_rcpt_wgt_cuom,
                weight_received_uom    = L_cuom
          where ss.rowid = L_rowid;
      else
         SQL_LIB.SET_MARK('UPDATE',
                           NULL,
                           L_table,
                          'shipment: '||I_shipment||' Distro No: '||I_distro_no||' Item: '||O_item_rec.item);
         update shipsku ss
            set ss.qty_received      = NVL(ss.qty_received, 0) + L_rcv_increment_qty,
                tampered_ind         = I_tampered_ind,
                weight_received      = L_total_ss_rcpt_wgt_cuom,
                weight_received_uom  = L_cuom
          where ss.rowid = L_rowid;
      end if;
   else
      update shipsku ss
         set ss.qty_received      = NVL(ss.qty_received, 0) + I_qty,
             tampered_ind         = I_tampered_ind,
             weight_received      = L_total_ss_rcpt_wgt_cuom,
             weight_received_uom  = I_weight_uom
       where ss.rowid = L_rowid;
   end if;
   -- Externally generated and to WH, load the inventory flows from shipitem_inv_flow
   if  I_external_ind = 'EG' and
       (O_item_rec.from_loc_type = 'W' or O_item_rec.to_loc_type = 'W') and
       LP_system_options_row.multichannel_ind = 'Y' then
      --------------------------------------------------------------------------
      -- EG transfers are at the physical location level on TSFHEAD.
      -- SHIPITEM_INV_FLOW records are associated with EG transfers, These
      -- records show which virtual locations the stock is actually moving
      -- between.  For example if a EG transfer is going from phy wh 1 (which
      -- contains virtuals 2, 3, 4, 5) to store 12, the SHIPITEM_INV_FLOW table
      -- could contain records as below (flows)
      --   from      to      tsf_qty    rcv_qty
      --    3        12       5           0
      --    4        12       6           0
      --
      -- Since receiving message come from outside of RMS (a store or wh) they contain
      -- physical locations.  A call to the distribution library call is used to
      -- determine what qty to give to each flow.  Continuing with the above example
      -- the message could, if the receipt message if for 8 units, the distribution
      -- library could tell us to give 3 units to the first flow and 5 units to the
      -- second flow.
      --   from      to      tsf_qty    rcv_qty
      --    3        12       5           3
      --    4        12       6           5
      --------------------------------------------------------------------------
      if DIST_QTY_TO_FLOW(O_error_message,
                          O_inv_flow_array,
                          O_item_rec.item,
                          I_shipment,
                          O_item_rec.ss_seq_no,
                          I_qty) = FALSE then
         return FALSE;
      end if;
      FOR flow_cnt IN O_inv_flow_array.FIRST..O_inv_flow_array.LAST LOOP
         O_inv_flow_array(flow_cnt).vir_from_loc_type := O_item_rec.from_loc_type;
         O_inv_flow_array(flow_cnt).vir_to_loc_type   := O_item_rec.to_loc_type;
         L_from_loc := O_inv_flow_array(flow_cnt).vir_from_loc;
         L_to_loc   := O_inv_flow_array(flow_cnt).vir_to_loc;
         L_table := 'SHIPITEM_INV_FLOW';
         L_key1 := TO_CHAR(I_shipment);
         L_key2 := O_item_rec.ss_seq_no;
         SQL_LIB.SET_MARK('OPEN',
                          'C_INV_FLOW',
                           L_table,
                          'shipment: '||O_item_rec.ship_no||' Seq No: '||O_item_rec.ss_seq_no||' Item: '||O_item_rec.item);
         open C_INV_FLOW;
         SQL_LIB.SET_MARK('FETCH',
                          'C_INV_FLOW',
                           L_table,
                          'shipment: '||O_item_rec.ship_no||' Seq No: '||O_item_rec.ss_seq_no||' Item: '||O_item_rec.item);
         fetch C_INV_FLOW into O_inv_flow_array(flow_cnt).exp_qty,
                               O_inv_flow_array(flow_cnt).prev_rcpt_qty,
                               L_rowid;
         SQL_LIB.SET_MARK('CLOSE',
                          'C_INV_FLOW',
                           L_table,
                          'shipment: '||O_item_rec.ship_no||' Seq No: '||O_item_rec.ss_seq_no||' Item: '||O_item_rec.item);
         close C_INV_FLOW;
         SQL_LIB.SET_MARK('UPDATE',
                           NULL,
                           L_table,
                          'shipment: '||O_item_rec.ship_no||' Seq No: '||O_item_rec.ss_seq_no||' Item: '||O_item_rec.item);
         update shipitem_inv_flow s
            set s.received_qty = NVL(s.received_qty, 0) + O_inv_flow_array(flow_cnt).dist_qty
          where s.rowid = L_rowid;
         -----------------------------------------------------------------------
         -- Calculate the overage.  The overage is used to decrment the sending
         -- loc's SOH and to update the receiving loc's average cost
         -- loc.  Each time a shipment is made the SOH is decremented at the
         -- from loc by the qty shipped and the to loc's average cost is updated to
         -- reflect the shipment qty.  When a receipt is made for a qty that
         -- is more that was originally shipped, we want to update the from
         -- loc's SOH bucket and update the to loc's average cost using the overage
         -- qty
         --
         -- Essentially we need to calcuate the overage (amount received that
         -- is greater that the amount shipped).  Then we can use the overage
         -- to update the from loc's SOH and the to loc's average cost.
         --
         --  current overage = previously received qty - shipped qty
         --  new overage     = (previously received qty + message receipt qty) - shipped qty
         --  update from SOH qty = new overage - current overage
         -----------------------------------------------------------------------
         L_curr_over_qty := GREATEST( (O_inv_flow_array(flow_cnt).prev_rcpt_qty -
                                       O_inv_flow_array(flow_cnt).exp_qty), 0);
         L_new_over_qty := GREATEST( ( (O_inv_flow_array(flow_cnt).prev_rcpt_qty +
                                           O_inv_flow_array(flow_cnt).dist_qty) -
                                        O_inv_flow_array(flow_cnt).exp_qty), 0);
         L_overage_qty := L_new_over_qty - L_curr_over_qty;
         O_inv_flow_array(flow_cnt).overage_qty := L_overage_qty;
         --CatchWeight
         if O_item_rec.catch_weight_ind = 'Y' AND O_item_rec.simple_pack_ind = 'Y' then
            O_inv_flow_array(flow_cnt).dist_weight_cuom := L_weight_cuom/I_qty * O_inv_flow_array(flow_cnt).dist_qty;
            O_inv_flow_array(flow_cnt).overage_weight_cuom := L_total_overage_wgt_cuom/L_total_overage_qty * O_inv_flow_array(flow_cnt).overage_qty;
            O_inv_flow_array(flow_cnt).cuom := L_cuom;
         end if;
         --CatchWeight End
         if O_item_rec.to_loc_type = 'S' then --store does not require distribution logic here for a wrong store.
            O_inv_flow_array(flow_cnt).vir_to_loc := O_item_rec.distro_to_loc;
         end if;
      END LOOP;
   else -- not externally generated, there is only one flow -- default it to array
      flow_cnt := 1;
      O_inv_flow_array(flow_cnt).vir_from_loc      := O_item_rec.distro_from_loc;
      O_inv_flow_array(flow_cnt).vir_from_loc_type := O_item_rec.from_loc_type;
      O_inv_flow_array(flow_cnt).vir_to_loc        := O_item_rec.distro_to_loc;
      O_inv_flow_array(flow_cnt).vir_to_loc_type   := O_item_rec.to_loc_type;
      O_inv_flow_array(flow_cnt).exp_qty           := O_ss_exp_qty;
      O_inv_flow_array(flow_cnt).prev_rcpt_qty     := O_ss_prev_rcpt_qty;
      O_inv_flow_array(flow_cnt).dist_qty          := I_qty;
      -- Set overage -- see above comment in EG section
      L_curr_over_qty := GREATEST( (O_inv_flow_array(flow_cnt).prev_rcpt_qty -
                                    O_inv_flow_array(flow_cnt).exp_qty), 0);
      L_new_over_qty := GREATEST( ( (O_inv_flow_array(flow_cnt).prev_rcpt_qty +
                                        O_inv_flow_array(flow_cnt).dist_qty) -
                                     O_inv_flow_array(flow_cnt).exp_qty), 0);
      L_overage_qty := L_new_over_qty - L_curr_over_qty;
      O_inv_flow_array(flow_cnt).overage_qty := L_overage_qty;
                 --CatchWeight
      if O_item_rec.catch_weight_ind = 'Y' AND O_item_rec.simple_pack_ind = 'Y' then
         O_inv_flow_array(flow_cnt).dist_weight_cuom := L_weight_cuom;
         O_inv_flow_array(flow_cnt).overage_weight_cuom := L_total_overage_wgt_cuom;
         O_inv_flow_array(flow_cnt).cuom := L_cuom;
      end if;
      if L_wf_ind = 'Y' AND
         L_store_type IN ('W', 'F') then
            L_curr_over_qty := 0;
            L_new_over_qty  := 0;
            L_overage_qty   := 0;
            O_inv_flow_array(flow_cnt).overage_weight_cuom := NULL;
      end if;
                 -- CatchWeight End
   end if;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.CHECK_SS',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END CHECK_SS;
-------------------------------------------------------------------------------
--New function for Catch Weight
FUNCTION DETERMINE_RECEIPT_WEIGHT(O_error_message          IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                                  O_total_overage_qty      IN OUT  SHIPSKU.QTY_EXPECTED%TYPE,
                                  O_total_overage_wgt_cuom IN OUT  SHIPSKU.WEIGHT_EXPECTED%TYPE,
                                  O_total_ss_rcpt_wgt_cuom IN OUT  SHIPSKU.WEIGHT_RECEIVED%TYPE,
                                  O_rcpt_wgt_cuom          IN OUT  SHIPSKU.WEIGHT_RECEIVED%TYPE,
                                  O_cuom                   IN OUT  ITEM_SUPP_COUNTRY.COST_UOM%TYPE,
                                  I_ss_exp_qty             IN      SHIPSKU.QTY_EXPECTED%TYPE,
                                  I_ss_exp_wgt             IN      SHIPSKU.WEIGHT_EXPECTED%TYPE,
                                  I_ss_exp_wgt_uom         IN      SHIPSKU.WEIGHT_EXPECTED_UOM%TYPE,
                                  I_ss_prev_rcpt_qty       IN      SHIPSKU.QTY_EXPECTED%TYPE,
                                  I_ss_prev_rcpt_wgt       IN      SHIPSKU.WEIGHT_RECEIVED%TYPE,
                                  I_ss_prev_rcpt_wgt_uom   IN      SHIPSKU.WEIGHT_RECEIVED_UOM%TYPE,
                                  I_rcpt_qty               IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                                  I_rcpt_wgt               IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,
                                  I_rcpt_wgt_uom           IN      UOM_CLASS.UOM%TYPE,
                                  I_item                   IN      ITEM_MASTER.ITEM%TYPE)
   RETURN BOOLEAN IS
   L_ss_exp_wgt_cuom         SHIPSKU.WEIGHT_EXPECTED%TYPE     := NULL;
   L_ss_prev_rcpt_wgt_cuom   SHIPSKU.WEIGHT_RECEIVED%TYPE     := NULL;
   L_rcpt_wgt_cuom           SHIPSKU.WEIGHT_RECEIVED%TYPE     := NULL;
   L_unit_wgt                ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE := 0;
BEGIN
   -- This function will determine the weight received and the overage weight/qty.
   -- SHIPSKU expected weight, previously received weight and new receipt weight
   -- can be in different weight uoms. Convert them all to item's cost uom for comparison.
   -- If the new receipt weight is defined on the message (i.e. goods are weighed at receiving),
   -- it will be used to evaluate the receipt weight and total overage weight.
   -- If not (i.e. goods are not weighed at receiving), SHIPSKU.weight_expected and
   -- weight_expected_uom will be used to derive the weight. Since at shipment time,
   -- SHIPSKU.weight_expected and weight_expected_uom are always populated for a simple
   -- pack catch weight item, we can expect them to be there when receiving against a
   -- shipment for a simple pack catch weight item.
   -- convert shipsku expected weight to cuom
   if not CATCH_WEIGHT_SQL.CONVERT_WEIGHT(O_error_message,
                                          L_ss_exp_wgt_cuom,
                                          O_cuom,
                                          I_item,
                                          I_ss_exp_wgt,
                                          I_ss_exp_wgt_uom) then
      return FALSE;
   end if;
   -- convert shipsku previously received weight to cuom
   if I_ss_prev_rcpt_wgt is NOT NULL then
      if not CATCH_WEIGHT_SQL.CONVERT_WEIGHT(O_error_message,
                                             L_ss_prev_rcpt_wgt_cuom,
                                             O_cuom,
                                             I_item,
                                             I_ss_prev_rcpt_wgt,
                                             I_ss_prev_rcpt_wgt_uom) then
         return FALSE;
      end if;
   end if;
   if I_rcpt_wgt is NOT NULL and I_rcpt_wgt_uom is NOT NULL then
      -- convert receiving weight to cuom
      -- use receiving weight to determine total shipsku received weight and overage weight
      if not CATCH_WEIGHT_SQL.CONVERT_WEIGHT(O_error_message,
                                             O_rcpt_wgt_cuom,
                                             O_cuom,
                                             I_item,
                                             I_rcpt_wgt,
                                             I_rcpt_wgt_uom) then
         return FALSE;
      end if;
   else
      -- no receiving weight, derive receiving weight from SHIPSKU expected weight
      if O_cuom = 'EA' then
         O_rcpt_wgt_cuom := L_ss_exp_wgt_cuom;
      else
         L_unit_wgt := L_ss_exp_wgt_cuom/I_ss_exp_qty;
         O_rcpt_wgt_cuom := L_unit_wgt * I_rcpt_qty;
      end if;
   end if;
   O_total_overage_qty := GREATEST(NVL(I_ss_prev_rcpt_qty,0)+I_rcpt_qty-I_ss_exp_qty, 0);
   O_total_overage_wgt_cuom := GREATEST(NVL(L_ss_prev_rcpt_wgt_cuom,0)+O_rcpt_wgt_cuom-L_ss_exp_wgt_cuom, 0);
   O_total_ss_rcpt_wgt_cuom := NVL(L_ss_prev_rcpt_wgt_cuom,0)+O_rcpt_wgt_cuom;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.DETERMINE_RECEIPT_WEIGHT',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END DETERMINE_RECEIPT_WEIGHT;
-------------------------------------------------------------------------------
FUNCTION DIST_QTY_TO_FLOW(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          O_inv_flow_array  IN OUT  STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                          I_item            IN      ITEM_MASTER.ITEM%TYPE,
                          I_shipment        IN      SHIPMENT.SHIPMENT%TYPE,
                          I_ss_seq_no       IN      SHIPSKU.SEQ_NO%TYPE,
                          I_tsf_qty         IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
   RETURN BOOLEAN IS
   L_dist_array     DISTRIBUTION_SQL.DIST_TABLE_TYPE;
   dist_cnt         BINARY_INTEGER := 0;
   flow_cnt         BINARY_INTEGER := 0;
BEGIN
   if DISTRIBUTION_SQL.DISTRIBUTE(O_error_message,
                                  L_dist_array,
                                  I_item,
                                  NULL,             --I_LOC
                                  I_tsf_qty,
                                  'TRANSFER',
                                  NULL,             --I_INV_STATUS,
                                  NULL,             --I_TO_LOC_TYPE
                                  NULL,             --I_TO_LOC
                                  NULL,             --I_ORDER_NO
                                  I_shipment,
                                  I_ss_seq_no) = FALSE then
      return FALSE;
   end if;
   FOR dist_cnt IN L_dist_array.FIRST..L_dist_array.LAST LOOP
      flow_cnt := flow_cnt + 1;
      O_inv_flow_array(flow_cnt).vir_to_loc   := L_dist_array(dist_cnt).to_loc;
      O_inv_flow_array(flow_cnt).vir_from_loc := L_dist_array(dist_cnt).from_loc;
      O_inv_flow_array(flow_cnt).dist_qty     := L_dist_array(dist_cnt).dist_qty;
   END LOOP;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.DIST_QTY_TO_FLOW',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END DIST_QTY_TO_FLOW;
-------------------------------------------------------------------------------
FUNCTION APPT_CHECK(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                    I_appt           IN      APPT_DETAIL.APPT%TYPE,
                    I_distro         IN      APPT_DETAIL.DOC%TYPE,
                    I_distro_type    IN      APPT_DETAIL.DOC_TYPE%TYPE,
                    I_to_loc_phy     IN      ITEM_LOC.LOC%TYPE,
                    I_item           IN      ITEM_MASTER.ITEM%TYPE,
                    I_asn            IN      APPT_DETAIL.ASN%TYPE,
                    I_receipt_no     IN      APPT_DETAIL.RECEIPT_NO%TYPE,
                    I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
   RETURN BOOLEAN IS
   L_rowid                 ROWID := NULL;
   L_table                 VARCHAR2(30);
   L_key1                  VARCHAR2(100);
   L_key2                  VARCHAR2(100);
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
   cursor C_APPT_EXIST is
      select ad.rowid
        from appt_detail ad,
             item_master im
       where ad.appt           = I_appt
         and ad.loc            = I_to_loc_phy
         and ad.doc            = I_distro
         and nvl(ad.asn, ' ')  = nvl(I_asn, ' ')
         and ((ad.item         = I_item and
               ad.item         = im.item) or
              (ad.item         = im.item and
               im.item_parent  = I_item))
        for update of ad.receipt_no nowait;
         -- By specifying ad.receipt_no above, the entire row on
         -- appt_detail will be locked while the corresponding
         -- row on item_master remains unlocked.
BEGIN
   L_table := 'APPT_DETAIL';
   L_key1 := TO_CHAR(I_appt);
   L_key2 := TO_CHAR(I_to_loc_phy)||' '||I_item;
   open C_APPT_EXIST;
   fetch C_APPT_EXIST into L_rowid;
   close C_APPT_EXIST;
   if L_rowid IS NULL then
      -- populate a queue table for distro closure
      P_doc_close_queue_size := P_doc_close_queue_size + 1;
      P_doc_close_queue_doc(P_doc_close_queue_size)        := I_distro;
      P_doc_close_queue_doc_type(P_doc_close_queue_size)   := I_distro_type;
   else
      -- update the appt_detail table
      P_appt_detail_size := P_appt_detail_size + 1;
      P_appt_detail_qty_received(P_appt_detail_size)     := I_qty;
      P_appt_detail_receipt_no (P_appt_detail_size)      := I_receipt_no;
      P_appt_detail_rowid (P_appt_detail_size)           := L_rowid;
   end if;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.APPT_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END APPT_CHECK;
------------------------------------------------------------------------------
FUNCTION TSF_CHECK(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                   O_tsf_type         IN OUT  TSFHEAD.TSF_TYPE%TYPE,
                   O_tsf_status       IN OUT  TSFHEAD.STATUS%TYPE,
                   O_from_loc_type    IN OUT  ITEM_LOC.LOC_TYPE%TYPE,
                   O_from_loc_distro  IN OUT  ITEM_LOC.LOC%TYPE,
                   O_from_loc_phy     IN OUT  ITEM_LOC.LOC%TYPE,
                   O_from_tsf_entity  IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                   O_from_finisher    IN OUT  VARCHAR2,
                   O_to_loc_type      IN OUT  ITEM_LOC.LOC_TYPE%TYPE,
                   O_to_loc_distro    IN OUT  ITEM_LOC.LOC%TYPE,
                   O_to_loc_phy       IN OUT  ITEM_LOC.LOC%TYPE,
                   O_to_tsf_entity    IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                   O_to_finisher      IN OUT  VARCHAR2,
                   O_tsf_parent_no    IN OUT  TSFHEAD.TSF_PARENT_NO%TYPE,
                   O_mrt_no           IN OUT  TSFHEAD.MRT_NO%TYPE,
                   I_tsf_no           IN      TSFHEAD.TSF_NO%TYPE,
                   I_loc              IN      ITEM_LOC.LOC%TYPE)
   RETURN BOOLEAN IS
   L_exist         BOOLEAN := FALSE;
   L_entity_name   tsf_entity.tsf_entity_desc%TYPE;
   L_finisher      BOOLEAN := FALSE;
   L_finisher_name WH.WH_NAME%TYPE;
   L_to_loc        item_loc.loc%TYPE;
  -- cursors
   cursor C_TSF is
      select h.tsf_type,
             h.status,
             h.from_loc_type,
             h.from_loc,
             h.to_loc_type,
             h.to_loc,
             h.tsf_parent_no,
             h.mrt_no
        from tsfhead h
       where h.tsf_no = I_tsf_no;
BEGIN
   --
   -- for externally generated transfers, physical warehouses are used on the
   -- transfer tables.  there could be multiple virtual warehouses for each
   -- physical warehouse.  if intercompany_tsf_ind = 'Y', those virtual warehouses
   -- could belong to different transfer entities, therefore, we could not assign
   -- a transfer entity to the physical warehouse, which is a problem.
   -- Hence, if intercompany_tsf_ind = 'Y, we don't allow 'EG' transfer
   -- between 2 physcial warehouses at the moment.  We do allow store to
   -- warehouse 'EG' transfer, because we assume that store is sending
   -- merchandise to the virtual warehouse within the same channel (and hence
   -- the same transfer entity).
   --
   --
   -- if system_options.intercompany_tsf_ind = 'Y' then
   --
   --    an externally generated transfer must:
   --    - have no finisher (no multilegged transfers allowed)
   --    - use physical warehouses on the transfer tables (this is mostly
   --      because RDM doesn't know what virtual warehouses are).  however we
   --      will only support the following scenarios:
   --      a.  store to warehouse (implemented in distribution via
   --                              channel level distribution)
   --      b.  store to store
   --      c.  warehouse to store
   --
   -- else if system_options.intercompany_tsf_ind = 'N' then
   --
   --    an externally generated transfer must:
   --    - have no finisher (no multilegged transfers allowed)
   --    - use physical warehouses on the transfer tables (this is mostly
   --      because RDM doesn't know what virtual warehouses are).  however we
   --      will only support the following scenarios:
   --      a.  store to warehouse (implemented in distribution via
   --                              channel level distribution)
   --      b.  store to store
   --      c.  warehouse to warehouse
   --
   -- if this is not the first call, use the cached values
   if (LP_cache_header_info.tsf_check_input_loc = I_loc AND
       LP_cache_header_info.tsf_check_tsf_no = I_tsf_no) then
      O_tsf_type           := LP_cache_header_info.tsf_check_tsf_type;
      O_tsf_status         := LP_cache_header_info.tsf_check_tsf_status;
      O_from_loc_type      := LP_cache_header_info.tsf_check_from_loc_type;
      O_from_loc_distro    := LP_cache_header_info.tsf_check_from_loc_distro;
      O_from_loc_phy       := LP_cache_header_info.tsf_check_from_loc_phy;
      O_from_tsf_entity    := LP_cache_header_info.tsf_check_from_tsf_entity;
      O_from_finisher      := LP_cache_header_info.tsf_check_from_finisher;
      O_to_loc_type        := LP_cache_header_info.tsf_check_to_loc_type;
      O_to_loc_distro      := LP_cache_header_info.tsf_check_to_loc_distro;
      O_to_loc_phy         := LP_cache_header_info.tsf_check_to_loc_phy;
      O_to_tsf_entity      := LP_cache_header_info.tsf_check_to_tsf_entity;
      O_to_finisher        := LP_cache_header_info.tsf_check_to_finisher;
      O_tsf_parent_no      := LP_cache_header_info.tsf_check_tsf_parent_no;
      O_mrt_no             := LP_cache_header_info.tsf_mrt_no;
      return TRUE;
   end if;
   O_tsf_type := NULL;
   open C_TSF;
   fetch C_TSF into O_tsf_type,
                    O_tsf_status,
                    O_from_loc_type,
                    O_from_loc_distro,
                    O_to_loc_type,
                    O_to_loc_distro,
                    O_tsf_parent_no,
                    O_mrt_no;
   close C_TSF;
   if O_tsf_type IS NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_TRANSFER', I_tsf_no, NULL, NULL);
      return FALSE;
   end if;
   -- if the transfer is not EG, the locs on tsfhead are virtual locs, thus the vir wh on
   -- tsfhead must exist in the physical wh in the message.
   if O_tsf_type != 'EG' and O_to_loc_type = 'W' then
      if WH_ATTRIB_SQL.VWH_EXISTS_IN_PWH(O_error_message,
                                         L_exist,
                                         O_to_loc_distro,      --virtual
                                         I_loc) = FALSE then   --phy
         return FALSE;
      end if;
      if L_exist = FALSE then
         O_error_message := SQL_LIB.CREATE_MSG('INV_TSF_TO_LOC', to_char(I_loc),
                                                to_char(I_tsf_no), NULL);
         return FALSE;
      end if;
   end if;
   O_to_loc_phy := I_loc;
   -- if the transfer is not EG and the from loc is warehouse, the from loc
   -- on tsfhead is a virtual loc, look up its pysical wh.
   if O_tsf_type != 'EG' and O_from_loc_type = 'W' then
      if WH_ATTRIB_SQL.GET_PWH_FOR_VWH(O_error_message,
                                       O_from_loc_phy,
                                       O_from_loc_distro) = FALSE then
         return FALSE;
      end if;
   else
      O_from_loc_phy := O_from_loc_distro;
   end if;
   if LP_system_options_row.intercompany_transfer_ind = 'Y'
      and (O_from_loc_type = 'S' or O_tsf_type != 'EG') then
      if LOCATION_ATTRIB_SQL.GET_ENTITY(O_error_message,
                                        O_from_tsf_entity,
                                        L_entity_name,
                                        O_from_loc_distro,
                                        O_from_loc_type) = FALSE then
         return FALSE;
      end if;
   end if;
   if O_tsf_type != 'EG' then
      if O_from_loc_type = 'W' then
         if WH_ATTRIB_SQL.CHECK_FINISHER(O_error_message,
                                         L_finisher,
                                         L_finisher_name,
                                         O_from_loc_distro) = FALSE then
            return FALSE;
         end if;
      end if;
   end if;
   if L_finisher then
      O_from_finisher := 'Y';
   elsif O_from_loc_type = 'E' then
      O_from_finisher := 'Y';
   else
      O_from_finisher := 'N';
   end if;
   if LP_system_options_row.intercompany_transfer_ind = 'Y' and (O_to_loc_type = 'S' or O_tsf_type != 'EG') then
      if O_to_loc_type = 'S' then
         --In case of wrong store receipt get the entity of I_to_loc, the actual receiving loc.
         --The entity of the intended to loc will be retreived in wrong_store_receipt
         L_to_loc := I_loc;
      else
         --For all other receiving use to_loc_distro (vir wh)
         --Vir wh's and External Finishers will not be received at a location other than the
         --Distro to loc.
         L_to_loc := O_to_loc_distro;
      end if;
      if LOCATION_ATTRIB_SQL.GET_ENTITY(O_error_message,
                                        O_to_tsf_entity,
                                        L_entity_name,
                                        L_to_loc,
                                        O_to_loc_type) = FALSE then
         return FALSE;
      end if;
   end if;
   L_finisher := FALSE;
   if O_tsf_type != 'EG' then
      if O_to_loc_type = 'W' then
         if WH_ATTRIB_SQL.CHECK_FINISHER(O_error_message,
                                         L_finisher,
                                         L_finisher_name,
                                         O_to_loc_distro) = FALSE then
            return FALSE;
         end if;
      end if;
   end if;
   if L_finisher then
      O_to_finisher := 'Y';
   elsif O_to_loc_type = 'E' then
      O_to_finisher := 'Y';
   else
      O_to_finisher := 'N';
   end if;
   -- this is the first time for this loc/tsf, populated the cache for next call
   LP_cache_header_info.tsf_check_tsf_no          := I_tsf_no;
   LP_cache_header_info.tsf_check_input_loc       := I_loc;
   LP_cache_header_info.tsf_check_tsf_type        := O_tsf_type;
   LP_cache_header_info.tsf_check_tsf_status      := O_tsf_status;
   LP_cache_header_info.tsf_check_from_loc_type   := O_from_loc_type;
   LP_cache_header_info.tsf_check_from_loc_distro := O_from_loc_distro;
   LP_cache_header_info.tsf_check_from_loc_phy    := O_from_loc_phy;
   LP_cache_header_info.tsf_check_from_tsf_entity := O_from_tsf_entity;
   LP_cache_header_info.tsf_check_from_finisher   := O_from_finisher;
   LP_cache_header_info.tsf_check_to_loc_type     := O_to_loc_type;
   LP_cache_header_info.tsf_check_to_loc_distro   := O_to_loc_distro;
   LP_cache_header_info.tsf_check_to_loc_phy      := O_to_loc_phy;
   LP_cache_header_info.tsf_check_to_tsf_entity   := O_to_tsf_entity;
   LP_cache_header_info.tsf_check_to_finisher     := O_to_finisher;
   LP_cache_header_info.tsf_check_tsf_parent_no   := O_tsf_parent_no;
   LP_cache_header_info.tsf_mrt_no                := O_mrt_no;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.TSF_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END TSF_CHECK;
-------------------------------------------------------------------------------
FUNCTION TSF_DETAIL_CHECK(O_error_message     IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          O_tsf_seq_no        IN OUT  TSFDETAIL.TSF_SEQ_NO%TYPE,
                          O_td_exp_qty        IN OUT  TSFDETAIL.TSF_QTY%TYPE,
                          O_td_prev_rcpt_qty  IN OUT  TSFDETAIL.RECEIVED_QTY%TYPE,
                          O_from_inv_status   IN OUT  TSFDETAIL.INV_STATUS%TYPE,
                          I_tsf_no            IN      TSFHEAD.TSF_NO%TYPE,
                          I_item              IN      ITEM_MASTER.ITEM%TYPE,
                          I_inv_status        IN      TSFDETAIL.INV_STATUS%TYPE,
                          I_recv_qty          IN      TSFDETAIL.RECEIVED_QTY%TYPE,
                          I_is_wrong_store    IN      BOOLEAN)
   RETURN BOOLEAN IS
   L_rowid                 ROWID;
   L_table                 VARCHAR2(30);
   L_key1                  VARCHAR2(100);
   L_key2                  VARCHAR2(100);
   L_tsf_type              TSFHEAD.TSF_TYPE%TYPE;
   L_wfr_ship_qty          TSFDETAIL.SHIP_QTY%TYPE;
   L_wfr_to_loc            TSFHEAD.TO_LOC%TYPE;
   L_wfr_to_loc_type       TSFHEAD.TO_LOC_TYPE%TYPE;
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
   cursor C_TSFDETAIL_EXIST is
      select /*+ INDEX(td PK_TSFDETAIL) */
             td.tsf_seq_no,
             NVL(td.tsf_qty, 0),
             (NVL(td.received_qty, 0) + NVL(td.reconciled_qty, 0)),
             td.inv_status,
             td.rowid
        from tsfdetail td
       where td.tsf_no = I_tsf_no
         and td.item   = I_item
         and rownum    = 1
         for update nowait;
   -- from_dispositon in the rib message is not reliable.  The receiving location
   -- will not necessarily know what the from disposition was.  Instead what we should
   -- do is to bring down the tsfdetail inventory status in tsfdetail_check and use
   -- this to determine the from status for overage.  If the item is not found on the
   -- transfer, check the transfer type.  If it is NS or NB, select inventory status from
   -- tsfdetail for the transfer.  Otherwise the from inventory status should be null.
   cursor C_FRM_INV_STATUS is
      select td.inv_status
        from tsfhead th, tsfdetail td
       where th.tsf_no = I_tsf_no
         and th.tsf_type in('NS','NB')
         and td.inv_status >= 0
         and th.tsf_no = td.tsf_no
         and rownum = 1;
   cursor C_WFR_DETAIL is
      select th.to_loc,
             th.to_loc_type,
             td.ship_qty
        from tsfhead th,
             tsfdetail td
       where th.tsf_no = I_tsf_no
         and td.tsf_no = th.tsf_no
         and td.item   = I_item;
BEGIN
   O_tsf_seq_no       := NULL;
   O_td_exp_qty       := 0;
   O_td_prev_rcpt_qty := 0;
   O_from_inv_status  := NULL;
   L_table := 'TSFDETAIL';
   L_key1 := TO_CHAR(I_tsf_no);
   L_key2 := I_item;
   --- Get the Transfer type
   if STOCK_ORDER_RECONCILE_SQL.GET_TSF_TYPE(O_error_message,
                                             L_tsf_type,
                                             I_tsf_no)= FALSE then
      return FALSE;
   end if;
   if L_tsf_type in ('WR', 'FR') then
      open C_WFR_DETAIL;
      fetch C_WFR_DETAIL into L_wfr_to_loc,
                              L_wfr_to_loc_type,
                              L_wfr_ship_qty;
      close C_WFR_DETAIL;
   else
      open C_TSFDETAIL_EXIST;
      fetch C_TSFDETAIL_EXIST into O_tsf_seq_no,
                                   O_td_exp_qty,
                                   O_td_prev_rcpt_qty,
                                   O_from_inv_status,
                                   L_rowid;
      close C_TSFDETAIL_EXIST;
      if O_tsf_seq_no is not NULL then
         if I_is_wrong_store = TRUE then
            update tsfdetail td
               set td.reconciled_qty = NVL(td.reconciled_qty, 0) + I_recv_qty
             where td.rowid = L_rowid;
         else
            update tsfdetail td
               set td.received_qty = NVL(td.received_qty, 0) + I_recv_qty
             where td.rowid = L_rowid;
         end if;
      else
         open C_FRM_INV_STATUS;
         fetch C_FRM_INV_STATUS into O_from_inv_status;
         close C_FRM_INV_STATUS;
      end if;
   end if;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.TSF_DETAIL_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END TSF_DETAIL_CHECK;
-------------------------------------------------------------------------------
FUNCTION ALLOC_CHECK(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                     O_alloc_status     IN OUT  ALLOC_HEADER.STATUS%TYPE,
                     O_from_loc_type    IN OUT  ITEM_LOC.LOC_TYPE%TYPE,
                     O_distro_from_loc  IN OUT  ITEM_LOC.LOC%TYPE,
                     O_from_loc_phy     IN OUT  ITEM_LOC.LOC%TYPE,
                     O_from_tsf_entity  IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                     O_to_tsf_entity    IN OUT  TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                     I_alloc_no         IN      ALLOC_HEADER.ALLOC_NO%TYPE,
                     I_item             IN      ITEM_MASTER.ITEM%TYPE,
                     I_to_loc           IN      ITEM_LOC.LOC%TYPE,
                     I_to_loc_type      IN      ITEM_LOC.LOC_TYPE%TYPE)
   RETURN BOOLEAN IS
   L_item         item_master.item%TYPE := NULL;
   L_entity_name  tsf_entity.tsf_entity_desc%TYPE;
   -- cursors
   cursor C_VAL_ALLOC is
      --alloc are always from wh locs
      select ah.status,
             'W',
             ah.wh,
             w.physical_wh,
             ah.item
        from alloc_header ah,
             wh w
       where ah.alloc_no = I_alloc_no
         and ah.wh       = w.wh;
BEGIN
   open C_VAL_ALLOC;
   fetch C_VAL_ALLOC into O_alloc_status,
                          O_from_loc_type,
                          O_distro_from_loc,
                          O_from_loc_phy,
                          L_item;
   close C_VAL_ALLOC;
   if L_item IS NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_ALLOC_NUM', NULL, NULL, NULL);
      return FALSE;
   end if;
   if L_item != I_item then
      O_error_message := SQL_LIB.CREATE_MSG('NO_ITEM_ALLOC', I_item, I_alloc_no, null);
      return FALSE;
   end if;
   if LP_system_options_row.intercompany_transfer_ind = 'Y' then
      if LOCATION_ATTRIB_SQL.GET_ENTITY(O_error_message,
                                        O_from_tsf_entity,
                                        L_entity_name,
                                        O_distro_from_loc,
                                        O_from_loc_type) = FALSE then
         return FALSE;
      end if;
      -- Assume can only allocate to stores
      if LOCATION_ATTRIB_SQL.GET_ENTITY(O_error_message,
                                        O_to_tsf_entity,
                                        L_entity_name,
                                        I_to_loc,
                                        I_to_loc_type) = FALSE then
         return FALSE;
      end if;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.ALLOC_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END ALLOC_CHECK;
-------------------------------------------------------------------------------
FUNCTION ALLOC_DETAIL_CHECK(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                            O_qty_allocated   IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                            O_qty_received    IN OUT  ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                            I_alloc_no        IN      ALLOC_HEADER.ALLOC_NO%TYPE,
                            I_to_loc          IN      ITEM_LOC.LOC%TYPE,
                            I_qty             IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                            I_is_wrong_store  IN      BOOLEAN)
   RETURN BOOLEAN IS
   L_rowid                 ROWID;
   L_table                 VARCHAR2(30);
   L_key1                  VARCHAR2(100);
   L_key2                  VARCHAR2(100);
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
   -- cursors
   cursor C_ALLOC_DETAIL_EXIST is
      select ad.qty_allocated,
             (NVL(ad.qty_received, 0) + NVL(ad.qty_reconciled, 0)),
             ad.rowid
        from alloc_detail ad,
             wh w
       where ad.alloc_no            = I_alloc_no
         --
         and ad.to_loc =  nvl(w.wh, I_to_loc)
         and w.wh (+) = ad.to_loc
         and w.physical_wh (+) = I_to_loc
         --
         for update nowait;
BEGIN
   L_table := 'ALLOC_DETAIL';
   L_key1 := TO_CHAR(I_alloc_no);
   L_key2 := TO_CHAR(I_to_loc);
   open C_ALLOC_DETAIL_EXIST;
   fetch C_ALLOC_DETAIL_EXIST into O_qty_allocated,
                                   O_qty_received,
                                   L_rowid;
   close C_ALLOC_DETAIL_EXIST;
   if O_qty_allocated IS NULL then
      O_error_message := SQL_LIB.CREATE_MSG('NO_ALLOC_DET',to_char(I_to_loc),to_char(I_alloc_no),null);
      return FALSE;
   else
      if I_is_wrong_store = TRUE then
         update alloc_detail ad
            set ad.qty_reconciled = NVL(ad.qty_reconciled, 0) + I_qty
          where ad.rowid = L_rowid;
      else
         update alloc_detail ad
            set ad.qty_received = NVL(ad.qty_received, 0) + I_qty
          where ad.rowid = L_rowid;
      end if;
   end if;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.ALLOC_DETAIL_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END ALLOC_DETAIL_CHECK;
-------------------------------------------------------------------------------
FUNCTION DETAIL_PROCESSING(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_item_rec        IN OUT  STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                           I_values          IN OUT  STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                           I_inv_flow_array  IN OUT  STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                           I_flow_cnt        IN      BINARY_INTEGER,
                           I_distro_no       IN      SHIPSKU.DISTRO_NO%TYPE,
                           I_distro_type     IN      APPT_DETAIL.DOC_TYPE%TYPE,
                           I_from_inv_status IN      TSFDETAIL.INV_STATUS%TYPE)
RETURN BOOLEAN IS
   L_distro_status           tsfhead.status%TYPE := NULL;
   L_pgm_name                  TRAN_DATA.PGM_NAME%TYPE                 := 'STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING';
   L_overage_ind               BOOLEAN                                 := FALSE;
   L_ship_close_ind            BOOLEAN                                 := FALSE;
   L_inventory_treatment_ind   SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE := NULL;
   L_short_qty                item_loc_soh.stock_on_hand%TYPE          := 0;
   L_overage_qty              item_loc_soh.stock_on_hand%TYPE          := 0;
BEGIN
   if I_item_rec.distro_type = 'A' then
      L_distro_status := I_item_rec.alloc_status;
   else
      L_distro_status := I_item_rec.tsf_status;
   end if;
   --
   L_short_qty    :=  I_inv_flow_array(I_flow_cnt).upd_intran_qty;
   L_overage_qty  := I_inv_flow_array(I_flow_cnt).overage_qty;
   if L_short_qty != 0 and (L_distro_status = 'C' or I_item_rec.adjust_type IS NOT NULL) then
      I_inv_flow_array(I_flow_cnt).dist_qty := I_inv_flow_array(I_flow_cnt).overage_qty;
      I_inv_flow_array(I_flow_cnt).upd_intran_qty := 0;
   end if;
   --
   if I_inv_flow_array(I_flow_cnt).overage_qty != 0 then
      L_overage_ind := TRUE;
   end if;
   --
   if I_item_rec.adjust_type IS NOT NULL then
      L_ship_close_ind := TRUE;
   end if;
   --
   if I_inv_flow_array(I_flow_cnt).upd_intran_qty != 0 or  I_inv_flow_array(I_flow_cnt).overage_qty != 0 then
      if STOCK_ORDER_RCV_SQL.GET_INVENTORY_TREATMENT (O_error_message,
                                                      L_inventory_treatment_ind,
                                                      I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                      I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                      I_distro_no,
                                                      I_distro_type,
                                                      I_item_rec.ship_no,
                                                      I_item_rec.ss_seq_no,
                                                      L_ship_close_ind,
                                                      L_overage_ind) = FALSE then
          return FALSE;
      end if;
      --
      if STOCK_ORDER_RCV_SQL.DETAIL_METHOD(O_error_message,
                                               I_item_rec,
                                               I_values,
                                               I_inv_flow_array,
                                               I_flow_cnt,
                                               I_distro_no,
                                               I_distro_type,
                                               I_from_inv_status,
                                               L_inventory_treatment_ind) = FALSE then
         return FALSE;
      end if;
      --
   end if;
   --
   if L_short_qty != 0 and (L_distro_status = 'C' or I_item_rec.adjust_type IS NOT NULL) then
      I_inv_flow_array(I_flow_cnt).dist_qty    := L_short_qty;
      I_inv_flow_array(I_flow_cnt).overage_qty := L_short_qty;
      --
      if STOCK_ORDER_RCV_SQL.GET_INVENTORY_TREATMENT (O_error_message,
                                                      L_inventory_treatment_ind,
                                                      I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                      I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                      I_distro_no,
                                                      I_distro_type,
                                                      I_item_rec.ship_no,
                                                      I_item_rec.ss_seq_no,
                                                      FALSE,
                                                      FALSE) = FALSE then
          return FALSE;
      end if;
      --
      if STOCK_ORDER_RCV_SQL.DETAIL_METHOD(O_error_message,
                                               I_item_rec,
                                               I_values,
                                               I_inv_flow_array,
                                               I_flow_cnt,
                                               I_distro_no,
                                               I_distro_type,
                                               I_from_inv_status,
                                               L_inventory_treatment_ind) = FALSE then
          return FALSE;
      end if;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END DETAIL_PROCESSING;
---------------------------------------------------------------------------------------------------------------
FUNCTION DETAIL_METHOD(O_error_message   IN OUT      RTK_ERRORS.RTK_TEXT%TYPE,
                       I_item_rec        IN OUT      STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                       I_values          IN OUT      STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                       I_inv_flow_array  IN          STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                       I_flow_cnt        IN          BINARY_INTEGER,
                       I_distro_no       IN          SHIPSKU.DISTRO_NO%TYPE,
                       I_distro_type     IN          APPT_DETAIL.DOC_TYPE%TYPE,
                       I_from_inv_status IN          TSFDETAIL.INV_STATUS%TYPE,
                       I_inventory_treatment_ind IN SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE )
RETURN BOOLEAN IS
   L_comp_items   stock_order_rcv_sql.comp_item_array;
   comp_cnt       BINARY_INTEGER              := 0;
   L_cycle_count  stake_head.cycle_count%TYPE := NULL;
   L_pack_total_chrgs_prim    item_loc.unit_retail%TYPE   := 0;
   L_pack_profit_chrgs_to_loc item_loc.unit_retail%TYPE   := 0;
   L_pack_exp_chrgs_to_loc    item_loc.unit_retail%TYPE   := 0;
   L_total_chrgs_prim         item_loc.unit_retail%TYPE   := 0;
   L_profit_chrgs_to_loc      item_loc.unit_retail%TYPE   := 0;
   L_exp_chrgs_to_loc         item_loc.unit_retail%TYPE   := 0;
   L_shipment                 shipment.shipment%TYPE      := NULL;
   L_ss_seq_no                shipsku.seq_no%TYPE         := NULL;
   L_intercompany             BOOLEAN                     := FALSE;
   L_total_pack_value         item_loc_soh.unit_cost%TYPE := NULL;
   L_comp_wac                 item_loc_soh.av_cost%TYPE   := NULL; -- Transfer and Item Valuation
   L_from_loc_currency        item_loc.unit_retail%TYPE   := 0;    -- Transfer and Item Valuation
   L_percent_in_pack          NUMBER;                              -- Transfer and Item Valuation
   --specific pack level overage processing
   L_from_loc_rcv_as_type     item_loc.receive_as_type%TYPE := 'P';
   L_update_comp_type         VARCHAR2(1)                   := 'C';
   L_rdw_tran_code            tran_data.tran_code%TYPE  := 44;
   L_dummy_cost               item_loc_soh.av_cost%TYPE := NULL;
   L_pgm_name                 tran_data.pgm_name%TYPE   := 'STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING'; -- Please do not change this as it is used by tran_data
   L_inventory_treatment_ind  system_options.tsf_force_close_ind%type := NULL;
   L_store_type                STORE.STORE_TYPE%TYPE                   := 'C';
   --
   cursor C_FRM_RECEIVE_AS_TYPE is
      select NVL(il.receive_as_type, 'E')
      from item_loc il
      where il.item = I_item_rec.item
      and il.loc  = I_inv_flow_array(I_flow_cnt).vir_from_loc;
BEGIN
   L_inventory_treatment_ind := I_inventory_treatment_ind;
   if I_item_rec.tsf_type = 'EG' then
      --pass shipment info for EG transfers
      L_shipment  := I_item_rec.ship_no;
      L_ss_seq_no := I_item_rec.ss_seq_no;
   else
      --do not pass shipment info for non-EG transfers or allocs
      L_shipment  := NULL;
      L_ss_seq_no := NULL;
   end if;
   if TRANSFER_SQL.IS_INTERCOMPANY(O_error_message,
                                   L_intercompany,
                                   I_distro_type,
                                   I_item_rec.tsf_type,
                                   I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                   I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                   I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                   I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE THEN
      return FALSE;
   end if;
   if I_item_rec.pack_ind = 'N' then
      if I_inv_flow_array(I_flow_cnt).overage_qty != 0 then
         if I_values.from_loc_av_cost > 0 then
            if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS(
                                O_error_message,
                                L_total_chrgs_prim,
                                L_profit_chrgs_to_loc,
                                L_exp_chrgs_to_loc,
                                I_distro_type,
                                I_distro_no,
                                I_item_rec.tsf_seq_no, --this will be null for allocs
                                L_shipment,
                                L_ss_seq_no,
                                I_item_rec.item,       --item
                                NULL,                  --pack_no
                                I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE then
               return FALSE;
            end if;
            if L_total_chrgs_prim > 0 then
               if CURRENCY_SQL.CONVERT_BY_LOCATION(O_error_message,
                                                   NULL,
                                                   NULL,
                                                   NULL,
                                                   I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                                   I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                   NULL,
                                                   L_total_chrgs_prim,
                                                   L_from_loc_currency,
                                                   'C',
                                                   NULL,
                                                   NULL) = FALSE THEN
                  return FALSE;
               else
                  I_values.from_loc_av_cost := I_values.from_loc_av_cost - L_from_loc_currency;
               end if;
            end if; --if L_total_chrgs_prim > 0
         elsif I_values.from_loc_av_cost = 0 then
            if ITEMLOC_ATTRIB_SQL.GET_WAC(O_error_message,
                                          I_values.from_loc_av_cost,
                                          I_item_rec.item,
                                          I_item_rec.dept,
                                          I_item_rec.class,
                                          I_item_rec.subclass,
                                          I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                          I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                          NULL,                  -- tran_date
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE then
               return FALSE;
            end if;
         end if;
         if STOCK_ORDER_RCV_SQL.TRANDATA_OVERAGE(O_error_message,
                                                 L_total_pack_value, --Null
                                                 NULL,               --pack_no
                                                 I_item_rec.item,
                                                 I_item_rec.dept,
                                                 I_item_rec.class,
                                                 I_item_rec.subclass,
                                                 I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                 I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                 I_item_rec.to_tsf_entity,
                                                 I_item_rec.to_finisher,
                                                 I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                                 I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                 I_item_rec.from_tsf_entity,
                                                 I_item_rec.from_finisher,
                                                 I_inv_flow_array(I_flow_cnt).overage_qty,
                                                 NULL,      -- overage_weight_cuom : Catch Weight
                                                 I_distro_no,
                                                 I_distro_type,
                                                 I_item_rec.ship_no,
                                                 I_item_rec.tran_date,
                                                 I_values.from_loc_av_cost,    -- Transfer and Item Valuation
                                                 L_profit_chrgs_to_loc,
                                                 L_exp_chrgs_to_loc,
                                                 L_intercompany,               -- Transfer and Item Valuation,
                                                 L_inventory_treatment_ind) = FALSE then
            return FALSE;
         end if;
         --
         if L_inventory_treatment_ind in ('NL','BL') then
            if UPDATE_FROM_OVERAGE(O_error_message,
                                   I_item_rec.item,
                                   'I',
                                   I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                   I_inv_flow_array(I_flow_cnt).overage_qty,
                                   NULL,           -- overage_weight_cuom : Catch Weight
                                   NULL            -- cuom : Catch Weight
                                   ) = FALSE then
               return FALSE;
            end if;
            -- If overage and non-sellable at sending location, take away
            -- the non-sellable overage from the from loc
            if NVL(I_from_inv_status, -1) != -1 then
               if STOCK_ORDER_RCV_SQL.UPD_INV_STATUS(O_error_message,
                                                     I_item_rec.item,
                                                     I_from_inv_status,
                                                     I_inv_flow_array(I_flow_cnt).overage_qty* -1,
                                                     I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                                     I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                     I_item_rec.tran_date,
                                                     I_item_rec.pack_ind) = FALSE then
                  return FALSE;
               end if;
            end if; -- if I_item_rec.inv_status != -1
         end if; -- L_inventory_treatment_ind in ('NL','BL')
      end if;  --if overage != 0
      if LP_system_options_row.rdw_ind = 'Y' then
         -- RDW specific pack tran_data write
         if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                                I_item_rec.item,
                                                I_item_rec.dept,
                                                I_item_rec.class,
                                                I_item_rec.subclass,
                                                I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                I_item_rec.tran_date,
                                                L_rdw_tran_code,
                                                NULL,
                                                I_inv_flow_array(I_flow_cnt).dist_qty,
                                                L_dummy_cost,
                                                NULL,
                                                -- V 1.04 Begin
                                                I_distro_no,          -- Ref_NO_1
                                                I_item_rec.ship_no,   -- Ref_NO_2                                                
                                            --    NULL,
                                            --    NULL,
                                                -- V 1.04 End
                                                NULL,
                                                NULL,
                                                NULL,
                                                NULL,
                                                NULL,
                                                NULL,
                                                NULL,
                                                L_pgm_name) = FALSE then
            return FALSE;
         end if;
      end if; -- if LP_system_options_row.rdw_ind = 'Y'
      LP_shipment := I_item_rec.ship_no;
      LP_tsf_type := I_item_rec.tsf_type;
      if STOCK_ORDER_RCV_SQL.UPDATE_ITEM_STOCK(O_error_message,
                                               I_distro_no,
                                               I_distro_type,
                                               I_item_rec.item,
                                               I_item_rec.dept,
                                               I_item_rec.class,
                                               I_item_rec.subclass,
                                               I_item_rec.inv_status,
                                               I_item_rec.pack_ind,
                                               NULL,  --pack no
                                               L_total_pack_value,
                                               I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                               I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                               I_values.from_loc_av_cost,                 -- Transfers and Item Valuation
                                               I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                               I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                               I_values.receive_as_type,                  --default E
                                               I_inv_flow_array(I_flow_cnt).upd_intran_qty,
                                               I_inv_flow_array(I_flow_cnt).overage_qty,
                                               NULL ,                                     -- CatchWeight: overage_weight_cuom
                                               L_total_chrgs_prim,
                                               I_inv_flow_array(I_flow_cnt).dist_qty,
                                               NULL,                                      -- CatchWeight: dist. weight
                                               NULL,                                      -- Catch Weight : CUOM
                                               I_item_rec.tran_date,
                                               L_intercompany) = FALSE then
         return FALSE;
      end if;
      if I_item_rec.to_finisher = 'Y' then
           if STOCK_ORDER_RCV_SQL.UPD_ITEM_RESV_EXP(O_error_message,
                                                    I_item_rec.item,
                                                    I_distro_no,
                                                    I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                    I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                    I_inv_flow_array(I_flow_cnt).dist_qty) = FALSE then
              return FALSE;
           end if;
      end if;  -- if I_item_rec.to_finisher = 'Y'
      if NWP_UPDATE_SQL.UPDATE_NWP_RECORD(O_error_message,
                                          I_item_rec.item,                                -- component item
                                          I_item_rec.item,                                -- component item (not at pack level)
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc,        -- to location
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc_type,   -- location type
                                          I_item_Rec.bol_no,                              -- bol no for transfer
                                          I_item_rec.ship_no,                             -- shipment
                                          I_item_rec.tran_date,                           -- I_receipt_date
                                          ROUND(I_values.input_qty,4),                    -- I_receipt_quantity
                                          ROUND(I_values.from_loc_av_cost,4),             -- I_receipt_cost
                                          NULL,                                           -- I_cost_adjust_amt
                                          NULL,                                           -- unit adjustment
                                          NULL,                                           -- I_ord_currency (looked up)
                                          NULL,                                           -- I_loc_currency (looked up)
                                          NULL,                                           -- I_ord_exchange_rate (looked up)
                                          'SO') =  FALSE then                             -- Stock Order Type
         return FALSE;
      end if;
   else -- pack_ind = 'Y'
      if I_inv_flow_array(I_flow_cnt).overage_qty != 0 then
         --if vendor pack, returns charges at the pack level
         --if buyer pack, returns summed up comp item charges
         if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS(
                             O_error_message,
                             L_pack_total_chrgs_prim,
                             L_pack_profit_chrgs_to_loc,
                             L_pack_exp_chrgs_to_loc,
                             I_distro_type,
                             I_distro_no,
                             I_item_rec.tsf_seq_no, --this will be null for allocs
                             L_shipment,
                             L_ss_seq_no,
                             I_item_rec.item,       --item (send pack in item field)
                             NULL,                  --pack_no
                             I_inv_flow_array(I_flow_cnt).vir_from_loc,
                             I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                             I_inv_flow_array(I_flow_cnt).vir_to_loc,
                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE then
            return FALSE;
         end if;
         if L_pack_total_chrgs_prim > 0 then
            if CURRENCY_SQL.CONVERT_BY_LOCATION(O_error_message,
                                                NULL,
                                                NULL,
                                                NULL,
                                                I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                                I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                NULL,
                                                L_pack_total_chrgs_prim,
                                                L_from_loc_currency,
                                                'C',
                                                NULL,
                                                NULL) = FALSE THEN
               return FALSE;
            else
               I_values.from_loc_av_cost := I_values.from_loc_av_cost - L_from_loc_currency;
            end if;
         end if; --if L_total_chrgs_prim > 0
         open C_FRM_RECEIVE_AS_TYPE;
         fetch C_FRM_RECEIVE_AS_TYPE into L_from_loc_rcv_as_type;
         close C_FRM_RECEIVE_AS_TYPE;
         -- If receiving a pack and from loc receive_as_type is 'E' then
         -- from loc is a finisher.
         -- Finishers are allowed to send packs but do not track stock at pack level.
         -- If from loc is a finisher update as item
         if L_from_loc_rcv_as_type = 'E' then
            L_update_comp_type := 'I';
         else
            L_update_comp_type := 'C';
         end if;
      end if; -- if I_inv_flow_array(I_flow_cnt).overage_qty != 0
      -- Pack level processing
      if STOCK_ORDER_RCV_SQL.PACK_LEVEL_PROC(O_error_message,
                                             I_values.receive_as_type,                      --at to loc
                                             I_values.pack_from_av_cost,
                                             I_values.pack_av_cost_ratio,
                                             I_distro_no,
                                             I_item_rec.item,
                                             I_item_rec.dept,
                                             I_item_rec.class,
                                             I_item_rec.subclass,
                                             I_item_rec.inv_status,
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                             L_from_loc_rcv_as_type,                         --default P unless from finisher
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                             I_item_rec.tran_date,
                                             I_inv_flow_array(I_flow_cnt).dist_qty,
                                             I_inv_flow_array(I_flow_cnt).upd_intran_qty,
                                             I_inv_flow_array(I_flow_cnt).overage_qty,
                                             I_inv_flow_array(I_flow_cnt).overage_weight_cuom, -- Catch Weight
                                             I_inv_flow_array(I_flow_cnt).cuom,                --Catch Weight
                                             L_pack_total_chrgs_prim,
                                             I_values.from_loc_av_cost,
                                             I_from_inv_status,
                                             L_store_type,
                                             L_inventory_treatment_ind) = FALSE then
         return FALSE;
      end if;
      if STOCK_ORDER_RCV_SQL.LOAD_COMPS(O_error_message,
                                        L_comp_items,
                                        I_item_rec.item,
                                        I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                        I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                        I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                        I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE then
         return FALSE;
      end if;
      -- Loop on the pack's comp items
      FOR comp_cnt IN L_comp_items.FIRST..L_comp_items.LAST LOOP
         if I_inv_flow_array(I_flow_cnt).overage_qty != 0 then
          -- Transfer and Item Valuation
            if TRANSFER_COST_SQL.PCT_IN_PACK(O_error_message,
                                             L_percent_in_pack,
                                             I_item_rec.item,   -- pack_no
                                             L_comp_items(comp_cnt).comp_item,
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc) = FALSE then
               return FALSE;
            end if;
            if I_values.from_loc_av_cost > 0 then
               L_comp_wac := I_values.from_loc_av_cost * L_percent_in_pack;
            elsif I_values.from_loc_av_cost = 0 then
               L_comp_wac := L_comp_items(comp_cnt).comp_from_loc_av_cost;
            end if;
           -- End Transfer and Item Valuation
            if I_item_rec.pack_type != 'B' then
               ---
               -- prorate the charges calculated at the pack level across the comp items
               -- need to use pack's av_cost not on shipsku --it does not have charges in it
               --******************************************************************************
               -- Value returned in L_pack_profit_chrgs_to_loc, L_pack_exp_chrgs_to_loc, and
               -- L_pack_total_chrgs_prim are unit values for the entire pack.  Need to take
               -- a proportionate piece of the value for each component item in the pack
               -- The formula for this is:
               --       [Pack Value * (Comp Item Avg Cost * Comp Qty in the Pack) /
               --                     (Total Pack Avg Cost)] /
               --       Comp Qty in the Pack
               -- You must divide the value by the Component Item Qty in the pack because the
               -- value will be for one pack.  In order to get a true unit value you need to
               -- do the last division.  Since we multiple by Comp Qty and then divide by it,
               -- it can be removed from the calculation completely.
               --******************************************************************************
               L_profit_chrgs_to_loc := L_pack_profit_chrgs_to_loc *
                                        L_comp_items(comp_cnt).comp_from_loc_av_cost /
                                        I_values.pack_from_av_cost;
               L_exp_chrgs_to_loc    := L_pack_exp_chrgs_to_loc *
                                        L_comp_items(comp_cnt).comp_from_loc_av_cost /
                                        I_values.pack_from_av_cost;
               L_total_chrgs_prim    := L_pack_total_chrgs_prim *
                                        L_comp_items(comp_cnt).comp_from_loc_av_cost /
                                        I_values.pack_from_av_cost;
            else
               if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS(
                                   O_error_message,
                                   L_total_chrgs_prim,
                                   L_profit_chrgs_to_loc,
                                   L_exp_chrgs_to_loc,
                                   I_distro_type,
                                   I_distro_no,
                                   I_item_rec.tsf_seq_no,            --this will be null for allocs
                                   L_shipment,
                                   L_ss_seq_no,
                                   L_comp_items(comp_cnt).comp_item, --item
                                   I_item_rec.item,                  --pack_no
                                   I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                   I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                   I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                   I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE then
                  return FALSE;
               end if;
            end if; -- if I_item_rec.pack_type != 'B'
            if STOCK_ORDER_RCV_SQL.TRANDATA_OVERAGE(O_error_message,
                                                    L_total_pack_value,
                                                    I_item_rec.item,
                                                    L_comp_items(comp_cnt).comp_item,
                                                    L_comp_items(comp_cnt).comp_dept,
                                                    L_comp_items(comp_cnt).comp_class,
                                                    L_comp_items(comp_cnt).comp_subclass,
                                                    I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                    I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                    I_item_rec.to_tsf_entity,
                                                    I_item_rec.to_finisher,                          --null for alloc
                                                    I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                                    I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                    I_item_rec.from_tsf_entity,
                                                    I_item_rec.from_finisher,
                                                    L_comp_items(comp_cnt).comp_qty *
                                                    I_inv_flow_array(I_flow_cnt).overage_qty,
                                                    I_inv_flow_array(I_flow_cnt).overage_weight_cuom, -- Catch Weight
                                                    I_distro_no,
                                                    I_distro_type,
                                                    I_item_rec.ship_no,
                                                    I_item_rec.tran_date,
                                                    L_comp_wac,                                      -- Transfers and Item Valuation
                                                    L_profit_chrgs_to_loc,
                                                    L_exp_chrgs_to_loc,
                                                    L_intercompany,                                  -- Transfers and Item Valuation
                                                    L_inventory_treatment_ind) = FALSE then
               return FALSE;
            end if;
            if L_inventory_treatment_ind in ('NL','BL') then
               if UPDATE_FROM_OVERAGE(O_error_message,
                                      L_comp_items(comp_cnt).comp_item,
                                      L_update_comp_type,
                                      I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                      I_inv_flow_array(I_flow_cnt).overage_qty *
                                         L_comp_items(comp_cnt).comp_qty,
                                      I_inv_flow_array(I_flow_cnt).overage_weight_cuom,-- Catch Weight
                                      I_inv_flow_array(I_flow_cnt).cuom                --Catch Weight
                                      ) = FALSE then
                  return FALSE;
               end if;
            end if;
            -- there is no need to do the upd_inv_status call for the from loc at the comp level
            -- when the item on the transfer is a pack, its always done at the pack level
         end if; -- if I_inv_flow_array(I_flow_cnt).overage_qty != 0
         if LP_system_options_row.rdw_ind = 'Y' then
            -- RDW specific pack tran_data write
            if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                                   L_comp_items(comp_cnt).comp_item,
                                                   L_comp_items(comp_cnt).comp_dept,
                                                   L_comp_items(comp_cnt).comp_class,
                                                   L_comp_items(comp_cnt).comp_subclass,
                                                   I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                   I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                   I_item_rec.tran_date,
                                                   L_rdw_tran_code,
                                                   NULL,
                                                   L_comp_items(comp_cnt).comp_qty *
                                                   I_inv_flow_array(I_flow_cnt).dist_qty,
                                                   L_dummy_cost,
                                                   NULL,
                                                   -- V 1.04 Begin
                                                   I_distro_no,          -- Ref_NO_1
                                                   I_item_rec.ship_no,   -- Ref_NO_2                                                
                                               --    NULL,
                                               --    NULL,
                                                   -- V 1.04 End
                                                   NULL,
                                                   NULL,
                                                   NULL,
                                                   NULL,
                                                   NULL,
                                                   NULL,
                                                   NULL,
                                                   L_pgm_name) = FALSE then
               return FALSE;
            end if;
         end if;  --- if LP_system_options_row.rdw_ind = 'Y'
         LP_shipment := I_item_rec.ship_no;
         LP_tsf_type := I_item_rec.tsf_type;
         if L_comp_items(comp_cnt).comp_inventory_ind ='Y' then
            if STOCK_ORDER_RCV_SQL.UPDATE_ITEM_STOCK(O_error_message,
                                                     I_distro_no,
                                                     I_distro_type,
                                                     L_comp_items(comp_cnt).comp_item,
                                                     L_comp_items(comp_cnt).comp_dept,
                                                     L_comp_items(comp_cnt).comp_class,
                                                     L_comp_items(comp_cnt).comp_subclass,
                                                     I_item_rec.inv_status,
                                                     I_item_rec.pack_ind,
                                                     I_item_rec.item,                                      --pack no
                                                     L_total_pack_value,                                   --pack value
                                                     I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                                     I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                                     L_comp_wac,                            -- Transfers and Item Valuation
                                                     I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                     I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                     I_values.receive_as_type,                             --at to loc
                                                     L_comp_items(comp_cnt).comp_qty *
                                                                 I_inv_flow_array(I_flow_cnt).upd_intran_qty,
                                                     L_comp_items(comp_cnt).comp_qty *
                                                                 I_inv_flow_array(I_flow_cnt).overage_qty,
                                                     I_inv_flow_array(I_flow_cnt).overage_weight_cuom,     --CatchWeight
                                                     L_total_chrgs_prim,
                                                     L_comp_items(comp_cnt).comp_qty *
                                                                 I_inv_flow_array(I_flow_cnt).dist_qty,
                                                     I_inv_flow_array(I_flow_cnt).dist_weight_cuom,        --CatchWeight: dist_weight
                                                     I_inv_flow_array(I_flow_cnt).cuom,                    --Catch Weight
                                                     I_item_rec.tran_date,
                                                     L_intercompany) = FALSE then
               return FALSE;
            end if;
         end if;
         if I_item_rec.to_finisher is not NULL and I_item_rec.to_finisher = 'Y' then
            if STOCK_ORDER_RCV_SQL.UPD_ITEM_RESV_EXP(O_error_message,
                                                     L_comp_items(comp_cnt).comp_item,
                                                     I_distro_no,
                                                     I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                     I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                     L_comp_items(comp_cnt).comp_qty *
                                                     I_inv_flow_array(I_flow_cnt).dist_qty) = FALSE then
               return FALSE;
            end if;
         end if;
         if NWP_UPDATE_SQL.UPDATE_NWP_RECORD(O_error_message,
                                             L_comp_items(comp_cnt).comp_item ,                   -- item
                                             I_item_rec.item,                                     -- pack item
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc,             -- to location
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type,        -- location type
                                             I_item_Rec.bol_no,                                   -- bol no for transfer
                                             I_item_rec.ship_no,                                  -- shipment
                                             I_item_rec.tran_date,                                -- I_receipt_date
                                             ROUND(L_comp_items(comp_cnt).comp_qty *
                                                 I_inv_flow_array(I_flow_cnt).dist_qty,4),        -- I_receipt_quantity
                                             ROUND(L_comp_items(comp_cnt).comp_from_loc_av_cost *
                                                    I_values.pack_av_cost_ratio,4),               -- I_receipt_cost
                                             NULL,                                                -- I_cost_adjust_amt
                                             NULL,                                                -- unit adjustment
                                             NULL,                                                -- I_ord_currency (looked up)
                                             NULL,                                                -- I_loc_currency (looked up)
                                             NULL,                                                -- I_ord_exchange_rate (looked up)
                                             'SO') =  FALSE then                                  -- Stock order type
           return FALSE;
         end if;
      END LOOP;
   end if; -- if pack_ind = 'N'
   /* Flush the TRAN_DATA_INSERT */
   if STKLEDGR_SQL.FLUSH_TRAN_DATA_INSERT (O_error_message) = FALSE then
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.DETAIL_METHOD',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END DETAIL_METHOD;
--------------------------------------------------------------------------------
FUNCTION WF_DETAIL_PROCESSING(O_error_message   IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                              I_item_rec        IN OUT STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                              I_values          IN OUT STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                              I_inv_flow_array  IN     STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY,
                              I_flow_cnt        IN     BINARY_INTEGER,
                              I_distro_no       IN     SHIPSKU.DISTRO_NO%TYPE,
                              I_distro_type     IN     APPT_DETAIL.DOC_TYPE%TYPE,
                              I_from_inv_status IN     TSFDETAIL.INV_STATUS%TYPE)
RETURN BOOLEAN IS
   L_comp_items   stock_order_rcv_sql.comp_item_array;
   comp_cnt       BINARY_INTEGER                                      := 0;
   L_cycle_count  stake_head.cycle_count%TYPE                         := NULL;
   L_pack_total_chrgs_prim      item_loc.unit_retail%TYPE               := 0;
   L_pack_profit_chrgs_to_loc   item_loc.unit_retail%TYPE               := 0;
   L_pack_exp_chrgs_to_loc      item_loc.unit_retail%TYPE               := 0;
   L_total_chrgs_prim           item_loc.unit_retail%TYPE               := 0;
   L_profit_chrgs_to_loc        item_loc.unit_retail%TYPE               := 0;
   L_exp_chrgs_to_loc           item_loc.unit_retail%TYPE               := 0;
   L_shipment                   shipment.shipment%TYPE                  := NULL;
   L_ss_seq_no                  shipsku.seq_no%TYPE                     := NULL;
   L_intercompany               BOOLEAN                                 := FALSE;
   L_total_pack_value           item_loc_soh.unit_cost%TYPE             := NULL;
   L_comp_wac                   item_loc_soh.av_cost%TYPE               := NULL; -- Transfer and Item Valuation
   L_from_loc_currency          item_loc.unit_retail%TYPE               := 0;    -- Transfer and Item Valuation
   L_percent_in_pack            NUMBER;                                          -- Transfer and Item Valuation
   --specific pack level overage processing
   L_from_loc_rcv_as_type       item_loc.receive_as_type%TYPE           := 'P';
   L_update_comp_type           VARCHAR2(1)                             := 'C';
   L_rdw_tran_code              tran_data.tran_code%TYPE                := 44;
   L_dummy_cost                 item_loc_soh.av_cost%TYPE               := NULL;
   L_inventory_treatment_ind    SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE := NULL;
   L_store_type                 STORE.STORE_TYPE%TYPE                   := 'C';
   L_pgm_name                   tran_data.pgm_name%TYPE                 := 'STOCK_ORDER_RCV_SQL.WF_DETAIL_PROCESSING';
   -- specific to update_wf_return
   L_item_record                item_master%rowtype;
BEGIN
   if I_item_rec.pack_ind = 'N' then
      if LP_system_options_row.rdw_ind = 'Y' then
         -- RDW specific pack tran_data write
         if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                                I_item_rec.item,
                                                I_item_rec.dept,
                                                I_item_rec.class,
                                                I_item_rec.subclass,
                                                I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                I_item_rec.tran_date,
                                                L_rdw_tran_code,
                                                NULL,
                                                I_inv_flow_array(I_flow_cnt).dist_qty,
                                                L_dummy_cost,
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
                                                L_pgm_name) = FALSE then
            return FALSE;
         end if;
      end if; -- if LP_system_options_row.rdw_ind = 'Y'
      LP_shipment := I_item_rec.ship_no;
      LP_tsf_type := I_item_rec.tsf_type;
      if STOCK_ORDER_RCV_SQL.UPDATE_ITEM_STOCK(O_error_message,
                                               I_distro_no,
                                               I_distro_type,
                                               I_item_rec.item,
                                               I_item_rec.dept,
                                               I_item_rec.class,
                                               I_item_rec.subclass,
                                               I_item_rec.inv_status,
                                               I_item_rec.pack_ind,
                                               NULL,  --pack no
                                               L_total_pack_value,
                                               I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                               I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                               I_values.from_loc_av_cost,                 -- Transfers and Item Valuation
                                               I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                               I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                               I_values.receive_as_type,                  --default E
                                               I_inv_flow_array(I_flow_cnt).upd_intran_qty,
                                               I_inv_flow_array(I_flow_cnt).overage_qty,
                                               NULL ,                                     -- CatchWeight: overage_weight_cuom
                                               L_total_chrgs_prim,
                                               I_inv_flow_array(I_flow_cnt).dist_qty,
                                               NULL,                                      -- CatchWeight: dist. weight
                                               NULL,                                      -- Catch Weight : CUOM
                                               I_item_rec.tran_date,
                                               L_intercompany) = FALSE then
         return FALSE;
      end if;
      if NWP_UPDATE_SQL.UPDATE_NWP_RECORD(O_error_message,
                                          I_item_rec.item,                                -- component item
                                          I_item_rec.item,                                -- component item (not at pack level)
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc,        -- to location
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc_type,   -- location type
                                          I_item_Rec.bol_no,                              -- bol no for transfer
                                          I_item_rec.ship_no,                             -- shipment
                                          I_item_rec.tran_date,                           -- I_receipt_date
                                          ROUND(I_values.input_qty,4),                     -- I_receipt_quantity
                                          ROUND(I_values.from_loc_av_cost,4),             -- I_receipt_cost
                                          NULL,                                           -- I_cost_adjust_amt
                                          NULL,                                           -- unit adjustment
                                          NULL,                                           -- I_ord_currency (looked up)
                                          NULL,                                           -- I_loc_currency (looked up)
                                          NULL,                                           -- I_ord_exchange_rate (looked up)
                                          'SO') =  FALSE then                             -- Stock Order Type
         return FALSE;
      end if;
      ---
      if STKLEDGR_SQL.WF_WRITE_FINANCIALS(O_error_message,
                                          I_distro_no,
                                          I_item_rec.tran_date,
                                          I_item_rec.item,                 -- component item
                                          NULL,                            -- component item (not at pack level)
                                          0,                               -- percent in pack
                                          I_item_rec.dept,
                                          I_item_rec.class,
                                          I_item_rec.subclass,
                                          ROUND(I_values.input_qty,4),
                                          I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                          I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                          NULL,
                                          NULL) = FALSE then
         return FALSE;
      end if;
      ---
   else -- pack_ind = 'Y'
      -- Pack level processing
      if STOCK_ORDER_RCV_SQL.PACK_LEVEL_PROC(O_error_message,
                                             I_values.receive_as_type,                      --at to loc
                                             I_values.pack_from_av_cost,
                                             I_values.pack_av_cost_ratio,
                                             I_distro_no,
                                             I_item_rec.item,
                                             I_item_rec.dept,
                                             I_item_rec.class,
                                             I_item_rec.subclass,
                                             I_item_rec.inv_status,
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                             L_from_loc_rcv_as_type,                         --default P unless from finisher
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                             I_item_rec.tran_date,
                                             I_inv_flow_array(I_flow_cnt).dist_qty,
                                             I_inv_flow_array(I_flow_cnt).upd_intran_qty,
                                             I_inv_flow_array(I_flow_cnt).overage_qty,
                                             I_inv_flow_array(I_flow_cnt).overage_weight_cuom, -- Catch Weight
                                             I_inv_flow_array(I_flow_cnt).cuom,                --Catch Weight
                                             L_pack_total_chrgs_prim,
                                             I_values.from_loc_av_cost,
                                             I_from_inv_status,
                                             L_store_type,
                                             L_inventory_treatment_ind) = FALSE then
         return FALSE;
      end if;
      if STOCK_ORDER_RCV_SQL.LOAD_COMPS(O_error_message,
                                        L_comp_items,
                                        I_item_rec.item,
                                        I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                        I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                        I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                        I_inv_flow_array(I_flow_cnt).vir_to_loc_type) = FALSE then
         return FALSE;
      end if;
      -- Loop on the pack's comp items
      FOR comp_cnt IN L_comp_items.FIRST..L_comp_items.LAST LOOP
         if LP_system_options_row.rdw_ind = 'Y' then
            -- RDW specific pack tran_data write
            if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                                   L_comp_items(comp_cnt).comp_item,
                                                   L_comp_items(comp_cnt).comp_dept,
                                                   L_comp_items(comp_cnt).comp_class,
                                                   L_comp_items(comp_cnt).comp_subclass,
                                                   I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                                   I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                                   I_item_rec.tran_date,
                                                   L_rdw_tran_code,
                                                   NULL,
                                                   L_comp_items(comp_cnt).comp_qty *
                                                   I_inv_flow_array(I_flow_cnt).dist_qty,
                                                   L_dummy_cost,
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
                                                   L_pgm_name) = FALSE then
               return FALSE;
            end if;
         end if;  --- if LP_system_options_row.rdw_ind = 'Y'
         LP_shipment := I_item_rec.ship_no;
         LP_tsf_type := I_item_rec.tsf_type;
         if L_comp_items(comp_cnt).comp_inventory_ind ='Y' then
            if STOCK_ORDER_RCV_SQL.UPDATE_ITEM_STOCK(
                             O_error_message,
                             I_distro_no,
                             I_distro_type,
                             L_comp_items(comp_cnt).comp_item,
                             L_comp_items(comp_cnt).comp_dept,
                             L_comp_items(comp_cnt).comp_class,
                             L_comp_items(comp_cnt).comp_subclass,
                             I_item_rec.inv_status,
                             I_item_rec.pack_ind,
                             I_item_rec.item,                                      --pack no
                             L_total_pack_value,                                   --pack value
                             I_inv_flow_array(I_flow_cnt).vir_from_loc,
                             I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                             L_comp_wac,                                           -- Transfers and Item Valuation
                             I_inv_flow_array(I_flow_cnt).vir_to_loc,
                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                             I_values.receive_as_type,                             --at to loc
                             L_comp_items(comp_cnt).comp_qty *
                                I_inv_flow_array(I_flow_cnt).upd_intran_qty,
                             L_comp_items(comp_cnt).comp_qty *
                                I_inv_flow_array(I_flow_cnt).overage_qty,
                             I_inv_flow_array(I_flow_cnt).overage_weight_cuom,     --CatchWeight
                             L_total_chrgs_prim,
                             L_comp_items(comp_cnt).comp_qty *
                                I_inv_flow_array(I_flow_cnt).dist_qty,
                             I_inv_flow_array(I_flow_cnt).dist_weight_cuom,        --CatchWeight: dist_weight
                             I_inv_flow_array(I_flow_cnt).cuom,                    --Catch Weight
                             I_item_rec.tran_date,
                             L_intercompany) = FALSE then
               return FALSE;
            end if;
         end if;
         if NWP_UPDATE_SQL.UPDATE_NWP_RECORD( O_error_message  ,
                                             L_comp_items(comp_cnt).comp_item,                    -- item
                                             I_item_rec.item,                                     -- pack item
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc,             -- to location
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type,        -- location type
                                             I_item_Rec.bol_no,                                   -- bol no for transfer
                                             I_item_rec.ship_no,                                  -- shipment
                                             I_item_rec.tran_date,                                -- I_receipt_date
                                             ROUND(L_comp_items(comp_cnt).comp_qty *
                                                 I_inv_flow_array(I_flow_cnt).dist_qty,4),        -- I_receipt_quantity
                                             ROUND(L_comp_items(comp_cnt).comp_from_loc_av_cost *
                                                    I_values.pack_av_cost_ratio,4),               -- I_receipt_cost
                                             NULL,                                                -- I_cost_adjust_amt
                                             NULL,                                                -- unit adjustment
                                             NULL,                                                -- I_ord_currency (looked up)
                                             NULL,                                                -- I_loc_currency (looked up)
                                             NULL,                                                -- I_ord_exchange_rate (looked up)
                                             'SO') =  FALSE then                                  -- Stock order type
           return FALSE;
         end if;
         ---
         if TRANSFER_COST_SQL.PCT_IN_PACK(O_error_message,
                                          L_percent_in_pack,
                                          I_item_rec.item,
                                          L_comp_items(comp_cnt).comp_item,
                                          I_inv_flow_array(I_flow_cnt).vir_to_loc) = FALSE then
            return FALSE;
         end if;
         if STKLEDGR_SQL.WF_WRITE_FINANCIALS(O_error_message,
                                             I_distro_no,
                                             I_item_rec.tran_date,
                                             L_comp_items(comp_cnt).comp_item,               -- component item
                                             I_item_rec.item,                                -- component item (not at pack level)
                                             L_percent_in_pack,                              -- percent in_pack
                                             L_comp_items(comp_cnt).comp_dept,
                                             L_comp_items(comp_cnt).comp_class,
                                             L_comp_items(comp_cnt).comp_subclass,
                                             ROUND(L_comp_items(comp_cnt).comp_qty *
                                                   I_inv_flow_array(I_flow_cnt).dist_qty,4),
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc,
                                             I_inv_flow_array(I_flow_cnt).vir_from_loc_type,
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc,
                                             I_inv_flow_array(I_flow_cnt).vir_to_loc_type,
                                             I_inv_flow_array(I_flow_cnt).overage_weight_cuom,
                                             NULL) = FALSE then
            return FALSE;
         end if;
         ---
      END LOOP;
   end if; -- if pack_ind = 'N'
   update tsfdetail td
      set td.tsf_qty      = NVL(td.tsf_qty, 0) - (NVL(td.tsf_qty, 0) - I_values.input_qty),
          td.ship_qty     = NVL(td.ship_qty, 0) - (NVL(td.ship_qty, 0) - I_values.input_qty),
          td.received_qty = NVL(td.received_qty, 0) + I_values.input_qty
    where td.tsf_no = I_distro_no
      and td.item   = I_item_rec.item;
   -- Set the variables in item record to pass it to  UPDATE_WF_BILLING
   if ITEM_ATTRIB_SQL.GET_ITEM_MASTER(O_error_message,
                                      L_item_record,
                                      I_item_rec.item) = FALSE then
      return FALSE;
   end if;
   -- Update Wholesale Franchise billing
   if UPDATE_WF_BILLING (O_error_message,
                         L_item_record,
                         I_distro_no,
                         I_distro_type,
                         NULL,
                         NULL) = FALSE then
      return FALSE;
   end if;
   -- Update Wholesale Franchise Returns
   if UPDATE_WF_RETURN (O_error_message,
                        L_item_record,
                        I_distro_no,
                        I_distro_type,
                        I_values.input_qty) = FALSE then
      return FALSE;
   end if;
   /* Flush the TRAN_DATA_INSERT */
   if STKLEDGR_SQL.FLUSH_TRAN_DATA_INSERT (O_error_message) = FALSE then
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.DETAIL_PROCESSING',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END WF_DETAIL_PROCESSING;
-------------------------------------------------------------------------------
FUNCTION UPDATE_ITEM_STOCK(O_error_message     IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_distro_no         IN      SHIPSKU.DISTRO_NO%TYPE,
                           I_distro_type       IN      APPT_DETAIL.DOC_TYPE%TYPE,
                           I_item              IN      ITEM_MASTER.ITEM%TYPE,
                           I_dept              IN      ITEM_MASTER.DEPT%TYPE,
                           I_class             IN      ITEM_MASTER.CLASS%TYPE,
                           I_subclass          IN      ITEM_MASTER.SUBCLASS%TYPE,
                           I_inv_status        IN      SHIPSKU.INV_STATUS%TYPE,
                           I_pack_ind          IN      ITEM_MASTER.PACK_IND%TYPE,
                           I_pack_no           IN      ITEM_MASTER.ITEM%TYPE,
                           IO_pack_value       IN OUT  ITEM_LOC_SOH.UNIT_COST%TYPE,
                           I_from_loc          IN      ITEM_LOC.LOC%TYPE,
                           I_from_loc_type     IN      ITEM_LOC.LOC_TYPE%TYPE,
                           I_from_loc_wac      IN      ITEM_LOC_SOH.AV_COST%TYPE,           -- Transfers and Item Valuation
                           I_to_loc            IN      ITEM_LOC.LOC%TYPE,
                           I_to_loc_type       IN      ITEM_LOC.LOC_TYPE%TYPE,
                           I_receive_as_type   IN      ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                           I_upd_intran_qty    IN      ITEM_LOC_SOH.IN_TRANSIT_QTY%TYPE,
                           I_upd_av_cost_qty   IN      TSFDETAIL.RECEIVED_QTY%TYPE,
                           I_upd_av_cost_wgt   IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,    -- CatchWeight
                           I_prim_charge       IN      ITEM_LOC_SOH.AV_COST%TYPE,
                           I_received_qty      IN      TSFDETAIL.RECEIVED_QTY%TYPE,
                           I_received_wgt_cuom IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,    -- Catch Weight: distributed weight
                           I_cuom              IN      ITEM_SUPP_COUNTRY.COST_UOM%TYPE,     -- Catch Weight: distributed weight
                           I_tran_date         IN      PERIOD.VDATE%TYPE,
                           I_intercompany      IN      BOOLEAN)
   RETURN BOOLEAN IS
   L_vdate                  DATE := GET_VDATE;
   L_neg_soh_wac_adj_amt    ITEM_LOC_SOH.AV_COST%TYPE;
   L_local_from_loc_av_cost ITEM_LOC_SOH.AV_COST%TYPE;
   L_charge_to_loc          ITEM_LOC_SOH.AV_COST%TYPE;
   L_percent_in_pack        NUMBER;
   L_to_store               ITEM_LOC.LOC%TYPE;
   L_to_wh                  ITEM_LOC.LOC%TYPE;
   L_from_store             ITEM_LOC.LOC%TYPE;
   L_from_wh                ITEM_LOC.LOC%TYPE;
   L_upd_av_cost_qty       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;     -- Catch Weight
   L_upd_soh_qty           ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;
   L_upd_qty               ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;     -- Catch Weight
   L_item_type             VARCHAR2(1) := NULL;
   L_upd_flag              VARCHAR2(1) := NULL;
   L_stock_count_processed BOOLEAN                     := FALSE;
   L_cycle_count           STAKE_HEAD.CYCLE_COUNT%TYPE := NULL;
   L_snapshot_cost         ITEM_LOC_SOH.AV_COST%TYPE   := 0;
   L_snapshot_retail       ITEM_LOC.UNIT_RETAIL%TYPE   := 0;
   L_new_wac               ITEM_LOC_SOH.AV_COST%TYPE;           -- Catch Weight
   L_upd_intran_qty        ITEM_LOC_SOH.IN_TRANSIT_QTY%TYPE;    -- Catch Weight
   L_ship_qty              TSFDETAIL.SHIP_QTY%TYPE     := 0;
   L_packsku_qty           NUMBER                      := 0;
   L_avg_weight_to         ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE := NULL;
   L_soh_curr              ITEM_LOC_SOH.STOCK_ON_HAND%TYPE  := NULL;
   L_avg_weight_new        ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE := NULL;
   L_rowid                 ROWID;
   L_table                 VARCHAR2(30);
   L_key1                  VARCHAR2(100);
   L_key2                  VARCHAR2(100);
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
   L_finisher_loc_ind      VARCHAR2(1);
   L_finisher_entity_ind   VARCHAR2(1);
   L_expected_qty          ITEM_LOC_SOH.STOCK_ON_HAND%TYPE; -- For adjusting the over receipt qty
   L_tsf_type              TSFHEAD.TSF_TYPE%TYPE;
  -- cursors
   cursor C_LOCK_ITEM_LOC_SOH is
      select ils.rowid,
             ils.stock_on_hand + ils.in_transit_qty + ils.pack_comp_intran + ils.pack_comp_soh total_soh,
             ils.average_weight
        from item_loc_soh ils
       where ils.item = I_item
         and ils.loc  = I_to_loc
         for update nowait;
   cursor C_TSF_TYPE is
      select tsf_type
        from tsfhead
       where tsf_no = I_distro_no;
   cursor C_SHIP_QTY is
      select NVL(ship_qty, 0)
        from tsfdetail
       where tsf_no = I_distro_no
         and item = decode(I_pack_ind,'Y',I_pack_no,I_item);
   cursor C_PACKSKU_QTY is
      select qty
        from v_packsku_qty
       where pack_no = I_pack_no
         and item = I_item;
BEGIN
   L_table := 'ITEM_LOC_SOH';
   L_key1 := I_item;
   L_key2 := to_char(I_to_loc);
   open C_TSF_TYPE;
   fetch C_TSF_TYPE into L_tsf_type;
   close C_TSF_TYPE;
   open C_LOCK_ITEM_LOC_SOH;
   fetch C_LOCK_ITEM_LOC_SOH into L_rowid,
                                  L_soh_curr,
                                  L_avg_weight_to;
   close C_LOCK_ITEM_LOC_SOH;
   -- If the receipt took place during a stock count that is now closed
   -- special processing is needed.  When the stock count was completed, it
   -- included the stock contained in the receipt currently being processed.
   -- Since RMS didn't know about the receipt adjustments were made and the
   -- stock_on_hand was updated to reflect the qty in the count that RMS was
   -- not aware of.
   --
   -- When a receipt comes in under there circumstances we do not want to
   -- update stock_on_hand -- it already has been accounted for.  We do want
   -- to write a adjustment to tran_data.  This tran_data write essentially
   -- reverses the tran_data that was written to explain the stock counts
   -- discrepancy.
   if I_tran_date < L_vdate then
      if STKCNT_ATTRIB_SQL.STOCK_COUNT_PROCESSED(O_error_message,
                                                 L_stock_count_processed,
                                                 L_cycle_count,
                                                 L_snapshot_cost,
                                                 L_snapshot_retail,
                                                 I_tran_date,
                                                 I_item,
                                                 I_to_loc_type,
                                                 I_to_loc) = FALSE then
         return FALSE;
      end if;
      if L_stock_count_processed = TRUE then
         if STOCK_ORDER_RCV_SQL.PROC_STK_CNT_TD_WRITE(O_error_message,
                                                      I_distro_no,
                                                      L_cycle_count,
                                                      I_item,
                                                      I_dept,
                                                      I_class,
                                                      I_subclass,
                                                      I_to_loc,
                                                      I_to_loc_type,
                                                      I_received_qty,
                                                      L_snapshot_retail,
                                                      L_snapshot_cost,
                                                      I_tran_date) = FALSE then
            return FALSE;
         end if;
      end if;
   end if;
   if I_upd_av_cost_qty != 0 then
      if I_pack_no is not NULL then
         if TRANSFER_COST_SQL.PCT_IN_PACK(O_error_message,
                                          L_percent_in_pack,
                                          I_pack_no,
                                          I_item,
                                          I_from_loc) = FALSE then
            return FALSE;
         end if;
      end if;
      --convert chrg from primary to to_loc's currency
      if CURRENCY_SQL.CONVERT_BY_LOCATION(O_error_message,
                                          NULL,
                                          NULL,
                                          NULL,
                                          I_to_loc,
                                          I_to_loc_type,
                                          NULL,
                                          I_prim_charge,
                                          L_charge_to_loc,
                                          'C',
                                          NULL,
                                          NULL) = FALSE then
         return FALSE;
      end if;
      if I_upd_av_cost_wgt is NOT NULL then
         if CATCH_WEIGHT_SQL.CALC_COMP_UPDATE_QTY(O_error_message,
                                                  L_upd_av_cost_qty,
                                                  I_item,
                                                  I_upd_av_cost_qty,
                                                  I_upd_av_cost_wgt,
                                                  I_cuom) = FALSE then
             return FALSE;
         end if;
         if NOT CATCH_WEIGHT_SQL.CALC_AVERAGE_WEIGHT(O_error_message,
                                                     L_avg_weight_new,
                                                     I_item,
                                                     I_to_loc,
                                                     I_to_loc_type,
                                                     L_soh_curr,
                                                     L_avg_weight_to,
                                                     I_received_qty,
                                                     I_received_wgt_cuom,
                                                     NULL) then
             return FALSE;
         end if;
      else
         L_upd_av_cost_qty := I_upd_av_cost_qty;
      end if;
--      if L_tsf_type NOT IN ('WR', 'FR') then -- OLR V1.03 Removed
      if L_tsf_type NOT IN ('WR', 'FR') or L_tsf_type is NULL then -- OLR V1.03 Inserted
         if TRANSFER_COST_SQL.RECALC_WAC(O_error_message,
                                         L_new_wac,                        -- Catch Weight
                                         I_distro_no,
                                         I_distro_type,
                                         I_item,
                                         I_pack_no,
                                         L_percent_in_pack,
                                         I_from_loc,
                                         I_from_loc_type,
                                         I_to_loc,
                                         I_to_loc_type,
                                         L_upd_av_cost_qty,
                                         I_upd_av_cost_wgt,                --CatchWeight
                                         I_from_loc_wac,                   --CatchWeight
                                         L_charge_to_loc,
                                         I_intercompany) = FALSE then
            return FALSE;
         end if;
      end if;
   else -- I_upd_av_cost_qty = 0
      -- set to 0 for av_cost update
      L_upd_av_cost_qty := 0;
   end if;
   --if a completed stock count was found, the qty was already accounted
   --for by the stock count
   if I_received_wgt_cuom is NOT NULL then
      if CATCH_WEIGHT_SQL.CALC_COMP_UPDATE_QTY(O_error_message,
                                               L_upd_qty,
                                               I_item,
                                               I_received_qty,
                                               I_received_wgt_cuom,
                                               I_cuom) = FALSE then
         return FALSE;
      end if;
      if L_stock_count_processed = TRUE then
         L_upd_soh_qty := 0;
      else
         L_upd_soh_qty := L_upd_qty;
      end if;
      L_upd_intran_qty := L_upd_qty/I_received_qty * I_upd_intran_qty;
   else
      if L_stock_count_processed = TRUE then
         L_upd_soh_qty := 0;
      else
         L_upd_soh_qty := I_received_qty;
      end if;
      L_upd_intran_qty := I_upd_intran_qty;
   end if;
   if I_to_loc_type = 'S' then
      L_upd_flag := 'I';
   elsif I_to_loc_type = 'W' then
      if I_receive_as_type = 'P' then
         L_upd_flag := 'P';
      else
         L_upd_flag := 'I';
      end if;
   else --to loc is an 'E'xternal finisher
      L_upd_flag := 'I';
   end if;
   ---
   if TRANSFER_SQL.GET_FINISHER_INFO(O_error_message,
                                     L_finisher_loc_ind,
                                     L_finisher_entity_ind,
                                     I_distro_no)= FALSE then
      raise PROGRAM_ERROR;
   end if;
   if L_finisher_loc_ind is NOT NULL then
      if BOL_SQL.PUT_ILS_AV_RETAIL(O_error_message,
                                   I_to_loc,
                                   I_to_loc_type,
                                   I_item,
                                   LP_shipment,
                                   I_distro_no,
                                   LP_tsf_type,
                                   L_upd_soh_qty) = FALSE then
         return FALSE;
      end if;
   end if;
   ---
   update item_loc_soh
      set stock_on_hand    = DECODE(L_upd_flag,
                                    'P', stock_on_hand,
                                    stock_on_hand + L_upd_soh_qty),
          pack_comp_soh    = DECODE(L_upd_flag,
                                    'P', pack_comp_soh + L_upd_soh_qty,
                                    pack_comp_soh),
          in_transit_qty   = DECODE(L_upd_flag,
                                   'P', in_transit_qty,
                                    in_transit_qty - L_upd_intran_qty),
          pack_comp_intran = DECODE(L_upd_flag,
                                    'P', pack_comp_intran - L_upd_intran_qty,
                                    pack_comp_intran),
          av_cost          = DECODE(L_upd_av_cost_qty,
                                    0, av_cost,
                                    ROUND(L_new_wac, 4)),
          average_weight       = NVL(L_avg_weight_new, average_weight),
          last_update_id       = USER,
          last_update_datetime = SYSDATE,
          soh_update_datetime  = DECODE(L_upd_flag,
                                        'P', soh_update_datetime,
                                        DECODE(L_upd_soh_qty,
                                               0, soh_update_datetime,
                                               SYSDATE)),
          first_received       = NVL(first_received, I_tran_date),
          last_received        = I_tran_date,
          qty_received         = L_upd_soh_qty
    where rowid = L_rowid;
   if L_tsf_type IN ('WR', 'FR') then
      open C_SHIP_QTY;
      fetch C_SHIP_QTY into L_ship_qty;
      close C_SHIP_QTY;
      if L_upd_flag = 'P' then
         open C_PACKSKU_QTY;
         fetch C_PACKSKU_QTY into L_packsku_qty;
         close C_PACKSKU_QTY;
      end if;
      update item_loc_soh
         set in_transit_qty   = DECODE(L_upd_flag,
                                      'P', in_transit_qty,
                                       in_transit_qty - (L_ship_qty - L_upd_intran_qty)),
             pack_comp_intran = DECODE(L_upd_flag,
                                       'P', pack_comp_intran - ((L_ship_qty * L_packsku_qty) - L_upd_intran_qty),
                                       pack_comp_intran),
             last_update_id       = USER,
             last_update_datetime = SYSDATE
       where rowid = L_rowid;
   end if;
   --if receiving an item -- update snapshot
   --if receiving a pack -- update shapshot for comp items if one is true
       --to loc is a store
       --rcv as type is 'E'ach
   if (I_pack_ind = 'N' or I_to_loc_type = 'S' or I_receive_as_type = 'E') then
      if I_pack_ind = 'N' then
         L_item_type := 'N'; --not a pack
      else
         L_item_type := 'C'; --comp item
      end if;
      if UPDATE_SNAPSHOT_SQL.EXECUTE(O_error_message,
                                     'TSFI',
                                     I_item,
                                     L_item_type,
                                     I_to_loc_type,
                                     I_to_loc,
                                     I_from_loc_type,
                                     I_from_loc,
                                     I_tran_date,
                                     L_vdate,
                                     L_upd_intran_qty, -- OLR V1.02 Inserted
                                     I_received_qty) = FALSE then
         return FALSE;
      end if;
      if I_inv_status != -1 then
         if STOCK_ORDER_RCV_SQL.UPD_INV_STATUS(O_error_message,
                                               I_item,
                                               I_inv_status,
                                               I_received_qty,
                                               I_to_loc,
                                               I_to_loc_type,
                                               I_tran_date,
                                               I_pack_ind) = FALSE then
            return FALSE;
         end if;
      end if;  --  if I_inv_status != -1
   end if;  --  if (I_pack_ind = 'N' or I_to_loc_type = 'S' or I_receive_as_type = 'E'
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.UPDATE_ITEM_STOCK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPDATE_ITEM_STOCK;
-------------------------------------------------------------------------------
FUNCTION UPD_INV_STATUS(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        I_item           IN      ITEM_MASTER.ITEM%TYPE,
                        I_inv_status     IN      SHIPSKU.INV_STATUS%TYPE,
                        I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                        I_loc            IN      ITEM_LOC.LOC%TYPE,
                        I_loc_type       IN      ITEM_LOC.LOC_TYPE%TYPE,
                        I_tran_date      IN      PERIOD.VDATE%TYPE,
                        I_pack_ind       IN      ITEM_MASTER.PACK_IND%TYPE)
   RETURN BOOLEAN IS
   L_found            BOOLEAN;
   L_pgm_name         tran_data.pgm_name%TYPE    := 'STOCK_ORDER_RCV_SQL.UPD_INV_STATUS';
   L_tran_code        tran_data.tran_code%TYPE   := 25;
   L_reason           inv_adj.reason%TYPE        := NULL;
   L_unavail_reason   INV_ADJ.REASON%TYPE        := 13;
   L_user_id          INV_ADJ.USER_ID%TYPE       := USER;
BEGIN
   if INVADJ_SQL.ADJ_UNAVAILABLE(I_item,
                                 I_inv_status,
                                 I_loc_type,
                                 I_loc,
                                 I_qty,
                                 O_error_message,
                                 L_found) = FALSE then
      return FALSE;
   end if;
   if INVADJ_SQL.BUILD_ADJ_TRAN_DATA(O_error_message,
                                     L_found,
                                     I_item,
                                     I_loc_type,
                                     I_loc,
                                     I_qty,
                                     NULL,
                                     NULL,
                                     NULL,  -- I_order_no
                                     L_pgm_name,
                                     I_tran_date,
                                     L_tran_code,
                                     L_reason,
                                     I_inv_status,
                                     NULL,
                                     NULL,
                                     I_pack_ind) = FALSE then
      return FALSE;
   end if;
   if LP_system_options_row.unavail_stkord_inv_adj_ind = 'Y' then
      if INVADJ_SQL.INSERT_INV_ADJ(O_error_message,
                                   I_item,
                                   I_inv_status,
                                   I_loc_type,
                                   I_loc,
                                   I_qty,
                                   L_unavail_reason,
                                   L_user_id,
                                   I_tran_date) = FALSE then
         return FALSE;
      end if;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_pgm_name,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPD_INV_STATUS;
-------------------------------------------------------------------------------
FUNCTION TRANDATA_OVERAGE(O_error_message             IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                          IO_total_pack_value         IN OUT   ITEM_LOC_SOH.UNIT_COST%TYPE,
                          I_pack_no                   IN       ITEM_MASTER.ITEM%TYPE,
                          I_item                      IN       ITEM_MASTER.ITEM%TYPE,
                          I_dept                      IN       ITEM_MASTER.DEPT%TYPE,
                          I_class                     IN       ITEM_MASTER.CLASS%TYPE,
                          I_subclass                  IN       ITEM_MASTER.SUBCLASS%TYPE,
                          I_to_loc                    IN       ITEM_LOC.LOC%TYPE,
                          I_to_loc_type               IN       ITEM_LOC.LOC_TYPE%TYPE,
                          I_to_tsf_entity             IN       TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                          I_to_finisher               IN       VARCHAR2,
                          I_from_loc                  IN       ITEM_LOC.LOC%TYPE,
                          I_from_loc_type             IN       ITEM_LOC.LOC_TYPE%TYPE,
                          I_from_tsf_entity           IN       TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                          I_from_finisher             IN       VARCHAR2,
                          I_rcv_qty                   IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                          I_rcv_weight                IN       ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE, -- Catch Weight
                          I_distro_no                 IN       SHIPSKU.DISTRO_NO%TYPE,
                          I_distro_type               IN       VARCHAR2,
                          I_shipment                  IN       SHIPMENT.SHIPMENT%TYPE,
                          I_tran_date                 IN       PERIOD.VDATE%TYPE,
                          I_from_wac                  IN       item_loc_soh.av_cost%TYPE,        -- Transfers and Item Valuation
                          I_profit_chrgs_to_loc       IN       ITEM_LOC_SOH.AV_COST%TYPE,
                          I_exp_chrgs_to_loc          IN       ITEM_LOC_SOH.AV_COST%TYPE,
                          I_intercompany              IN       BOOLEAN,                        -- Transfers and Item Valuation
                          I_inventory_treatment_ind   IN       SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE)
   RETURN BOOLEAN IS
   L_pgm_name              TRAN_DATA.PGM_NAME%TYPE     := 'STOCK_ORDER_RCV_SQL.TRANDATA_OVERAGE';
   L_pct_in_pack           NUMBER;
   L_tsf_alloc_unit_cost   ITEM_LOC_SOH.AV_COST%TYPE   := NULL;   -- Transfers and Item Valuation
   L_tran_code             TRAN_DATA.TRAN_CODE%TYPE    := NULL;
   L_receipt_qty           TSFDETAIL.TSF_QTY%TYPE      := 0;
   L_total_cost            TRAN_DATA.TOTAL_COST%TYPE   := 0;
   L_total_retail          TRAN_DATA.TOTAL_RETAIL%TYPE := 0;
   L_total_cost_conv       TRAN_DATA.TOTAL_COST%TYPE   := 0;      -- Receiving Location Cost
   L_total_retail_conv     TRAN_DATA.TOTAL_RETAIL%TYPE := 0;      -- Receiving Location Retail
   L_from_loc_av_cost      item_loc_soh.av_cost%TYPE := NULL;
BEGIN
   if I_pack_no is not NULL and IO_total_pack_value is NULL then
      if TRANSFER_COST_SQL.PCT_IN_PACK(O_error_message,
                                       L_pct_in_pack,
                                       I_pack_no,
                                       I_item,
                                       I_from_loc) = FALSE then
         return FALSE;
      end if;
   end if;
   -- Get the transfer unit retail for inventory treatment other than 'BL'. For 'BL', the call is made
   -- in WRITE_FINANCIAL.
   if I_inventory_treatment_ind != 'BL' then
      if STKLEDGR_SQL.GET_TSF_COSTS_RETAILS(O_error_message,
                                            L_total_cost,
                                            L_total_retail,
                                            L_total_retail_conv,
                                            I_distro_no,
                                            I_intercompany,
                                            I_from_finisher,
                                            I_to_finisher,
                                            I_item,
                                            I_from_loc,
                                            I_from_loc_type,
                                            I_to_loc,
                                            I_to_loc_type) = FALSE then
         return FALSE;
      end if;
   end if;
   --
   L_tran_code := 22;
   --move stock into sending location for NL and SL
   if I_inventory_treatment_ind in ('NL','SL') then
      if I_inventory_treatment_ind = 'NL' then
         L_receipt_qty  := I_rcv_qty *(-1);
         --L_total_cost   := L_total_cost*(-1);
         --L_total_retail := L_total_retail*(-1);
      else
         L_receipt_qty  := I_rcv_qty ;
      end if;
      L_total_cost   := I_from_wac * L_receipt_qty;
      L_total_retail := L_total_retail * L_receipt_qty;
      -- move stock out of sending location
      if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                             I_item,
                                             I_dept,
                                             I_class,
                                             I_subclass,
                                             I_from_loc,
                                             I_from_loc_type,
                                             I_tran_date,
                                             L_tran_code,
                                             NULL,
                                             L_receipt_qty,
                                             L_total_cost,
                                             L_total_retail,
                                             I_distro_no,
                                             I_shipment,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             L_pgm_name,
                                             NULL) = FALSE then
         return FALSE;
      end if;
      if I_inventory_treatment_ind ='NL' then
         if ITEMLOC_ATTRIB_SQL.GET_WAC(O_error_message,
                                          L_from_loc_av_cost,
                                          I_item,
                                          I_dept,
                                          I_class,
                                          I_subclass,
                                          I_from_loc,
                                          I_from_loc_type,
                                          NULL,                  -- tran_date
                                          I_to_loc,
                                          I_to_loc_type) = FALSE then
               return FALSE;
          end if;
         if L_from_loc_av_cost!= I_from_wac then
           if STKLEDGR_SQL.POST_COST_VARIANCE(O_error_message,
                                               I_item,
                                               NULL,
                                               I_dept,
                                               I_class,
                                               I_subclass,
                                               I_from_loc,
                                               I_from_loc_type,
                                               I_from_wac,  -- in from loc currency
                                               L_from_loc_av_cost,
                                               I_rcv_qty,
                                               NULL,
                                               I_distro_no,
                                               I_shipment,
                                               I_tran_date)= FALSE then
              return FALSE;
           end if;
         end if;
      end if;
   end if;
   -- move stock into receiving location for NL and RL
   if I_inventory_treatment_ind in ('NL','RL') then
      L_receipt_qty   := I_rcv_qty;
      --
      if ITEMLOC_ATTRIB_SQL.GET_AV_COST(O_error_message,
                                        I_item,
                                        I_from_loc,
                                        I_from_loc_type,
                                        L_total_cost_conv) = FALSE then
         RETURN FALSE;
      end if;
      L_total_cost_conv   := I_from_wac * L_receipt_qty;
      L_total_retail_conv := L_total_retail_conv * L_receipt_qty;
      -- move stock into receiving location
      if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                             I_item,
                                             I_dept,
                                             I_class,
                                             I_subclass,
                                             I_to_loc,
                                             I_to_loc_type,
                                             I_tran_date,
                                             L_tran_code,
                                             NULL,
                                             L_receipt_qty,
                                             L_total_cost_conv,    -- Receiving Location Cost
                                             L_total_retail_conv,  -- Receiving Location Retail
                                             I_distro_no,
                                             I_shipment,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             NULL,
                                             L_pgm_name,
                                             NULL) = FALSE then
        return FALSE;
      end if;
   end if; -- I_inventory_treatment_ind in ('NL','RL')
   --
   if I_inventory_treatment_ind in ('SL','BL') then
      if STKLEDGR_SQL.WRITE_FINANCIALS(O_error_message,
                                       L_tsf_alloc_unit_cost,
                                       I_distro_type,
                                       I_shipment,
                                       I_distro_no,
                                       I_tran_date,
                                       I_item,
                                       I_pack_no,
                                       L_pct_in_pack,
                                       I_dept,
                                       I_class,
                                       I_subclass,
                                       I_rcv_qty,
                                       I_rcv_weight,           -- Catch Weight
                                       I_from_loc,
                                       I_from_loc_type,
                                       I_from_finisher,
                                       I_to_loc,
                                       I_to_loc_type,
                                       I_to_finisher,
                                       I_from_wac,             -- Transfer and Item Valuation
                                       I_profit_chrgs_to_loc,
                                       I_exp_chrgs_to_loc,
                                       I_intercompany) = FALSE then
         return FALSE;
      end if;
      if I_inventory_treatment_ind ='BL' then
         if ITEMLOC_ATTRIB_SQL.GET_WAC(O_error_message,
                                          L_from_loc_av_cost,
                                          I_item,
                                          I_dept,
                                          I_class,
                                          I_subclass,
                                          I_from_loc,
                                          I_from_loc_type,
                                          NULL,                  -- tran_date
                                          I_to_loc,
                                          I_to_loc_type) = FALSE then
               return FALSE;
          end if;
         if L_from_loc_av_cost!= I_from_wac then
           if STKLEDGR_SQL.POST_COST_VARIANCE(O_error_message,
                                               I_item,
                                               NULL,
                                               I_dept,
                                               I_class,
                                               I_subclass,
                                               I_from_loc,
                                               I_from_loc_type,
                                               I_from_wac,  -- in from loc currency
                                               L_from_loc_av_cost,
                                               I_rcv_qty,
                                               NULL,
                                               I_distro_no,
                                               I_shipment,
                                               I_tran_date)= FALSE then
              return FALSE;
           end if;
         end if;
      end if;
   end if; -- I_inventory_treatment_ind in ('SL','BL')
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_pgm_name,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END TRANDATA_OVERAGE;
-------------------------------------------------------------------------------
FUNCTION UPDATE_FROM_OVERAGE(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                             I_item           IN      ITEM_MASTER.ITEM%TYPE,
                             I_comp_ind       IN      VARCHAR2,
                             I_from_loc       IN      ITEM_LOC.LOC%TYPE,
                             I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                             I_weight_cuom    IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                             I_cuom           IN      ITEM_SUPP_COUNTRY.COST_UOM%TYPE)    -- Catch Weight
   RETURN BOOLEAN IS
   L_rowid                  ROWID;
   L_table                  VARCHAR2(30);
   L_key1                   VARCHAR2(100);
   L_key2                   VARCHAR2(100);
   L_total_soh              ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;   -- Catch Weight
   L_current_average_weight ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;  -- Catch Weight
   L_new_average_weight     ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;  -- Catch Weight
   L_qty                    ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;  -- Catch Weight
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
  -- cursors
   cursor C_LOCK_ITEM_LOC_SOH is
      select ils.rowid,
                 ils.average_weight,                                                         -- Catch Weight
                 ils.stock_on_hand+ils.in_transit_qty+ils.pack_comp_intran+ils.pack_comp_soh -- Catch Weight
        from item_loc_soh ils
       where ils.item = I_item
         and ils.loc  = I_from_loc
         for update nowait;
BEGIN
   L_table := 'ITEM_LOC_SOH';
   L_key1 := I_item;
   L_key2 := TO_CHAR(I_from_loc);
   open C_LOCK_ITEM_LOC_SOH;
   fetch C_LOCK_ITEM_LOC_SOH into L_rowid, L_current_average_weight, L_total_soh;  -- Catch Weight
   close C_LOCK_ITEM_LOC_SOH;
   -- Catch Weight
   if I_comp_ind = 'P' and I_weight_cuom is not NULL then
      if CATCH_WEIGHT_SQL.CALC_AVERAGE_WEIGHT(O_error_message,
                                              L_new_average_weight,
                                              I_item,
                                              I_from_loc,
                                              NULL,
                                              L_total_soh,
                                              L_current_average_weight,
                                              I_qty * -1,        -- Convert to negative value in order to decrement at the from loc
                                              I_weight_cuom * -1,-- Convert to negative value in order to decrement at the from loc
                                              NULL) = FALSE THEN
         return FALSE;
      end if;
   end if;
   if I_comp_ind = 'C' and I_weight_cuom is NOT NULL then
      if CATCH_WEIGHT_SQL.CALC_COMP_UPDATE_QTY(O_error_message,
                                               L_qty,
                                               I_item,
                                               I_qty,
                                               I_weight_cuom,
                                               I_cuom) = FALSE then
         return FALSE;
      end if;
   else
      L_qty := I_qty;
   end if;
   -- Catch Weight end
   update item_loc_soh ils
      set ils.stock_on_hand = DECODE(I_comp_ind,
                                     'I', ils.stock_on_hand - L_qty,
                                     'P', ils.stock_on_hand - L_qty,
                                     ils.stock_on_hand),
          ils.pack_comp_soh = DECODE(I_comp_ind, 'C',
                                     ils.pack_comp_soh - L_qty,
                                     ils.pack_comp_soh),
          ils.average_weight = DECODE(I_comp_ind,
                                     'P', L_new_average_weight,
                                     ils.average_weight),
          ils.soh_update_datetime  = DECODE(I_comp_ind,
                                            'I', DECODE(I_qty,
                                                        0, soh_update_datetime,
                                                        SYSDATE),
                                            'P', DECODE(I_qty,
                                                        0, soh_update_datetime,
                                                        SYSDATE),
                                            soh_update_datetime),
          ils.last_update_datetime = SYSDATE,
          ils.last_update_id       = USER
    where ils.rowid = L_rowid;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.UPDATE_FROM_OVERAGE',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPDATE_FROM_OVERAGE;
-------------------------------------------------------------------------------
FUNCTION PROC_STK_CNT_TD_WRITE(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                               I_distro_no        IN      SHIPSKU.DISTRO_NO%TYPE,
                               I_cycle_count      IN      STAKE_HEAD.CYCLE_COUNT%TYPE,
                               I_item             IN      ITEM_MASTER.ITEM%TYPE,
                               I_dept             IN      ITEM_MASTER.DEPT%TYPE,
                               I_class            IN      ITEM_MASTER.CLASS%TYPE,
                               I_subclass         IN      ITEM_MASTER.SUBCLASS%TYPE,
                               I_to_loc           IN      ITEM_LOC.LOC%TYPE,
                               I_to_loc_type      IN      ITEM_LOC.LOC_TYPE%TYPE,
                               I_qty              IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                               I_snapshot_retail  IN      ITEM_LOC_SOH.AV_COST%TYPE,
                               I_snapshot_cost    IN      ITEM_LOC.UNIT_RETAIL%TYPE,
                               I_tran_date        IN      PERIOD.VDATE%TYPE)
   RETURN BOOLEAN IS
   L_pgm_name      tran_data.pgm_name%TYPE  := 'STOCK_ORDER_RCV_SQL.PROC_STK_CNT_TD_WRITE';
   L_tran_code     tran_data.tran_code%TYPE := 22;
   L_total_retail  item_loc_soh.av_cost%TYPE       := I_snapshot_retail * I_qty * -1;
   L_total_cost    item_loc.unit_retail%TYPE       := I_snapshot_cost * I_qty * -1;
   L_receipt_qty   item_loc_soh.stock_on_hand%TYPE := I_qty * -1;
BEGIN
   if STKLEDGR_SQL.BUILD_TRAN_DATA_INSERT(O_error_message,
                                          I_item,
                                          I_dept,
                                          I_class,
                                          I_subclass,
                                          I_to_loc,
                                          I_to_loc_type,
                                          I_tran_date,
                                          L_tran_code,
                                          NULL,
                                          L_receipt_qty,
                                          L_total_cost,
                                          L_total_retail,
                                          I_distro_no,
                                          I_cycle_count,
                                          NULL,
                                          NULL,
                                          NULL,
                                          NULL,
                                          NULL,
                                          NULL,
                                          NULL,
                                          L_pgm_name,
                                          NULL) = FALSE then
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.PROC_STK_CNT_TD_WRITE',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END PROC_STK_CNT_TD_WRITE;
-------------------------------------------------------------------------------
FUNCTION PACK_LEVEL_PROC(O_error_message             IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                         O_receive_as_type           IN OUT   ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                         O_from_pack_av_cost         IN OUT   ITEM_LOC_SOH.AV_COST%TYPE,
                         O_pack_av_cost_ratio        IN OUT   NUMBER,
                         I_distro_no                 IN       SHIPSKU.DISTRO_NO%TYPE,
                         I_pack_no                   IN       ITEM_MASTER.ITEM%TYPE,
                         I_dept                      IN       ITEM_MASTER.DEPT%TYPE,
                         I_class                     IN       ITEM_MASTER.CLASS%TYPE,
                         I_subclass                  IN       ITEM_MASTER.SUBCLASS%TYPE,
                         I_inv_status                IN       SHIPSKU.INV_STATUS%TYPE,
                         I_from_loc                  IN       ITEM_LOC.LOC%TYPE,
                         I_from_loc_type             IN       ITEM_LOC.LOC_TYPE%TYPE,
                         I_from_rcv_as_type          IN       ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                         I_to_loc                    IN       ITEM_LOC.LOC%TYPE,
                         I_to_loc_type               IN       ITEM_LOC.LOC_TYPE%TYPE,
                         I_tran_date                 IN       PERIOD.VDATE%TYPE,
                         I_rcv_qty                   IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_intran_qty                IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_overage_qty               IN       ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_overage_weight_cuom       IN       ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                         I_cuom                      IN       ITEM_SUPP_COUNTRY.COST_UOM%TYPE,    --CatchWeight
                         I_prim_charge               IN       ITEM_LOC_SOH.AV_COST%TYPE,
                         I_from_loc_av_cost          IN       ITEM_LOC_SOH.AV_COST%TYPE,
                         I_from_inv_status           IN       TSFDETAIL.INV_STATUS%TYPE,
                         I_store_type                IN       STORE.STORE_TYPE%TYPE,
                         I_inventory_treatment_ind   IN       SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE)
   RETURN BOOLEAN IS
   L_vdate                      DATE := GET_VDATE;
   L_stock_count_processed      BOOLEAN := FALSE;
   L_cycle_count                stake_head.cycle_count%TYPE := NULL;
   L_snapshot_cost              item_loc_soh.av_cost%TYPE   := 0;
   L_snapshot_retail            item_loc.unit_retail%TYPE   := 0;
   L_from_charge                item_loc_soh.av_cost%TYPE   := 0;
   L_wf_ind                     SYSTEM_OPTIONS.WHOLESALE_FRANCHISE_IND%TYPE;
   L_tsf_type                   TSFHEAD.TSF_TYPE%TYPE;
   L_ship_qty                   TSFDETAIL.SHIP_QTY%TYPE;
   L_store_type                 STORE.STORE_TYPE%TYPE        := 'C';
   -- cursors
   cursor C_TO_RECEIVE_AS_TYPE is
      select NVL(il.receive_as_type, 'E')
        from item_loc il
       where il.item = I_pack_no
         and il.loc  = I_to_loc;
   cursor C_GET_WF_IND is
      select wholesale_franchise_ind
        from system_options;
   cursor C_TSF_TYPE is
      select tsf_type
        from tsfhead
       where tsf_no = I_distro_no;
   cursor C_SHIP_QTY is
      select NVL(ship_qty, 0)
        from tsfdetail
       where tsf_no = I_distro_no
         and item = I_pack_no;
BEGIN
   if I_store_type is NOT NULL then
      L_store_type := I_store_type;
   end if;
   open C_TO_RECEIVE_AS_TYPE;
   fetch C_TO_RECEIVE_AS_TYPE into O_receive_as_type;
   close C_TO_RECEIVE_AS_TYPE;
   open C_GET_WF_IND;
   fetch C_GET_WF_IND into L_wf_ind;
   close C_GET_WF_IND;
   open C_TSF_TYPE;
   fetch C_TSF_TYPE into L_tsf_type;
   close C_TSF_TYPE;
   if I_to_loc_type = 'W' and O_receive_as_type = 'P' then
      --check back posted transactions for processed stock counts
      if I_tran_date < L_vdate then
         if STKCNT_ATTRIB_SQL.STOCK_COUNT_PROCESSED(O_error_message,
                                                    L_stock_count_processed,
                                                    L_cycle_count,
                                                    L_snapshot_cost,
                                                    L_snapshot_retail,
                                                    I_tran_date,
                                                    I_pack_no,
                                                    I_to_loc_type,
                                                    I_to_loc) = FALSE then
            return FALSE;
         end if;
         if L_stock_count_processed = TRUE then
            if STOCK_ORDER_RCV_SQL.PROC_STK_CNT_TD_WRITE(O_error_message,
                                                         I_distro_no,
                                                         L_cycle_count,
                                                         I_pack_no,
                                                         I_dept,
                                                         I_class,
                                                         I_subclass,
                                                         I_to_loc,
                                                         I_to_loc_type,
                                                         I_rcv_qty,
                                                         L_snapshot_retail,
                                                         L_snapshot_cost,
                                                         I_tran_date) = FALSE then
               return FALSE;
            end if;
         end if;
      end if;
      if STOCK_ORDER_RCV_SQL.UPDATE_PACK_STOCK(O_error_message,
                                               I_pack_no,
                                               I_to_loc,
                                               L_stock_count_processed,
                                               I_rcv_qty,
                                               I_intran_qty,
                                               I_overage_qty,          -- Catch Weight
                                               I_overage_weight_cuom,  -- Catch Weight
                                               I_tran_date) = FALSE then
         return FALSE;
      end if;
      if L_tsf_type IN ('WR', 'FR') then
         open C_SHIP_QTY;
         fetch C_SHIP_QTY into L_ship_qty;
         close C_SHIP_QTY;
         update item_loc_soh
            set in_transit_qty = in_transit_qty - (L_ship_qty - I_rcv_qty)
          where item = I_pack_no
            and loc = I_to_loc;
      end if;
      if I_inv_status != -1 then
         if STOCK_ORDER_RCV_SQL.UPD_INV_STATUS(O_error_message,
                                               I_pack_no,
                                               I_inv_status,
                                               I_rcv_qty,
                                               I_to_loc,
                                               I_to_loc_type,
                                               I_tran_date,
                                               'Y') = FALSE then -- pack_ind
            return FALSE;
         end if;
      end if;
      if UPDATE_SNAPSHOT_SQL.EXECUTE(O_error_message,
                                     'TSFI',
                                     I_pack_no,
                                     'P',
                                     I_to_loc_type,
                                     I_to_loc,
                                     I_from_loc_type,
                                     I_from_loc,
                                     I_tran_date,
                                     L_vdate,
                                     I_rcv_qty) = FALSE then
         return FALSE;
      end if;
   end if;
   -- Ensure from loc receive_as_type is 'P'
   -- If receiving a pack and from loc receive_as_type is 'E' then
   -- from loc is a finisher which does not track stock at pack level.
   if L_wf_ind != 'Y' OR
      L_store_type NOT IN ('W', 'F') then
      if I_overage_qty != 0 and I_from_rcv_as_type = 'P' then
         if I_inventory_treatment_ind in ('NL','BL') then
            if UPDATE_FROM_OVERAGE(O_error_message,
                                   I_pack_no,
                                   'P',
                                   I_from_loc,
                                   I_overage_qty,
                                   I_overage_weight_cuom,   -- Catch Weight
                                   I_cuom                   -- Catch Weight
                                   ) = FALSE then
               return FALSE;
            end if;
            if NVL(I_from_inv_status, -1) != -1 then
               if STOCK_ORDER_RCV_SQL.UPD_INV_STATUS(O_error_message,
                                                     I_pack_no,
                                                     I_from_inv_status,
                                                     I_overage_qty * -1,
                                                     I_from_loc,
                                                     I_from_loc_type,
                                                     I_tran_date,
                                                     'Y') = FALSE then -- pack_ind
                  return FALSE;
               end if;
            end if;
         end if; -- I_inventory_treatment_ind in ('NL','BL')
      end if;
      if I_prim_charge != 0 then
         --convert the up charges from prim currency to the from loc's currency
         if CURRENCY_SQL.CONVERT_BY_LOCATION(O_error_message,
                                             NULL,
                                             NULL,
                                             NULL,
                                             I_from_loc,
                                             I_from_loc_type,
                                             NULL,
                                             I_prim_charge,
                                             L_from_charge,
                                             'C',
                                             NULL,
                                             NULL) = FALSE then
            return FALSE;
         end if;
      else
         L_from_charge := 0;
      end if;
   -- Get pack's current av cost -- it may be different that what is on shipsku.
   -- The ratio between the two will be used when writting adjustments at
   -- the comp level.  Get the packs av cost at from loc -- used in average cost
   -- updates on over ships.  Since shipsku cost holds up charges we need to add
   -- them into the pack's av_cost before we calculage the ratio.
      if ITEMLOC_ATTRIB_SQL.GET_AV_COST(O_error_message,
                                        I_pack_no,
                                        I_from_loc,
                                        I_from_loc_type,
                                        O_from_pack_av_cost) = FALSE then
         return FALSE;
      end if;
   else
      O_from_pack_av_cost := I_from_loc_av_cost;
   end if;
   if I_overage_qty != 0 then
      O_pack_av_cost_ratio := I_from_loc_av_cost / (O_from_pack_av_cost + L_from_charge);
   else
      O_pack_av_cost_ratio := 1;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.PACK_LEVEL_PROC',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END PACK_LEVEL_PROC;
-------------------------------------------------------------------------------
FUNCTION UPDATE_PACK_STOCK(O_error_message       IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_pack_no             IN      ITEM_MASTER.ITEM%TYPE,
                           I_to_loc              IN      ITEM_LOC.LOC%TYPE,
                           I_stk_cnt_procd       IN      BOOLEAN,
                           I_rcv_qty             IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                           I_intran_qty          IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                           I_overage_qty         IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,   -- Catch Weight
                           I_overage_weight_cuom IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                           I_tran_date           IN      PERIOD.VDATE%TYPE)
   RETURN BOOLEAN IS
   L_upd_qty                item_loc_soh.stock_on_hand%TYPE;
   L_rowid                  ROWID;
   L_table                  VARCHAR2(30);
   L_key1                   VARCHAR2(100);
   L_key2                   VARCHAR2(100);
   L_total_soh              ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;   -- Catch Weight
   L_current_average_weight ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;  -- Catch Weight
   L_new_average_weight     ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;  -- Catch Weight
   RECORD_LOCKED EXCEPTION;
   PRAGMA        EXCEPTION_INIT(Record_Locked, -54);
   -- cursors
   cursor C_LOCK_PACK_ITEM_LOC is
      select ils.rowid,
             ils.average_weight,    -- Catch Weight
             ils.stock_on_hand+ils.in_transit_qty+ils.pack_comp_intran+ils.pack_comp_soh -- Catch Weight
        from item_loc_soh ils
       where ils.item = I_pack_no
         and ils.loc  = I_to_loc
        for update nowait;
BEGIN
   L_table := 'ITEM_LOC_SOH';
   L_key1 := I_pack_no;
   L_key2 := TO_CHAR(I_to_loc);
   open C_LOCK_PACK_ITEM_LOC;
   fetch C_LOCK_PACK_ITEM_LOC into L_rowid, L_current_average_weight, L_total_soh;  -- Catch Weight
   close C_LOCK_PACK_ITEM_LOC;
   --if a completed stock count was found, the qty was already
   --accounted for by the stock count
   if I_stk_cnt_procd = TRUE then
      L_upd_qty := 0;
   else
      L_upd_qty := I_rcv_qty;
   end if;
   -- Catch Weight
   if I_overage_weight_cuom is not NULL then
      if CATCH_WEIGHT_SQL.CALC_AVERAGE_WEIGHT(O_error_message,
                                              L_new_average_weight,
                                              I_pack_no,
                                              I_to_loc,
                                              NULL,
                                              L_total_soh,
                                              L_current_average_weight,
                                              I_overage_qty,
                                              I_overage_weight_cuom,
                                              NULL) = FALSE THEN
         return FALSE;
      end if;
   end if;
   -- Catch Weight end
   update item_loc_soh ils
      set ils.stock_on_hand    = ils.stock_on_hand + L_upd_qty,
          ils.in_transit_qty   = ils.in_transit_qty - I_intran_qty,
          ils.last_update_id       = USER,
          ils.last_update_datetime = SYSDATE,
          ils.soh_update_datetime = DECODE(L_upd_qty,
                                           0, soh_update_datetime,
                                           SYSDATE),
          first_received       = NVL(first_received, I_tran_date),
          last_received        = I_tran_date,
          qty_received         = L_upd_qty,
          average_weight       = L_new_average_weight  -- Catch Weight
    where ils.rowid = L_rowid;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.UPDATE_PACK_STOCK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPDATE_PACK_STOCK;
-------------------------------------------------------------------------------
FUNCTION LOAD_COMPS(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                    O_comp_items     IN OUT  STOCK_ORDER_RCV_SQL.COMP_ITEM_ARRAY,
                    I_pack_no        IN      ITEM_MASTER.ITEM%TYPE,
                    I_from_loc       IN      ITEM_LOC.LOC%TYPE,
                    I_from_loc_type  IN      ITEM_LOC.LOC_TYPE%TYPE,
                    I_to_loc         IN      ITEM_LOC.LOC%TYPE,
                    I_to_loc_type    IN      ITEM_LOC.LOC_TYPE%TYPE)
   RETURN BOOLEAN IS
   comp_cnt BINARY_INTEGER := 0;
   -- cursors
   cursor C_ITEMS_IN_PACK is
      select vpq.item item,
             vpq.qty qty,
             NVL(ils.av_cost, 0) av_cost,
             im.pack_ind pack_ind,
             im.dept dept,
             im.class class,
             im.subclass subclass,
             im.inventory_ind
        from v_packsku_qty vpq,
             item_loc_soh ils,
             item_master im
       where vpq.pack_no = I_pack_no
         and ils.item    = vpq.item
         and ils.loc     = I_from_loc
         and im.item     = vpq.item
       order by item;
BEGIN
   FOR rec IN C_ITEMS_IN_PACK LOOP
      comp_cnt := comp_cnt + 1;
      O_comp_items(comp_cnt).comp_item               := rec.item;
      O_comp_items(comp_cnt).comp_qty                := rec.qty;
      O_comp_items(comp_cnt).comp_from_loc_av_cost   := rec.av_cost;
      O_comp_items(comp_cnt).comp_pack_ind           := rec.pack_ind;
      O_comp_items(comp_cnt).comp_dept               := rec.dept;
      O_comp_items(comp_cnt).comp_class              := rec.class;
      O_comp_items(comp_cnt).comp_subclass           := rec.subclass;
      O_comp_items(comp_cnt).comp_inventory_ind      := rec.inventory_ind;
   END LOOP;
   if O_comp_items.COUNT < 1 then
      O_error_message := SQL_LIB.CREATE_MSG('INV_ITEM', NULL, NULL, NULL);
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.LOAD_COMPS',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END LOAD_COMPS;
-------------------------------------------------------------------------------
FUNCTION FLUSH_APPT_DETAIL_UPDATE(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
   RETURN BOOLEAN IS
   L_function              VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.FLUSH_APPT_DETAIL_UPDATE';
BEGIN
   if P_appt_detail_size > 0 then
      FORALL i IN 1..P_appt_detail_size
      update appt_detail
         set receipt_no   = P_appt_detail_receipt_no(i),
             qty_received = NVL(qty_received, 0) + P_appt_detail_qty_received(i)
       where rowid        = P_appt_detail_rowid(i);
   end if;
   P_appt_detail_size := 0;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_function,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END FLUSH_APPT_DETAIL_UPDATE;
-------------------------------------------------------------------------------
FUNCTION FLUSH_DOC_CLOSE_QUEUE_INSERT(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE)
   RETURN BOOLEAN IS
   L_function              VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.FLUSH_DOC_CLOSE_QUEUE_INSERT';
BEGIN
   if P_doc_close_queue_size > 0 then
      FORALL i IN 1..P_doc_close_queue_size
         insert into doc_close_queue( doc,
                                      doc_type)
                              values( P_doc_close_queue_doc(i),
                                      P_doc_close_queue_doc_type(i));
   end if;
   P_doc_close_queue_size := 0;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_function,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END FLUSH_DOC_CLOSE_QUEUE_INSERT;
-------------------------------------------------------------------------------
-- *** This function is only here as a debug aid.  It should not be used ***
-- *** in prodcution code.                                               ***
--------------------------------------------------------------------------------
/*FUNCTION DISPLAY_STRUCT(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        I_item_rec        IN      STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                        I_values          IN      STOCK_ORDER_RCV_SQL.COST_RETAIL_QTY_RECORD,
                        I_inv_flow_array  IN      STOCK_ORDER_RCV_SQL.INV_FLOW_ARRAY)
RETURN BOOLEAN IS
   i BINARY_INTEGER := 0;
BEGIN
   dbms_output.put_line('=================================================================');
   dbms_output.put_line('ITEM_STRUCT======================================================');
   dbms_output.put_line('I_item_rec.item              ->'||I_item_rec.item           );
   dbms_output.put_line('I_item_rec.ref_item          ->'||I_item_rec.ref_item       );
   dbms_output.put_line('I_item_rec.carton            ->'||I_item_rec.carton         );
   dbms_output.put_line('I_item_rec.dept              ->'||I_item_rec.dept           );
   dbms_output.put_line('I_item_rec.class             ->'||I_item_rec.class          );
   dbms_output.put_line('I_item_rec.subclass          ->'||I_item_rec.subclass       );
   dbms_output.put_line('I_item_rec.pack_ind          ->'||I_item_rec.pack_ind       );
   dbms_output.put_line('I_item_rec.pack_type         ->'||I_item_rec.pack_type      );
   dbms_output.put_line('I_item_rec.distro_type       ->'||I_item_rec.distro_type    );
   dbms_output.put_line('I_item_rec.tran_date         ->'||I_item_rec.tran_date      );
   dbms_output.put_line('I_item_rec.transaction_type  ->'||I_item_rec.transaction_type      );
   dbms_output.put_line('I_item_rec.alloc_no          ->'||I_item_rec.alloc_no       );
   dbms_output.put_line('I_item_rec.alloc_status      ->'||I_item_rec.alloc_status   );
   dbms_output.put_line('I_item_rec.tsf_no            ->'||I_item_rec.tsf_no         );
   dbms_output.put_line('I_item_rec.tsf_type          ->'||I_item_rec.tsf_type       );
   dbms_output.put_line('I_item_rec.tsf_status        ->'||I_item_rec.tsf_status     );
   dbms_output.put_line('I_item_rec.tsf_seq_no        ->'||I_item_rec.tsf_seq_no     );
   dbms_output.put_line('I_item_rec.distro_from_loc   ->'||I_item_rec.distro_from_loc);
   dbms_output.put_line('I_item_rec.from_loc_phy      ->'||I_item_rec.from_loc_phy   );
   dbms_output.put_line('I_item_rec.from_loc_type     ->'||I_item_rec.from_loc_type  );
   dbms_output.put_line('I_item_rec.distro_to_loc     ->'||I_item_rec.distro_to_loc  );
   dbms_output.put_line('I_item_rec.to_loc_phy        ->'||I_item_rec.to_loc_phy     );
   dbms_output.put_line('I_item_rec.to_loc_type       ->'||I_item_rec.to_loc_type    );
   dbms_output.put_line('I_item_rec.appt              ->'||I_item_rec.appt           );
   dbms_output.put_line('I_item_rec.receipt_no        ->'||I_item_rec.receipt_no     );
   dbms_output.put_line('I_item_rec.inv_status        ->'||I_item_rec.inv_status     );
   dbms_output.put_line('I_item_rec.bol_no            ->'||I_item_rec.bol_no         );
   dbms_output.put_line('I_item_rec.ship_no           ->'||I_item_rec.ship_no        );
   dbms_output.put_line('I_item_rec.ss_seq_no         ->'||I_item_rec.ss_seq_no      );
   dbms_output.put_line('ITEM_STRUCT======================================================');
   dbms_output.put_line('=================================================================');
   dbms_output.put_line('=================================================================');
   dbms_output.put_line('COST_RETAIL_QTY_STRUCT===========================================');
   dbms_output.put_line('I_values.receive_as_type           ->'||I_values.receive_as_type        );
   dbms_output.put_line('I_values.input_qty                 ->'||I_values.input_qty              );
   dbms_output.put_line('I_values.ss_exp_qty                ->'||I_values.ss_exp_qty             );
   dbms_output.put_line('I_values.ss_prev_rcpt_qty          ->'||I_values.ss_prev_rcpt_qty       );
   dbms_output.put_line('I_values.td_exp_qty                ->'||I_values.td_exp_qty             );
   dbms_output.put_line('I_values.td_prev_rcpt_qty          ->'||I_values.td_prev_rcpt_qty       );
   dbms_output.put_line('I_values.ad_exp_qty                ->'||I_values.ad_exp_qty             );
   dbms_output.put_line('I_values.ad_prev_rcpt_qty          ->'||I_values.ad_prev_rcpt_qty       );
   dbms_output.put_line('I_values.from_loc_av_cost          ->'||I_values.from_loc_av_cost       );
   dbms_output.put_line('I_values.pack_from_av_cost         ->'||I_values.pack_from_av_cost      );
   dbms_output.put_line('I_values.pack_av_cost_ratio        ->'||I_values.pack_av_cost_ratio     );
   dbms_output.put_line('COST_RETAIL_QTY_STRUCT===========================================');
   dbms_output.put_line('=================================================================');
   dbms_output.put_line('=================================================================');
   dbms_output.put_line('INV_FLOW STRUCT==================================================');
   FOR i IN I_inv_flow_array.FIRST..I_inv_flow_array.LAST LOOP
   dbms_output.put_line('i is: ->'||i);
   dbms_output.put_line('I_inv_flow_array(i).vir_from_loc       ->'||I_inv_flow_array(i).vir_from_loc       );
   dbms_output.put_line('I_inv_flow_array(i).vir_from_loc_type  ->'||I_inv_flow_array(i).vir_from_loc_type  );
   dbms_output.put_line('I_inv_flow_array(i).vir_to_loc         ->'||I_inv_flow_array(i).vir_to_loc         );
   dbms_output.put_line('I_inv_flow_array(i).vir_to_loc_type    ->'||I_inv_flow_array(i).vir_to_loc_type    );
   dbms_output.put_line('I_inv_flow_array(i).exp_qty            ->'||I_inv_flow_array(i).exp_qty            );
   dbms_output.put_line('I_inv_flow_array(i).prev_rcpt_qty      ->'||I_inv_flow_array(i).prev_rcpt_qty      );
   dbms_output.put_line('I_inv_flow_array(i).dist_qty           ->'||I_inv_flow_array(i).dist_qty           );
   dbms_output.put_line('I_inv_flow_array(i).upd_intran_qty     ->'||I_inv_flow_array(i).upd_intran_qty);
   dbms_output.put_line('I_inv_flow_array(i).overage_qty->'||I_inv_flow_array(i).overage_qty);
   END LOOP;
   dbms_output.put_line('INV_FLOW STRUCT==================================================');
   dbms_output.put_line('=================================================================');
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'DISPLAY_STRUCT',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END DISPLAY_STRUCT;*/
-------------------------------------------------------------------------------
FUNCTION UPD_SHIPMENT(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                      I_shipment       IN      SHIPMENT.SHIPMENT%TYPE,
                      I_tran_date      IN      PERIOD.VDATE%TYPE)
   RETURN BOOLEAN IS
   L_rowid                 ROWID;
   L_table                 VARCHAR2(30);
   L_key1                  VARCHAR2(100);
   L_key2                  VARCHAR2(100);
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
   -- cursors
   cursor C_SHIP_EXIST is
      select s.rowid
        from shipment s
       where s.shipment = I_shipment
         for update nowait;
BEGIN
   L_table := 'SHIPMENT';
   L_key1 := TO_CHAR(I_shipment);
   L_key2 := NULL;
   open C_SHIP_EXIST;
   fetch C_SHIP_EXIST into L_rowid;
   close C_SHIP_EXIST;
   update shipment s
      set s.status_code  = 'R',
          s.receive_date = TO_DATE(TO_CHAR(I_tran_date, 'YYYYMMDD'), 'YYYYMMDD')
    where s.rowid = L_rowid;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.UPD_SHIPMENT',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPD_SHIPMENT;
-----------------------------------------------------------------------------------
FUNCTION UNWANDED_CARTON(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                         O_unwanded       IN OUT  BOOLEAN,
                         I_carton         IN      SHIPSKU.CARTON%TYPE)
   RETURN BOOLEAN IS
   L_program      VARCHAR2(50) := 'STOCK_ORDER_RCV_SQL.UNWANDED_CARTON';
   L_exists_ind   VARCHAR2(1)  := 'N';
   cursor C_CARTON_EXISTS is
      select 'Y'
        from shipsku
       where carton = I_carton;
BEGIN
   if I_carton is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INV_PARM_PROG',
                                            L_program,
                                            'I_carton',
                                            I_carton);
      return FALSE;
   end if;
   open C_CARTON_EXISTS;
   fetch C_CARTON_EXISTS into L_exists_ind;
   close C_CARTON_EXISTS;
   O_unwanded := (L_exists_ind = 'N');
   if O_unwanded then
      O_error_message := SQL_LIB.CREATE_MSG('CARTON_NOT_EXISTS',
                                            NULL,
                                            NULL,
                                            NULL);
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_program,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UNWANDED_CARTON;
-----------------------------------------------------------------------------------
FUNCTION BOL_CHECK(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                   IO_bol_no        IN OUT  SHIPMENT.BOL_NO%TYPE,
                   I_carton         IN      SHIPSKU.CARTON%TYPE,
                   I_distro_no      IN      SHIPSKU.DISTRO_NO%TYPE)
RETURN BOOLEAN IS
   L_exists      VARCHAR2(1) := 'N';
   L_bol_no      shipment.bol_no%TYPE;
   L_function    VARCHAR2(30) := 'STOCK_ORDER_RCV_SQL.BOL_CHECK';
   -- cursors
   cursor C_CORRECT_BOL is
      select 'Y'
        from shipment s, shipsku ss
       where s.shipment = ss.shipment
         and s.bol_no = IO_bol_no
         and ss.carton = I_carton
         and ss.distro_no = I_distro_no;
   cursor C_GET_BOL is
      select s.bol_no
        from shipment s, shipsku  ss
       where s.shipment     = ss.shipment
         and NVL(ss.carton, ss.shipment) = NVL(I_carton, ss.shipment)
         and ss.distro_no   = I_distro_no;
BEGIN
   if I_distro_no is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('REQUIRED_INPUT_IS_NULL',
                                            to_char(I_distro_no),
                                            L_function,
                                            NULL);
      return FALSE;
   end if;
   open C_CORRECT_BOL;
   fetch C_CORRECT_BOL into L_exists;
   close C_CORRECT_BOL;
   if L_exists = 'Y' then
      return TRUE;
   end if;
   open C_GET_BOL;
   fetch C_GET_BOL into L_bol_no;
   close C_GET_BOL;
   ---
   if L_bol_no is NULL then
      if I_carton is NOT NULL then
         O_error_message := SQL_LIB.CREATE_MSG('BOL_NO_CARTON',
                                               I_carton,
                                               to_char(I_distro_no),
                                               NULL);
         return FALSE;
      else
         O_error_message := SQL_LIB.CREATE_MSG('BOL_NOT_FOUND',
                                               to_char(I_distro_no),
                                               NULL,
                                               NULL);
         return FALSE;
      end if;
   end if;
   IO_bol_no := L_bol_no;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.BOL_CHECK',
                                             TO_CHAR(SQLCODE));
      return FALSE;
END BOL_CHECK;
---------------------------------------------------------------------------------------------
FUNCTION WALK_THROUGH_STORE(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                            O_is_walk_through  IN OUT  BOOLEAN,
                            O_shipment         IN OUT  SHIPMENT.SHIPMENT%TYPE,
                            O_intended_store   IN OUT  STORE.STORE%TYPE,
                            I_bol_no           IN      SHIPMENT.BOL_NO%TYPE,
                            I_rcv_to_loc       IN      STORE.STORE%TYPE,
                            I_carton           IN      SHIPSKU.CARTON%TYPE)
   RETURN BOOLEAN IS
   L_program        VARCHAR2(64)    := 'STOCK_ORDER_RCV_SQL.WALK_THROUGH_STORE';
   L_dummy          VARCHAR2(1);
   L_shipment       shipment.shipment%TYPE;
   L_ship_to_loc    shipment.to_loc%TYPE;
   cursor C_SHIP_TO_LOC is
      select s.shipment, s.to_loc
        from shipment s,
             shipsku ss
       where s.shipment = ss.shipment
         and s.bol_no = I_bol_no
         and ss.carton = I_carton
         and to_loc_type = 'S';
   cursor C_WALK_THROUGH_STORE is
      select 'X'
        from walk_through_store
       where store = L_ship_to_loc
         and walk_through_store = I_rcv_to_loc;
BEGIN
   O_is_walk_through := FALSE;
   --
   -- Get the Shipment to location (store)
   --
   open C_SHIP_TO_LOC;
   fetch C_SHIP_TO_LOC into L_shipment, L_ship_to_loc;
   if C_SHIP_TO_LOC%NOTFOUND then
      -- BOL does not have a shipment or to_loc is a warehouse return to continue exception handling
      close C_SHIP_TO_LOC;
      return TRUE;
   end if;
   close C_SHIP_TO_LOC;
   --
   -- Validate that the shipment to location is a walk through store for the receipt to location
   --
   open C_WALK_THROUGH_STORE;
   fetch C_WALK_THROUGH_STORE into L_dummy;
   if C_WALK_THROUGH_STORE%NOTFOUND then
      -- it is not a walk through store return to continue exception handling
      close C_WALK_THROUGH_STORE;
      return TRUE;
   end if;
   close C_WALK_THROUGH_STORE;
   --
   O_is_walk_through := TRUE;
   O_shipment        := L_shipment;
   O_intended_store  := L_ship_to_loc;
   --
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_program,
                                            to_char(SQLCODE));
   RETURN FALSE;
END WALK_THROUGH_STORE;
-------------------------------------------------------------------------------
FUNCTION WRONG_STORE_RECEIPT(O_error_message         IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                             O_shipment              IN OUT  SHIPMENT.SHIPMENT%TYPE,
                             O_intended_to_loc       IN OUT  ITEM_LOC.LOC%TYPE,
                             I_actual_to_loc         IN      ITEM_LOC.LOC%TYPE,
                             I_actual_to_tsf_entity  IN      TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                             I_from_loc              IN      ITEM_LOC.LOC%TYPE,
                             I_from_loc_type         IN      ITEM_LOC.LOC_TYPE%TYPE,
                             I_from_tsf_entity       IN      TSF_ENTITY.TSF_ENTITY_ID%TYPE,
                             I_from_finisher         IN      VARCHAR2,
                             I_item                  IN      ITEM_MASTER.ITEM%TYPE,
                             I_bol_no                IN      SHIPMENT.BOL_NO%TYPE,
                             I_carton                IN      SHIPSKU.CARTON%TYPE,
                             I_distro_type           IN      SHIPSKU.DISTRO_TYPE%TYPE,
                             I_distro_no             IN      SHIPSKU.DISTRO_NO%TYPE,
                             I_dept                  IN      ITEM_MASTER.DEPT%TYPE,
                             I_class                 IN      ITEM_MASTER.CLASS%TYPE,
                             I_subclass              IN      ITEM_MASTER.SUBCLASS%TYPE,
                             I_pack_ind              IN      ITEM_MASTER.PACK_IND%TYPE,
                             I_pack_type             IN      ITEM_MASTER.PACK_TYPE%TYPE,
                             I_tran_date             IN      TRAN_DATA.TRAN_DATE%TYPE,
                             I_tsf_type              IN      TSFHEAD.TSF_TYPE%TYPE)          -- Transfer and Item Valuation
   RETURN BOOLEAN IS
   L_function                   VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.WRONG_STORE_RECEIPT';
   L_shipment                   shipment.shipment%TYPE;
   L_item_loc_exists            BOOLEAN;
   L_item                       item_master.item%TYPE;
   L_intended_to_loc            item_loc.loc%TYPE;
   L_intended_to_loc_type       item_loc.loc_type%TYPE;
   L_intended_tsf_entity        tsf_entity.tsf_entity_id%TYPE        := NULL;
   L_entity_name                tsf_entity.tsf_entity_desc%TYPE      := NULL;
   L_ship_seq_no                shipsku.seq_no%TYPE;
   L_tsf_seq_no                 tsfdetail.tsf_seq_no%TYPE;
   L_ship_qty                   shipsku.qty_expected%TYPE;
   L_from_av_cost               item_loc_soh.av_cost%TYPE;
   L_total_chrgs_prim           item_exp_detail.est_exp_value%TYPE;
   L_profit_chrgs_to_loc        item_loc_soh.av_cost%TYPE;
   L_exp_chrgs_to_loc           item_loc_soh.av_cost%TYPE;
   L_pack_total_chrgs_prim      item_exp_detail.est_exp_value%TYPE;
   L_pack_profit_chrgs_to_loc   item_loc_soh.av_cost%TYPE;
   L_pack_exp_chrgs_to_loc      item_loc_soh.av_cost%TYPE;
   L_pack_loc_av_cost           item_loc_soh.av_cost%TYPE;
   L_receive_as_type            item_loc.receive_as_type%TYPE        := NULL;
   L_pct_in_pack                NUMBER;
   L_finisher                   BOOLEAN := FALSE;
   L_intercompany               BOOLEAN := FALSE;
   L_dummy_name                 partner.partner_desc%TYPE;
   L_from_wac                   item_loc_soh.av_cost%TYPE;         -- Transfers and Item Valuation
   L_tsf_alloc_unit_cost        item_loc_soh.av_cost%TYPE := NULL; -- Transfers and Item Valuation
   L_weight_expected            ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;  -- Catch Weight
   L_weight_expected_uom        UOM_CLASS.UOM%TYPE;                -- Catch Weight
   L_weight_expected_cuom       ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE;  -- Catch Weight
   L_cuom                       UOM_CLASS.UOM%TYPE;                -- Catch Weight
   -- cursors
   cursor C_SHIPMENT is
      select s.shipment, s.to_loc, s.to_loc_type, ss.seq_no, ss.qty_expected,
             ss.weight_expected, ss.weight_expected_uom
      from shipment s, shipsku ss
      where s.bol_no = I_bol_no
      and s.shipment = ss.shipment
      and ss.item = I_item
      and ss.carton = I_carton
      and ss.distro_no = I_distro_no;
   cursor C_TSF_SEQ_NO is
      select tsf_seq_no
        from tsfdetail
       where tsf_no = I_distro_no
         and item = I_item;
   cursor C_GET_ILS_AMOUNTS is
      select ils.av_cost
        from item_loc_soh ils,
             item_loc il
       where ils.item = L_item
         and ils.loc  = I_from_loc
         and il.item  = ils.item
         and il.loc   = ils.loc;
   cursor C_ITEM_IN_PACK is
      select v.item,
             v.qty,
             im.dept,
             im.class,
             im.subclass,
             im.inventory_ind
        from item_master im,
             v_packsku_qty v
       where v.pack_no = I_item
         and im.item   = v.item;
BEGIN
   open C_SHIPMENT;
   fetch C_SHIPMENT into L_shipment, L_intended_to_loc, L_intended_to_loc_type, L_ship_seq_no, L_ship_qty, L_weight_expected, L_weight_expected_uom;
   if C_SHIPMENT%NOTFOUND then
      close C_SHIPMENT;
      return FALSE;
   else
      O_intended_to_loc := L_intended_to_loc;
      O_shipment := L_shipment;
   end if;
   close C_SHIPMENT;
   -- Catch Weight
   if L_weight_expected is NOT NULL then
      if CATCH_WEIGHT_SQL.CONVERT_WEIGHT(O_error_message,
                                         L_weight_expected_cuom,
                                         L_cuom,
                                         I_item,
                                         L_weight_expected,
                                         L_weight_expected_uom) = FALSE then
         return FALSE;
      end if;
   end if;
   -- End Catch Weight
   --if the intended to loc and acutal to loc are not in the same
   --tsf entity do not allow wrong store receipt
   if I_distro_type = 'T' then
      if LP_system_options_row.intercompany_transfer_ind = 'Y' then
         if LOCATION_ATTRIB_SQL.GET_ENTITY(O_error_message,
                                           L_intended_tsf_entity,
                                           L_entity_name,
                                           L_intended_to_loc,
                                           L_intended_to_loc_type) = FALSE then
            return FALSE;
         end if;
         if I_actual_to_tsf_entity != L_intended_tsf_entity then
            O_error_message := SQL_LIB.CREATE_MSG('WRNG_STR_RECV_DIF_ENTITY', NULL,
                                                  NULL,NULL);
            return FALSE;
         end if;
      end if;
      open C_TSF_SEQ_NO;
      fetch C_TSF_SEQ_NO into L_tsf_seq_no;
      close C_TSF_SEQ_NO;
   else
      L_tsf_seq_no := NULL;
   end if;
--   L_intercompany := (I_from_tsf_entity != I_actual_to_tsf_entity);
--  InterCompany or IntraCompany??   --Transfers and Item Valuation
   if TRANSFER_SQL.IS_INTERCOMPANY(O_error_message,
                                   L_intercompany,
                                   I_distro_type,
                                   I_tsf_type,
                                   I_from_loc,
                                   I_from_loc_type,
                                   L_intended_to_loc,
                                   L_intended_to_loc_type) = FALSE THEN
      return FALSE;
   end if;
-- End Transfers and Item valuation
   if NEW_ITEM_LOC(O_error_message,
                   I_item,
                   I_actual_to_loc,
                   NULL, NULL, 'S', NULL,
                   I_dept,
                   I_class,
                   I_subclass,
                   NULL, NULL,
                   NULL, NULL, NULL, NULL, NULL,
                   I_pack_ind,
                   NULL, NULL, NULL, NULL, NULL, NULL,
                   NULL, NULL, NULL, NULL, NULL, NULL,
                   NULL, NULL, NULL, NULL, NULL, NULL,
                   NULL, NULL, NULL, NULL, NULL) = FALSE then
      return FALSE;
   end if;
   --update in-transit qty for old location
   --update weighted avg cost for old location
   if I_pack_ind = 'N' then
      L_item := I_item;
          -- Transfers and Item Valuation
      if ITEMLOC_ATTRIB_SQL.GET_WAC(O_error_message,
                                    L_from_wac,            -- Transfer and Item Valuation
                                    I_item,
                                    I_dept,
                                    I_class,
                                    I_subclass,
                                    I_actual_to_loc,
                                    'S',
                                    I_tran_date) = FALSE then
             return FALSE;
      end if;
          -- Transfers and Item Valuation END
      if I_distro_type = 'T' then --shipment for transfer
         if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS( O_error_message,
                                                         L_total_chrgs_prim,
                                                         L_profit_chrgs_to_loc,
                                                         L_exp_chrgs_to_loc,
                                                         'T',
                                                         I_distro_no,
                                                         L_tsf_seq_no,
                                                         NULL,
                                                         NULL,
                                                         I_item,      --item
                                                         NULL,        --pack no
                                                         I_from_loc,
                                                         I_from_loc_type,
                                                         L_intended_to_loc,
                                                         'S') = FALSE then
            return FALSE;
         end if;
      else --shipment for allocation
         if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS( O_error_message,
                                                         L_total_chrgs_prim,
                                                         L_profit_chrgs_to_loc,
                                                         L_exp_chrgs_to_loc,
                                                         'A',
                                                         I_distro_no,
                                                         NULL,
                                                         NULL,
                                                         NULL,
                                                         I_item,      --item
                                                         NULL,        --pack no
                                                         I_from_loc,
                                                         I_from_loc_type,
                                                         L_intended_to_loc,
                                                         'S') = FALSE then
            return FALSE;
         end if;
      end if;
      if UPD_TO_ITEM_LOC(O_error_message,
                         I_distro_no,
                         I_distro_type,
                         I_item,
                         NULL,  --pack no
                         NULL,  --percent of pack value
                         L_receive_as_type,
                         L_intended_to_loc,
                         L_intended_to_loc_type,
                         (L_ship_qty *-1),
                         (L_weight_expected_cuom*-1), -- Catch Weight
                         L_cuom,                      -- Catch Weight
                         I_from_loc,
                         I_from_loc_type,
                         L_from_wac,                  -- Transfer and Item Valuation
                         L_total_chrgs_prim,
                         L_intercompany) = FALSE then
         return FALSE;
      end if;
      --write reverse tran data rec to back out recs that where written when shipped
      if STKLEDGR_SQL.WRITE_FINANCIALS(O_error_message,
                                       L_tsf_alloc_unit_cost,
                                       I_distro_type,
                                       L_shipment,
                                       I_distro_no,
                                       I_tran_date,
                                       I_item,
                                       NULL,   --pack no
                                       L_pct_in_pack, --null
                                       I_dept,
                                       I_class,
                                       I_subclass,
                                       (L_ship_qty * -1),
                                       (L_weight_expected_cuom*-1), -- Catch Weight
                                       I_from_loc,
                                       I_from_loc_type,
                                       I_from_finisher,
                                       L_intended_to_loc,
                                       L_intended_to_loc_type,
                                       'N',
                                       L_from_wac,                  -- Transfer and Item Valuation
                                       L_profit_chrgs_to_loc,
                                       L_exp_chrgs_to_loc,
                                       L_intercompany) = FALSE then
         return FALSE;
      end if;
      if UPD_TO_ITEM_LOC(O_error_message,
                         I_distro_no,
                         I_distro_type,
                         I_item,
                         NULL,   --pack no
                         NULL,   --percent of pack
                         L_receive_as_type,
                         I_actual_to_loc,
                         'S',
                         L_ship_qty,
                         L_weight_expected_cuom, -- Catch Weight
                         L_cuom,                 -- Catch Weight
                         I_from_loc,
                         I_from_loc_type,
                         L_from_wac,             -- Transfer and Item Valuation
                         L_total_chrgs_prim,
                         L_intercompany) = FALSE then
         return FALSE;
      end if;
      if STKLEDGR_SQL.WRITE_FINANCIALS(O_error_message,
                                       L_tsf_alloc_unit_cost,
                                       I_distro_type,
                                       L_shipment,
                                       I_distro_no,
                                       I_tran_date,
                                       I_item,
                                       NULL,                   --pack no
                                       L_pct_in_pack,          --null
                                       I_dept,
                                       I_class,
                                       I_subclass,
                                       L_ship_qty,
                                       L_weight_expected_cuom, -- Catch Weight
                                       I_from_loc,
                                       I_from_loc_type,
                                       I_from_finisher,
                                       I_actual_to_loc,
                                       'S',  --to loc type
                                       'N', --to finisher
                                       L_from_wac,             -- Transfer and Item Valuation
                                       L_profit_chrgs_to_loc,
                                       L_exp_chrgs_to_loc,
                                       L_intercompany) = FALSE then
         return FALSE;
      end if;
   else --pack
      if I_pack_type != 'B' then
         if I_distro_type = 'T' then
            if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS( O_error_message,
                                                            L_pack_total_chrgs_prim,
                                                            L_pack_profit_chrgs_to_loc,
                                                            L_pack_exp_chrgs_to_loc,
                                                            'T',
                                                            I_distro_no,
                                                            L_tsf_seq_no,
                                                            NULL,
                                                            NULL,
                                                            I_item,
                                                            NULL,
                                                            I_from_loc,
                                                            I_from_loc_type,
                                                            L_intended_to_loc,
                                                            'S') = FALSE then
               return FALSE;
            end if;
         else  -- shipment for allocation
            if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS( O_error_message,
                                                            L_pack_total_chrgs_prim,
                                                            L_pack_profit_chrgs_to_loc,
                                                            L_pack_exp_chrgs_to_loc,
                                                            'A',
                                                            I_distro_no,
                                                            NULL,
                                                            NULL,
                                                            NULL,
                                                            I_item,
                                                            NULL,
                                                            I_from_loc,
                                                            I_from_loc_type,
                                                            L_intended_to_loc,
                                                            'S') = FALSE then
               return FALSE;
            end if;
         end if;
         if ITEMLOC_ATTRIB_SQL.GET_AV_COST(O_error_message,
                                           I_item,
                                           I_from_loc,
                                           I_from_loc_type,
                                           L_pack_loc_av_cost) = FALSE then
            return FALSE;
         end if;
      end if; --Pack type != 'B'
      FOR rec in C_ITEM_IN_PACK LOOP
         --Get av_cost for each component item
         L_item := rec.item;
         open C_GET_ILS_AMOUNTS;
         fetch C_GET_ILS_AMOUNTS into L_from_av_cost;
         close C_GET_ILS_AMOUNTS;
             -- Transfers and Item Valuation
         if ITEMLOC_ATTRIB_SQL.GET_WAC(O_error_message,
                                       L_from_wac,            -- Transfer and Item Valuation
                                       L_item,
                                       rec.dept,
                                       rec.class,
                                       rec.subclass,
                                       I_actual_to_loc,
                                       'S',
                                       I_tran_date) = FALSE then
                return FALSE;
         end if;
             -- Transfers and Item Valuation END
         if I_pack_type != 'B' then
            --******************************************************************************
            -- Value returned in L_pack_profit_chrgs_to_loc, L_pack_exp_chrgs_to_loc, and
            -- L_pack_total_chrgs_prim are unit values for the entire pack.  Need to take
            -- a proportionate piece of the value for each component item in the pack
            -- The formula for this is:
            --       [Pack Value * (Comp Item Avg Cost * Comp Qty in the Pack) /
            --                     (Total Pack Avg Cost)] /
            --       Comp Qty in the Pack
            -- You must divide the value by the Component Item Qty in the pack because the
            -- value will be for one pack.  In order to get a true unit value you need to
            -- do the last division.  Since we multiple by Comp Qty and then divide by it,
            -- it can be removed from the calculation completely.
            --******************************************************************************
            L_profit_chrgs_to_loc := L_pack_profit_chrgs_to_loc * L_from_av_cost / L_pack_loc_av_cost;
            L_exp_chrgs_to_loc    := L_pack_exp_chrgs_to_loc    * L_from_av_cost / L_pack_loc_av_cost;
            L_total_chrgs_prim    := L_pack_total_chrgs_prim    * L_from_av_cost / L_pack_loc_av_cost;
         else  --I_pack_type = 'B'
            if I_distro_type  = 'T' then
               if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS( O_error_message,
                                                               L_total_chrgs_prim,
                                                               L_profit_chrgs_to_loc,
                                                               L_exp_chrgs_to_loc,
                                                               'T',
                                                               I_distro_no,
                                                               L_tsf_seq_no,
                                                               NULL,
                                                               NULL,
                                                               rec.item,      --item
                                                               I_item,        --pack no
                                                               I_from_loc,
                                                               I_from_loc_type,
                                                               L_intended_to_loc,
                                                               'S') = FALSE then
                  return FALSE;
               end if;
            else
               if UP_CHARGE_SQL.CALC_TSF_ALLOC_ITEM_LOC_CHRGS( O_error_message,
                                                               L_total_chrgs_prim,
                                                               L_profit_chrgs_to_loc,
                                                               L_exp_chrgs_to_loc,
                                                               'A',
                                                               I_distro_no,
                                                               NULL,
                                                               NULL,
                                                               NULL,
                                                               rec.item,      --item
                                                               I_item,        --pack no
                                                               I_from_loc,
                                                               I_from_loc_type,
                                                               L_intended_to_loc,
                                                               'S') = FALSE then
                  return FALSE;
               end if;
            end if; --distro type
         end if; -- pack type = B
         if TRANSFER_COST_SQL.PCT_IN_PACK(O_error_message,
                                          L_pct_in_pack,
                                          I_item,
                                          rec.item,
                                          I_from_loc) = FALSE then
            return FALSE;
         end if;
         if rec.inventory_ind = 'Y' then
            if UPD_TO_ITEM_LOC(O_error_message,
                               I_distro_no,
                               I_distro_type,
                               rec.item,
                               I_item,
                               L_pct_in_pack,
                               L_receive_as_type,
                               L_intended_to_loc,
                               L_intended_to_loc_type,
                               (L_ship_qty * rec.qty *-1),
                               (L_weight_expected_cuom*-1), -- Catch Weight
                               L_cuom,                      -- Catch Weight
                               I_from_loc,
                               I_from_loc_type,
                               L_from_wac,                  -- Transfer and Item Valuation
                               L_total_chrgs_prim,
                               L_intercompany) = FALSE then
               return FALSE;
            end if;
         end if;
         --write reverse tran data rec to back out recs that where written when shipped
         if STKLEDGR_SQL.WRITE_FINANCIALS(O_error_message,
                                          L_tsf_alloc_unit_cost,
                                          I_distro_type,
                                          L_shipment,
                                          I_distro_no,
                                          I_tran_date,
                                          rec.item,
                                          I_item,
                                          L_pct_in_pack,
                                          rec.dept,
                                          rec.class,
                                          rec.subclass,
                                          (L_ship_qty * rec.qty * -1),
                                          (L_weight_expected_cuom*-1), -- Catch Weight
                                          I_from_loc,
                                          I_from_loc_type,
                                          I_from_finisher,
                                          L_intended_to_loc,
                                          L_intended_to_loc_type,
                                          'N',
                                          L_from_wac,                  -- Transfer ans Item Valuation
                                          L_profit_chrgs_to_loc,
                                          L_exp_chrgs_to_loc,
                                          L_intercompany) = FALSE then
            return FALSE;
         end if;
         if rec.inventory_ind = 'Y' then
            if UPD_TO_ITEM_LOC(O_error_message,
                               I_distro_no,
                               I_distro_type,
                               rec.item,
                               I_item,
                               L_pct_in_pack,
                               L_receive_as_type,
                               I_actual_to_loc,
                               'S',
                               (L_ship_qty * rec.qty),
                               L_weight_expected_cuom, -- Catch Weight
                               L_cuom,                 -- Catch Weight
                               I_from_loc,
                               I_from_loc_type,
                               L_from_wac,             -- Transfer and Item Valuation
                               L_total_chrgs_prim,
                               L_intercompany) = FALSE then
               return FALSE;
            end if;
         end if;
         if STKLEDGR_SQL.WRITE_FINANCIALS(O_error_message,
                                          L_tsf_alloc_unit_cost,
                                          I_distro_type,
                                          L_shipment,
                                          I_distro_no,
                                          I_tran_date,
                                          rec.item,
                                          I_item,
                                          L_pct_in_pack,
                                          rec.dept,
                                          rec.class,
                                          rec.subclass,
                                          (L_ship_qty * rec.qty),
                                          L_weight_expected_cuom, -- Catch Weight
                                          I_from_loc,
                                          I_from_loc_type,
                                          I_from_finisher,
                                          I_actual_to_loc,
                                          'S',                    --to loc type
                                          'N',                    --to finisher
                                          L_from_wac,             -- Transfer and Item Valuation
                                          L_profit_chrgs_to_loc,
                                          L_exp_chrgs_to_loc,
                                          L_intercompany) = FALSE then
            return FALSE;
         end if;
      END LOOP; --pack comp
   end if; --end pack
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_function,
                                            TO_CHAR(SQLCODE));
END WRONG_STORE_RECEIPT;
-------------------------------------------------------------------------------
FUNCTION UPD_TO_ITEM_LOC(O_error_message    IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                         I_distro_no        IN      SHIPSKU.DISTRO_NO%TYPE,
                         I_distro_type      IN      APPT_DETAIL.DOC_TYPE%TYPE,
                         I_item             IN      ITEM_MASTER.ITEM%TYPE,
                         I_pack_no          IN      ITEM_MASTER.ITEM%TYPE,
                         I_percent_in_pack  IN      NUMBER,
                         I_receive_as_type  IN      ITEM_LOC.RECEIVE_AS_TYPE%TYPE,
                         I_to_loc           IN      ITEM_LOC.LOC%TYPE,
                         I_to_loc_type      IN      ITEM_LOC.LOC_TYPE%TYPE,
                         I_qty              IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                         I_weight_cuom      IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,  -- Catch Weight
                         I_cuom             IN      UOM_CLASS.UOM%TYPE,                -- Catch Weight
                         I_from_loc         IN      ITEM_LOC.LOC%TYPE,
                         I_from_loc_type    IN      ITEM_LOC.LOC_TYPE%TYPE,
                         I_from_wac         IN      ITEM_LOC_SOH.AV_COST%TYPE,         -- changed from av_cost to wac for Transfers and Item Valuation
                         I_prim_charge      IN      ITEM_LOC_SOH.AV_COST%TYPE,
                         I_intercompany     IN      BOOLEAN)
   RETURN BOOLEAN IS
   L_function              VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.UPD_TO_ITEM_LOC';
   L_upd_av_cost         item_loc_soh.av_cost%TYPE;
   L_charge_to_loc       item_loc_soh.av_cost%TYPE;
   L_new_wac             item_loc_soh.av_cost%TYPE;
   L_neg_soh_wac_adj_amt item_loc_soh.av_cost%TYPE;
   L_qty                 ITEM_LOC_SOH.STOCK_ON_HAND%TYPE;  -- Catch Weight
   L_rowid                 ROWID;
   L_table                 VARCHAR2(30);
   L_key1                  VARCHAR2(100);
   L_key2                  VARCHAR2(100);
   RECORD_LOCKED           EXCEPTION;
   PRAGMA                  EXCEPTION_INIT(Record_Locked, -54);
   -- cursors
   cursor C_LOCK_TO_ILS is
      select ils.rowid
        from item_loc_soh ils
       where ils.item = I_item
         and ils.loc  = I_to_loc
         for update nowait;
BEGIN
   L_table := 'ITEM_LOC_SOH';
   L_key1 := I_item;
   L_key2 := TO_CHAR(I_to_loc);
   open C_LOCK_TO_ILS;
   fetch C_LOCK_TO_ILS into  L_rowid;
   close C_LOCK_TO_ILS;
   -- Update stock buckets by weight if simple pack catch weight component item's suom is Mass.
   -- WAC should be updated based on how stock buckets are updated.
   if I_weight_cuom is not NULL then
      if CATCH_WEIGHT_SQL.CALC_COMP_UPDATE_QTY(O_error_message,
                                               L_qty,
                                               I_item,
                                               I_qty,
                                               I_weight_cuom,
                                               I_cuom) = FALSE then
         return FALSE;
      end if;
   else
      L_qty := I_qty;
   end if;
   --convert chrg from primary to to_loc's currency
   if CURRENCY_SQL.CONVERT_BY_LOCATION(O_error_message,
                                       NULL,
                                       NULL,
                                       NULL,
                                       I_to_loc,
                                       'S',
                                       NULL,
                                       I_prim_charge,
                                       L_charge_to_loc,
                                       'C',
                                       NULL,
                                       NULL) = FALSE then
      return FALSE;
   end if;
   if TRANSFER_COST_SQL.RECALC_WAC(O_error_message,
                                   L_upd_av_cost,
                                   I_distro_no,
                                   I_distro_type,
                                   I_item,
                                   I_pack_no,
                                   I_percent_in_pack,
                                   I_from_loc,
                                   I_from_loc_type,
                                   I_to_loc,
                                   I_to_loc_type,
                                   L_qty,
                                   I_weight_cuom,              -- Catch Weight
                                   I_from_wac,                 -- Catch Weight
                                   L_charge_to_loc,
                                   I_intercompany) = FALSE then
      return FALSE;
   end if;
   update item_loc_soh ils
      set ils.in_transit_qty   = DECODE(I_receive_as_type,
                                        'P', ils.in_transit_qty,
                                        ils.in_transit_qty + L_qty),
          ils.pack_comp_intran = DECODE(I_receive_as_type,
                                        'P', ils.pack_comp_intran + L_qty,
                                        ils.pack_comp_intran),
          ils.av_cost          = ROUND(L_upd_av_cost, 4),
          last_update_id       = USER,
          last_update_datetime = SYSDATE
    where ils.rowid = L_rowid;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            'STOCK_ORDER_RCV_SQL.UPD_TO_ITEM_LOC',
                                            to_char(SQLCODE));
   return FALSE;
END UPD_TO_ITEM_LOC;
-------------------------------------------------------------------------------
FUNCTION UPD_ITEM_RESV_EXP(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                           I_item           IN      ITEM_MASTER.ITEM%TYPE,
                           I_tsf_no         IN      TSFHEAD.TSF_NO%TYPE,
                           I_recv_loc       IN      ITEM_LOC.LOC%TYPE,
                           I_recv_loc_type  IN      ITEM_LOC.LOC_TYPE%TYPE,
                           I_qty            IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
   RETURN BOOLEAN IS
   L_function       VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.UPD_ITEM_RESV_EXP';
   L_final_recv_loc item_loc.loc%TYPE;
   L_exists         BOOLEAN;
   L_upd_item       item_master.item%TYPE;
   cursor C_GET_FINAL_RCV_LOC is
      select to_loc
        from tsfhead
       where tsf_parent_no = I_tsf_no;
   cursor C_LOCK_FINISHER is
      select 'x'
        from item_loc_soh
       where item = I_item
         and loc= I_recv_loc
         for update nowait;
   cursor C_LOCK_FINAL_RCV_LOC is
      select 'X'
        from item_loc_soh
       where item = L_upd_item
         and loc = L_final_recv_loc
         for update nowait;
BEGIN
   open C_GET_FINAL_RCV_LOC;
   fetch C_GET_FINAL_RCV_LOC into L_final_recv_loc;
   close C_GET_FINAL_RCV_LOC;
   --Determine if the item is on the transform table.
   if ITEM_XFORM_PACK_SQL.GET_XFORM_TO_ITEM(O_error_message,
                                            L_exists,
                                            L_upd_item,
                                            I_tsf_no,
                                            I_item) = FALSE then
      return FALSE;
   end if;
   if L_exists = FALSE then
      L_upd_item := I_item;
   end if;
   open C_LOCK_FINISHER;
   close C_LOCK_FINISHER;
   --reserve item at receiving finisher loc
   update item_loc_soh
      set tsf_reserved_qty     = nvl(tsf_reserved_qty,0) + I_qty,
          last_update_id       = USER,
          last_update_datetime = SYSDATE
    where item = I_item
      and loc  = I_recv_loc;
   open C_LOCK_FINAL_RCV_LOC;
   close C_LOCK_FINAL_RCV_LOC;
   --Update to item expected qty at final receiving loc
   --It is not possible to determine if xformed item will be packed so pack_comp_exp is never incremented.
   --This is accounted for when the second leg is sent from the finisher.
   update item_loc_soh
      set tsf_expected_qty     = nvl(tsf_expected_qty, 0) + I_qty,
          last_update_id       = USER,
          last_update_datetime = SYSDATE
    where item = L_upd_item
      and loc  = L_final_recv_loc;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_function,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPD_ITEM_RESV_EXP;
-------------------------------------------------------------------------------
FUNCTION NEW_RECEIPT_ITEM(O_error_message   IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                          O_item_rec        IN OUT  STOCK_ORDER_RCV_SQL.ITEM_RCV_RECORD,
                          I_shipment        IN      SHIPMENT.SHIPMENT%TYPE,
                          I_from_inv_status IN      SHIPSKU.INV_STATUS%TYPE,
                          I_carton          IN      SHIPSKU.CARTON%TYPE,
                          I_qty             IN      ITEM_LOC_SOH.STOCK_ON_HAND%TYPE,
                          I_weight          IN      ITEM_LOC_SOH.AVERAGE_WEIGHT%TYPE,   -- Catch Weight
                          I_weight_uom      IN      UOM_CLASS.UOM%TYPE)                 -- CatchWeight
   RETURN BOOLEAN IS
   L_function       VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.NEW_RECEIPT_ITEM';
   L_supp_pack_size       item_supp_country.supp_pack_size%TYPE := NULL;
   L_qty                  item_loc_soh.stock_on_hand%TYPE       := 0;
   L_av_cost              item_loc_soh.av_cost%TYPE             := NULL;
   L_unit_cost            item_loc_soh.unit_cost%TYPE           := NULL;
   L_unit_retail          item_loc.unit_retail%TYPE             := NULL;
   L_selling_unit_retail  item_loc.selling_unit_retail%TYPE     := NULL;
   L_selling_uom          item_loc.selling_uom%TYPE             := NULL;
   L_tsf_exist            varchar2(1)                           :='N';
   cursor C_TSFDETAIL_EXISTS is
      select 'x'
        from tsfdetail
       where tsf_no = O_item_rec.tsf_no
         and item   = O_item_rec.item;
BEGIN
   -- for non-orderable packs (pack_type of NULL), use 1 as supp_pack_size
   if O_item_rec.pack_ind = 'Y' and O_item_rec.pack_type = 'N' then
      L_supp_pack_size := 1;
   else
      if SUPP_ITEM_ATTRIB_SQL.GET_SUPP_PACK_SIZE(O_error_message,
                                                 L_supp_pack_size,
                                                 O_item_rec.item,
                                                 NULL,
                                                 NULL) = FALSE then
         return FALSE;
      end if;
   end if;
   -- call new BOL functions that populate LP_bol_rec...specifically for RECEIPTS
   if BOL_SQL.RECEIPT_PUT_BOL(O_error_message,
                              O_item_rec.bol_no,
                              O_item_rec.to_loc_phy,
                              O_item_rec.tran_date,
                              I_shipment,
                              O_item_rec.from_loc_phy,
                              O_item_rec.to_loc_type,
                              O_item_rec.from_loc_type,
                              O_item_rec.tsf_no,
                              O_item_rec.tsf_status,
                              O_item_rec.tsf_type) = FALSE then
      return FALSE;
   end if;
   open C_TSFDETAIL_EXISTS;
   fetch C_TSFDETAIL_EXISTS into L_tsf_exist;
   close C_TSFDETAIL_EXISTS;
   if BOL_SQL.RECEIPT_PUT_TSF_ITEM(O_error_message,
                                   O_item_rec.tsf_seq_no,
                                   O_item_rec.ss_seq_no,
                                   O_item_rec.tsf_no,
                                   O_item_rec.item,
                                   I_carton,
                                   I_qty,
                                   I_weight,        -- Catch Weight
                                   I_weight_uom,    -- Catch Weight
                                   I_from_inv_status,
                                   O_item_rec.from_loc_phy,
                                   O_item_rec.from_loc_type,
                                   O_item_rec.to_loc_phy,
                                   O_item_rec.to_loc_type,
                                   O_item_rec.distro_to_loc,
                                   O_item_rec.distro_from_loc,
                                   O_item_rec.tsf_type,
                                   O_item_rec.ref_item,
                                   O_item_rec.dept,
                                   O_item_rec.class,
                                   O_item_rec.subclass,
                                   O_item_rec.pack_ind,
                                   O_item_rec.pack_type,
                                   O_item_rec.simple_pack_ind,
                                   O_item_rec.catch_weight_ind,
                                   L_supp_pack_size,
                                   O_item_rec.sellable_ind,
                                   O_item_rec.item_xform_ind) = FALSE then
      return FALSE;
   end if;
   if BOL_SQL.PROCESS_TSF(O_error_message) = FALSE then
      return FALSE;
   end if;
   if BOL_SQL.FLUSH_BOL_PROCESS(O_error_message) = FALSE then
      return FALSE;
   end if;
   if L_tsf_exist !='x' then
      -- don't need to lock tsfdetail since this record was just created
      update tsfdetail td
         set td.received_qty = nvl(td.received_qty, 0) + I_qty
       where td.tsf_no     = O_item_rec.tsf_no
         and td.tsf_seq_no = O_item_rec.tsf_seq_no;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_function,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END NEW_RECEIPT_ITEM;
-------------------------------------------------------------------------------
FUNCTION GET_INV_STATUS(O_error_message  IN OUT  RTK_ERRORS.RTK_TEXT%TYPE,
                        O_inv_status     IN OUT  SHIPSKU.INV_STATUS%TYPE,
                        I_shipment       IN      SHIPSKU.SHIPMENT%TYPE,
                        I_distro_no      IN      SHIPSKU.DISTRO_NO%TYPE,
                        I_distro_type    IN      SHIPSKU.DISTRO_TYPE%TYPE,
                        I_carton         IN      SHIPSKU.CARTON%TYPE,
                        I_item           IN      SHIPSKU.ITEM%TYPE)
RETURN BOOLEAN IS
   L_function       VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.GET_INV_STATUS';
   cursor C_INV_STATUS is
      select inv_status
        from shipsku
       where shipment          = I_shipment
         and item              = I_item
         and distro_no         = I_distro_no
         and distro_type       = I_distro_type
         and NVL(carton,shipment) = NVL(I_carton,shipment);
BEGIN
   open  C_INV_STATUS;
   fetch C_INV_STATUS into O_inv_status;
   close C_INV_STATUS;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_function,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END GET_INV_STATUS;
-------------------------------------------------------------------------------
FUNCTION MRT_LINE_ITEM(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                       I_mrt_no        IN     MRT_ITEM_LOC.MRT_NO%TYPE,
                       I_item          IN     MRT_ITEM_LOC.ITEM%TYPE,
                       I_location      IN     MRT_ITEM_LOC.LOCATION%TYPE,
                       I_received_qty  IN     MRT_ITEM_LOC.RECEIVED_QTY%TYPE)
RETURN BOOLEAN IS
L_function      VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.MRT_LINE_ITEM';
--
L_rowid         ROWID := null;
--
L_table         VARCHAR2(30);
L_key1          VARCHAR2(100);
L_key2          VARCHAR2(100);
RECORD_LOCKED   EXCEPTION;
PRAGMA          EXCEPTION_INIT(RECORD_LOCKED, -54);
cursor C_MRT_ITEM_LOC is
select rowid
  from mrt_item_loc
 where mrt_no = I_mrt_no
   and item = I_item
   and location = I_location
   for update of received_qty nowait;
BEGIN
   L_table := 'MRT_ITEM_LOC';
   L_key1 := to_char(I_mrt_no);
   L_key2 := to_char(I_item) || '-' || to_char(I_location);
   open C_MRT_ITEM_LOC;
   fetch C_MRT_ITEM_LOC into L_rowid;
   close C_MRT_ITEM_LOC;
   if L_rowid is not null then
      update mrt_item_loc
         set received_qty = nvl(received_qty, 0) + nvl(I_received_qty, 0)
       where rowid = L_rowid;
   end if;
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                             L_table,
                                             L_key1,
                                             L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_function,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END MRT_LINE_ITEM;
-------------------------------------------------------------------------------
FUNCTION UPDATE_WF_BILLING(O_error_message   IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                           I_item_rec        IN       ITEM_MASTER%ROWTYPE,
                           I_distro_no       IN       SHIPSKU.DISTRO_NO%TYPE,
                           I_distro_type     IN       SHIPSKU.DISTRO_TYPE%TYPE,
                           I_rma_no          IN       WF_RETURN_HEAD.RMA_NO%TYPE,
                           I_orderable_qty   IN       WF_RETURN_DETAIL.RETURNED_QTY%TYPE)
RETURN BOOLEAN IS
   L_function           VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.UPDATE_WF_BILLING';
   L_customer_loc       WF_RETURN_HEAD.CUSTOMER_LOC%TYPE         := NULL;
   L_vat_code           VAT_ITEM.VAT_CODE%TYPE                   := NULL;
   --
   L_orderable_cost     ITEM_LOC.UNIT_RETAIL%TYPE;
   L_from_loc           ITEM_LOC.LOC%TYPE;
   L_to_loc             ITEM_LOC.LOC%TYPE;
   L_unit_restock_fee   WF_RETURN_DETAIL.UNIT_RESTOCK_FEE%TYPE;
   L_tax_info_tbl       OBJ_TAX_INFO_TBL := OBJ_TAX_INFO_TBL();
   L_tax_info_rec       OBJ_TAX_INFO_REC := OBJ_TAX_INFO_REC();
   cursor C_GET_RETURN_DETAILS_DISTRO is
   select wfrh.customer_loc,
          wfoh.cust_ord_ref_no,
          wfrd.wf_order_no,
          wfrh.rma_no,
          wfrd.returned_qty,
          wfrd.return_unit_cost,
          wfrd.unit_restock_fee,
          MAX(wfod.vat_rate) vat_rate
     from tsfhead th,
          wf_return_head wfrh,
          wf_return_detail wfrd,
          wf_order_head wfoh,
          wf_order_detail wfod
    where th.tsf_no         = I_distro_no
      and TO_CHAR(wfrh.rma_no)       = th.ext_ref_no
      and wfrd.rma_no       = wfrh.rma_no
      and wfrd.item         = I_item_rec.item
      and wfoh.wf_order_no  = wfrd.wf_order_no
      and wfod.wf_order_no  = wfoh.wf_order_no
      and wfod.item         = wfrd.item
      and wfod.customer_loc = wfrh.customer_loc
      group by wfrh.customer_loc,
               wfoh.cust_ord_ref_no,
               wfrd.wf_order_no,
               wfrh.rma_no,
               wfrd.returned_qty,
               wfrd.return_unit_cost,
               wfrd.unit_restock_fee;
   cursor C_GET_RETURN_DETAILS_RMA is
   select wfrh.customer_loc,
          wfoh.cust_ord_ref_no,
          wfrd.wf_order_no,
          wfrh.rma_no,
          wfrd.returned_qty,
          wfrd.return_unit_cost,
          wfrd.unit_restock_fee,
          MAX(wfod.vat_rate) vat_rate
     from wf_return_head wfrh,
          wf_return_detail wfrd,
          wf_order_head wfoh,
          wf_order_detail wfod
    where wfrh.rma_no       = I_rma_no
      and wfrd.rma_no       = wfrh.rma_no
      and wfrd.item         = I_item_rec.item
      and wfoh.wf_order_no  = wfrd.wf_order_no
      and wfod.wf_order_no  = wfoh.wf_order_no
      and wfod.item         = wfrd.item
      and wfod.customer_loc = wfrh.customer_loc
    group by wfrh.customer_loc,
             wfoh.cust_ord_ref_no,
             wfrd.wf_order_no,
             wfrh.rma_no,
             wfrd.returned_qty,
             wfrd.return_unit_cost,
             wfrd.unit_restock_fee;
   cursor C_BTS_GET_RETURN_DET_DISTRO is
      select wfrh.customer_loc,
             wfoh.cust_ord_ref_no,
             wfrd.wf_order_no,
             wfrh.rma_no,
             td.tsf_qty,
             NVL(wfrd.return_unit_cost,0) return_unit_cost,
             id.yield_from_head_item_pct,
             wfrd.unit_restock_fee,
             wfrd.restock_type,
             MAX(wfod.vat_rate) vat_rate
        from item_xform_head ih,
             item_xform_detail id,
             tsfhead th,
             tsfdetail td,
             wf_return_head wfrh,
             wf_return_detail wfrd,
             wf_order_head wfoh,
             wf_order_detail wfod
       where th.tsf_no             = td.tsf_no
         and th.tsf_no             = I_distro_no
         and TO_CHAR(wfrh.rma_no)           = th.ext_ref_no
         and wfrd.rma_no           = wfrh.rma_no
         and wfrd.item             = id.detail_item
         and wfoh.wf_order_no      = wfrd.wf_order_no
         and wfod.wf_order_no      = wfoh.wf_order_no
         and wfod.item             = wfrd.item
         and id.detail_item        = wfod.item
         and ih.head_item          = I_item_rec.item
         and ih.item_xform_head_id = id.item_xform_head_id
         and td.item               = ih.head_item
         and wfod.customer_loc     = wfrh.customer_loc
       group by wfrh.customer_loc,
                wfoh.cust_ord_ref_no,
                wfrd.wf_order_no,
                wfrh.rma_no,
                td.tsf_qty,
                wfrd.return_unit_cost,
                id.yield_from_head_item_pct,
                wfrd.unit_restock_fee,
                wfrd.restock_type;
   cursor C_BTS_GET_RETURN_DETAILS_RMA is
      select wfrh.customer_loc,
             wfoh.cust_ord_ref_no,
             wfrd.wf_order_no,
             wfrh.rma_no,
             I_orderable_qty,
             NVL(wfrd.return_unit_cost,0) return_unit_cost,
             id.yield_from_head_item_pct,
             wfrd.unit_restock_fee,
             wfrd.restock_type,
             MAX(wfod.vat_rate) vat_rate
        from item_xform_head ih,
             item_xform_detail id,
             wf_return_head wfrh,
             wf_return_detail wfrd,
             wf_order_head wfoh,
             wf_order_detail wfod
       where wfrh.rma_no           = I_rma_no
         and wfrd.rma_no           = wfrh.rma_no
         and wfrd.item             = id.detail_item
         and wfoh.wf_order_no      = wfrd.wf_order_no
         and wfod.wf_order_no      = wfoh.wf_order_no
         and wfod.item             = wfrd.item
         and id.detail_item        = wfod.item
         and ih.item_xform_head_id = id.item_xform_head_id
         and ih.head_item          = I_item_rec.item
         and wfod.customer_loc     = wfrh.customer_loc
       group by wfrh.customer_loc,
                wfoh.cust_ord_ref_no,
                wfrd.wf_order_no,
                wfrh.rma_no,
                I_orderable_qty,
                wfrd.return_unit_cost,
                id.yield_from_head_item_pct,
                wfrd.unit_restock_fee,
                wfrd.restock_type;
   TYPE wf_ret_det_TBL IS TABLE OF C_GET_RETURN_DETAILS_DISTRO%ROWTYPE INDEX BY BINARY_INTEGER;
   L_wf_ret_det_tbl       WF_RET_DET_TBL;
   TYPE BTS_WF_RET_DET_TBL is TABLE OF C_BTS_GET_RETURN_DET_DISTRO%ROWTYPE INDEX BY BINARY_INTEGER;
   L_bts_wf_ret_det_tbl   BTS_WF_RET_DET_TBL;
BEGIN
   if I_distro_no is NULL AND I_rma_no is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('REQ_FIELDS_NULL',
                                            'I_distro_no',
                                            'I_rma_no');
      return FALSE;
   end if;
   if I_distro_no is NOT NULL then
      if I_item_rec.item_xform_ind = 'Y' and
         I_item_rec.orderable_ind = 'Y' then
         SQL_LIB.SET_MARK('OPEN',
                          'C_BTS_GET_RETURN_DET_DISTRO',
                          'ITEM_XFORM_HEAD ITEM_XFORM_DETAIL',
                          NULL);
         open C_BTS_GET_RETURN_DET_DISTRO;
         SQL_LIB.SET_MARK('FETCH',
                          'C_BTS_GET_RETURN_DET_DISTRO',
                          'ITEM_XFORM_HEAD ITEM_XFORM_DETAIL',
                          NULL);
         fetch C_BTS_GET_RETURN_DET_DISTRO BULK COLLECT into L_bts_wf_ret_det_tbl;
         SQL_LIB.SET_MARK('CLOSE',
                          'C_BTS_GET_RETURN_DET_DISTRO',
                          'ITEM_XFORM_HEAD ITEM_XFORM_DETAIL',
                          NULL);
         close C_BTS_GET_RETURN_DET_DISTRO;
      else
         open C_GET_RETURN_DETAILS_DISTRO;
         fetch C_GET_RETURN_DETAILS_DISTRO BULK COLLECT INTO L_wf_ret_det_tbl;
         close C_GET_RETURN_DETAILS_DISTRO;
      end if;
   elsif I_rma_no is NOT NULL then
      if I_item_rec.item_xform_ind = 'Y' and
         I_item_rec.orderable_ind = 'Y' then
         SQL_LIB.SET_MARK('OPEN',
                          'C_BTS_GET_RETURN_DETAILS_RMA',
                          'ITEM_XFORM_HEAD ITEM_XFORM_DETAIL',
                          NULL);
         open C_BTS_GET_RETURN_DETAILS_RMA;
         SQL_LIB.SET_MARK('FETCH',
                          'C_BTS_GET_RETURN_DETAILS_RMA',
                          'ITEM_XFORM_HEAD ITEM_XFORM_DETAIL',
                          NULL);
         fetch C_BTS_GET_RETURN_DETAILS_RMA BULK COLLECT into L_bts_wf_ret_det_tbl;
         SQL_LIB.SET_MARK('CLOSE',
                          'C_BTS_GET_RETURN_DETAILS_RMA',
                          'ITEM_XFORM_HEAD ITEM_XFORM_DETAIL',
                          NULL);
         close C_BTS_GET_RETURN_DETAILS_RMA;
      else
         open C_GET_RETURN_DETAILS_RMA;
         fetch C_GET_RETURN_DETAILS_RMA BULK COLLECT INTO L_wf_ret_det_tbl;
         close C_GET_RETURN_DETAILS_RMA;
      end if;
   end if;
   if I_item_rec.item_xform_ind = 'Y' and
      I_item_rec.orderable_ind = 'Y' then
      if L_bts_wf_ret_det_TBL.first is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                               NULL,
                                               L_function,
                                               NULL);
         return FALSE;
      end if;
      L_tax_info_tbl.EXTEND();
      L_tax_info_rec.item             := I_item_rec.item;
      L_tax_info_rec.from_entity_type := 'ST';
      L_tax_info_rec.cost_retail_ind  := 'R';
      FOR i IN L_bts_wf_ret_det_tbl.first..L_bts_wf_ret_det_tbl.last LOOP
         L_customer_loc := L_bts_wf_ret_det_tbl(i).customer_loc;
         L_tax_info_rec.from_entity := L_customer_loc;
         L_tax_info_tbl(L_tax_info_tbl.COUNT) := L_tax_info_rec;
         if TAX_SQL.GET_TAX_RATE(O_error_message,
                                 L_tax_info_tbl) = FALSE then
            return FALSE;
         end if;
         L_vat_code       := L_tax_info_tbl(L_tax_info_tbl.COUNT).tax_code;
         L_orderable_cost := L_bts_wf_ret_det_tbl(i).return_unit_cost * NVL(L_bts_wf_ret_det_tbl(i).yield_from_head_item_pct/100,1);
         if L_bts_wf_ret_det_tbl(i).yield_from_head_item_pct is NULL then
            L_unit_restock_fee := L_bts_wf_ret_det_tbl(i).unit_restock_fee;
         else
            if L_bts_wf_ret_det_tbl(i).restock_type = 'V' then
               L_unit_restock_fee := (L_bts_wf_ret_det_tbl(i).unit_restock_fee * (L_bts_wf_ret_det_tbl(i).yield_from_head_item_pct/100));
            elsif L_bts_wf_ret_det_tbl(i).restock_type = 'S' then
               L_unit_restock_fee := ((L_bts_wf_ret_det_tbl(i).unit_restock_fee * L_bts_wf_ret_det_tbl(i).tsf_qty) * (L_bts_wf_ret_det_tbl(i).yield_from_head_item_pct/100));
            end if;
         end if;
         insert into wf_billing_returns (customer_loc,
                                         cust_ord_ref_no,
                                         wf_order_no,
                                         rma_no,
                                         return_date,
                                         item,
                                         dept,
                                         class,
                                         subclass,
                                         returned_qty,
                                         return_unit_cost,
                                         restocking_fee,
                                         vat_code,
                                         vat_rate,
                                         extracted_ind,
                                         extracted_date)
                                 values (L_bts_wf_ret_det_tbl(i).customer_loc,
                                         L_bts_wf_ret_det_tbl(i).cust_ord_ref_no,
                                         L_bts_wf_ret_det_tbl(i).wf_order_no,
                                         L_bts_wf_ret_det_tbl(i).rma_no,
                                         GET_VDATE(),
                                         I_item_rec.item,
                                         I_item_rec.dept,
                                         I_item_rec.class,
                                         I_item_rec.subclass,
                                         L_bts_wf_ret_det_tbl(i).tsf_qty,
                                         L_orderable_cost,
                                         L_unit_restock_fee,
                                         L_vat_code,
                                         L_bts_wf_ret_det_tbl(i).vat_rate,
                                         'N',
                                         NULL);
      END LOOP;
   else
      if L_wf_ret_det_tbl.first is NULL then
         O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                               NULL,
                                               L_function,
                                               NULL);
         return FALSE;
      end if;
      L_tax_info_tbl.EXTEND();
      L_tax_info_rec.item             := I_item_rec.item;
      L_tax_info_rec.from_entity_type := 'ST';
      L_tax_info_rec.cost_retail_ind  := 'R';
      FOR i IN L_wf_ret_det_tbl.first..L_wf_ret_det_tbl.last LOOP
         L_customer_loc := L_wf_ret_det_tbl(i).customer_loc;
         L_tax_info_rec.from_entity := L_customer_loc;
         L_tax_info_tbl(L_tax_info_tbl.COUNT) := L_tax_info_rec;
         if TAX_SQL.GET_TAX_RATE(O_error_message,
                                 L_tax_info_tbl) = FALSE then
            return FALSE;
         end if;
         L_vat_code := L_tax_info_tbl(L_tax_info_tbl.COUNT).tax_code;
         if SQL%NOTFOUND then
            O_error_message := SQL_LIB.CREATE_MSG('NO_REC',
                                                  'C_GET_VAT_CODE');
            return FALSE;
         end if;
         insert into wf_billing_returns (customer_loc,
                                         cust_ord_ref_no,
                                         wf_order_no,
                                         rma_no,
                                         return_date,
                                         item,
                                         dept,
                                         class,
                                         subclass,
                                         returned_qty,
                                         return_unit_cost,
                                         restocking_fee,
                                         vat_code,
                                         vat_rate,
                                         extracted_ind,
                                         extracted_date)
                                 values (L_wf_ret_det_tbl(i).customer_loc,
                                         L_wf_ret_det_tbl(i).cust_ord_ref_no,
                                         L_wf_ret_det_tbl(i).wf_order_no,
                                         L_wf_ret_det_tbl(i).rma_no,
                                         GET_VDATE(),
                                         I_item_rec.item,
                                         I_item_rec.dept,
                                         I_item_rec.class,
                                         I_item_rec.subclass,
                                         L_wf_ret_det_tbl(i).returned_qty,
                                         L_wf_ret_det_tbl(i).return_unit_cost,
                                         L_wf_ret_det_tbl(i).unit_restock_fee,
                                         L_vat_code,
                                         L_wf_ret_det_tbl(i).vat_rate,
                                         'N',
                                         NULL);
         if SQL%NOTFOUND then
            O_error_message := SQL_LIB.CREATE_MSG('COULD_NOT_INSERT_REC',
                                                  NULL,
                                                  'WF_BILLING_RETURNS');
            return FALSE;
         end if;
      END LOOP;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_function,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPDATE_WF_BILLING;
--------------------------------------------------------------------------------
FUNCTION UPDATE_WF_RETURN(O_error_message IN OUT RTK_ERRORS.RTK_TEXT%TYPE,
                          I_item_rec      IN     ITEM_MASTER%ROWTYPE,
                          I_distro_no     IN     SHIPSKU.DISTRO_NO%TYPE,
                          I_distro_type   IN     SHIPSKU.DISTRO_TYPE%TYPE,
                          I_qty           IN     ITEM_LOC_SOH.STOCK_ON_HAND%TYPE)
RETURN BOOLEAN IS
   L_function        VARCHAR2(60) := 'STOCK_ORDER_RCV_SQL.UPDATE_WF_RETURN';
   L_rma_no          WF_RETURN_HEAD.RMA_NO%TYPE;
   L_detail_item     ITEM_XFORM_DETAIL.DETAIL_ITEM%TYPE;
   L_yld_frm_itm     ITEM_XFORM_DETAIL.YIELD_FROM_HEAD_ITEM_PCT%TYPE;
   L_prod_loss_pct   ITEM_XFORM_HEAD.PRODUCTION_LOSS_PCT%TYPE;
   ---
   cursor C_RMA_NO is
   select ext_ref_no
     from tsfhead
    where tsf_no = I_distro_no;
   ---
   cursor C_GET_SELL_ITEM is
      select distinct wrd.item,
             ixd.yield_from_head_item_pct,
             ixh.production_loss_pct
        from item_xform_detail ixd,
             item_xform_head ixh,
             tsfhead tsh,
             tsfdetail tsd,
             wf_return_detail wrd,
             wf_return_head wrh
       where tsh.tsf_no = tsd.tsf_no
         and TO_CHAR(wrh.rma_no) = tsh.ext_ref_no
         and ixh.head_item = I_item_rec.item
         and ixd.item_xform_head_id = ixh.item_xform_head_id
         and wrd.item = ixd.detail_item;
BEGIN
   if I_distro_no is NULL OR I_distro_type is NULL then
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_DISTRO',
                                            I_distro_no);
      return FALSE;
   end if;
   if I_qty is NULL OR I_qty = 0 then
      O_error_message := SQL_LIB.CREATE_MSG('INV_QTY');
      return FALSE;
   end if;
   open C_RMA_NO;
   fetch C_RMA_NO INTO L_rma_no;
   close C_RMA_NO;
   if SQL%NOTFOUND then
      O_error_message := SQL_LIB.CREATE_MSG('INVALID_DISTRO',
                                            I_distro_no);
      return FALSE;
   end if;
   update tsfhead
      set status = 'C'
    where tsf_no = I_distro_no;
   if SQL%NOTFOUND then
      O_error_message := SQL_LIB.CREATE_MSG('COULD_NOT_UPDATE_REC',
                                             NULL,
                                            'TSFHEAD');
      return FALSE;
   end if;
   update wf_return_head
      set status = 'C'
    where rma_no = L_rma_no;
   if SQL%NOTFOUND then
      O_error_message := SQL_LIB.CREATE_MSG('COULD_NOT_UPDATE_REC',
                                             NULL,
                                            'WF_RETURN_HEAD');
      return FALSE;
   end if;
   if I_item_rec.item_xform_ind = 'Y' and I_item_rec.orderable_ind = 'Y' then
      SQL_LIB.SET_MARK('OPEN',
                       'C_GET_SELL_ITEM',
                       'ITEM_XFORM_DETAIL ITEM_XFORM_HEAD',
                       NULL);
      open C_GET_SELL_ITEM;
      SQL_LIB.SET_MARK('FETCH',
                       'C_GET_SELL_ITEM',
                       'ITEM_XFORM_DETAIL ITEM_XFORM_HEAD',
                       NULL);
      fetch C_GET_SELL_ITEM into L_detail_item,
                                 L_yld_frm_itm,
                                 L_prod_loss_pct;
      SQL_LIB.SET_MARK('CLOSE',
                       'C_GET_SELL_ITEM',
                       'ITEM_XFORM_DETAIL ITEM_XFORM_HEAD',
                       NULL);
      close C_GET_SELL_ITEM;
      if L_yld_frm_itm is NULL then --Single Orderable Item
         update wf_return_detail
            set received_qty = I_qty * (1 - (L_prod_loss_pct/100))
          where rma_no = L_rma_no
            and item = L_detail_item;
      else --Multiple Orderable Item
         update wf_return_detail
            set received_qty = I_qty * ((1 - (L_prod_loss_pct/100))/(L_yld_frm_itm/100))
          where rma_no = L_rma_no
            and item = L_detail_item;
      end if;
   else
      update wf_return_detail
         set received_qty = nvl(received_qty, 0) + I_qty
       where rma_no = L_rma_no
         and item = I_item_rec.item;
   end if;
   if SQL%NOTFOUND then
      O_error_message := SQL_LIB.CREATE_MSG('COULD_NOT_UPDATE_REC',
                                             NULL,
                                            'WF_RETURN_DETAIL');
      return FALSE;
   end if;
   return TRUE;
EXCEPTION
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                             SQLERRM,
                                             L_function,
                                             TO_CHAR(SQLCODE));
      return FALSE;
END UPDATE_WF_RETURN;
--------------------------------------------------------------------------------------------------------------
FUNCTION GET_INVENTORY_TREATMENT(O_error_message             IN OUT   RTK_ERRORS.RTK_TEXT%TYPE,
                                 O_inventory_treatment_ind   IN OUT   SYSTEM_OPTIONS.TSF_FORCE_CLOSE_IND%TYPE,
                                 I_from_loc_type             IN       ITEM_LOC.LOC_TYPE%TYPE,
                                 I_to_loc_type               IN       ITEM_LOC.LOC_TYPE%TYPE,
                                 I_distro_no                 IN       SHIPSKU.DISTRO_NO%TYPE,
                                 I_distro_type               IN       SHIPSKU.DISTRO_TYPE%TYPE,
                                 I_shipment                  IN       SHIPSKU.SHIPMENT%TYPE,
                                 I_ship_seq_no               IN       SHIPSKU.SEQ_NO%TYPE,
                                 I_so_reconcile_ind          IN       BOOLEAN,
                                 I_overage_ind               IN       BOOLEAN)
   RETURN BOOLEAN IS
   L_function      VARCHAR2(60)             := 'STOCK_ORDER_RCV_SQL.GET_INVENTORY_TREATMENT';
   --
   L_adjust_type   SHIPSKU.ADJUST_TYPE%TYPE := NULL;
   L_status        TSFHEAD.STATUS%TYPE      := NULL;
   --
   L_table         VARCHAR2(30);
   L_key1          VARCHAR2(100);
   L_key2          VARCHAR2(100);
   RECORD_LOCKED   EXCEPTION;
   PRAGMA          EXCEPTION_INIT(RECORD_LOCKED, -54);
   --
   cursor C_SHIPSKU_CLOSED is
      select adjust_type
        from shipsku
       where shipment = I_shipment
         and seq_no   = I_ship_seq_no;
   --
   cursor C_DISTRO_CLOSED is
      select status
        from tsfhead
       where tsf_no        = I_distro_no
         and I_distro_type = 'T'
       union all
      select status
        from alloc_header
       where alloc_no      = I_distro_no
         and I_distro_type = 'A';
BEGIN
   L_table := 'shipsku, tsfhead, alloc_header';
   L_key1  := to_char(I_shipment);
   L_key2  := to_char(I_distro_no) || '-' || to_char(I_distro_type);
   --
   if I_overage_ind then -- For Overage
      if I_so_reconcile_ind = FALSE then
         open C_SHIPSKU_CLOSED;
         fetch C_SHIPSKU_CLOSED into L_adjust_type;
         close C_SHIPSKU_CLOSED;
         --
         if L_adjust_type in ('NL','RL','SL','BL') then
               O_inventory_treatment_ind := L_adjust_type;
               return TRUE;
         end if;
      end if;   --End of Shipment closed
      --
      if (I_from_loc_type ='S' and  I_to_loc_type ='S' and LP_system_options_row.sim_force_close_ind is not null) then  -- For Store-Store Transfers
          O_inventory_treatment_ind := 'BL';
      else -- For WH-WH,WH-Store and Store-WH transfers
            O_inventory_treatment_ind := LP_system_options_row.tsf_over_receipt_ind;
      end if;
   else -- Shortage
      if I_so_reconcile_ind = FALSE then
         open C_SHIPSKU_CLOSED;
         fetch C_SHIPSKU_CLOSED into L_adjust_type;
         close C_SHIPSKU_CLOSED;
         --
         if L_adjust_type is NULL then
            open C_DISTRO_CLOSED;
            fetch C_DISTRO_CLOSED into L_status;
            close C_DISTRO_CLOSED;
            if L_status <> 'C' then
               O_inventory_treatment_ind := NULL;
               return TRUE;
            end if;
         else
            if L_adjust_type in ('NL','RL','SL','BL') then
               O_inventory_treatment_ind := L_adjust_type;
               return TRUE;
            end if;
         end if;
      end if;   --End of Shipment closed
      --
      if (I_from_loc_type ='S' and  I_to_loc_type ='S' and LP_system_options_row.sim_force_close_ind is not null) then  -- For Store-Store Transfers
         O_inventory_treatment_ind := LP_system_options_row.sim_force_close_ind;
      else -- For WH-WH,WH-Store and Store-WH transfers
            O_inventory_treatment_ind := LP_system_options_row.tsf_force_close_ind;
      end if;
   end if; -- End of Shortage Logic
   return TRUE;
EXCEPTION
   when RECORD_LOCKED then
      O_error_message := SQL_LIB.CREATE_MSG('TABLE_LOCKED',
                                            L_table,
                                            L_key1,
                                            L_key2);
      return FALSE;
   when OTHERS then
      O_error_message := SQL_LIB.CREATE_MSG('PACKAGE_ERROR',
                                            SQLERRM,
                                            L_function,
                                            TO_CHAR(SQLCODE));
      return FALSE;
END GET_INVENTORY_TREATMENT;
--------------------------------------------------------------------------------
END STOCK_ORDER_RCV_SQL;
/