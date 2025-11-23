#pragma once
#include <string>

#if defined(_WIN32)
#include <windows.h>
#endif

void InitializeLogger(const std::string& package_root_dir, DWORD pid, int argc, char* argv[]);
void ShutdownLogger();