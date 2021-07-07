#!/bin/bash

set -e
set -x

source _init.sh


adb root
adb shell "mount -t debugfs nodev /sys/kernel/debug/"

adb shell rm -rf $ANDROID_GCOV_PATH
adb shell mkdir  $ANDROID_GCOV_PATH
adb push \
	$ANDROID_GCOV_FETCHER \
	$ANDROID_GCOV_PATH
adb shell \
	$ANDROID_GCOV_PATH/$ANDROID_GCOV_FETCHER \
	$ANDROID_GCOV_COVERAGE_COMPRESSED
adb pull $ANDROID_GCOV_COVERAGE_COMPRESSED
tar xfz coverage.tar.gz
