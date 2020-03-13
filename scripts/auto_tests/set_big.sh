#!/bin/bash

B_CPUS=(cpu4 cpu5 cpu6 cpu7)

function setCoreFreq {
	echo "Set core $1 to $2:$3"
	adb shell "echo $2 > /sys/devices/system/cpu/$1//cpufreq/scaling_min_freq"
	adb shell "echo $3 > /sys/devices/system/cpu/$1//cpufreq/scaling_max_freq"
}

function setBCPUFreq {
	for core in ${B_CPUS[*]}
	do
		setCoreFreq $core $1 $2
	done
}

setBCPUFreq $1 $1
