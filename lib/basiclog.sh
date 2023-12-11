#!/bin/bash

declare -a LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="crit" [3]="err" [4]="warning" [5]="notice" [6]="info" [7]="debug")
declare VOLUME_INEXISTS=10
declare VOLUME_OK=0
declare VOLUME_DIVERGENT=20
export VOLUME_INEXISTS
export VOLUME_OK
export VOLUME_DIVERGENT

#todo:lib: Put initialization process, aka log path and rotation. Export pertinent data after this
if [ -z "$APP_LOG_FILE" ]; then
	echo "The variable APP_LOG_FILE is null."
	DEFAULT_LOG_FILE="/tmp/patriot/logs/$(date +'%Y%m%d').log"
	if [ -e "$DEFAULT_LOG_FILE" ]; then
		echo "The default log file already exists: $DEFAULT_LOG_FILE"
	else
		echo "Forcing default log file: $DEFAULT_LOG_FILE"
	fi
	APP_LOG_FILE="$DEFAULT_LOG_FILE"
else
	echo "The variable APP_LOG_FILE is not null."
	if [ -e "$APP_LOG_FILE" ]; then
		echo "The log file exists: $APP_LOG_FILE"
	else
		echo "The log file does not exist: $APP_LOG_FILE"
		DEFAULT_LOG_FILE="/tmp/patriot/logs/$(date +'%Y%m%d')"
		echo "Forcing default log file: $DEFAULT_LOG_FILE"
		APP_LOG_FILE="$DEFAULT_LOG_FILE"
	fi
fi

# Ensure log file exists
LOG_DIR=$(dirname "$APP_LOG_FILE")
mkdir -p "$LOG_DIR"
touch "$APP_LOG_FILE"

#Globals for log
export APP_LOG_FILE
export APP_VERBOSE_LEVEL=10  #Highest level of verbosity

function slog() {
	#rotina de registro de logs
	local LEVEL="$1"
	shift
	if [[ ${APP_VERBOSE_LEVEL} -ge ${LEVEL} ]]; then
		if [ -t 0 ]; then
			echo "[${LOG_LEVELS[$LEVEL]}]" "$@" | tee -a "$APP_LOG_FILE"
		else
			if [[ $1 ]]; then
				echo "[${LOG_LEVELS[$LEVEL]}] $1" | tee -a "$APP_LOG_FILE"
			else
				echo "[${LOG_LEVELS[$LEVEL]}] $(cat)" | tee -a "$APP_LOG_FILE"
			fi
		fi
	fi
}
