#include "installation_channel.h"
#include "../updater/third_party/json.hpp"
#include <sddl.h>
#include <tlhelp32.h>
#include <bcrypt.h>
#include <vector>
#include <algorithm>
#include <stdexcept>
namespace plug::installation {
using Json = nlohmann::json;
namespace {
struct Handle {
  HANDLE value;
  explicit Handle(HANDLE h = nullptr) : value(h) {}
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
  bool valid() const { return value && value != INVALID_HANDLE_VALUE; }
};
uint64_t created(HANDLE process) {
  FILETIME a{}, b{}, c{}, d{};
  if (!GetProcessTimes(process, &a, &b, &c, &d)) throw std::runtime_error("process_identity_unconfirmed");
  return (uint64_t(a.dwHighDateTime) << 32) | a.dwLowDateTime;
}
std::wstring image(HANDLE process) {
  wchar_t text[32768]; DWORD length = 32768;
  if (!QueryFullProcessImageNameW(process, 0, text, &length)) throw std::runtime_error("process_path_unconfirmed");
  return canonical_executable(std::wstring(text, length));
}
std::vector<uint8_t> token_user(HANDLE token) {
  DWORD size = 0; GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<uint8_t> user(size);
  if (!size || !GetTokenInformation(token, TokenUser, user.data(), size, &size)) throw std::runtime_error("caller_identity_unconfirmed");
  return user;
}
bool authorized(HANDLE pipe) {
  ULONG pid = 0;
  if (!GetNamedPipeClientProcessId(pipe, &pid)) return false;
  Handle peer(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid));
  if (!peer.valid() || WaitForSingleObject(peer.value, 0) != WAIT_TIMEOUT) return false;
  const auto peer_image = image(peer.value);
  if (std::filesystem::path(peer_image).filename() != L"plug_update_client.exe") return false;
  HANDLE raw = nullptr;
  if (!OpenProcessToken(peer.value, TOKEN_QUERY, &raw)) return false;
  Handle token(raw);
  TOKEN_ELEVATION elevation{}; DWORD size = 0;
  if (GetTokenInformation(token.value, TokenElevation, &elevation, sizeof(elevation), &size) && elevation.TokenIsElevated) return true;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw)) return false;
  Handle own(raw);
  auto caller = token_user(token.value), local = token_user(own.value);
  if (!EqualSid(reinterpret_cast<TOKEN_USER*>(caller.data())->User.Sid,
                  reinterpret_cast<TOKEN_USER*>(local.data())->User.Sid)) return false;
  // A non-elevated caller must be the client shipped with this installation.
  // Old/per-user installers without it require manual application closure.
  const auto directory = std::filesystem::path(current_executable()).parent_path();
  return peer_image == (directory / L"updater" / L"plug_update_client.exe").native();
}
bool transfer(HANDLE pipe, void* data, DWORD size, bool write, HANDLE stop = nullptr) {
  auto* bytes = static_cast<char*>(data);
  while (size) {
    Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)); OVERLAPPED operation{}; operation.hEvent = event.value;
    DWORD done = 0;
    const BOOL immediate = write ? WriteFile(pipe, bytes, size, &done, &operation) : ReadFile(pipe, bytes, size, &done, &operation);
    if (!immediate) {
      if (GetLastError() != ERROR_IO_PENDING) return false;
      HANDLE waits[] = {event.value, stop};
      if (WaitForMultipleObjects(stop ? 2 : 1, waits, FALSE, 2000) != WAIT_OBJECT_0) {
        CancelIoEx(pipe, &operation); GetOverlappedResult(pipe, &operation, &done, TRUE); return false;
      }
      if (!GetOverlappedResult(pipe, &operation, &done, FALSE)) return false;
    }
    if (!done) return false;
    size -= done; bytes += done;
  }
  return true;
}
std::string read_message(HANDLE pipe, HANDLE stop = nullptr) {
  DWORD size = 0;
  if (!transfer(pipe, &size, sizeof(size), false, stop) || size == 0 || size > 4096) throw std::runtime_error("installation_channel_read_failed");
  std::string value(size, '\0');
  if (!transfer(pipe, value.data(), size, false, stop)) throw std::runtime_error("installation_channel_read_failed");
  return value;
}
void write_message(HANDLE pipe, std::string value, HANDLE stop = nullptr) {
  DWORD size = static_cast<DWORD>(value.size());
  if (!transfer(pipe, &size, sizeof(size), true, stop) || !transfer(pipe, value.data(), size, true, stop))
    throw std::runtime_error("installation_channel_write_failed");
}
}
std::wstring canonical_executable(const std::filesystem::path& path) {
  if (!path.is_absolute() || path.native().rfind(L"\\\\", 0) == 0) throw std::runtime_error("installation_path_rejected");
  auto current = path.root_path();
  for (const auto& part : path.relative_path()) {
    if (part == L".." || part == L"." || part.native().find(L':') != std::wstring::npos) throw std::runtime_error("installation_path_rejected");
    current /= part;
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) throw std::runtime_error("installation_path_rejected");
  }
  Handle file(CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  wchar_t name[32768];
  if (!file.valid()) throw std::runtime_error("installation_path_rejected");
  DWORD length = GetFinalPathNameByHandleW(file.value, name, 32768, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (!length || length >= 32768) throw std::runtime_error("installation_path_rejected");
  std::wstring result(name, length);
  std::transform(result.begin(), result.end(), result.begin(), towlower); return result;
}
std::wstring current_executable() {
  wchar_t name[32768]; DWORD length = GetModuleFileNameW(nullptr, name, 32768);
  if (!length || length >= 32768) throw std::runtime_error("process_path_unconfirmed");
  return canonical_executable(std::wstring(name, length));
}
std::wstring endpoint(const std::wstring& path, DWORD pid) {
  BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) throw std::runtime_error("hash_unavailable");
  uint8_t digest[32];
  const bool ok = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0 &&
      BCryptHashData(hash, reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(path.data())), static_cast<ULONG>(path.size()*sizeof(wchar_t)), 0) >= 0 &&
      BCryptFinishHash(hash, digest, sizeof(digest), 0) >= 0;
  if (hash) BCryptDestroyHash(hash); BCryptCloseAlgorithmProvider(algorithm, 0);
  if (!ok) throw std::runtime_error("hash_unavailable");
  std::wstring name = L"\\\\.\\pipe\\PlugAgente.Install.v1.";
  constexpr wchar_t hex[] = L"0123456789abcdef";
  for (auto byte : digest) { name += hex[byte >> 4]; name += hex[byte & 15]; }
  return name + L"." + std::to_wstring(pid);
}
bool valid_operation(const std::string& value) { return value.size() == 32 && value.find_first_not_of("0123456789abcdef") == std::string::npos; }
Channel::Channel() : stop_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
Channel::~Channel() { stopping_ = true; SetEvent(stop_); if (thread_.joinable()) thread_.join(); CloseHandle(stop_); }
bool Channel::start() {
  std::unique_lock<std::mutex> lock(mutex_);
  if (!stop_) return false;
  if (!thread_.joinable()) thread_ = std::thread([this] { serve(); });
  startup_.wait(lock, [this] { return startup_finished_; });
  return available_;
}
std::string Channel::poll() { std::lock_guard<std::mutex> lock(mutex_); if (operation_.empty() || delivered_) return ""; delivered_ = true; return operation_; }
bool Channel::cancelled() { std::lock_guard<std::mutex> lock(mutex_); return cancelled_; }
void Channel::report(const std::string& text) {
  const auto response = Json::parse(text);
  const auto state = response.at("state").get<std::string>();
  if (state != "waiting" && state != "closing" && state != "blocked" && state != "cancelled" && state != "recoveryRequired") throw std::runtime_error("invalid_installation_state");
  std::lock_guard<std::mutex> lock(mutex_);
  if (response.at("operation").get<std::string>() != operation_) throw std::runtime_error("installation_operation_changed");
  state_ = state;
}
void Channel::serve() {
  try {
    const auto name = endpoint(current_executable(), GetCurrentProcessId());
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;OW)", SDDL_REVISION_1, &descriptor, nullptr)) throw std::runtime_error("installation_channel_acl_failed");
    SECURITY_ATTRIBUTES security{sizeof(security), descriptor, FALSE};
    while (!stopping_) {
      Handle pipe(CreateNamedPipeW(name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 4096, 4096, 0, &security));
      if (!pipe.valid()) {
        OutputDebugStringW(L"Installation channel pipe creation failed\n");
        break;
      }
      {
        std::lock_guard<std::mutex> lock(mutex_);
        available_ = true;
        startup_finished_ = true;
      }
      startup_.notify_all();
      Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)); OVERLAPPED connect{}; connect.hEvent = event.value;
      BOOL connected = ConnectNamedPipe(pipe.value, &connect); DWORD error = connected ? ERROR_SUCCESS : GetLastError();
      if (error == ERROR_IO_PENDING) {
        HANDLE waits[] = {event.value, stop_};
        if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) != WAIT_OBJECT_0) {
          CancelIoEx(pipe.value, &connect); DWORD done; GetOverlappedResult(pipe.value, &connect, &done, TRUE); break;
        }
      } else if (error != ERROR_PIPE_CONNECTED && error != ERROR_SUCCESS) break;
      try {
        if (!authorized(pipe.value)) throw std::runtime_error("installation_caller_rejected");
        const auto request = Json::parse(read_message(pipe.value, stop_));
        const auto operation = request.at("operation").get<std::string>();
        const auto command = request.at("command").get<std::string>();
        if (request.at("protocol") != 1 || !valid_operation(operation) || (command != "prepare" && command != "status" && command != "cancel")) throw std::runtime_error("invalid_installation_request");
        std::string response;
        { std::lock_guard<std::mutex> lock(mutex_);
          if (operation_.empty() && command == "prepare") { operation_ = operation; state_ = "waiting"; }
          if (operation_ != operation) throw std::runtime_error("installation_operation_changed");
          if (command == "cancel") cancelled_ = true;
          response = Json{{"protocol",1},{"operation",operation_},{"state",state_}}.dump();
        }
        write_message(pipe.value, response, stop_);
        char receipt = 0; transfer(pipe.value, &receipt, 1, false, stop_);
      } catch (const std::exception&) { OutputDebugStringW(L"Installation channel request rejected\n"); }
      DisconnectNamedPipe(pipe.value);
    }
    LocalFree(descriptor);
  } catch (const std::exception&) { OutputDebugStringW(L"Installation channel unavailable\n"); }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    available_ = false;
    startup_finished_ = true;
  }
  startup_.notify_all();
}
void prepare_installation(const std::filesystem::path& directory, const std::string& operation, bool request, bool cancel) {
  if (!valid_operation(operation)) throw std::runtime_error("invalid_installation_operation");
  const auto executable = directory / L"plug_agente.exe";
  if (!std::filesystem::exists(executable)) return;
  const auto expected = canonical_executable(executable);
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  if (!snapshot.valid()) throw std::runtime_error("process_enumeration_failed");
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
  bool active = false;
  std::string failure;
  if (!Process32FirstW(snapshot.value, &entry)) throw std::runtime_error("process_enumeration_failed");
  do {
    if (_wcsicmp(entry.szExeFile, L"plug_agente.exe") != 0) continue;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, entry.th32ProcessID));
    if (!process.valid()) { if (GetLastError() == ERROR_INVALID_PARAMETER) continue; throw std::runtime_error("process_identity_unconfirmed"); }
    if (WaitForSingleObject(process.value, 0) == WAIT_OBJECT_0 || image(process.value) != expected) continue;
    active = true;
    try {
    const auto birth = created(process.value);
    Handle pipe(CreateFileW(endpoint(expected, entry.th32ProcessID).c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr));
    if (!pipe.valid()) {
      const auto error = GetLastError();
      if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND)
        throw std::runtime_error("close_previous_application_manually");
      if (error == ERROR_ACCESS_DENIED) throw std::runtime_error("process_identity_unconfirmed");
      if (error == ERROR_PIPE_BUSY) throw std::runtime_error("installation_channel_busy");
      throw std::runtime_error("installation_channel_open_failed:" + std::to_string(error));
    }
    ULONG server = 0;
    if (!GetNamedPipeServerProcessId(pipe.value, &server) || server != entry.th32ProcessID ||
        WaitForSingleObject(process.value, 0) != WAIT_TIMEOUT || created(process.value) != birth)
      throw std::runtime_error("installation_server_rejected");
    write_message(pipe.value, Json{{"protocol",1},{"operation",operation},{"command",cancel ? "cancel" : request ? "prepare" : "status"}}.dump());
    const auto result = Json::parse(read_message(pipe.value));
    char receipt = 1; if (!transfer(pipe.value, &receipt, 1, true)) throw std::runtime_error("installation_receipt_failed");
    if (result.at("protocol") != 1 || result.at("operation") != operation) throw std::runtime_error("installation_response_rejected");
    const auto state = result.at("state").get<std::string>();
    if (state == "recoveryRequired") throw std::runtime_error("installation_recovery_required");
    if (state == "blocked") throw std::runtime_error("installation_operations_active");
    if (state == "cancelled") throw std::runtime_error("installation_cancelled");
    if (state != "waiting" && state != "closing") throw std::runtime_error("installation_response_rejected");
    } catch (const std::exception& error) {
      if (failure.empty()) failure = error.what();
    }
  } while (Process32NextW(snapshot.value, &entry));
  if (GetLastError() != ERROR_NO_MORE_FILES) throw std::runtime_error("process_enumeration_failed");
  if (!failure.empty()) throw std::runtime_error(failure);
  if (active) throw std::runtime_error("installation_waiting_for_exit");
}
}
