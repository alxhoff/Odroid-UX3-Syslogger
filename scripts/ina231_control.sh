#!/bin/bash

INA_DIRS[0]=/sys/devices/12c60000.i2c/i2c-4/4-0040
INA_DIRS[1]=/sys/devices/12c60000.i2c/i2c-4/4-0041
INA_DIRS[2]=/sys/devices/12c60000.i2c/i2c-4/4-0044
INA_DIRS[3]=/sys/devices/12c60000.i2c/i2c-4/4-0045

INA_CTS="$(adb shell cat ${INA_DIRS[0]}/available_ct)"

VB=0
VSH=0
AVG=0

print_usage() {
    echo "Usage: $0 (-v) [setup (-cg) (-nt) (-nb) (-nogl) (-i) | start | stop | finish (-nr)]"
    echo ""
    echo "-vb           Do not trace binder {binder_transaction, cpu_idle, sched_switch}"
    echo "-vsh          Do not trace OpenGL {sys_logger:opengl_frame}"
    echo "-a            Syslogger logging interval, default = 5ms"
}


while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -vb)
        shift
        VB=$1
        shift # past argument
        ;;
    -vsh)
        shift
        VSH=$1
        shift # past argument
        ;;
    -a)
        shift
        AVG=$1
        shift
        ;;
    *)
        print_usage
        exit 1
        ;;
    esac
done

echo "Vbus CT given as ${VB}, Vshunt as ${VSH} with ${AVG} averages"

if [ "$VB" -eq 0 ] || [ "$VSH" -eq 0 ] || [ "$AVG" -eq 0 ]; then
    echo "Not all required arguments given"
    exit 1
fi

for INA in "${INA_DIRS[@]}"
do
    echo "Setting $INA to $VB:$VSH:$AVG"
    adb shell "echo $VB > $INA/vbus_ct"
    adb shell "echo $VSH > $INA/vsh_ct"
    adb shell "echo $AVG > $INA/averages"
done

DELAY=$(adb shell "cat ${INA_DIRS[0]}/delay")

echo "New delay is $DELAY"
