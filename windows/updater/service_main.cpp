#include "win_security.h"
#include <sddl.h>
#include <shellapi.h>
#include <atomic>
#include <thread>

using namespace plug::updater;
namespace {
constexpr wchar_t kServiceName[] = L"PlugAgenteUpdater";
SERVICE_STATUS_HANDLE status_handle = nullptr;
SERVICE_STATUS service_status{};
HANDLE stop_event = nullptr;
std::atomic<bool> worker_active{false};

void report(DWORD state) {
  service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  service_status.dwCurrentState = state;
  service_status.dwControlsAccepted = state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN : 0;
  service_status.dwWin32ExitCode = NO_ERROR;
  SetServiceStatus(status_handle, &service_status);
}
DWORD WINAPI control(DWORD code, DWORD, void*, void*) {
  if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
    if (worker_active) return ERROR_BUSY;
    report(SERVICE_STOP_PENDING); SetEvent(stop_event);
  }
  return NO_ERROR;
}
Json journal() {
  const auto path = updater_root() / L"journal.json";
  return fs::exists(path) ? parse_json(read_file(path)) : Json{{"state", "idle"}};
}
Json public_status(const Json& value) {
  Json status{{"protocol", 1}, {"state", value.value("state", "idle")}};
  for (const auto& name : {"operationId", "version", "reason", "missingCapabilities", "rebootPending"})
    if (value.contains(name)) status[name] = value.at(name);
  return status;
}
void reconcile_interrupted_operation();
void save(const Json& value) { write_atomic(updater_root() / L"journal.json", value.dump()); }
std::string operation_id() {
  GUID guid{}; if (FAILED(CoCreateGuid(&guid))) throw std::runtime_error("operation_id_failed");
  wchar_t text[40]{}; StringFromGUID2(guid, text, 40);
  std::wstring result(text);
  result.erase(std::remove_if(result.begin(), result.end(), [](wchar_t value) { return value == L'{' || value == L'}' || value == L'-'; }), result.end());
  std::transform(result.begin(), result.end(), result.begin(), towlower);
  return utf8(result);
}
std::wstring client_sid(HANDLE pipe) {
  if (!ImpersonateNamedPipeClient(pipe)) throw std::runtime_error("client_authentication_failed");
  HANDLE raw = nullptr;
  if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &raw)) { RevertToSelf(); throw std::runtime_error("client_token_failed"); }
  Handle token(raw); DWORD size = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  std::vector<uint8_t> bytes(size);
  const BOOL read = GetTokenInformation(token.get(), TokenUser, bytes.data(), size, &size);
  RevertToSelf();
  if (!read) throw std::runtime_error("client_token_failed");
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &sid)) throw std::runtime_error("client_sid_failed");
  std::wstring result(sid); LocalFree(sid); return result;
}
DWORD authorize_client(HANDLE pipe, const Json& policy) {
  ULONG pid = 0;
  if (!GetNamedPipeClientProcessId(pipe, &pid)) throw std::runtime_error("client_pid_failed");
  Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid));
  wchar_t image[32768]{}; DWORD size = 32768;
  if (!process.valid() || !QueryFullProcessImageNameW(process.get(), 0, image, &size)) throw std::runtime_error("client_image_failed");
  const auto path = fs::path(image);
  const auto install = fs::path(wide(policy.at("installDirectory").get<std::string>()));
  if (path != install / L"plug_agente.exe" && path != control_root() / L"plug_update_client.exe")
    throw std::runtime_error("client_image_rejected");
  const auto thumbprint = trusted_publisher(path);
  if (std::find(policy.at("publishers").begin(), policy.at("publishers").end(), thumbprint) == policy.at("publishers").end())
    throw std::runtime_error("client_publisher_rejected");
  return pid;
}
void copy_client_file(HANDLE pipe, const fs::path& source, const fs::path& destination, uint64_t expected_size) {
  reject_reparse_path(source);
  if (!ImpersonateNamedPipeClient(pipe)) throw std::runtime_error("client_impersonation_failed");
  std::unique_ptr<PinnedPath> pinned_source;
  try { pinned_source = std::make_unique<PinnedPath>(source); }
  catch (...) { RevertToSelf(); throw; }
  RevertToSelf();
  const auto input = pinned_source->leaf();
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(input, &size) || static_cast<uint64_t>(size.QuadPart) != expected_size || expected_size > 2ull * 1024 * 1024 * 1024)
    throw std::runtime_error("staging_size_rejected");
  Handle output(CreateFileW(destination.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!output.valid()) throw std::runtime_error("staging_destination_failed");
  std::vector<uint8_t> bytes(65536); DWORD read = 0;
  while (true) {
    if (!ReadFile(input, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr)) throw std::runtime_error("staging_read_failed");
    if (!read) break;
    DWORD written = 0;
    if (!WriteFile(output.get(), bytes.data(), read, &written, nullptr) || written != read) throw std::runtime_error("staging_write_failed");
  }
  if (!FlushFileBuffers(output.get())) throw std::runtime_error("staging_flush_failed");
}
bool process_alive(const Json& job) {
  if (!job.contains("workerPid")) return false;
  Handle process(OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, job.at("workerPid").get<DWORD>()));
  if (!process.valid()) return GetLastError() == ERROR_ACCESS_DENIED;
  FILETIME creation{}, exit{}, kernel{}, user{};
  if (!GetProcessTimes(process.get(), &creation, &exit, &kernel, &user)) return true;
  const uint64_t started = (static_cast<uint64_t>(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
  return started == job.value("workerCreated", uint64_t{0}) && WaitForSingleObject(process.get(), 0) == WAIT_TIMEOUT;
}
void reconcile_interrupted_operation() {
  auto current = journal();
  worker_active = process_alive(current);
  const auto state = current.value("state", "idle");
  if (!worker_active && (state == "installing" || state == "verifying" || state == "rollingBack" ||
      state == "snapshotting" || state == "waitingForExit" || state == "restoringUserData")) {
    current["state"] = "recoveryRequired"; current["reason"] = "worker_interrupted";
    save(current);
  }
}
Json handle_request(HANDLE pipe, const Json& request) {
  if (request.value("protocol", 0) != 1) throw std::runtime_error("unsupported_protocol");
  // Revocation stops new applications, not status, cancellation or recovery
  // of an operation that has already been dispatched.
  const auto policy = load_policy(false);
  const DWORD client_pid = authorize_client(pipe, policy);
  const auto sid = utf8(client_sid(pipe));
  const auto command = request.at("command").get<std::string>();
  auto current = journal();
  worker_active = process_alive(current);
  if (command == "status") return Json{{"ok", true}, {"status", public_status(current)}, {"channel", policy.at("channel")}};
  if (command == "capabilities") return Json{{"ok", true}, {"capabilities", {
      {"protocol", kProtocolVersion}, {"authorized", policy.at("enabled")},
      {"applicationReady", kApplicationContractImplemented && policy.value("applicationContractValidated", false)},
      {"channel", policy.at("channel")}, {"approved", policy.at("capabilities")}}}};
  if (command == "prepare") {
    if (!policy.at("enabled").get<bool>()) throw std::runtime_error("authorization_required");
    if (worker_active) throw std::runtime_error("installation_in_progress");
    if (!can_prepare_operation(current.value("state", "")))
      throw std::runtime_error("recovery_required");
    const auto manifest = verify_manifest(request.at("manifest"), policy.at("publicKeys").get<std::string>());
    if (current.value("state", "") == "preparing") {
      const auto stored = updater_root() / L"operations" / wide(current.at("operationId").get<std::string>()) / L"manifest.json";
      if (current.value("version", "") == manifest.at("version") && sid == current.value("clientSid", "") &&
          parse_json(read_file(stored)) == request.at("manifest"))
        return Json{{"ok", true}, {"status", public_status(current)}};
      throw std::runtime_error("another_update_is_prepared");
    }
    if (manifest.at("channel") != policy.at("channel")) throw std::runtime_error("channel_rejected");
    const auto missing = missing_capabilities(manifest, policy);
    if (!missing.empty()) return Json{{"ok", false}, {"code", "authorization_required"}, {"missingCapabilities", missing}};
    if (current.value("blockedVersion", "") == manifest.at("version")) throw std::runtime_error("version_blocked_after_rollback");
    const auto blocked = current.value("blockedVersions", Json::array());
    if (std::find(blocked.begin(), blocked.end(), manifest.at("version")) != blocked.end())
      throw std::runtime_error("version_blocked_after_rollback");
    if (blocked.size() >= 1024) throw std::runtime_error("administrative_history_review_required");
    if (current.contains("lastHealthyVersion") && !newer_version(manifest.at("version"), current.at("lastHealthyVersion")))
      throw std::runtime_error("version_replay_rejected");
    const auto id = operation_id();
    const auto directory = updater_root() / L"operations" / wide(id);
    protect_directory(directory);
    const auto installer = directory / L"setup.exe";
    copy_client_file(pipe, fs::path(wide(request.at("installerPath").get<std::string>())), installer, manifest.at("installer").at("size").get<uint64_t>());
    if (fs::file_size(installer) != manifest.at("installer").at("size").get<uint64_t>() ||
        sha256_file(installer) != manifest.at("installer").at("sha256")) throw std::runtime_error("installer_hash_mismatch");
    const auto publisher = trusted_publisher(installer);
    if (std::find(policy.at("publishers").begin(), policy.at("publishers").end(), publisher) == policy.at("publishers").end())
      throw std::runtime_error("installer_publisher_rejected");
    write_atomic(directory / L"manifest.json", request.at("manifest").dump());
    const auto previous = current;
    current = Json{{"state", "preparing"}, {"operationId", id}, {"version", manifest.at("version")},
                   {"clientSid", sid}, {"clientPid", client_pid}, {"installDirectory", policy.at("installDirectory")}};
    for (const auto& name : {"blockedVersion", "blockedVersions", "lastHealthyVersion"})
      if (previous.contains(name)) current[name] = previous.at(name);
    save(current);
    return Json{{"ok", true}, {"status", public_status(current)}};
  }
  if (request.value("operationId", "") != current.value("operationId", "") || sid != current.value("clientSid", ""))
    throw std::runtime_error("operation_identity_rejected");
  if (command == "cancel") {
    if (worker_active) throw std::runtime_error("installation_in_progress");
    if (current.value("state", "") != "preparing" && current.value("state", "") != "deferred")
      throw std::runtime_error("cancellation_not_safe");
    current["state"] = "deferred"; current["reason"] = "cancelled_before_installation"; save(current);
    return Json{{"ok", true}, {"status", public_status(current)}};
  }
  if (command == "health") {
    if (current.value("state", "") != "verifying") throw std::runtime_error("health_not_expected");
    if (request.at("version") != current.at("version") || request.at("nonce") != current.at("healthNonce")) throw std::runtime_error("health_identity_rejected");
    write_atomic(updater_root() / L"operations" / wide(current.at("operationId").get<std::string>()) / L"health.json",
                 Json{{"nonce", current.at("healthNonce")}, {"version", current.at("version")}}.dump());
    return Json{{"ok", true}};
  }
  if (command != "start") throw std::runtime_error("unsupported_command");
  if (worker_active) return Json{{"ok", true}, {"status", public_status(current)}, {"healthNonce", current.at("healthNonce")}};
  if (!policy.at("enabled").get<bool>()) throw std::runtime_error("authorization_required");
  // Activation requires the separately homologated application/launcher
  // contract. Enrollment alone is never evidence that recovery is complete.
  if constexpr (!kApplicationContractImplemented) throw std::runtime_error("transition_validation_required");
  if (!policy.value("applicationContractValidated", false))
    throw std::runtime_error("transition_validation_required");
  Handle manual_setup(OpenMutexW(SYNCHRONIZE, FALSE, L"Global\\PlugAgenteSetup"));
  if (manual_setup.valid() || GetLastError() == ERROR_ACCESS_DENIED) throw std::runtime_error("manual_setup_in_progress");
  if (current.value("state", "") != "preparing") throw std::runtime_error("operation_not_prepared");
  DWORD session = 0;
  if (!ProcessIdToSessionId(client_pid, &session) || !active_user_session(session, sid))
    throw std::runtime_error("interactive_session_required");
  const auto directory = updater_root() / L"operations" / wide(current.at("operationId").get<std::string>());
  const auto manifest = verify_manifest(parse_json(read_file(directory / L"manifest.json")), policy.at("publicKeys").get<std::string>());
  if (!missing_capabilities(manifest, policy).empty()) throw std::runtime_error("authorization_required");
  // The current-user client submits its encrypted exact snapshot before shutdown.
  const auto secret_blob = decode_base64(request.at("secretsSnapshot").get<std::string>());
  if (secret_blob.empty() || secret_blob.size() > 512 * 1024) throw std::runtime_error("secrets_snapshot_invalid");
  write_atomic(directory / L"secrets.dpapi", std::string(secret_blob.begin(), secret_blob.end()));
  const DWORD app_pid = request.at("appPid").get<DWORD>();
  Handle app(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, app_pid));
  wchar_t app_image[32768]{}; DWORD app_image_length = 32768, app_session = 0;
  if (!app.valid() || !QueryFullProcessImageNameW(app.get(), 0, app_image, &app_image_length) ||
      fs::path(app_image) != fs::path(wide(policy.at("installDirectory").get<std::string>())) / L"plug_agente.exe" ||
      !ProcessIdToSessionId(app_pid, &app_session) || app_session != session || process_user_sid(app.get()) != sid)
    throw std::runtime_error("app_identity_rejected");
  const auto data_directory = fs::path(wide(request.at("dataDirectory").get<std::string>())).lexically_normal();
  if (data_directory != updater_root().parent_path() / L"PlugAgente") throw std::runtime_error("data_directory_rejected");
  reject_reparse_path(data_directory);
  FILETIME app_creation{}, app_exit{}, app_kernel{}, app_user{};
  if (!GetProcessTimes(app.get(), &app_creation, &app_exit, &app_kernel, &app_user)) throw std::runtime_error("app_identity_unconfirmed");
  current["appPid"] = app_pid; current["sessionId"] = session;
  current["appCreated"] = (static_cast<uint64_t>(app_creation.dwHighDateTime) << 32) | app_creation.dwLowDateTime;
  current["dataDirectory"] = utf8(data_directory.native());
  current["healthNonce"] = operation_id(); current["state"] = "waitingForExit";
  current["workerVersion"] = policy.at("workerVersion");
  save(current);
  const auto worker = registered_worker(policy);
  PinnedPath pinned_worker(worker);
  if (trusted_publisher(worker) != trusted_publisher(control_root() / L"plug_update_service.exe")) throw std::runtime_error("worker_publisher_rejected");
  std::wstring line = quote(worker.native()) + L" --operation " + wide(current.at("operationId").get<std::string>());
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
  if (!CreateProcessW(worker.c_str(), line.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, control_root().c_str(), &startup, &process))
    throw std::runtime_error("worker_start_failed");
  Handle worker_process(process.hProcess), thread(process.hThread);
  FILETIME creation{}, exit{}, kernel{}, user{};
  GetProcessTimes(process.hProcess, &creation, &exit, &kernel, &user);
  current["workerPid"] = process.dwProcessId;
  current["workerCreated"] = (static_cast<uint64_t>(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
  save(current); worker_active = true;
  write_atomic(directory / L"start.ready", "1");
  return Json{{"ok", true}, {"status", public_status(current)}, {"healthNonce", current.at("healthNonce")}};
}
void WINAPI service_main(DWORD, LPWSTR*) {
  status_handle = RegisterServiceCtrlHandlerExW(kServiceName, control, nullptr);
  if (!status_handle) return;
  stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr); report(SERVICE_RUNNING);
  while (WaitForSingleObject(stop_event, 0) == WAIT_TIMEOUT) {
    try { reconcile_interrupted_operation(); }
    catch (const std::exception&) { worker_active = true; /* unknown journal prevents stop/reuse */ }
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x0012019b;;;AU)", SDDL_REVISION_1, &descriptor, nullptr);
    SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};
    Handle pipe(CreateNamedPipeW(L"\\\\.\\pipe\\PlugAgenteUpdater.v1", PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 65536, 65536, 0, &attributes));
    LocalFree(descriptor);
    if (!pipe.valid()) { WaitForSingleObject(stop_event, 1000); continue; }
    OVERLAPPED connection{}; Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)); connection.hEvent = event.get();
    const BOOL connected = ConnectNamedPipe(pipe.get(), &connection);
    const DWORD error = connected ? ERROR_SUCCESS : GetLastError();
    if (error == ERROR_IO_PENDING) {
      HANDLE events[]{stop_event, event.get()};
      if (WaitForMultipleObjects(2, events, FALSE, 1000) != WAIT_OBJECT_0 + 1) {
        CancelIoEx(pipe.get(), &connection); DWORD transferred = 0; GetOverlappedResult(pipe.get(), &connection, &transferred, TRUE); continue;
      }
    } else if (error != ERROR_SUCCESS && error != ERROR_PIPE_CONNECTED) continue;
    try {
      DWORD length = 0;
      if (!pipe_transfer(pipe.get(), &length, sizeof(length), false, 5000) || length > kMaxMessageBytes) throw std::runtime_error("invalid_message_size");
      std::string bytes(length, '\0');
      if (!pipe_transfer(pipe.get(), bytes.data(), length, false, 5000)) throw std::runtime_error("invalid_message");
      Json response;
      try { response = handle_request(pipe.get(), parse_json(bytes)); }
      catch (const std::exception& exception) {
        const std::string reason(exception.what());
        const bool code = reason.size() <= 64 && std::regex_match(reason, std::regex("[a-z][a-z_]*"));
        response = Json{{"ok", false}, {"code", code ? reason : "invalid_request"}};
      }
      bytes = response.dump(); length = static_cast<DWORD>(bytes.size());
      pipe_transfer(pipe.get(), &length, sizeof(length), true, 5000); pipe_transfer(pipe.get(), bytes.data(), length, true, 5000);
    } catch (const std::exception&) {
      const HANDLE event_log = RegisterEventSourceW(nullptr, kServiceName);
      if (event_log) {
        const wchar_t* text = L"Updater IPC request failed; no installation was authorized.";
        ReportEventW(event_log, EVENTLOG_WARNING_TYPE, 0, 1, nullptr, 1, 0, &text, nullptr);
        DeregisterEventSource(event_log);
      }
    }
    DisconnectNamedPipe(pipe.get());
  }
  CloseHandle(stop_event); report(SERVICE_STOPPED);
}
}
int wmain() {
  SERVICE_TABLE_ENTRYW table[]{{const_cast<LPWSTR>(kServiceName), service_main}, {nullptr, nullptr}};
  return StartServiceCtrlDispatcherW(table) ? 0 : 1;
}
