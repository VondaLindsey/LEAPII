Object Name : ordhead.fmb

Description:
   The Ordhead form was modified as part of Leap . Below are the list of changes  

- The Base Ordhead form was modified to restrict the Order from having Mixed Items. The order cannot contain a mix of Vendor Pack and and normal Items
- The form was also modified to default and "Include on On-Order" flag to 'N' for Bulk(9401) orders and make the field disabled for the same.


Algorithm
 - Validate Order(P_CHK_PACK_EACH_MIX) On Submitting and while Saving to check if the Order Contains Regular Item and Pack Items.
 - Disable the "Include on On-Order" For 9401 Orders.