# Triangle using Zig and wgpu

Just testing out drawing a triangle in Zig using wgpu. Nothing fancy, trying the interop between Zig and C APIs.

Uses:
* [glfw](https://github.com/glfw/glfw)
* [wgpu-native](https://github.com/gfx-rs/wgpu-native/)

Uses pre-built third-party libraries for simplicity but one drawback with this is that you will need to build using MSVC on Window:
```
> zig build run -Dtarget=x86_64-windows-msvc
```
Ideally you might want to setup compilation for the third-party stuff as well, like https://github.com/hexops/mach-gpu-dawn, to simplify cross-compiling. That's out of scope here however.

For anyone actually wanting to make a graphics application/game with Zig, I recommend having a look at:
* [mach](https://machengine.org/)
* [zig-gamedev](https://github.com/zig-gamedev/zig-gamedev)

