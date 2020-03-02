obj-m  := sys_logger.o
sys_logger-y := module.o

# make sure the trace.h file can be found
EXTRA_CFLAGS = -I$(PWD)

ARCH ?= arm
#CROSS_COMPILE ?= arm-eabi-
CROSS_COMPILE ?= /opt/toolchains/arm-eabi-4.8/bin/arm-eabi-
KDIR ?= /home/alxhoff/Work/Optigame/android_builds/voodik/Android_7.1/android_source_xu3_Android7.1/kernel/hardkernel/odroidxu3

default:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

adb_install: default
	adb push sys_logger.ko /data/local/tmp
	adb push android/sys_logger.sh /data/local/tmp
	adb push android/trace-cmd /data/local/tmp
