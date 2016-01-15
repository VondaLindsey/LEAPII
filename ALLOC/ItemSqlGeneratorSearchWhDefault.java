/* 
--------------------------------------------------------------------------------
Modification History

Revision : $Id: ItemSqlGeneratorSearchWhDefault.java,v 1.1 2015/08/07 15:31:45 potukuchia Exp $

Ver. Date     Developer        Description
==== ======== ===========      ======================================================
1.0 07-FEB-11 Oracle	       Initial version
1.1 07-FEB-11 Anil Potukuchi   SMR OLR CR #103 
                               For Buyer pack Mod

$Log: ItemSqlGeneratorSearchWhDefault.java,v $
Revision 1.1  2015/08/07 15:31:45  potukuchia
Initial version

Revision 1.1  2012/09/26 14:42:58  apotukuchi
Anil's Machine Code Last one.

Revision 1.4  2011/04/12 17:36:38  apotukuchi
Added Dynamic Revision and Log


--------------------------------------------------------------------------------
*/
package com.retek.alloc.db.rms.v11.itemdao;

import java.io.Serializable;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.Map;

import com.retek.alloc.business.Source;
import com.retek.alloc.db.rms.v11.AItemDao;

public class ItemSqlGeneratorSearchWhDefault extends AItemSearchSqlGenerator implements
        Serializable {
    private static final long serialVersionUID = -1954358537037785876L;
    private int bindCount;

    private static final String AVAIL_QTY_ONE = "alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(d.item, 0, il.loc) \n"
            + "                + nvl((select sum(qty_allocated) \n"
            + "                       from alloc_header alh, alloc_detail ald, alc_xref alx \n"
            + "                       where alx.alloc_id = ? \n"
            + "                         and alh.alloc_no = alx.xref_alloc_no \n"
            + "                         and ald.alloc_no=alh.alloc_no \n"
            + "                         and alh.item=d.item \n"
            + "                         and alh.wh=il.loc \n"
            + "                         and alh.order_no is NULL \n"
            + "                       group by alh.item),0) \n";
            
     /* SMR OLR v1.1 CR#103 Mod - Inserted START */                    
    private static final String AVAIL_QTY_ONEB = " to_number( trunc( min ( (  alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(case when d.pack_type = 'B' and sso.use_buyer_pack = 'Y' then pb.item else d.item end, 0, il.loc) \n"
            + "                + nvl((select sum(qty_allocated) \n"
            + "                       from alloc_header alh, alloc_detail ald, alc_xref alx  \n"
            + "                       where alx.alloc_id = ? \n"
            + "                         and alh.alloc_no = alx.xref_alloc_no \n"
            + "                         and ald.alloc_no=alh.alloc_no \n"
            + "                         and alh.item=case when d.pack_type = 'B' and sso.use_buyer_pack = 'Y' then im1.item else d.item end \n"
            + "                         and alh.wh=il.loc \n"
            + "                         and alh.order_no is NULL \n"
            + "                       group by alh.item),0)   ) / case when d.pack_type = 'B' and sso.use_buyer_pack = 'Y' then pb.pack_item_qty else 1 end)) ) \n";
    /* SMR OLR v1.1 CR#103 Mod - Inserted END */         
    private static final String AVAIL_QTY_TWO = "alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(d.item, 0, il.loc) \n"
            + "                + nvl((select sum(qty_allocated) \n"
            + "                       from alloc_header alh, alloc_detail ald, alc_xref alx \n"
            + "                       where alx.alloc_id = ? \n"
            + "                         and alh.alloc_no = alx.xref_alloc_no \n"
            + "                         and ald.alloc_no=alh.alloc_no \n"
            + "                         and alh.item=d.item \n"
            + "                         and alh.wh=il.loc \n"
            + "                         and alh.order_no is NULL \n"
            + "                       group by alh.item),0) \n";

    private static final String AVAIL_QTY_THREE = "alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(pack.item, 0, il.loc) \n"
            + "                + nvl((select sum(qty_allocated) \n"
            + "                       from alloc_header alh, alloc_detail ald, alc_xref alx \n"
            + "                       where alx.alloc_id = ? \n"
            + "                         and alh.alloc_no = alx.xref_alloc_no \n"
            + "                         and ald.alloc_no=alh.alloc_no \n"
            + "                         and alh.item=pack.item \n"
            + "                         and alh.wh=il.loc \n"
            + "                         and alh.order_no is NULL \n"
            + "                       group by alh.item),0) \n";

    private static final String AVAIL_QTY_THREE_A = "alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(im.item, 0, il.loc) \n"
            + "                + nvl((select sum(qty_allocated) \n"
            + "                       from alloc_header alh, alloc_detail ald, alc_xref alx \n"
            + "                       where alx.alloc_id = ? \n"
            + "                         and alh.alloc_no = alx.xref_alloc_no \n"
            + "                         and ald.alloc_no=alh.alloc_no \n"
            + "                         and alh.item=im.item \n"
            + "                         and alh.wh=il.loc \n"
            + "                         and alh.order_no is NULL \n"
            + "                       group by alh.item),0) \n";

    private static final String AVAIL_QTY_FOUR = "alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(p.item, 0, il.loc) \n"
            + "                + nvl((select sum(qty_allocated) \n"
            + "                       from alloc_header alh, alloc_detail ald, alc_xref alx \n"
            + "                       where alx.alloc_id = ? \n"
            + "                         and alh.alloc_no = alx.xref_alloc_no \n"
            + "                         and ald.alloc_no=alh.alloc_no \n"
            + "                         and alh.item=p.item \n"
            + "                         and alh.wh=il.loc \n"
            + "                         and alh.order_no is NULL \n"
            + "                       group by alh.item),0) \n";

    public ItemSqlGeneratorSearchWhDefault(AItemDao bean, Map mapOfSqlIndexes) {
        super(bean, 99999, mapOfSqlIndexes);
    }

    public String buildSqlQuery() {
        // populate common buffers
        StringBuffer fromTables = populateFrom();
        StringBuffer whereClause = populateWhere();

        // construct the main section and it's sub-sections
        String sql = mainSection(whereClause, fromTables);

        return sql;

    }

    protected StringBuffer populateFrom() {
        StringBuffer fromTables = new StringBuffer();

        if (this.poNo.length() > 0) {
            fromTables.append("         ordloc ol,\n");
        } else if (this.asnNo.length() > 0) {
            fromTables.append("         shipment s, \n");
            fromTables.append("         shipsku ss, \n");
            // fromTables.append(" wh, \n");
        }

        if (this.apptNo.length() > 0) {
            if (this.apptType.equals("T")) {
                fromTables.append("         tsfdetail td,\n");
            } else {
                fromTables.append("         ordsku os,\n");
            }
        }

        return fromTables;
    }

    protected StringBuffer populateWhere() {
        StringBuffer whereClause = new StringBuffer();

        if (this.poNo.length() > 0) {
            whereClause.append("     and ol.order_no = ? \n");
            whereClause.append("     and ol.loc_type = 'W' \n");
            whereClause.append("     and ol.location = il.loc  \n");
            if (whNo.length() > 0) {
                whereClause.append("     and ol.location = ? \n");
            }

            whereClause.append("     and ol.item = d.item \n");
        } else if (this.asnNo.length() > 0) {
            whereClause.append("     and s.asn = ? \n");
            whereClause.append("     and s.shipment = ss.shipment \n");
            whereClause.append("     and nvl(ss.qty_received,0) >0 \n");
            whereClause.append("     and s.to_loc_type = 'W' \n");

            // whereClause.append(" and s.to_loc = il.loc \n");
            whereClause.append("     and s.to_loc = wh.physical_wh \n");
            whereClause.append("     and wh.wh = il.loc \n");

            if (whNo.length() > 0) {
                whereClause.append("     and s.to_loc = ? \n");
            }
            whereClause.append("     and ss.item = d.item \n");
        } else
        // both orderNo and asnNo are null
        {
            if (whNo.length() > 0) {
                whereClause.append("     and il.loc = ? \n");
            }
        }
        if (this.apptNo.length() > 0) {
            if (this.apptType.equals("T")) {
                whereClause.append("     and il.item = td.item \n");
                whereClause.append("     and td.tsf_no in ( select doc from appt_detail\n");
                whereClause.append("                                    where doc_type = 'T'\n");
                whereClause.append("                                      and appt = ? )\n");
            } else {
                whereClause.append("     and il.item = os.item \n");
                whereClause.append("     and os.order_no in ( select doc from appt_detail\n");
                whereClause.append("                                    where doc_type = 'P'\n");
                whereClause.append("                                      and appt = ? )\n");
            }
        }

        return whereClause;
    }

    protected boolean sectionOne(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer) {
     
        /* SMR OLR v1.1 CR#103 Mod - Removed START */
     /*       
        sqlBuffer.append("  -- Wh default section 1 \n");
        sqlBuffer.append("  SELECT");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_ONE));
        sqlBuffer.append("         distinct d.item,  \n");
        sqlBuffer.append("         d.item_desc,  \n");
        sqlBuffer.append("         il.loc loc,   \n");
        sqlBuffer.append("         null order_no,   \n");
        sqlBuffer.append("         0 avail_qty,  \n");
        sqlBuffer.append("         decode(d.item_parent, null,'T', '1') parent_code, \n");
        sqlBuffer.append("         d.pack_ind,  \n");
        sqlBuffer.append("         d.sellable_ind,  \n");
        sqlBuffer.append("         '" + Source.WAREHOUSE + "' source_type,  \n");
        sqlBuffer.append("         d.diff_1,  \n");
        sqlBuffer.append("         d.dept,  \n");
        sqlBuffer.append("         d.class,  \n");
        sqlBuffer.append("         d.subclass,  \n");
        sqlBuffer.append("         d.diff_2,  \n");
        sqlBuffer.append("         d.diff_3,  \n");
        sqlBuffer.append("         d.diff_4,  \n");
        sqlBuffer.append("         d.item_parent,  \n");
        sqlBuffer.append("         d.item_grandparent,  \n");
        sqlBuffer.append("         d.tran_level,  \n");
        sqlBuffer.append("         'N' " + NON_SELLABLE_FASHION_PACK + ", \n");
        sqlBuffer.append("         1 os_sps,  \n");
        sqlBuffer.append(AVAIL_QTY_ONE + " curr_avail, \n");

        sqlBuffer.append("         isc.INNER_PACK_SIZE isc_ips, \n");
        sqlBuffer.append("         isc.supp_pack_size  isc_sps, \n");
        sqlBuffer.append("         isc.ti isc_ti, \n");
        sqlBuffer.append("         isc.hi isc_hi, \n");
        sqlBuffer.append("         null not_after_date, \n");
        sqlBuffer.append("         wh.break_pack_ind break_pack_ind  \n");
        sqlBuffer.append("    FROM item_master d, \n");
        sqlBuffer.append("         item_master im1, \n");
        sqlBuffer.append("         packitem_breakout pb,   \n");
        sqlBuffer.append("         item_loc_soh il,   \n");
        sqlBuffer.append("         wh,   \n");
        sqlBuffer.append(getBean().getFromTables());
        sqlBuffer.append(fromTables);
        sqlBuffer.append("         item_supp_country isc   \n");

        sqlBuffer.append("          WHERE d.item = il.item   \n");
        sqlBuffer.append("            and d.status = 'A' \n");
        sqlBuffer.append("            and d.item = isc.item(+)  \n");
        sqlBuffer.append("            and isc.primary_supp_ind(+) = 'Y' \n");
        sqlBuffer.append("            and isc.primary_country_ind(+) = 'Y' \n");
        sqlBuffer.append("            and d.item = pb.pack_no \n");
        sqlBuffer.append("            and pb.item = im1.item  \n");
        sqlBuffer.append("            and ((im1.tran_level = 1  \n");
        sqlBuffer.append("                  and im1.item_level = 1  \n");
        sqlBuffer.append("                  and im1.ITEM_AGGREGATE_IND = 'N') or \n");
        sqlBuffer.append("                 (im1.tran_level = 2 \n");
        sqlBuffer.append("                  and im1.item_parent in \n");
        sqlBuffer.append("                  (select item \n");
        sqlBuffer.append("                     from item_master \n");
        sqlBuffer.append("                    where ITEM_AGGREGATE_IND = 'N')) or \n");
        sqlBuffer.append("                 (im1.tran_level = 3 \n");
        sqlBuffer.append("                  and im1.item_grandparent in \n");
        sqlBuffer.append("                  (select item \n");
        sqlBuffer.append("                     from item_master \n");
        sqlBuffer.append("                    where ITEM_AGGREGATE_IND = 'N')) \n");
        sqlBuffer.append("                  )  \n");
        sqlBuffer.append("            and il.loc_type = 'W'  \n");
        sqlBuffer.append("            and wh.wh = il.loc  \n");
        sqlBuffer.append("            and wh.redist_wh_ind = 'N'  \n");
        sqlBuffer.append("            and wh.finisher_ind = 'N' \n");
        sqlBuffer.append("            and d.item_aggregate_ind = 'N'   \n");
        sqlBuffer.append("            and d.pack_ind = 'Y' \n");
        sqlBuffer.append("            and d.sellable_ind = 'N' \n");
        sqlBuffer.append(getBean().getWhereClause());
        sqlBuffer.append(whereClause.toString());
        if (isIncludeZeroAvail()) {
            sqlBuffer.append("\n");
        } else {
            sqlBuffer
                    .append("            and (GREATEST(il.stock_on_hand,0) - (il.tsf_reserved_qty +   \n");
            sqlBuffer.append("                                                 il.rtv_qty +   \n");
            sqlBuffer
                    .append("                                                 greatest(il.non_sellable_qty,0) + \n");
            sqlBuffer
                    .append("                                                 il.customer_resv +  \n");
            sqlBuffer
                    .append("                                                 il.customer_backorder \n");
            sqlBuffer.append("                                                ) \n");
            sqlBuffer.append("                ) > 0  \n");
        } 
        */
      /* SMR OLR v1.1 CR#103 Mod - Removed END */
        /* SMR OLR v1.1 CR#103 Mod - Inserted START */
        sqlBuffer.append("  -- Wh default section 1 \n");
        sqlBuffer.append("  SELECT");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_ONE));
        sqlBuffer.append("         distinct d.item,  \n");
        sqlBuffer.append("         d.item_desc,  \n");
        sqlBuffer.append("         il.loc loc,   \n");
        sqlBuffer.append("         null order_no,   \n");
        sqlBuffer.append("         0 avail_qty,  \n");
        sqlBuffer.append("         decode(d.item_parent, null,'T', '1') parent_code, \n");
        sqlBuffer.append("         d.pack_ind,  \n");
        sqlBuffer.append("         d.sellable_ind,  \n");
        sqlBuffer.append("         '" + Source.WAREHOUSE + "' source_type,  \n");
        sqlBuffer.append("         d.diff_1,  \n");
        sqlBuffer.append("         d.dept,  \n");
        sqlBuffer.append("         d.class,  \n");
        sqlBuffer.append("         d.subclass,  \n");
        sqlBuffer.append("         d.diff_2,  \n");
        sqlBuffer.append("         d.diff_3,  \n");
        sqlBuffer.append("         d.diff_4,  \n");
        sqlBuffer.append("         d.item_parent,  \n");
        sqlBuffer.append("         d.item_grandparent,  \n");
        sqlBuffer.append("         d.tran_level,  \n");
        sqlBuffer.append("         'N' " + NON_SELLABLE_FASHION_PACK + ", \n");
        sqlBuffer.append("         1 os_sps,  \n");

        sqlBuffer.append(AVAIL_QTY_ONEB + " curr_avail, \n");
 
        sqlBuffer.append("         isc.INNER_PACK_SIZE isc_ips, \n");
        sqlBuffer.append("         isc.supp_pack_size  isc_sps, \n");
        sqlBuffer.append("         isc.ti isc_ti, \n");
        sqlBuffer.append("         isc.hi isc_hi, \n");
        sqlBuffer.append("         null not_after_date, \n");
        sqlBuffer.append("         wh.break_pack_ind break_pack_ind  \n");
        sqlBuffer.append("    FROM item_master d, \n");
        sqlBuffer.append("         item_master im1, \n");
        sqlBuffer.append("         packitem_breakout pb,   \n");
        sqlBuffer.append("         item_loc_soh il,   \n");
        sqlBuffer.append("         smr_system_options sso, \n"); 
        sqlBuffer.append("         wh,   \n");
        sqlBuffer.append(getBean().getFromTables());
        sqlBuffer.append(fromTables);
        sqlBuffer.append("         item_supp_country isc   \n");

        sqlBuffer.append("          WHERE d.status = 'A'  \n");
        sqlBuffer.append("         and ( (d.PACK_TYPE = 'B' and sso.use_buyer_pack = 'Y' and pb.item = il.item)  \n"); 
        sqlBuffer.append("                or (d.pack_type != 'B' and  d.item = il.item )  \n"); 
        sqlBuffer.append("                  or ( sso.use_buyer_pack = 'N' and d.item = il.item) ) \n"); 
        sqlBuffer.append("            and d.item = isc.item(+)  \n");
        sqlBuffer.append("            and isc.primary_supp_ind(+) = 'Y' \n");
        sqlBuffer.append("            and isc.primary_country_ind(+) = 'Y' \n");
        sqlBuffer.append("            and d.item = pb.pack_no \n");
        sqlBuffer.append("            and pb.item = im1.item  \n");
        sqlBuffer.append("            and ((im1.tran_level = 1  \n");
        sqlBuffer.append("                  and im1.item_level = 1  \n");
        sqlBuffer.append("                  and im1.ITEM_AGGREGATE_IND = 'N') or \n");
        sqlBuffer.append("                 (im1.tran_level = 2 \n");
        sqlBuffer.append("                  and im1.item_parent in \n");
        sqlBuffer.append("                  (select item \n");
        sqlBuffer.append("                     from item_master \n");
        sqlBuffer.append("                    where ITEM_AGGREGATE_IND = 'N')) or \n");
        sqlBuffer.append("                 (im1.tran_level = 3 \n");
        sqlBuffer.append("                  and im1.item_grandparent in \n");
        sqlBuffer.append("                  (select item \n");
        sqlBuffer.append("                     from item_master \n");
        sqlBuffer.append("                    where ITEM_AGGREGATE_IND = 'N')) \n");
        sqlBuffer.append("                  )  \n");
        sqlBuffer.append("            and il.loc_type = 'W'  \n");
        sqlBuffer.append("            and wh.wh = il.loc  \n");
        sqlBuffer.append("            and wh.redist_wh_ind = 'N'  \n");
        sqlBuffer.append("            and wh.finisher_ind = 'N' \n");
        sqlBuffer.append("            and d.item_aggregate_ind = 'N'   \n");
        sqlBuffer.append("            and d.pack_ind = 'Y' \n");
        sqlBuffer.append("            and d.sellable_ind = 'N' \n");
        sqlBuffer.append(getBean().getWhereClause());
        sqlBuffer.append(whereClause.toString());
        if (isIncludeZeroAvail()) {
   //         sqlBuffer.append("\n");
        } else {
            sqlBuffer.append(" and case when d.PACK_TYPE = 'B' and sso.use_buyer_pack = 'Y' then \n");
            sqlBuffer.append("      ( select  min((stock_on_hand- (tsf_reserved_qty +    \n");
            sqlBuffer.append("                                    rtv_qty +                       \n");
            sqlBuffer.append("                                    greatest(non_sellable_qty,0) +    \n");
            sqlBuffer.append("                                    customer_resv +  pack_comp_resv +     \n");
            sqlBuffer.append("                                    customer_backorder  ))/ pb.pack_item_qty)      \n");
            sqlBuffer.append("          from item_loc_soh ils,         \n");
            sqlBuffer.append("               packitem_breakout pb     \n");
            sqlBuffer.append("        where ils.item = pb.item       \n");
            sqlBuffer.append("          and pb.pack_no = d.item     \n");
            sqlBuffer.append("          and loc = il.loc   )   \n");
            sqlBuffer.append("  else ");
            sqlBuffer.append("             (GREATEST(il.stock_on_hand,0) - (il.tsf_reserved_qty +   \n");
            sqlBuffer.append("                                                 il.rtv_qty +   \n");
            sqlBuffer.append("                                                 greatest(il.non_sellable_qty,0) + \n");
            sqlBuffer.append("                                                 il.customer_resv +  \n");
            sqlBuffer.append("                                                 il.customer_backorder \n");
            sqlBuffer.append("                                                ) \n");
            sqlBuffer.append("             ) \n");
            sqlBuffer.append("   end > 0 \n");        
        }
        sqlBuffer.append(" group by   d.item,  d.item_desc, d.PACK_TYPE , il.loc ,   decode(d.item_parent, null,'T', '1') ,  d.pack_ind,  \n");
        sqlBuffer.append("     d.sellable_ind,  d.diff_1,  d.dept,  d.class,  d.subclass,  d.diff_2,   d.diff_3,  \n");
        sqlBuffer.append("    d.diff_4,  d.item_parent,  d.item_grandparent,  d.tran_level,  isc.INNER_PACK_SIZE , \n");
        sqlBuffer.append("    isc.supp_pack_size  ,  isc.ti  , isc.hi  ,  wh.break_pack_ind  \n");
        /* SMR OLR v1.1 CR#103 Mod - Inserted END */   
        return true;
    }

    protected boolean sectionTwo(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer) {
        sqlBuffer.append("       -- Wh default section 2 \n");
        sqlBuffer.append("       SELECT");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_TWO));
        sqlBuffer.append("         distinct d.item, \n");
        sqlBuffer.append("         d.item_desc, \n");
        sqlBuffer.append("         il.loc loc,  \n");
        sqlBuffer.append("         null order_no,  \n");
        sqlBuffer.append("         0 avail_qty,  \n");
        sqlBuffer.append("         decode(d.item_parent, null,'T', '1') parent_code,\n");
        sqlBuffer.append("         d.pack_ind, \n");
        sqlBuffer.append("         d.sellable_ind, \n");
        sqlBuffer.append("         '" + Source.WAREHOUSE + "' source_type, \n");
        sqlBuffer.append("         d.diff_1, \n");
        sqlBuffer.append("         d.dept, \n");
        sqlBuffer.append("         d.class, \n");
        sqlBuffer.append("         d.subclass, \n");
        sqlBuffer.append("         d.diff_2, \n");
        sqlBuffer.append("         d.diff_3, \n");
        sqlBuffer.append("         d.diff_4, \n");
        sqlBuffer.append("         d.item_parent, \n");
        sqlBuffer.append("         d.item_grandparent, \n");
        sqlBuffer.append("         d.tran_level, \n");
        sqlBuffer.append("         'N' " + NON_SELLABLE_FASHION_PACK + ", \n");
        sqlBuffer.append("         1 os_sps,  \n");
        sqlBuffer.append(AVAIL_QTY_TWO + " curr_avail, \n");

        sqlBuffer.append("         isc.INNER_PACK_SIZE isc_ips, \n");
        sqlBuffer.append("         isc.supp_pack_size  isc_sps, \n");
        sqlBuffer.append("         isc.ti isc_ti, \n");
        sqlBuffer.append("         isc.hi isc_hi, \n");
        sqlBuffer.append("         null not_after_date, \n");
        sqlBuffer.append("         wh.break_pack_ind break_pack_ind  \n");
        sqlBuffer.append("    FROM item_master d,  \n");
        sqlBuffer.append("         item_loc_soh il,  \n");
        sqlBuffer.append("         wh,  \n");
        sqlBuffer.append(getBean().getFromTables());
        sqlBuffer.append(fromTables);
        sqlBuffer.append("         item_supp_country isc  \n");

        sqlBuffer.append("         WHERE d.item = il.item  \n");
        sqlBuffer.append("           and d.status = 'A' \n");
        sqlBuffer.append("           and d.item = isc.item(+) \n");
        sqlBuffer.append("           and isc.primary_supp_ind(+) = 'Y' \n");
        sqlBuffer.append("           and isc.primary_country_ind(+) = 'Y' \n");
        sqlBuffer.append("           and il.loc_type = 'W' \n");
        sqlBuffer.append("           and wh.wh = il.loc \n");
        sqlBuffer.append("           and wh.finisher_ind = 'N' \n");
        sqlBuffer.append("           and wh.redist_wh_ind = 'N' \n");
        sqlBuffer.append("           and d.item_aggregate_ind = 'N'  \n");
        sqlBuffer.append("           and d.item_level = d.tran_level  \n");
        sqlBuffer
                .append("           and (d.pack_ind = 'N' or (d.pack_ind = 'Y' and d.sellable_ind = 'Y')) \n");
        sqlBuffer.append(getBean().getWhereClause());
        sqlBuffer.append(whereClause.toString());
        if (isIncludeZeroAvail()) {
            sqlBuffer.append("\n");
        } else {
            sqlBuffer
                    .append("           and (GREATEST(il.stock_on_hand,0) - (il.tsf_reserved_qty +  \n");
            sqlBuffer.append("                                                il.rtv_qty +  \n");
            sqlBuffer
                    .append("                                                greatest(il.non_sellable_qty,0) + \n");
            sqlBuffer
                    .append("                                                il.customer_resv + \n");
            sqlBuffer
                    .append("                                                il.customer_backorder \n");
            sqlBuffer.append("                                               ) \n");
            sqlBuffer.append("               ) > 0 \n");
        }
        return true;
    }

    protected boolean sectionTwoA(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer) {
        return false;
    }

    protected boolean sectionThreeA(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer) {
        sqlBuffer.append(" -- Wh default section 3 A \n");
        sqlBuffer.append(" SELECT ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_THREE_A));
        sqlBuffer.append("         distinct im.item, \n");
        sqlBuffer.append("         im.item_desc, \n");
        sqlBuffer.append("         il.loc loc,  \n");
        sqlBuffer.append("         null order_no,  \n");
        sqlBuffer.append("         sum((GREATEST(il.stock_on_hand,0) -  \n");
        sqlBuffer.append("          (il.tsf_reserved_qty +  \n");
        sqlBuffer.append("           il.rtv_qty +  \n");
        sqlBuffer.append("           greatest(il.non_sellable_qty,0) + \n");
        sqlBuffer.append("           il.customer_resv + \n");
        sqlBuffer.append("           il.customer_backorder \n");
        sqlBuffer.append("          ) \n");
        sqlBuffer.append("         )) avail_qty, \n");
        sqlBuffer.append("         decode(d.item_parent, null,'T', '1') parent_code,\n");
        sqlBuffer.append("         d.pack_ind, \n");
        sqlBuffer.append("         d.sellable_ind, \n");
        sqlBuffer.append("         '" + Source.WAREHOUSE + "' source_type, \n");
        sqlBuffer.append("         im.diff_1, \n");
        sqlBuffer.append("         d.dept, \n");
        sqlBuffer.append("         d.class, \n");
        sqlBuffer.append("         d.subclass, \n");
        sqlBuffer.append("         im.diff_2, \n");
        sqlBuffer.append("         im.diff_3, \n");
        sqlBuffer.append("         im.diff_4, \n");
        sqlBuffer.append("         im.item_parent, \n");
        sqlBuffer.append("         im.item_grandparent, \n");
        sqlBuffer.append("         im.tran_level, \n");
        sqlBuffer.append("         'N' " + NON_SELLABLE_FASHION_PACK + ",\n");
        sqlBuffer.append("         1 os_sps,  \n");
        sqlBuffer.append(AVAIL_QTY_THREE_A + " curr_avail, \n");

        sqlBuffer.append("         isc.INNER_PACK_SIZE isc_ips, \n");
        sqlBuffer.append("         isc.supp_pack_size  isc_sps, \n");
        sqlBuffer.append("         isc.ti isc_ti, \n");
        sqlBuffer.append("         isc.hi isc_hi, \n");
        sqlBuffer.append("         null not_after_date, \n");
        sqlBuffer.append("         max(wh.break_pack_ind) break_pack_ind  \n");
        sqlBuffer.append("    FROM item_master d,  \n");
        sqlBuffer.append("         item_master im,  \n");
        sqlBuffer.append("         item_loc_soh il,  \n");
        sqlBuffer.append("         wh,  \n");
        sqlBuffer.append("         deps dp,   \n");
        sqlBuffer.append("         class cl,   \n");
        sqlBuffer.append("         subclass sb,   \n");
        sqlBuffer.append(getBean().getFromTables());
        sqlBuffer.append(fromTables);
        sqlBuffer.append(" item_supp_country isc \n");

        sqlBuffer.append("   WHERE im.item = il.item  \n");
        sqlBuffer.append("     and im.item_parent = d.item  \n");
        sqlBuffer.append("     and d.status = 'A' \n");
        sqlBuffer.append("     and il.loc_type = 'W' \n");
        sqlBuffer.append("     and wh.wh = il.loc \n");
        sqlBuffer.append("     and wh.redist_wh_ind = 'N' \n");
        sqlBuffer.append("     and wh.finisher_ind = 'N' \n");
        sqlBuffer.append("     and im.item_aggregate_ind = 'N'  \n");
        sqlBuffer.append("     and im.item_level = im.tran_level  \n");
        sqlBuffer.append("     and d.pack_ind = 'N'  \n");
        sqlBuffer.append("     and d.item = isc.item(+)  \n");
        sqlBuffer.append("     and d.dept = dp.dept  \n");
        sqlBuffer.append("     and d.dept = cl.dept  \n");
        sqlBuffer.append("     and d.class = cl.class  \n");
        sqlBuffer.append("     and d.dept = sb.dept  \n");
        sqlBuffer.append("     and d.class = sb.class  \n");
        sqlBuffer.append("     and d.subclass = sb.subclass  \n");
        sqlBuffer.append(getBean().getWhereClause());
        sqlBuffer.append(whereClause);
        if (isIncludeZeroAvail()) {
            sqlBuffer.append("\n");
        } else {
            sqlBuffer.append("     and (GREATEST(il.stock_on_hand,0) -  \n");
            sqlBuffer.append("          (il.tsf_reserved_qty +  \n");
            sqlBuffer.append("           il.rtv_qty +  \n");
            sqlBuffer.append("           greatest(il.non_sellable_qty,0) + \n");
            sqlBuffer.append("           il.customer_resv + \n");
            sqlBuffer.append("           il.customer_backorder \n");
            sqlBuffer.append("          ) \n");
            sqlBuffer.append("         ) > 0 \n");
        }
        sqlBuffer.append(" group by im.item,  \n");
        sqlBuffer.append("          im.item_desc, \n");
        sqlBuffer.append("          loc, \n");
        sqlBuffer.append("          decode(d.item_parent, null,'T', '1'),  \n");
        sqlBuffer.append("          d.pack_ind, \n");
        sqlBuffer.append("          d.sellable_ind, \n");
        sqlBuffer.append("             im.diff_1, \n");
        sqlBuffer.append("          d.dept, \n");
        sqlBuffer.append("          d.class,  \n");
        sqlBuffer.append("          d.subclass,  \n");
        sqlBuffer.append("          im.diff_2,  \n");
        sqlBuffer.append("          im.diff_3,  \n");
        sqlBuffer.append("          im.diff_4,  \n");
        sqlBuffer.append("          im.item_parent,  \n");
        sqlBuffer.append("          im.item_grandparent,  \n");
        sqlBuffer.append("          im.tran_level, \n");
        sqlBuffer.append("          isc.INNER_PACK_SIZE ,\n");
        sqlBuffer.append("          isc.supp_pack_size  ,\n");
        sqlBuffer.append("          isc.ti ,\n");
        sqlBuffer.append("          isc.hi \n");
        return true;
    }

    protected boolean sectionThree(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer) {
        String nsWhereWh = whereClause.toString();
        int fromIndex = 0;
        int stringIndex = 0;

        while ((stringIndex = nsWhereWh.indexOf("d.item", fromIndex)) >= 0) {
            nsWhereWh = nsWhereWh.substring(0, stringIndex - 1) + "pack"
                    + nsWhereWh.substring(stringIndex + 1);
        }

        sqlBuffer.append("   -- Wh default section 3 \n");
        sqlBuffer.append("   SELECT ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_THREE));
        sqlBuffer.append("         distinct pack.item, \n");
        sqlBuffer.append("         null item_desc, \n");
        sqlBuffer.append("         il.loc loc,  \n");
        sqlBuffer.append("         null order_no,  \n");
        sqlBuffer.append("         0 avail_qty,  \n");
        sqlBuffer.append("         max(decode(sku.item_parent, null,'T', '1')) parent_code,\n");
        sqlBuffer.append("         max(pack.pack_ind) pack_ind, \n");
        sqlBuffer.append("         max(pack.sellable_ind) sellable_ind, \n");
        sqlBuffer.append("         '" + Source.WAREHOUSE + "' source_type, \n");
        sqlBuffer.append("         max(sku.diff_1) diff_1, \n");
        sqlBuffer.append("         max(parent.dept) dept, \n");
        sqlBuffer.append("         max(parent.class) class, \n");
        sqlBuffer.append("         max(parent.subclass) subclass, \n");
        sqlBuffer.append("         max(sku.diff_2) diff_2, \n");
        sqlBuffer.append("         max(sku.diff_3) diff_3, \n");
        sqlBuffer.append("         max(sku.diff_4) diff_4, \n");
        sqlBuffer.append("         max(sku.item_parent) item_parent, \n");
        sqlBuffer.append("         max(sku.item_grandparent) item_grandparent, \n");
        sqlBuffer.append("         max(sku.tran_level) tran_level, \n");
        sqlBuffer.append("         'Y' " + NON_SELLABLE_FASHION_PACK + ", \n");
        sqlBuffer.append("         1 os_sps,  \n");
        sqlBuffer.append(AVAIL_QTY_THREE + " curr_avail, \n");

        sqlBuffer.append("         isc.INNER_PACK_SIZE isc_ips, \n");
        sqlBuffer.append("         isc.supp_pack_size  isc_sps, \n");
        sqlBuffer.append("         isc.ti isc_ti, \n");
        sqlBuffer.append("         isc.hi isc_hi, \n");
        sqlBuffer.append("         null not_after_date, \n");
        sqlBuffer.append("         max(wh.break_pack_ind)  break_pack_ind \n");
        sqlBuffer.append("    FROM item_master pack, \n");
        sqlBuffer.append("         item_master parent, \n");
        sqlBuffer.append("         item_master sku,  \n");
        sqlBuffer.append("         packitem_breakout pb, \n");
        sqlBuffer.append("         item_loc_soh il,  \n");
        sqlBuffer.append("         wh,  \n");
        sqlBuffer.append(getBean().getFromTables());
        sqlBuffer.append(fromTables);
        sqlBuffer.append("         item_supp_country isc  \n");

        sqlBuffer.append("           WHERE pb.pack_no = pack.item \n");
        sqlBuffer.append("                and pack.status = 'A' \n");
        sqlBuffer.append("             and pack.item = isc.item(+) \n");
        sqlBuffer.append("             and isc.primary_supp_ind(+) = 'Y' \n");
        sqlBuffer.append("             and isc.primary_country_ind(+) = 'Y' \n");
        sqlBuffer.append("             and pb.pack_no = il.item \n");
        sqlBuffer.append("             and pb.item = sku.item \n");
        sqlBuffer.append("             and pack.sellable_ind = 'N' \n");
        sqlBuffer.append("             and pack.pack_ind = 'Y' \n");
        sqlBuffer.append(getBean().getNonSellablePackWhereClause());
        sqlBuffer.append(nsWhereWh);
        sqlBuffer
                .append("             and ((sku.item_parent = parent.item and parent.item_aggregate_ind = 'Y') \n");
        sqlBuffer
                .append("                  or (sku.item_grandparent = parent.item and parent.item_aggregate_ind = 'Y')\n");
        sqlBuffer.append("                 )\n");
        sqlBuffer.append("             and (parent.diff_1_aggregate_ind = 'N' or           \n");
        sqlBuffer.append("                     (parent.diff_1_aggregate_ind = 'Y'        \n");
        sqlBuffer.append("                       and ((select count(distinct skus1.diff_1)  \n");
        sqlBuffer
                .append("                               from item_master skus1, packitem_breakout pb1\n");
        sqlBuffer.append("                              where skus1.item = pb1.item\n");
        sqlBuffer.append("                                and pb1.pack_no = pack.item) = 1) \n");
        sqlBuffer.append("                     )                                           \n");
        sqlBuffer.append("                 )                                            \n");
        sqlBuffer.append("             and (parent.diff_2_aggregate_ind = 'N' or     \n");
        sqlBuffer.append("                  (parent.diff_2_aggregate_ind = 'Y'           \n");
        sqlBuffer.append("                   and ((select count(distinct skus1.diff_2)  \n");
        sqlBuffer.append("                        from item_master skus1, packitem_breakout pb1\n");
        sqlBuffer.append("                       where skus1.item = pb1.item\n");
        sqlBuffer.append("                    and pb1.pack_no = pack.item) = 1) \n");
        sqlBuffer.append("           )\n");
        sqlBuffer.append("                 )\n");
        sqlBuffer.append("             and (parent.diff_3_aggregate_ind = 'N' or\n");
        sqlBuffer.append("                  (parent.diff_3_aggregate_ind = 'Y'\n");
        sqlBuffer.append("                   and ((select count(distinct skus1.diff_3)\n");
        sqlBuffer.append("                        from item_master skus1, packitem_breakout pb1\n");
        sqlBuffer.append("                       where skus1.item = pb1.item\n");
        sqlBuffer.append("                    and pb1.pack_no = pack.item) = 1) \n");
        sqlBuffer.append("             )\n");
        sqlBuffer.append("            )\n");
        sqlBuffer.append("             and (parent.diff_4_aggregate_ind = 'N' or\n");
        sqlBuffer.append("                  (parent.diff_4_aggregate_ind = 'Y'\n");
        sqlBuffer.append("                   and ((select count(distinct skus1.diff_4)\n");
        sqlBuffer.append("                        from item_master skus1, packitem_breakout pb1\n");
        sqlBuffer.append("                       where skus1.item = pb1.item\n");
        sqlBuffer.append("                    and pb1.pack_no = pack.item) = 1) \n");
        sqlBuffer.append("            )\n");
        sqlBuffer.append("                 )  \n");
        if (isIncludeZeroAvail()) {
            sqlBuffer.append("\n");
        } else {
            sqlBuffer.append("             and (GREATEST(il.stock_on_hand,0) - \n");
            sqlBuffer.append("                  (il.tsf_reserved_qty + \n");
            sqlBuffer.append("                   il.rtv_qty + \n");
            sqlBuffer.append("                   greatest(il.non_sellable_qty,0) +\n");
            sqlBuffer.append("                   il.customer_resv +\n");
            sqlBuffer.append("                   il.customer_backorder\n");
            sqlBuffer.append("                  )\n");
            sqlBuffer.append("                 ) > 0   \n");
        }
        sqlBuffer.append("        group by pack.item, il.loc,   \n");
        sqlBuffer.append("                 isc.INNER_PACK_SIZE, \n");
        sqlBuffer.append("                 isc.supp_pack_size, \n");
        sqlBuffer.append("                 isc.ti, \n");
        sqlBuffer.append("                 isc.hi    \n");
        return true;
    }

    protected boolean sectionFour(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer) {
        sqlBuffer.append("       -- Wh default section 4 \n");
        sqlBuffer.append("  SELECT \n");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_FOUR));
        sqlBuffer.append("         distinct p.item,\n");
        sqlBuffer.append("         p.item_desc,\n");
        sqlBuffer.append("         il.loc loc,\n");
        sqlBuffer.append("         null order_no,\n");
        sqlBuffer.append("         0 avail_qty,  \n");
        sqlBuffer.append("         '" + TRANSACTION + "' parent_code,\n");
        sqlBuffer.append("         p.pack_ind,\n");
        sqlBuffer.append("         p.sellable_ind,\n");
        sqlBuffer.append("         '" + Source.WAREHOUSE + "' source_type,\n");
        sqlBuffer.append("         p.diff_1,\n");
        sqlBuffer.append("         p.dept,\n");
        sqlBuffer.append("         p.class,\n");
        sqlBuffer.append("         p.subclass,\n");
        sqlBuffer.append("         p.diff_2,\n");
        sqlBuffer.append("         p.diff_3,\n");
        sqlBuffer.append("         p.diff_4,\n");
        sqlBuffer.append("         p.item_parent,\n");
        sqlBuffer.append("         p.item_grandparent,\n");
        sqlBuffer.append("         p.tran_level, \n");
        sqlBuffer.append("         'Y' " + NON_SELLABLE_FASHION_PACK + ", \n");
        sqlBuffer.append("         1 os_sps,  \n");
        sqlBuffer.append(AVAIL_QTY_FOUR + " curr_avail, \n");

        sqlBuffer.append("         isc.INNER_PACK_SIZE isc_ips,\n");
        sqlBuffer.append("         isc.supp_pack_size  isc_sps,\n");
        sqlBuffer.append("         isc.ti isc_ti,\n");
        sqlBuffer.append("         isc.hi isc_hi, \n");
        sqlBuffer.append("         null not_after_date, \n");
        sqlBuffer.append("         wh.break_pack_ind  break_pack_ind \n");
        sqlBuffer.append("    FROM item_master d,\n");
        sqlBuffer.append("         item_master p,\n");
        sqlBuffer.append("         packitem_breakout pb,\n");
        sqlBuffer.append("         deps dp,\n");
        sqlBuffer.append("         class cl,\n");
        sqlBuffer.append(getBean().getFromTables());
        sqlBuffer.append(fromTables);
        sqlBuffer.append("         subclass sb, \n");
        sqlBuffer.append("         item_loc_soh il,  \n");
        sqlBuffer.append("         wh,  \n");
        sqlBuffer.append("         item_supp_country isc  \n");
        sqlBuffer.append("   WHERE d.status = 'A'  \n");
        sqlBuffer.append("     and d.item_aggregate_ind = 'N'  \n");
        sqlBuffer.append("     and d.item_level = d.tran_level \n");
        sqlBuffer.append("     and d.pack_ind = 'N' \n");
        sqlBuffer.append("     and (p.pack_ind = 'Y' and p.sellable_ind = 'N')\n");
        sqlBuffer.append("     and d.item = pb.item \n");
        sqlBuffer.append("     and d.item = isc.item(+)  \n");
        sqlBuffer.append("     and isc.primary_supp_ind(+) = 'Y' \n");
        sqlBuffer.append("     and isc.primary_country_ind(+) = 'Y' \n");
        sqlBuffer.append("     and pb.pack_no = p.item \n");
        sqlBuffer.append("     and p.dept = dp.dept \n");
        sqlBuffer.append("     and p.dept = cl.dept \n");
        sqlBuffer.append("     and p.class = cl.class \n");
        sqlBuffer.append("     and p.dept = sb.dept \n");
        sqlBuffer.append("     and p.class = sb.class \n");
        sqlBuffer.append("     and p.subclass = sb.subclass \n");
        sqlBuffer.append("     and p.item = il.item  \n");
        sqlBuffer.append("     and il.loc_type = 'W' \n");
        sqlBuffer.append("     and wh.wh = il.loc \n");
        sqlBuffer.append("     and wh.redist_wh_ind = 'N' \n");
        if (isIncludeZeroAvail()) {
            sqlBuffer.append("\n");
        } else {
            sqlBuffer.append("     and (GREATEST(il.stock_on_hand,0) - (il.tsf_reserved_qty +  \n");
            sqlBuffer.append("                                          il.rtv_qty +  \n");
            sqlBuffer
                    .append("                                          greatest(il.non_sellable_qty,0) + \n");
            sqlBuffer.append("                                          il.customer_resv + \n");
            sqlBuffer.append("                                          il.customer_backorder \n");
            sqlBuffer.append("                                         ) \n");
            sqlBuffer.append("         ) > 0 \n");
        }
        sqlBuffer.append(getBean().getWhereClause());
        sqlBuffer.append(whereClause.toString());

        return true;
    }

    // protected boolean sectionLoad(StringBuffer whereClause, StringBuffer fromTables,
    // StringBuffer sqlBuffer)
    // {
    // sqlBuffer.append(" -- Wh default section load \n");
    // sqlBuffer.append("SELECT \n");
    // sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_FOUR));
    // sqlBuffer.append(" distinct d.item, \n");
    // sqlBuffer.append(" d.item_desc, \n");
    // sqlBuffer.append(" il.loc, \n");
    // sqlBuffer.append(" null, \n"); // order number
    // sqlBuffer.append(" 0, \n"); // avail qty
    // sqlBuffer.append(" decode(d.item_parent, null,'T', '1') parent_code, \n");
    // sqlBuffer.append(" d.pack_ind, \n");
    // sqlBuffer.append(" '" + Source.WAREHOUSE + "',\n"); // source_type WH
    // sqlBuffer.append(" d.diff_1, \n");
    // sqlBuffer.append(" d.dept, \n");
    // sqlBuffer.append(" d.class, \n");
    // sqlBuffer.append(" d.subclass, \n");
    // sqlBuffer.append(" d.diff_2 \n");
    // sqlBuffer.append(" d.diff_3, \n");
    // sqlBuffer.append(" d.diff_4 \n");
    // sqlBuffer.append(" d.item_parent, \n");
    // sqlBuffer.append(" d.item_grandparent, \n");
    // sqlBuffer.append(" d.tran_level, \n"); // tran_level
    // sqlBuffer.append(" 'N' " + NON_SELLABLE_FASHION_PACK + ", \n");
    // sqlBuffer.append(" 1 os_sps, \n");
    // sqlBuffer
    // .append(" alloc_wrapper_sql.GET_WH_CURRENT_AVAIL(d.item, 0, il.loc) curr_avail, \n");
    //
    // sqlBuffer.append(" isc.INNER_PACK_SIZE isc_ips, \n");
    // sqlBuffer.append(" isc.supp_pack_size isc_sps, \n");
    // sqlBuffer.append(" isc.ti isc_ti, \n");
    // sqlBuffer.append(" isc.hi isc_hi \n");
    //        
    // sqlBuffer.append(" FROM item_master d, \n");
    // sqlBuffer.append(" item_loc il, \n");
    // sqlBuffer.append(" item_supp_country isc, \n");
    // sqlBuffer.append(" diff_ids c1, \n");
    // sqlBuffer.append(" diff_ids c2, \n");
    // sqlBuffer.append(" --diff_ids c3, \n");
    // sqlBuffer.append(" deps dp, \n");
    // sqlBuffer.append(" class cl, \n");
    // sqlBuffer.append(" subclass sb, \n");
    // sqlBuffer.append(" alc_item_source ais \n");
    //        
    // sqlBuffer.append(" WHERE ais.alloc_id = 1004616 \n");
    // sqlBuffer.append(" and (d.item_parent = ais.item_id \n");
    // sqlBuffer.append(" or d.item_grandparent = ais.item_id) \n");
    // sqlBuffer.append(" -- and d.diff_1 = 'COLOR 23' \n");
    // sqlBuffer.append(" and d.diff_1 = c1.diff_id \n");
    // sqlBuffer.append(" -- and ais.diff1_id = d.diff_1 \n");
    // sqlBuffer.append(" -- and d.diff_2 = 'WFCOTTON' \n");
    // sqlBuffer.append(" and d.diff_2 = c2.diff_id \n");
    // sqlBuffer.append(" -- and d.diff_3 = '32I' \n");
    // sqlBuffer.append(" -- and d.diff_3 = c3.diff_id \n");
    // sqlBuffer.append(" and d.item_level = d.tran_level \n");
    // sqlBuffer.append(" and il.loc = ais.wh_id \n");
    // sqlBuffer.append(" and d.item = il.item \n");
    // sqlBuffer.append(" and d.item = isc.item \n");
    // sqlBuffer.append(" and isc.primary_supp_ind = 'Y' \n");
    // sqlBuffer.append(" and isc.primary_country_ind = 'Y' \n");
    // sqlBuffer.append(" and d.dept = dp.dept \n");
    // sqlBuffer.append(" and d.dept = cl.dept \n");
    // sqlBuffer.append(" and d.class = cl.class \n");
    // sqlBuffer.append(" and d.dept = sb.dept \n");
    // sqlBuffer.append(" and d.class = sb.class \n");
    // sqlBuffer.append(" and d.subclass = sb.subclass \n");
    // sqlBuffer.append("ORDER BY d.item }} \n");
    // return true;
    // }

    protected void bindVarForSections(PreparedStatement ps) throws SQLException {
        ps.setLong(++bindCount, this.allocId);
        bindCount = bean.bindWhereClause(ps, bindCount);
        bindVariables(ps);

        if (!isNonsellablePackOnly) {
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);

            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindNonSellablePackWhereClause(ps, bindCount);
            bindVariables(ps);
        }

        if (isItemList()) {
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);
        }

        if (isSku) {
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);
        }
    }

    protected void bindVariables(PreparedStatement ps) throws SQLException {
        if (this.poNo.length() > 0) {
            ps.setLong(++bindCount, Long.parseLong(this.poNo));

            if (whNo.length() > 0) {
                ps.setLong(++bindCount, Long.parseLong(this.poNo));
            }
        } else if (this.asnNo.length() > 0) {
            ps.setString(++bindCount, this.asnNo);

            if (whNo.length() > 0) {
                ps.setLong(++bindCount, Long.parseLong(this.whNo));
            }
        } else
        // both orderNo and asnNo are null
        {
            if (whNo.length() > 0) {
                ps.setLong(++bindCount, Long.parseLong(this.whNo));
            }
        }
        if (this.apptNo.length() > 0) {
            ps.setString(++bindCount, this.apptNo);
        }
    }
}