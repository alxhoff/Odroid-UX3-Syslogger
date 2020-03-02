# System logger for Odroid XU3 based off of ftrace

The system logger (syslogger) creates and traces a number of custom trace points that extract system information from a combination of sysfs, kernel stats and device drivers.

The system logger implements custom tracing for the following:

- OpenGL frames:
    - Timestamps
    - Inter-frame periods
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
