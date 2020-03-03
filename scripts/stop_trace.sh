#!/bin/bash

echo "Stopping sys_logger ..."
adb shell "/data/local/tmp/sys_logger.sh stop"

echo "Write the trace file ..."
adb shell "/data/local/tmp/sys_logger.sh finish $@"

echo "Fetching the trace file ..."
adb pull "/data/local/tmp/trace.dat" .
adb pull "/data/local/tmp/trace.report" .
