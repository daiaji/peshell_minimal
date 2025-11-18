#pragma once
#include <string>

// Windows.h 需要在spdlog等之前被包含，以避免宏冲突
#if defined(_WIN32)
#include <windows.h>
#endif

void InitializeLogger(const std::string& package_root_dir, DWORD pid, int argc, char* argv[]);
void ShutdownLogger();