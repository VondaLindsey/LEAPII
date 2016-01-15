Object : recutadj.fmb

Description :
     The form recutadj was modifed to invoke the custom package smr_custom_rca for Xdoc Receipts to create adjustment for the store shipments created . The custom package is only invoked for Xdoc PO's.

Algorithm
     - The Form was modified to call the function SMR_CUSTOM_RCA.F_SAVE_ADJUSTMENT for only Xdoc warehouses
     - The function SMR_CUSTOM_RCA.F_SAVE_ADJUSTMENT is used to create the reversal of the store shipments and also update the SOH in SIM.
     