-------------------------------------------------------
-- Modification History
-- Version Date      Developer   Issue/CR      Description
-- ======= ========= =========== ========   =========================================
-- 1.0    10-May-15  Murali        LEAP2        Creation of Interface Table to support SDQ.            
--------------------------------------------------------

Prompt Drop table SMR_RMS_INT_TYPE
DROP TABLE RMS13.SMR_RMS_INT_TYPE;

Prompt create table SMR_RMS_INT_TYPE
create table RMS13.SMR_RMS_INT_TYPE 
			(INTERFACE_ID   NUMBER(10),
			INTERFACE_NAME  VARCHAR2(50),
			DESCRIPTION	    VARCHAR2(100),
			INTERFACE_TYPE	VARCHAR2(8),
			CONSTRAINT "PK_SMR_RMS_INT_TYPE" PRIMARY KEY (INTERFACE_ID));

Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_TYPE
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_TYPE FOR RMS13.SMR_RMS_INT_TYPE;

Prompt Select Privs on TABLE SMR_RMS_INT_TYPE TO ROLES
GRANT SELECT ON SMR_RMS_INT_TYPE TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_TYPE TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_TYPE TO RMS13_UPDATE;
------------------------------------------------------------------------------------------------

Prompt create table SMR_RMS_INT_QUEUE
DROP TABLE RMS13.SMR_RMS_INT_QUEUE;

Prompt Drop table SMR_RMS_INT_QUEUE
create table RMS13.SMR_RMS_INT_QUEUE
		(INTERFACE_QUEUE_ID	NUMBER(10),
		INTERFACE_ID	NUMBER(10),
		GROUP_ID	VARCHAR2(50),
		CREATE_DATETIME	DATE,
		PROCESSED_DATETIME	DATE,
		STATUS	VARCHAR2(2),
		CONSTRAINT "PK_SMR_RMS_INT_QUEUE" PRIMARY KEY (INTERFACE_QUEUE_ID),
		CONSTRAINT "INTERFACE_ID_FK" FOREIGN KEY ("INTERFACE_ID")
				  REFERENCES "RMS13"."SMR_RMS_INT_TYPE" ("INTERFACE_ID") ENABLE);
			  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_QUEUE
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_QUEUE FOR RMS13.SMR_RMS_INT_QUEUE;

Prompt Select Privs on TABLE SMR_RMS_INT_QUEUE TO ROLES
GRANT SELECT ON SMR_RMS_INT_QUEUE TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_QUEUE TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_QUEUE TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_QUEUE TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_QUEUE TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_ERROR
DROP TABLE RMS13.SMR_RMS_INT_ERROR;

Prompt create table SMR_RMS_INT_ERROR
create table RMS13.SMR_RMS_INT_ERROR
		(INTERFACE_ERROR_ID	VARCHAR2(50),
		GROUP_ID	VARCHAR2(50),
		RECORD_ID	NUMBER(10),
		ERROR_MSG VARCHAR2(100),
		CREATE_DATETIME	DATE,
		CONSTRAINT "PK_SMR_RMS_INT_ERROR" PRIMARY KEY (INTERFACE_ERROR_ID));
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_ERROR
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_ERROR FOR RMS13.SMR_RMS_INT_ERROR;

Prompt Select Privs on TABLE SMR_RMS_INT_ERROR TO ROLES
GRANT SELECT ON SMR_RMS_INT_ERROR TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_ERROR TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_ERROR TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_ERROR TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_ERROR TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_SHIPPING_IMP
DROP TABLE RMS13.SMR_RMS_INT_SHIPPING_IMP;

Prompt create table SMR_RMS_INT_SHIPPING_IMP
create table RMS13.SMR_RMS_INT_SHIPPING_IMP
		(GROUP_ID	VARCHAR2(50),
		  RECORD_ID	NUMBER(10),     
		  ship_date     DATE,
		  from_loc      NUMBER(10),
		  from_loc_type VARCHAR2(1),
		  to_loc        NUMBER(10),
		  to_loc_type   VARCHAR2(1),
		  order_no      NUMBER(10),
		  ship_type     VARCHAR2(2),
		  tsf_no        NUMBER(10),
		  alloc_no      NUMBER(10),
		  bol_no        VARCHAR2(17),
		  carton        VARCHAR2(30),
		  item          VARCHAR2(25),
		  upc           VARCHAR2(25),
		  qty_shipped   NUMBER(12,4),
		  shipment      NUMBER(10),
		  carrier_code  VARCHAR2(30),
		  CREATE_DATETIME	DATE,
		  PROCESSED_IND	VARCHAR2(1),
		  PROCESSED_DATETIME	DATE,
		  ERROR_IND	VARCHAR2(1));
		  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_SHIPPING_IMP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_SHIPPING_IMP FOR RMS13.SMR_RMS_INT_SHIPPING_IMP;

Prompt Select Privs on TABLE SMR_RMS_INT_SHIPPING_IMP TO ROLES
GRANT SELECT ON SMR_RMS_INT_SHIPPING_IMP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_SHIPPING_IMP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_SHIPPING_IMP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_SHIPPING_IMP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_SHIPPING_IMP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_RECEIVING_IMP
DROP TABLE RMS13.SMR_RMS_INT_RECEIVING_IMP;

Prompt create table SMR_RMS_INT_RECEIVING_IMP
create table RMS13.SMR_RMS_INT_RECEIVING_IMP
		( GROUP_ID	VARCHAR2(50),
		  RECORD_ID	NUMBER(10),     
		  whse_receiver      VARCHAR2(15),
		  WH                 NUMBER(5),
		  shipment_type      VARCHAR2(1),
		  asn_no             VARCHAR2(30),
		  bol_no             VARCHAR2(30),
		  order_no           NUMBER(9),
		  alloc_no           NUMBER(10),
		  transfer_no        NUMBER(10),
		  store              NUMBER(5),
		  file_date          DATE,
		  vendor             NUMBER(9),
		  item                NUMBER(11),
		  qty_to_be_received NUMBER(12,4),
		  rcv_date           DATE,
		  carton          VARCHAR2(30),
		  CREATE_DATETIME	DATE,
		  PROCESSED_IND	VARCHAR2(1),
		  PROCESSED_DATETIME	DATE,
		  ERROR_IND	VARCHAR2(1));
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_RECEIVING_IMP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_RECEIVING_IMP FOR RMS13.SMR_RMS_INT_RECEIVING_IMP;

Prompt Select Privs on TABLE SMR_RMS_INT_RECEIVING_IMP TO ROLES
GRANT SELECT ON SMR_RMS_INT_RECEIVING_IMP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_RECEIVING_IMP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_RECEIVING_IMP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_RECEIVING_IMP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_RECEIVING_IMP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt create table SMR_RMS_INT_ASN_VENDOR_IMP
DROP TABLE RMS13.SMR_RMS_INT_ASN_VENDOR_IMP;

Prompt Drop table SMR_RMS_INT_ASN_VENDOR_IMP
create table RMS13.SMR_RMS_INT_ASN_VENDOR_IMP
		(GROUP_ID  VARCHAR2(50),
		  RECORD_ID  NUMBER(10),     
		  ASN_NO     varchar2(30),
		  bol_no     varchar2(30),
		  ship_date  date,
		  EST_ARR_DATE date,
		  SHIP_TO       number(10),
		  COURIER       varchar2(30),
		  vendor     number(10),
		  CREATE_DATETIME	DATE,
		  PROCESSED_IND	VARCHAR2(1),
		  PROCESSED_DATETIME	DATE,
		  ERROR_IND	VARCHAR2(1));
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_ASN_VENDOR_IMP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_ASN_VENDOR_IMP FOR RMS13.SMR_RMS_INT_ASN_VENDOR_IMP;

Prompt Select Privs on TABLE SMR_RMS_INT_ASN_VENDOR_IMP TO ROLES
GRANT SELECT ON SMR_RMS_INT_ASN_VENDOR_IMP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_ASN_VENDOR_IMP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_ASN_VENDOR_IMP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_ASN_VENDOR_IMP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_ASN_VENDOR_IMP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_ASN_ITEM_IMP
DROP TABLE RMS13.SMR_RMS_INT_ASN_ITEM_IMP;

Prompt create table SMR_RMS_INT_ASN_ITEM_IMP
create table RMS13.SMR_RMS_INT_ASN_ITEM_IMP
		( GROUP_ID  VARCHAR2(50),
		  RECORD_ID  NUMBER(10),  
		  ASN_NO     varchar2(30),
		  order_no     number(10),
		  order_loc  number(10),
		  mark_for    number(10),
		  carton       varchar2(20),
		  UPC       varchar2(25),
		  ITEM     varchar2(25),
		  units_shipped number(20,4),
		  vendor   number(10),
		  ERROR_MSG varchar2(100),
		  ERROR_IND	VARCHAR2(1));
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_ASN_ITEM_IMP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_ASN_ITEM_IMP FOR RMS13.SMR_RMS_INT_ASN_ITEM_IMP;

Prompt Select Privs on TABLE SMR_RMS_INT_ASN_ITEM_IMP TO ROLES
GRANT SELECT ON SMR_RMS_INT_ASN_ITEM_IMP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_ASN_ITEM_IMP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_ASN_ITEM_IMP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_ASN_ITEM_IMP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_ASN_ITEM_IMP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_ADJUSTMENTS_IMP
DROP TABLE RMS13.SMR_RMS_INT_ADJUSTMENTS_IMP;

Prompt create table SMR_RMS_INT_ADJUSTMENTS_IMP
create table RMS13.SMR_RMS_INT_ADJUSTMENTS_IMP
		(GROUP_ID  VARCHAR2(50),
		  RECORD_ID  NUMBER(10),     
		  ADJ_ID    Number(10),
		  WA_TRAN_CODE varchar2(10),
		  WH     number(10),
		  item     varchar2(25),
		  QTY_ADJUSTED  number(20,4),
		  UOM           Varchar2(3),
		  carton       varchar2(20),
		  REASON_CODE       number(4),
		  TRAN_DATE     date,
		  ORDER_NO      number(10),
		  USER_ID     varchar2(10),
		  SMRT_MARK_FOR  NUMBER(10),
		  REASON_DESC    VARCHAR2(30),
		  CREATE_DATETIME	DATE,
		  PROCESSED_IND	VARCHAR2(1),
		  PROCESSED_DATETIME	DATE,
		  ERROR_IND	VARCHAR2(1));
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_ADJUSTMENTS_IMP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_ADJUSTMENTS_IMP FOR RMS13.SMR_RMS_INT_ADJUSTMENTS_IMP;

Prompt Select Privs on TABLE SMR_RMS_INT_ADJUSTMENTS_IMP TO ROLES
GRANT SELECT ON SMR_RMS_INT_ADJUSTMENTS_IMP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_ADJUSTMENTS_IMP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_ADJUSTMENTS_IMP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_ADJUSTMENTS_IMP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_ADJUSTMENTS_IMP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_RTW_EXP
DROP TABLE RMS13.SMR_RMS_INT_RTW_EXP;

Prompt create table SMR_RMS_INT_RTW_EXP
 create table RMS13.SMR_RMS_INT_RTW_EXP
		(GROUP_ID	VARCHAR2(50),
		  RECORD_ID	NUMBER(10),     
		  ship_date     DATE,
		  from_loc      NUMBER(10),
		  from_loc_type VARCHAR2(1),
		  to_loc        NUMBER(10),
		  to_loc_type   VARCHAR2(1),
		  tsf_no        NUMBER(10),
		  bol_no        VARCHAR2(17),
		  carton        VARCHAR2(30),
		  Item           VARCHAR2(25),
		  qty_shipped   NUMBER(12,4),
		  shipment      NUMBER(10),
		  status        varchar2(1),
		  CREATE_DATETIME	DATE);
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_RTW_EXP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_RTW_EXP FOR RMS13.SMR_RMS_INT_RTW_EXP;

Prompt Select Privs on TABLE SMR_RMS_INT_RTW_EXP TO ROLES
GRANT SELECT ON SMR_RMS_INT_RTW_EXP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_RTW_EXP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_RTW_EXP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_RTW_EXP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_RTW_EXP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_RTV_EXP
DROP TABLE RMS13.SMR_RMS_INT_RTV_EXP;

Prompt create table SMR_RMS_INT_RTV_EXP
create table RMS13.SMR_RMS_INT_RTV_EXP
		(GROUP_ID  VARCHAR2(50),
		  RECORD_ID  NUMBER(10),     
		  rtv_order_no       NUMBER(10),
		  supplier           NUMBER(10),
		  wh                 NUMBER(10),
		  ship_to_add_1      VARCHAR2(240),
		  ship_to_add_2      VARCHAR2(240),
		  ship_to_add_3      VARCHAR2(240),
		  ship_to_city       VARCHAR2(120) ,
		  state              VARCHAR2(3),
		  ship_to_country_id VARCHAR2(3) ,
		  ship_to_pcode      VARCHAR2(30),
		  ret_auth_num       VARCHAR2(12),
		  courier            VARCHAR2(250),
		  created_date       DATE ,
		  not_after_date     DATE,
		  item               VARCHAR2(25),
		  qty_returned       NUMBER(12,4),
		  reason             VARCHAR2(6),
		  comment_desc       VARCHAR2(2000),
		  status             VARCHAR2(1),
		  CREATE_DATETIME  DATE);
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_RTV_EXP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_RTV_EXP FOR RMS13.SMR_RMS_INT_RTV_EXP;

Prompt Select Privs on TABLE SMR_RMS_INT_RTV_EXP TO ROLES
GRANT SELECT ON SMR_RMS_INT_RTV_EXP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_RTV_EXP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_RTV_EXP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_RTV_EXP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_RTV_EXP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_INT_PACK_EXP
DROP TABLE RMS13.SMR_RMS_INT_PACK_EXP;

Prompt create table SMR_RMS_INT_PACK_EXP
create table RMS13.SMR_RMS_INT_PACK_EXP
		(GROUP_ID	VARCHAR2(50),
		  RECORD_ID	NUMBER(10),     
		  pack_no   varchar2(25),
		  PACK_DESC varchar2(100),
		  COMP_ITEM varchar2(25),
		  COMP_QTY  NUMBER(8),
		  STATUS    varchar2(1),
		  CREATE_DATETIME	DATE);
				  
Prompt Creating Public synonymn for RMS13.SMR_RMS_INT_PACK_EXP
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_INT_PACK_EXP FOR RMS13.SMR_RMS_INT_PACK_EXP;

Prompt Select Privs on TABLE SMR_RMS_INT_PACK_EXP TO ROLES
GRANT SELECT ON SMR_RMS_INT_PACK_EXP TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_INT_PACK_EXP TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_INT_PACK_EXP TO RMS13_UPDATE;

Prompt DML Privs on TABLE SMR_RMS_INT_PACK_EXP TO user SVC_INT_RMS
GRANT  INSERT, UPDATE ON SMR_RMS_INT_PACK_EXP TO SVC_INT_RMS;
------------------------------------------------------------------------------------------------
