# Automated testing scripts

## [`set_little`](set_little.sh)

A simple script to set the minimum and maximum frequencies for the little core cluster.

Usage: `./set_little.sh $MIN_FREQ $MAX_FREQ`

## [`set_big`](set_big.sh)

Same as above but for big.

## [`get_combos`](get_combos.py)

Small script that returns all the unique combinations using replacement, meaning that unique combinations are looked for but the order of the items does not matter. This is generally used to find unique test combinations for CPU/GPU frequencies as all cores on a given PU are considered the same as as such the "order" does not matter.

Usage:

Given no arguments, the script returns the combinations of the default test set [0, 10, 25, 50, 75, 100] otherwise the test set is taken from the provided arguments.

Eg. `./get_combos.py 1 2 3 4` will find the unique combinations of the test set [1, 2, 3, 4].

## [`gov_controller`](gov_controller.py)

A small python module for controlling the OdroidXU3's CPU governor. It is implemented to not use PyADB but instead interface with the standard ADB binary. This is to avoid the poor PyADB USB implementation.

The script can set cores on and off as well as setting frequencies to each core.

## [`big_off`](big_off.sh)

Simply turns the big cpu off, nothing more, nothing less.

## [`reset_system`](reset_system.sh)

Resets the system by doing

- Turning the big CPU on
- Sets the min and max frequency for each core to it's receptive min and max

## [`power_tests_simulator_syslogger`](power_tests_simulator_syslogger.sh)

This script profiles the OdroidXU3 for simulated workloads generated using the CPU [stresstester](../stress_tester).
The combinations that are tested are generated using the [get_combos](get_combos.py) script, using the default test set.
Each test performs the following:
- Sets either big and/or little frequency to new test frequency
- Sets up syslogger
- Starts stress tester
- Finishes syslogger
- Pulls result data and converts it using [`trace_conv`](../../trace_conv/trace_conv.py)
- Saves result into appropriate subfolder

Each test is stored with the filname `{big, little}\_$CPU{0,4}_FREQ\_$CPU{1,5}_FREQ\_$CPU{2,6}_FREQ\_$CPU{3,7}_FREQ`

Usage: the only argument the script takes is the output directory where the test results are to be stored.

## [`power_tests_syslogger`](power_tests_syslogger.sh)

Similar to the previous script, this script tests also tests all possible frequency combinations while instead of using the stresstester the script prompts the user when to use the system, eg. play a game, such that organic workloads can be used.

Usage: same as [`power_tests_simulator_syslogger`](power_tests_simulator_syslogger.sh).
