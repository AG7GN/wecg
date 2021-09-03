#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv] [left|right [frequency]]
#%
#% DESCRIPTION
#%   This script starts the FL apps (Fldigi, Flmsg) on WECG
#%   managed Raspberry Pis. It will check if the ax25 and rmsgw
#%   and dw_aprs_gui.sh apps are running, and stop them if they
#%   are running prior to starting the FL apps.
#%
#% OPTIONS
#%    -h, --help                  Print this help
#%    -v, --version               Print script information
#%
#================================================================
#- IMPLEMENTATION
#-    version         ${SCRIPT_NAME} 1.0.3
#-    author          Steve Magnuson, AG7GN
#-    license         CC-BY-SA Creative Commons License
#-    script_id       0
#-
#================================================================
#  HISTORY
#     20200814 : Steve Magnuson : Script creation.
# 
#================================================================
#  DEBUG OPTION
#    set -n  # Uncomment to check your syntax, without execution.
#    set -x  # Uncomment to debug this shell script
#
#================================================================
# END_OF_HEADER
#================================================================

SYNTAX=false
DEBUG=false
Optnum=$#

#============================
#  FUNCTIONS
#============================

function TrapCleanup() {
   [[ -d "${TMPDIR}" ]] && rm -rf "${TMPDIR}/"
   for P in ${YAD_PIDs[@]}
	do
		kill $P >/dev/null 2>&1
	done
   rm -f $PIPE
}

function SafeExit() {
   trap - INT TERM EXIT SIGINT
	TrapCleanup
   exit 0
}

function ScriptInfo() { 
	HEAD_FILTER="^#-"
	[[ "$1" = "usage" ]] && HEAD_FILTER="^#+"
	[[ "$1" = "full" ]] && HEAD_FILTER="^#[%+]"
	[[ "$1" = "version" ]] && HEAD_FILTER="^#-"
	head -${SCRIPT_HEADSIZE:-99} ${0} | grep -e "${HEAD_FILTER}" | \
	sed -e "s/${HEAD_FILTER}//g" \
	    -e "s/\${SCRIPT_NAME}/${SCRIPT_NAME}/g" \
	    -e "s/\${SPEED}/${SPEED}/g" \
	    -e "s/\${DEFAULT_PORTSTRING}/${DEFAULT_PORTSTRING}/g"
}

function Usage() { 
	printf "Usage: "
	ScriptInfo usage
	exit
}

function Die () {
	echo "${*}"
	SafeExit
}

#============================
#  FILES AND VARIABLES
#============================

# Set Temp Directory
# -----------------------------------
# Create temp directory with three random numbers and the process ID
# in the name.  This directory is removed automatically at exit.
# -----------------------------------
TMPDIR="/tmp/${SCRIPT_NAME}.$RANDOM.$RANDOM.$RANDOM.$$"
(umask 077 && mkdir "${TMPDIR}") || {
  Die "Could not create temporary directory! Exiting."
}

  #== general variables ==#
SCRIPT_NAME="$(basename ${0})" # scriptname without path
SCRIPT_DIR="$( cd $(dirname "$0") && pwd )" # script directory
SCRIPT_FULLPATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
SCRIPT_ID="$(ScriptInfo | grep script_id | tr -s ' ' | cut -d' ' -f3)"
SCRIPT_HEADSIZE=$(grep -sn "^# END_OF_HEADER" ${0} | head -1 | cut -f1 -d:)
VERSION="$(ScriptInfo version | grep version | tr -s ' ' | cut -d' ' -f 4)" 
RIG_MODEL=1022 # Yaesu FT-857
RIG_SPEED=38400
RIG_PORT=/dev/yaesu

TITLE="Start Fldigi and Flmsg $VERSION"

PIPE=$TMPDIR/pipe
mkfifo $PIPE
exec 8<> $PIPE

#============================
#  PARSE OPTIONS WITH GETOPTS
#============================
  
#== set short options ==#
SCRIPT_OPTS=':r:hv-:'

#== set long options associated with short one ==#
typeset -A ARRAY_OPTS
ARRAY_OPTS=(
	[help]=h
	[version]=v
)

LONG_OPTS="^($(echo "${!ARRAY_OPTS[@]}" | tr ' ' '|'))="

# Parse options
while getopts ${SCRIPT_OPTS} OPTION
do
	# Translate long options to short
	if [[ "x$OPTION" == "x-" ]]
	then
		LONG_OPTION=$OPTARG
		LONG_OPTARG=$(echo $LONG_OPTION | egrep "$LONG_OPTS" | cut -d'=' -f2-)
		LONG_OPTIND=-1
		[[ "x$LONG_OPTARG" = "x" ]] && LONG_OPTIND=$OPTIND || LONG_OPTION=$(echo $OPTARG | cut -d'=' -f1)
		[[ $LONG_OPTIND -ne -1 ]] && eval LONG_OPTARG="\$$LONG_OPTIND"
		OPTION=${ARRAY_OPTS[$LONG_OPTION]}
		[[ "x$OPTION" = "x" ]] &&  OPTION="?" OPTARG="-$LONG_OPTION"
		
		if [[ $( echo "${SCRIPT_OPTS}" | grep -c "${OPTION}:" ) -eq 1 ]]; then
			if [[ "x${LONG_OPTARG}" = "x" ]] || [[ "${LONG_OPTARG}" = -* ]]; then 
				OPTION=":" OPTARG="-$LONG_OPTION"
			else
				OPTARG="$LONG_OPTARG";
				if [[ $LONG_OPTIND -ne -1 ]]; then
					[[ $OPTIND -le $Optnum ]] && OPTIND=$(( $OPTIND+1 ))
					shift $OPTIND
					OPTIND=1
				fi
			fi
		fi
	fi

	# Options followed by another option instead of argument
	if [[ "x${OPTION}" != "x:" ]] && [[ "x${OPTION}" != "x?" ]] && [[ "${OPTARG}" = -* ]]; then 
		OPTARG="$OPTION" OPTION=":"
	fi

	# Finally, manage options
	case "$OPTION" in
		h) 
			ScriptInfo full
			exit 0
			;;
		v) 
			ScriptInfo version
			exit 0
			;;
		r) 
			RIG=${OPTARG^^:-KENWOOD}
			;;
		:) 
			Die "${SCRIPT_NAME}: -$OPTARG: option requires an argument"
			;;
		?) 
			Die "${SCRIPT_NAME}: -$OPTARG: unknown option"
			;;
	esac
done
shift $((${OPTIND} - 1)) ## shift options

#============================
#  MAIN SCRIPT
#============================

# Trap bad exits with cleanup function
trap SafeExit EXIT INT TERM

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

YAD_PIDs=()

case ${1,,} in
	left)
		SIDE="-left"
		;;
	right)
		SIDE="-right"
		;;
	*)
		SIDE=""
		;;
esac


if ! pgrep fldigi >/dev/null && ! pgrep flrig >/dev/null
then
	yad --on-top --back=black --fore=yellow --selectable-labels --width=400 --height=550 \
		--text-info --text-align=center --title="$TITLE" \
		--tail --center --no-buttons <&8 &
	YAD_PIDs+=( $! )
	if systemctl | grep running | grep -q ax25.service
	then # ax25 is running.  Stop it so we can run Fldigi.
		echo "Stopping rmsgw..." >&8
		sudo systemctl stop ax25
		echo "rmsgw stopped." >&8
	fi
	if pgrep -if ".*yad.*Log Viewer.*following.*" >/dev/null
	then
		echo "Stopping RMSGW Log Viewer..." >&8
		pkill -SIGTERM -if ".*yad.*Log Viewer.*following.*"
		echo "RMSGW Log Viewer stopped." >&8
	fi
	if pgrep -if ".*yad.*Direwolf APRS Monitor and Configuration.*" >/dev/null
	then
		echo "Stopping APRS..." >&8
		pkill -SIGTERM -if ".*Direwolf APRS Monitor and Configuration.*"
		echo "APRS stopped." >&8
	fi
	echo "Trimming FSQ logs..." >&8
	/usr/local/bin/trim-fsq-audit.sh "now"
	/usr/local/bin/trim-fsq-heard.sh "now"
	#echo "Trimming FLDigi logs..." >&8
	#/usr/local/bin/trim-fldigi-log.sh "1 week ago"
	echo "Logs trimmed." >&8
	if [ ! -z "$2" ]
	then # Frequency has been specified
		RE="^[0-9]+([.][0-9]+)?$"
		if [[ $2 =~ $RE ]]
		then # Supplied frequency is a number
			case $RIG in
				KENWOOD)
					if ! pgrep -f 710.py >/dev/null 2>&1
					then
						if $(command -v 710.sh) >/dev/null 2>&1
						then # 710.sh script is installed, so change to the desired frequency
							echo -e "\nQSY to $2, standby...\n" >&8
							$(command -v 710.sh) set b freq $2 >&8
						fi
					else  # 710.py is running. Disable RigCAT in FLdigi
						echo -e "\n710.py already running.\nFrequency will not be changed\n" >&8
						# Disable RigCAT if necessary, because 710.py is running.
						RIGCAT="$(grep -o -P '(?<=<CHKUSERIGCATIS>).*(?=<\/CHKUSERIGCATIS>)' \
						$HOME/.fldigi$SIDE/fldigi_def.xml)"
						if [[ $RIGCAT == "1" ]]
						then
							echo -e "\nRigCAT enabled in FLdigi. Disabling it.\n" >&8
							sed -i -e \
						's/<CHKUSERIGCATIS>1<\/CHKUSERIGCATIS>/<CHKUSERIGCATIS>0<\/CHKUSERIGCATIS>/' $HOME/.fldigi$SIDE/fldigi_def.xml
							echo "RIGCAT=$RIGCAT" > $HOME/.fldigi$SIDE/fldigi_def.rigcat
						fi
					fi
					echo >&8
					;;
				YAESU)
					if $(command -v yaesu_power.sh) &>/dev/null
					then
						echo -e "\nPowering on $RIG, standby...\n" >&8
						yaesu_power.sh on >&8
						echo -e "\nQSY to $2, standby...\n" >&8
						rigctl -m $RIG_MODEL -s $RIG_SPEED -r $RIG_PORT F $(printf "%d" $(bc <<< $2*1000000)) >&8
					fi
					echo >&8
					;;
				*)
					echo -e "Unknown rig" >&8
					;;
			esac
		fi
	fi
	gtk-launch fldigi$SIDE.desktop >/dev/null 2>&1 &
	echo "Fldigi started." >&8
fi

#if ! pgrep flrig >/dev/null
#then
#	/usr/local/bin/trim-flrig-log.sh "yesterday"
#	flrig --debug-level 0 &
#fi

if ! pgrep flmsg >/dev/null
then
	START_FILE="$HOME/.nbems$SIDE/ICS/messages/W7ECG-ClosingComments.213"
	touch -m $START_FILE
	#echo "Trimming FLmsg logs..." >&8
	#/usr/local/bin/trim-flmsg-log.sh "1 month ago"
	#echo "Logs trimmed." >&8
	VER="$(flmsg --version | cut -d" " -f2)"
	# Open flmsg with $START_FILE, which will also open it in a browser...
	#flmsg --b $START_FILE -ti "Flmsg $VER" -g 700x600+1220+70 &
	gtk-launch flmsg$SIDE.desktop >/dev/null 2>&1 &
	echo "Flmsg started." >&8
	sleep 4
	# ...kill the browser
	pkill -f "chromium.*$(basename -- $START_FILE .213)"
fi
echo "This window will close in 5 seconds." >&8
sleep 5
SafeExit

