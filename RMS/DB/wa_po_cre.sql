drop table SMR_RMS_WH_PO_HDR_EXP;
create table SMR_RMS_WH_PO_HDR_EXP(
       GROUP_ID           VARCHAR2(80),
       RECORD_ID          NUMBER(10),
       ProcessingCode     VARCHAR2(6),
       order_no           NUMBER(9),
       location           NUMBER(10),
       wh                 NUMBER(10),
       physical_wh        NUMBER(10),
       po_type            VARCHAR2(5),
       order_type         VARCHAR2(3),
       Status             VARCHAR2(6),
       freight_terms      VARCHAR2(30),
       supplier        NUMBER(10),
       buyer              NUMBER(4),
       dept               NUMBER(4),
       earliest_ship_date DATE,
       latest_ship_date   DATE,
       not_before_date    DATE,
       not_after_date     DATE,
       modifyDate         DATE);

drop table SMR_RMS_WH_PO_DTL_STG;
create table SMR_RMS_WH_PO_DTL_STG(
       GROUP_ID           VARCHAR2(80),
       order_no           NUMBER(9),
       physical_wh        NUMBER(10),
       location           NUMBER(10),
       item               NUMBER(11),
       pack_ind           VARCHAR2(1),
       qty_ordered        NUMBER(12,4),
       create_datetime    DATE        DEFAULT SYSDATE,
       processed_ind      VARCHAR2(1) DEFAULT 'N',
       processed_datetime DATE);

drop table SMR_RMS_WH_PO_DTL_EXP;
create table SMR_RMS_WH_PO_DTL_EXP(
       GROUP_ID           VARCHAR2(80),
       RECORD_ID          NUMBER(10),
       order_no           NUMBER(9),
       physical_wh        NUMBER(10),
       item               NUMBER(11),
       pack_ind           VARCHAR2(1),
       qty_ordered        NUMBER(12,4));

drop table SMR_RMS_WH_PO_HDR_UPD_STG;
create table SMR_RMS_WH_PO_HDR_UPD_STG as ( select * from SMR_RMS_WH_PO_HDR_EXP where 1=2);
alter table SMR_RMS_WH_PO_HDR_UPD_STG add (create_datetime DATE        DEFAULT SYSDATE);
alter table SMR_RMS_WH_PO_HDR_UPD_STG add (processed_ind VARCHAR2(1) DEFAULT 'N');

drop table SMR_RMS_WH_PO_DTL_UPD_STG;
create table SMR_RMS_WH_PO_DTL_UPD_STG as ( select * from SMR_RMS_WH_PO_DTL_EXP where 1=2);

drop public synonym SMR_RMS_WH_PO_HDR_EXP;   
create public synonym SMR_RMS_WH_PO_HDR_EXP for RMS13.SMR_RMS_WH_PO_HDR_EXP;
grant select,insert,update on SMR_RMS_WH_PO_HDR_EXP to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_RMS_WH_PO_HDR_EXP TO SVC_INT_RMS;

drop public synonym SMR_RMS_WH_PO_DTL_STG;   
create public synonym SMR_RMS_WH_PO_DTL_STG for RMS13.SMR_RMS_WH_PO_DTL_STG;
grant select,insert,update on SMR_RMS_WH_PO_DTL_STG to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_RMS_WH_PO_DTL_STG TO SVC_INT_RMS;

drop public synonym SMR_RMS_WH_PO_DTL_EXP;   
create public synonym SMR_RMS_WH_PO_DTL_EXP for RMS13.SMR_RMS_WH_PO_DTL_EXP;
grant select,insert,update on SMR_RMS_WH_PO_DTL_EXP to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_RMS_WH_PO_DTL_EXP TO SVC_INT_RMS;

drop public synonym SMR_RMS_WH_PO_HDR_UPD_STG;   
create public synonym SMR_RMS_WH_PO_HDR_UPD_STG for RMS13.SMR_RMS_WH_PO_HDR_UPD_STG;
grant select,insert,update on SMR_RMS_WH_PO_HDR_UPD_STG to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_RMS_WH_PO_HDR_UPD_STG TO SVC_INT_RMS;

drop public synonym SMR_RMS_WH_PO_DTL_UPD_STG;   
create public synonym SMR_RMS_WH_PO_DTL_UPD_STG for RMS13.SMR_RMS_WH_PO_DTL_UPD_STG;
grant select,insert,update on SMR_RMS_WH_PO_DTL_UPD_STG to DEVELOPER,RMS13_SELECT;
GRANT  INSERT, UPDATE ON SMR_RMS_WH_PO_DTL_UPD_STG TO SVC_INT_RMS;

