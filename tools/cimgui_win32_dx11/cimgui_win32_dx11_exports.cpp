#include "cimgui.h"

#include <d3d11.h>
#include <stdint.h>
#include <windows.h>

#include "imgui.h"
#include "imgui/backends/imgui_impl_dx11.h"
#include "imgui/backends/imgui_impl_win32.h"

extern "C" {

CIMGUI_API bool ImGui_ImplWin32_Init(void* hwnd) {
    return ::ImGui_ImplWin32_Init(static_cast<HWND>(hwnd));
}

CIMGUI_API void ImGui_ImplWin32_Shutdown(void) {
    ::ImGui_ImplWin32_Shutdown();
}

CIMGUI_API void ImGui_ImplWin32_NewFrame(void) {
    ::ImGui_ImplWin32_NewFrame();
}

CIMGUI_API long ImGui_ImplWin32_WndProcHandler(void* hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam) {
    return static_cast<long>(::ImGui_ImplWin32_WndProcHandler(
        static_cast<HWND>(hwnd),
        msg,
        static_cast<WPARAM>(wParam),
        static_cast<LPARAM>(lParam)));
}

CIMGUI_API bool ImGui_ImplDX11_Init(ID3D11Device* device, ID3D11DeviceContext* device_context) {
    return ::ImGui_ImplDX11_Init(device, device_context);
}

CIMGUI_API void ImGui_ImplDX11_Shutdown(void) {
    ::ImGui_ImplDX11_Shutdown();
}

CIMGUI_API void ImGui_ImplDX11_NewFrame(void) {
    ::ImGui_ImplDX11_NewFrame();
}

CIMGUI_API void ImGui_ImplDX11_RenderDrawData(ImDrawData* draw_data) {
    ::ImGui_ImplDX11_RenderDrawData(reinterpret_cast<::ImDrawData*>(draw_data));
}

}
