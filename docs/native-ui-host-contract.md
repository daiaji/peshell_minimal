# Native UI Host Contract

`peshell_minimal` keeps ImGui orchestration in Lua, but the real Win32/D3D11
objects must come from the native host. LuaJIT FFI can call cimgui, but creating
and owning HWND, swap chain, render target, and device lifetime is safer in C++.

The host should expose `_G.pesh_native.ui` with these functions:

- `create_window(title, width, height) -> window | nil, err`
- `destroy_window(window) -> true | nil, err`
- `create_d3d11(window) -> d3d | nil, err`
- `begin_d3d11_frame(d3d) -> true | nil, err`
- `end_d3d11_frame(d3d) -> true | nil, err`
- `destroy_d3d11(d3d) -> true | nil, err`
- `poll_events() -> running`

Expected object fields:

- `window.hwnd`: HWND pointer usable by `ImGui_ImplWin32_Init`.
- `d3d.device`: ID3D11Device pointer usable by `ImGui_ImplDX11_Init`.
- `d3d.device_context`: ID3D11DeviceContext pointer.
- `d3d.swap_chain`: IDXGISwapChain pointer, for host-side present/resize.

`src/main.cpp` currently implements this contract for the Windows host. It
returns lightuserdata pointer fields for cimgui and keeps native ownership in the
host-side `_native` fields. Destroy functions clear those `_native` fields after
releasing the C++ objects.

Lua modules already prepared for this contract:

- `ui.native_host`: validates and obtains handles from the host.
- `ui.backends.win32_d3d11`: initializes cimgui Win32/DX11 backend with handles.
- `ui.runtime`: drives frame lifecycle once a backend is selected.

`plugins.imgui` exposes `imgui-native-smoke` as the first end-to-end command. It
creates the native host resources, runs a short ImGui frame loop, and then tears
the resources down.
