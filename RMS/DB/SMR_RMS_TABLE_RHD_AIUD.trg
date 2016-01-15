CREATE OR REPLACE TRIGGER SMR_RMS_TABLE_RHD_AIUD
/*=====================================================================================*/
--
-- Module Name: SMR_RMS_TABLE_RHD_AIUD
-- Description: Trigger on Item Master to stage Vendor Packs
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== ===============================================
-- 1.00    30-May-15 Murali N    LEAP     Capture the approved RTV for WH in a staging table
/*
Description:
  The Trigger SMR_RMS_TABLE_RHD_AIUD on RTV_HEAD table is used to load all Vendor RTV created in RMS For Warehouse in the  staging table 
SMR_RMS_RTV_STG. The data from the staging table is then inserted into the Interface table by a batch job.

Algorithm :
    -- Check is the RTV is approved/Cancelled 
    -- Insert RTV details into SMR_RMS_RTV_STG with status as 'A' if item is just approved or 'C' if item was Cancelled.      
*/
-----------------------------------------------------------------------------------------
/*=====================================================================================*/
 AFTER DELETE OR UPDATE
 ON RTV_HEAD
REFERENCING NEW AS New OLD AS Old
 FOR EACH ROW
DECLARE
   L_status_new   rtv_head.STATUS_IND%type;
   L_status_old       rtv_head.STATUS_IND%type;
   L_status      varchar2(1);
   L_RTV_ORDER_NO rtv_head.rtv_order_no%type;
BEGIN

     L_status_new := :New.STATUS_IND;
     L_status_old := nvl(:Old.STATUS_IND,5);
     L_RTV_ORDER_NO := :New.RTV_ORDER_NO;

     if L_status_new in(10,20) and  L_status_old not in (10,20) then

      if L_status_new = 20 then
        L_status := 'C';
      else
         L_status := 'A';
      end if;

      insert into SMR_RMS_RTV_STG values (L_RTV_ORDER_NO,
                                     L_status,
                                     sysdate,
                                     'N');
     end if;
EXCEPTION

  WHEN OTHERS then
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: SMR_RMS_RTV_STG - Error Inserting into SMR_RMS_RTV_STG table-'||SQLERRM);

END;
/