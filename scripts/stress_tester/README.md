# Android stresstester

This script uses the Android stresstester (not on Github yet but binary in this folder) to automate the controlled generation of arithmetic loads on target CPU cores.

usage is as follows

```
usage: android_runStresstest.sh  --duration     | -d   <ms>
                                 --cores        | -c   <core> (FOR NOW ONLY ONE CORE AT A TIME;
                                                               DEFINE MULTIPLE CORES WITH [..] -c <core1> -c <core2> ...)
                                 --workload     | -w   <workload> (SAME AS ABOVE)
                                 --threads      | -t   <num threads>
                                 --verbose      | -v
                                 --slotDuration | -s <ms>
```
