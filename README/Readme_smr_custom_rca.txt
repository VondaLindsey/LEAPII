Object Name : smr_custom_rca

Description :
    The Package smr_custom_rca was modifed to make Changes to the custom RUA packages to adjust the the shipment to the store 
	in case a Xdoc PO Reciept is adjusted. The final destination of a Carton in Xdoc PO can be identified based on the to_loc in the Carton table or the actual_receiving_store in shipsku table.  The Script also Updates the SOH in SIM tables using a DB link.

Algorithm
    - When a RUA is a done for a Xdoc PO the function is SMR_CUSTOM_RCA.F_PROCESS_ADJUSTMENT is invoked.
    - The function F_PROCESS_ADJUSTMENT reverses the store shipment and posts reversal for tran code 30 and 32
    - The function also updates the SOH in SIM using DB link.
    - In case the store shipment does not exist in SIM the RUA for XDOC PO is not done.