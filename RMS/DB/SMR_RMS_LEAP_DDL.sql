-------------------------------------------------------
-- Modification History
-- Version Date      Developer   Issue/CR      Description
-- ======= ========= =========== ========   ===============================================
-- 1.0    10-May-15  Murali        LEAP2        Creation of Tables.            
-------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_ADJ_STAGE
DROP TABLE RMS13.SMR_RMS_ADJ_STAGE;

Prompt create table SMR_RMS_ADJ_STAGE
create table RMS13.SMR_RMS_ADJ_STAGE
(
  group_id      VARCHAR2(50),
  record_id     NUMBER(10),
  adj_id        NUMBER(10),
  wa_tran_code  VARCHAR2(10),
  wh            NUMBER(10),
  item          VARCHAR2(25),
  qty_adjusted  NUMBER(20,4),
  uom           VARCHAR2(3),
  carton_id     VARCHAR2(20),
  reason_code   NUMBER(4),
  tran_date     DATE,
  order_no      NUMBER(10),
  user_id       VARCHAR2(10),
  smrt_mark_for NUMBER(10),
  reason_desc   VARCHAR2(30),
  location      NUMBER(10));

Prompt Create primary constraints
alter table SMR_RMS_ADJ_STAGE
  add constraint PK_SMR_RMS_ADJ_STAGE primary key (GROUP_ID, RECORD_ID);
  
Prompt Create Indexes   
create index SMR_RMS_ADJ_STAGE_I1 on SMR_RMS_ADJ_STAGE (WA_TRAN_CODE);

create index SMR_RMS_ADJ_STAGE_I2 on SMR_RMS_ADJ_STAGE (WH, ITEM);

Prompt Creating Public synonymn for RMS13.SMR_RMS_ADJ_STAGE
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_ADJ_STAGE FOR RMS13.SMR_RMS_ADJ_STAGE;

Prompt Select Privs on TABLE SMR_RMS_ADJ_STAGE TO ROLES
GRANT SELECT ON SMR_RMS_ADJ_STAGE TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_ADJ_STAGE TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_ADJ_STAGE TO RMS13_UPDATE;
  
-------------------------------------------------------------------------------------------
Prompt Drop table SMR_ADJ_REASON_CODE
DROP TABLE RMS13.SMR_ADJ_REASON_CODE;

Prompt create table SMR_ADJ_REASON_CODE
create table RMS13.SMR_ADJ_REASON_CODE
(
  reason_code     NUMBER(4),
  reason_desc     VARCHAR2(100),
  wms_reason_code NUMBER(4),
  inv_status      NUMBER(2));

Prompt Create primary constraints 
  alter table SMR_ADJ_REASON_CODE
  add constraint PK_SMR_ADJ_REASON_CODE primary key (WMS_REASON_CODE);
 
Prompt Create Indexes 
  create index SMR_ADJ_REASON_CODE_I1 on SMR_ADJ_REASON_CODE (REASON_CODE);
  
Prompt Creating Public synonymn for RMS13.SMR_ADJ_REASON_CODE
CREATE OR REPLACE PUBLIC SYNONYM SMR_ADJ_REASON_CODE FOR RMS13.SMR_ADJ_REASON_CODE;

Prompt Select Privs on TABLE SMR_ADJ_REASON_CODE TO ROLES
GRANT SELECT ON SMR_ADJ_REASON_CODE TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_ADJ_REASON_CODE TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_ADJ_REASON_CODE TO RMS13_UPDATE;  
-------------------------------------------------------------------------------------------
Prompt Drop table SMR_RMS_WH_RUA
DROP TABLE RMS13.SMR_RMS_WH_RUA;

Prompt create table SMR_RMS_WH_RUA
 create table RMS13.SMR_RMS_WH_RUA
(
  adj_id             NUMBER(10),
  wa_tran_code       VARCHAR2(10),
  wh                 NUMBER(10),
  item               VARCHAR2(25),
  qty_adjusted       NUMBER(20,4),
  uom                VARCHAR2(3),
  carton_id          VARCHAR2(20),
  reason_code        NUMBER(4),
  tran_date          DATE,
  order_no           NUMBER(10),
  user_id            VARCHAR2(10),
  smrt_mark_for      NUMBER(10),
  reason_desc        VARCHAR2(30),
  location           NUMBER(10),
  processed_ind      VARCHAR2(2),
  processed_datetime DATE,
  processed_by       VARCHAR2(10));
  
create index SMR_RMS_WH_RUA_I1 on SMR_RMS_WH_RUA (WH);

create index SMR_RMS_WH_RUA_I2 on SMR_RMS_WH_RUA (WH, ITEM);

create index SMR_RMS_WH_RUA_I3 on SMR_RMS_WH_RUA (ORDER_NO);

Prompt Creating Public synonymn for RMS13.SMR_RMS_WH_RUA
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_WH_RUA FOR RMS13.SMR_RMS_WH_RUA;

Prompt Select Privs on TABLE SMR_RMS_WH_RUA TO ROLES
GRANT SELECT ON SMR_RMS_WH_RUA TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_WH_RUA TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_WH_RUA TO RMS13_UPDATE;  
-------------------------------------------------------------------------------------------
Prompt Drop table SMR_WH_RECEIVING_DATA
DROP TABLE RMS13.SMR_WH_RECEIVING_DATA;

Prompt create table SMR_WH_RECEIVING_DATA
create table RMS13.SMR_WH_RECEIVING_DATA
(
  group_id           VARCHAR2(50) not null,
  record_id          NUMBER(10) not null,
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
  item                VARCHAR2(25),
  qty_to_be_received NUMBER(7),
  rcv_date           DATE,
  carton             VARCHAR2(30),
  shipment_id        VARCHAR2(30));

-- Create/Recreate primary, unique and foreign key constraints 
Prompt Create primary constraints 
alter table SMR_WH_RECEIVING_DATA
  add constraint PK_SMR_WH_RECEIVING_DATA primary key (GROUP_ID, RECORD_ID);
  
-- Create/Recreate indexes 
Prompt Create Indexes 
create index SMR_WH_RECEIVING_DATA_I1 on SMR_WH_RECEIVING_DATA (WH);

create index SMR_WH_RECEIVING_DATA_I2 on SMR_WH_RECEIVING_DATA (ORDER_NO, ALLOC_NO, TRANSFER_NO);

create index SMR_WH_RECEIVING_DATA_I3 on SMR_WH_RECEIVING_DATA (item);

create index SMR_WH_RECEIVING_DATA_I4 on SMR_WH_RECEIVING_DATA (CARTON);

Prompt Creating Public synonymn for RMS13.SMR_WH_RECEIVING_DATA
CREATE OR REPLACE PUBLIC SYNONYM SMR_WH_RECEIVING_DATA FOR RMS13.SMR_WH_RECEIVING_DATA;

Prompt Select Privs on TABLE SMR_WH_RECEIVING_DATA TO ROLES
GRANT SELECT ON SMR_WH_RECEIVING_DATA TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_WH_RECEIVING_DATA TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_WH_RECEIVING_DATA TO RMS13_UPDATE;  

-------------------------------------------------------------------------------------------
Prompt Drop table SMR_WH_RECEIVING_ERROR
DROP TABLE RMS13.SMR_WH_RECEIVING_ERROR;

Prompt create table SMR_WH_RECEIVING_ERROR
-- Create table
create table RMS13.SMR_WH_RECEIVING_ERROR
(
  group_id      VARCHAR2(50),
  record_id     NUMBER(10),
  whse_receiver      VARCHAR2(15),
  WH               NUMBER(5),
  shipment_type      VARCHAR2(1),
  asn_no             VARCHAR2(30),
  bol_no             VARCHAR2(30),
  order_no           NUMBER(9),
  alloc_no           NUMBER(10),
  transfer_no        NUMBER(10),
  store              NUMBER(5),
  file_date          DATE,
  vendor             NUMBER(9),
  item                VARCHAR2(25),
  qty_to_be_received NUMBER(7),
  rcv_date           DATE,
  carton          VARCHAR2(30),
  shipment_id        VARCHAR2(30),
  error_msg          VARCHAR2(2000),
  error_date         DATE,
  d_rowid            ROWID);


-- Create/Recreate indexes 
Prompt Create Indexes 
create index SMR_WH_RECEIVING_ERROR_I1 on SMR_WH_RECEIVING_ERROR (CARTON);

create index SMR_WH_RECEIVING_ERROR_I2 on SMR_WH_RECEIVING_ERROR (BOL_NO);

create index SMR_WH_RECEIVING_ERROR_I3 on SMR_WH_RECEIVING_ERROR (WH);

create index SMR_WH_RECEIVING_ERROR_I4 on SMR_WH_RECEIVING_ERROR (ORDER_NO, ALLOC_NO, TRANSFER_NO);

create index SMR_WH_RECEIVING_ERROR_I5 on SMR_WH_RECEIVING_ERROR (Item);

Prompt Creating Public synonymn for RMS13.SMR_WH_RECEIVING_ERROR
CREATE OR REPLACE PUBLIC SYNONYM SMR_WH_RECEIVING_ERROR FOR RMS13.SMR_WH_RECEIVING_ERROR;

Prompt Select Privs on TABLE SMR_WH_RECEIVING_ERROR TO ROLES
GRANT SELECT ON SMR_WH_RECEIVING_ERROR TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_WH_RECEIVING_ERROR TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_WH_RECEIVING_ERROR TO RMS13_UPDATE;  

-------------------------------------------------------------------------------------------
Prompt Drop table SMR_WH_ASN_STAGE
DROP TABLE RMS13.SMR_WH_ASN_STAGE;

Prompt create table SMR_WH_ASN_STAGE  
-- Create table
create table RMS13.SMR_WH_ASN_STAGE
(
  group_id      VARCHAR2(50) not null,
  record_id     NUMBER(10) not null,
  bol_no        VARCHAR2(17),
  ship_date     DATE,
  from_loc      NUMBER(10),
  from_loc_type VARCHAR2(1),
  to_loc        NUMBER(10),
  to_loc_type   VARCHAR2(1),
  shipment      NUMBER(10),
  carrier_code  VARCHAR2(30),
  ship_type     VARCHAR2(2),
  order_no      NUMBER(10),
  alloc_no      NUMBER(10),
  tsf_no        NUMBER(10),
  carton        VARCHAR2(30),
  Item           VARCHAR2(25),
  upc           VARCHAR2(25),
  qty_shipped   NUMBER(12)
);

Prompt Create primary constraints 
-- Create/Recreate primary, unique and foreign key constraints 
alter table SMR_WH_ASN_STAGE
  add constraint PK_SMR_WH_ASN_STAGE primary key (GROUP_ID, RECORD_ID);
  
Prompt Create Indexes   
-- Create/Recreate indexes 
create index SMR_WH_ASN_I1 on SMR_WH_ASN_STAGE (FROM_LOC, TO_LOC);

create index SMR_WH_ASN_I2 on SMR_WH_ASN_STAGE (CARTON);

create index SMR_WH_ASN_I3 on SMR_WH_ASN_STAGE (Item);

create index SMR_WH_ASN_I4 on SMR_WH_ASN_STAGE (ORDER_NO, ALLOC_NO, TSF_NO);

Prompt Creating Public synonymn for RMS13.SMR_WH_ASN_STAGE
CREATE OR REPLACE PUBLIC SYNONYM SMR_WH_ASN_STAGE FOR RMS13.SMR_WH_ASN_STAGE;

Prompt Select Privs on TABLE SMR_WH_ASN_STAGE TO ROLES
GRANT SELECT ON SMR_WH_ASN_STAGE TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_WH_ASN_STAGE TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_WH_ASN_STAGE TO RMS13_UPDATE;    
-------------------------------------------------------------------------------------------
 
Prompt Drop table SMR_WH_ASN_ERRORS
DROP TABLE RMS13.SMR_WH_ASN_ERRORS;

Prompt create table SMR_WH_ASN_ERRORS  
-- Create table
create table RMS13.SMR_WH_ASN_ERRORS
(
  group_id      VARCHAR2(50),
  record_id     NUMBER(10),
  bol_no        VARCHAR2(17),
  ship_date     DATE,
  from_loc      NUMBER(10),
  from_loc_type VARCHAR2(1),
  to_loc        NUMBER(10),
  to_loc_type   VARCHAR2(1),
  shipment      NUMBER(10),
  carrier_code  VARCHAR2(30),
  ship_type     VARCHAR2(2),
  order_no      NUMBER(10),
  alloc_no      NUMBER(10),
  tsf_no        NUMBER(10),
  carton        VARCHAR2(30),
  Item           VARCHAR2(25),
  upc           VARCHAR2(25),
  qty_shipped   NUMBER(12),
  error_msg     VARCHAR2(2000),
  error_date    DATE);
  
-- Create/Recreate indexes 
Prompt Create Indexes 
create index SMR_WH_ASN_ERRORS_I1 on SMR_WH_ASN_ERRORS (GROUP_ID, RECORD_ID);

 Prompt Creating Public synonymn for RMS13.SMR_WH_ASN_ERRORS
CREATE OR REPLACE PUBLIC SYNONYM SMR_WH_ASN_ERRORS FOR RMS13.SMR_WH_ASN_ERRORS;

Prompt Select Privs on TABLE SMR_WH_ASN_ERRORS TO ROLES
GRANT SELECT ON SMR_WH_ASN_ERRORS TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_WH_ASN_ERRORS TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_WH_ASN_ERRORS TO RMS13_UPDATE;  

-------------------------------------------------------------------------------------------
Prompt Alter SMR_SYSTEM_OPTIONS and add ASN_IS_CARTON RUA_WH_AUTO_PROCESS and VND_ASN_SDQ
Alter table RMS13.SMR_SYSTEM_OPTIONS add ASN_IS_CARTON VARCHAR2(1) default 'N' not null;

Alter table RMS13.SMR_SYSTEM_OPTIONS add RUA_WH_AUTO_PROCESS VARCHAR2(1) default 'N' not null;

Alter table RMS13.SMR_SYSTEM_OPTIONS add VND_ASN_SDQ VARCHAR2(1) default 'N' not null;

--------------------------------------------------------------------------------------------
 
Prompt Drop table SMR_RMS_RTV_STG
DROP TABLE RMS13.SMR_RMS_RTV_STG;

Prompt create table SMR_RMS_RTV_STG  
create table RMS13.SMR_RMS_RTV_STG
(
  rtv_order_no  NUMBER(10) not null,
  status        VARCHAR2(1) not null,
  created_date  DATE,
  processed_ind VARCHAR2(1) not null
);

 Prompt Creating Public synonymn for RMS13.SMR_RMS_RTV_STG
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_RTV_STG FOR RMS13.SMR_RMS_RTV_STG;

Prompt Select Privs on TABLE SMR_RMS_RTV_STG TO ROLES
GRANT SELECT ON SMR_RMS_RTV_STG TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_RTV_STG TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_RTV_STG TO RMS13_UPDATE;  

-------------------------------------------------------------------------------------------
 
Prompt Drop table SMR_RMS_RTW_STG
DROP TABLE RMS13.SMR_RMS_RTW_STG;

Prompt create table SMR_RMS_RTW_STG  
create table RMS13.SMR_RMS_RTW_STG
(
  tsf_no        NUMBER(10) not null,
  status        VARCHAR2(1) not null,
  created_date  DATE,
  processed_ind VARCHAR2(1) not null
);

 Prompt Creating Public synonymn for RMS13.SMR_RMS_RTW_STG
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_RTW_STG FOR RMS13.SMR_RMS_RTW_STG;

Prompt Select Privs on TABLE SMR_RMS_RTW_STG TO ROLES
GRANT SELECT ON SMR_RMS_RTW_STG TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_RTW_STG TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_RTW_STG TO RMS13_UPDATE;  

------------------------------------------------------------------------------------------- 
Prompt Drop table SMR_RMS_PACK_DTL_STG
DROP TABLE RMS13.SMR_RMS_PACK_DTL_STG;

Prompt create table SMR_RMS_PACK_DTL_STG  
create table RMS13.SMR_RMS_PACK_DTL_STG
(
  item          VARCHAR2(25) not null,
  status        VARCHAR2(1) not null,
  created_date  DATE,
  processed_ind VARCHAR2(1) not null
);
 Prompt Creating Public synonymn for RMS13.SMR_RMS_PACK_DTL_STG
CREATE OR REPLACE PUBLIC SYNONYM SMR_RMS_PACK_DTL_STG FOR RMS13.SMR_RMS_PACK_DTL_STG;

Prompt Select Privs on TABLE SMR_RMS_PACK_DTL_STG TO ROLES
GRANT SELECT ON SMR_RMS_PACK_DTL_STG TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_RMS_PACK_DTL_STG TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_RMS_PACK_DTL_STG TO RMS13_UPDATE;  

-------------------------------------------------------------------------------------------
Prompt Drop table SMR_ASN_VENDOR_ITEM
DROP TABLE RMS13.SMR_ASN_VENDOR_ITEM;

Prompt create table SMR_ASN_VENDOR_ITEM  
create table RMS13.SMR_ASN_VENDOR_ITEM
(  partner       NUMBER(10),
  asn           VARCHAR2(30),
  order_no      NUMBER(10),
  order_loc     VARCHAR2(3),
  carton        VARCHAR2(48),
  upc           NUMBER(14),
  sku           NUMBER(11),
  upc_char      VARCHAR2(25),
  sku_char      VARCHAR2(25),
  units_shipped NUMBER(8),
  vendor        NUMBER(10),
  mark_for      varchar2(80),
  group_id      VARCHAR2(50),
  record_id     NUMBER(10));

Prompt Creating Public synonymn for RMS13.SMR_ASN_VENDOR_ITEM
CREATE OR REPLACE PUBLIC SYNONYM SMR_ASN_VENDOR_ITEM FOR RMS13.SMR_ASN_VENDOR_ITEM;

Prompt Select Privs on TABLE SMR_ASN_VENDOR_ITEM TO ROLES
GRANT SELECT ON SMR_ASN_VENDOR_ITEM TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_ASN_VENDOR_ITEM TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_ASN_VENDOR_ITEM TO RMS13_UPDATE;   

-------------------------------------------------------------------------------------------
Prompt Drop table SMR_ASN_VENDOR_ERRORS
DROP TABLE RMS13.SMR_ASN_VENDOR_ERRORS;

Prompt create table SMR_ASN_VENDOR_ERRORS  
create table SMR_ASN_VENDOR_ERRORS
(  partner     NUMBER(10),
  asn         VARCHAR2(30),
  vendor      NUMBER(10),
  error_code  NUMBER(3),
  error_type  VARCHAR2(1),
  error_value VARCHAR2(50),
  fail_date   DATE,
  file_type   VARCHAR2(5),
  Error_msg   VARCHAR2(500),
  group_id    VARCHAR2(50),
  record_id   NUMBER(10));

Prompt Creating Public synonymn for RMS13.SMR_ASN_VENDOR_ERRORS
CREATE OR REPLACE PUBLIC SYNONYM SMR_ASN_VENDOR_ERRORS FOR RMS13.SMR_ASN_VENDOR_ERRORS;

Prompt Select Privs on TABLE SMR_ASN_VENDOR_ERRORS TO ROLES
GRANT SELECT ON SMR_ASN_VENDOR_ERRORS TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_ASN_VENDOR_ERRORS TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_ASN_VENDOR_ERRORS TO RMS13_UPDATE;   
-------------------------------------------------------------------------------------------
Prompt Alter Temp Tables releated to Vendor ASN

alter table smr_856_vendor_asn  add (group_id      VARCHAR2(50),
                                     record_id     NUMBER(10));
        
alter table smr_856_vendor_order   add (group_id      VARCHAR2(50),
                                       record_id     NUMBER(10));        
        
alter table smr_856_vendor_item   add (mark_for      varchar2(80),
									   group_id      VARCHAR2(50),
                                       record_id     NUMBER(10));    

------------------------------------------------------------------------------------------- 

Prompt Drop table SMR_BOL_SHIPMENT
DROP TABLE RMS13.SMR_BOL_SHIPMENT;

Prompt create table SMR_BOL_SHIPMENT  
create table SMR_BOL_SHIPMENT
(
  bol_no        VARCHAR2(30) not null,
  ship_date     DATE,
  from_loc      NUMBER(10) not null,
  from_loc_type VARCHAR2(1) not null,
  to_loc        NUMBER(10) not null,
  to_loc_type   VARCHAR2(1) not null,
  courier       VARCHAR2(250),
  no_boxes      NUMBER(4),
  comments      VARCHAR2(2000));

Prompt Create primary unique and foreign key constraints SMR_BOL_SHIPMENT
alter table SMR_BOL_SHIPMENT
  add constraint PK_SMR_BOL_SHIPMENT primary key (BOL_NO);
  
Prompt Create check constraints SMR_BOL_SHIPMENT
alter table SMR_BOL_SHIPMENT
  add constraint SMR_BOL_SHIPMENT_FROM_LOC_TYPE
  check (from_loc_type in ('S','W'));
alter table SMR_BOL_SHIPMENT
  add constraint SMR_BOL_SHIPMENT_TO_LOC_TYPE
  check (to_loc_type in ('S','W'));
  
Prompt Creating Public synonymn for RMS13.SMR_BOL_SHIPMENT
create or replace public synonym SMR_BOL_SHIPMENT for rms13.SMR_BOL_SHIPMENT;

Prompt Select Privs on TABLE SMR_BOL_SHIPMENT TO ROLES
GRANT SELECT ON SMR_BOL_SHIPMENT TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_BOL_SHIPMENT TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_BOL_SHIPMENT TO RMS13_UPDATE; 

------------------------------------------------------------------------------------------- 

Prompt Drop table SMR_BOL_SHIPSKU
DROP TABLE RMS13.SMR_BOL_SHIPSKU;

Prompt create table SMR_BOL_SHIPSKU  
create table SMR_BOL_SHIPSKU
(
  bol_no               VARCHAR2(30) not null,
  distro_no            NUMBER(10) not null,
  distro_type          VARCHAR2(1) not null,
  item                 VARCHAR2(25) not null,
  ref_item             VARCHAR2(25),
  carton               VARCHAR2(20),
  ship_qty             NUMBER(12,4),
  weight_expected      NUMBER(12,4),
  weight_expected_uom  VARCHAR2(4),
  last_update_datetime DATE);

Prompt Create primary unique and foreign key constraints SMR_BOL_SHIPSKU
alter table SMR_BOL_SHIPSKU
  add constraint PK_SMR_BOL_SHIPSKU primary key (BOL_NO, DISTRO_NO, DISTRO_TYPE, ITEM,CARTON);

alter table SMR_BOL_SHIPSKU
  add constraint SMR_BSU_BST_FK foreign key (BOL_NO)
  references SMR_BOL_SHIPMENT (BOL_NO);
  
Prompt Create check constraints SMR_BOL_SHIPSKU
alter table SMR_BOL_SHIPSKU
  add constraint SMR_BOL_SHIPSKU_DISTRO_TYPE
  check (distro_type in ('A','T'));
  
Prompt Creating Public synonymn for RMS13.SMR_BOL_SHIPSKU
create or replace public synonym SMR_BOL_SHIPSKU for rms13.SMR_BOL_SHIPSKU;

Prompt Select Privs on TABLE SMR_BOL_SHIPSKU TO ROLES
GRANT SELECT ON SMR_BOL_SHIPSKU TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;

Prompt DML Privs on TABLE SMR_BOL_SHIPSKU TO ROLE RMS13_UPDATE
GRANT DELETE, INSERT, UPDATE ON SMR_BOL_SHIPSKU TO RMS13_UPDATE; 

------------------------------------------------------------------------------------------- 
Prompt Drop table SMR_WH_RECEIVING_ARI
DROP TABLE RMS13.SMR_WH_RECEIVING_ARI;

Prompt create table SMR_WH_RECEIVING_ARI  
create table SMR_WH_RECEIVING_ARI
(
  order_no    NUMBER(10),
  mess        age     VARCHAR2(2000),
  alert_type  NUMBER(3),
  create_date VARCHAR2(30),
  processed   VARCHAR2(1));
  
Prompt Creating Public synonymn for RMS13.SMR_WH_RECEIVING_ARI
create or replace public synonym SMR_WH_RECEIVING_ARI for rms13.SMR_WH_RECEIVING_ARI;

Prompt Select Privs on TABLE SMR_WH_RECEIVING_ARI TO ROLES
grant select on SMR_WH_RECEIVING_ARI to RMS13_SELECT;

Prompt DML Privs on TABLE SMR_WH_RECEIVING_ARI TO ROLE RMS13_UPDATE
grant insert, update, delete on SMR_WH_RECEIVING_ARI to RMS13_UPDATE;

------------------------------------------------------------------------------------------- 