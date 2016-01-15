#!/bin/ksh
# Purpose : This script will generate Payment Advice Report
#           This is setup to run uc4

# Process Flow : Step 1 Get max number of threads for this job from restart_control(getMaxThreads function)
               # Step 2 load staging data(LOAD_STG_DATA shell function), call data base function SMR_RMS_INT_EDI_810.VALIDATE_DATA  
              ##        This database function call will validate all the records if they can be loaded into ReIM
              ##        Any records that failed validation will be flagged for analysis
              ##        this Call the load stage data in multi process way
              #  Step 3 Get a list of suppliers fron the staging tables (getsupplist)
              ##        Generate files for each supplier(GENERATE_FILE function)


# Parse the command line
#-----------------------------------------------
if [ $# -lt 2 ] ; then
   echo "Usage: $0 User/pass OutDirectory "
   exit 1
fi

UP=$UP
OUTDIR=$2
WIDTHOFJOBS=5


export SQLHOME=/app/oracle/product/11.2.0.3/dbms/bin/
BASEDIR=${MMHOME}
batch_log=${BASEDIR}
LOG_DIR=${BASEDIR}/log
ERR_DIR=${BASEDIR}/log
ERR_FILE=${ERR_DIR}/err.`basename $0`.${LOG_DATE}
logdate=`date +"%a %h %d %T"`
logfile=`date +"%h_%d.log"`
errfile="err.`basename $0`.`date +"%h_%d"`"

echo $BASEDIR

POSTED_ADVICE="/tmp/smr_posted_adv_list1.lst"

touch $POSTED_ADVICE
if [ $? -ne 0 ] ; then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Can not Create $POSTED_ADVICE ..." >> $LOG_DIR/$logfile
   return 1
fi


getpaidinv()
{

`sqlplus -s $UP  <<-ENDSQL > ${POSTED_ADVICE}
   whenever sqlerror exit 1
   set pages 299
   set lines 800
   set trimspool on
   set termout off;
   set newpage 0;
   set space 0;
   set linesize 1000;
   set pagesize 0;
   set echo off;
   set feedback off;
   set heading off;
   set verify off;
   set serveroutput on

   select xh.paid_inv_no 
     from im_doc_head idh, 
          SMR_INV_CROSS_REF_HEAD xh
    where idh.ext_doc_id = xh.paid_inv_no
      and idh.post_date = get_vdate
      and idh.status = 'POSTED'
      union
       select PAID_INV_NO from SMR_INV_CROSS_REF_HEAD;

ENDSQL`

}

function GENERATE_FILE {
run_dte=`date +%Y%m%d%H%M%S`
supplier=$1
sqlplus -S $UP <<-ENDSQL >/dev/null 
set pages 299
set lines 800
set trimspool on
set termout off;
set linesize 300;
set echo off;
set feedback off;
set heading on;
set verify off;
set escape on
break on  paid_inv_no on due_date  on order_no on sdc_inv_amt
 COLUMN paid_inv_no HEADING "Paid Invoice Number" FORMAT A20
 COLUMN due_date HEADING "Paid Inv Due Date" FORMAT A20
 COLUMN order_no HEADING "PO (9 digit)" FORMAT 99999999999
 COLUMN sdc_inv_amt HEADING "Invoice Amount" FORMAT "\$9,999,999.00"
 COLUMN orig_inv_no HEADING "Vendor Inv Number" FORMAT A20
 COLUMN orig_due_date HEADING "Orig. Due Date" FORMAT A20
 COLUMN orig_order_no HEADING "PO (6 digit)" FORMAT 99999999999
 COLUMN store HEADING "Store"
 COLUMN str_inv_amt HEADING "Store Invoice Amount" FORMAT "\$9,999,999.00"
TTITLE  LEFT "           Payment Advice Cross Reference"
 compute avg label "sum of Paid Invoice" of sdc_inv_amt on paid_inv_no 
 compute SUM label "Sum of store invoices " OF str_inv_amt on paid_inv_no

 spool $OUTDIR/PaymentAdvice_$1_${run_dte}.dat

select substr(xh.paid_inv_no,1,20) paid_inv_no, xh.due_date, xh.order_no,
       xh.sdc_inv_amt, substr(xd.orig_inv_no,1,20) orig_inv_no,
       xd.due_date orig_due_date, xd.order_no orig_order_no, xd.location store,
       xd.str_inv_amt
  from SMR_INV_CROSS_REF_HEAD xh,
       SMR_INV_CROSS_REF_DETAIL xd
 where xh.record_id = xd.record_id
   and xh.paid_inv_no = '$1';
 

spool off
ENDSQL

}

removezerobyte() {
   for input_file in `ls  $OUTDIR/PaymentAdvice_*.dat `
   do

  if [ ! -s $input_file ]
     then
      rm -f $input_file 
  fi 

    done
}

#### Execution starts from here
# Main program starts

#######################################################################
# Step 1
getpaidinv
#if [[ $? -eq ${FATAL} ]] ; then
#   logdate=`date +"%a %h %d %T"`
#   echo "$logdate Program: ${0}: Error Getting Paid Invoices " >> ${LOG_DIR}/$logfile
#   return 1
#fi

# Step 2
## generate advice report based on Invoice number

   x=0
   cat ${POSTED_ADVICE} | while read paidInvNo
   do
      if [ `jobs | wc -l` -lt ${WIDTHOFJOBS} ]
      then
         (( x++)) 
         (
             GENERATE_FILE  $paidInvNo   || touch $failed;
         ) &
      else
         # Loop until a thread becomes available
         while [ `jobs | wc -l` -ge ${WIDTHOFJOBS} ]
         do
            : # Null command
            sleep 1
         done
         (( x++))
         (
             GENERATE_FILE  $paidInvNo   || touch $failed;
         ) &
      fi
  done
   
   # Wait for all of the threads to complete
   wait
   
   # jobs() and wait() are not working well for long rebuilts
#   while true; do
#      if [ `ps -ef | grep ${pgmName} | grep -v grep | wc -l` -gt 1 ]; then
#         LOG_MESSAGE "Waiting for the background ${PROGRAM} process"
#         #sleep 1
#      else
#         break;
#      fi
#  done

removezerobyte

echo "Last step"




