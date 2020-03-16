# System logger for Odroid XU3

The system logger (syslogger) creates and traces, using ftrace, a number of custom trace points that extract system information from a combination of sysfs, kernel stats, device drivers as well as user-space IOctl "stat pipes".

The system logger implements custom tracing for the following:

- OpenGL frames:
    - Timestamps
    - Inter-frame periods
    - Average wattage for each peripheral throughout the frame
    - Energy usage by each peripheral throughout the frame
- CPU info:
    - Online status
    - CPU time
        - System
        - User
        - Idle
- CPU Frequency
- INA231 power sensors:
    - A15
    - A7
    - Memory
    - GPU
- Mali GPU:
    - Load
    - Frequency
- Temperatures:
    - A15 cores
    - GPU
- Network:
    - RX
    - TX

Syslogger is also used as the trace backend for [BrezeFlow](https://github.com/alxhoff/BrezeFlow) by encorporating automated tracing of scheduling operations and binder transactions needed for the interpolation of system execution flows.

# Building

## Kernel Module

To build the syslogger kernel module the Makefile must be invoked with the kernel source directory passed in as `KDIR`. 

For example, if your kernel source is in ~/linux then you would envoke make as follows

``` bash
make KDIR=~/linux
```

It should be noted that this has caused issues for me with version magic. As such I usually copy the sources into my kernel and perform an in-source build. See my [complete kernel](/home/alxhoff/Work/Optigame/android_builds/voodik/Android_7.1/android_source_xu3_Android7.1/kernel/hardkernel/odroidxu3) for a pre-modified Odroid XU3 kernel with syslogger already integrated. If you should opt to DIY then the only modifications required are the the [Kconfig](https://github.com/alxhoff/Odroid-XU3-Kernel/commit/ff3c6109baa84736ead0a099fbb9bcdae5817031#diff-61f226c1c1f3a78524783445250fe875) file as well as the [Makefile](https://github.com/alxhoff/Odroid-XU3-Kernel/commit/ff3c6109baa84736ead0a099fbb9bcdae5817031#diff-ba85cd02ff38397bfd6c84c770d5a699).

## Cross Compilation Toolchain (gcc-arm-linux-androideabi)

On Ubuntu systems the package `gcc-arm-linux-gnueabi` should be all you need.

Otherwise you can build a toolchain from the Android NDK. Get a copy of the Android NDK, on Arch systems the NDK can be retrieved from the AUR repo `android-ndk`.

From the NDK directory you can build the toolchain by running

``` bash
TOOLCHAIN_DIR=/path/to/your/desired/toolchain/location
NDK_ROOT=/path/to/your/ndk/installation/directory
$NDK_ROOT/build/tools/make-standalone-toolchain.sh --install-dir=$TOOLCHAIN_DIR --arch=arm
```
Where `TOOLCHAIN_DIR` is the desired install location.

This toolchain dir should then be exported when it is to be used.

``` bash

export PATH=$TOOLCHAIN_DIR/bin:$PATH

```

## Trace-cmd

Trace-cmd is needed/used for controlling ftrace as well as processing the output `.dat` files.

*Note: you may need to set the system's python version to 2.7 to build trace-cmd*

I was having problems with the Makefile finding my python libraries, hence the PYTHON_INCLUDES.

``` bash
git clone https://git.kernel.org/pub/scm/linux/kernel/git/rostedt/trace-cmd.git
cd trace-cmd

mkdir x86
sudo make PYTHON_INCLUDES=-I/usr/include/python2.7 ctracecmd.so 
sudo make PYTHON_INCLUDES=-I/usr/include/python2.7 trace-cmd
cp tracecmd/trace-cmd python/ctracecmd.so x86/

export CC=arm-linux-gnueabi-gcc #fix for broken propogation of CROSS_COMPILE variable
mkdir android
sudo make LDFLAGS=-static CROSS_COMPILE=arm-linux-gnueabi- PYTHON_INCLUDES=-I/usr/include/python2.7 trace-cmd
cp tracecmd/trace-cmd android/
```
Now we have built trace-cmd and it's python clib for the x86 host machine as well as a trace-cmd binary for the XU3. These binaries are also included in this repository [here (x86)](trace_conv) and [here (Android)](android). 

### Fixes for trace-cmd

#### Undefined reference

It seems that there is some missing definitions in the source. If you are getting an `undefined reference to 'add_event_pid'` error then the following patch will fix this. PR can be found [here](https://github.com/rostedt/trace-cmd/pull/14)

``` c
diff --git a/tracecmd/trace-record.c b/tracecmd/trace-record.c
index 0a3851a..483a8b1 100644
--- a/tracecmd/trace-record.c
+++ b/tracecmd/trace-record.c
@@ -1431,6 +1431,7 @@ static void ptrace_wait(enum trace_type type)
 static inline void ptrace_wait(enum trace_type type) { }
 static inline void enable_ptrace(void) { }
 static inline void ptrace_attach(int pid) { }
+static inline void add_event_pid(const char *buf) {  }
 
 #endif /* NO_PTRACE */
```
#### Global name `event_format_name_get` is not defined

See [this](https://github.com/rostedt/trace-cmd/pull/13) PR.

#### Problems cross compiling `trace-cmd`

See [this](https://github.com/rostedt/trace-cmd/pull/16) PR.

# Usage

## Installation 
Once the kernel module is installed onto the target device, the tracer is controlled using [`sys_logger.sh`](android/sys_logger.sh). The script should be installed onto the device and placed into the path `/data/local/tmp` along with the android [`trace-cmd`](android/trace-cmd) binary.

``` bash
adb push android/sys_logger.sh /data/local/tmp/sys_logger.sh
adb push android/trace-cmd /data/local/tmp/trace-cmd
```
## Running

Usage of the script is as follows:

``` bash
Usage: android/sys_logger.sh [setup (-cg) (-nt) (-nb) (-nogl) (-i) | start | stop | finish (-nr)]

Syslogger workflow: Setup -> Start -> Stop -> Finish

Setup
-cg           Trace Chrome governor
-nt           Do not trace threads {sched:sched_process_fork}
-nb           Do not trace binder {binder_transaction, cpu_idle, sched_switch}
-nogl         Do not trace OpenGL {sys_logger:opengl_frame}
-i            Syslogger logging interval, default = 5ms
-r            Record straight to a trace.dat
 
Finish
-r            Must be given if recording was specified during setup
-nr           Do not generate ftrace report (trace.report)
```
There are two modes of executing `trace-cmd`. Either `trace-cmd` executes using [`trace-cmd-start`](https://linux.die.net/man/1/trace-cmd-start) or using [`trace-cmd-record`](https://linux.die.net/man/1/trace-cmd-record). Standard execution (using start) means that once ftrace's ring buffer is full events will start being dropped. In practise this means that traces over about 1-5 seconds will start to drop large quantities of trace data. `record` spawns worker threads that pipe the ring buffer into temp files, at a given interval. This means that your trace "buffer" is only limited by the storage capactity of your system. This is the prefered method of tracing and to do so you must provide the `-r` option during `setup` and `finish`.

## Converting trace data (trace.dat)

To convert the binary trace data to usable data the script [trace_conv.py](trace_conv/trace_conv.py) can be used, similarly the [trace-cmd](trace_conv/trace-cmd) binary can be used directly from python to parse `.dat` files. See [here](https://github.com/alxhoff/BrezeFlow/blob/dc9b6bf8c64ce2d6e1f0e10d5ca02220d1a3f35d/TraceCMDParser.py#L69).

Example conversion of `trace.dat`

``` bash
mkdir trace_out
adb pull /data/local/tmp/trace.dat .
python trace_conv/trace_conv.py -i trace.dat -o trace_out
```

# OpenGL Tracing

The native OpenGL libraries require modification to enable tracing of frame information. See the folder [opengl_mods](opengl_mods) for more information.

# Authors

- Alex Hoffman (alex.hoffman@tum.de)
- David Hildenbrand (davidhildenbrand@gmail.com)
