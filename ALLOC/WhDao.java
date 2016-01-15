package com.retek.alloc.db.rms.v11;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;

import com.retek.alloc.business.Warehouse;
import com.retek.alloc.utils.AllocException;
import com.retek.alloc.utils.ConnectionPool;
import com.retek.alloc.utils.Severity;
import com.retek.alloc.utils.Utility;
import com.retek.alloc.utils.AllocLogger;

public class WhDao extends AWhDao
{
    public static final String TABLE_NAME = "WH";
    private int whCount = 0;

    public Warehouse[] select(boolean isSecondary) throws AllocException, SQLException
    {
    	ResultSet resultSet = null;
        ArrayList dataList;
        String descSecondary = "";
        StringBuffer sql = new StringBuffer(10);
        PreparedStatement pStmt = null;
        int argNum = 0;
        try
        {

	        if (isSecondary)
	        {
	        	sql.append("SELECT wh, wh_name \n" + "  FROM wh, smr_system_options \n"
                        + " WHERE redist_wh_ind = 'N' \n" + " AND finisher_ind = 'N' " +
                        "and (ALLOW_XDOCK_ALLOC = 'Y' and wh not in (select wh from wh_attributes where wh_type_code = 'XD') \n" + 
                        "          or (ALLOW_XDOCK_ALLOC = 'N' and 1 = 1 )  )\n"
                        + " AND wh <> physical_wh");

                if (id.length() > 0)
                {
                    sql.append(" and wh = ? \n");
                }
                else if (desc.length() > 0)
                {
                    sql.append(" and upper(wh_name) like upper(?) \n");
                }

                sql.append(" ORDER BY wh_name, wh");

                pStmt = this.conn.prepareStatement(sql.toString());

                if (id.length() > 0)
                {
                    pStmt.setString(++argNum, id);
                }
                else if (desc.length() > 0)
                {
                    pStmt.setString(++argNum, Utility.handlePSLikeString(desc));
                }

                resultSet = pStmt.executeQuery();
                dataList = new ArrayList(1);

                while (resultSet.next())
                {
                    descSecondary = "";
                    dataList.add(new Warehouse(resultSet.getString(1), resultSet.getString(2),
                            descSecondary));
                }

                if (dataList.isEmpty()) // Nothing found.
                {
                    throw new AllocException("52099", AllocLogger.ERROR);
                }
            }
            else
            {
                sql.append("SELECT wh, wh_name \n " + "  FROM wh, smr_system_options \n ");
                sql.append(" WHERE redist_wh_ind = 'N' \n" + " AND finisher_ind = 'N'\n" +
                "and (ALLOW_XDOCK_ALLOC = 'Y' and wh not in (select wh from wh_attributes where wh_type_code = 'XD') \n" + 
                "          or (ALLOW_XDOCK_ALLOC = 'N' and 1 = 1 )  )\n");
                sql.append(" AND wh <> physical_wh");

                if (id.length() > 0)
                {
                    sql.append(" and wh = ? \n");
                }
                else if (desc.length() > 0)
                {
                    sql.append(" and upper(wh_name) like upper(?) \n");
                }

                sql.append(" ORDER BY wh_name, wh");

                pStmt = this.conn.prepareStatement(sql.toString());

                if (id.length() > 0)
                {
                    pStmt.setString(++argNum, id);
                }
                else if (desc.length() > 0)
                {
                    pStmt.setString(++argNum, Utility.handlePSLikeString(desc));
                }
                resultSet = pStmt.executeQuery();
                dataList = new ArrayList(1);

                while (resultSet.next())
                {
                    dataList.add(new Warehouse(resultSet.getString(1), resultSet.getString(2)));
                }

                if (dataList.isEmpty()) // Nothing found.
                {
                    throw new AllocException("52099", AllocLogger.ERROR);
                }
            }
            whCount = dataList.size();
            Warehouse data[] = new Warehouse[whCount];
            dataList.toArray(data);
            return data;
        }
        finally
        {
            if (resultSet != null)
            {
                resultSet.close();
            }
            if (pStmt != null)
            {
                pStmt.close();
            }
        }
    }

    public Warehouse read() throws SQLException
    {
        Warehouse warehouse = null;
        PreparedStatement pStmt = null;
        ResultSet resultSet = null;

        String sql = "SELECT wh, wh_name, inbound_handling_days, channel_id \n "
                + "  FROM wh \n where wh = ?";

        try
        {
        	pStmt = conn.prepareStatement(sql);
            pStmt.setString(1, this.id);

            resultSet = pStmt.executeQuery();

            while (resultSet.next())
            {
            	warehouse = new Warehouse(resultSet.getString(1), resultSet.getString(2));
                warehouse.setInboundHandlingDays(resultSet.getInt(3));
                warehouse.setChannelId(resultSet.getInt(4));

                return warehouse;
            }
        }
        finally
        {
            if (resultSet != null)
            {
                resultSet.close();
            }

            if (pStmt != null)
            {
                pStmt.close();
            }
        }


        return warehouse;
    }
    
    public boolean getWhBreakPackInd(String whNo) throws AllocException
    {
       PreparedStatement pstmt2 = null;
       boolean retVal = false;
       ResultSet rSet = null;
       String sql1 = "SELECT break_pack_ind \n "
           + "  FROM wh \n where wh = ?";
       try
       {
           if (conn == null) {
               throw new AllocException("51205", Severity.ERROR);
           }
           pstmt2 = conn.prepareStatement(sql1);
           pstmt2.setString(1, whNo);

           rSet = pstmt2.executeQuery();
           String breakPackInd = null;
           if (rSet.next()) {
               breakPackInd = rSet.getString(1);
           }
           if (breakPackInd != null) {
               retVal = "Y".equals(breakPackInd.trim());
           }
       } catch (SQLException sqe) {
           throw new AllocException("51205", sqe);
        
       }
       finally
       {
            try
            {
                if (rSet != null)
                {
                    rSet.close();
                }
                if (pstmt2 != null)
                {
                    pstmt2.close();
                }
            }
            catch (SQLException sqe)
            {
                throw new AllocException("51205", sqe);
            }
        }
       return retVal;
    }
    
}