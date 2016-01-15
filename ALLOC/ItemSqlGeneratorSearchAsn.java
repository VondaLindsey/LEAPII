package com.retek.alloc.db.rms.v11.itemdao;

import java.io.Serializable;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.Map;

import com.retek.alloc.business.Source;
import com.retek.alloc.db.rms.v11.AItemDao;

public class ItemSqlGeneratorSearchAsn extends AItemSearchSqlGenerator implements Serializable
{
    private static final long serialVersionUID = 216971852279272569L;

    private int bindCount;

    public ItemSqlGeneratorSearchAsn(AItemDao bean, Map mapOfSqlIndexes)
    {
        super(bean, 99999, mapOfSqlIndexes);
    }

    public String buildSqlQuery()
    {
        // populate common buffers
        StringBuffer fromTables = populateFrom();
        StringBuffer whereClause = populateWhere();

        // construct the main section and it's sub-sections
        String sql = mainSectionBolAsn(whereClause, fromTables, "ASN");
        
        return sql;
    }

    protected StringBuffer populateWhere()
    {
        StringBuffer whereClause = new StringBuffer();

        if (this.asnNo.length() > 0)
        {
            whereClause.append("            and s.asn = ? \n");
        }
        else
        {
            whereClause.append("            and s.asn is not null \n");
        }

        whereClause.append("            and ol.location = wh.wh\n");
        whereClause.append("            and s.to_loc = wh.physical_wh\n");

        if (this.poNo != null && this.poNo.length() > 0)
        {
            whereClause.append("            and s.order_no = ? \n");
            whereClause.append("            and ol.order_no = ? \n");
            whereClause.append("            and os.order_no = ? \n");
            whereClause.append("            and o.order_no = ? \n");
        }
        else
        {
            whereClause.append("            and s.order_no = os.order_no\n");
            whereClause.append("            and ol.order_no = os.order_no\n");
            whereClause.append("            and o.order_no = os.order_no\n");
        }
        
 //      whereClause.append("            and ol.item = ss.item \n"); ANIL commented
        whereClause.append("            and s.shipment = ss.shipment\n"); 
        

        if (this.whNo.length() > 0)
        {
            whereClause.append("            and wh.wh= ? \n");
            whereClause.append("            and wh.finisher_ind='N' \n");
        }

        if (this.apptNo.length() > 0)
        {
            whereClause.append("            and ad.doc_type = 'P'\n");
            whereClause.append("            and ad.doc = os.order_no\n");
        }

        if (this.fromDate != null)
        {
            whereClause.append(" and s.ship_date >= ? \n");
        }

        if (this.toDate != null)
        {
        	whereClause.append(" and (s.receive_date is null or s.receive_date <= ?) \n");
        }
        return whereClause;
    }

    protected void bindVariables(PreparedStatement ps) throws SQLException
    {
        //StringBuffer whereClause = new StringBuffer();

        if (this.asnNo.length() > 0)
        {
            ps.setString(++bindCount, this.asnNo);
        }
        if (this.poNo != null && this.poNo.length() > 0)
        {
            ps.setString(++bindCount, this.poNo);
            ps.setString(++bindCount, this.poNo);
            ps.setString(++bindCount, this.poNo);
            ps.setString(++bindCount, this.poNo);
        }

        if (this.whNo.length() > 0)
        {
            ps.setString(++bindCount, this.whNo);
        }

        if (this.fromDate != null)
        {
            ps.setString(++bindCount, formatter.format(this.fromDate));
        }

        if (this.toDate != null)
        {
            ps.setString(++bindCount, formatter.format(this.toDate));
        }
    }

    protected void bindVarForSections(PreparedStatement ps) throws SQLException
    {
        ps.setLong(++bindCount, this.allocId);
        bindCount = bean.bindWhereClause(ps, bindCount);
        bindVariables(ps);

        if (!isNonsellablePackOnly)
        {
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);

// Anil P added this for extra query
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);
       
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);
   // End mod         
            if (isUdaAndDefaultLevelIsStyleColor())
            {
                ps.setLong(++bindCount, this.allocId);
                bindCount = bean.bindStyleWhereClause(ps, bindCount);
                bindVariables(ps);
            }

            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindNonSellablePackWhereClause(ps, bindCount);
            bindVariables(ps);
        }

        /*if (isItemList())
        {
            bindVariables(ps);
        }*/

        if (isSku)
        {
            ps.setLong(++bindCount, this.allocId);
            bindCount = bean.bindWhereClause(ps, bindCount);
            bindVariables(ps);
        }
    }

    protected StringBuffer populateFrom()
    {
        StringBuffer fromTables = new StringBuffer();

        fromTables.append("                item_supp_country isc, \n");
        fromTables.append("                shipment s,\n");
        fromTables.append("                shipsku ss,\n");

        if (this.apptNo.length() > 0)
        {
            fromTables.append("         appt_detail ad,\n");
        }

        fromTables.append("         wh,\n");
        fromTables.append("         ordloc ol, \n");
        fromTables.append("         ordsku os, \n");
        fromTables.append("         ordhead o \n");

        return fromTables;
    }

    protected boolean sectionFour(StringBuffer whereClausePo, StringBuffer fromTablesPo,
            StringBuffer sqlBuffer)
    {
        sqlBuffer.append("          -- ASN Section #4 \n");
        sqlBuffer.append("          SELECT ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_FOUR));
        sqlBuffer.append("                 distinct p.item,\n");
        sqlBuffer.append("                 p.item_desc,\n");
        sqlBuffer.append("                 ol.location loc,  \n");
        sqlBuffer.append("                 s.asn order_no,\n");
        sqlBuffer.append("                     ss.qty_expected - nvl(ss.qty_received,0) \n");
        sqlBuffer.append("                     - nvl((select sum(qty_allocated) \n");
        sqlBuffer
                .append("                            from alloc_header alh, alloc_detail ald, alc_xref alx \n");
        sqlBuffer.append("                            where alx.alloc_id != ?  \n");
        sqlBuffer.append("                              and alh.alloc_no = alx.xref_alloc_no \n");
        sqlBuffer.append("                              and ald.alloc_no=alh.alloc_no \n");
        sqlBuffer.append("                              and alh.item=p.item \n");
        sqlBuffer.append("                              and alh.doc_type='ASN' \n");
        sqlBuffer.append("                              and alh.doc=s.asn \n");
        sqlBuffer.append("                              and alh.wh=ol.location \n");
        sqlBuffer.append("                            group by alh.item,alh.doc),0) \n");
        sqlBuffer.append("                 avail_qty, \n");
        sqlBuffer.append("                 '" + TRANSACTION + "' parent_code,\n");
        sqlBuffer.append("                 p.pack_ind,\n");
        sqlBuffer.append("                 p.sellable_ind,\n");
        sqlBuffer.append("                 '" + Source.ASN + "' source_type,\n");
        sqlBuffer.append("                 p.diff_1,\n");
        sqlBuffer.append("                 p.dept,\n");
        sqlBuffer.append("                 p.class,\n");
        sqlBuffer.append("                 p.subclass,\n");
        sqlBuffer.append("                 p.diff_2,\n");
        sqlBuffer.append("                 p.diff_3,\n");
        sqlBuffer.append("                 p.diff_4,\n");
        sqlBuffer.append("                 p.item_parent,\n");
        sqlBuffer.append("                 p.item_grandparent,\n");
        sqlBuffer.append("                 p.tran_level,\n");
        sqlBuffer.append("                 'N' " + NON_SELLABLE_FASHION_PACK + ", \n");
        sqlBuffer.append("                 os.supp_pack_size os_sps,\n");
        sqlBuffer.append("                 0 curr_avail, \n");
        sqlBuffer.append("                 isc.inner_pack_size isc_ips,\n");
        sqlBuffer.append("                 isc.supp_pack_size isc_sps,\n");
        sqlBuffer.append("                 isc.ti isc_ti,\n");
        sqlBuffer.append("                 isc.hi isc_hi, \n");
        sqlBuffer.append("                 ol.qty_ordered qty_order, \n");
        sqlBuffer.append("                 wh.physical_wh pw, \n");
        sqlBuffer.append("                  wh.break_pack_ind break_pack_ind, \n");
        sqlBuffer.append("                 o.not_after_date not_after_date, \n");
        sqlBuffer.append("                 decode(o.order_no, null, 0, o.order_no) po_no \n");
        sqlBuffer.append("            FROM item_master d,\n");
        sqlBuffer.append("                 item_master p,\n");
        sqlBuffer.append("                 packitem_breakout pb,\n");
        sqlBuffer.append(bean.getFromTables());
        sqlBuffer.append(fromTablesPo);

        sqlBuffer.append("           WHERE d.item_aggregate_ind = 'N'  \n");
        sqlBuffer.append("              and d.item_level = d.tran_level \n");
        sqlBuffer.append("              and d.pack_ind = 'N' \n");
        sqlBuffer.append("              and (p.pack_ind = 'Y' and p.sellable_ind = 'N')\n");
        sqlBuffer.append("              and d.item = pb.item \n");
        sqlBuffer.append("              and pb.pack_no = p.item \n");
        sqlBuffer.append("              and pb.pack_no = ss.item \n");
        sqlBuffer.append("              and s.to_loc_type = 'W' \n");
        sqlBuffer.append("              and ss.item = p.item \n");
        //        sqlBuffer.append(" and (ss.qty_expected - nvl(ss.qty_received,0)) > 0 \n");
        sqlBuffer.append("              and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
        sqlBuffer.append("              and isc.item=os.item \n");
        sqlBuffer.append("              and isc.item=ol.item \n");
        sqlBuffer.append("              and isc.supplier = o.supplier \n");
        sqlBuffer.append(bean.getWhereClause());
        sqlBuffer.append(whereClausePo.toString());
        return true;
    }

    protected boolean sectionThree(StringBuffer whereClausePo, StringBuffer fromTablesPo,
            StringBuffer sqlBuffer)
    {
    	  // replace the shipsku join with a subquery to aggregate the cartons of a single item
        fromTablesPo = replaceShipSkuString(fromTablesPo);

    	sqlBuffer.append("       -- ASN Section #3 \n");
        sqlBuffer.append("          SELECT ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_THREE));
        sqlBuffer.append("                 distinct d.item, \n");
        sqlBuffer.append("                 null item_desc, \n");
        sqlBuffer.append("                 ol.location loc,  \n");
        sqlBuffer.append("                 s.asn order_no,  \n");
        sqlBuffer.append("                     ss.qty_expected - nvl(ss.qty_received,0) \n");
        sqlBuffer.append("                     - nvl((select sum(qty_allocated) \n");
        sqlBuffer
                .append("                            from alloc_header alh, alloc_detail ald, alc_xref alx \n");
        sqlBuffer.append("                            where alx.alloc_id != ?  \n");
        sqlBuffer.append("                              and alh.alloc_no = alx.xref_alloc_no \n");
        sqlBuffer.append("                              and ald.alloc_no=alh.alloc_no \n");
        sqlBuffer.append("                              and alh.item=d.item \n");
        sqlBuffer.append("                              and alh.doc_type='ASN' \n");
        sqlBuffer.append("                              and alh.doc=s.asn \n");
        sqlBuffer.append("                              and alh.wh=ol.location \n");
        sqlBuffer.append("                            group by alh.item,alh.doc),0) \n");
        sqlBuffer.append("                 avail_qty, \n");
        sqlBuffer
                .append("                 max(decode(sku.item_parent, null,'T', '1')) parent_code,\n");
        sqlBuffer.append("                 max(d.pack_ind) pack_ind, \n");
        sqlBuffer.append("                 max(d.sellable_ind) sellable_ind, \n");
        sqlBuffer.append("                 '" + Source.ASN + "' source_type, \n");
        sqlBuffer.append("                 max(sku.diff_1) diff_1, \n");
        sqlBuffer.append("                 max(parent.dept) dept, \n");
        sqlBuffer.append("                 max(parent.class) class, \n");
        sqlBuffer.append("                 max(parent.subclass) subclass, \n");
        sqlBuffer.append("                 max(sku.diff_2) diff_2, \n");
        sqlBuffer.append("                 max(sku.diff_3) diff_3, \n");
        sqlBuffer.append("                 max(sku.diff_4) diff_4, \n");
        sqlBuffer.append("                 max(sku.item_parent) item_parent, \n");
        sqlBuffer.append("                 max(sku.item_grandparent) item_grandparent, \n");
        sqlBuffer.append("                 max(sku.tran_level) tran_level,\n");
        sqlBuffer.append("                'Y' " + NON_SELLABLE_FASHION_PACK + ",\n");
        sqlBuffer.append("                os.supp_pack_size os_sps,\n");
        sqlBuffer.append("                 0 curr_avail, \n");

        sqlBuffer.append("                isc.inner_pack_size isc_ips,\n");
        sqlBuffer.append("                isc.supp_pack_size isc_sps,\n");
        sqlBuffer.append("                isc.ti isc_ti,\n");
        sqlBuffer.append("                isc.hi isc_hi, \n");
        sqlBuffer.append("                 ol.qty_ordered qty_order, \n");
        sqlBuffer.append("                 wh.physical_wh pw, \n");
        sqlBuffer.append("                 max(wh.break_pack_ind) break_pack_ind, \n");
        sqlBuffer.append("                 o.not_after_date not_after_date, \n");
        sqlBuffer.append("                 decode(o.order_no, null, 0, o.order_no) po_no \n");
        sqlBuffer.append("            FROM item_master d, --pack\n");
        sqlBuffer.append("                 item_master parent, \n");
        sqlBuffer.append("                 item_master sku,  \n");
        sqlBuffer.append("                 packitem_breakout pb, \n");
        sqlBuffer.append(bean.getFromTables());
        sqlBuffer.append(fromTablesPo);

        sqlBuffer.append("           WHERE pb.pack_no = d.item \n");
        sqlBuffer.append("             and ss.shipment = s.shipment \n");
        sqlBuffer.append("             and d.item = isc.item(+) \n");
        sqlBuffer.append("             and pb.pack_no = ss.item \n");
        sqlBuffer.append("             and pb.item = sku.item \n");
        sqlBuffer.append("             and d.sellable_ind = 'N' \n");
        sqlBuffer.append("             and d.pack_ind = 'Y' \n");
        sqlBuffer.append("             and pb.pack_no = ss.item  \n");
        sqlBuffer.append("             and s.to_loc_type = 'W' \n");
        sqlBuffer
                .append("             and ((sku.item_parent = parent.item and parent.item_aggregate_ind = 'Y') \n");
        sqlBuffer
                .append("              or (sku.item_grandparent = parent.item and parent.item_aggregate_ind = 'Y')\n");
        sqlBuffer.append("             )\n");
        //        sqlBuffer.append(" and (ss.qty_expected - nvl(ss.qty_received,0)) > 0 \n");
        sqlBuffer.append("              and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
        sqlBuffer.append("              and isc.item=os.item \n");
        sqlBuffer.append("              and isc.item=ol.item \n");
        sqlBuffer.append("              and isc.supplier = o.supplier \n");
        sqlBuffer.append(bean.getNonSellablePackWhereClause());
        sqlBuffer.append(whereClausePo);
        sqlBuffer.append("            and ol.item = ss.item \n");

        sqlBuffer.append("    GROUP BY d.item, \n");
        sqlBuffer.append("             ol.location,  \n");
        sqlBuffer.append("             s.asn,  \n");
        sqlBuffer.append("             ss.qty_expected - nvl(ss.qty_received,0),  \n");
        sqlBuffer.append("             os.supp_pack_size ,\n");
        sqlBuffer.append("             isc.inner_pack_size ,\n");
        sqlBuffer.append("             isc.supp_pack_size ,\n");
        sqlBuffer.append("             isc.ti ,\n");
        sqlBuffer.append("             isc.hi , \n");
        sqlBuffer.append("             ol.qty_ordered, \n");
        sqlBuffer.append("             wh.physical_wh, \n");
        sqlBuffer.append("             o.not_after_date,  \n");
        sqlBuffer.append("             o.order_no \n");
        return true;
    }

    protected boolean sectionTwoA(StringBuffer whereClausePo, StringBuffer fromTablesPo,
            StringBuffer sqlBuffer)
    {
    	 // replace the shipsku join with a subquery to aggregate the cartons of a single item
        fromTablesPo = replaceShipSkuString(fromTablesPo);
    	sqlBuffer.append("          -- ASN Section #2 A \n");
        sqlBuffer.append("          SELECT  \n");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_TWO_A));
        sqlBuffer.append("                 distinct d.item,\n");
        sqlBuffer.append("                 d.item_desc,\n");
        sqlBuffer.append("                 ol.location loc,\n");
        sqlBuffer.append("                 s.asn order_no,\n");
        sqlBuffer.append("                     ss.qty_expected - nvl(ss.qty_received,0) \n");
        sqlBuffer.append("                     - nvl((select sum(qty_allocated) \n");
        sqlBuffer
                .append("                            from alloc_header alh, alloc_detail ald, alc_xref alx \n");
        sqlBuffer.append("                            where alx.alloc_id != ?  \n");
        sqlBuffer.append("                              and alh.alloc_no = alx.xref_alloc_no \n");
        sqlBuffer.append("                              and ald.alloc_no=alh.alloc_no \n");
        sqlBuffer.append("                              and alh.item=d.item \n");
        sqlBuffer.append("                              and alh.doc_type='ASN' \n");
        sqlBuffer.append("                              and alh.doc=s.asn \n");
        sqlBuffer.append("                              and alh.wh=ol.location \n");
        sqlBuffer.append("                            group by alh.item,alh.doc),0) \n");
        sqlBuffer.append("                 avail_qty, \n");
        sqlBuffer.append("                 '" + STYLE_COLOR + "' parent_code,\n");
        sqlBuffer.append("                 d.pack_ind, \n");
        sqlBuffer.append("                 d.sellable_ind, \n");
        sqlBuffer.append("                 '" + Source.ASN + "' source_type,\n");
        sqlBuffer.append("                 d.diff_1 diff_1,\n");
        sqlBuffer.append("                 d.dept,\n");
        sqlBuffer.append("                 d.class,\n");
        sqlBuffer.append("                 d.subclass,\n");
        sqlBuffer.append("                 d.diff_2 diff_2,\n");
        sqlBuffer.append("                 d.diff_3 diff_3,\n");
        sqlBuffer.append("                 d.diff_4 diff_4,\n");
        sqlBuffer.append("                 d.item_parent item_parent,\n");
        sqlBuffer.append("                 d.item_grandparent item_grandparent,\n");
        sqlBuffer.append("                 d.tran_level tran_level,\n");
        sqlBuffer.append("                 'N' " + NON_SELLABLE_FASHION_PACK + ",\n");
        sqlBuffer.append("                 os.supp_pack_size os_sps,\n");
        sqlBuffer.append("                 0 curr_avail, \n");
        sqlBuffer.append("                 isc.inner_pack_size isc_ips,\n");
        sqlBuffer.append("                 isc.supp_pack_size isc_sps,\n");
        sqlBuffer.append("                 isc.ti isc_ti,\n");
        sqlBuffer.append("                 isc.hi isc_hi, \n");
        sqlBuffer.append("                 ol.qty_ordered qty_order, \n");
        sqlBuffer.append("                 wh.physical_wh pw, \n");
        sqlBuffer.append("                  wh.break_pack_ind break_pack_ind, \n");
        sqlBuffer.append("                 o.not_after_date not_after_date, \n");
        sqlBuffer.append("                 decode(o.order_no, null, 0, o.order_no) po_no \n");
        sqlBuffer.append("            FROM item_master d,\n");
        sqlBuffer.append("                 item_master parent, \n");
        sqlBuffer.append(bean.getFromTables());
        sqlBuffer.append(fromTablesPo);

//        sqlBuffer.append("           WHERE ss.item = d.item\n");
//        sqlBuffer.append("             and os.item = d.item\n");
//        sqlBuffer.append("             and ol.item = d.item \n");
      sqlBuffer.append("           WHERE ss.item = d.item\n");
        
        sqlBuffer.append("             and d.item_level = d.tran_level\n");
        sqlBuffer
                .append("              and ((d.pack_ind = 'Y' and d.sellable_ind = 'Y') or d.pack_ind = 'N')\n");
        sqlBuffer.append("             and s.to_loc_type = 'W'\n");
        sqlBuffer.append("             and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
        sqlBuffer.append("             and isc.item=ss.item \n");
        sqlBuffer.append("             and isc.supplier = o.supplier \n");
        sqlBuffer
                .append("              and ((d.item_parent = parent.item and parent.item_aggregate_ind = 'Y') \n");
        sqlBuffer
                .append("                 or (d.item_grandparent = parent.item and parent.item_aggregate_ind = 'Y')) \n");
        sqlBuffer.append(bean.getStyleWhereClause());
        sqlBuffer.append(whereClausePo);
        return true;
    }

    protected boolean sectionTwo(StringBuffer whereClausePo, StringBuffer fromTablesPo,
            StringBuffer sqlBuffer)
    {
    	   // replace the shipsku join with a subquery to aggregate the cartons of a single item
        fromTablesPo = replaceShipSkuString(fromTablesPo);
    	sqlBuffer.append("          -- ASN Section #2 \n");
        sqlBuffer.append("          SELECT ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_TWO));
        sqlBuffer.append("                 distinct d.item,\n");
        sqlBuffer.append("                 d.item_desc,\n");
        sqlBuffer.append("                 ol.location loc,\n");
        sqlBuffer.append("                 s.asn order_no,\n");
        sqlBuffer.append("                     ss.qty_expected - nvl(ss.qty_received,0) \n");
        sqlBuffer.append("                     - nvl((select sum(qty_allocated) \n");
        sqlBuffer
                .append("                            from alloc_header alh, alloc_detail ald, alc_xref alx \n");
        sqlBuffer.append("                            where alx.alloc_id != ?  \n");
        sqlBuffer.append("                              and alh.alloc_no = alx.xref_alloc_no \n");
        sqlBuffer.append("                              and ald.alloc_no=alh.alloc_no \n");
        sqlBuffer.append("                              and alh.item=d.item \n");
        sqlBuffer.append("                              and alh.doc_type='ASN' \n");
        sqlBuffer.append("                              and alh.doc=s.asn \n");
        sqlBuffer.append("                              and alh.wh=ol.location \n");
        sqlBuffer.append("                            group by alh.item,alh.doc),0) \n");
        sqlBuffer.append("                 avail_qty, \n");
        sqlBuffer.append("                 '" + STYLE_COLOR + "' parent_code,\n");
        sqlBuffer.append("                 d.pack_ind, \n");
        sqlBuffer.append("                 d.sellable_ind, \n");
        sqlBuffer.append("                 '" + Source.ASN + "' source_type,\n");
        sqlBuffer.append("                 d.diff_1 diff_1,\n");
        sqlBuffer.append("                 d.dept,\n");
        sqlBuffer.append("                 d.class,\n");
        sqlBuffer.append("                 d.subclass,\n");
        sqlBuffer.append("                 d.diff_2 diff_2,\n");
        sqlBuffer.append("                 d.diff_3 diff_3,\n");
        sqlBuffer.append("                 d.diff_4 diff_4,\n");
        sqlBuffer.append("                 d.item_parent item_parent,\n");
        sqlBuffer.append("                 d.item_grandparent item_grandparent,\n");
        sqlBuffer.append("                 d.tran_level tran_level,\n");
        sqlBuffer.append("                 'N' " + NON_SELLABLE_FASHION_PACK + ",\n");
        sqlBuffer.append("                 os.supp_pack_size os_sps,\n");
        sqlBuffer.append("                 0 curr_avail, \n");

        sqlBuffer.append("                 isc.inner_pack_size isc_ips,\n");
        sqlBuffer.append("                 isc.supp_pack_size isc_sps,\n");
        sqlBuffer.append("                 isc.ti isc_ti,\n");
        sqlBuffer.append("                 isc.hi isc_hi, \n");
        sqlBuffer.append("                 ol.qty_ordered qty_order, \n");
        sqlBuffer.append("                 wh.physical_wh pw, \n");
        sqlBuffer.append("                  wh.break_pack_ind break_pack_ind, \n");
        sqlBuffer.append("                 o.not_after_date not_after_date, \n");
        sqlBuffer.append("                 decode(o.order_no, null, 0, o.order_no) po_no \n"); 
        sqlBuffer.append("            FROM item_master d,\n");
//        sqlBuffer.append("            packitem_breakout pb, \n"); 
//         sqlBuffer.append("                       item_master d2, \n"); 
        sqlBuffer.append(bean.getFromTables());
        sqlBuffer.append(fromTablesPo);

//        sqlBuffer.append("           WHERE ss.item = d.item\n");
//        sqlBuffer.append("             and ss.shipment = s.shipment\n");
//        sqlBuffer.append("             and os.item=d.item \n");
//        sqlBuffer.append("             and ol.item=d.item \n");
        sqlBuffer.append("           WHERE ss.item = d.item\n");
        sqlBuffer.append("             and ss.shipment = s.shipment\n");
        
        sqlBuffer.append("             and d.item_level = d.tran_level\n");
        sqlBuffer
                .append("              and (d.pack_ind = 'N' or (d.pack_ind = 'Y' and d.sellable_ind = 'Y')) \n");
        sqlBuffer.append("             and s.to_loc_type = 'W'\n");
        sqlBuffer.append("             and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
        sqlBuffer.append("             and isc.item=ss.item \n");
        sqlBuffer.append("             and isc.supplier = o.supplier \n");
        sqlBuffer.append(bean.getWhereClause());
       sqlBuffer.append(whereClausePo);
       sqlBuffer.append("            and ol.item = ss.item \n");

        sqlBuffer.append(" UNION ALL " );
sqlBuffer.append (" select       item,\n" + 
"                 item_desc,\n" + 
"                   loc,\n" + 
"                   order_no,\n" + 
"                   SMR_ASN_AVAIL_BPACK_QTY ( shipment,  asn, alloc_id,\n" + 
"                                                      item,\n" + 
"                                                 loc)  avail_qty,\n" + 
"                   parent_code,\n" + 
"                 pack_ind, \n" + 
"                 sellable_ind, \n" + 
"                  source_type,\n" + 
"                   diff_1,\n" + 
"                  dept,\n" + 
"                  class,\n" + 
"                 subclass,\n" + 
"                   diff_2,\n" + 
"                 diff_3,\n" + 
"                 diff_4,\n" + 
"                 item_parent,\n" + 
"                 item_grandparent,\n" + 
"                 tran_level,\n" + 
"                  non_sellable_fashion_pack,\n" + 
"                  os_sps,\n" + 
"                  curr_avail, \n" + 
"                 isc_ips,\n" + 
"                 isc_sps,\n" + 
"                 isc_ti,\n" + 
"                 isc_hi, \n" + 
"                 qty_order, \n" + 
"                 pw, \n" + 
"                  break_pack_ind, \n" + 
"                 not_after_date, \n" + 
"                po_no \n" + 
"    from (  ") ;

 sqlBuffer.append("          SELECT ");
 sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_TWO));
 sqlBuffer.append("                 distinct  case when ol.item <> ss.item then \n" + 
 "                                       pb.pack_no \n" + 
 "                                  else d.item\n" + 
 "                                      end item,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                       d2.item_desc\n" + 
 "                    else d.item_desc\n" + 
 "                 end item_desc,\n");
 sqlBuffer.append("                 ol.location loc,\n");
sqlBuffer.append("                 s.asn ,\n");
        sqlBuffer.append("               to_char( ol.order_no) order_no,\n");
 sqlBuffer.append("                 ? alloc_id, \n");

 sqlBuffer.append("                 '" + STYLE_COLOR + "' parent_code,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.pack_ind \n" + 
 "                                  else d.pack_ind\n" + 
 "                                      end pack_ind, \n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.sellable_ind \n" + 
 "                                  else d.sellable_ind\n" + 
 "                                      end sellable_ind, \n");
 sqlBuffer.append("                 '" + Source.ASN + "' source_type,\n");
 sqlBuffer.append("                case when ol.item <> ss.item then \n" + 
 "                                       d2.diff_1 \n" + 
 "                                  else d.diff_1\n" + 
 "                                      end  diff_1,\n");
        sqlBuffer.append("                 s.shipment,\n");
 sqlBuffer.append("                 d.dept,\n");
 sqlBuffer.append("                 d.class,\n");
 sqlBuffer.append("                 d.subclass,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.diff_2 \n" + 
 "                                  else d.diff_2\n" + 
 "                                      end  diff_2,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.diff_3 \n" + 
 "                                  else d.diff_3\n" + 
 "                                      end  diff_3,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.diff_4 \n" + 
 "                                  else d.diff_4\n" + 
 "                                      end  diff_4,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.item_parent \n" + 
 "                                  else d.item_parent\n" + 
 "                                      end   item_parent,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.item_grandparent \n" + 
 "                                  else d.item_grandparent\n" + 
 "                                      end   item_grandparent,\n");
 sqlBuffer.append("                 case when ol.item <> ss.item then \n" + 
 "                                       d2.tran_level \n" + 
 "                                  else d.tran_level\n" + 
 "                                      end   tran_level,\n");
 sqlBuffer.append("                 'N' " + NON_SELLABLE_FASHION_PACK + ",\n");
 sqlBuffer.append("                 os.supp_pack_size os_sps,\n");
 sqlBuffer.append("                 0 curr_avail, \n");

 sqlBuffer.append("                 isc.inner_pack_size isc_ips,\n");
 sqlBuffer.append("                 isc.supp_pack_size isc_sps,\n");
 sqlBuffer.append("                 isc.ti isc_ti,\n");
 sqlBuffer.append("                 isc.hi isc_hi, \n");
 sqlBuffer.append("                 ol.qty_ordered qty_order, \n");
 sqlBuffer.append("                 wh.physical_wh pw, \n");
 sqlBuffer.append("                  wh.break_pack_ind break_pack_ind, \n");
 sqlBuffer.append("                 o.not_after_date not_after_date, \n");
 sqlBuffer.append("                 decode(o.order_no, null, 0, o.order_no) po_no \n"); 
 sqlBuffer.append("            FROM item_master d,\n");
 sqlBuffer.append("            packitem_breakout pb, \n"); 
  sqlBuffer.append("                       item_master d2, \n"); 
 sqlBuffer.append(bean.getFromTables());
 sqlBuffer.append(fromTablesPo);

 //        sqlBuffer.append("           WHERE ss.item = d.item\n");
 //        sqlBuffer.append("             and ss.shipment = s.shipment\n");
 //        sqlBuffer.append("             and os.item=d.item \n");
 //        sqlBuffer.append("             and ol.item=d.item \n");
 sqlBuffer.append("           WHERE ss.item = d.item\n");
 sqlBuffer.append("             and ss.shipment = s.shipment\n");
 
 sqlBuffer.append("             and d.item_level = d.tran_level\n");
 sqlBuffer
         .append("              and (d.pack_ind = 'N' or (d.pack_ind = 'Y' and d.sellable_ind = 'Y')) \n");
 sqlBuffer.append("             and s.to_loc_type = 'W'\n");
 sqlBuffer.append("             and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
 sqlBuffer.append("             and isc.item=ss.item \n");
 sqlBuffer.append("             and isc.supplier = o.supplier \n");


        sqlBuffer.append(bean.getWhereClause());
        sqlBuffer.append(whereClausePo);
        sqlBuffer.append("            and ol.item = pb.pack_no and ss.item = pb.item  \n");
        sqlBuffer.append("          and ol.item = pb.pack_no and ss.item = pb.item and d2.item = pb.pack_no \n");
       
        
//        sqlBuffer.append("            and (ol.item = ss.item or (ol.item = pb.pack_no and ss.item = pb.item )) \n");
//        sqlBuffer.append("          and ((ol.item = ss.item and d.item = d2.item ) or (ol.item = pb.pack_no and ss.item = pb.item and d2.item = pb.pack_no) ) \n");
        sqlBuffer.append("            and  ol.item = os.item  \n");
        sqlBuffer.append( "  )" );   
        
        sqlBuffer.append(" UNION ALL " );
        
        sqlBuffer.append ("    select     distinct  item,\n" + 
        "                 item_desc,\n" + 
        "                  loc,\n" + 
        "                   order_no,\n" + 
        "                  SMR_ASN_BAL_AVAIL_BPACK_QTY (asn,pack_no,item, to_loc,substr(min_max_pack,1, instr(min_max_pack, '~') -1)) avail_qty,\n" + 
        "                  parent_code,\n" + 
        "                  pack_ind, \n" + 
        "                  sellable_ind, \n" + 
        "                   source_type,\n" + 
        "                 diff_1,\n" + 
        "                 dept,\n" + 
        "                 class,\n" + 
        "                 subclass,\n" + 
        "                 diff_2,\n" + 
        "                 diff_3,\n" + 
        "                 diff_4,\n" + 
        "                 item_parent,\n" + 
        "                 item_grandparent,\n" + 
        "                 tran_level,\n" + 
        "                 non_sellable_fashion_pack,\n" + 
        "                  os_sps,\n" + 
        "                 curr_avail, \n" + 
        "                  isc_ips,\n" + 
        "                 isc_sps,\n" + 
        "                 isc_ti,\n" + 
        "                 isc_hi, \n" + 
        "                 qty_order, \n" + 
        "                  pw, \n" + 
        "                 break_pack_ind, \n" + 
        "                 not_after_date, \n" + 
        "                 po_no \n" + 
        "          from (\n" + 
        "select     distinct  item,\n" + 
        "                 item_desc,\n" + 
        "                  pack_no,\n" + 
        "                  to_loc,\n" + 
        "                    SMR_ASN_MIN_PACK_QTY(asn, pack_no, to_loc) min_max_pack,\n" + 
        "                   loc,\n" + 
        "                   asn,\n" + 
        "                   order_no,\n" + 
        "                  parent_code,\n" + 
        "                  pack_ind, \n" + 
        "                  sellable_ind, \n" + 
        "                   source_type,\n" + 
        "                 diff_1,\n" + 
        "                 dept,\n" + 
        "                 class,\n" + 
        "                 subclass,\n" + 
        "                 diff_2,\n" + 
        "                 diff_3,\n" + 
        "                 diff_4,\n" + 
        "                 item_parent,\n" + 
        "                 item_grandparent,\n" + 
        "                 tran_level,\n" + 
        "                 non_sellable_fashion_pack,\n" + 
        "                  os_sps,\n" + 
        "                 curr_avail, \n" + 
        "                  isc_ips,\n" + 
        "                 isc_sps,\n" + 
        "                 isc_ti,\n" + 
        "                 isc_hi, \n" + 
        "                 qty_order, \n" + 
        "                  pw, \n" + 
        "                 break_pack_ind, \n" + 
        "                 not_after_date, \n" + 
        "                 po_no \n" + 
        "          from ( ") ;
        
        sqlBuffer.append("          SELECT ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_TWO));
        sqlBuffer.append("                 distinct d.item,\n");
        sqlBuffer.append("                 d.item_desc,\n");
        sqlBuffer.append("                 ol.location loc,\n");
        sqlBuffer.append("                 s.asn ,\n");
        sqlBuffer.append("                 to_char(ol.order_no) order_no,\n");
        sqlBuffer.append("                 ? alloc_id, \n");
        sqlBuffer.append("                pb.pack_no,   ");
        sqlBuffer.append("                s.to_loc,  ");
        
        sqlBuffer.append("                 '" + STYLE_COLOR + "' parent_code,\n");
        sqlBuffer.append("                 d.pack_ind, \n");
        sqlBuffer.append("                 d.sellable_ind, \n");
        sqlBuffer.append("                 '" + Source.ASN + "' source_type,\n");
        sqlBuffer.append("                 d.diff_1 diff_1,\n");
        sqlBuffer.append("                 d.dept,\n");
        sqlBuffer.append("                 d.class,\n");
        sqlBuffer.append("                 d.subclass,\n");
        sqlBuffer.append("                 d.diff_2 diff_2,\n");
        sqlBuffer.append("                 d.diff_3 diff_3,\n");
        sqlBuffer.append("                 d.diff_4 diff_4,\n");
        sqlBuffer.append("                 d.item_parent item_parent,\n");
        sqlBuffer.append("                 d.item_grandparent item_grandparent,\n");
        sqlBuffer.append("                 d.tran_level tran_level,\n");
        sqlBuffer.append("                 'N' " + NON_SELLABLE_FASHION_PACK + ",\n");
        sqlBuffer.append("                 os.supp_pack_size os_sps,\n");
        sqlBuffer.append("                 0 curr_avail, \n");

        sqlBuffer.append("                 isc.inner_pack_size isc_ips,\n");
        sqlBuffer.append("                 isc.supp_pack_size isc_sps,\n");
        sqlBuffer.append("                 isc.ti isc_ti,\n");
        sqlBuffer.append("                 isc.hi isc_hi, \n");
        sqlBuffer.append("                 ol.qty_ordered qty_order, \n");
        sqlBuffer.append("                 wh.physical_wh pw, \n");
        sqlBuffer.append("                  wh.break_pack_ind break_pack_ind, \n");
        sqlBuffer.append("                 o.not_after_date not_after_date, \n");
        sqlBuffer.append("                 decode(o.order_no, null, 0, o.order_no) po_no \n"); 
        sqlBuffer.append("            FROM item_master d,\n");
        sqlBuffer.append("            packitem_breakout pb, \n"); 
//         sqlBuffer.append("                       item_master d2, \n"); 
        sqlBuffer.append(bean.getFromTables());
        sqlBuffer.append(fromTablesPo);

        //        sqlBuffer.append("           WHERE ss.item = d.item\n");
        //        sqlBuffer.append("             and ss.shipment = s.shipment\n");
        //        sqlBuffer.append("             and os.item=d.item \n");
        //        sqlBuffer.append("             and ol.item=d.item \n");
        sqlBuffer.append("           WHERE ss.item = d.item\n");
        sqlBuffer.append("             and ss.shipment = s.shipment\n");
        
        sqlBuffer.append("             and d.item_level = d.tran_level\n");
        sqlBuffer
                .append("              and (d.pack_ind = 'N' or (d.pack_ind = 'Y' and d.sellable_ind = 'Y')) \n");
        sqlBuffer.append("             and s.to_loc_type = 'W'\n");
        sqlBuffer.append("             and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
        sqlBuffer.append("             and isc.item=ss.item \n");
        sqlBuffer.append("             and isc.supplier = o.supplier \n");
        sqlBuffer.append(bean.getWhereClause());
        sqlBuffer.append(whereClausePo);
        sqlBuffer.append("             AND PB.PACK_NO = ol.item \n");
        sqlBuffer.append("             AND ss.item = pb.item \n");
       
        sqlBuffer.append("  )  ) where  substr(min_max_pack,1, instr(min_max_pack, '~') -1)  != substr(min_max_pack, instr(min_max_pack, '~') +1) ");
                    
        
        return true;
    }
    private void replaceString(StringBuffer buf, String targetString, String replacementString)
    {
        int startIndex = buf.indexOf(targetString);
        if (startIndex > -1)
        {
            int endIndex = startIndex + targetString.length();
            buf.replace(startIndex, endIndex, replacementString);
        }
    }

    private StringBuffer replaceShipSkuString(StringBuffer buf)
    {
        StringBuffer newBuffer = new StringBuffer(buf.toString());
        String shipSkuStagingSql =
            "(select distinct ss.shipment shipment, ss.item item , sum(ss.qty_expected) qty_expected, sum(ss.qty_received) qty_received\n" +
                    "             from shipsku ss, shipment s where ss.shipment = s.shipment and s.asn=<asn>\n" +
                    "             group by ss.shipment, ss.item, s.shipment, s.asn) ss";

        String shipSkuStagingSqlNoAsn =
            "(select distinct ss.shipment shipment, ss.item item , sum(ss.qty_expected) qty_expected, sum(ss.qty_received) qty_received\n" +
                    "             from shipsku ss, shipment s where ss.shipment = s.shipment \n" +
                    "             group by ss.shipment, ss.item, s.shipment, s.asn) ss";

        String targetString = "shipsku ss";

        if (this.asnNo == null || this.asnNo.length() == 0)
        {
            replaceString(newBuffer, targetString, shipSkuStagingSqlNoAsn);
        }
        else
        {
            replaceString(newBuffer, targetString, shipSkuStagingSql);
            replaceString(newBuffer, "<asn>", "'" + this.asnNo + "'");
        }
        return newBuffer;
    }

    protected boolean sectionOne(StringBuffer whereClausePo, StringBuffer fromTablesPo,
            StringBuffer sqlBuffer)
    {
    	  // replace the shipsku join with a subquery to aggregate the cartons of a single item
        fromTablesPo = replaceShipSkuString(fromTablesPo);
    	sqlBuffer.append("           -- ASN Section #1 \n");
        sqlBuffer.append("           SELECT  ");
        sqlBuffer.append(mapOfSqlIndexes.get(AItemSearchSqlGenerator.INDEX_ONE));
        sqlBuffer.append("                  distinct d.item,\n");
        sqlBuffer.append("                  d.item_desc,\n");
        sqlBuffer.append("                  ol.location loc,\n");
        sqlBuffer.append("                  s.asn order_no,\n");
        sqlBuffer.append("                     ss.qty_expected - nvl(ss.qty_received,0) \n");
        sqlBuffer.append("                     - nvl((select sum(qty_allocated) \n");
        sqlBuffer
                .append("                            from alloc_header alh, alloc_detail ald, alc_xref alx \n");
        sqlBuffer.append("                            where alx.alloc_id != ?  \n");
        sqlBuffer.append("                              and alh.alloc_no = alx.xref_alloc_no \n");
        sqlBuffer.append("                              and ald.alloc_no=alh.alloc_no \n");
        sqlBuffer.append("                              and alh.item=d.item \n");
        sqlBuffer.append("                              and alh.doc_type='ASN' \n");
        sqlBuffer.append("                              and alh.doc=s.asn \n");
        sqlBuffer.append("                              and alh.wh=ol.location \n");
        sqlBuffer.append("                            group by alh.item,alh.doc),0) \n");
        sqlBuffer.append("                  avail_qty, \n");
        sqlBuffer.append("                  '" + STYLE_COLOR + "' parent_code,\n");
        sqlBuffer.append("                  d.pack_ind, \n");
        sqlBuffer.append("                  d.sellable_ind, \n");
        sqlBuffer.append("                  '" + Source.ASN + "' source_type,\n");
        sqlBuffer.append("                  d.diff_1 diff_1,\n");
        sqlBuffer.append("                  d.dept,\n");
        sqlBuffer.append("                  d.class,\n");
        sqlBuffer.append("                  d.subclass,\n");
        sqlBuffer.append("                  d.diff_2 diff_2,\n");
        sqlBuffer.append("                  d.diff_3 diff_3,\n");
        sqlBuffer.append("                  d.diff_4 diff_4,\n");
        sqlBuffer.append("                  d.item_parent item_parent,\n");
        sqlBuffer.append("                  d.item_grandparent item_grandparent,\n");
        sqlBuffer.append("                  d.tran_level tran_level,\n");
        sqlBuffer.append("                  'N' " + NON_SELLABLE_FASHION_PACK + ",\n");
        sqlBuffer.append("                  os.supp_pack_size os_sps,\n");
        sqlBuffer.append("                  0 curr_avail, \n");
        sqlBuffer.append("                  isc.inner_pack_size isc_ips,\n");
        sqlBuffer.append("                  isc.supp_pack_size isc_sps,\n");
        sqlBuffer.append("                  isc.ti isc_ti,\n");
        sqlBuffer.append("                  isc.hi isc_hi, \n");
        sqlBuffer.append("                  ol.qty_ordered qty_order, \n");
        sqlBuffer.append("                  wh.physical_wh pw, \n");
        sqlBuffer.append("                  wh.break_pack_ind break_pack_ind, \n");
        sqlBuffer.append("                  o.not_after_date not_after_date, \n");
        sqlBuffer.append("                  decode(o.order_no, null, 0, o.order_no) po_no \n");
        sqlBuffer.append("             FROM item_master d,\n");
        sqlBuffer.append("                  item_master im1,\n");
        sqlBuffer.append("                  packitem_breakout pb,\n");
        sqlBuffer.append(bean.getFromTables());
        sqlBuffer.append(fromTablesPo);

        //        sqlBuffer.append(" WHERE ss.item = d.item\n");
        //        sqlBuffer.append(" and os.item = d.item\n");
        //        sqlBuffer.append(" and ol.item = d.item\n");
        sqlBuffer.append("            WHERE ss.item = d.item\n");
        
        
        sqlBuffer.append("              and d.item = pb.pack_no\n");
        sqlBuffer.append("              and pb.item = im1.item\n");
        sqlBuffer.append("              and ((im1.tran_level = 1 \n");
        sqlBuffer.append("                    and im1.item_level = 1 \n");
        sqlBuffer.append("                    and im1.ITEM_AGGREGATE_IND = 'N') or\n");
        sqlBuffer.append("                  (im1.tran_level = 2\n");
        sqlBuffer.append("                    and im1.item_parent in\n");
        sqlBuffer.append("                    (select item\n");
        sqlBuffer.append("                       from item_master\n");
        sqlBuffer.append("                      where ITEM_AGGREGATE_IND = 'N')) or\n");
        sqlBuffer.append("                  (im1.tran_level = 3\n");
        sqlBuffer.append("                    and im1.item_grandparent in\n");
        sqlBuffer.append("                    (select item\n");
        sqlBuffer.append("                       from item_master\n");
        sqlBuffer.append("                      where ITEM_AGGREGATE_IND = 'N')))\n");
        sqlBuffer.append("              and d.item_aggregate_ind = 'N'  \n");
        sqlBuffer.append("              and d.pack_ind = 'Y'\n");
        sqlBuffer.append("              and d.sellable_ind = 'N'\n");
        sqlBuffer.append("              and s.to_loc_type = 'W'\n");
        sqlBuffer.append("              and isc.ORIGIN_COUNTRY_ID=os.ORIGIN_COUNTRY_ID \n");
        sqlBuffer.append("              and isc.item=ss.item \n");
        sqlBuffer.append("              and isc.supplier = o.supplier \n");
        sqlBuffer.append("              and wh.wh = ol.location \n");
        if (this.itemlistId.length() > 0)
        {
            sqlBuffer.append("            and d.item = sl.item \n");
            //sqlBuffer.append("            and sl.skulist = " + this.itemlistId + "\n");
        }
        sqlBuffer.append(bean.getWhereClause());
        sqlBuffer.append(whereClausePo);
        sqlBuffer.append("            and ol.item = ss.item \n");
        return true;
    }

    protected boolean sectionThreeA(StringBuffer whereClause, StringBuffer fromTables,
            StringBuffer sqlBuffer)
    {
        return false;
    }

}