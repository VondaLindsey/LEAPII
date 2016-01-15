This script creates a trigger on TSFHEAD table.
Basically this trigger collects Warehouse Transfers information into SMR_RMS_INT_TSF_STG staging table through out the day. 
There will be another job that will process this staged data at a scheduled time via UC4.
Once this information is processed the records will be deleted from the SMR_RMS_INT_TSF_STG staging table.

