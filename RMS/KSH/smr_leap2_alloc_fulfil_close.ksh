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
# Function Name: CLOSE_ALLOC
# Purpose      : closes unfulfilled allocations
#-------------------------------------------------------------------------
function CLOSE_ALLOC
{
#   sqlTxt="
plsql_result=`sqlplus -s $dbConnect <<-ENDSQL
   whenever sqlerror exit 1 rollback
   set serveroutput on size 100000
   set feedback off
    VARIABLE outtext VARCHAR2(4000)
      DECLARE
        
         L_alloc_no          alloc_header.alloc_no%type;
         L_item              item_master.item%type;
         L_to_loc            item_loc_soh.loc%type;
         L_qty_cancelled     alloc_detail.QTY_CANCELLED%type;
         L_qty_filled        alloc_detail.QTY_CANCELLED%type;
	 L_QTY_TRANSFERRED   alloc_detail.QTY_TRANSFERRED%type;
	 L_group_id          SMR_RMS_INT_QUEUE.group_id%type;
	 L_prev_group_id     SMR_RMS_INT_QUEUE.group_id%type;


         L_wh                item_loc_soh.loc%type;
         L_in_transit_qty    item_loc_soh.in_transit_qty%type;
         L_interface_error_id    VARCHAR2(50);
         
      
         TYPE alloc_no_tab is TABLE OF alloc_header.alloc_no%type;
         t_alloc_no           alloc_no_tab := alloc_no_tab();
          TYPE group_id_tab is TABLE OF SMR_RMS_INT_QUEUE.group_id%type;
         t_group_id          group_id_tab := group_id_tab();
         L_prev_alloc_no      alloc_header.alloc_no%type := null;
         L_error_message      varchar2(255);
          pkg_err EXCEPTION;
      
         cursor c_alloc_head is
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
                   and alloc_no is not null;
      
      
  cursor c_upd_alloc_dtl is
       select ah.alloc_no,
              ah.item,  NVL(ad.qty_transferred, 0),nvl(ad.qty_allocated, 0) ,
              GREATEST(NVL(ad.qty_transferred, 0),NVL(ad.qty_received,0)) - NVL(ad.qty_allocated, 0) upd_qty,
              'W' from_loc_type,
              ah.wh from_loc,
              ad.to_loc_type to_loc_type,
              ad.to_loc to_loc
         from alloc_header ah,
              alloc_detail ad
        where ah.alloc_no = L_alloc_no
          and ah.alloc_no = ad.alloc_no
          and ad.to_loc = L_to_loc
          and NVL(ad.qty_transferred, 0) < nvl(ad.qty_allocated, 0)
         and ah.order_no is NULL;

             cursor c_INTERFACE_ERROR_ID is
              select interface_id|| '_'||INTERFACE_NAME || '_' ||to_char(get_vdate, 'YYYYMMDD') || '_'  
                   from SMR_RMS_INT_TYPE
           where interface_name = 'WH_ALLOC';
           
            cursor c_alloc_dtl is
           select  QTY_TRANSFERRED - (QTY_TRANSFERRED - QTY_RECEIVED),
                   QTY_TRANSFERRED - L_qty_filled
              from alloc_detail
             where alloc_no = L_alloc_no
               and to_loc = L_to_loc;    
 
 BEGIN
 
         open c_INTERFACE_ERROR_ID;
        fetch c_INTERFACE_ERROR_ID into L_interface_error_id;
        close c_INTERFACE_ERROR_ID;


     for r1 in c_alloc_head loop
     
              DECLARE
              L_err_msg  varchar2(255);
          
              BEGIN

 
      L_alloc_no := r1.alloc_no;
      L_to_loc   := r1.to_loc;
      L_item     := r1.item;
      L_qty_filled := r1.QTY_FULFILLED;
 
               open c_alloc_dtl;
              fetch c_alloc_dtl into L_QTY_TRANSFERRED,
                                   L_qty_cancelled;
              close c_alloc_dtl;
              
               if L_qty_cancelled < 0 then
	                       insert into SMR_RMS_INT_ERROR ( INTERFACE_ERROR_ID,
	      		                                            GROUP_ID,
	      		                                            RECORD_ID,
	      		                                            ERROR_MSG,
	      		                                            CREATE_DATETIME)
	      		                                   values ( L_interface_error_id || lpad(SMR_RMS_INT_ERROR_SEQ.nextval, 10, 0) ,
	      		                                            r1.group_id,
	      		                                            r1.record_id ,
	      		                                            'alloc ' || L_alloc_no || ' itm ' ||L_item || ' to_loc ' || L_to_loc || ' cancel more than allocate ' || L_qty_cancelled ,
	                                                  sysdate);
              end if;
 
      --   for r2 in c_upd_alloc_dtl loop
 
           update alloc_detail
              set qty_allocated = qty_allocated - (QTY_TRANSFERRED - QTY_RECEIVED),
                  qty_cancelled =  case when L_qty_cancelled < 0 then
                                                0
                                             else qty_allocated - r1.QTY_FULFILLED
                                      end
--                  qty_distro = r2.upd_qty
            where alloc_no = L_alloc_no
              and to_loc = L_to_loc;
              
     --    end loop;
 
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
              where alloc_no = r1.alloc_no
                and item = r1.item
                and group_id = r1.group_id
                and from_loc = r1.from_loc
                and to_loc =  r1.to_loc ;
                  
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
                                                   where interface_name = 'WH_ALLOC' );
                         L_prev_group_id := r1.group_id;                         
                  end if;

       EXCEPTION
          when pkg_err then 
             raise;
           when OTHERS then
                 update SMR_RMS_INT_QUEUE
                    set status = 'E',
                        PROCESSED_DATETIME = sysdate
                  where group_id = r1.group_id 
                   and interface_id in (    select interface_id
                                                from SMR_RMS_INT_TYPE
                                               where interface_name = 'WH_ALLOC' );
                    
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
                                                    where interface_name = 'WH_ALLOC' );

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
         echo "$logdate Program: ${0}: Error while running function CLOSE_ALLOC $plsql_result    ..." >> $MMHOME/error/$errfile
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


CLOSE_ALLOC

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



