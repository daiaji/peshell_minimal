#include <d3d11.h>
#include <stdint.h>
#include <windows.h>

#define ImGui_ImplWin32_Init ImGui_ImplWin32_Init_internal
#define ImGui_ImplWin32_Shutdown ImGui_ImplWin32_Shutdown_internal
#define ImGui_ImplWin32_NewFrame ImGui_ImplWin32_NewFrame_internal
#define ImGui_ImplWin32_WndProcHandler ImGui_ImplWin32_WndProcHandler_internal
#define ImGui_ImplDX11_Init ImGui_ImplDX11_Init_internal
#define ImGui_ImplDX11_Shutdown ImGui_ImplDX11_Shutdown_internal
#define ImGui_ImplDX11_NewFrame ImGui_ImplDX11_NewFrame_internal
#define ImGui_ImplDX11_RenderDrawData ImGui_ImplDX11_RenderDrawData_internal

#include "imgui/imgui.h"
#include "imgui/backends/imgui_impl_dx11.h"
#include "imgui/backends/imgui_impl_win32.h"
#include "imgui/backends/imgui_impl_dx11.cpp"
#include "imgui/backends/imgui_impl_win32.cpp"

#undef ImGui_ImplWin32_Init
#undef ImGui_ImplWin32_Shutdown
#undef ImGui_ImplWin32_NewFrame
#undef ImGui_ImplWin32_WndProcHandler
#undef ImGui_ImplDX11_Init
#undef ImGui_ImplDX11_Shutdown
#undef ImGui_ImplDX11_NewFrame
#undef ImGui_ImplDX11_RenderDrawData

#define PESHELL_CIMGUI_EXPORT extern "C" __declspec(dllexport)

extern "C" {

PESHELL_CIMGUI_EXPORT bool ImGui_ImplWin32_Init(void* hwnd) {
    return ::ImGui_ImplWin32_Init_internal(static_cast<HWND>(hwnd));
}

PESHELL_CIMGUI_EXPORT void ImGui_ImplWin32_Shutdown(void) {
    ::ImGui_ImplWin32_Shutdown_internal();
}

PESHELL_CIMGUI_EXPORT void ImGui_ImplWin32_NewFrame(void) {
    ::ImGui_ImplWin32_NewFrame_internal();
}

PESHELL_CIMGUI_EXPORT long ImGui_ImplWin32_WndProcHandler(void* hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam) {
    return static_cast<long>(::ImGui_ImplWin32_WndProcHandler_internal(
        static_cast<HWND>(hwnd),
        msg,
        static_cast<WPARAM>(wParam),
        static_cast<LPARAM>(lParam)));
}

PESHELL_CIMGUI_EXPORT bool ImGui_ImplDX11_Init(ID3D11Device* device, ID3D11DeviceContext* device_context) {
    return ::ImGui_ImplDX11_Init_internal(device, device_context);
}

PESHELL_CIMGUI_EXPORT void ImGui_ImplDX11_Shutdown(void) {
    ::ImGui_ImplDX11_Shutdown_internal();
}

PESHELL_CIMGUI_EXPORT void ImGui_ImplDX11_NewFrame(void) {
    ::ImGui_ImplDX11_NewFrame_internal();
}

PESHELL_CIMGUI_EXPORT void ImGui_ImplDX11_RenderDrawData(ImDrawData* draw_data) {
    ::ImGui_ImplDX11_RenderDrawData_internal(reinterpret_cast<::ImDrawData*>(draw_data));
}

}
