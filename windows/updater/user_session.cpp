#include "user_session.h"
#include <wtsapi32.h>
#include <userenv.h>
#include <sddl.h>

namespace plug::updater {
DWORD find_original_user_session(const Json& job) {
  const auto sid = job.at("clientSid").get<std::string>();
  const auto previous = job.at("sessionId").get<DWORD>();
  if (active_user_session(previous, sid)) return previous;
  PWTS_SESSION_INFOW sessions = nullptr; DWORD count = 0;
  if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &sessions, &count))
    throw std::runtime_error("session_inventory_unavailable");
  DWORD selected = 0;
  for (DWORD index = 0; index < count; ++index) {
    if (sessions[index].State == WTSActive && active_user_session(sessions[index].SessionId, sid)) {
      selected = sessions[index].SessionId;
      break;
    }
  }
  WTSFreeMemory(sessions);
  if (!selected) throw std::runtime_error("original_session_unavailable");
  return selected;
}
uint64_t unix_time_ms() {
  FILETIME now{}; GetSystemTimeAsFileTime(&now);
  return (((static_cast<uint64_t>(now.dwHighDateTime) << 32) | now.dwLowDateTime) - 116444736000000000ULL) / 10000;
}
uint64_t process_creation_time(HANDLE process) {
  FILETIME start{}, end{}, kernel{}, user{};
  if (!GetProcessTimes(process, &start, &end, &kernel, &user)) throw std::runtime_error("process_identity_unconfirmed");
  return (static_cast<uint64_t>(start.dwHighDateTime) << 32) | start.dwLowDateTime;
}
PROCESS_INFORMATION create_original_user_process(const Json& job, const std::wstring& arguments) {
  const auto session = job.at("sessionId").get<DWORD>();
  const auto sid = job.at("clientSid").get<std::string>();
  if (!active_user_session(session, sid)) throw std::runtime_error("original_session_unavailable");
  HANDLE raw = nullptr;
  if (!WTSQueryUserToken(session, &raw)) throw std::runtime_error("original_user_token_unavailable");
  Handle token(raw);
  HANDLE selected = token.get();
  std::unique_ptr<Handle> limited;
  TOKEN_ELEVATION elevation{}; DWORD size = 0;
  if (!GetTokenInformation(selected, TokenElevation, &elevation, sizeof(elevation), &size))
    throw std::runtime_error("user_elevation_unconfirmed");
  if (elevation.TokenIsElevated) {
    TOKEN_LINKED_TOKEN linked{};
    if (!GetTokenInformation(selected, TokenLinkedToken, &linked, sizeof(linked), &size))
      throw std::runtime_error("limited_user_token_unavailable");
    limited = std::make_unique<Handle>(linked.LinkedToken);
    selected = limited->get();
  }
  if (!GetTokenInformation(selected, TokenElevation, &elevation, sizeof(elevation), &size) || elevation.TokenIsElevated)
    throw std::runtime_error("elevated_relaunch_rejected");
  GetTokenInformation(selected, TokenUser, nullptr, 0, &size);
  std::vector<uint8_t> user(size);
  if (!size || !GetTokenInformation(selected, TokenUser, user.data(), size, &size))
    throw std::runtime_error("original_user_unconfirmed");
  PSID expected = nullptr;
  if (!ConvertStringSidToSidW(wide(sid).c_str(), &expected)) throw std::runtime_error("invalid_original_user");
  const bool same = EqualSid(reinterpret_cast<TOKEN_USER*>(user.data())->User.Sid, expected) != FALSE;
  LocalFree(expected);
  if (!same) throw std::runtime_error("original_user_changed");
  const auto app = fs::path(wide(job.at("installDirectory").get<std::string>())) / L"plug_agente.exe";
  PinnedPath pinned(app);
  assert_protected_directory(app, true, false);
  void* environment = nullptr;
  if (!CreateEnvironmentBlock(&environment, selected, FALSE)) throw std::runtime_error("user_environment_unavailable");
  std::wstring line = quote(app.native()) + L" " + arguments;
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  wchar_t desktop[] = L"winsta0\\default"; startup.lpDesktop = desktop;
  PROCESS_INFORMATION process{};
  const BOOL created = CreateProcessAsUserW(selected, app.c_str(), line.data(), nullptr, nullptr, FALSE,
      CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED, environment, app.parent_path().c_str(), &startup, &process);
  DestroyEnvironmentBlock(environment);
  if (!created) throw std::runtime_error("user_process_start_failed");
  return process;
}
void require_validation_process(const Json& job, DWORD pid, const std::string& sid) {
  if (pid != job.at("validationPid").get<DWORD>() || sid != job.at("clientSid"))
    throw std::runtime_error("validation_process_rejected");
  Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid));
  DWORD session = 0; wchar_t image[32768]{}; DWORD length = 32768;
  const auto app = fs::path(wide(job.at("installDirectory").get<std::string>())) / L"plug_agente.exe";
  if (!process.valid() || process_creation_time(process.get()) != job.at("validationCreated").get<uint64_t>() ||
      process_user_sid(process.get()) != sid || !ProcessIdToSessionId(pid, &session) || session != job.at("sessionId") ||
      WaitForSingleObject(process.get(), 0) != WAIT_TIMEOUT ||
      !QueryFullProcessImageNameW(process.get(), 0, image, &length) || _wcsicmp(image, app.c_str()) != 0)
    throw std::runtime_error("validation_process_rejected");
}
}
