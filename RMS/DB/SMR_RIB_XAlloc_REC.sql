CREATE OR REPLACE
TYPE         RMS13."RIB_XAlloc_REC"                                          UNDER RIB_OBJECT (
   --------------------------------------------------------------------------------------------------------------------------------------------
   --
   --  These variables are infrastructure variables which will be used by the RIB internally for constructing the namespace of the payload.
   --
   --------------------------------------------------------------------------------------------------------------------------------------------
  "ns_version_v1" varchar2(1), -- This variable(ns_type_<version no>) is used to identify the version of a retail domain object.
  "ns_name_XAllocDesc" varchar2(1), -- This variable(ns_name_<xyz>) is used to identify the current type name or parent type name of a retail domain object.
  "ns_type_bo" varchar2(1), -- This variable(ns_type_<bo or bm>) is used to identify the type or category of a retail domain object.
  "ns_location_base" varchar2(1), -- This variable(ns_location_<custom or base>) is used to identify the location of a retail domain object.
  "ns_level_nontop" varchar2(1), -- This variable(ns_level_<top or nontop>) is used to identify the level of a retail domain object.
   --------------------------------------------------------------------------------------------------------------------------------------------
   --
   --  These variables are the payload variables which are used to construct the payload.
   --
   --------------------------------------------------------------------------------------------------------------------------------------------
  alloc_no number(10),
  alloc_desc varchar2(300),
  order_no number(10),
  item varchar2(25),
  from_loc number(10),
  release_date date,
  XAllocDtl_TBL "RIB_XAllocDtl_TBL",
  ExtOfXAlloc_TBL "RIB_ExtOfXAlloc_TBL",
  OVERRIDING MEMBER PROCEDURE appendNodeValues( i_prefix IN VARCHAR2)
,constructor function "RIB_XAlloc_REC"
(
  rib_oid number
, alloc_no number
, alloc_desc varchar2
, order_no number
, item varchar2
, from_loc number
) return self as result
,constructor function "RIB_XAlloc_REC"
(
  rib_oid number
, alloc_no number
, alloc_desc varchar2
, order_no number
, item varchar2
, from_loc number
, release_date date
) return self as result
,constructor function "RIB_XAlloc_REC"
(
  rib_oid number
, alloc_no number
, alloc_desc varchar2
, order_no number
, item varchar2
, from_loc number
, release_date date
, XAllocDtl_TBL "RIB_XAllocDtl_TBL"
) return self as result
,constructor function "RIB_XAlloc_REC"
(
  rib_oid number
, alloc_no number
, alloc_desc varchar2
, order_no number
, item varchar2
, from_loc number
, release_date date
, XAllocDtl_TBL "RIB_XAllocDtl_TBL"
, ExtOfXAlloc_TBL "RIB_ExtOfXAlloc_TBL"
) return self as result
);
/