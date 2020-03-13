#!/bin/bash
# @file android_runStresstest.sh
# @AUTHOR Tobias Fuchs (ga76zem)
# @DATE 30.07.2016
# @brief stresstest script to be run on odroid board.
#
# Version  Date       Changes
# 0.1      30.07.16   Added file
# vim: foldmethod=marker

if [ ! -e /data/local/tmp/powerLogger.android ]; then
    echo "powerLogger is not installed. Install powerLogger first!";
    return 1;
fi

usage() # {{{
{
    echo ""
    echo "usage: android_runStresstest.sh  --duration     | -d   <ms> "
    echo "                                 --cores        | -c   <core> (FOR NOW ONLY ONE CORE AT A TIME;"
    echo "                                                               DEFINE MULTIPLE CORES WITH [..] -c <core1> -c <core2> ...)"
    echo "                                 --workload     | -w   <workload> (SAME AS ABOVE)"
    echo "                                 --threads      | -t   <num threads> "
    echo "                                 --verbose      | -v "
    echo "                                 --slotDuration | -s <ms>"
} #}}}

FIFO_SETUP_CMD=1
FIFO_START_CMD=2
FIFO_STOPP_CMD=3

# parse arguments {{{
T=0
C=0
W=0
D=0
S=0

while [ "$1" != "" ]; do
    case $1 in
        -t | --threads)     shift
                            NUM_THREADS=$1
                            T=1
                            ;;
        -c | --cores )      shift
                            CORES+=" $1 ";
                            C=1
                            ;;
        -w | --workload )   shift
                            WORKLOADS+=" $1 "
                            W=1
                            ;;
        -d | --duration )	shift
                            DURATION=$1
                            D=1
                            ;;
        -s | --slotDuration ) shift
                            SLOTDURATION=$1
                            S=1
                            ;;
        -v | --verbose )    VERBOSE="-v"
                            ;;
        * )  			    echo "runStresstest: Unrecognized option $1"
                            echo $CORES
                            usage
                            exit
                            ;;
    esac
    shift
done

if [ $T -eq 0 ] || [ $C -eq 0 ] || [ $W -eq 0 ] || [ $D -eq 0 ] || [ $S -eq 0 ];
then
    usage
    exit
fi
# }}}

# set to userspace if not already is {{{
GOV0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
GOV4=$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor)
if [ GOV0 != "userspace" ]; then
    echo "userspace" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor;
fi
if [ GOV4 != "userspace" ]; then
    echo "userspace" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor;
fi
echo "set governor to userspace"
# }}}

echo "clearing workspace (deleting old logfiles)"
# clear data and start logging {{{
rm -f /data/local/tmp/meas.log
rm -f /data/local/tmp/history.log
touch /data/local/tmp/meas.log
touch /data/local/tmp/history.log
chmod 777 /data/local/tmp/meas.log
chmod 777 /data/local/tmp/history.log
taskset 0F /data/local/tmp/powerLogger.android &
sleep 1
chmod 777 /data/local/tmp/myFifo
# }}}
echo "all setup, start logging"

/data/local/tmp/log/fifoSendCmd $FIFO_SETUP_CMD
/data/local/tmp/log/fifoSendCmd $FIFO_START_CMD
echo "start stressing"

echo "/data/local/tmp/cpuStresstester -t $NUM_THREADS -c $CORES -w $WORKLOADS -d $DURATION $VERBOSE -s $SLOTDURATION"
#/data/local/tmp/cpuStresstester -t $NUM_THREADS -c $CORES -w $WORKLOADS -d $DURATION $VERBOSE -s $SLOTDURATION
/data/local/tmp/android_executable -t $NUM_THREADS -c $CORES -w $WORKLOADS -d $DURATION $VERBOSE -s $SLOTDURATION

/data/local/tmp/log/fifoSendCmd $FIFO_STOPP_CMD

echo "finished stressing, cleaning up"
/data/local/tmp/log/terminateLogger
