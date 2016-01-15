Create or replace view smr_alc_holdback_v as (
select b.order_no,a.alloc_id,a.item_id,hold_back_pct_flag,hold_back_value,avail_qty 
  from alc_item_source a, alc_xref b
 where a.alloc_id = b.alloc_id
   and b.item_id = a.item_id
   and a.hold_back_value > 0);

drop table smr_alloc_wh_hold_back;
create table smr_alloc_wh_hold_back(
order_no number(10) not null,
alloc_id number(15) not null,
item_id varchar2(40) not null,
hold_back_pct_flag varchar2(1) not null,
hold_back_value number(12,4) not null,
avail_qty number(12,4) not null,
sdc1 number(10),
sdc2 number(10),
sdc3 number(10),
sdc1_hb_qty number(12,4),
sdc2_hb_qty number(12,4),
sdc3_hb_qty number(12,4),
sdc_order_create_datetime date);

CREATE OR REPLACE PUBLIC SYNONYM SMR_ALLOC_WH_HOLD_BACK FOR RMS13.SMR_ALLOC_WH_HOLD_BACK;
GRANT SELECT ON SMR_ALLOC_WH_HOLD_BACK TO SMR_READONLY,SVC_SMRREP,BI_RMS_USER,RMS13_SELECT;
GRANT DELETE, INSERT, UPDATE ON SMR_ALLOC_WH_HOLD_BACK TO RMS13_UPDATE;  


/****
insert into smr_alloc_wh_hold_back (order_no,alloc_id,item_id,hold_back_pct_flag,hold_back_value,avail_qty)(
select order_no,alloc_id,item_id,hold_back_pct_flag,hold_back_value,avail_qty 
  from alc_item_source
 where nvl(hold_back_value,0) > 0
   and (order_no,alloc_id,item_id) in 
  ( select to_number(order_no),alloc_id,item_id
      from alc_item_source
   minus
    select order_no,alloc_id,item_id
      from smr_alloc_wh_hold_back ));
commit;
*****/

