CREATE OR REPLACE
TYPE         RMS13."RIB_DSDDeals_REC"                                          UNDER RIB_OBJECT (
   --------------------------------------------------------------------------------------------------------------------------------------------
   --
   --  These variables are infrastructure variables which will be used by the RIB internally for constructing the namespace of the payload.
   --
   --------------------------------------------------------------------------------------------------------------------------------------------
  "ns_version_v1" varchar2(1), -- This variable(ns_type_<version no>) is used to identify the version of a retail domain object.
  "ns_name_DSDDealsDesc" varchar2(1), -- This variable(ns_name_<xyz>) is used to identify the current type name or parent type name of a retail domain object.
  "ns_type_bo" varchar2(1), -- This variable(ns_type_<bo or bm>) is used to identify the type or category of a retail domain object.
  "ns_location_base" varchar2(1), -- This variable(ns_location_<custom or base>) is used to identify the location of a retail domain object.
  "ns_level_nontop" varchar2(1), -- This variable(ns_level_<top or nontop>) is used to identify the level of a retail domain object.
   --------------------------------------------------------------------------------------------------------------------------------------------
   --
   --  These variables are the payload variables which are used to construct the payload.
   --
   --------------------------------------------------------------------------------------------------------------------------------------------
  order_no number(10),
  supplier varchar2(10),
  store number(10),
  dept number(4),
  currency_code varchar2(3),
  paid_ind varchar2(1),
  ext_ref_no varchar2(30),
  proof_of_delivery_no varchar2(30),
  payment_ref_no varchar2(16),
  payment_date date,
  deals_ind varchar2(1),
  shipment number(10),
  invc_id number(10),
  invc_ind varchar2(1),
  vdate date,
  qty_sum number(12,4),
  cost_sum number(20,4),
  ext_receipt_no varchar2(17),
  ExtOfDSDDeals_TBL "RIB_ExtOfDSDDeals_TBL",
  OVERRIDING MEMBER PROCEDURE appendNodeValues( i_prefix IN VARCHAR2)
,constructor function "RIB_DSDDeals_REC"
(
  rib_oid number
, order_no number
, supplier varchar2
, store number
, dept number
, currency_code varchar2
, paid_ind varchar2
, ext_ref_no varchar2
, proof_of_delivery_no varchar2
, payment_ref_no varchar2
, payment_date date
, deals_ind varchar2
, shipment number
, invc_id number
, invc_ind varchar2
, vdate date
, qty_sum number
, cost_sum number
, ext_receipt_no varchar2
) return self as result
,constructor function "RIB_DSDDeals_REC"
(
  rib_oid number
, order_no number
, supplier varchar2
, store number
, dept number
, currency_code varchar2
, paid_ind varchar2
, ext_ref_no varchar2
, proof_of_delivery_no varchar2
, payment_ref_no varchar2
, payment_date date
, deals_ind varchar2
, shipment number
, invc_id number
, invc_ind varchar2
, vdate date
, qty_sum number
, cost_sum number
, ext_receipt_no varchar2
, ExtOfDSDDeals_TBL "RIB_ExtOfDSDDeals_TBL"
) return self as result
);
/