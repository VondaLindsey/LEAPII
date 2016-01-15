This script creates a trigger on alloc_header table.
Information of Approved allocations that are for putaway Wh's will be collected  through out the day into SMR_RMS_INT_ALLOC_STG staging table.
Once the allocation is putaway to WH , the allocation is locked so the user will not be able to modify.
There will be another job that will be scheduled and run through UC4 which will process this information and send to WA.
Once this information is processed the records will be deleted from the SMR_RMS_INT_ALLOC_STG staging table.
