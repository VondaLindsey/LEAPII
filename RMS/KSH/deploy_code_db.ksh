#!/bin/ksh
### The Script deploy_code_db.ksh Can be used for deploying the Leap 2 Changes for the RMS DB server. The script will be part of the 
### code checked in and would Need to be copied along with the other scripts for Deployment.
### Below are the steps to Deploy script in RMS DB
### 	1. Copy all the objects required for Leap Deployment from CVS to the RMS DB server  
### 	2. Below should be the Folder Structure in the RMS DB server  For Script to be Used for deployent
###			 <Release_Directory>               - Folder Where all objects will need to be Copied from CVS
###					- sql                      - Sql folder containing all DB scripts  
###					- shell                    - Shell Folder containing all shell scripts
###					- proc                     - Proc folder containing all Proc files
###					- deploy_code_db.ksh       - Deployment script to be placed in the Release directory
###     3. sudo to rmststbt/rmsprdbt user  
###     4. Execute the script deploy_code_db.ksh to deploy the Leap Changes on the DB server
### The script performs the below Steps  
### 			a. Run the sql scripts connecting to RMS DB
### 			b. copy the shell script to $MMHOME/oracle/proc/src and bin
###             c. Create Link Files For Shell scripts in Bin Folder
### 			c. Copy Pro*C to $MMHOME/oracle/proc/src and compile. Also copy the executables to $MMHOME/oracle/proc/bin
### 			d. Copy pro*C libraries to $MMHOME/oracle/lib/src and compile. Also copy the executables to $MMHOME/oracle/lib/bin 

if [ $# -ne 1 ] ; then
   echo "Usage: $0 User/pass "
   exit 1
fi

UP=$1

curr_dir=`pwd`
log_dir=$curr_dir
log_file=`echo "Leap_Release_0.1.log"`

cd $curr_dir/sql
dos2unix * >> $log_dir/$log_file

echo "Deploying All DB changes" >> $log_dir/$log_file

$ORACLE_HOME/bin/sqlplus -s $UP @run_all_sql.sql >> $log_dir/$log_file

cd $curr_dir/shell
dos2unix * >> $log_dir/$log_file

echo "Copying Shell Scripts to src folder" >> $log_dir/$log_file

echo "Change Permissions for Shell Scripts"
chmod 755 *.ksh >> $log_dir/$log_file
cp *.ksh $MMHOME/oracle/proc/src/ >> $log_dir/$log_file

echo "Create link file for all new shell scripts in Bin folder" >> $log_dir/$log_file

srcdir=$MMHOME/oracle/proc/src
tgtdir=$MMHOME/oracle/proc/bin
for i in $(ls *.ksh)
do 
echo "Creating Link for $i" >> $log_dir/$log_file
ln -vs $srcdir/$i $tgtdir/$i >> $log_dir/$log_file
done

echo "Copy Pro*c file to $MMHOME/oracle/proc/src" >> $log_dir/$log_file

cd $curr_dir/proc
dos2unix * >> $log_dir/$log_file

echo "Change Permissions for Proc*c Files"
chmod 755 *.pc >> $log_dir/$log_file
cp *.pc $MMHOME/oracle/proc/src/ >> $log_dir/$log_file

echo "Copy header file to $MMHOME/oracle/lib/src" >> $log_dir/$log_file

cd $curr_dir

echo "Copy C Header File"
cp $curr_dir/shell/std_len.h $MMHOME/oracle/lib/src >> $log_dir/$log_file

cd $MMHOME/oracle/lib/src

echo "Compile libraries and move executable to $MMHOME/oracle/lib/bin "
make -f rmslib.mk clean >> $log_dir/$log_file

make -f rmslib.mk all >> $log_dir/$log_file

make -f rmslib.mk install >> $log_dir/$log_file

cd $MMHOME/oracle/proc/src

echo "Compile Proc*c files and move executable to $MMHOME/oracle/proc/bin "
make -f rms.mk clean >> $log_dir/$log_file

make -f rms.mk all >> $log_dir/$log_file

make -f rms.mk install >> $log_dir/$log_file

exit
