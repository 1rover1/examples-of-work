#!/bin/bash

# Reqirements
#
# You can run this locally if you have the following dependencies installed: jsonlint shellcheck
# E.g.: 
#     apt install jsonlint
#
# https://github.com/koalaman/shellcheck/wiki     for shellcheck doco and error codes

RETURN_CODE=0

FILE_LIST=$(find -name "*.php")
for FILE_NAME in $FILE_LIST; do
    echo -n "${FILE_NAME}: "
    php -l $FILE_NAME > /dev/null
    if [ "$?" -eq "0" ]
    then
        echo -e "\xE2\x9C\x94"
    else
        RETURN_CODE=$?
        echo ""
    fi
done

FILE_LIST=$(find -name "*.json")
for FILE_NAME in $FILE_LIST; do
    echo -n "${FILE_NAME}: "
    jsonlint-php $FILE_NAME > /dev/null
    if [ "$?" -eq "0" ]
    then
        echo -e "\xE2\x9C\x94"
    else
        RETURN_CODE=$?
        echo ""
    fi
done

FILE_LIST=$(find -name "*.sh")
for FILE_NAME in $FILE_LIST; do
    echo -n "${FILE_NAME}: "
    shellcheck --shell=bash --exclude=SC2086 $FILE_NAME
    if [ "$?" -eq "0" ]
    then
        echo -e "\xE2\x9C\x94"
    else
        RETURN_CODE=$?
        echo ""
    fi
done

exit $RETURN_CODE
