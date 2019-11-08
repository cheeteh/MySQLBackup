# #################################################################################################
#  File         $URL: file:///var/svn/fw-repo/branches/4.2.7/Iguazu/Iguazu-Web/src/main/webapp/WEB-INF/bin/inc_db_backup_31.sh $
#  Revision     $Revision: 14488 $
#  Author       $Author: randy $
#  Last Revised $Date: 2015-09-23 10:58:24 -0400 (Wed, 23 Sep 2015) $
# #################################################################################################
#!/bin/sh

##################
# Return codes
##################
SUCCESS=0
MYSQL_BACKUP_FAILED=1
MYSQL_BACKUP_NOT_INSTALLED=2
TAR_FAILED=3
GPG_FAILED=4
CUSTOMER_HOME_DOESNT_EXIST=5
MYSQL_BACKUP_STILL_RUNNING=6
NO_FULL_BACKUP_AVAILABLE=7

##################
# Variables
##################
BU_OUT_DIR=/chroot/home/db_backup
CURRENT_BACKUP_FILENAME=`date '+%A'`"_incremental.mbi"
BACKUP_DAY=`date '+%A'`
BACKUP_DIR=${BU_OUT_DIR}"/"${BACKUP_DAY}
PASSPHRASE_FILE=/usr/local/tomcat/serverA/webapps/Iguazu-Web/WEB-INF/bin/my_passphrase
LOG_FILE=/home/fairwarning/log/meb_inc_backup.log

MYSQL_USER=root
MYSQL_PASSWORD=r1singtide

CUSTOMER_HOME=/chroot/home
CUSTOMER_USER=tomcat.data

##################
# Functions
##################
check_return_code ()
{
  return_code=$1
  message=$2
  exit_code=$3
  if [ x"$1" != x"0" ] ; then
    echo "$message - exiting with code of $exit_code"  >> $LOG_FILE  2>&1
    exit $3
  fi
}

clean_up_failed_backup()
{
  failed_backup_file=$1
  backup_tmp_dir=$2
  echo cleaning up failed backup $failed_backup_file $backup_tmp_dir >> $LOG_FILE 2>&1
  # remove the incomplete backup
  rm -f $failed_backup_file
  # clean up the temp directory
  rm -rf $backup_tmp_dir
}

##################
# Start execution
##################

echo ""                                                                    >>$LOG_FILE  2>&1
echo "*****************************************************************"   >>$LOG_FILE  2>&1
echo `date +'%Y-%m-%d %H:%M:%S'` "  Starting MEB Incremental  Backup..."   >>$LOG_FILE  2>&1
echo "*****************************************************************"   >>$LOG_FILE  2>&1
echo ""                                                                    >>$LOG_FILE  2>&1

#  Locate the mysql client executable...
MYSQL_EXE=`which mysql`
if [ "$MYSQL_EXE" == "" ] ; then
  if [ -x /usr/local/mysql/bin/mysql ] ; then
    MYSQL_EXE="/usr/local/mysql/bin/mysql"
  elif [ -x /usr/bin/mysql ] ; then
    MYSQL_EXE="/usr/bin/mysql"
  else
    check_return_code 1 "Cannot locate mysql client - exiting..." $MYSQL_CLIENT_NOT_INSTALLED
  fi
fi

# Make sure backup isn't currently running...
BACKUP_RUNNING=`ps -ef | grep mysqlbackup | wc -l`
if [[ $BACKUP_RUNNING -gt 1 ]] ; then
  check_return_code 1 "!\nMySQL Backup is still running.  Exiting." $MYSQL_BACKUP_STILL_RUNNING
fi

if [[ ! -d $CUSTOMER_HOME  || -z $CUSTOMER_HOME ]]; then
  check_return_code 1 "Directory $CUSTOMER_HOME not found!\nExiting." $CUSTOMER_HOME_DOESNT_EXIST
fi


$MYSQL_EXE -u${MYSQL_USER} -p${MYSQL_PASSWORD} epictide -s -s -e"select setting_value from APP_SETTINGS where setting_key = 'FULL_BACKUP_PATHS';" >./fb_dirs.lst 2>/dev/null
BU_OUT_DIRS=$(< ./fb_dirs.lst)
BU_OUT_DIR0=`echo $BU_OUT_DIRS | cut -d ',' -f 1`
BU_OUT_DIR1=`echo $BU_OUT_DIRS | cut -d ',' -f 2`
if [ "${BU_OUT_DIR0}" == "" ] ; then
  check_return_code 1 "App Setting is not returning location for backup file..." $BACKUP_LOCATION_NOT_SET
fi

# echo "Before attempting to fix: DIR0: ${BU_OUT_DIR0}  -  DIR1: ${BU_OUT_DIR1}"
#  Make sure each var has a trailing "/"...
if [ "${BU_OUT_DIR0: -1}" != "/" ] ; then
  BU_OUT_DIR0="${BU_OUT_DIR0}/"
fi
if [ "${BU_OUT_DIR1: -1}" != "/" ] ; then
  BU_OUT_DIR1="${BU_OUT_DIR1}/"
fi


#  Check to see if there is only one directory is requested...
if [ "${BU_OUT_DIR0}" == "${BU_OUT_DIR1}" ] || [ ${BU_OUT_DIR1} == "/" ] ; then
  # echo "We only want one directory..."
  SINGLE_DIR=1
  echo "Single directory Dir 0 found at: $BU_OUT_DIR0"    >>$LOG_FILE  2>&1
  # echo "Dir 0 found at: $BU_OUT_DIR0"
else
  SINGLE_DIR=0
  echo "Dir 0 found at: $BU_OUT_DIR0  -  Dir 1 found: $BU_OUT_DIR1" >>$LOG_FILE 2>&1
  # echo "Dir 0 found at: $BU_OUT_DIR0  -  Dir 1 found: $BU_OUT_DIR1"
fi

#check which one of them has the latest backup - and make that backup dir
if [ $SINGLE_DIR = 0 ]; then
	if [ -f $BU_OUT_DIR0/full_db_backup.mbi ]; then
		BU_OUT_DIR=${BU_OUT_DIR0}
	fi	
	if [ -f $BU_OUT_DIR1/full_db_backup.mbi ]; then
		BU_OUT_DIR=${BU_OUT_DIR1}
	fi
fi	

echo "Current Full DB Backup is at ::: $BU_OUT_DIR\n"

# if the output directory does not exist create it
if [ ! -d $BU_OUT_DIR ] ; then
  mkdir -p $BU_OUT_DIR
  chown $CUSTOMER_USER $BU_OUT_DIR
fi

# if MySQL enterprise backup is not installed, let's complain about it and exit.
mysqlbackup_bin=`which mysqlbackup`
if [ -x /opt/mysql/meb-3.10/bin/mysqlbackup ] ; then
  mysqlbackup_bin="/opt/mysql/meb-3.10/bin/mysqlbackup --socket=/var/lib/mysql/mysql.sock"
elif [ -x /usr/bin/mysqlbackup ] ; then
  mysqlbackup_bin="/usr/bin/mysqlbackup --socket=/var/lib/mysql/mysql.sock"
elif [ -x /usr/local/mysql/bin/mysqlbackup ] ; then
  mysqlbackup_bin=/usr/local/mysql/bin/mysqlbackup
else
  check_return_code 1 "MySQL enterprise backup is not installed at /usr/local/mysql/bin/mysqlbackup or /opt/mysql/meb-3.10/bin/mysqlbackup!!! exiting." $MYSQL_BACKUP_NOT_INSTALLED
fi
echo "MySQL Enterprise Backup Found: $mysqlbackup_bin"  >>$LOG_FILE 2>&1

# Get the day of the week full backups possess...
$MYSQL_EXE -u${MYSQL_USER} -p${MYSQL_PASSWORD} -s -s \
  -e"SELECT from_unixtime(substring(prev_fire_time,1,10),'%W') \
       FROM quartz.QTZ_TRIGGERS \
      WHERE trigger_group = 'DEFAULT' \
        AND job_name = 'MEB Backup' \
        AND job_group = 'SYSTEM_COMMAND';" >./fb_day.lst 2>>/dev/null
FULL_BACKUP_DAY=$(< ./fb_day.lst)
if [ "$FULL_BACKUP_DAY" == "" ] ; then
  $MYSQL_EXE -uroot -pr1singtide events -s -s \
    -e"SELECT date_format(start_time,'%W') \
         FROM mysql.backup_history \
        WHERE backup_type = 'FULL' \
          AND exit_state = 'SUCCESS' \
       ORDER BY backup_id desc limit 1;" \
       >./fb_day.lst 2>>/dev/null
  FULL_BACKUP_DAY=$(< fb_day.lst)
  if [ "$FULL_BACKUP_DAY" == "" ] ; then
    check_return_code 1 "Must have successful full backup in order to run incremental..." $NO_FULL_BACKUP_AVAILABLE
  fi
fi

echo "Full Backups run on: $FULL_BACKUP_DAY" >> $LOG_FILE 2>&1

echo "Let's get the last day of backup..." >> $LOG_FILE 2>&1
# First see if we can get this from the backup_history_table...
$MYSQL_EXE -u${MYSQL_USER} -p${MYSQL_PASSWORD} -s -s -e"SELECT date_format(end_time,'%W') from mysql.backup_history where exit_state = 'SUCCESS' order by backup_id desc limit 1;" >./lb_day.lst 2>/dev/null
LAST_BACKUP_DAY=$(<lb_day.lst)
echo "Last Backup Day: [$LAST_BACKUP_DAY]"      >>$LOG_FILE   2>&1
LAST_BACKUP_DIR=${BU_OUT_DIR}"/"${LAST_BACKUP_DAY}

if [ "$LAST_BACKUP_DAY" == "$FULL_BACKUP_DAY" ] ; then
  #  Check to make sure full backup is in the house...
  if [ -f ${BU_OUT_DIR}"/""full_db_backup.mbi" ] ; then
    LAST_BACKUP_DIR=${BU_OUT_DIR}"/tmp_backup/"
    #  Let's remove all of the previous incremental zip files...
    for myday in "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday" ; do
      if [ -f "${BU_OUT_DIR}"/"${myday}""_incremental.mbi"  ] ; then
        echo "removing ${BU_OUT_DIR}""/""${myday}""_incremental.mbi" >> $LOG_FILE 2>&1
        rm -rf ${BU_OUT_DIR}"/""${myday}""_incremental.mbi"
      fi
    done
    break
  else
    check_return_code 1 "No full backup to base incremental from ${BU_OUT_DIR}""/""full_db_backup.mbi" $MYSQL_BACKUP_FAILED
  fi
else
  if [ -f ${LAST_BACKUP_DIR}"/"${LAST_BACKUP_DAY}"_incremental.mbi" ] ; then
    echo "Found prior backup on $LAST_BACKUP_DAY"
    #  Clean out current backup day directory in case Monday's clear-all didn't work...
    if [ -d ${BACKUP_DIR} ] ; then
      rm -rf ${BACKUP_DIR}
    fi
    break
  fi
fi

echo "Last backup day: $LAST_BACKUP_DAY"  >> $LOG_FILE 2>&1
echo "current backup day: $BACKUP_DAY"    >> $LOG_FILE 2>&1

echo "backup executable found: $mysqlbackup_bin" >> $LOG_FILE 2>&1
# make the incremental backup - encryption not an option for incrmentals...
echo $mysqlbackup_bin -u${MYSQL_USER} -p${MYSQL_PASSWORD} --port=3306 --incremental --no-locking --backup-dir=${BACKUP_DIR}"/" \
                     --incremental-base=history:last_backup --encrypt --key-file=${PASSPHRASE_FILE} backup-to-image \
                     --backup-image=${BACKUP_DIR}"/"${CURRENT_BACKUP_FILENAME} >> $LOG_FILE 2>&1
$mysqlbackup_bin -u${MYSQL_USER} -p${MYSQL_PASSWORD} --port=3306 --incremental --no-locking --backup-dir=${BACKUP_DIR}"/" \
                 --incremental-base=history:last_backup --encrypt --key-file=${PASSPHRASE_FILE} backup-to-image --backup-image=${BACKUP_DIR}"/"${CURRENT_BACKUP_FILENAME} >> $LOG_FILE 2>&1
mysqlbackup_return=$?

# if the backup is not a success, do not leave an corrupt backup sitting around...
if [ x"$mysqlbackup_return" != x"0" ] ; then
  clean_up_failed_backup ${BACKUP_DIR}/${CURRENT_BACKUP_FILENAME} ${BACKUP_DIR}
  # exit and log on failure
  check_return_code $mysqlbackup_return "mysqlbackup " $MYSQL_BACKUP_FAILED
else
  #  The backup was a success - now let's move it to a file at the same level as full backup...
  mv ${BACKUP_DIR}"/"${CURRENT_BACKUP_FILENAME} ${BU_OUT_DIR}"/"
  tar_rc=$?
  if [ x"$tar_rc" == "x0" ] ; then
   rm -rf ${BACKUP_DIR}"/"
  fi
fi

exit $SUCCESS
