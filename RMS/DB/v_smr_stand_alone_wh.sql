  CREATE OR REPLACE FORCE VIEW "RMS13"."V_SMR_STAND_ALONE_WH" ("WH", "PHYSICAL_WH_IND") AS 
  select wh.wh, decode(wh.physical_wh, wh.wh, 'Y','N') physical_wh_ind
  from wh,
       wh_attributes wh_a
 where wh.wh = wh_a.wh
   and wh_type_code = 'PA' /* Put-away */;
