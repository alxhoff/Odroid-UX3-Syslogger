#!/bin/bash

print_usage() {
    echo "Usage: $0 -o -d (--auto) (-t)"
    echo ""
    echo "-o,  --out_dir:       Output directory where the results should be stored"
    echo "-d,  --duration:      Duration, in seconds, of each individual test"
    echo "-a,  --auto:          Script will not prompt user to continue between tests"
    echo "-t,  --trace_conv:    Custom location of trace conv"
    echo "-b,  --brezeflow:     Trace BrezeFlow dependencies"
    echo "-gl, --opengl         Trace opengl"
    echo "-tr, --threads        Trace threads"
}

if [ "$#" -lt 2 ]; then
    echo "ERROR: Illegal number of parameters"
    print_usage
    exit 1
fi

DATA_DIR="/data/local/tmp"
TRACE_CONV_DIR="../../trace_conv"
TRACE_BREZE=0
TRACE_THREADS=0
TRACE_OPENGL=0

while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        -o|--out_dir)
            shift
            RESULT_DIR=$1
            shift
            ;;
        -d|--duration)
            shift
            TEST_DUR=$1
            shift
            ;;
        -a|--auto)
            AUTO_TEST=1
            shift
            ;;
        -t|--trace_conv)
            shift
            TRACE_CONV_DIR=$1
            shift
            ;;
        -b|--brezeflow)
            TRACE_BREZE=1
            shift
            ;;
        -gl|--opengl)
            TRACE_OPENGL=1
            shift
            ;;
        -tr|--threads)
            TRACE_THREADS=1
            shift
            ;;
        *)
            print_usage
            exit 1
    esac
done

SYSLOG_PARAMS=""

if [ $TRACE_BREZE -eq 0 ]; then
    SYSLOG_PARAMS="-nb"
fi

if [ $TRACE_OPENGL -eq 0 ]; then
    SYSLOG_PARAMS="${SYSLOG_PARAMS} -nogl"
fi

if [ $TRACE_THREADS -eq 0 ]; then
    SYSLOG_PARAMS="${SYSLOG_PARAMS} -nt"
fi

echo "Syslogger params: $SYSLOG_PARAMS"

L_CPUS=(cpu0 cpu1 cpu2 cpu3)
B_CPUS=(cpu4 cpu5 cpu6 cpu7)
LITTLE_FREQS=(1000000 1100000 1200000 1300000 1400000)
BIG_FREQS=(1200000 1300000 1400000 1500000 1600000 1700000 1800000 1900000 2000000)
GPU_FREQS=(177 266 350 420 480 543)

function turnOnBig {
	echo "Turning on BIG CPU"
    sleep 1
	adb shell "echo 1 > /sys/devices/system/cpu/cpu4/online"
    wait
	adb shell "echo 1 > /sys/devices/system/cpu/cpu5/online"
    wait
	adb shell "echo 1 > /sys/devices/system/cpu/cpu6/online"
    wait
	adb shell "echo 1 > /sys/devices/system/cpu/cpu7/online"
    wait
}

function turnOffBig {
	echo "Turning off BIG CPU"
    sleep 1
	adb shell "echo 0 > /sys/devices/system/cpu/cpu4/online"
    wait
	adb shell "echo 0 > /sys/devices/system/cpu/cpu5/online"
    wait
	adb shell "echo 0 > /sys/devices/system/cpu/cpu6/online"
    wait
	adb shell "echo 0 > /sys/devices/system/cpu/cpu7/online"
    wait
}

function setGov {
	echo "Set governor to userspace"
	adb shell "echo "userspace" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    wait
	adb shell "echo "userspace" > /sys/devices/system/cpu/cpu5/cpufreq/scaling_governor"
    wait
	adb shell "echo 1 > /sys/devices/11800000.mali/dvfs_governor"
    wait
}

function setCoreFreq {
	echo "Set core $1 to $2:$3"
	adb shell "echo $3 > /sys/devices/system/cpu/$1//cpufreq/scaling_max_freq"
    wait
	adb shell "echo $2 > /sys/devices/system/cpu/$1//cpufreq/scaling_min_freq"
    wait
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

function setGPUFreq {
    adb shell "echo $1 > /sys/devices/11800000.mali/dvfs_max_lock"
    wait
    adb shell "echo $1 > /sys/devices/11800000.mali/dvfs_min_lock"
    wait
    echo "Set GPU to $1:$1"
}

function setupStartSyslogger {
    adb shell ".$DATA_DIR/sys_logger.sh setup -r $SYSLOG_PARAMS"
    wait
    adb shell ".$DATA_DIR/sys_logger.sh start"
    wait
}

function stopFinishSyslogger {
    adb shell ".$DATA_DIR/sys_logger.sh stop"
    wait
    adb shell ".$DATA_DIR/sys_logger.sh finish -r -nr"
    wait
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
    wait
    sleep 2
    echo "Converting trace.dat"
    pushd $TRACE_CONV_DIR
    python2.7 trace_conv.py -i /tmp/trace.dat -o /tmp/trace_out &>/dev/null
    wait
    popd
    sleep 2
    cp /tmp/trace_out/powerlogger-0.csv $RESULT_DIR/power_$1.csv
    cp /tmp/trace_out/framelogger-0.csv $RESULT_DIR/frame_$1.csv
    wait
    echo "Moving /tmp/trace_out/powerlogger-0.csv to $RESULT_DIR/$1.csv"
    cleanUp
}

# $1: little freq
# $2: big freq
# $3: gpu freq
function runTest {
    echo "########## STARTING TEST $1 $2 $3 ##########"
    setLCPUFreq $1 $1
    FILENAME="${1}"

    if [ ! -z "$2" ]
        then
        turnOnBig
        setBCPUFreq $2 $2
        FILENAME="${FILENAME}_${2}"
    else
        turnOffBig
        FILENAME="${FILENAME}_0"
    fi

    if [ ! -z "$3" ]
        then
        setGPUFreq $3
        FILENAME="${FILENAME}_$3"
    else
        FILENAME="${FILENAME}_X"
    fi

    sleep 1

	echo "Open app and prepare for test"

    if [ -z "$AUTO_TEST" ]; then
	    read -p "Press enter to continue"
    fi

    while : ; do
        setupStartSyslogger
        sleep $TEST_DUR
        stopFinishSyslogger

        if [ ! "$AUTO_TEST" -eq 1 ]; then
            read -p "Was utilization ok? [y/n] " yn
            case $yn in
                [Yy]* ) pullConvTraceDat $FILENAME; break ;;
                [Nn]* ) adb shell rm "$DATA_DIR/trace.dat*";;
                * ) echo "Please answer y or n.";;
            esac
        else
            pullConvTraceDat $FILENAME
            wait
            break
        fi
	done

    echo "######### TEST FINISHED ##########"
}

mkdir -p $RESULT_DIR
mkdir -p /tmp/trace_out

restoreSystem
setGov

echo "##############"
echo "Starting tests"
echo "##############"

for l_freq in ${LITTLE_FREQS[*]}
do
    for b_freq in ${BIG_FREQS[*]}
    do
        for g_freq in ${GPU_FREQS[*]}
        do
            runTest $l_freq $b_freq $g_freq
        done
    done
done

restoreSystem

echo "#####DONE#####"
