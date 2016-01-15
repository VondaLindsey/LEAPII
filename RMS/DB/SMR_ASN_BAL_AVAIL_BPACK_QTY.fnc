CREATE OR REPLACE FUNCTION RMS13.SMR_ASN_BAL_AVAIL_BPACK_QTY (I_asn               IN     shipment.asn%TYPE,
                                                        I_pack_no           IN     item_master.item%type,
                                                        I_item              IN     item_master.item%type,
                                                        I_location          IN     store.store%type ,
                                                        I_min_pack_qty      IN     item_loc_soh.STOCK_ON_HAND%TYPE) 
     RETURN item_loc_soh.STOCK_ON_HAND%TYPE IS
     
     
     L_calc_qty        item_loc_soh.STOCK_ON_HAND%TYPE :=0;
     L_calc_unit_qty        item_loc_soh.STOCK_ON_HAND%TYPE :=0;

    cursor c_qty is
       select distinct ss.shipment shipment, ss.item item , sum(ss.qty_expected) qty_expected, sum(ss.qty_received) qty_received,
              pb.pack_item_qty
             from shipsku ss, shipment s ,  packitem_breakout pb  where ss.shipment = s.shipment and s.asn= I_asn 
               and pb.item = ss.item
               and pb.pack_no = I_pack_no
               and s.to_loc = I_location
               and ss.item =  I_item
             group by ss.shipment, ss.item, s.shipment, s.asn ,pb.pack_item_qty ;

  
  BEGIN
  
  
     for r1 in c_qty loop
         L_calc_qty := ( r1.qty_expected - nvl( r1.qty_received,0) )/r1.pack_item_qty;

         
         L_calc_unit_qty  := abs(L_calc_unit_qty - I_min_pack_qty ) * r1.pack_item_qty;
     
     end loop;
  
     return L_calc_unit_qty;
  END;
/