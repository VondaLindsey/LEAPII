CREATE OR REPLACE TRIGGER SMR_RMS_TABLE_IEMVP_AIUD
/*=====================================================================================*/
--
-- Module Name: SMR_RMS_TABLE_IEMVP_AIUD
-- Description: Trigger on Item Master to stage Vendor Packs
--
-- Modification History
-- Version Date      Developer   Issue    Description
-- ======= ========= =========== ======== ===============================================
-- 1.00    30-May-15 Murali N    LEAP     Capture the Vendor packs in a staging table
/*
Description :
    The Trigger SMR_RMS_TABLE_IEMVP_AIUD on ITEM_MASTER table is used to load all Vendor Packs created in RMS to staging table 
SMR_RMS_PACK_DTL_STG. The data from the staging table is then inserted into the Interface table by a batch job.

Algorithm :
    -- Check the Item approved is Vendor Pack (Pack_Type = 'V' , Simple_Pack_Ind = 'N'  and Pack_ind = 'Y'
    -- Insert pack details into SMR_RMS_PACK_DTL_STG Eith status as 'A' if item is just approved or 'D' if item was deleted.       
*/
-----------------------------------------------------------------------------------------
/*=====================================================================================*/

 After INSERT or DELETE OR UPDATE
 ON ITEM_MASTER
REFERENCING NEW AS New OLD AS Old
 FOR EACH ROW
DECLARE
   L_status_new   item_master.STATUS%type;
   L_status_old       item_master.STATUS%type;
   L_status      varchar2(1);
   L_item     item_master.item%type;
BEGIN

     L_status_new := :New.STATUS;
     L_status_old := nvl(:Old.STATUS,'W');
     L_item := :New.item;

     IF :New.Pack_Ind = 'Y' and :New.Simple_Pack_Ind = 'N' and :New.Pack_Type = 'V' then

     if INSERTING or UPDATING then
       if (L_status_new = 'A' and  L_status_old <> 'A') then
        L_status := 'A';
        insert into SMR_RMS_PACK_DTL_STG values (L_item,
                                                 L_status,
                                                 sysdate,
                                                 'N');
       end if;
     elsif DELETING then
        L_status := 'D' ;
        insert into SMR_RMS_PACK_DTL_STG values (L_item,
                                                 L_status,
                                                 sysdate,
                                                 'N');
     end if;
     end if;
EXCEPTION

  WHEN OTHERS then
      RAISE_APPLICATION_ERROR(-20000,'INTERNAL ERROR: SMR_RMS_PACK_DTL_STG - Error Inserting into SMR_RMS_PACK_DTL_STG table.-'||SQLERRM);

END;
/