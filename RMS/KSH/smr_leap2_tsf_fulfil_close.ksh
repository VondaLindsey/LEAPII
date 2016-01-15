#!/bin/ksh
#
#################################################################################
# Modification History
# Rev. Date        Programmer    Description
# ==== =========== ============= =======================
# 1                Anil Potukuchi  
#################################################################################
typeset -r dbConnect="$MMUSER/$PASSWORD@$ORACLE_SID"


#-------------------------------------------------------------------------
# Function Name: CLOSE_TSF
# Purpose      : closes unfulfilled allocations
#-------------------------------------------------------------------------
function CLOSE_TSF
{
#   sqlTxt="
plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   whenever sqlerror exit 1 rollback
   set serveroutput on size 100000
   set feedback off
    VARIABLE outtext VARCHAR2(4000)
      DECLARE
         
             L_error_message      varchar2(255);
             L_tsf_no        tsfdetail.tsf_no%type := null;
             L_item          tsfdetail.item%type := null;
             L_qty_filled    tsfdetail.ship_qty%type;
             L_ship_qty      tsfdetail.ship_qty%type;
             L_qty_cancelled    tsfdetail.ship_qty%type;
             L_group_id          SMR_RMS_INT_QUEUE.group_id%type;
             L_prev_group_id     SMR_RMS_INT_QUEUE.group_id%type;
             
             L_shipping_shortage_ind    BOOLEAN;
            
              L_interface_error_id    VARCHAR2(50);
             cursor c_tsf is
           select   distinct  RECORD_ID, 
                              GROUP_ID, 
                              TRAN_DATE, 
                              FROM_LOC, 
                              FROM_LOC_TYPE, 
                              TO_LOC, 
                              TO_LOC_TYPE, 
                              TRAN_TYPE, 
                              ALLOC_NO, 
                              TSF_NO, 
                              ITEM, 
                              QTY_FULFILLED
             from SMR_RMS_INT_ALC_TSF_FULFIL_IMP
              where processed = 'N'
                and tsf_no is not null;
                
             cursor c_INTERFACE_ERROR_ID is
              select interface_id|| '_'||INTERFACE_NAME || '_' ||to_char(get_vdate, 'YYYYMMDD') || '_'  
                   from SMR_RMS_INT_TYPE
           where interface_name = 'WH_TSF';
           
           cursor c_tsf_dtl is
           select  tsf_qty - (ship_qty - received_qty),
                   tsf_qty - L_qty_filled
              from tsfdetail
             where tsf_no = L_tsf_no
               and item = L_item;
     
     BEGIN
     
         open c_INTERFACE_ERROR_ID;
       fetch c_INTERFACE_ERROR_ID into L_interface_error_id;
       close c_INTERFACE_ERROR_ID;
    
    
         for r1 in c_tsf loop
         DECLARE
         L_err_msg  varchar2(255);
     
         BEGIN
        
	      L_tsf_no     := r1.tsf_no; 
	      L_item       := r1.item;
	      L_qty_filled := r1.QTY_FULFILLED;
        
              open c_tsf_dtl;
             fetch c_tsf_dtl into L_ship_qty,
                                  L_qty_cancelled;
              close c_tsf_dtl;
              
              if L_qty_cancelled < 0 then
                 insert into SMR_RMS_INT_ERROR ( INTERFACE_ERROR_ID,
		                                            GROUP_ID,
		                                            RECORD_ID,
		                                            ERROR_MSG,
		                                            CREATE_DATETIME)
		                                   values ( L_interface_error_id || lpad(SMR_RMS_INT_ERROR_SEQ.nextval, 10, 0) ,
		                                            r1.group_id,
		                                            r1.record_id ,
		                                            'tsf ' || L_tsf_no || ' itm ' ||L_item || ' cancel more than ship ' || L_qty_cancelled ,
                                            sysdate);
              end if;
        
                    update tsfdetail
                       set tsf_qty = tsf_qty - (ship_qty - received_qty),
                           cancelled_qty = case when L_qty_cancelled < 0 then
                                                0
                                             else tsf_qty - r1.QTY_FULFILLED
                                           end
                     where tsf_no = r1.tsf_no
                       and item = r1.item;
                       
                  update item_loc_soh
                            set tsf_reserved_qty = case when (tsf_reserved_qty - r1.QTY_FULFILLED) < 0 then
                                                          0
                                                   else
                                                          (tsf_reserved_qty - r1.QTY_FULFILLED)
                                                   end
                          where item = r1.item
                            and loc = r1.From_loc;
                            
                     update item_loc_soh
                            set tsf_expected_qty = case when (tsf_expected_qty - r1.QTY_FULFILLED) < 0 then
                                                          0
                                                   else
                                                          (tsf_expected_qty - r1.QTY_FULFILLED)
                                                   end
                          where item = r1.item
                             and loc = r1.to_loc;
                             
                  update SMR_RMS_INT_ALC_TSF_FULFIL_IMP
                   set processed = 'Y',
                       PROCESSED_DATE = sysdate
                 where tsf_no = r1.tsf_no
                   and group_id = r1.group_id;   
                   
                   L_group_id := r1.group_id;
                 if L_prev_group_id is null then
                    L_prev_group_id := r1.group_id;
                 end if;
                 if L_prev_group_id <> r1.group_id  then
                     update SMR_RMS_INT_QUEUE
                     set status = 'C',
                        PROCESSED_DATETIME = sysdate
                   where group_id = L_prev_group_id
                     and interface_id in (    select interface_id
                                                from SMR_RMS_INT_TYPE
                                               where interface_name = 'WH_TSF' );
                      L_prev_group_id := r1.group_id;                         
                 end if;
            EXCEPTION
               when OTHERS then
                update SMR_RMS_INT_QUEUE
                     set status = 'E',
                        PROCESSED_DATETIME = sysdate
                   where group_id = r1.group_id 
                     and interface_id in (    select interface_id
                                                from SMR_RMS_INT_TYPE
                                               where interface_name = 'WH_TSF' );
                   
                   L_err_msg := substr(SQLERRM, 1,255);
                   
                     insert into SMR_RMS_INT_ERROR ( INTERFACE_ERROR_ID,
                                            GROUP_ID,
                                            RECORD_ID,
                                            ERROR_MSG,
                                            CREATE_DATETIME)
                                   values ( L_interface_error_id || lpad(SMR_RMS_INT_ERROR_SEQ.nextval, 10, 0) ,
                                            r1.group_id,
                                            r1.record_id ,
                                            L_err_msg,
                                            sysdate);
            
            END;
     
         end loop;
                           update SMR_RMS_INT_QUEUE
	                           set status = 'C',
	                              PROCESSED_DATETIME = sysdate
	                         where group_id = L_group_id 
	                           and interface_id in (    select interface_id
	                                                      from SMR_RMS_INT_TYPE
	                                                     where interface_name = 'WH_TSF' );

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
         echo "$logdate Program: ${0}: Error while running function CLOSE_TSF $plsql_result    ..." >> $MMHOME/error/$errfile
          return 1
        else
          return 0
        fi

}

#-----------------------------------------------
# Main program starts
# Parse the command line
#-----------------------------------------------

logdate=`date +"%a %h %d %T"`
logfile=`date +"%h_%d.log"`
errfile="err.smr_wh_receiving.`date +"%h_%d"`"


CLOSE_TSF

if [ $? -eq 0 ]
then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0} Function SEND_ALLOC_WA : Terminated Succesfully " >> $MMHOME/log/$logfile
   exit 0
else
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Function SEND_ALLOC_WA Terminated with errors " >> $MMHOME/log/$logfile
   exit 1
fi
