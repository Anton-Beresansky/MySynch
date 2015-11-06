#!/bin/bash

#====================================================================================
#	VARIABLES Initialization
#====================================================================================
SCRIPTNAME=`basename "$0" | cut -d'.' -f1`
SCRIPTFULLPATH=$0
SERVERSLIST=(192.168.1.157 192.168.1.189)
USERNAME=$USER
LOGFILE='/var/log/MySynchLog.log' #Set log directory and filename.
TARGETDIR='/tmp'	#Set directory to collect data
TMPDIR='/tmp' #Set temp path.
MINSPACE=10240	#Set limit of free space in Kbytes. If TMPDIR (local) have less - script will stop.
TIMEOUT=300	#Set timeout in seconds. If execution of COPYing time exseeds - script will stop.
EXIT_CODE=0

#====================================================================================
#	Function Logging
#	$1 = message (string to log)
#====================================================================================
function log() {
	if [ ! "$1" ]
		then
			printf "$SCRIPTNAME ERROR: Log function called without argument!\n"
			exit
	fi

	local DATETIME=`date +%d.%m.%Y-%T`
	local MSGLN="$DATETIME\t$1\n"

	touch $LOGFILE &>> /dev/null

	if [ ! -w $LOGFILE ]
		then
			printf "$MSGLN"
		else
			printf "$MSGLN" &>> $LOGFILE
	fi
}

#====================================================================================
#	Directory Validation
#	$1 = absolute path
#====================================================================================
function validdir(){
	if [ ! "$1" ]
		then
			log "ERROR: Function «validdir» called without argument;"
			return 1
	elif echo $1 | grep "^/.*" >> /dev/null
		then
			return 0
	else
		return 2
	fi
}

#====================================================================================
#	Function Usage
#====================================================================================
function usage() {
	printf "Usage: $SCRIPTNAME [FULL PATH to replicate] [OPTION]\n\t-s install public key in a remote machine's authorized_keys\n\t-u USERNAME set remote user name\n\t"
}

#====================================================================================
#	Function SSH Keys generate and copy
#====================================================================================
function sshkeyscopy() {
	log "starting ssh-keygen;"
	ssh-keygen -t rsa
	for SERVER in ${SERVERSLIST[@]} 
	do
		log "copying key to «$SERVER.»"
		ssh-copy-id ${USERNAME}@${SERVER}
	done
}
#====================================================================================
#	Body
#====================================================================================
log "Starting «$SCRIPTNAME»;"

if [ $# = 0 ]
	then
		log "You must provide absolute path as the first argument to run this script;"
		usage
		exit
elif ! validdir $1
	then
		log "You must provide ABSOLUTE PATH as the FIRST argument to run this script;"
		usage
		exit
fi

SOURCEDIR=$1
log "Source directory is «$SOURCEDIR»;"
shift

while [ $# -gt 0 ]
do
	case $1 in
		"-s")
			sshkeyscopy
			exit
			;;
		"-u")
			USERNAME=$2
			log "Username is «$USERNAME»;"
			shift
			;;
		*)
			log "ERROR: Unknown option «$1»;"
			usage
			exit
			;;
	esac
	shift
done

log "Servers to process: «${SERVERSLIST[*]}»;"
for SERVER in ${SERVERSLIST[*]}
do
	log "Starting SSH session to «$SERVER» with username «$USERNAME»;"
	SSHSESSION="ssh ${USERNAME}@${SERVER}"
	$SSHSESSION "echo HI, HUNNY! I\'M HOME!" &>> /dev/null
	EXIT_CODE=$?
	if [ $EXIT_CODE -ne 0 ]
		then
			log "ERROR: connection to host «$SERVER» with username «$USERNAME» (exitcode = $EXIT_CODE)."
			continue
	else
			log "Connected to «$SERVER» with username «$USERNAME»;"
	fi
	
	$SSHSESSION "[ -d $SOURCEDIR ]" &>> /dev/null
	EXIT_CODE=$?
	if [ $EXIT_CODE -ne 0 ]
		then
			log "ERROR: source directory «$SOURCEDIR» does not exist on server «$SERVER» or is not a directory (exitcode = $EXIT_CODE)."
			continue
	fi
	
	$SSHSESSION "[ -r $SOURCEDIR ]" &>> /dev/null
	EXIT_CODE=$?
	if [ $EXIT_CODE -ne 0 ]
		then
			log "ERROR: user «$USERNAME» does not have permissions to read source directory «$SOURCEDIR» on server «$SERVER» (exitcode = $EXIT_CODE)."
			continue
	fi
	
	$SSHSESSION "[ -x $SOURCEDIR ]" &>> /dev/null
	EXIT_CODE=$?
	if [ $EXIT_CODE -ne 0 ]
		then
			log "ERROR: user «$USERNAME» does not have permissions to execute (or search) directory «$SOURCEDIR» on server «$SERVER» (exitcode = $EXIT_CODE)."
			continue
	fi
	
	SERVER_TMP_FREESPACE=$($SSHSESSION "df --output=avail $TMPDIR" | awk 'NR==2 {print $1}')
	log "«$SERVER_TMP_FREESPACE» Kbytes free space available in «$TMPDIR» on «$SERVER»;"
	SERVER_SOURCE_SPACE=$($SSHSESSION "df --output=used $SOURCEDIR" | awk 'NR==2 {print $1}')
	log "«$SERVER_SOURCE_SPACE» Kbytes used by source directory «$SOURCEDIR» on «$SERVER»;"
	LOCAL_TMP_FREESPACE=$(df --output=avail $TMPDIR | awk 'NR==2 {print $1}')
	log "«$LOCAL_TMP_FREESPACE» Kbytes used by source directory «$TMPDIR» on «$HOSTNAME»;"
	if [ $LOCAL_TMP_FREESPACE -lt $MINSPACE ]
		then
			log "ERROR: there is only «$LOCAL_TMP_FREESPACE» Kbytes left in «$TMPDIR» (Minimal amount of free space available = «$MINSPACE»);"
			continue
	elif [ $SERVER_TMP_FREESPACE -lt $SERVER_SOURCE_SPACE ]
		then
			log "ERROR: there is only «$SERVER_TMP_FREESPACE» Kbytes left in «$TMPDIR» on «$SERVER», «$SERVER_SOURCE_SPACE» needed;"
			continue
	fi
	
	TMPDATE=$(date +%d%m%Y-%H%M%S)
	TMPFILE="$TMPDIR/MySynch_$SERVER"_"$TMPDATE.tar.gz"
	TARGETFILE="$TARGETDIR/MySynch_$SERVER"_"$TMPDATE.tar.gz"

	log "Trying to create archive «$TARGETFILE» on «$SERVER»;"
	$SSHSESSION "tar -zcvf $TMPFILE $SOURCEDIR &>> /dev/null"
	EXIT_CODE=$?	
	if [ $EXIT_CODE -eq 0 ]
		then
			log "File «$TMPFILE» on «$SERVER» created successfully;"
	else
		case $EXIT_CODE in
			1)
				log "WARNING: some files were changed while being archived and so the resulting archive does not contain the exact copy of the file set;"
				;;
			2)
				log "ERROR: some fatal, unrecoverable error occurred (exitcode = $EXIT_CODE);"
				continue
				;;
			*)
				log "ERROR: failed to create archive «$TMPFILE» in «$TMPDIR» on «$SERVER» (exitcode = $EXIT_CODE);"
				continue
				;;
		esac
	fi
	SERVER_MD5=$($SSHSESSION "md5sum $TMPFILE | awk '{print \$1}'")
	EXIT_CODE=$?
	if [ $EXIT_CODE -eq 0 ]
		then
			log "md5sum of «$TMPFILE» on «$SERVER» = «$SERVER_MD5»;"
		else
			log "ERROR: failed to get md5sum of «$TMPFILE» on «$SERVER» (exitcode = $EXIT_CODE);"
			continue
	fi
	
	timeout $TIMEOUT scp -r ${USERNAME}@${SERVER}:$TMPFILE $TARGETDIR &>> /dev/null
	EXIT_CODE=$?
	if [ $EXIT_CODE -eq 0 ]
		then
			log "File «$TMPFILE» has been successfully copied from «$SERVER» to «$TARGETDIR»;"
	else
		case $EXIT_CODE in
			124)
				log "ERROR: time to copy «$TMPFILE» from «$SERVER» to «$TARGETDIR» exceeded timout limit «$TIMEOUT» seconds. File was NOT copied;"
				;;
			125)
				log "ERROR: timeout itself fails. (scriptline = «$LINENO»);"
				;;
			126)
				log "ERROR: command is found but cannot be invoked. (scriptline = «$LINENO»);"
				;;
			127)
				log "ERROR: command cannot be found. (scriptline = «$LINENO»);"
				;;
			137)
				log "ERROR: command is sent the KILL(9) signal (128+9). (scriptline = «$LINENO»);"
				;;
		esac
			log "ERROR: unknown ERROR occured while trying to copy file «$TMPFILE» from «$SERVER» to «$TARGETDIR». (exitcode = $EXIT_CODE);"
	fi
	
	$SSHSESSION "rm -f $TMPFILE &>> /dev/null"
	EXIT_CODE=$?
	if [ $EXIT_CODE -eq 0 ]
		then
			log "File «$TMPFILE» successfully deleted from «$SERVER»;"
	else
		log "ERROR: failed to delete file «$TMPFILE» from «$SERVER». (exitcode = $EXIT_CODE);"
	fi
done
