#!/usr/bin/env bash

#### required local files
## * test-command
##     - contains script to be executed to test if service works
## * restart-command
##     - contains script to be executed if tests fail
## * notify-command
##     - contains script to be executed on restart
#
#### env variables can be redefined in ar.conf file

set -e
set -u


# read environment from ar.conf file if it exists
AR_CONF="ar.conf"
if [ -f $AR_CONF ]; then
	echo "Reading environment from $AR_CONF"
	set -a
	source "$AR_CONF"
	set +a
fi

# apply defaults
export AR_DEBUG=${AR_DEBUG:-0}
export AR_SERVICE=${AR_SERVICE:-$(hostname)}
export AR_USE_LOCK=${AR_USE_LOCK:-1}
## log files for ar
export AR_LOG=${AR_LOG:-logs/ar.log}
export AR_FAILS_LOG=${AR_FAILS_LOG:-ar-fails}
export AR_RESTARTS_LOG=${AR_RESTARTS_LOG:-ar-restarts}
## log files when executing external tasks
export AR_EXEC_LOG=${AR_EXEC_LOG:-logs/ar-exec-out.log}
export AR_EXEC_ERR=${AR_EXEC_ERR:-logs/ar-exec-err.log}
## consecutive fails to cause a restart
export AR_FAILS_BEFORE_RESTART=${AR_FAILS_BEFORE_RESTART:-3}
## max separation in seconds between fails to still count them as consecutive
export AR_FAILS_MAX_SEP=${AR_FAILS_MAX_SEP:-300}
## min separation in seconds between consecutive restarts
export AR_RESTARTS_MIN_SEP=${AR_RESTARTS_MIN_SEP:-600}
## action functions
export AR_TEST_COMMAND_FILE=${AR_TEST_COMMAND_FILE:-test-command}
export AR_RESTART_COMMAND_FILE=${AR_RESTART_COMMAND_FILE:-restart-command}
export AR_NOTIFY_COMMAND_FILE=${AR_NOTIFY_COMMAND_FILE:-notify-command}
## simple switches
export AR_RESTART=${AR_RESTART:-1}
export AR_NOTIFY=${AR_NOTIFY:-1}


log() {
	echo "$(date -u +%Y-%m-%d"T"%H:%M:%S)" "$AR_SERVICE" "$@" >> $AR_LOG
}

if [ "$AR_DEBUG" -ne "0" ]; then
	dbg() {
		log "$@"
	}
else
	dbg() {
		:
	}
fi

enabled_str() {
	if [ "$1" -ne "0" ]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}


check_file() {
	dbg "Checking file for $2: $1"
	if [ ! -f "$1" ]; then
		log "File for $2 not found: $1"
		log "Exiting"
		exit 3
	fi

	if [ ! -s "$1" ]; then
		log "File for $2 is empty: $1"
		log "Exiting"
		exit 3
	fi
}

execute_file() {
	dbg "Executing $2 from: $1"
	bash "$1" >> $AR_EXEC_LOG 2>>$AR_EXEC_ERR
	echo $?
	log "Executing $2 completed"
}

check_lock() {
	if [ -f .ar.lock ]; then
		log "Lock file already exists, skipping"
		exit 4
	else
		touch .ar.lock
	fi
}


notify() {
	if [ "$AR_NOTIFY" -ne "0" ]; then
		dbg "Send notification"
		execute_file "$AR_NOTIFY_COMMAND_FILE" "notify command" > /dev/null
	else
		log "Do not send notification because AR_NOTIFY is $AR_NOTIFY"
	fi
}

do_restart() {
	echo "$AR_SERVICE" "$(date -u +%s)" "$(date -u +%Y-%m-%d"T"%H:%M:%S)" >>$AR_RESTARTS_LOG
	notify
	if [ "$AR_RESTART" -ne "0" ]; then
		execute_file "$AR_RESTART_COMMAND_FILE" "restart command" > /dev/null
	else
		log "Do not restart because AR_RESTART is $AR_RESTART"
	fi
}

failed() {
	echo "$AR_SERVICE" "$(date -u +%s)" "$(date -u +%Y-%m-%d"T"%H:%M:%S)" >>$AR_FAILS_LOG
	grep "^$AR_SERVICE " "$AR_FAILS_LOG" | tail -n "$AR_FAILS_BEFORE_RESTART" > .ar-last-fails.tmp
	if [ "$(wc -l < .ar-last-fails.tmp)" -lt "$AR_FAILS_BEFORE_RESTART" ]; then
		dbg "Too few fails to trigger a restart (< $AR_FAILS_BEFORE_RESTART)"
		echo 1
	else
		dbg "Check if latest fails are separated by more than $AR_FAILS_MAX_SEP seconds"
		local fail_sep=$(awk '{ if (NR==1) f=$2 } END { print $2-f }' .ar-last-fails.tmp)
		if [ "$fail_sep" -lt "$AR_FAILS_MAX_SEP" ]; then
			dbg "Check if the last restart was too recently"
			touch "$AR_RESTARTS_LOG"
			local last_restart="$(grep "^$AR_SERVICE " "$AR_RESTARTS_LOG" | tail -n 1 | awk '{ print $2 }')"
			if [ -z "$last_restart" ]; then
				last_restart="0"
			fi
			local now_ts="$(date -u +%s)"
			local restart_sep="$(( now_ts - last_restart ))"
			if [ "$restart_sep" -ge "$AR_RESTARTS_MIN_SEP" ]; then
				log "Do restart"
				do_restart
				echo 2
			else
				log "Last restart was too recently ($restart_sep < $AR_RESTARTS_MIN_SEP), do not restart"
				echo 1
			fi
		else
			log "Latest fails are too separated ($fail_sep > $AR_FAILS_MAX_SEP seconds), do not restart"
			echo 1
		fi
	fi
}


main() {
	log "Starting, restarts: $(enabled_str "$AR_RESTART"), notifications: $(enabled_str "$AR_NOTIFY"), use lock: $(enabled_str "$AR_USE_LOCK")"
	check_file "$AR_TEST_COMMAND_FILE" "test_command"
	if [ "$AR_RESTART" -ne "0" ]; then
		check_file "$AR_RESTART_COMMAND_FILE" "restart command"
	fi
	if [ "$AR_NOTIFY" -ne "0" ]; then
		check_file "$AR_NOTIFY_COMMAND_FILE" "notify command"
	fi

	if [ "$AR_USE_LOCK" -ne "0" ]; then
		check_lock
	fi

	local result="$(execute_file $AR_TEST_COMMAND_FILE "test command")"
	local fresult="0"
	dbg "Test command completed, result: $result"
	if [ "$result" -ne "0" ]; then
		log "Test command failed"
		fresult=$(failed)
	else
		log "Test command passed"
	fi
	if [ "$AR_USE_LOCK" -ne "0" ]; then
		rm -f .ar.lock
	fi
	exit $fresult
}

main
