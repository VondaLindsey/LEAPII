#!/bin/ksh
#
#################################################################################
# Modification History
# Rev. Date        Programmer    Description
# ==== =========== ============= =======================
# 1                Anil Potukuchi  
#################################################################################

#############################################################################################
#VARIABLE DECLARATION
#############################################################################################
typeset -r dbConnect="$MMUSER/$PASSWORD@$ORACLE_SID"

error_ind=0
#-------------------------------------------------------------------------
# Function Name: SEND_ALLOC_WA
# Purpose      : sends Approved, Closed, Deleted Allocations to WA
#-------------------------------------------------------------------------
function SEND_ALLOC_WA
{

echo " Calling SEND ALLOC_WA"
   #sqlTxt="
plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   whenever sqlerror exit 1 rollback
   set serveroutput on size 100000
   set feedback off
    VARIABLE outtext VARCHAR2(4000)
      DECLARE
        cursor c_stg_alloc is
            select /*+ cardinality(ax 100) cardinality(ad 100) cardinality(ais 100) */ distinct  ax.wh_id wh,
           ax.xref_alloc_no alloc_no,
          stg.order_no,
            case when ais.source_type = 1 then
                  'P' 
                when ais.source_type = 2 then
                  'A'
                when ais.source_type = 3 then
                   'W'
           end source,
           ax.alloc_id,
           dv.division,
           d.dept,
           ad.to_loc store,
           case when st.default_wh is null then
                stg.wh
                else
                st.default_wh
            end store_wh,
           stg.create_datetime order_date,
           ad.in_store_date DATE_EXPECTED,
           ax.item_id item,
           ad.qty_allocated qty,
          'A' status,
           stg.create_datetime
      from alc_xref ax,
           alc_item_source ais,
           alloc_detail ad,
          SMR_RMS_INT_ALLOC_STG stg,
           item_master im,
           deps d,
           groups g,
           division dv,
           store st
     where ax.alloc_id = ais.alloc_id
       and ax.wh_id = stg.wh
       and ax.item_id = stg.item
       and ax.xref_alloc_no = stg.alloc_no
       and ad.alloc_no = stg.alloc_no
       and ais.item_id = stg.item
       and ax.item_id = im.item
       and im.dept = d.dept
       and d.group_no = g.group_no
       and g.division = dv.division
       and st.store = ad.to_loc 
   order by ax.xref_alloc_no;

    cursor c_guid is
          select   interface_id
               from SMR_RMS_INT_TYPE
       where interface_name = 'WH_ALLOC';
   
   L_alloc_id      alc_xref.alloc_id%type;
   L_interface_id  SMR_RMS_INT_TYPE.interface_id%type;     
   L_guid          varchar2(50);
   L_error_message varchar2(255);   
   L_record_id     number(10) := 0;
   guid_err   EXCEPTION;

      BEGIN

       for r1 in c_stg_alloc loop
           if L_alloc_id is null or L_alloc_id <> r1.alloc_id then
                open c_guid;
               fetch c_guid into  L_interface_id;
               close c_guid;
               if SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID ( L_error_message, L_interface_id, L_guid ) = FALSE then
	              RAISE guid_err;
               end if;
               L_alloc_id :=  r1.alloc_id;
                 insert into SMR_RMS_INT_QUEUE (INTERFACE_QUEUE_ID, 
                                         INTERFACE_ID, 
                                         GROUP_ID, 
                                         CREATE_DATETIME, 
                                         PROCESSED_DATETIME, 
                                         STATUS)
                                values   (SMR_RMS_INT_QUEUE_SEQ.nextval,
                                          L_interface_id,
                                          L_guid,
                                          sysdate,
                                          null,
                                          'N');             
            end if;
             L_record_id := L_record_id + 1;
          insert into SMR_RMS_INT_ALLOC_TSF_EXP    ( RECORD_ID,
                                      GROUP_ID,
                                      FROM_WH, 
                                      ALLOC_NO, 
                                      ORDER_NO, 
                                      SOURCE, 
                                      DIVISION, 
                                      DEPT, 
                                      TO_LOC, 
                                      STORE_WH, 
                                      DATE_EXPECTED, 
                                      ITEM, 
                                      QTY, 
                                      STATUS, 
                                      CREATE_DATETIME )
                             values ( L_record_id,
                                      L_guid,
                                      r1.WH, 
                                      r1.ALLOC_NO, 
                                      r1.ORDER_NO, 
                                      r1.SOURCE, 
                                      r1.DIVISION, 
                                      r1.DEPT, 
                                      r1.STORE, 
                                      r1.STORE_WH, 
                                      r1.DATE_EXPECTED, 
                                      r1.ITEM, 
                                      r1.QTY, 
                                      r1.STATUS, 
                                      r1.CREATE_DATETIME);
      end loop;
     delete from SMR_RMS_INT_ALLOC_STG;
         commit;
      EXCEPTION
       when OTHERS then
            L_error_message := SQLERRM || l_error_message  || TO_CHAR(SQLCODE);
            :outtext := L_error_message;
            rollback;
      END;
/
 print :outtext
  QUIT;
ENDSQL`

echo " Plsql result  ${plsql_result} "
       if [ `echo ${plsql_result} | grep "ORA-"  | wc -l` -gt 0 ] ;  then
         logdate=`date +"%a %h %d %T"`
         echo "$logdate Program: ${0}: Error while running function SEND_ALLOC_WA $plsql_result  $1  ..." >> $MMHOME/error/$errfile
          return 1
        else
          return 0
        fi

}

#-------------------------------------------------------------------------
# Function Name: SEND_TSF_WA
# Purpose      : sends Approved, Closed, Deleted TSF to WA
#-------------------------------------------------------------------------
function SEND_TSF_WA
{
plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   whenever sqlerror exit 1 rollback
   set serveroutput on size 100000
   set feedback off
    VARIABLE outtext VARCHAR2(4000)

      DECLARE
        cursor c_stg_tsf is
select distinct td.tsf_no,
           stg.FROM_LOC , 
           stg.TO_LOC TO_LOC, 
           stg.INVENTORY_TYPE INVENTORY_TYPE, 
           substr(stg.TSF_TYPE,1,2) TSF_TYPE,
           dv.division,
          d.dept,
          stg.DATE_EXPECTED,
           td.item,
           td.TSF_QTY qty,
          stg.status status,
          stg.create_datetime
     from TSFDETAIL td,
          item_master im,
          SMR_RMS_INT_TSF_STG stg,
          deps d,
          groups g,
          division dv
    where td.tsf_no = stg.tsf_no
      and td.item = im.item
       and im.dept = d.dept
      and d.group_no = g.group_no
      and g.division = dv.division;

    cursor c_guid is
          select    interface_id
               from SMR_RMS_INT_TYPE
       where interface_name = 'WH_TSF';
       
   L_tsf_no      tsfhead.tsf_no%type;
   L_interface_id  SMR_RMS_INT_TYPE.interface_id%type;     
   L_guid   varchar2(50);
   L_error_message varchar2(255);  
   L_record_id   number(10) := 0;
   guid_err   EXCEPTION;

      BEGIN


      for r1 in c_stg_tsf loop
     
         if L_tsf_no is null or L_tsf_no <> r1.TSF_NO then
                     open c_guid;
                    fetch c_guid into   L_interface_id;
                    close c_guid;
              
                    if SMR_LEAP_INTERFACE_SQL.GENERATE_GROUP_ID ( L_error_message, L_interface_id, L_guid ) = FALSE then
	              RAISE guid_err;
                    end if;
                    
                    L_tsf_no :=  r1.TSF_NO;
                      insert into SMR_RMS_INT_QUEUE (INTERFACE_QUEUE_ID, 
                                              INTERFACE_ID, 
                                              GROUP_ID, 
                                              CREATE_DATETIME, 
                                              PROCESSED_DATETIME, 
                                              STATUS)
                                     values   (SMR_RMS_INT_QUEUE_SEQ.nextval,
                                               L_interface_id,
                                               L_guid,
                                               sysdate,
                                               null,
                                               'N');             
                 end if;
             L_record_id := L_record_id + 1;
      
          insert into SMR_RMS_INT_ALLOC_TSF_EXP    ( RECORD_ID,
                                      GROUP_ID,
                                      FROM_WH, 
                                      TSF_NO, 
                                      TSF_TYPE, 
                                      INVENTORY_TYPE, 
                                      DIVISION, 
                                      DEPT, 
                                      TO_LOC, 
                                      DATE_EXPECTED, 
                                      ITEM, 
                                      QTY, 
                                      STATUS, 
                                      CREATE_DATETIME )
                             values ( L_record_id,
                                      L_guid,
                                      r1.from_loc, 
                                      r1.tsf_no, 
                                      r1.tsf_type, 
                                      r1.inventory_type, 
                                      r1.DIVISION, 
                                      r1.DEPT, 
                                      r1.to_loc, 
                                      r1.DATE_EXPECTED, 
                                      r1.ITEM, 
                                      r1.QTY, 
                                      r1.STATUS, 
                                      r1.create_datetime);
                                      
      end loop;

     delete from SMR_RMS_INT_TSF_STG;
         commit;
      EXCEPTION
       when OTHERS then
            L_error_message := SQLERRM || l_error_message  || TO_CHAR(SQLCODE);
            :outtext := L_error_message;
            rollback;
      END;
/
 print :outtext
  QUIT;
ENDSQL`

        echo " Plsql result  ${plsql_result} "
       if [ `echo ${plsql_result} | grep "ORA-"  | wc -l` -gt 0 ] ;  then
         logdate=`date +"%a %h %d %T"`
         echo "$logdate Program: ${0}: Error while running function SEND_TSF_WA $plsql_result  $1  ..." >> $MMHOME/error/$errfile
          return 1
        else
          return 0
        fi

}

#-----------------------------------------------
# Main program starts
# Parse the command line
#-----------------------------------------------
#if [ $# -ne 1 ] ; then
#   echo "Usage: <connect>"
#   exit 1
#fi

logdate=`date +"%a %h %d %T"`
logfile=`date +"%h_%d.log"`
errfile="err.smr_wh_receiving.`date +"%h_%d"`"


SEND_ALLOC_WA

if [ $? -eq 0 ]
then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0} Function SEND_ALLOC_WA : Terminated Succesfully " >> $MMHOME/log/$logfile
else
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Function SEND_ALLOC_WA Terminated with errors " >> $MMHOME/log/$logfile
   error_ind=1
fi


SEND_TSF_WA

if [ $? -eq 0 ]
then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0} Function SEND_TSF_WA : Terminated Succesfully " >> $MMHOME/log/$logfile
else
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Function SEND_TSF_WA Terminated with errors " >> $MMHOME/log/$logfile
   error_ind=2
fi


if [[ $error_ind -ne 0  ]]; then
   exit 1
else 
   exit 0
fi
