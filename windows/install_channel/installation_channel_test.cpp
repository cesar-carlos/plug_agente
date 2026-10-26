#include "installation_channel.h"
#include <iostream>
#include <stdexcept>
using namespace plug::installation;
namespace fs = std::filesystem;
namespace {
void require(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
DWORD call(const fs::path& client, const fs::path& directory, const std::wstring& operation, const wchar_t* command) {
  std::wstring args = L"\"" + client.native() + L"\" --call \"" + directory.native() + L"\" " + operation + L" " + command;
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
  if (!CreateProcessW(client.c_str(), args.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process))
    throw std::runtime_error("fixture_client_start_failed");
  CloseHandle(process.hThread);
  const auto wait = WaitForSingleObject(process.hProcess, 10000);
  DWORD code = 255; GetExitCodeProcess(process.hProcess, &code); CloseHandle(process.hProcess);
  require(wait == WAIT_OBJECT_0, "fixture_client_timeout"); return code;
}
}
int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 5 && std::wstring(argv[1]) == L"--call") {
      std::wstring op(argv[3]);
      try { prepare_installation(argv[2], std::string(op.begin(), op.end()), std::wstring(argv[4]) == L"request", std::wstring(argv[4]) == L"cancel"); }
      catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return std::string(error.what()) == "installation_waiting_for_exit" ? 10 : 11;
      }
      return 0;
    }
    wchar_t path[32768]; require(GetModuleFileNameW(nullptr, path, 32768) != 0, "fixture_path_failed");
    const auto directory = fs::path(path).parent_path();
    const auto client = directory / L"updater" / L"plug_update_client.exe";
    const std::wstring operation(32, L'a');
    require(valid_operation(std::string(32, 'a')) && !valid_operation("bad") && !valid_operation(std::string(32, 'g')), "invalid_operation_accepted");
    require(endpoint(current_executable(), 1) != endpoint(current_executable(), 2), "pid_not_bound");
    require(endpoint(L"c:\\a.exe", 1) != endpoint(L"c:\\b.exe", 1), "path_not_bound");
    std::string absent_failure;
    try { prepare_installation(directory, std::string(32, 'a'), true); }
    catch (const std::exception& error) { absent_failure = error.what(); }
    require(absent_failure == "close_previous_application_manually", "absent_channel_must_require_manual_exit");
    const auto occupied_name = endpoint(current_executable(), GetCurrentProcessId());
    HANDLE occupied = CreateNamedPipeW(occupied_name.c_str(), PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 4096, 4096, 0, nullptr);
    require(occupied != INVALID_HANDLE_VALUE, "fixture_pipe_creation_failed");
    HANDLE connection = CreateFileW(occupied_name.c_str(), GENERIC_READ | GENERIC_WRITE,
      0, nullptr, OPEN_EXISTING, 0, nullptr);
    require(connection != INVALID_HANDLE_VALUE, "fixture_pipe_connection_failed");
    std::string busy_failure;
    try { prepare_installation(directory, std::string(32, 'a'), true); }
    catch (const std::exception& error) { busy_failure = error.what(); }
    CloseHandle(connection);
    require(busy_failure == "installation_channel_busy", "busy_channel_misclassified_as_legacy");
    {
      Channel unavailable;
      const bool started = unavailable.start();
      CloseHandle(occupied);
      require(!started, "unavailable_channel_reported_ready");
      require(!unavailable.start(), "failed_channel_restart_reported_ready");
    }
    Channel channel; require(channel.start(), "channel_start_failed");
    require(channel.start(), "enabled_channel_not_idempotent");
    // Wait for endpoint creation only; no preparation is retried.
    const auto pipe = endpoint(current_executable(), GetCurrentProcessId());
    for (unsigned i = 0; i < 100 && !WaitNamedPipeW(pipe.c_str(), 10); ++i) Sleep(10);
    bool unauthorized = false;
    try { prepare_installation(directory, std::string(32, 'a'), true); } catch (...) { unauthorized = true; }
    require(unauthorized && channel.poll().empty(), "unauthorized_caller_started_preparation");
    require(call(client, directory, operation, L"status") == 11, "query_started_preparation");
    require(channel.poll().empty(), "query_delivered_effect");
    require(call(client, directory, operation, L"request") == 10, "authorized_request_failed");
    require(channel.poll() == std::string(32, 'a'), "request_not_delivered");
    require(channel.poll().empty(), "request_replayed");
    require(call(client, directory, operation, L"request") == 10 && channel.poll().empty(), "duplicate_request_replayed");
    require(call(client, directory, operation, L"status") == 10, "status_failed");
    require(call(client, directory, std::wstring(32, L'b'), L"request") == 11, "different_operation_accepted");
    require(call(client, directory, operation, L"cancel") == 10 && channel.cancelled(), "cancel_not_delivered");
    channel.report("{\"operation\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"state\":\"recoveryRequired\"}");
    require(call(client, directory, operation, L"status") == 11, "recovery_not_blocked");
    require(channel.poll().empty(), "status_replayed_effect");
    std::cout << "Installation channel contract passed\n"; return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
