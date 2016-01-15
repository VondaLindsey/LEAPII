Object Name : smr_wh_rua.fmb

Description :
   The New Custom Form smr_wh_rua was developed to Process/Review the Receipt Adjustments from WA into RMS . In case a Reciept adjsutment is created for a PO after an Invoice is matched or attempted Match the Reciept is put on Hold . The user then reviews theadjustment using the screen and decides to further process it or Just Ignore it.  


Algorithm
   - The screen displays all RUA's from WA that are either sucessfully processed by batch or is put on hold because an Invoice Exists.
   - The RUA data are staged in SMR_RMS_WH_RUA.
   - The user can Process the RUA on hold using the Screen.
   - The RUA process is similar to the Base RMS RUA form. 