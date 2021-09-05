#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+   ${SCRIPT_NAME} [-hv] [rmsgw|aprs [left|right [frequency]]]
#%
#% DESCRIPTION
#%   This script stops the FL apps (Fldigi, Flrig, Flmsg) on WECG
#%   managed Raspberry Pis, and optionally restarts the "default"
#%   app on those Pis. Usually it's rmsgw or aprs.
#%
#% OPTIONS
#%    -h, --help        	Print this help
#%    -v, --version     	Print script information
#%
#% COMMANDS (optional)
#%    rmsgw|aprs [frequency]	If you specify rmsgw, the ax25 and 
#%                            rmsgw gateway services will 
#%										(re)start when the FL apps stop. 
#%										If you specify aprs, the 
#%										dw_aprs_gui.sh will (re)start when 
#%										the FL apps are stopped. In each 
#%										case, you can optionally also 
#%										supply a frequency in MHz. If the
#%										710.sh script is installed, it will
#%										attempt to QSY to the supplied
#%										frequency prior to restarting rmsgw
#%										or aprs. 
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

function restoreApp () {
	# Takes 2 arguments: 
	#   $1: App to restore rmsgw|aprs
	#   $2: Frequency as a floating point number (MHz)
	
	RE="^[0-9]+([.][0-9]+)?$"
	if [[ $2 =~ $RE ]]
	then # Supplied frequency is a number
		case $RIG in
			KENDWOOD)
				if ! pgrep -f 710.py >/dev/null 2>&1
				then  # 710.py not running. Use 710.sh to change frequency
					if $(command -v 710.sh) >/dev/null 2>&1
					then # 710.sh script is installed, so change to the desired frequency
						echo -e "\nQSY to $2, standby...\n" >$PIPEDATA
						$(command -v 710.sh) set b freq $2 >$PIPEDATA 
					fi
				else  # 710.py running. Disable RigCAT in fldigi and continue using 710.py instead
					echo -e "\n710.py already running.\nFrequency will not be changed.\n" >$PIPEDATA
				fi
				# Re-enable RigCAT if it was running when the start script ran.
				if [[ -s $HOME/.fldigi$SIDE/fldigi_def.rigcat ]]  # RigCAT was previously enabled
				then  # Re-enable it
					echo -e "\nRe-enabling RigCAT in FLdigi\n" >$PIPEDATA
					sed -i -e \
					  's/<CHKUSERIGCATIS>0<\/CHKUSERIGCATIS>/<CHKUSERIGCATIS>1<\/CHKUSERIGCATIS>/' $HOME/.fldigi$SIDE/fldigi_def.xml
					rm -f $HOME/.fldigi$SIDE/fldigi_def.rigcat
				fi
				echo >$PIPEDATA
				;;
			YAESU)
				killall flrig >$PIPEDATA
				echo -e "\nQSY to $2, standby...\n" >$PIPEDATA
				rigctl -m $RIG_MODEL -s $RIG_SPEED -r $RIG_PORT F $(printf "%d" $(bc <<< $2*1000000)) >$PIPEDATA
				echo -e "\nPowering off $RIG, standby...\n" >$PIPEDATA
				yaesu_power.sh off >$PIPEDATA
				echo >&8
				;;
			*)
				echo -e "Unknown rig" >$PIPEDATA
				;;
		esac
	fi
	
	case ${1,,} in
		rmsgw)
			if ! pgrep -if ".*yad.*Log Viewer.*following.*" >/dev/null
			then
				echo "Starting RMSGW Log Viewer..." >$PIPEDATA 
				gtk-launch rmsgw_monitor.desktop >/dev/null 2>&1 &
				echo "RMSGW Log Viewer started." >$PIPEDATA 
			fi
			if ! systemctl | grep running | grep -q ax25.service
			then # Start ax25 if it's not already running 
				echo "Starting rmsgw..." >$PIPEDATA
				sudo systemctl start ax25 >$PIPEDATA
				echo "rmsgw started." >$PIPEDATA 
			fi
			;;
		aprs)
			echo "Starting APRS..." >$PIPEDATA 
			gtk-launch dw_aprs_gui.desktop >/dev/null 2>&1 &
			echo "APRS started." >$PIPEDATA 
			;;
		*)
			;;
	esac
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

TITLE="Stop Fldigi and Flmsg $VERSION"

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

[ -z "$1" ] && APP="" || APP="$1"
case ${2,,} in
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
[ -z "$3" ] && FREQ="" || FREQ="$3"
export -f restoreApp
export restoreApp_cmd="bash -c 'restoreApp $APP $FREQ'"
export PIPEDATA=$PIPE

#============================
#  MAIN SCRIPT
#============================

# Trap bad exits with cleanup function
trap SafeExit EXIT INT TERM

# Exit on error. Append '||true' when you run the script if you expect an error.
#set -o errexit

# Check Syntax if set
$SYNTAX && set -n
# Run in debug mode, if set
$DEBUG && set -x 

YAD_PIDs=()


yad --on-top --back=black --fore=yellow --selectable-labels --width=400 --height=550 \
	--text-info --text-align=center --title="$TITLE" \
	--tail --center --no-buttons <&8 &
YAD_PIDs+=( $! )

echo "Stopping FLmsg..." >&8
pkill -SIGTERM flmsg
echo "FLmsg stopped" >&8
echo "Stopping FLdigi..." >&8
if pgrep fldigi >/dev/null
then
	pkill -SIGTERM fldigi
fi
echo "FLdigi stopped" >&8
pkill -SIGTERM flrig

#yad --on-top --back=black --fore=yellow --selectable-labels --width=350 --height=550 \
#	--text-info --text-align=center --title="$TITLE" --tail --center \
#	--buttons-layout=center --button="<b>Exit</b>":1 --button="<b>Restart ${1^^} &#x26; #Exit</b>":"$restoreApp_cmd" <&8

[ -z $APP ] || restoreApp $APP $FREQ
echo "This window will close in 5 seconds." >&8
sleep 5
SafeExit


