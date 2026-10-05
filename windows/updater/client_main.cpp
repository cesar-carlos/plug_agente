#include "win_security.h"
#include "trusted_keys.h"
#include <winsvc.h>
#include <iostream>

using namespace plug::updater;
namespace {
void prepare_control(const std::string& worker_version = "") {
  if (!is_admin()) throw std::runtime_error("administrator_required");
  if (fs::exists(control_root())) assert_protected_tree(control_root(), true);
  if (fs::exists(updater_root())) assert_protected_tree(updater_root());
  protect_directory(control_root(), true);
  protect_directory(control_root() / L"workers", true);
  if (!worker_version.empty()) {
    if (!std::regex_match(worker_version, std::regex("[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+")))
      throw std::runtime_error("invalid_worker_version");
    protect_directory(control_root() / L"workers" / wide(worker_version), true);
  }
  protect_directory(updater_root());
}
void revoke() {
  if (!is_admin()) throw std::runtime_error("administrator_required");
  assert_protected_directory(updater_root());
  const auto policy_path = updater_root() / L"policy.json";
  // A failed first enrollment may not have created an authorization policy yet.
  if (!fs::exists(policy_path)) return;
  auto policy = parse_json(read_file(policy_path));
  policy["enabled"] = false;
  write_atomic(policy_path, policy.dump());
}
void check_install(bool automatic) {
  const auto journal_path = updater_root() / L"journal.json";
  if (!fs::exists(journal_path)) {
    if (automatic) throw std::runtime_error("automatic_operation_missing");
    return;
  }
  assert_protected_directory(updater_root());
  const auto job = parse_json(read_file(journal_path));
  const auto state = job.value("state", "idle");
  if (automatic) {
    HANDLE raw = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw)) throw std::runtime_error("setup_identity_unconfirmed");
    Handle token(raw); DWORD size = 0; GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
    std::vector<uint8_t> user(size);
    if (!GetTokenInformation(token.get(), TokenUser, user.data(), size, &size) ||
        !IsWellKnownSid(reinterpret_cast<TOKEN_USER*>(user.data())->User.Sid, WinLocalSystemSid) || state != "installing")
      throw std::runtime_error("automatic_setup_identity_rejected");
    return;
  }
  if (state == "waitingForExit" || state == "snapshotting" || state == "installing" || state == "verifying" ||
      state == "rollingBack" || state == "restoringUserData" || state == "recoveryRequired")
    throw std::runtime_error("update_operation_prevents_manual_install");
}
void enroll(const fs::path& install, const fs::path& installer, const std::string& channel, const std::string& worker_version) {
  if (!is_admin()) throw std::runtime_error("administrator_required");
  if (std::string(kFeedPublicKeys).empty()) throw std::runtime_error("feed_keys_unavailable");
  if (channel != "stable" && channel != "beta" && channel != "internal") throw std::runtime_error("invalid_channel");
  if (!std::regex_match(worker_version, std::regex("[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+")))
    throw std::runtime_error("invalid_worker_version");
  reject_reparse_path(install); reject_reparse_path(installer);
  // Pin the source and all its ancestors through verification and copying.
  PinnedPath pinned_installer(installer);
  PinnedPath pinned_app(install / L"plug_agente.exe");
  PinnedPath pinned_host(control_root() / L"plug_update_service.exe");
  PinnedPath pinned_worker(control_root() / L"workers" / wide(worker_version) / L"plug_update_worker.exe");
  const auto publisher = trusted_publisher(control_root() / L"plug_update_service.exe");
  if (trusted_publisher(installer) != publisher || trusted_publisher(install / L"plug_agente.exe") != publisher ||
      trusted_publisher(control_root() / L"workers" / wide(worker_version) / L"plug_update_worker.exe") != publisher)
    throw std::runtime_error("enrollment_publisher_rejected");
  assert_protected_tree(control_root(), true);
  assert_protected_tree(updater_root());
  protect_directory(updater_root()); protect_directory(control_root(), true);
  const auto baseline = updater_root() / L"baseline"; protect_directory(baseline);
  const auto baseline_installer = baseline / L"setup.exe";
  if (!fs::exists(baseline_installer)) {
    PinnedPath pinned_baseline_directory(baseline);
    if (!CopyFileW(installer.c_str(), baseline_installer.c_str(), TRUE)) throw std::runtime_error("baseline_copy_failed");
    PinnedPath pinned_baseline(baseline_installer);
    if (sha256_file(baseline_installer) != sha256_file(installer) || trusted_publisher(baseline_installer) != publisher)
      throw std::runtime_error("baseline_validation_failed");
  } else {
    PinnedPath pinned_baseline(baseline_installer);
    if (trusted_publisher(baseline_installer) != publisher) throw std::runtime_error("baseline_publisher_rejected");
  }
  Json policy{{"protocol", 1}, {"enabled", true}, {"applicationContractValidated", false}, {"channel", channel}, {"installDirectory", utf8(install.native())},
              {"capabilities", kCapabilities}, {"publicKeys", kFeedPublicKeys}, {"publishers", {publisher}}, {"workerVersion", worker_version}};
  if (fs::exists(updater_root() / L"policy.json")) {
    const auto previous = parse_json(read_file(updater_root() / L"policy.json"));
    // Preserve previously approved additions during a routine reinstall.
    policy["capabilities"] = previous.at("capabilities"); policy["publishers"] = previous.at("publishers");
    if (std::find(policy["publishers"].begin(), policy["publishers"].end(), publisher) == policy["publishers"].end())
      policy["publishers"].push_back(publisher);
  }
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT | SC_MANAGER_CREATE_SERVICE);
  if (!manager) throw std::runtime_error("service_manager_denied");
  const auto executable = quote((control_root() / L"plug_update_service.exe").native());
  SC_HANDLE service = CreateServiceW(manager, L"PlugAgenteUpdater", L"Plug Agente Updater", SERVICE_START | SERVICE_CHANGE_CONFIG | SERVICE_QUERY_CONFIG,
      SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START, SERVICE_ERROR_NORMAL, executable.c_str(), nullptr, nullptr, nullptr, L"LocalSystem", nullptr);
  if (!service && GetLastError() == ERROR_SERVICE_EXISTS) service = OpenServiceW(manager, L"PlugAgenteUpdater", SERVICE_START | SERVICE_CHANGE_CONFIG | SERVICE_QUERY_CONFIG);
  if (!service) { CloseServiceHandle(manager); throw std::runtime_error("service_registration_failed"); }
  DWORD size = 0;
  QueryServiceConfigW(service, nullptr, 0, &size);
  std::vector<uint8_t> configuration(size);
  auto config = reinterpret_cast<QUERY_SERVICE_CONFIGW*>(configuration.data());
  const bool compatible = size != 0 && QueryServiceConfigW(service, config, size, &size) &&
      executable == config->lpBinaryPathName && _wcsicmp(config->lpServiceStartName, L"LocalSystem") == 0 &&
      config->dwServiceType == SERVICE_WIN32_OWN_PROCESS;
  if (!compatible) { CloseServiceHandle(service); CloseServiceHandle(manager); throw std::runtime_error("service_contract_rejected"); }
  write_atomic(updater_root() / L"policy.json", policy.dump());
  SERVICE_DELAYED_AUTO_START_INFO delayed{TRUE}; ChangeServiceConfig2W(service, SERVICE_CONFIG_DELAYED_AUTO_START_INFO, &delayed);
  const bool started = StartServiceW(service, 0, nullptr) || GetLastError() == ERROR_SERVICE_ALREADY_RUNNING;
  CloseServiceHandle(service); CloseServiceHandle(manager);
  if (!started) throw std::runtime_error("service_start_failed");
}
void remove_service() {
  if (!is_admin()) throw std::runtime_error("administrator_required");
  const auto state_path = updater_root() / L"journal.json";
  if (fs::exists(state_path)) {
    const auto state = parse_json(read_file(state_path)).value("state", "idle");
    if (state == "installing" || state == "verifying" || state == "rollingBack" || state == "waitingForExit" ||
        state == "snapshotting" || state == "restoringUserData" || state == "recoveryRequired")
      throw std::runtime_error("active_update_prevents_uninstall");
  }
  if (fs::exists(updater_root() / L"policy.json")) {
    auto policy = parse_json(read_file(updater_root() / L"policy.json")); policy["enabled"] = false;
    write_atomic(updater_root() / L"policy.json", policy.dump());
  }
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!manager) throw std::runtime_error("service_manager_denied");
  SC_HANDLE service = OpenServiceW(manager, L"PlugAgenteUpdater", SERVICE_STOP | SERVICE_QUERY_STATUS | DELETE);
  if (!service) { const auto error = GetLastError(); CloseServiceHandle(manager); if (error == ERROR_SERVICE_DOES_NOT_EXIST) return; throw std::runtime_error("service_open_failed"); }
  SERVICE_STATUS status{}; ControlService(service, SERVICE_CONTROL_STOP, &status);
  for (unsigned count = 0; count < 100; ++count) {
    if (QueryServiceStatus(service, &status) && status.dwCurrentState == SERVICE_STOPPED) break;
    Sleep(100);
  }
  const bool removed = status.dwCurrentState == SERVICE_STOPPED && DeleteService(service);
  CloseServiceHandle(service); CloseServiceHandle(manager);
  if (!removed) throw std::runtime_error("service_removal_unconfirmed");
}
}
int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 2 && std::wstring(argv[1]) == L"--prepare-control") { prepare_control(); return 0; }
    if (argc == 3 && std::wstring(argv[1]) == L"--prepare-control") { prepare_control(utf8(argv[2])); return 0; }
    if (argc == 2 && std::wstring(argv[1]) == L"--revoke") { revoke(); return 0; }
    if (argc == 3 && std::wstring(argv[1]) == L"--check-install") {
      check_install(std::wstring(argv[2]) == L"1"); return 0;
    }
    if (argc == 6 && std::wstring(argv[1]) == L"--enroll") {
      enroll(fs::path(argv[2]), fs::path(argv[3]), utf8(argv[4]), utf8(argv[5]));
      std::cout << Json{{"ok", true}}.dump() << '\n'; return 0;
    }
    if (argc == 2 && std::wstring(argv[1]) == L"--remove-service") { remove_service(); return 0; }
    if (argc != 2 || (std::wstring(argv[1]) != L"--ipc" && std::wstring(argv[1]) != L"--protect-secrets" &&
                     std::wstring(argv[1]) != L"--unprotect-secrets")) throw std::runtime_error("invalid_client_arguments");
    std::string bytes; char character;
    while (std::cin.get(character)) { bytes += character; if (bytes.size() > kMaxMessageBytes) throw std::runtime_error("message_too_large"); }
    if (std::wstring(argv[1]) == L"--protect-secrets") {
      std::vector<uint8_t> plaintext(bytes.begin(), bytes.end());
      const auto protected_bytes = user_dpapi(plaintext, true);
      SecureZeroMemory(plaintext.data(), plaintext.size()); SecureZeroMemory(bytes.data(), bytes.size());
      std::cout << Json{{"ok", true}, {"blob", encode_base64(protected_bytes)}}.dump() << '\n'; return 0;
    }
    if (std::wstring(argv[1]) == L"--unprotect-secrets") {
      auto plaintext = user_dpapi(decode_base64(bytes), false);
      std::cout.write(reinterpret_cast<const char*>(plaintext.data()), static_cast<std::streamsize>(plaintext.size()));
      SecureZeroMemory(plaintext.data(), plaintext.size()); return 0;
    }
    const auto response = pipe_call(parse_json(bytes));
    std::cout << response.dump() << '\n'; return response.value("ok", false) ? 0 : 1;
  } catch (const std::exception& error) {
    const bool secrets = argc > 1 && (std::wstring(argv[1]) == L"--protect-secrets" || std::wstring(argv[1]) == L"--unprotect-secrets");
    const std::string reason(error.what());
    const bool safe_code = reason.size() <= 64 && std::regex_match(reason, std::regex("[a-z][a-z_]*"));
    std::cout << Json{{"ok", false}, {"code", secrets ? "user_snapshot_failed" : (safe_code ? reason : "invalid_request")}}.dump() << '\n'; return 1;
  }
}
