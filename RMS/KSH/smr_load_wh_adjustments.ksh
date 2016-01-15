#!/bin/ksh
#-------------------------------------------------------------------------
#  File:  smr_load_wh_adjustments.ksh
#
#  Desc:  UNIX shell script to Process WH adjustments into RMS from the Interface tables             
#-------------------------------------------------------------------------
#############################################################################
# Modification History
# Ver. Date        Programmer         Description
# ==== =========== ================   =============
# 1.00 10-May-15   Murali Natarajan   Initial Version 
#This script will be the main script that loops through and processes the Shipment data and load thems into RMS. 
#This script will also be responsible for calling all the Database packages for validating and processing the data into RMS
# Algorithm
#1.	Invoked from UC4 Job.
#2.	Call Function SMR_WH_ADJ_SQL.F_INIT_WH_ADJ to initiate the process and copy required data to RMS staging tables. As part of this function the adjustment data 
#  from EDI table SMR_RMS_INT_ADJSUTMENTS will be loaded into SMR_RMS_ADJ_STAGE for further validation and processing.
#3.	Invoke the package SMR_WH_ADJ_SQL.F_PROCESS_WH_ADJ to process the data from staging table.
#4.	Invoke the package SMR_WH_ADJ_SQL.F_FINISH_PROCESS to finish processing the data and update status accordingly. 

#############################################################################
# Revision : $Id: 

###############
   set serveroutput on
      set heading off
      set verify off
      set feedback off##############################################################################
#VARIABLE DECLARATION
#############################################################################################
typeset -r dbConnect="$MMUSER/$PASSWORD@$ORACLE_SID"

run_function()
{

plsql_result=`sqlplus -s $dbConnect <<-ENDSQL 
   whenever sqlerror exit 1
   
   VARIABLE outtext VARCHAR2(4000)

   DECLARE

      L_error_message varchar2(500):= NULL;
   BEGIN

	  if  SMR_WH_ADJ_SQL.F_INIT_WH_ADJ(l_ERROR_MESSAGE ) = FALSE then
		 raise_application_error(-20010, l_error_message);
	  else
		 L_error_message := '';
	  end if;

	  if  SMR_WH_ADJ_SQL.F_PROCESS_WH_ADJ(l_ERROR_MESSAGE ) = FALSE then
		 raise_application_error(-20010, l_error_message);
	  else
		 L_error_message := '';
	  end if;
	  
	  if  SMR_WH_ADJ_SQL.F_FINISH_PROCESS(l_ERROR_MESSAGE ) = FALSE then
		 raise_application_error(-20010, l_error_message);
	  else
		 L_error_message := '';
	  end if;
	  
  EXCEPTION
   when OTHERS then
      L_error_message := SQLERRM || l_error_message  || TO_CHAR(SQLCODE);
      :outtext := L_error_message;
  END;
/
 print :outtext
  QUIT;
ENDSQL`

    echo " plsql result $plsql_result"

#	if [[ "${plsql_result}" = +(*"ORA-"*) ]]; then
	if [ `echo ${plsql_result} | grep "ORA-"  | wc -l` -gt 0 ] ;  then
	 logdate=`date +"%a %h %d %T"`
	 echo "$logdate Program: ${0}: Error while running package c$plsql_result  $1  ..." >> ${MMHOME}/error/$errfile
	  return 1
	else
	  return 0
	fi
}

# Main Program

logdate=`date +"%a %h %d %T"`
logfile=`date +"%h_%d.log"`
errorfile="err.smr_load_wh_adjustments.`date +"%h_%d"`"

echo "$logdate Program: ${0}: Started" >> $MMHOME/log/$logfile
	   
run_function

if [ $? -eq 0 ]
then
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Terminated Succesfully " >> $MMHOME/log/$logfile
else
   logdate=`date +"%a %h %d %T"`
   echo "$logdate Program: ${0}: Terminated with errors " >> $MMHOME/log/$logfile
   exit 1 
fi

exit 0


