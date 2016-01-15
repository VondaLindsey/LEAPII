Object Name : Ordloc.fmb

Description:
	
- The Base Ordloc form was modified to include a New Canvas to Distribute the Holdback qty(Not allocated for Xdoc) across the 3 warehouses.   Once the distribution is done for the holdback Qty using the Screen the Split PO's are created in RMS .
- The warehouses 953 and 954 can handle only Boxes so the Distribution is enabled for these warehouses only if the Case Name is Box
- ALso for Item with Supp_pack_size > 1 the Distribution will always be rounded to the nearest case pack .

Algorithm
    - Define New Convas C_ALLOC_HOLDBACK to distribute the Holdback Qty
    - Define Data Blocks B_ALLOC_HB_DETAIL and B_ALLOC_HB_HEADER to capture the Distribution Details .
    - The Distribution is enabled for WH 953 and 954 only for items with Case Name(Item_supplier) as Box(BX).
    - The Split PO's are created and approved after the Hold Back Distribution(B_ALLOC_HB_ACTION.PB_APPROVE)