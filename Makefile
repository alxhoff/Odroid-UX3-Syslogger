obj-m  := sys_logger.o
sys_logger-y := module.o

# make sure the trace.h file can be found
EXTRA_CFLAGS = -I$(PWD)

ARCH ?= arm
CROSS_COMPILE ?= arm-eabi-

default:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

adb_install: default
	adb push sys_logger.ko /data/local/tmp
	adb push android/sys_logger.sh /data/local/tmp
	adb push android/trace-cmd /data/local/tmp
