#pragma once
#include <windows.h>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <string>
#include <filesystem>
#include <stdexcept>

namespace plug::installation {
class DiagnosticError : public std::runtime_error {
 public:
  DiagnosticError(const char* code, const char* operation, DWORD pid, DWORD error)
      : std::runtime_error(code), operation(operation), pid(pid), win32_error(error) {}
  const std::string operation;
  const DWORD pid;
  const DWORD win32_error;
};
std::wstring canonical_executable(const std::filesystem::path& path);
std::wstring current_executable();
std::wstring endpoint(const std::wstring& image, DWORD pid);
bool valid_operation(const std::string& operation);
// Checks every process of the target executable. Never terminates a process.
void prepare_installation(const std::filesystem::path& directory,
                          const std::string& operation, bool request, bool cancel = false);
class Channel {
 public:
  Channel();
  ~Channel();
  bool start();
  std::string poll();
  bool cancelled();
  void report(const std::string& response);
 private:
  void serve();
  std::atomic<bool> stopping_{false};
  HANDLE stop_ = nullptr;
  std::thread thread_;
  std::mutex mutex_;
  std::condition_variable startup_;
  bool startup_finished_ = false;
  bool available_ = false;
  std::string operation_, state_ = "idle";
  bool delivered_ = false;
  bool cancelled_ = false;
};
}
