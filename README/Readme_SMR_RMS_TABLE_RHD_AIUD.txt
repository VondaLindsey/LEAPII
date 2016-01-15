Object Name : SMR_RMS_TABLE_RHD_AIUD 

Description:
  The Trigger SMR_RMS_TABLE_RHD_AIUD on RTV_HEAD table is used to load all Vendor RTV created in RMS For Warehouse in the  staging table SMR_RMS_RTV_STG. The data from the staging table is then inserted into the Interface table by a batch job.


Algorithm :
    -- Check is the RTV is approved/Cancelled  
    -- Insert RTV details into SMR_RMS_RTV_STG with status as 'A' if item is just approved or 'C' if item was Cancelled.          