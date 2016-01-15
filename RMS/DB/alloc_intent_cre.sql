drop table SMR_ORD_ALLOC_INTENT;
create table SMR_ORD_ALLOC_INTENT(
  GROUP_ID	        VARCHAR2(80),
  RECORD_ID	        NUMBER(10),
  ORDER_NO	        NUMBER(10),
  ALLOC_INTENT_IND	VARCHAR(1),
  ARI_SENT_IND	        VARCHAR(1),
  ARI_SENT_DATETIME	DATE,
  CREATE_DATETIME	DATE,
  CREATE_USERID	        VARCHAR2(100));
  
  CREATE OR REPLACE FORCE VIEW "RMS13"."V_SMR_ORD_ALC_INTENT" ("ORDER_NO", "DEPT", "WH", "WH_NAME", "SUPPLIER", "SUP_NAME", "ALLOC_INTENT_IND", "STATUS") AS 
  (
  select a.order_no,
         a.dept,
         a.location wh,
         b.wh_name,
         a.supplier,
         d.sup_name,
         nvl(e.alloc_intent_ind,'N') alloc_intent_ind,
         e.status
    from ordhead a,
         wh b,
         wh_attributes c,
         sups d,
         (select alloc_intent_ind, order_no, status 
            from smr_ord_alloc_intent x, 
                 smr_rms_int_queue y 
           where x.group_id = y.group_id
             and x.create_datetime = (select max(create_datetime) from smr_ord_alloc_intent where order_no = x.order_no)) e
   where a.supplier = d.supplier
     and a.location = b.wh
     and a.status = 'A'
     and b.wh = c.wh
     and c.wh_type_code = 'PA'
     and a.order_no = e.order_no(+));
  
 
delete from nav_element_mode_role where element = 'ordalcintnt';
delete from nav_element_mode where element = 'ordalcintnt';
delete from nav_element where element = 'ordalcintnt';

insert into nav_element values ('ordalcintnt','F','RMS');
/* 
  no longer needed re: Raj created 6/18/2013
     insert into nav_folder(folder, folder_name) values ('SMR_CUSTOM','SMR_Custom');
*/
insert into nav_element_mode(element,nav_mode,folder,element_mode_name) values ('ordalcintnt','EDIT','SMR_CUSTOM','Order Alloc Intent');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','DEVELOPER');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','RMS13_SELECT');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','RMS13_UDPATE');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','VIEW_ONLY');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','DATASUPP1');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','DATASUPP2');
insert into nav_element_mode_role values ('ordalcintnt','EDIT','SMR_CUSTOM','EXECMERCH');
commit;     

drop public synonym SMR_ORD_ALLOC_INTENT;

create or replace public synonym SMR_ORD_ALLOC_INTENT for rms13.SMR_ORD_ALLOC_INTENT;
GRANT SELECT ON SMR_ORD_ALLOC_INTENT TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;
GRANT DELETE, INSERT, UPDATE ON SMR_ORD_ALLOC_INTENT TO RMS13_UPDATE;  

create or replace public synonym v_smr_ord_alc_intent for rms13.v_smr_ord_alc_intent;
GRANT SELECT ON v_smr_ord_alc_intent TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT,RMS13_UPDATE;

insert into SMR_RMS_INT_TYPE values(113,'ALLOC_INTENT','Intent to allocate by ASN to WA','E');
commit;
