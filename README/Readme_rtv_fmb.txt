Object Name : Rtv.fmb

Description:
    The base rtv form was modified to default the Inventory staus fields in the RTV screen. The USer can now only select the Inventory Status as Available whil creating a Mass transfer. Also the list of custom reason Codes are included in the base form.


Algorithm : 
     - The inventory Status Field(B_RTV_APPLY.LI_INV_STATUS) in the RTV form is defaulted to "Available" when the user created a Mass Transfer.
     - The Custom RTV reason codes are added to the Reason Code LOV for the returns.      

