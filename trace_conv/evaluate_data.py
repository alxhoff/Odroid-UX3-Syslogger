#!/usr/bin/python3

import os
import sys
import csv
import argparse

import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import numpy as np

import warnings
warnings.filterwarnings("ignore")

parser = argparse.ArgumentParser()
parser.add_argument("-i", "--input-folder", nargs=1, default=["."],
		    help="Folder containing input data")
parser.add_argument("-o", "--output-folder", nargs=1, default=["."],
		    help="Folder data will be written to")
args = parser.parse_args()

threads = {}

class ThreadInfo:
    def __init__(self, dict):
        self.pid = int(dict['pid'])
        self.ppid = int(dict['ppid'])
        self.comm = dict['comm']

    def is_direct_main_thread(self):
        if "chromium.chrome" in self.comm:
            return True;
        if self.ppid > 0:
            if "chromium.chrome" in threads[self.ppid].comm:
                return True;
        return False;

    def is_chrome_main_thread(self):
        if "chromium.chrome" in self.comm:
            return True;
        if self.ppid > 0:
            return threads[self.ppid].is_chrome_main_thread()
        return False;

    def is_renderer_thread(self):
        if "dboxed_process" in self.comm:
            return True;
        if self.ppid > 0:
            return threads[self.ppid].is_renderer_thread()
        return False;

    def is_gpu_thread(self):
        if ("ileged_process" in self.comm or
            "CrGpuMain" in self.comm):
            return True;
        if self.ppid > 0:
            return threads[self.ppid].is_gpu_thread()
        return False;

    def is_trace_thread(self):
        if "trace-cmd" in self.comm:
            return True;
        if "sys_logger" in self.comm:
            return True;
        return False;

    def is_chrome_thread(self):
        return (self.is_chrome_main_thread() or
                self.is_renderer_thread() or
                self.is_gpu_thread())

def read_threads_csv(path):
    with open(path) as csvfile:
        reader = csv.DictReader(csvfile)
        for dict in reader:
            threads[int(dict['pid'])] = (ThreadInfo(dict))

class ThreadActivity:
    def __init__(self, pid):
        self.pid = pid
        self.running_ns = 0

class CPUActivity:
    def __init__(self, cpu):
        self.cpu = cpu
        self.running_ns = 0
        self.threads = {}

class MeasurementInfo:
    def __init__(self, dict):
        self.start = int(dict['Time [ns]'])
        self.stop = -1
        self.interval_ns = -1
        self.a15_power = float(dict['Power A15 [W]'])
        self.a7_power = float(dict['Power A7 [W]'])
        self.avg_15_power = -1
        self.avg_a7_power = -1
        self.cpu = []
        for cpu in range(0, 8):
            self.cpu.append(CPUActivity(cpu))

class PhaseInfo:
    def __init__(self, start, phase):
        self.start = start
        self.stop = -1;
        self.phase = phase

class RunInfo:
    def __init__(self, run_nr):
        self.run_nr = run_nr
        self.measurements = []
        self.phases = []

        # assume cpu activity is added sequentially per cpu
        self.last_index = 0
        self.last_cpu = 0

    def add_cg_event(self, dict):
        ts = int(dict['ts'])
        event = int(dict['event'])
        value = int(dict['value'])

        if event == 11:
            self.phases.append(PhaseInfo(ts, value))

    def add_measurement(self, dict):
        self.measurements.append(MeasurementInfo(dict))
        cur = self.measurements[-1]

        '''
        these values will be fixed up on the next event, this is only valid
        for the last event.
        '''
        cur.stop = cur.start + 5000000 - 1
        cur.interval_ns = cur.stop - cur.start + 1
        cur.avg_a7_power = cur.a7_power
        cur.avg_a15_power = cur.a15_power

        # calculate the stop time and total ns - we assume all are ordered
        if len(self.measurements) > 1:
                # fixup prev
                prev = self.measurements[-2]
                prev.stop = cur.start - 1
                prev.interval_ns = prev.stop - prev.start + 1
                prev.avg_a7_power = (prev.a7_power + cur.a7_power) / 2
                prev.avg_a15_power = (prev.a15_power + cur.a15_power) / 2

    def add_cpu_activity(self, cpu, dict):
        handled = False
        if self.last_cpu != cpu:
            self.last_index = 0
            self.last_cpu = cpu

        start = int(dict['start'])
        stop = int(dict['stop'])
        pid = int(dict['pid'])
        while (self.last_index < len(self.measurements)):
            m = self.measurements[self.last_index]
            self.last_index = self.last_index + 1
            if m.stop < start:
                # continue searching
                continue;
            if m.start > stop:
                # finished searching
                break;
            # overlaps somehow
            ns = min(stop, m.stop) - max(start, m.start) + 1
            assert(ns > 0)
            if (stop <= m.stop):
                handled = True
            # do the accounting
            m.cpu[cpu].running_ns += ns
            if not pid in m.cpu[cpu].threads:
                m.cpu[cpu].threads[pid] = ThreadActivity(pid)
            m.cpu[cpu].threads[pid].running_ns += ns

        # make sure we don't mess up accounting for the next task
        assert(handled == True)
        self.last_index = max(0, self.last_index - 2)

    def _output_load_csv(self, output_folder, name, timestamps_ns, little_load,
                         big_load, power):
            data = np.column_stack((timestamps_ns, little_load, big_load, power))
            header = "timestamp (ns), little_load (%), big_load (%), power (W)"
            np.savetxt(output_folder + '/load-{}-{}.csv'.format(name, self.run_nr),
                       data, delimiter=',', header=header)

    def _output_consumption_csv(self, output_folder, name, power):
        with open(output_folder + '/consumption-{}-{}.csv'.format(name, self.run_nr), 'w') as csvfile:
            fieldnames = [
                "phase",
                "start",
                "stop",
                "Ws",
                "avg_W",
            ]
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()

            # calculate total power consumption over the whole measurement
            total_s = sum(self.interval_ns / 1000000000)
            ws = sum(self.interval_ns * power) / 1000000000
            avg_w = ws / total_s
            writer.writerow( {
                "phase" : "all",
                "start" : self.measurements[0].start - self.start_ns,
                "stop" : self.measurements[-1].stop - self.start_ns,
                "Ws" : ws,
                "avg_W" : avg_w,
            } )

            # calculate the power consumption per phase
            for phase in self.phases:
                phase_start = phase.start - self.start_ns
                phase_stop = phase.stop - self.start_ns
                '''
                Create a vector containing for each measurement, how much time
                belongs to this phase. It only differs at the phase start
                and stop. This is not 100 % correct for tasks (e.g. we don't
                know if the task actually ran in this interval before
                the phase start), but this isn't really significant.
                '''
                phase_interval_ns = np.array([0] * len(self.measurements))
                for idx, m in enumerate(self.measurements):
                    meas_start = m.start - self.start_ns
                    meas_stop = m.stop - self.start_ns
                    if meas_start > phase_stop:
                        break;
                    if meas_stop < phase_start:
                        continue;
                    start = max(meas_start, phase_start)
                    stop = min(meas_stop, phase_stop)
                    phase_interval_ns[idx] = stop - start + 1

                phase_interval_s = phase_interval_ns / 1000000000
                total_s = sum(phase_interval_s)
                ws = sum(phase_interval_s * power)
                avg_w = ws / total_s
                writer.writerow( {
                    "phase" : phase.phase,
                    "start" : phase_start,
                    "stop" : phase_stop,
                    "Ws" : ws,
                    "avg_W" : avg_w,
                } )

    def output_files(self, output_folder):
        # some sanity checking
        for m in self.measurements:
            for cpu in m.cpu:
                assert(m.interval_ns >= cpu.running_ns)
                for key in cpu.threads:
                    thread = cpu.threads[key]
                    load = thread.running_ns / m.interval_ns;
                    assert(load >= 0 and load <= 1)

        # Phases - make sure our phases cover the whole measurement
        if len(self.phases) == 0 or self.phases[0].start != self.measurements[0].start:
               self.phases.insert(0, PhaseInfo(self.measurements[0].start, -1))
        for idx, phase in enumerate(self.phases):
            # calculate the stop time of a phase
            if (idx + 1) < len(self.phases):
                phase.stop = self.phases[idx + 1].start - 1
            else:
                phase.stop = self.measurements[-1].stop

        # extract and normalize our measurement time stamps
        timestamps_ns = np.array([m.start for m in self.measurements])
        self.start_ns = timestamps_ns[0]
        timestamps_ns = (timestamps_ns - self.start_ns)
        timestamps = timestamps_ns / 1000000

        # average power sensor values per measurement
        little_power = np.array([m.avg_a7_power for m in self.measurements])
        big_power = np.array([m.avg_a15_power for m in self.measurements])
        total_power = little_power + big_power

        # interval per measurement
        interval_ns = np.array([m.interval_ns for m in self.measurements])
        self.interval_ns = interval_ns

        # make the phases graph look nicer - draw straight lines
        phase_timestamps_ns = np.array([0] * (2 * len(self.phases)))
        phases = np.array([0] * (2 * len(self.phases)))
        for idx, phase in enumerate(self.phases):
            phases[idx * 2] = phase.phase
            phases[idx * 2 + 1] = phase.phase
            phase_timestamps_ns[idx * 2] = phase.start
            phase_timestamps_ns[idx * 2 + 1] = phase.stop
        # normalize the timestamps
        phase_timestamps_ns = phase_timestamps_ns - self.start_ns
        phase_timestamps = phase_timestamps_ns / 1000000

        # calculate our total ns spend for certain tasks
        total_little_ns = np.array([0] * len(self.measurements))
        total_big_ns = np.array([0] * len(self.measurements))
        chrome_little_ns = np.array([0] * len(self.measurements))
        chrome_big_ns = np.array([0] * len(self.measurements))
        load_gpu_little = np.array([0] * len(self.measurements))
        load_gpu_big = np.array([0] * len(self.measurements))
        renderer_big_ns = np.array([0] * len(self.measurements))
        renderer_little_ns = np.array([0] * len(self.measurements))
        gpu_big_ns = np.array([0] * len(self.measurements))
        gpu_little_ns = np.array([0] * len(self.measurements))
        chrome_main_big_ns = np.array([0] * len(self.measurements))
        chrome_main_little_ns = np.array([0] * len(self.measurements))
        trace_big_ns = np.array([0] * len(self.measurements))
        trace_little_ns = np.array([0] * len(self.measurements))
        for i in range(len(self.measurements)):
            m = self.measurements[i]
            for cpu in m.cpu:
                for pid in cpu.threads:
                    thread = cpu.threads[pid]
                    t = threads[pid]
                    if cpu.cpu < 4:
                        total_little_ns[i] += thread.running_ns
                        if t.is_chrome_thread():
                            chrome_little_ns[i] += thread.running_ns
                        if t.is_renderer_thread():
                            renderer_little_ns[i] += thread.running_ns
                        if t.is_gpu_thread():
                            gpu_little_ns[i] += thread.running_ns
                        if t.is_chrome_main_thread():
                            chrome_main_little_ns[i] += thread.running_ns
                        if t.is_trace_thread():
                            trace_little_ns[i] += thread.running_ns
                    else:
                        total_big_ns[i] += thread.running_ns
                        if t.is_chrome_thread():
                            chrome_big_ns[i] += thread.running_ns
                        if t.is_renderer_thread():
                            renderer_big_ns[i] += thread.running_ns
                        if t.is_gpu_thread():
                            gpu_big_ns[i] += thread.running_ns
                        if t.is_chrome_main_thread():
                            chrome_main_big_ns[i] += thread.running_ns
                        if t.is_trace_thread():
                            trace_big_ns[i] += thread.running_ns

        # calculate the loads (0% - 400%) based on the real interval time
        total_little_load = total_little_ns / interval_ns
        total_big_load = total_big_ns / interval_ns
        chrome_little_load = chrome_little_ns / interval_ns
        chrome_big_load = chrome_big_ns / interval_ns
        renderer_little_load = renderer_little_ns / interval_ns
        renderer_big_load = renderer_big_ns / interval_ns
        gpu_little_load = gpu_little_ns / interval_ns
        gpu_big_load = gpu_big_ns / interval_ns
        chrome_main_little_load = chrome_main_little_ns / interval_ns
        chrome_main_big_load = chrome_main_big_ns / interval_ns
        trace_little_load = trace_little_ns / interval_ns
        trace_big_load = trace_big_ns / interval_ns

        '''
        We don't map any power to "idle" because this would be very misleading.
        If 3 CPUs are idle and 1 is doing heavy work, we would account way to
        much power as "idle". Instead, use the total execution time on a CPU
        instead (total_little_ns, not 4 * interval_ns).
        '''
        # calculate power using the timing data - triggers warnings we ignore
        chrome_power = np.nan_to_num(chrome_little_ns / total_little_ns) * little_power
        chrome_power += np.nan_to_num(chrome_big_ns / total_big_ns) * big_power
        renderer_power = np.nan_to_num(renderer_little_ns / total_little_ns) * little_power
        renderer_power += np.nan_to_num(renderer_big_ns / total_big_ns) * big_power
        gpu_power = np.nan_to_num(gpu_little_ns / total_little_ns) * little_power
        gpu_power += np.nan_to_num(gpu_big_ns / total_big_ns) * big_power
        chrome_main_power = np.nan_to_num(chrome_main_little_ns / total_little_ns) * little_power
        chrome_main_power += np.nan_to_num(chrome_main_big_ns / total_big_ns) * big_power
        trace_power = np.nan_to_num(trace_little_ns / total_little_ns) * little_power
        trace_power += np.nan_to_num(trace_big_ns / total_big_ns) * big_power

        # store the data as csv
        self._output_load_csv(output_folder, "total", timestamps_ns,
                                    total_little_load, total_big_load,
                                    total_power)
        self._output_load_csv(output_folder, "chrome", timestamps_ns,
                                    chrome_little_load, chrome_big_load,
                                    chrome_power)
        self._output_load_csv(output_folder, "renderer", timestamps_ns,
                                    renderer_little_load, renderer_big_load,
                                    renderer_power)
        self._output_load_csv(output_folder, "gpu", timestamps_ns,
                                    gpu_little_load, gpu_big_load, gpu_power)
        self._output_load_csv(output_folder, "chrome_main", timestamps_ns,
                                    chrome_main_little_load, chrome_main_big_load,
                                    chrome_main_power)
        self._output_load_csv(output_folder, "trace", timestamps_ns,
                                    trace_little_load, trace_big_load,
                                    trace_power)

        # create a nice PDF with the overview first
        pp = PdfPages(output_folder + '/report-{}.pdf'.format(self.run_nr))
        fig = plt.figure(figsize=(6.0,8.91), dpi=80)
        fig.set_canvas(plt.gcf().canvas)
        plt.title('System')
        plt.subplot(411)
        plt.plot(timestamps, total_little_load, label="total")
        plt.plot(timestamps, chrome_little_load + trace_little_load, label="+chrome main")
        plt.plot(timestamps, renderer_little_load + gpu_little_load + trace_little_load, label="+renderer")
        plt.plot(timestamps, gpu_little_load + trace_little_load, label="+gpu")
        plt.plot(timestamps, trace_little_load, label="tracing")
        plt.xlim(timestamps[0], timestamps[-1])
        plt.ylabel("A7 [%]")
        plt.legend()
        plt.subplot(412)
        plt.plot(timestamps, total_big_load, label="total")
        plt.plot(timestamps, chrome_big_load + trace_big_load, label="+chrome main")
        plt.plot(timestamps, renderer_big_load + gpu_big_load + trace_big_load, label="+renderer")
        plt.plot(timestamps, gpu_big_load + trace_big_load, label="+gpu")
        plt.plot(timestamps, trace_big_load, label="tracing")
        plt.xlim(timestamps[0], timestamps[-1])
        plt.ylabel("A15 [%]")
        plt.legend()
        plt.subplot(413)
        plt.plot(timestamps, total_power, label="total")
        plt.plot(timestamps, chrome_power + trace_power, label="+chrome main")
        plt.plot(timestamps, renderer_power + gpu_power + trace_power, label="+renderer")
        plt.plot(timestamps, gpu_power + trace_power, label="+gpu")
        plt.plot(timestamps, trace_power, label="tracing")
        plt.xlim(timestamps[0], timestamps[-1])
        plt.ylabel("A7 + A15 [W]")
        plt.legend()
        plt.subplot(414)
        plt.plot(phase_timestamps, phases, label="phases")
        plt.xlim(timestamps[0], timestamps[-1])
        plt.ylabel("Phase")
        plt.legend()
        plt.xlabel("time [ms]")
        plt.draw()
        fig.savefig(pp, format='pdf')
        plt.close()

        for pid in threads:
            thread = threads[pid]
            name = thread.comm + " (pid=%d)" % pid

            # collect thread runtime
            thread_little_ns = np.array([0] * len(self.measurements))
            thread_big_ns = np.array([0] * len(self.measurements))
            for i in range(len(self.measurements)):
                m = self.measurements[i]
                for cpu in m.cpu:
                    if pid in cpu.threads:
                        t = cpu.threads[pid]
                        if cpu.cpu < 4:
                            thread_little_ns[i] += t.running_ns
                        else:
                            thread_big_ns[i] += t.running_ns

            #ignore tasks that basically never ran
            if np.sum(thread_little_ns + thread_big_ns) == 0:
                continue

            # calculate thread load and power based on runtime
            thread_power = np.nan_to_num(thread_little_ns / total_little_ns) * little_power
            thread_power += np.nan_to_num(thread_big_ns / total_big_ns) * big_power
            thread_little_load = thread_little_ns / interval_ns
            thread_big_load = thread_big_ns / interval_ns

            # calculate and output the consumption
            self._output_consumption_csv(output_folder, "thread-{}".format(pid),
                                         thread_power)

            # store the data as csv
            self._output_load_csv(output_folder, "thread-{}".format(pid),
                                        timestamps_ns, thread_little_load,
                                        thread_big_load, thread_power)

            fig = plt.figure(figsize=(6.0,8.91), dpi=80)
            fig.set_canvas(plt.gcf().canvas)
            plt.title('System')
            plt.subplot(411)
            plt.plot(timestamps, total_little_load, label="total")
            if thread.is_chrome_thread():
                plt.plot(timestamps, chrome_little_load, label="chrome")
            if thread.is_renderer_thread():
                plt.plot(timestamps, renderer_little_load, label="renderer")
            if thread.is_gpu_thread():
                plt.plot(timestamps, gpu_little_load, label="gpu")
            if thread.is_chrome_main_thread():
                plt.plot(timestamps, chrome_main_little_load, label="chrome main")
            if thread.is_trace_thread():
                plt.plot(timestamps, trace_little_load, label="tracing")
            plt.plot(timestamps, thread_little_load, label=name)
            plt.xlim(timestamps[0], timestamps[-1])
            plt.ylabel("A7 [%]")
            plt.legend()
            plt.subplot(412)
            plt.plot(timestamps, total_big_load, label="total")
            if thread.is_chrome_thread():
                plt.plot(timestamps, chrome_big_load, label="chrome")
            if thread.is_renderer_thread():
                plt.plot(timestamps, renderer_big_load, label="renderer")
            if thread.is_gpu_thread():
                plt.plot(timestamps, gpu_big_load, label="gpu")
            if thread.is_chrome_main_thread():
                plt.plot(timestamps, chrome_main_big_load, label="chrome main")
            if thread.is_trace_thread():
                plt.plot(timestamps, trace_big_load, label="tracing")
            plt.plot(timestamps, thread_big_load, label=name)
            plt.xlim(timestamps[0], timestamps[-1])
            plt.ylabel("A15 [%]")
            plt.legend()
            plt.subplot(413)
            plt.plot(timestamps, total_power, label="total")
            if thread.is_chrome_thread():
                plt.plot(timestamps, chrome_power, label="chrome")
            if thread.is_renderer_thread():
                plt.plot(timestamps, renderer_power, label="renderer")
            if thread.is_gpu_thread():
                plt.plot(timestamps, gpu_power, label="gpu")
            if thread.is_chrome_main_thread():
                plt.plot(timestamps, chrome_main_power, label="chrome main")
            if thread.is_trace_thread():
                plt.plot(timestamps, trace_power, label="tracing")
            plt.plot(timestamps, thread_big_ns / interval_ns, label=name)
            plt.xlim(timestamps[0], timestamps[-1])
            plt.ylabel("A7 + A15 [W]")
            plt.legend()
            plt.subplot(414)
            plt.plot(phase_timestamps, phases, label="phases")
            plt.xlim(timestamps[0], timestamps[-1])
            plt.ylabel("Phase")
            plt.legend()
            plt.xlabel("time [ms]")
            plt.draw()
            fig.savefig(pp, format='pdf')
            plt.close()

        pp.close()

        # calculate and output power consumption
        self._output_consumption_csv(output_folder, "total", total_power)
        self._output_consumption_csv(output_folder, "chrome", chrome_power)
        self._output_consumption_csv(output_folder, "renderer", renderer_power)
        self._output_consumption_csv(output_folder, "gpu", gpu_power)
        self._output_consumption_csv(output_folder, "chrome_main", chrome_main_power)
        self._output_consumption_csv(output_folder, "trace", trace_power)


def process_run_csvs(folder, output_folder, run_nr):
    # identify via powerlogger.csv if this run exists
    if not os.path.isfile(folder + "/powerlogger-{}.csv".format(run_nr)):
        return False

    runinfo = RunInfo(run_nr)

    # read in cg information
    with open(folder + "/cg_events-{}.csv".format(run_nr)) as csvfile:
        reader = csv.DictReader(csvfile, fieldnames=("ts", "event", "value"))
        for dict in reader:
            runinfo.add_cg_event(dict)

    # read in power information
    with open(folder + "/powerlogger-{}.csv".format(run_nr)) as csvfile:
        reader = csv.DictReader(csvfile)
        for dict in reader:
            runinfo.add_measurement(dict)

    # read in all cpu activity and account them properly to the measurements
    for cpu in range(0, 8):
        with open(folder + "/cpu_activity_{}-{}.csv".format(cpu, run_nr)) as csvfile:
            reader = csv.DictReader(csvfile)
            for dict in reader:
                runinfo.add_cpu_activity(cpu, dict)

    runinfo.output_files(output_folder)

    return True


if __name__ == "__main__":
    # all runs need the global thread info file
    read_threads_csv(args.input_folder[0] + "/threads.csv")

    run_nr = 0
    while (True):
        more = process_run_csvs(args.input_folder[0], args.output_folder[0], run_nr)
        run_nr = run_nr + 1
        if not more:
            break

