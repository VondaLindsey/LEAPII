#!/bin/ksh


# Parse the command line
#-----------------------------------------------
echo " para $#"
if [ $# -lt 3 ] ; then
   echo "Usage: $0 User/pass OutDirectory Threads2Launch"
   exit 1
fi

 UP=$UP
 OUTDIR=$2
typeset -i WIDTHOFJOBS=$3
SUPPLIST="/tmp/smr_Edisupplier_list1.lst"

export SQLHOME=/app/oracle/product/11.2.0.3/dbms/bin/
export CONNECT_STRING=$UP
BASEDIR=$(dirname $0)
batch_log=${BASEDIR}
LOG_DIR=${BASEDIR}/../log
ERR_DIR=${BASEDIR}/../log
CTLFILE=${BASEDIR}/SmrEdi810_FileLoad.ctl
ERR_FILE=${ERR_DIR}/err.`basename $0`.${LOG_DATE}

echo $CONNECT_STRING

. ${BASEDIR}/smr_leap2_lib.ksh

echo $0
echo `date`


MaxThreads=0

function getMaxThreads {

MaxThreads=`sqlplus -S $UP <<EOF
set termout off;
set newpage 0;
set space 0;
set linesize 1000;
set pagesize 0;
set echo off;
set feedback off;
set heading off;
set verify off;

select num_threads
  from restart_control
 where program_name = 'smrEdi810';

EOF`

}

function LOAD_STG_DATA {
   sqlTxt="
      DECLARE
     
         L_error_message      varchar2(255);
         L_vdate              date;
         L_num_threads        number(10) := $1;
         L_thread_val         number(10) := $2;
         L_directory          number(10) := null;
     
 BEGIN
 
     if SMR_RMS_INT_EDI_810.VALIDATE_DATA  (L_error_message ,
                        L_num_threads   ,
                        L_thread_val    ) = FALSE then
          dbms_output.put_line(L_error_message);
         :GV_return_code  := ${FATAL};
    end if;
   
 
            :GV_return_code := ${OK};
          commit;
      EXCEPTION
         WHEN OTHERS THEN
             dbms_output.put_line(SQLERRM);
             :GV_return_code  := ${FATAL};
             RAISE;
      END;"

   result=$(EXEC_SQL ${sqlTxt})

   err=$?

   if [[ $err -eq ${NONFATAL} ]] ; then
      echo $result
      LOG_ERROR "$result" "LOAD_STG_DATA" ${NONFATAL}
      return $err
   fi

   if [[ $err -ne ${OK} ]] ; then
      echo $result
      LOG_ERROR "$result" "LOAD_STG_DATA" ${NONFATAL}
      return $err
   fi

   return 0

}
function GENERATE_FILE {
run_dte=`date +%Y%m%d%H%M%S`
supplier=$1
sqlplus -S $CONNECT_STRING <<-ENDSQL >/dev/null 
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

spool $OUTDIR/EDIUPINV_${supplier}_${run_dte}.dat
 select FORMAT_REC || chr(13) 
       from SMR_EDI_810_FINAL_FILE_FORMAT
       where supplier =$1
       order by row_num, supplier, decode( HDR_DTL_IND,'F',1,'H',2,'D', 3, 'T',4, 'X', 5);
spool off
ENDSQL

dos2unix $OUTDIR/EDIUPINV_${supplier}_${run_dte}.dat
}

getsupplist()
{

`sqlplus -s $CONNECT_STRING  <<-ENDSQL > ${SUPPLIST}
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

  select distinct supplier 
        from SMR_EDI_810_FINAL_FILE_FORMAT
       order by SUPPLIER;

ENDSQL`

}
removezerobyte() {
   for input_file in `ls  $OUTDIR/EDIUPINV_*.dat `
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
getMaxThreads

echo $MaxThreads

echo "first step"
#######################################################################
# STEP  2 load staging data, call data base function
##  Call the load stage data in multi process way
# Set filename to flag any failed executions
failed=${pgmName}.$$
[ -f ${failed} ] && rm ${failed}

# If this script is killed, cleanup
trap "kill -15 0; rm -f $failed; exit 15" 1 2 3 15

i=1
while [[ $i -le $MaxThreads ]]
do
   if [ `jobs | wc -l` -lt ${WIDTHOFJOBS} ]
   then
      (( i++))
      (
          LOAD_STG_DATA $MaxThreads $i || touch $failed;
      ) &
   else
      # Loop until a thread becomes available
      while [ `jobs | wc -l` -ge ${WIDTHOFJOBS} ]
      do
         : # Null command
         sleep 1
      done
      (( i++))
      (
          LOAD_STG_DATA $MaxThreads $i || touch $failed;
      ) &
   fi
done
# Wait for all of the threads to complete
wait
# jobs() and wait() are not working well for long rebuilts
#while true; do
#   if [ `ps -ef | grep ${pgmName} | grep -v grep | wc -l` -gt 1 ]; then
#      LOG_MESSAGE "Waiting for the background LOAD_STG_DATA process"
#      #sleep 1
#   else
#      break;
#   fi
#done
sleep 5

echo "second step "
#######################################################################
# Step 3
getsupplist
if [[ $? -eq ${FATAL} ]] ; then
   echo $result
   LOG_ERROR "Error Getting Suppliers from Stage" ${FATAL}
   return 1
fi
   
   x=0
   cat ${SUPPLIST} | while read supplier
   do
      if [ `jobs | wc -l` -lt ${WIDTHOFJOBS} ]
      then
         (( x++)) 
         (
             GENERATE_FILE  $supplier   || touch $failed;
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
             GENERATE_FILE  $supplier   || touch $failed;
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
#######################################################################
