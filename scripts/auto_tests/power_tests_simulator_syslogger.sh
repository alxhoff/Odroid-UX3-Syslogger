#!/bin/bash

# Runs through possible core frequencies and records them with syslogger

DATA_DIR="/data/local/tmp"
RESULT_DIR=$1
TRACE_CONV_DIR="../../trace_conv"
TEST_DUR=4000
SLOT_DUR=100

L_CPUS=(cpu0 cpu1 cpu2 cpu3)
B_CPUS=(cpu4 cpu5 cpu6 cpu7)
UTILS=(0 25 50 75 100)
LITTLE_FREQS=(1000000 1100000 1200000 1300000 1400000)
BIG_FREQS=(1200000 1300000 1400000 1500000 1600000 1700000 1800000 1900000 2000000)
GPU_FREQS=(177 266 350 420 480 543)
COMBOS=($(python get_combos.py | tr -d '[](),'))
COMBO_COUNT=$((${#COMBOS[@]}/4))
TOTAL_TESTS=$((126*14))
COUNT=0

function setGPUFreq {
    adb shell "echo $1 > /sys/devices/11800000.mali/dvfs_max_lock"
    sleep 1
    adb shell "echo $1 > /sys/devices/11800000.mali/dvfs_min_lock"
}

function turnOnBig {
	echo "Turning on BIG CPU"
    sleep 1
	adb shell "echo 1 > /sys/devices/system/cpu/cpu4/online"
	adb shell "echo 1 > /sys/devices/system/cpu/cpu5/online"
	adb shell "echo 1 > /sys/devices/system/cpu/cpu6/online"
	adb shell "echo 1 > /sys/devices/system/cpu/cpu7/online"
}

function turnOffBig {
	echo "Turning off BIG CPU"
    sleep 1
	adb shell "echo 0 > /sys/devices/system/cpu/cpu4/online"
	adb shell "echo 0 > /sys/devices/system/cpu/cpu5/online"
	adb shell "echo 0 > /sys/devices/system/cpu/cpu6/online"
	adb shell "echo 0 > /sys/devices/system/cpu/cpu7/online"
}

function setGov {
	echo "Set governor to userspace"
	adb shell "echo "userspace" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
	adb shell "echo "userspace" > /sys/devices/system/cpu/cpu5/cpufreq/scaling_governor"
	adb shell "echo 1 > /sys/devices/11800000.mali/dvfs_governor"
}

function setCoreFreq {
	echo "Set core $1 to $2:$3"
	adb shell "echo $3 > /sys/devices/system/cpu/$1//cpufreq/scaling_max_freq"
	adb shell "echo $2 > /sys/devices/system/cpu/$1//cpufreq/scaling_min_freq"
}

function setLCPUFreq {
	for core in ${L_CPUS[*]}
	do
		setCoreFreq $core $1 $2
	done
}

function setBCPUFreq {
	for core in ${B_CPUS[*]}
	do
		setCoreFreq $core $1 $2
	done
}

function setupStartSyslogger {
    adb shell ".$DATA_DIR/sys_logger.sh setup -nt"
    adb shell ".$DATA_DIR/sys_logger.sh start"
}

function stopFinishSyslogger {
    adb shell ".$DATA_DIR/sys_logger.sh stop"
    adb shell ".$DATA_DIR/sys_logger.sh finish"
}

function cleanUp {
    rm /tmp/trace.dat
    rm /tmp/trace_out/*
}

function restoreSystem {
    turnOnBig
    setLCPUFreq ${LITTLE_FREQS[0]} ${LITTLE_FREQS[4]}
    setBCPUFreq ${BIG_FREQS[0]} ${BIG_FREQS[8]}
    echo "System restored"
}

function pullConvTraceDat {
    echo "Pulling $DATA_DIR/trace.dat to /tmp/trace.dat"
    adb pull $DATA_DIR/trace.dat /tmp/trace.dat
    echo "Converting trace.dat"
    pushd $TRACE_CONV_DIR
    python2.7 trace_conv.py -i /tmp/trace.dat -o /tmp/trace_out
    wait
    popd
    mv /tmp/trace_out/powerlogger-0.csv $RESULT_DIR/$1.csv
    echo "Moving /tmp/trace_out/powerlogger-0.csv to $RESULT_DIR/$1.csv"
    cleanUp
}

# $1: freq
# $2: true for big

# simulator params
# $3 num of threads
# $4 cores
# $5 duration
# $6 slot duration
# $7 verbose
# $8-15 workloads
function runTest {
    if [ $2 -eq 0 ]
        then
            echo "Little frequency to ${1}"
            setLCPUFreq $1 $1
            FILENAME="little_${1}_$7_$8_$9_${10}"
    else
        echo "Big frequency to ${1}"
        setBCPUFreq $1 $1
        # FILENAME="big_${1}_${11}_${12}_${13}_${14}"
        FILENAME="big_${1}_$7_$8_$9_${10}"
    fi

    setupStartSyslogger
    echo "Syslogger started"
    echo "Starting bigLITTLE simulator with following parameters"
    echo "Running test at ${1} frequency"
    echo "Num of threads: $3"
    echo "Duration: $4"
    echo "Slot Duration: $5"
    echo "Verbose: $6"
    if [ $2 -eq 0 ]
    then
        echo "Cores: LITTLE"
        echo "Workloads: $7 $8 $9 ${10}"
        echo "Running"
        echo "$DATA_DIR/cpuStresstester -d $4 -t $3 -c 0 -c 1 -c 2 -c 3 -w $7 -w $8 -w $9 -w ${10} $6 -s $5"
		# read -p "Press enter to continue"
        adb shell $DATA_DIR/cpuStresstester -d $4 -t $3 -c 0 -c 1 -c 2 -c 3 -w $7 -w $8 -w $9 -w ${10} $6 -s $5
    else
        echo "Cores: big"
        echo "Workloads: $7 $8 $9 ${10} ${11} ${12} ${13} ${14}"
        echo "Running"
        echo "adb shell $DATA_DIR/cpuStresstester -t $3 -c 4 -c 5 -c 6 -c 7 -w $7 -w $8 -w $9 -w ${10} -d $4 -s $5"
        adb shell $DATA_DIR/cpuStresstester -t $3 -c 4 -c 5 -c 6 -c 7 -w $7 -w $8 -w $9 -w ${10} -d $4 -s $5
    fi
    stopFinishSyslogger
    echo "Syslogger stopped"

    pullConvTraceDat $FILENAME
    adb shell rm "$DATA_DIR/trace.dat*"
}

function runGPUTest {
    setGPUFreq $1
    echo "Set gpu frequency to ${1}"

    echo "Running test at ${1} frequency"
	echo "Open app and prepare for test"
	read -p "Press enter to continue"

    FILENAME="gpu_${1}"

    while : ; do

        setupStartSyslogger
        echo "Test started, running for $2 seconds"
        sleep $2
        stopFinishSyslogger

        read -p "Was utilization ok? [y/n] " yn
        case $yn in
            [Yy]* ) pullConvTraceDat $FILENAME; break ;;
            [Nn]* ) adb shell rm "$DATA_DIR/trace.dat*";;
            * ) echo "Please answer y or n.";;
        esac
	done
}

mkdir -p $RESULT_DIR
mkdir -p /tmp/trace_out

restoreSystem
sleep 1

setGov
sleep 1
turnOffBig

echo "Sarting little tests"
for freq in ${LITTLE_FREQS[*]}
do
    turnOffBig
    for (( i=0; i<COMBO_COUNT; i++ ))
    do
        echo "runTest $freq 0 4 $TEST_DUR $SLOT_DUR -v ${COMBOS[$(($i*4))]} ${COMBOS[$(($i*4 + 1))]} ${COMBOS[$(($i*4 + 2))]} ${COMBOS[$(($i*4 + 3))]}"
        runTest $freq 0 4 $TEST_DUR $SLOT_DUR -v ${COMBOS[$(($i*4))]} ${COMBOS[$(($i*4 + 1))]} ${COMBOS[$(($i*4 + 2))]} ${COMBOS[$(($i*4 + 3))]}
        COUNT=$((COUNT+1))
        REMAINING=$((TOTAL_TESTS-COUNT))
        echo "$COUNT tests run, $REMAINING tests left"
    done
done

setLCPUFreq ${LITTLE_FREQS[0]} ${LITTLE_FREQS[0]}
turnOnBig
setGov

echo "starting big tests"
for freq in ${BIG_FREQS[*]}
do
    turnOnBig
    for (( i=0; i<COMBO_COUNT; i++ ))
    do
        echo "runTest $freq 1 4 $TEST_DUR $SLOT_DUR -v ${COMBOS[$(($i*4))]} ${COMBOS[$(($i*4 + 1))]} ${COMBOS[$(($i*4 + 2))]} ${COMBOS[$(($i*4 + 3))]}"
        runTest $freq 1 4 $TEST_DUR $SLOT_DUR -v ${COMBOS[$(($i*4))]} ${COMBOS[$(($i*4 + 1))]} ${COMBOS[$(($i*4 + 2))]} ${COMBOS[$(($i*4 + 3))]}
        COUNT=$((COUNT+1))
        REMAINING=$((TOTAL_TESTS-COUNT))
        echo "$COUNT tests run, $REMAINING tests left"
    done
done

for freq in ${GPU_FREQS[*]}
do
    runGPUTest $freq $TEST_DUR
done

restoreSystem
echo "#####DONE#####"
