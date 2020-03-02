# OpenGL Modifications

To trace frame information the native OpenGL libraries must be modified such that the kernel can be given frame information via IOctl. This is done by modifying the `eglSwapBuffers` call to wrap the standard swapping of frames in debug code that sends frame timing information to the kernel via an IOctl call. The modified native Android frameworks can be found [here](https://github.com/alxhoff/android_frameworks_native_new). A patch containing the necessary modifications is [here](native_frameworks.patch).

`git submodule update --init --recursive` will also pull the modified frameworks into directory.
