#!/bin/ksh
### The script forms_compile_all.ksh can be used to Compile all Form related Objects in RMS app server.
### The script needs placed in <RMS Application Home>/forms_scripts Folder
### The script picks the latest source from Forms "src" directory and compile and move the executable to the "bin" directory.


CONCURPS=5; export CONCURPS

LOG=$LOGDIR/forms.comp.log
touch $LOG

###  Function used to recompile all Form PLL libraries
function LIBCMP {
	rm $PLL.plx 2>/dev/null
        print "Compiling $1.pll...."|tee -a $LOG
        frmcmp_batch.sh module=$PLL userid=$UP module_type=library logon=yes script=no compile_all=yes strip_source=no > $LOGDIR/$1.pll.log
        cat $LOGDIR/$1.pll.log >> $LOG
        if [ ! -f $PLL.plx ]
        then
           print "Warning: $1.pll failed to compile.  See $ERRDIR/$1.pll.err for more details." |tee -a $LOG
		   mv $LOGDIR/$1.pll.log $ERRDIR/$1.pll.err
        fi
}

###  Function used to recompile all Menu elements
function MMBCMP {
	rm $MMB.mmx 2>/dev/null
        print "Compiling $1.mmb...."|tee -a $LOG
        frmcmp_batch.sh module=$MMB userid=$UP module_type=menu > $LOGDIR/$1.mmb.log
        cat $LOGDIR/$1.mmb.log >> $LOG
        if [ ! -f $MMB.mmx ]
        then
            print "Warning: $1.mmb failed to compile.  See $ERRDIR/$1.mmb.err for more details." |tee -a $LOG
			mv $LOGDIR/$1.mmb.log $ERRDIR/$1.mmb.err
        fi
}

###  Function used to recompile all Form elements
function FMBCMP {
	rm $FMB.fmx 2>/dev/null
        print "Compiling $1.fmb...."|tee -a $LOG
        frmcmp_batch.sh module=$FMB userid=$UP module_type=form > $LOGDIR/$1.fmb.log
        cat $LOGDIR/$1.fmb.log >> $LOG
        if [ ! -f $FMB.fmx ]
        then
            print "Warning: $1.fmb failed to compile.  See $ERRDIR/$1.fmb.err for more details." |tee -a $LOG
		    mv $LOGDIR/$1.fmb.log $ERRDIR/$1.fmb.err
		    rm $1.fmb
        fi
}

for PLL in `ls ../toolset/src/*.pll | sed s/.pll//` `ls ../forms/src/*.pll | sed s/.pll//`
do
    filename=`basename $PLL`
	LIBCMP $filename
done

mv ../toolset/src/*.plx ../toolset/bin/ >> $LOG
mv ../forms/src/*.plx ../forms/bin/>> $LOG

for MMB in `ls ../toolset/src/*.mmb | sed s/.mmb//` `ls ../forms/src/*.mmb | sed s/.mmb//`
do
    filename=`basename $MMB` 
	MMBCMP $filename &		
	MMB_CNT=`ps | grep frmcmp |grep -v grep| wc -l`

	while [ $MMB_CNT -ge $CONCURPS ]
	do
		MMB_CNT=`ps | grep frmcmp |grep -v grep| wc -l`
	done
done
wait

mv ../toolset/src/*.mmx ../toolset/bin/ >> $LOG
mv ../forms/src/*.mmx ../forms/bin/ >> $LOG

for FMB in `ls ../toolset/src/*.fmb | sed s/.fmb//` `ls ../forms/src/*.fmb | sed s/.fmb//`
do
    filename=`basename $FMB`
	FMBCMP $filename &
	FMB_CNT=`ps | grep frmcmp |grep -v grep| wc -l`

	while [ $FMB_CNT -ge $CONCURPS ]
	do
		FMB_CNT=`ps | grep frmcmp |grep -v grep| wc -l`
	done
done
wait

mv ../toolset/src/*.fmx ../toolset/bin/ >> $LOG
mv ../forms/src/*.fmx ../forms/bin/ >> $LOG

exit
