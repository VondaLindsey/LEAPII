Object Name : SMR_RMS_TABLE_IEMVP_AIUD

Description :
    The Trigger SMR_RMS_TABLE_IEMVP_AIUD on ITEM_MASTER table is used to load all Vendor Packs created in RMS to staging table SMR_RMS_PACK_DTL_STG. The data from the staging table is then inserted into the Interface table by a batch job.

Algorithm :
    -- Check the Item approved is Vendor Pack (Pack_Type = 'V' , Simple_Pack_Ind = 'N'  and Pack_ind = 'Y'
    -- Insert pack details into SMR_RMS_PACK_DTL_STG with status as 'A' if item is just approved or 'D' if item was deleted.          