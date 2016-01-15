This script loads the original EDI 810 file that comes to BSYS from vendor.
There will not be any validation on the contents of the file, the data from the file
will be loaded into below staging tables via sql loader
-- SMR_RMS_INT_EDI_810_HDR_STG
-- SMR_RMS_INT_EDI_810_DTL_STG
Next step in this script is loading the staged data into following tables with line sequence number
-- SMR_RMS_INT_EDI_810_HDR_IMP
-- SMR_RMS_INT_EDI_810_DTL_IMP
Since this tables have proper line sequence number and formatted lines, it will be easy to spool and generate file to be loaded later