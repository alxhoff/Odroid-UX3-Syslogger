#Alex Hoffman 2019
from enum import Enum
import logging
import os

from subprocess import check_output, CalledProcessError

from tempfile import TemporaryFile

def __getout(*args):
    with TemporaryFile() as t:
        try:
            out = check_output(args, stderr=t)
            return  0, out
        except CalledProcessError as e:
            t.seek(0)
            return e.returncode, t.read()

# cmd is string, split with blank
def getout(cmd):
    cmd = str(cmd)
    args = cmd.split(' ')
    return __getout(*args)

def bytes2str(bytes):
    return str(bytes, encoding='utf-8')

def isAdbConnected():
    cmd = 'adb devices'
    (code, out) = getout(cmd)
    if code != 0:
        print('something is error')
        return False
    outstr = bytes2str(out)
    if outstr == 'List of devices attached\n\n':
        print('no devices')
        return False
    else:
        print('have devices')
        return True

class core_type(Enum):
    big = 0
    little = 1

class Core:

    def __init__(self, name, freq, freq_table, online=1, bigLITTLE=core_type.little.value):
        self.name = name
        self.core_type = bigLITTLE
        if bigLITTLE is 0:
            self.online = online
        else:
            self.online = 1
        self.freq = freq
        self.freq_table = freq_table

def GhettoADB(command):
    complete_command = 'adb shell "' + command + ' > /data/local/tmp/result"'
    os.system(complete_command)
    os.system('adb pull /data/local/tmp/result /tmp/adbresult')
    with open("/tmp/adbresult") as f:
        result = f.read().splitlines()
        return result

def GhettoADBNoRet(command):
    complete_command = 'adb shell "' + command + '"'
    os.system(complete_command)

class GovStatus:

    def GetCores(self):
        command = "ls /sys/devices/system/cpu | busybox grep -E \'cpu[0-9]+\'"
        cpus = GhettoADB(command)
        self.core_count = len(cpus)
        for x in cpus:
            self.SetCoreOn(x)
            command = "cat /sys/devices/system/cpu/" + x + "/cpufreq/cpuinfo_cur_freq"
            core_freq = int(GhettoADB(command)[0])
            command = "cat /sys/devices/system/cpu/" + x + "/topology/physical_package_id"
            core_type = int(GhettoADB(command)[0])
            if core_type is 0:
                command = "cat /sys/devices/system/cpu/cpufreq/mp-cpufreq/cpu_freq_table"
                freqs = GhettoADB(command)[0].split()

            else:
                command = "cat /sys/devices/system/cpu/cpufreq/mp-cpufreq/kfc_freq_table"
                freqs = GhettoADB(command)[0].split()
            self.cores.append(Core(x, core_freq, freqs, 1, core_type))

    def SetCoreFreqs(self, freqs=[]):
        if not freqs:
            return
        #TODO check freq validity

        for x,f in enumerate(freqs):
            if f is 0:
                self.SetCoreOff(self.cores[x].name)
            else:
                self.SetCoreOn(self.cores[x].name)
                command = "echo " + str(f) + " > /sys/devices/system/cpu/" \
                    + self.cores[x].name + "/cpufreq/scaling_min_freq"
                GhettoADBNoRet(command)
                command = "echo " + str(f) + " > /sys/devices/system/cpu/" \
                    + self.cores[x].name + "/cpufreq/scaling_max_freq"
                GhettoADBNoRet(command)

    def SetCoreOn(self, core):
        command = "echo 1 > /sys/devices/system/cpu/" + core + "/online"
        GhettoADBNoRet(command)

    def SetCoreOff(self, core):
        command = "echo 0 > /sys/devices/system/cpu/" + core + "/online"
        GhettoADBNoRet(command)

    def __init__(self):
        logging.basicConfig(filename="power_testing.log",
                            format='%(asctime)s %(levelname)s:%(message)s', level=logging.DEBUG)
        self.logger = logging.getLogger(__name__)

        isAdbConnected()

        command = "echo userspace > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        GhettoADBNoRet(command)
        command = "echo userspace > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor"
        GhettoADBNoRet(command)
        self.cores = []
        self.GetCores()


