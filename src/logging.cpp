#include "logging.h"

#include <spdlog/async.h>
#include <spdlog/pattern_formatter.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>

namespace
{
    std::atomic<bool> g_shutdown_flag(false);
    std::thread       g_config_monitor_thread;
    std::wstring      g_config_dir_wstr;
    HANDLE            g_hConfigDirHandle = INVALID_HANDLE_VALUE;

    const char* PLAIN_LOG_PATTERN = "[%Y-%m-%d %H:%M:%S.%f] [pid:%P] [thread:%t] [%^%l%$] %v";
    const char* JSON_LOG_PATTERN = R"({"timestamp":"%Y-%m-%d %H:%M:%S.%f","level":"%l","thread":%t,"pid":%P,"message":"%v"})";

    spdlog::level::level_enum level_from_string(const std::string& level_str)
    {
        if (level_str == "trace") return spdlog::level::trace;
        if (level_str == "debug") return spdlog::level::debug;
        if (level_str == "warn") return spdlog::level::warn;
        if (level_str == "error") return spdlog::level::err;
        if (level_str == "critical") return spdlog::level::critical;
        if (level_str == "off") return spdlog::level::off;
        return spdlog::level::info;
    }

    void apply_log_settings(const std::filesystem::path& config_path)
    {
        std::string level_str  = "info";
        std::string format_str = "plain";

        std::ifstream config_file(config_path);
        if (config_file.is_open())
        {
            std::string line;
            while (std::getline(config_file, line))
            {
                size_t comment_pos = line.find(';');
                if (comment_pos != std::string::npos) line = line.substr(0, comment_pos);
                line.erase(0, line.find_first_not_of(" \t\r\n"));
                line.erase(line.find_last_not_of(" \t\r\n") + 1);
                if (line.empty() || line[0] == '[') continue;
                size_t equals_pos = line.find('=');
                if (equals_pos != std::string::npos) {
                    std::string key = line.substr(0, equals_pos);
                    key.erase(key.find_last_not_of(" \t") + 1);
                    std::string value = line.substr(equals_pos + 1);
                    value.erase(0, value.find_first_not_of(" \t"));
                    if (key == "level") level_str = value;
                    else if (key == "format") format_str = value;
                }
            }
        }

        auto level = level_from_string(level_str);
        spdlog::apply_all([&](std::shared_ptr<spdlog::logger> l) { l->set_level(level); });

        if (format_str == "json") {
            spdlog::default_logger()->set_formatter(std::make_unique<spdlog::pattern_formatter>(JSON_LOG_PATTERN, spdlog::pattern_time_type::local));
        } else {
            spdlog::default_logger()->set_formatter(std::make_unique<spdlog::pattern_formatter>(PLAIN_LOG_PATTERN, spdlog::pattern_time_type::local));
        }
        
        if (spdlog::default_logger() && spdlog::default_logger()->name() == "peshell") {
            spdlog::default_logger()->info("Log settings applied. Level: {}, Format: {}", level_str, format_str);
        }
    }

    void monitor_config_thread_func(std::filesystem::path config_path)
    {
        g_hConfigDirHandle = CreateFileW(g_config_dir_wstr.c_str(), FILE_LIST_DIRECTORY,
                                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                                         FILE_FLAG_BACKUP_SEMANTICS, NULL);

        if (g_hConfigDirHandle == INVALID_HANDLE_VALUE) {
            spdlog::error("Failed to get config dir handle. Error: {}", GetLastError());
            return;
        }

        char  buffer[4096];
        DWORD bytesReturned;

        while (!g_shutdown_flag)
        {
            if (ReadDirectoryChangesW(g_hConfigDirHandle, buffer, sizeof(buffer), FALSE,
                                      FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_FILE_NAME, &bytesReturned,
                                      NULL, NULL))
            {
                if (g_shutdown_flag) break;
                Sleep(200);
                spdlog::info("Config change detected, reloading...");
                apply_log_settings(config_path);
            }
            else
            {
                if (g_shutdown_flag || GetLastError() == ERROR_OPERATION_ABORTED) break;
                spdlog::warn("ReadDirectoryChangesW failed. Error: {}", GetLastError());
                Sleep(5000);
            }
        }
        CloseHandle(g_hConfigDirHandle);
        g_hConfigDirHandle = INVALID_HANDLE_VALUE;
        spdlog::trace("Config monitor thread shut down.");
    }
}

void InitializeLogger(const std::string& package_root_dir, DWORD pid, int argc, char* argv[])
{
    try
    {
        std::filesystem::path config_dir = std::filesystem::path(package_root_dir) / "config";
        std::filesystem::create_directories(config_dir);
        std::filesystem::path config_path = config_dir / "logging.ini";
        g_config_dir_wstr = config_path.parent_path().wstring();

        auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        auto placeholder_logger = std::make_shared<spdlog::logger>("placeholder", console_sink);
        spdlog::set_default_logger(placeholder_logger);

        if (!std::filesystem::exists(config_path)) {
            std::ofstream default_config(config_path);
            if (default_config.is_open()) {
                default_config << "[Logging]\nlevel = info\nformat = plain\n";
            }
        }

        spdlog::init_thread_pool(8192, 1);
        std::vector<spdlog::sink_ptr> sinks;
        sinks.push_back(console_sink);

        auto now = std::chrono::system_clock::now();
        auto in_time_t = std::chrono::system_clock::to_time_t(now);
        std::stringstream timestamp_ss;
        tm tm_buf;
        localtime_s(&tm_buf, &in_time_t);
        timestamp_ss << std::put_time(&tm_buf, "%Y%m%d%H%M%S");

        std::filesystem::path log_dir = std::filesystem::path(package_root_dir) / "logs";
        std::filesystem::create_directories(log_dir);
        std::string log_filename = fmt::format("peshell_{}_{}.log", pid, timestamp_ss.str());
        std::filesystem::path file_path = log_dir / log_filename;

        auto rotating_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(file_path.string(), 5 * 1024 * 1024, 10);
        sinks.push_back(rotating_sink);

        auto logger = std::make_shared<spdlog::async_logger>("peshell", begin(sinks), end(sinks), spdlog::thread_pool(), spdlog::async_overflow_policy::block);
        spdlog::set_default_logger(logger);

        apply_log_settings(config_path);

        std::string command_line;
        for (int i = 0; i < argc; ++i) command_line += (std::string(argv[i]) + " ");
        if (!command_line.empty()) command_line.pop_back();

        spdlog::info("Session start. PID: {}. Command line: \"{}\"", pid, command_line);
        g_config_monitor_thread = std::thread(monitor_config_thread_func, config_path);
    }
    catch (const spdlog::spdlog_ex& ex)
    {
        std::cerr << "Log init failed: " << ex.what() << std::endl;
    }
}

void ShutdownLogger()
{
    spdlog::info("Logger shutdown requested.");
    g_shutdown_flag = true;
    if (g_hConfigDirHandle != INVALID_HANDLE_VALUE) CancelIoEx(g_hConfigDirHandle, NULL);
    if (g_config_monitor_thread.joinable()) g_config_monitor_thread.join();
    spdlog::shutdown();
}