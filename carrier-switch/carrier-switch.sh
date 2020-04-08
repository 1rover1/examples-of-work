#!/bin/bash

SCRIPT_PATH="$(dirname $(which $0))/"

# database configuration
source ${SCRIPT_PATH}switch.conf

# Checks parameters
if [ $# -ne 2 ] || [ ! -e "${SCRIPT_PATH}definitions/$1" ] || [[ ! "$2" =~ ^(enable|disable|lock|unlock)$ ]]
then
    echo "usage : $0 [carrier definition] [action]"
    echo ""
    echo "[carrier definition] is a file listed in the 'definitions' directory. It contains a SQL which returns"
    echo "         a comma separated list of CARRIER_ACCOUNT.ID values. Each CARRIER_ACCOUNT must have LOCKED=N."
    echo ""
    echo "[action] can be any of the following:"
    echo "         lock      - Stop the carrier account from making bookings"
    echo "         disable   - alias of lock"
    echo "         unlock    - Allow the carrier account from making bookings"
    echo "         enable    - alias of unlock"
    echo ""
    exit 1
fi

LOCKED_ACCOUNTS_FILE="${SCRIPT_PATH}lock-$1.lock"
LOG_FILE="${SCRIPT_PATH}switch.log"

# Update Carrier Account LOCKED value
function set_lock_status {

    NEW_STATUS=$1
    ID_LIST=$2

    # Check data
    if ! [[ "$NEW_STATUS" =~ ^(Y|N)$ ]]
    then
        echo "Error: Invalid lock value of '$NEW_STATUS' submitted"
        exit 1
    fi

    if ! [[ "$ID_LIST" =~ ^[0-9,]+$ ]]
    then
        echo "Error: Invalid ID list of '$ID_LIST' submitted"
        exit 1
    fi

    # SQL to enable/disable Courier Post
    SQL="UPDATE CARRIER_ACCOUNT SET LOCKED='$NEW_STATUS' WHERE ID IN ($ID_LIST)"

    echo "$(date +%Y-%m-%d_%H:%M:%S) Carrier=$3 Setting LOCKED=$NEW_STATUS for ID=$ID_LIST " >> $LOG_FILE 
    
    # Run SQL query 
    MYSQL_PWD=${MYSQL_PASS} mysql -u ${MYSQL_USER} -h ${MYSQL_HOST} ${MYSQL_DATABASE} -e "$SQL" >> $LOG_FILE 
}

# Checks if the script is to enable or disable
if [[ "$2" =~ ^(disable|lock)$ ]]
then
        # Fetch the Carrier Account ID's that are currently enabled
        SQL=$( cat ${SCRIPT_PATH}definitions/$1 )

        CARRIER_ACCOUNTS=`MYSQL_PWD=${MYSQL_PASS} mysql -u ${MYSQL_USER} -h ${MYSQL_HOST} ${MYSQL_DATABASE} -e "$SQL" --batch --skip-column-names`

        if ! [[ "$CARRIER_ACCOUNTS" =~ ^[0-9,]+$ ]]
        then
            echo "Error: wasn't able to get a list of unlocked carrier accounts"
            exit 1
        fi

        echo $CARRIER_ACCOUNTS > $LOCKED_ACCOUNTS_FILE

        # Set LOCKED=Y for accounts
        set_lock_status Y $CARRIER_ACCOUNTS $1

elif [[ "$2" =~ ^(enable|unlock)$ ]]
then
        # Get list of affected accounts
        CARRIER_ACCOUNTS=`cat $LOCKED_ACCOUNTS_FILE`

        if ! [[ "$CARRIER_ACCOUNTS" =~ ^[0-9,]+$ ]]
        then
            echo "Error: unable to retrieve list of locked accounts"
            exit 1
        fi

        # Set LOCKED=N for accounts
        set_lock_status N $CARRIER_ACCOUNTS $1

        rm $LOCKED_ACCOUNTS_FILE

fi
