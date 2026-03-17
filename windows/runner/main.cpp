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

void HandleSecondInstance(bool is_autostart) {
  if (is_autostart) {
    return;
  }
  wchar_t username[256];
  DWORD username_size = 256;
  wchar_t computer_name[256];
  DWORD computer_name_size = 256;

  const bool has_user = ::GetUserNameW(username, &username_size) != 0;
  const bool has_computer =
      ::GetComputerNameW(computer_name, &computer_name_size) != 0;

  std::wstring msg = L"O aplicativo Plug Agente já está em execução.\n\n";
  if (has_user) {
    msg += L"Usuário: ";
    msg += username;
    msg += L"\n";
  }
  if (has_computer) {
    msg += L"Máquina: ";
    msg += computer_name;
  }
  if (!has_user && !has_computer) {
    msg += L"Não foi possível obter informações do sistema.";
  }

  ::MessageBoxW(nullptr, msg.c_str(), L"Plug Agente",
                MB_OK | MB_ICONINFORMATION);
}

HANDLE CreateSingleInstanceMutex() {
  HANDLE h = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexGlobal);
  if (h != nullptr && ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return h;
  }
  if (h != nullptr) {
    ::CloseHandle(h);
    return nullptr;
  }
  h = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexLocal);
  if (h != nullptr && ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return h;
  }
  if (h != nullptr) {
    ::CloseHandle(h);
  }
  return nullptr;
}

bool IsAnotherInstanceRunning() {
  HANDLE h = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexGlobal);
  if (h == nullptr) {
    h = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexLocal);
  }
  if (h == nullptr) {
    return false;
  }
  const bool already_exists = (::GetLastError() == ERROR_ALREADY_EXISTS);
  ::CloseHandle(h);
  return already_exists;
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
  HANDLE h_mutex = CreateSingleInstanceMutex();
  if (h_mutex == nullptr) {
    if (IsAnotherInstanceRunning()) {
      std::vector<std::string> args = GetCommandLineArguments();
      const bool is_autostart = HasAutostartArg(args);
      HandleSecondInstance(is_autostart);
      return EXIT_SUCCESS;
    }
    if (::IsDebuggerPresent()) {
      std::fprintf(stderr,
                   "[plug_agente] Single-instance mutex failed; continuing "
                   "without protection.\n");
    }
  } else {
    g_single_instance_mutex = new MutexGuard(h_mutex);
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
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
