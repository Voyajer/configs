#!/bin/bash

# How many seconds to wait before checking temps / setting fan speeds. Lower values mean higher CPU usage.
INTERVAL=3.0

# Set fan speed to 0% if temperature under TEMP[0]
MINSPEED=10

# What fan speed to set at what temperature, for example set the fan speed at 25% when GPU temp is 50 degrees.
# All other values are calculated on the fly, pass the SHOWMAP=true environment variable to show the calculated values.
TEMP[0]=40
SPEED[0]=20

TEMP[1]=60
SPEED[1]=40

TEMP[2]=70
SPEED[2]=60

TEMP[3]=80
SPEED[3]=100

# Show the temp to speed map then exit.
SHOWMAP=${SHOWMAP:-false}

# Show the current speed / temp.
SHOWCURRENT=${SHOWCURRENT:-false}

# This is in case there's some kind of logic flaw in the while loop.
SAFESPEED=${SPEED[1]}

declare -A PAIRS
for PAIR in 0:1 1:2 2:3; do
    LOW=$(echo "$PAIR" | cut -d: -f1)
    HIGH=$(echo "$PAIR" | cut -d: -f2)
    # Due to truncating this is not precise.
    TDIFF0=$(($((${SPEED[$HIGH]} - ${SPEED[$LOW]})) / $((${TEMP[$HIGH]} - ${TEMP[$LOW]}))))
    TDIFF1=$(($TDIFF0 + ${SPEED[$LOW]}))
    for i in $(seq ${TEMP[$LOW]} ${TEMP[$HIGH]}); do
        if [[ $i == ${TEMP[$LOW]} ]]; then
            PAIRS[$i]=${SPEED[$LOW]}
        elif [[ $i == ${TEMP[$HIGH]} ]]; then
            PAIRS[$i]=${SPEED[$HIGH]}
        elif [[ $TDIFF1 -le ${SPEED[$LOW]} ]]; then
            PAIRS[$i]=${SPEED[$LOW]}
        elif [[ $TDIFF1 -ge ${SPEED[$HIGH]} ]]; then
            PAIRS[$i]=${SPEED[$HIGH]}
        else
            PAIRS[$i]=$TDIFF1
        fi
        TDIFF1=$(($TDIFF1 + $TDIFF0))
    done
done

if [[ $SHOWMAP == true ]]; then
    for i in "${!PAIRS[@]}"; do
        echo $i ${PAIRS[$i]}
    done | sort -n
    exit
fi

trap restoreautofans SIGHUP SIGINT SIGQUIT SIGFPE SIGKILL SIGTERM

function restoreautofans() {
    nvidia-settings -a GPUFanControlState=0 1> /dev/null
    exit
}

nvidia-settings -a GPUFanControlState=1 1> /dev/null

while [ true ]; do
    CTEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader --id=0)
    if [[ $CTEMP -lt ${TEMP[0]} ]]; then
        SPEED=$MINSPEED
    elif [[ $CTEMP -ge ${TEMP[3]} ]]; then
        SPEED=${SPEED[3]}
    elif [[ ! -z ${PAIRS[$CTEMP]} ]]; then
        SPEED=${PAIRS[$CTEMP]}
    else
        SPEED=$SAFESPEED
    fi
    if [[ $SHOWCURRENT == true ]]; then
        echo "Current Temp: $CTEMP Speed: $SPEED"
    fi
    nvidia-settings -a GPUTargetFanSpeed=$SPEED 1> /dev/null
    sleep $INTERVAL
done
