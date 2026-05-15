#include <windows.h>

#include <shellapi.h>
#include <softpub.h>
#include <wintrust.h>

#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cwchar>
#include <string>
#include <vector>

namespace {

constexpr DWORD kDefaultWaitPidTimeoutSeconds = 45;
constexpr wchar_t kStateStarted[] = L"started";
constexpr wchar_t kStateWaitingForAppExit[] = L"waitingForAppExit";
constexpr wchar_t kStateNonAdminStarted[] = L"nonAdminStarted";
constexpr wchar_t kStateNonAdminFailed[] = L"nonAdminFailed";
constexpr wchar_t kStateElevatedStarted[] = L"elevatedStarted";
constexpr wchar_t kStateElevatedCancelled[] = L"elevatedCancelled";
constexpr wchar_t kStateCompleted[] = L"completed";
constexpr wchar_t kStateElevatedFailed[] = L"elevatedFailed";
constexpr wchar_t kStateLauncherFailed[] = L"launcherFailed";
constexpr wchar_t kHashValidationPending[] = L"pending";
constexpr wchar_t kHashValidationValid[] = L"valid";
constexpr wchar_t kHashValidationMissing[] = L"missing";
constexpr wchar_t kHashValidationSizeMismatch[] = L"sizeMismatch";
constexpr wchar_t kHashValidationHashMismatch[] = L"hashMismatch";
constexpr wchar_t kHashValidationError[] = L"error";

struct Options {
  std::wstring version;
  std::wstring installerPath;
  std::wstring installDirectory;
  std::wstring logPath;
  std::wstring statusPath;
  std::wstring expectedSha256;
  DWORD appPid = 0;
  std::uint64_t expectedAssetSize = 0;
  bool tryCurrentUserFirst = false;
  bool requireValidSignature = false;
  DWORD waitPidTimeoutSeconds = kDefaultWaitPidTimeoutSeconds;
};

struct HelperStatus {
  std::wstring version;
  std::wstring state;
  std::wstring strategy;
  std::wstring installDirectory;
  std::wstring installerPath;
  std::wstring logPath;
  std::wstring statusPath;
  std::wstring expectedSha256;
  std::wstring actualSha256;
  std::wstring hashValidationStatus = kHashValidationPending;
  std::wstring signatureStatus = L"unknown";
  std::wstring startedAt;
  std::wstring errorMessage;
  DWORD appPid = 0;
  std::uint64_t expectedAssetSize = 0;
  std::uint64_t actualAssetSize = 0;
  DWORD waitPidTimeoutSeconds = kDefaultWaitPidTimeoutSeconds;
  DWORD waitForAppExitDurationMs = 0;
  DWORD nonAdminExitCode = 0;
  bool hasNonAdminExitCode = false;
  DWORD nonAdminDurationMs = 0;
  bool hasNonAdminDurationMs = false;
  DWORD elevatedExitCode = 0;
  bool hasElevatedExitCode = false;
  DWORD elevatedDurationMs = 0;
  bool hasElevatedDurationMs = false;
  bool elevatedRetryStarted = false;
  bool elevatedCancelled = false;
  bool installDirectoryWritable = false;
  bool signatureRequired = false;
  bool mutexAcquired = false;
};

struct RunResult {
  bool started = false;
  bool cancelled = false;
  DWORD exitCode = 1;
  DWORD durationMs = 0;
  std::wstring errorMessage;
};

std::wstring now_iso8601() {
  SYSTEMTIME now{};
  GetSystemTime(&now);
  wchar_t buffer[32]{};
  swprintf_s(
      buffer,
      L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
      now.wYear,
      now.wMonth,
      now.wDay,
      now.wHour,
      now.wMinute,
      now.wSecond,
      now.wMilliseconds);
  return std::wstring(buffer);
}

DWORD elapsed_ms(std::chrono::steady_clock::time_point started_at) {
  const auto elapsed = std::chrono::steady_clock::now() - started_at;
  const auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count();
  if (millis <= 0) {
    return 0;
  }
  if (millis > static_cast<long long>(MAXDWORD)) {
    return MAXDWORD;
  }
  return static_cast<DWORD>(millis);
}

std::wstring format_win32_error(DWORD error_code) {
  wchar_t* buffer = nullptr;
  const DWORD size = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr,
      error_code,
      MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPWSTR>(&buffer),
      0,
      nullptr);
  if (size == 0 || buffer == nullptr) {
    return L"Windows error " + std::to_wstring(error_code);
  }
  std::wstring message(buffer, size);
  LocalFree(buffer);
  while (!message.empty() && (message.back() == L'\r' || message.back() == L'\n' || message.back() == L' ')) {
    message.pop_back();
  }
  return message;
}

std::string wide_to_utf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int byte_count =
      WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (byte_count <= 0) {
    return std::string();
  }
  std::string result(static_cast<size_t>(byte_count), '\0');
  WideCharToMultiByte(
      CP_UTF8,
      0,
      value.c_str(),
      static_cast<int>(value.size()),
      &result[0],
      byte_count,
      nullptr,
      nullptr);
  return result;
}

std::string json_escape(const std::wstring& value) {
  const std::string utf8 = wide_to_utf8(value);
  std::string escaped;
  for (const unsigned char character : utf8) {
    switch (character) {
      case '"':
        escaped += "\\\"";
        break;
      case '\\':
        escaped += "\\\\";
        break;
      case '\b':
        escaped += "\\b";
        break;
      case '\f':
        escaped += "\\f";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        if (character < 0x20) {
          char buffer[7]{};
          sprintf_s(buffer, "\\u%04x", character);
          escaped += buffer;
        } else {
          escaped += static_cast<char>(character);
        }
        break;
    }
  }
  return escaped;
}

void append_json_string(std::string* json, const char* key, const std::wstring& value) {
  *json += "  \"";
  *json += key;
  *json += "\": \"";
  *json += json_escape(value);
  *json += "\"";
}

void append_json_number(std::string* json, const char* key, DWORD value) {
  *json += "  \"";
  *json += key;
  *json += "\": ";
  *json += std::to_string(value);
}

void append_json_uint64(std::string* json, const char* key, std::uint64_t value) {
  *json += "  \"";
  *json += key;
  *json += "\": ";
  *json += std::to_string(value);
}

void append_json_bool(std::string* json, const char* key, bool value) {
  *json += "  \"";
  *json += key;
  *json += "\": ";
  *json += value ? "true" : "false";
}

void append_json_null(std::string* json, const char* key) {
  *json += "  \"";
  *json += key;
  *json += "\": null";
}

template <typename AppendValue>
void append_field(std::string* json, bool* first, AppendValue append_value) {
  if (!*first) {
    *json += ",\n";
  }
  append_value();
  *first = false;
}

bool write_status_file(const HelperStatus& status) {
  std::string json = "{\n";
  bool first = true;
  append_field(&json, &first, [&]() { append_json_string(&json, "version", status.version); });
  append_field(&json, &first, [&]() { append_json_string(&json, "state", status.state); });
  append_field(&json, &first, [&]() { append_json_string(&json, "strategy", status.strategy); });
  append_field(&json, &first, [&]() { append_json_string(&json, "installDirectory", status.installDirectory); });
  append_field(&json, &first, [&]() { append_json_string(&json, "installerPath", status.installerPath); });
  append_field(&json, &first, [&]() { append_json_string(&json, "logPath", status.logPath); });
  append_field(&json, &first, [&]() { append_json_string(&json, "statusPath", status.statusPath); });
  append_field(&json, &first, [&]() { append_json_number(&json, "appPid", status.appPid); });
  append_field(&json, &first, [&]() { append_json_uint64(&json, "expectedAssetSize", status.expectedAssetSize); });
  append_field(&json, &first, [&]() { append_json_uint64(&json, "actualAssetSize", status.actualAssetSize); });
  append_field(&json, &first, [&]() { append_json_string(&json, "expectedSha256", status.expectedSha256); });
  append_field(&json, &first, [&]() { append_json_string(&json, "actualSha256", status.actualSha256); });
  append_field(&json, &first, [&]() { append_json_string(&json, "hashValidationStatus", status.hashValidationStatus); });
  append_field(
      &json, &first, [&]() { append_json_bool(&json, "installDirectoryWritable", status.installDirectoryWritable); });
  append_field(&json, &first, [&]() { append_json_bool(&json, "signatureRequired", status.signatureRequired); });
  append_field(&json, &first, [&]() { append_json_bool(&json, "mutexAcquired", status.mutexAcquired); });
  append_field(
      &json, &first, [&]() { append_json_number(&json, "waitPidTimeoutSeconds", status.waitPidTimeoutSeconds); });
  append_field(
      &json, &first, [&]() { append_json_number(&json, "waitForAppExitDurationMs", status.waitForAppExitDurationMs); });
  append_field(&json, &first, [&]() { append_json_string(&json, "signatureStatus", status.signatureStatus); });
  append_field(&json, &first, [&]() { append_json_string(&json, "startedAt", status.startedAt); });
  append_field(&json, &first, [&]() { append_json_string(&json, "lastUpdatedAt", now_iso8601()); });
  append_field(&json, &first, [&]() {
    if (status.hasNonAdminExitCode) {
      append_json_number(&json, "nonAdminExitCode", status.nonAdminExitCode);
    } else {
      append_json_null(&json, "nonAdminExitCode");
    }
  });
  append_field(&json, &first, [&]() {
    if (status.hasNonAdminDurationMs) {
      append_json_number(&json, "nonAdminDurationMs", status.nonAdminDurationMs);
    } else {
      append_json_null(&json, "nonAdminDurationMs");
    }
  });
  append_field(&json, &first, [&]() {
    if (status.hasElevatedExitCode) {
      append_json_number(&json, "elevatedExitCode", status.elevatedExitCode);
    } else {
      append_json_null(&json, "elevatedExitCode");
    }
  });
  append_field(&json, &first, [&]() {
    if (status.hasElevatedDurationMs) {
      append_json_number(&json, "elevatedDurationMs", status.elevatedDurationMs);
    } else {
      append_json_null(&json, "elevatedDurationMs");
    }
  });
  append_field(&json, &first, [&]() { append_json_bool(&json, "elevatedRetryStarted", status.elevatedRetryStarted); });
  append_field(&json, &first, [&]() { append_json_bool(&json, "elevatedCancelled", status.elevatedCancelled); });
  append_field(&json, &first, [&]() {
    if (!status.errorMessage.empty()) {
      append_json_string(&json, "errorMessage", status.errorMessage);
    } else {
      append_json_null(&json, "errorMessage");
    }
  });
  json += "\n}\n";

  if (json.size() > MAXDWORD) {
    return false;
  }
  const std::wstring temp_status_path = status.statusPath + L".tmp";
  const HANDLE file = CreateFileW(
      temp_status_path.c_str(),
      GENERIC_WRITE,
      FILE_SHARE_READ,
      nullptr,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD written = 0;
  const BOOL ok = WriteFile(file, json.data(), static_cast<DWORD>(json.size()), &written, nullptr);
  CloseHandle(file);
  if (!ok || written != static_cast<DWORD>(json.size())) {
    DeleteFileW(temp_status_path.c_str());
    return false;
  }
  const BOOL moved = MoveFileExW(
      temp_status_path.c_str(), status.statusPath.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
  if (!moved) {
    DeleteFileW(temp_status_path.c_str());
    return false;
  }
  return true;
}

bool file_exists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring verify_signature_status(const std::wstring& file_path) {
  if (!file_exists(file_path)) {
    return L"unknown";
  }

  WINTRUST_FILE_INFO file_info{};
  file_info.cbStruct = sizeof(file_info);
  file_info.pcwszFilePath = file_path.c_str();

  WINTRUST_DATA trust_data{};
  trust_data.cbStruct = sizeof(trust_data);
  trust_data.dwUIChoice = WTD_UI_NONE;
  trust_data.fdwRevocationChecks = WTD_REVOKE_NONE;
  trust_data.dwUnionChoice = WTD_CHOICE_FILE;
  trust_data.pFile = &file_info;
  trust_data.dwStateAction = WTD_STATEACTION_VERIFY;
  trust_data.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;

  GUID policy_guid = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  const LONG result = WinVerifyTrust(nullptr, &policy_guid, &trust_data);

  trust_data.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(nullptr, &policy_guid, &trust_data);

  if (result == ERROR_SUCCESS) {
    return L"valid";
  }
  if (result == TRUST_E_NOSIGNATURE || result == TRUST_E_SUBJECT_FORM_UNKNOWN ||
      result == TRUST_E_PROVIDER_UNKNOWN) {
    return L"unsigned";
  }
  return L"invalid";
}

bool read_next_value(const std::vector<std::wstring>& args, size_t* index, std::wstring* value) {
  if (*index + 1 >= args.size()) {
    return false;
  }
  *value = args[*index + 1];
  *index += 1;
  return true;
}

bool parse_bool_value(const std::wstring& raw, bool* value) {
  if (raw == L"true" || raw == L"1" || raw == L"yes") {
    *value = true;
    return true;
  }
  if (raw == L"false" || raw == L"0" || raw == L"no") {
    *value = false;
    return true;
  }
  return false;
}

DWORD parse_dword_value(const std::wstring& raw, DWORD fallback) {
  wchar_t* end = nullptr;
  const unsigned long long parsed = wcstoull(raw.c_str(), &end, 10);
  if (end == raw.c_str() || (end != nullptr && *end != L'\0') || parsed > MAXDWORD) {
    return fallback;
  }
  return static_cast<DWORD>(parsed);
}

std::uint64_t parse_uint64_value(const std::wstring& raw, std::uint64_t fallback) {
  wchar_t* end = nullptr;
  const unsigned long long parsed = wcstoull(raw.c_str(), &end, 10);
  if (end == raw.c_str() || (end != nullptr && *end != L'\0')) {
    return fallback;
  }
  return static_cast<std::uint64_t>(parsed);
}

std::wstring lowercase_ascii(std::wstring value) {
  for (wchar_t& ch : value) {
    if (ch >= L'A' && ch <= L'Z') {
      ch = static_cast<wchar_t>(ch - L'A' + L'a');
    }
  }
  return value;
}

bool is_valid_sha256(const std::wstring& value) {
  if (value.size() != 64) {
    return false;
  }
  for (const wchar_t ch : value) {
    const bool is_digit = ch >= L'0' && ch <= L'9';
    const bool is_hex = ch >= L'a' && ch <= L'f';
    if (!is_digit && !is_hex) {
      return false;
    }
  }
  return true;
}

bool parse_options(const std::vector<std::wstring>& args, Options* options, std::wstring* error_message) {
  for (size_t index = 1; index < args.size(); ++index) {
    const std::wstring& arg = args[index];
    if (arg == L"--version") {
      if (!read_next_value(args, &index, &options->version)) {
        *error_message = L"Missing value for --version";
        return false;
      }
    } else if (arg == L"--installer") {
      if (!read_next_value(args, &index, &options->installerPath)) {
        *error_message = L"Missing value for --installer";
        return false;
      }
    } else if (arg == L"--install-dir") {
      if (!read_next_value(args, &index, &options->installDirectory)) {
        *error_message = L"Missing value for --install-dir";
        return false;
      }
    } else if (arg == L"--log") {
      if (!read_next_value(args, &index, &options->logPath)) {
        *error_message = L"Missing value for --log";
        return false;
      }
    } else if (arg == L"--status") {
      if (!read_next_value(args, &index, &options->statusPath)) {
        *error_message = L"Missing value for --status";
        return false;
      }
    } else if (arg == L"--app-pid") {
      std::wstring value;
      if (!read_next_value(args, &index, &value)) {
        *error_message = L"Missing value for --app-pid";
        return false;
      }
      options->appPid = parse_dword_value(value, 0);
    } else if (arg == L"--asset-size") {
      std::wstring value;
      if (!read_next_value(args, &index, &value)) {
        *error_message = L"Missing value for --asset-size";
        return false;
      }
      options->expectedAssetSize = parse_uint64_value(value, 0);
    } else if (arg == L"--sha256") {
      if (!read_next_value(args, &index, &options->expectedSha256)) {
        *error_message = L"Missing value for --sha256";
        return false;
      }
      options->expectedSha256 = lowercase_ascii(options->expectedSha256);
    } else if (arg.rfind(L"--try-current-user-first=", 0) == 0) {
      const std::wstring value = arg.substr(std::wstring(L"--try-current-user-first=").size());
      if (!parse_bool_value(value, &options->tryCurrentUserFirst)) {
        *error_message = L"Invalid value for --try-current-user-first";
        return false;
      }
    } else if (arg == L"--try-current-user-first") {
      std::wstring value;
      if (!read_next_value(args, &index, &value) || !parse_bool_value(value, &options->tryCurrentUserFirst)) {
        *error_message = L"Invalid value for --try-current-user-first";
        return false;
      }
    } else if (arg == L"--wait-pid-timeout-seconds") {
      std::wstring value;
      if (!read_next_value(args, &index, &value)) {
        *error_message = L"Missing value for --wait-pid-timeout-seconds";
        return false;
      }
      options->waitPidTimeoutSeconds = parse_dword_value(value, kDefaultWaitPidTimeoutSeconds);
    } else if (arg.rfind(L"--require-valid-signature=", 0) == 0) {
      const std::wstring value = arg.substr(std::wstring(L"--require-valid-signature=").size());
      if (!parse_bool_value(value, &options->requireValidSignature)) {
        *error_message = L"Invalid value for --require-valid-signature";
        return false;
      }
    } else if (arg == L"--require-valid-signature") {
      std::wstring value;
      if (!read_next_value(args, &index, &value) || !parse_bool_value(value, &options->requireValidSignature)) {
        *error_message = L"Invalid value for --require-valid-signature";
        return false;
      }
    } else {
      *error_message = L"Unknown argument: " + arg;
      return false;
    }
  }

  if (options->version.empty() || options->installerPath.empty() || options->installDirectory.empty() ||
      options->logPath.empty() || options->statusPath.empty() || options->expectedAssetSize == 0 ||
      !is_valid_sha256(options->expectedSha256)) {
    *error_message = L"Missing required update helper arguments";
    return false;
  }
  return true;
}

DWORD wait_for_process_exit(DWORD pid, DWORD timeout_seconds) {
  const auto started_at = std::chrono::steady_clock::now();
  if (pid == 0) {
    return 0;
  }
  const HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, pid);
  if (process == nullptr) {
    return elapsed_ms(started_at);
  }
  const DWORD timeout_ms = timeout_seconds >= (MAXDWORD / 1000) ? MAXDWORD : timeout_seconds * 1000;
  WaitForSingleObject(process, timeout_ms);
  CloseHandle(process);
  return elapsed_ms(started_at);
}

bool can_write_to_directory(const std::wstring& directory) {
  const std::wstring probe_path =
      directory + L"\\.plug_agente_update_helper_probe_" + std::to_wstring(GetCurrentProcessId()) + L".tmp";
  const HANDLE file = CreateFileW(
      probe_path.c_str(),
      GENERIC_WRITE,
      0,
      nullptr,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_TEMPORARY | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  const char probe[] = "probe";
  DWORD written = 0;
  const BOOL ok = WriteFile(file, probe, static_cast<DWORD>(sizeof(probe) - 1), &written, nullptr);
  CloseHandle(file);
  DeleteFileW(probe_path.c_str());
  return ok && written == sizeof(probe) - 1;
}

bool file_size(const std::wstring& path, std::uint64_t* size) {
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  LARGE_INTEGER large_size{};
  const BOOL ok = GetFileSizeEx(file, &large_size);
  CloseHandle(file);
  if (!ok || large_size.QuadPart < 0) {
    return false;
  }
  *size = static_cast<std::uint64_t>(large_size.QuadPart);
  return true;
}

std::wstring bytes_to_hex(const BYTE* bytes, DWORD byte_count) {
  constexpr wchar_t hex[] = L"0123456789abcdef";
  std::wstring result;
  result.reserve(static_cast<size_t>(byte_count) * 2);
  for (DWORD index = 0; index < byte_count; ++index) {
    const BYTE value = bytes[index];
    result.push_back(hex[(value >> 4) & 0x0F]);
    result.push_back(hex[value & 0x0F]);
  }
  return result;
}

bool sha256_of_file(const std::wstring& path, std::wstring* digest, std::wstring* error_message) {
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    *error_message = format_win32_error(GetLastError());
    return false;
  }

  HCRYPTPROV provider = 0;
  HCRYPTHASH hash = 0;
  bool success = false;
  if (!CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT)) {
    *error_message = format_win32_error(GetLastError());
  } else if (!CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash)) {
    *error_message = format_win32_error(GetLastError());
  } else {
    BYTE buffer[64 * 1024]{};
    success = true;
    while (true) {
      DWORD read = 0;
      if (!ReadFile(file, buffer, static_cast<DWORD>(sizeof(buffer)), &read, nullptr)) {
        *error_message = format_win32_error(GetLastError());
        success = false;
        break;
      }
      if (read == 0) {
        break;
      }
      if (!CryptHashData(hash, buffer, read, 0)) {
        *error_message = format_win32_error(GetLastError());
        success = false;
        break;
      }
    }
    if (success) {
      DWORD hash_size = 32;
      BYTE hash_bytes[32]{};
      if (!CryptGetHashParam(hash, HP_HASHVAL, hash_bytes, &hash_size, 0)) {
        *error_message = format_win32_error(GetLastError());
        success = false;
      } else {
        *digest = bytes_to_hex(hash_bytes, hash_size);
      }
    }
  }

  if (hash != 0) {
    CryptDestroyHash(hash);
  }
  if (provider != 0) {
    CryptReleaseContext(provider, 0);
  }
  CloseHandle(file);
  return success;
}

bool validate_installer_payload(const Options& options, HelperStatus* status) {
  std::uint64_t actual_size = 0;
  if (!file_size(options.installerPath, &actual_size)) {
    status->hashValidationStatus = kHashValidationMissing;
    status->errorMessage = L"Installer file is missing or cannot be read";
    return false;
  }
  status->actualAssetSize = actual_size;
  if (actual_size != options.expectedAssetSize) {
    status->hashValidationStatus = kHashValidationSizeMismatch;
    status->errorMessage = L"Installer size changed after download validation";
    return false;
  }

  std::wstring hash_error;
  if (!sha256_of_file(options.installerPath, &status->actualSha256, &hash_error)) {
    status->hashValidationStatus = kHashValidationError;
    status->errorMessage = hash_error.empty() ? L"Failed to compute installer SHA-256" : hash_error;
    return false;
  }
  if (status->actualSha256 != options.expectedSha256) {
    status->hashValidationStatus = kHashValidationHashMismatch;
    status->errorMessage = L"Installer SHA-256 changed after download validation";
    return false;
  }

  status->hashValidationStatus = kHashValidationValid;
  status->errorMessage.clear();
  return true;
}

std::wstring quote_executable(const std::wstring& value) {
  std::wstring quoted = L"\"";
  for (const wchar_t ch : value) {
    if (ch == L'"') {
      quoted += L"\\\"";
    } else {
      quoted += ch;
    }
  }
  quoted += L"\"";
  return quoted;
}

std::wstring join_arguments(const std::vector<std::wstring>& args) {
  std::wstring joined;
  for (size_t index = 0; index < args.size(); ++index) {
    if (index > 0) {
      joined += L" ";
    }
    joined += args[index];
  }
  return joined;
}

std::vector<std::wstring> build_base_setup_args(const Options& options) {
  return {
      L"/VERYSILENT",
      L"/SUPPRESSMSGBOXES",
      L"/NORESTART",
      L"/CLOSEAPPLICATIONS",
      L"/RESTARTAPPLICATIONS",
      L"/LAUNCHAFTERUPDATE=1",
      L"/MERGETASKS=\"!desktopicon,!startup\"",
      L"/DIR=\"" + options.installDirectory + L"\"",
      L"/LOG=\"" + options.logPath + L"\"",
  };
}

RunResult run_setup_process(const std::wstring& executable, const std::vector<std::wstring>& args) {
  RunResult result{};
  const auto started_at = std::chrono::steady_clock::now();
  std::wstring command_line = quote_executable(executable) + L" " + join_arguments(args);
  std::vector<wchar_t> mutable_command_line(command_line.begin(), command_line.end());
  mutable_command_line.push_back(L'\0');

  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  const BOOL started = CreateProcessW(
      nullptr,
      mutable_command_line.data(),
      nullptr,
      nullptr,
      FALSE,
      0,
      nullptr,
      nullptr,
      &startup_info,
      &process_info);
  if (!started) {
    result.errorMessage = format_win32_error(GetLastError());
    result.durationMs = elapsed_ms(started_at);
    return result;
  }

  result.started = true;
  WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  if (GetExitCodeProcess(process_info.hProcess, &exit_code)) {
    result.exitCode = exit_code;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  result.durationMs = elapsed_ms(started_at);
  return result;
}

RunResult run_setup_elevated(const std::wstring& executable, const std::vector<std::wstring>& args) {
  RunResult result{};
  const auto started_at = std::chrono::steady_clock::now();
  const std::wstring parameters = join_arguments(args);

  SHELLEXECUTEINFOW shell_execute_info{};
  shell_execute_info.cbSize = sizeof(shell_execute_info);
  shell_execute_info.fMask = SEE_MASK_NOCLOSEPROCESS;
  shell_execute_info.lpVerb = L"runas";
  shell_execute_info.lpFile = executable.c_str();
  shell_execute_info.lpParameters = parameters.c_str();
  shell_execute_info.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&shell_execute_info)) {
    const DWORD error_code = GetLastError();
    result.cancelled = error_code == ERROR_CANCELLED;
    result.errorMessage = format_win32_error(error_code);
    result.durationMs = elapsed_ms(started_at);
    return result;
  }

  result.started = true;
  WaitForSingleObject(shell_execute_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  if (GetExitCodeProcess(shell_execute_info.hProcess, &exit_code)) {
    result.exitCode = exit_code;
  }
  CloseHandle(shell_execute_info.hProcess);
  result.durationMs = elapsed_ms(started_at);
  return result;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE previous_instance, PWSTR command_line, int show_command) {
  UNREFERENCED_PARAMETER(instance);
  UNREFERENCED_PARAMETER(previous_instance);
  UNREFERENCED_PARAMETER(command_line);
  UNREFERENCED_PARAMETER(show_command);

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return 2;
  }

  std::vector<std::wstring> args;
  args.reserve(static_cast<size_t>(argc));
  for (int index = 0; index < argc; ++index) {
    args.emplace_back(argv[index]);
  }
  LocalFree(argv);

  Options options{};
  std::wstring parse_error;
  if (!parse_options(args, &options, &parse_error)) {
    if (!options.statusPath.empty()) {
      HelperStatus status{};
      status.version = options.version;
      status.state = kStateLauncherFailed;
      status.strategy = options.tryCurrentUserFirst ? L"currentUserThenElevated" : L"elevatedOnly";
      status.installDirectory = options.installDirectory;
      status.installerPath = options.installerPath;
      status.logPath = options.logPath;
      status.statusPath = options.statusPath;
      status.expectedSha256 = options.expectedSha256;
      status.expectedAssetSize = options.expectedAssetSize;
      status.appPid = options.appPid;
      status.waitPidTimeoutSeconds = options.waitPidTimeoutSeconds;
      status.signatureRequired = options.requireValidSignature;
      status.startedAt = now_iso8601();
      status.errorMessage = parse_error;
      write_status_file(status);
    }
    return 2;
  }

  HelperStatus status{};
  status.version = options.version;
  status.state = kStateStarted;
  status.strategy = options.tryCurrentUserFirst ? L"currentUserThenElevated" : L"elevatedOnly";
  status.installDirectory = options.installDirectory;
  status.installerPath = options.installerPath;
  status.logPath = options.logPath;
  status.statusPath = options.statusPath;
  status.expectedSha256 = options.expectedSha256;
  status.expectedAssetSize = options.expectedAssetSize;
  status.appPid = options.appPid;
  status.waitPidTimeoutSeconds = options.waitPidTimeoutSeconds;
  status.signatureRequired = options.requireValidSignature;
  status.startedAt = now_iso8601();
  status.signatureStatus = verify_signature_status(options.installerPath);
  status.installDirectoryWritable = can_write_to_directory(options.installDirectory);
  if (!status.installDirectoryWritable) {
    options.tryCurrentUserFirst = false;
    status.strategy = L"elevatedOnly";
  }
  write_status_file(status);

  HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Global\\PlugAgenteUpdateHelper");
  if (mutex == nullptr) {
    status.state = kStateLauncherFailed;
    status.errorMessage = L"Failed to create update mutex: " + format_win32_error(GetLastError());
    write_status_file(status);
    return 1;
  }
  const DWORD mutex_wait = WaitForSingleObject(mutex, 0);
  if (mutex_wait != WAIT_OBJECT_0 && mutex_wait != WAIT_ABANDONED) {
    status.state = kStateLauncherFailed;
    status.errorMessage = L"Another update helper is already running";
    write_status_file(status);
    CloseHandle(mutex);
    return 1;
  }
  status.mutexAcquired = true;
  write_status_file(status);

  if (!validate_installer_payload(options, &status)) {
    status.state = kStateLauncherFailed;
    write_status_file(status);
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 1;
  }
  write_status_file(status);

  if (options.requireValidSignature && status.signatureStatus != L"valid") {
    status.state = kStateLauncherFailed;
    status.errorMessage = L"Installer signature is required but is not valid";
    write_status_file(status);
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 1;
  }

  status.state = kStateWaitingForAppExit;
  write_status_file(status);
  status.waitForAppExitDurationMs = wait_for_process_exit(options.appPid, options.waitPidTimeoutSeconds);

  const std::vector<std::wstring> base_args = build_base_setup_args(options);
  if (options.tryCurrentUserFirst) {
    status.state = kStateNonAdminStarted;
    write_status_file(status);
    std::vector<std::wstring> current_user_args;
    current_user_args.reserve(base_args.size() + 1);
    current_user_args.emplace_back(L"/CURRENTUSER");
    current_user_args.insert(current_user_args.end(), base_args.begin(), base_args.end());
    const RunResult current_user_result = run_setup_process(options.installerPath, current_user_args);
    status.hasNonAdminExitCode = true;
    status.nonAdminExitCode = current_user_result.exitCode;
    status.hasNonAdminDurationMs = true;
    status.nonAdminDurationMs = current_user_result.durationMs;
    if (!current_user_result.started) {
      status.errorMessage = current_user_result.errorMessage;
    }
    if (current_user_result.started && current_user_result.exitCode == 0) {
      status.state = kStateCompleted;
      status.errorMessage.clear();
      write_status_file(status);
      ReleaseMutex(mutex);
      CloseHandle(mutex);
      return 0;
    }
    status.state = kStateNonAdminFailed;
    write_status_file(status);
  }

  status.state = kStateElevatedStarted;
  status.elevatedRetryStarted = true;
  status.errorMessage.clear();
  write_status_file(status);
  std::vector<std::wstring> all_users_args;
  all_users_args.reserve(base_args.size() + 1);
  all_users_args.emplace_back(L"/ALLUSERS");
  all_users_args.insert(all_users_args.end(), base_args.begin(), base_args.end());
  const RunResult elevated_result = run_setup_elevated(options.installerPath, all_users_args);
  status.hasElevatedExitCode = true;
  status.elevatedExitCode = elevated_result.exitCode;
  status.hasElevatedDurationMs = true;
  status.elevatedDurationMs = elevated_result.durationMs;
  if (!elevated_result.started) {
    status.state = elevated_result.cancelled ? kStateElevatedCancelled : kStateLauncherFailed;
    status.elevatedCancelled = elevated_result.cancelled;
    status.errorMessage = elevated_result.errorMessage;
    write_status_file(status);
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 1;
  }
  if (elevated_result.exitCode == 0) {
    status.state = kStateCompleted;
    status.errorMessage.clear();
    write_status_file(status);
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 0;
  }

  status.state = kStateElevatedFailed;
  status.errorMessage = L"Elevated installer exited with code " + std::to_wstring(elevated_result.exitCode);
  write_status_file(status);
  ReleaseMutex(mutex);
  CloseHandle(mutex);
  return static_cast<int>(elevated_result.exitCode);
}
