# ImGui Spike

This is the first PEShell UI probe layer. Lua owns ImGui orchestration and the
C++ host owns Win32/D3D11 object lifetime.

The user-facing GUI target is an AutoHotkey v2-like Lua API: object-oriented
windows, controls, values, and event callbacks. ImGui/cimgui is the rendering
backend, not the scripting surface that every PE script must use directly.

The practical complexity target is the familiar CGI-style WinPE system deployer:
image path picker, target disk/partition table, deployment options, progress,
logs, and confirm/error dialogs. This does not require WebView, WinUI, or .NET;
ImGui is sufficient and still leaves room for custom themes and richer drawing.

## Current State

- `scripts/lib/ui/imgui.lua` loads `ffi.cimgui` when present, otherwise tries
  common `cimgui` DLL names through `ffi.load`.
- `scripts/plugins/imgui/init.lua` registers `imgui-probe` and
  `imgui-native-smoke`.
- `scripts/test_imgui_probe.lua` is an offline smoke test. It passes both when
  cimgui is present and when dependencies are missing.
- `scripts/lib/ui/runtime.lua` defines a small backend-neutral runtime contract.
- `scripts/lib/ui/backends/null.lua` is a headless backend for offline tests.
- `scripts/lib/ui/backends/win32_d3d11.lua` initializes cimgui Win32/DX11 and
  delegates event polling, render-target setup, and present to the native host.
- `scripts/lib/ui/native_host.lua` obtains HWND/D3D11 handles from
  `_G.pesh_native.ui`. See `docs/native-ui-host-contract.md`.
- `src/main.cpp` exposes `_G.pesh_native.ui` with Win32 window creation, D3D11
  swap-chain/device/context creation, frame begin/end, message polling, and
  destruction hooks.
- `scripts/lib/ui/widgets/message_box.lua` provides a message-box view model and
  an ImGui draw function covered by an offline stub test.
- `scripts/lib/ui/widgets/file_picker.lua` provides open/save/folder picker state
  and selection logic plus an ImGui draw function covered by an offline stub
  test.
- `imgui-native-smoke` draws both widgets so the Windows backend smoke test has
  real UI components once cimgui is available.

## Missing Runtime Dependencies

- Windows build verification with MSVC/Windows SDK.
- Real render verification on Windows with `cimgui.dll` next to `peshell.exe`.

## Next UI Milestone

1. Keep CI building and packaging `cimgui.dll` beside `peshell.exe`.
2. Build and run `imgui-native-smoke` on Windows.
3. Add swap-chain resize handling.
4. Add an AHK v2-like `ui.gui` layer on top of the widget/runtime primitives.
5. Add progress/log view and screenshot preview on top of the backend.

Priority controls for the `ui.gui` layer: `Text`, `Button`, `Edit`, `Checkbox`,
`Radio`, `DropDownList`, `ListView/Table`, `Progress`, `Tab`, `StatusBar`,
`LogView`, `PathPicker`, `DiskList`, and `ConfirmDialog`.
