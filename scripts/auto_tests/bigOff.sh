#!/system/bin/sh

echo "Turning off BIG CPU"
sleep 1
adb shell "echo 0 > /sys/devices/system/cpu/cpu4/online"
adb shell "echo 0 > /sys/devices/system/cpu/cpu5/online"
adb shell "echo 0 > /sys/devices/system/cpu/cpu6/online"
adb shell "echo 0 > /sys/devices/system/cpu/cpu7/online"
