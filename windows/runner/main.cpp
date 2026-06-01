#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

#include "launch_args_constants.h"

namespace {

constexpr wchar_t kSingleInstanceMutexGlobal[] =
    L"Global\\PlugAgente_SingleInstance";
constexpr wchar_t kSingleInstanceMutexLocal[] =
    L"Local\\PlugAgente_SingleInstance";
constexpr wchar_t kRunnerWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr ULONG_PTR kRuntimeDeepLinkMessageId = 0x706c7567;

class MutexGuard {
 public:
  explicit MutexGuard(HANDLE handle) : handle_(handle) {}
  ~MutexGuard() { release(); }
  MutexGuard(const MutexGuard&) = delete;
  MutexGuard& operator=(const MutexGuard&) = delete;

  void release() {
    if (handle_ != nullptr) {
      ::CloseHandle(handle_);
      handle_ = nullptr;
    }
  }

  HANDLE get() const { return handle_; }
  bool is_valid() const { return handle_ != nullptr; }

 private:
  HANDLE handle_;
};

static MutexGuard* g_single_instance_mutex = nullptr;

bool HasAutostartArg(const std::vector<std::string>& args) {
  for (const auto& arg : args) {
    if (arg == plug_agente::kAutostartArg) {
      return true;
    }
  }
  return false;
}

std::string ExtractDeepLinkArgument(const std::vector<std::string>& args) {
  for (const auto& arg : args) {
    if (arg.rfind("plugdb://", 0) == 0 || arg.rfind("http://", 0) == 0 ||
        arg.rfind("https://", 0) == 0) {
      return arg;
    }
  }
  return std::string();
}

bool ForwardDeepLinkToExistingInstance(const std::string& deep_link) {
  if (deep_link.empty()) {
    return false;
  }

  HWND target_window = ::FindWindowW(kRunnerWindowClassName, nullptr);
  if (target_window == nullptr) {
    return false;
  }

  COPYDATASTRUCT copy_data{};
  copy_data.dwData = kRuntimeDeepLinkMessageId;
  copy_data.cbData = static_cast<DWORD>(deep_link.size() + 1);
  copy_data.lpData = const_cast<char*>(deep_link.c_str());

  DWORD_PTR send_result = 0;
  const auto send_status = ::SendMessageTimeoutW(
      target_window, WM_COPYDATA, 0,
      reinterpret_cast<LPARAM>(&copy_data), SMTO_ABORTIFHUNG, 2000,
      &send_result);
  return send_status != 0 && send_result == 0;
}

bool IsRunnerWindowPresent() {
  return ::FindWindowW(kRunnerWindowClassName, nullptr) != nullptr;
}

void HandleSecondInstance(const std::vector<std::string>& args,
                          bool is_autostart) {
  if (is_autostart) {
    return;
  }
  if (ForwardDeepLinkToExistingInstance(ExtractDeepLinkArgument(args))) {
    return;
  }
  wchar_t username[256];
  DWORD username_size = 256;
  wchar_t computer_name[256];
  DWORD computer_name_size = 256;

  const bool has_user = ::GetUserNameW(username, &username_size) != 0;
  const bool has_computer =
      ::GetComputerNameW(computer_name, &computer_name_size) != 0;

  std::wstring msg =
      L"O aplicativo Plug Agente j\u00E1 est\u00E1 em execu\u00E7\u00E3o.\n\n";
  if (has_user) {
    msg += L"Usu\u00E1rio: ";
    msg += username;
    msg += L"\n";
  }
  if (has_computer) {
    msg += L"M\u00E1quina: ";
    msg += computer_name;
  }
  if (!has_user && !has_computer) {
    msg += L"N\u00E3o foi poss\u00EDvel obter informa\u00E7\u00F5es do sistema.";
  }

  ::MessageBoxW(nullptr, msg.c_str(), L"Plug Agente",
                MB_OK | MB_ICONINFORMATION);
}

struct NamedMutexAcquireResult {
  HANDLE handle = nullptr;
  bool existing_instance_detected = false;
  DWORD create_error = ERROR_SUCCESS;
  DWORD open_error = ERROR_SUCCESS;
};

NamedMutexAcquireResult TryAcquireNamedMutex(
    const wchar_t* mutex_name,
    bool access_denied_has_existing_window_evidence = false) {
  NamedMutexAcquireResult result{};
  HANDLE handle = ::CreateMutexW(nullptr, TRUE, mutex_name);
  if (handle != nullptr) {
    if (::GetLastError() == ERROR_ALREADY_EXISTS) {
      result.existing_instance_detected = true;
      ::CloseHandle(handle);
      return result;
    }
    result.handle = handle;
    return result;
  }

  result.create_error = ::GetLastError();
  if (result.create_error != ERROR_ACCESS_DENIED) {
    return result;
  }

  HANDLE existing = ::OpenMutexW(SYNCHRONIZE, FALSE, mutex_name);
  if (existing != nullptr) {
    result.existing_instance_detected = true;
    ::CloseHandle(existing);
    return result;
  }

  result.open_error = ::GetLastError();
  if (access_denied_has_existing_window_evidence &&
      result.open_error == ERROR_ACCESS_DENIED) {
    // Cross-privilege scenario with runner-window evidence: another instance
    // may own a mutex ACL that denies this process from opening it.
    result.existing_instance_detected = true;
  }
  return result;
}

struct SingleInstanceMutexResult {
  HANDLE handle = nullptr;
  bool existing_instance_detected = false;
  bool runner_window_detected = false;
  NamedMutexAcquireResult global_attempt{};
  NamedMutexAcquireResult local_attempt{};
};

SingleInstanceMutexResult CreateSingleInstanceMutexResult() {
  SingleInstanceMutexResult result{};
  result.runner_window_detected = IsRunnerWindowPresent();

  result.global_attempt = TryAcquireNamedMutex(
      kSingleInstanceMutexGlobal,
      result.runner_window_detected);
  if (result.global_attempt.handle != nullptr) {
    result.handle = result.global_attempt.handle;
    return result;
  }
  if (result.global_attempt.existing_instance_detected) {
    result.existing_instance_detected = true;
    return result;
  }

  result.local_attempt = TryAcquireNamedMutex(kSingleInstanceMutexLocal);
  if (result.local_attempt.handle != nullptr) {
    result.handle = result.local_attempt.handle;
    return result;
  }
  if (result.local_attempt.existing_instance_detected) {
    result.existing_instance_detected = true;
  }

  return result;
}

void LogSingleInstanceMutexDiagnostics(
    const SingleInstanceMutexResult& mutex_result,
    const wchar_t* outcome) {
  wchar_t buffer[512];
  const int written = ::swprintf_s(
      buffer,
      L"[plug_agente] Single-instance mutex outcome=%ls "
      L"runner_window_detected=%d "
      L"global_create_error=%lu global_open_error=%lu "
      L"local_create_error=%lu local_open_error=%lu\n",
      outcome,
      mutex_result.runner_window_detected ? 1 : 0,
      static_cast<unsigned long>(mutex_result.global_attempt.create_error),
      static_cast<unsigned long>(mutex_result.global_attempt.open_error),
      static_cast<unsigned long>(mutex_result.local_attempt.create_error),
      static_cast<unsigned long>(mutex_result.local_attempt.open_error));
  if (written <= 0) {
    return;
  }
  ::OutputDebugStringW(buffer);
  if (::IsDebuggerPresent()) {
    std::fwprintf(stderr, L"%ls", buffer);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Single instance: only one app per machine.
  const SingleInstanceMutexResult mutex_result = CreateSingleInstanceMutexResult();
  HANDLE h_mutex = mutex_result.handle;
  if (h_mutex == nullptr) {
    if (mutex_result.existing_instance_detected) {
      LogSingleInstanceMutexDiagnostics(mutex_result, L"existing_instance");
      std::vector<std::string> args = GetCommandLineArguments();
      const bool is_autostart = HasAutostartArg(args);
      HandleSecondInstance(args, is_autostart);
      return EXIT_SUCCESS;
    }
    LogSingleInstanceMutexDiagnostics(mutex_result, L"degraded_no_mutex");
  } else {
    g_single_instance_mutex = new MutexGuard(h_mutex);
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool is_autostart = HasAutostartArg(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, !is_autostart);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"plug_agente", origin, size)) {
    if (g_single_instance_mutex != nullptr) {
      delete g_single_instance_mutex;
      g_single_instance_mutex = nullptr;
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (g_single_instance_mutex != nullptr) {
    delete g_single_instance_mutex;
    g_single_instance_mutex = nullptr;
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
