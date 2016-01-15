CREATE OR REPLACE TRIGGER SMR_RMS_TABLE_THD_AIUD
/*=====================================================================================*/
--
-- Module Name: SMR_RMS_TABLE_THD_AIUD
-- Description: Trigger on Item Master to stage Vendor Packs
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== ===============================================
-- 1.00    30-May-15 Murali N    LEAP     Capture the Shipped Store to WH Transfer in a staging table
/*
Description:
  The Trigger SMR_RMS_TABLE_THD_AIUD on TSFHEAD table is used to load all Vendor RTW created in RMS in the  staging table SMR_RMS_RTW_STG. 
  The data from the staging table is then inserted into the Interface table by a batch job.
  
Algorithm :
  - Check is the transfer is from a Store to warehouse and it is in Shipped status
  - Insert the transfer details into SMR_RMS_RTW_STG.  
*/

 AFTER INSERT or DELETE OR UPDATE
 ON TSFHEAD
REFERENCING NEW AS New OLD AS Old
 FOR EACH ROW
DECLARE
   L_status_new   tsfhead.STATUS%type;
   L_status_old       tsfhead.STATUS%type;
   L_status      varchar2(1);
   L_tsf_no     tsfhead.tsf_no%type;
BEGIN

     L_status_new := :New.STATUS;
     L_status_old := nvl(:Old.STATUS,'I');
     L_tsf_no := :New.tsf_no;

     if :new.from_loc_type= 'S' and :new.to_loc_type = 'W' then
       if (L_status_new = 'S' and  L_status_old <> 'S') then
        L_status := 'A';
        insert into SMR_RMS_RTW_STG values (L_tsf_no,
                                       L_status,
                                       sysdate,
                                       'N');
       end if;
     end if;
EXCEPTION

  WHEN OTHERS then
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: SMR_RMS_RTW_STG - Error Inserting into SMR_RMS_RTW_STG table-'||SQLERRM);

END;
/