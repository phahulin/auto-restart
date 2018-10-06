# Auto Restart
Simple bash script to automatically restart services if they fail too often

## How-to
1. create the following files
```bash
touch ar.conf # optional
touch test-command
touch restart-command
touch notify-command
```
2. when script is started, content of `test-command` file is executed. If it returns non-zero exit code, then under certain conditions, content of `restart-command` file will be executed.
3. restart only happens if 
    * `test-command` failed at least `AR_FAILS_BEFORE_RESTART` times
    * failures happen sufficiently often (of the latest `AR_FAILS_BEFORE_RESTART` failures, the earliest one and the last one are separated by less than `AR_FAILS_MAX_SEP` seconds)
    * latest restart didn't happen too recently (at least `AR_RESTARTS_MIN_SEP` seconds should pass between restarts)
    * `AR_RESTART=1` (it is by default)
4. when all above conditions are met and a restart is triggered, `notify-command` is also executed (unless `AR_NOTIFY=0`)
5. timestamps of failures and restarts are written to `AR_FAILS_LOG` and `AR_RESTARTS_LOG`, these files should be preserved for correct work of the script
6. environment variables can be read from `ar.conf` file if it exists. Full list of env variables and their default values is:
```bash
export AR_DEBUG=0                               # additional logging (0/1)
export AR_SERVICE=$(hostname)                   # name of the service
export AR_LOG=logs/ar.log                       # main log file
export AR_FAILS_LOG=ar-fails                    # log file to store failures
export AR_RESTARTS_LOG=ar-restarts              # log file to store restarts
export AR_EXEC_LOG=logs/ar-exec-out.log         # stdout for *-command. Use /dev/null to ignore output
export AR_EXEC_ERR=logs/ar-exec-err.log         # stderr for *-command. Use /dev/null to ignore output
export AR_FAILS_BEFORE_RESTART=3                # min N of failures to trigger restart
export AR_FAILS_MAX_SEP=300                     # max separation of failures in seconds so that they count as consecutive
export AR_RESTARTS_MIN_SEP=600                  # min number of seconds between two restarts
export AR_TEST_COMMAND_FILE=test-command        # name of the file with test commands
export AR_RESTART_COMMAND_FILE=restart-command  # name of the file with restart command
export AR_NOTIFY_COMMAND_FILE=notify-command    # name of the file with notification command
export AR_RESTART=1                             # switch to quickly enable/disable restarts
export AR_NOTIFY=1                              # switch to quickly enable/disable notifications
```
7. exit code of this script is
    * `0` if test passed
    * `1` if test failed, but restart wasn't triggered
    * `2` if restart was or should have been triggered (depending on values of `AR_RESTART`)
    * `3` if initial validation failed and one of `*-command` files doesn't exist or is empty
8. files in `logs/` subfolder can be rotated freely. `ar-fails` and `ar-restarts` files should be preserved, or at least their tailing lines
