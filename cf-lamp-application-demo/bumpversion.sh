#!/bin/bash

function usage()
{
    SCRIPT_NAME=$(basename "$0")
    echo "Seach/replace multiple references of an AMI ID in this project."
    echo "Usage: ./$SCRIPT_NAME [old_ami_id] [new_ami_id]"
    exit 1
}

if [[ "$#" != "2" ]]; then
    usage
fi

if ! [[ "$1" =~ ^ami-[a-z0-9]{8}$ ]]; then
    usage
fi

if ! [[ "$2" =~ ^ami-[a-z0-9]{8}$ ]]; then
    usage
fi

grep -rl $1 . --exclude-dir=.git | xargs --verbose sed -i "s/$1/$2/g"

echo "Done"