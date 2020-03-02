#!/bin/bash

A7_GOV_PATH=/sys/devices/system/cpu/cpu0/cpufreq
A15_GOV_PATH=/sys/devices/system/cpu/cpu4/cpufreq

echo "Current A7 Governer:"
adb shell "cat $A7_GOV_PATH/scaling_governor"
echo "Current A15 Governer:"
adb shell "cat $A15_GOV_PATH/scaling_governor"

echo "Available A7 Governer:"
adb shell "cat $A7_GOV_PATH/scaling_available_governors"
echo "Available A15 Governer:"
adb shell "cat $A15_GOV_PATH/scaling_available_governors"

echo "Enabling governer: $1"
adb shell "chmod 755 /dev/chrome_ioctl"
adb shell "echo $1 > $A7_GOV_PATH/scaling_governor"
adb shell "echo $1 > $A15_GOV_PATH/scaling_governor"
