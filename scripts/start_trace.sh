#!/bin/bash

echo "Removing old trace.dat ..."
adb shell "rm -rf /data/local/tmp/trace.dat"

echo "Setting up sys_logger ..."
adb shell "/data/local/tmp/sys_logger.sh setup $@"

echo "Starting the trace ..."
adb shell "/data/local/tmp/sys_logger.sh start"
