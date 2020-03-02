# System logger for Odroid XU3

The system logger (syslogger) creates and traces, using ftrace, a number of custom trace points that extract system information from a combination of sysfs, kernel stats and device drivers.

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

# OpenGL Tracing

The native OpenGL libraries require modification to enable tracing of frame information. See the folder [opengl_mods](opengl_mods) for more information.

# Authors

- Alex Hoffman (alex.hoffman@tum.de)
- David Hildenbrand (davidhildenbrand@gmail.com)
