#!/bin/bash

LITTLE_FREQS=(1000000 1100000 1200000 1300000 1400000)
BIG_FREQS=(1200000 1300000 1400000 1500000 1600000 1700000 1800000 1900000 2000000)

function turnOnBig {
	echo "Turning on BIG CPU"
    sleep 1
	adb shell "echo 1 > /sys/devices/system/cpu/cpu4/online"
	adb shell "echo 1 > /sys/devices/system/cpu/cpu5/online"
	adb shell "echo 1 > /sys/devices/system/cpu/cpu6/online"
	adb shell "echo 1 > /sys/devices/system/cpu/cpu7/online"
}

function setCoreFreq {
	echo "Set core $1 to $2:$3"
	adb shell "echo $2 > /sys/devices/system/cpu/$1//cpufreq/scaling_min_freq"
	adb shell "echo $3 > /sys/devices/system/cpu/$1//cpufreq/scaling_max_freq"
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

function restoreSystem {
    turnOnBig
    sleep 1
    setLCPUFreq ${LITTLE_FREQS[0]} ${LITTLE_FREQS[4]}
    setBCPUFreq ${BIG_FREQS[0]} ${BIG_FREQS[8]}
    echo "System restored"
}

restoreSystem
