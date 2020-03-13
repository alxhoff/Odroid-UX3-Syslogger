PID_FILE=/data/local/tmp/sys_logger.pid
MYDIR="$(dirname "$(realpath "$0")")"

# also trace the chrome governor
generate_report=true
trace_cg=false
trace_threads=true
trace_opengl=true
trace_binder=true

default_interval=5
PARAMS="cpu=2"

print_usage()
{
    echo "Usage: $0 [setup (-cg) (-nt) (-nb) (-nogl) (-i) | start | stop | finish (-nr)]"
    echo ""
    echo "Syslogger workflow: Setup -> Start -> Stop -> Finish"
    echo ""
    echo "Setup"
    echo "-cg           Trace Chrome governor"
    echo "-nt           Do not trace threads {sched:sched_process_fork}"
    echo "-nb           Do not trace binder {binder_transaction, cpu_idle, sched_switch}"
    echo "-nogl         Do not trace OpenGL {sys_logger:opengl_frame}"
    echo "-i            Syslogger logging interval, default = 5ms"
    echo ""
    echo "Finish"
    echo "-nr           Do not generate ftrace report (trace.report)"
}

is_loaded()
{
	if lsmod | grep -q sys_logger; then
		return 0
	fi
	return 1
}

is_enabled()
{
	enabled=`cat /sys/module/sys_logger/parameters/enabled 2>/dev/null`
	if [ $enabled ] ; then
		if [ "$enabled" == 'Y' ]; then
			return 0
		fi
	fi
	return 1
}

setup()
{
    SYSLOG_EVENTS="-e sys_logger"

	if is_loaded; then
		echo "Error: Already setup!"
	fi

	# `insmod $MYDIR/sys_logger.ko $PARAMS`
    `insmod /system/lib/modules/sys_logger.ko $PARAMS`

    chmod 666 /dev/EGLSyslogger

	ret=$?

	if [ "$ret" != 0 ]; then
		echo "Error: Could not load kernel module"
		exit 1
	fi

	while [ ! -w /sys/module/sys_logger/parameters/enabled ]; do
		# Especially when switching to the interactive governor,
		# the sysfs is sometimes messed up. We have to try reloading
		# the module until it works. (happen also with other modules)
		rmmod sys_logger
		sleep 3

		# `insmod $MYDIR/sys_logger.ko $PARAMS`
		ret=$?

		if [ "$ret" != 0 ]; then
			echo "Error: Could not load kernel module"
			exit 1
		fi
		sleep 5
		if [ -w /sys/module/sys_logger/parameters/enabled ]; then
			break;
		fi
	done

	printf "Preparing to trace: "
	if [ "$trace_cg" == true ]; then
		APPEND="-e cpufreq_cg"
        printf "Chrome governor, "
	else
		APPEND=""
	fi

    if [ "$trace_binder" == true ]; then
        APPEND="${APPEND} -e binder_transaction -e cpu_idle -e sched_switch"
        printf "Binder, CPU idle, Context switches, "
	fi

    BUFFER_SIZE=20000
	if [ "$trace_threads" == true ]; then
		# in order to detect all chrome threads, we have to trace forks early
		APPEND="$APPEND -e sched:sched_process_fork"
		# We trace rougly 50mb per 30 second (mostly on little CPUs), make the
		# buffers big enough. 8 * 40 MB -> 320 MB
		BUFFER_SIZE=40000
        printf "Threads,  "
	fi

    if [ "$trace_opengl" == true ]; then
        SYSLOG_EVENTS="${SYSLOG_EVENTS} -e sys_logger:opengl_frame"
        printf "OpenGL, "
    fi

    printf "\n"

	# clear all events if enything is pending
	$MYDIR/trace-cmd reset > /dev/null

	# start tracing so we can monitor forks of children (relevant for chrome)
	$MYDIR/trace-cmd start \
        $SYSLOG_EVENTS \
		-i \
		-b $BUFFER_SIZE \
		-d -D \
		$APPEND

	ret=$?
	if [ "$ret" != 0 ]; then
		echo "Error: trace-cmd failed"
		rmmod sys_logger
		exit 1
	fi
}

start()
{
	if ! is_loaded; then
		echo "Error: Not setup!"
		exit 1
	elif is_enabled; then
		echo "Error: Already started!"
		exit 1
	fi

	# detect if we are tracing threads via active fork tracing
	tmp=`cat /sys/kernel/debug/tracing/events/sched/sched_process_fork/enable 2>/dev/null`
	if [[ $tmp -eq "1" ]]; then
		# enable all expensive tracing
		echo 1 > /sys/kernel/debug/tracing/events/sched/sched_wakeup/enable
		echo 1 > /sys/kernel/debug/tracing/events/sched/sched_wakeup_new/enable
		echo 1 > /sys/kernel/debug/tracing/events/sched/sched_stat_runtime/enable
	fi

	# start a new measurement run
	echo 1 > /sys/module/sys_logger/parameters/enabled
}

stop()
{
	if ! is_loaded; then
		echo "Error: Not setup!"
		exit 1
	elif ! is_enabled; then
		echo "Error: Not started!"
		exit 1
	fi

	# stop the measurement run
	echo 0 > /sys/module/sys_logger/parameters/enabled

	# detect if we are tracing threads via active fork tracing
	tmp=`cat /sys/kernel/debug/tracing/events/sched/sched_process_fork/enable 2>/dev/null`
	if [[ $tmp -eq "1" ]]; then
		# disable all expensive tracing
		echo 0 > /sys/kernel/debug/tracing/events/sched/sched_wakeup/enable
		echo 0 > /sys/kernel/debug/tracing/events/sched/sched_wakeup_new/enable
		echo 0 > /sys/kernel/debug/tracing/events/sched/sched_stat_runtime/enable
	fi
}

finish()
{
	if ! is_loaded; then
		echo "Error: Not setup!"
		exit 1
	elif is_enabled; then
		stop
	fi

	# stop tracing
	$MYDIR/trace-cmd stop

	# write the trace.dat file
	$MYDIR/trace-cmd extract -o $MYDIR/trace.dat

	# turn of and reset all tracing
	$MYDIR/trace-cmd reset

    if [ "$generate_report" == true ]; then
        echo "Generating trace report"

        rm $MYDIR/*.report

        $MYDIR/trace-cmd report -i $MYDIR/trace.dat > $MYDIR/trace.report
    fi

	# unload the module
	rmmod /system/lib/modules/sys_logger.ko
}

if [ $# -lt 1 ]; then
	print_usage
	exit 1
fi

key="$1"
action=""

while [[ $# -gt 0 ]]
	do
	key="$1"

	case $key in
		setup|start|stop|finish)
			action=$key
			shift # past argument
			;;
		-cg|--chrome-governor)
			if [ "$action" != "setup" ]; then
				print_usage
				exit 1
			fi
			trace_cg=true
			shift # past argument
			;;
		-nt|--no-threads)
			if [ "$action" != "setup" ]; then
				print_usage
				exit 1
			fi
			trace_threads=0
			shift # past argument
			;;
        -nr|--no-report)
			if [ "$action" != "finish" ]; then
				print_usage
				exit 1
			fi
            generate_report=false
            shift
            ;;
        -nb|--no-binder)
			if [ "$action" != "setup" ]; then
				print_usage
				exit 1
			fi
            trace_binder=false
            shift
            ;;
        -nogl|--no-opengl)
			if [ "$action" != "setup" ]; then
				print_usage
				exit 1
			fi
            trace_opengl=false
            shift
            ;;
        -i)
			if [ "$action" != "setup" ]; then
				print_usage
				exit 1
			fi
            shift
            echo "interval set"
            default_interval=$1
            shift
            ;;
		*)
			print_usage
			exit 1
	esac
done

PARAMS="${PARAMS} interval=${default_interval}"

case "$action" in
    setup)
        setup
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    finish)
        finish
        ;;
    *)
        print_usage
        exit 1
esac

exit 0
