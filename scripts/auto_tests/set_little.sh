#!/bin/bash

L_CPUS=(cpu0 cpu1 cpu2 cpu3)

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

setLCPUFreq $1 $1
