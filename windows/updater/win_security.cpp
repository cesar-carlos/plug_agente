#include "win_security.h"
#include <aclapi.h>
#include <bcrypt.h>
#include <sddl.h>
#include <shlobj.h>
#include <softpub.h>
#include <wincrypt.h>
#include <wintrust.h>
#include <wtsapi32.h>
#include <fstream>
#include <iomanip>
#include <sstream>
#include "third_party/monocypher-ed25519.h"

namespace plug::updater {
PinnedPath::PinnedPath(const fs::path& path, DWORD leaf_access) {
  reject_reparse_path(path);
  fs::path current = path.root_path();
  std::vector<fs::path> components{current};
  for (const auto& part : path.relative_path()) { current /= part; components.push_back(current); }
  for (size_t index = 0; index < components.size(); ++index) {
    const bool leaf = index + 1 == components.size();
    const auto attributes = GetFileAttributesW(components[index].c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) throw std::runtime_error("path_identity_unconfirmed");
    const bool directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    const DWORD access = leaf ? (directory ? FILE_READ_ATTRIBUTES | (leaf_access & DELETE) : leaf_access) : FILE_READ_ATTRIBUTES;
    const DWORD sharing = directory ? FILE_SHARE_READ | FILE_SHARE_WRITE : FILE_SHARE_READ;
    auto handle = std::make_unique<Handle>(CreateFileW(components[index].c_str(), access, sharing, nullptr,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    FILE_ATTRIBUTE_TAG_INFO identity{};
    if (!handle->valid() || !GetFileInformationByHandleEx(handle->get(), FileAttributeTagInfo, &identity, sizeof(identity)) ||
        (identity.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) throw std::runtime_error("path_identity_rejected");
    if (leaf && !directory) {
      FILE_STANDARD_INFO standard{};
      if (!GetFileInformationByHandleEx(handle->get(), FileStandardInfo, &standard, sizeof(standard)) ||
          standard.NumberOfLinks != 1 || standard.DeletePending)
        throw std::runtime_error("file_identity_rejected");
    }
    handles_.push_back(std::move(handle));
  }
}
std::wstring wide(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (!length && !value.empty()) throw std::runtime_error("invalid_utf8");
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), length);
  return result;
}
std::string utf8(const std::wstring& value) {
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (!length && !value.empty()) throw std::runtime_error("invalid_utf16");
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), length, nullptr, nullptr);
  return result;
}
static fs::path known_folder(REFKNOWNFOLDERID id) {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(id, 0, nullptr, &path))) throw std::runtime_error("known_folder_unavailable");
  fs::path result(path); CoTaskMemFree(path); return result;
}
fs::path updater_root() { return known_folder(FOLDERID_ProgramData) / L"PlugAgenteUpdater"; }
fs::path control_root() { return known_folder(FOLDERID_ProgramFiles) / L"PlugAgenteUpdater"; }
fs::path registered_worker(const Json& policy) {
  const auto version = policy.at("workerVersion").get<std::string>();
  if (version.size() > 128 || !std::regex_match(version, std::regex("[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+")))
    throw std::runtime_error("invalid_worker_version");
  return control_root() / L"workers" / wide(version) / L"plug_update_worker.exe";
}

void reject_reparse_path(const fs::path& path) {
  if (!path.is_absolute() || path.native().rfind(L"\\\\", 0) == 0) throw std::runtime_error("invalid_local_path");
  for (const auto& component : path.relative_path())
    if (component == L".." || component == L"." || component.native().find(L':') != std::wstring::npos)
      throw std::runtime_error("invalid_local_path");
  for (auto current = path; !current.empty() && current != current.parent_path(); current = current.parent_path()) {
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT))
      throw std::runtime_error("reparse_point_rejected");
  }
}
std::string read_file(const fs::path& path, size_t limit) {
  reject_reparse_path(path);
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("file_read_failed");
  std::string result;
  char buffer[8192];
  while (input.read(buffer, sizeof(buffer)) || input.gcount()) {
    result.append(buffer, static_cast<size_t>(input.gcount()));
    if (result.size() > limit) throw std::runtime_error("file_too_large");
  }
  if (!input.eof()) throw std::runtime_error("file_read_failed");
  return result;
}
void write_atomic(const fs::path& path, const std::string& bytes) {
  reject_reparse_path(path);
  const auto temporary = fs::path(path.native() + L".tmp");
  reject_reparse_path(temporary);
  {
    Handle file(CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
    DWORD written = 0;
    if (!file.valid() || !WriteFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) || written != bytes.size() ||
        !FlushFileBuffers(file.get())) throw std::runtime_error("journal_write_failed");
  }
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    throw std::runtime_error("journal_replace_failed");
}
void protect_directory(const fs::path& path, bool executable_control) {
  reject_reparse_path(path);
  fs::create_directories(path);
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  const wchar_t* permissions = executable_control
      ? L"O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)"
      : L"O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(permissions, SDDL_REVISION_1, &descriptor, nullptr))
    throw std::runtime_error("acl_descriptor_failed");
  PACL dacl = nullptr; BOOL present = FALSE, inherited = FALSE;
  GetSecurityDescriptorDacl(descriptor, &present, &dacl, &inherited);
  const auto result = SetNamedSecurityInfoW(const_cast<PWSTR>(path.c_str()), SE_FILE_OBJECT,
      DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, nullptr, nullptr, dacl, nullptr);
  LocalFree(descriptor);
  if (result != ERROR_SUCCESS) throw std::runtime_error("acl_write_failed");
  assert_protected_directory(path, executable_control);
}
void assert_protected_directory(const fs::path& path, bool executable_control, bool require_explicit) {
  reject_reparse_path(path);
  PSECURITY_DESCRIPTOR descriptor = nullptr; PACL dacl = nullptr;
  if (GetNamedSecurityInfoW(path.c_str(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | OWNER_SECURITY_INFORMATION,
      nullptr, nullptr, &dacl, nullptr, &descriptor) != ERROR_SUCCESS) throw std::runtime_error("acl_read_failed");
  PSID system = nullptr, admins = nullptr, users = nullptr;
  ConvertStringSidToSidW(L"S-1-5-18", &system); ConvertStringSidToSidW(L"S-1-5-32-544", &admins);
  ConvertStringSidToSidW(L"S-1-5-32-545", &users);
  bool safe = dacl != nullptr; SECURITY_DESCRIPTOR_CONTROL control = 0; DWORD revision = 0;
  GetSecurityDescriptorControl(descriptor, &control, &revision);
  safe = safe && (!require_explicit || (control & SE_DACL_PROTECTED));
  PSID owner = nullptr; BOOL owner_defaulted = FALSE;
  GetSecurityDescriptorOwner(descriptor, &owner, &owner_defaulted);
  safe = safe && owner && (EqualSid(owner, system) || EqualSid(owner, admins));
  if (dacl) for (DWORD i = 0; i < dacl->AceCount; ++i) {
    void* ace = nullptr; GetAce(dacl, i, &ace);
    const auto header = static_cast<ACE_HEADER*>(ace);
    if (header->AceType == ACCESS_ALLOWED_ACE_TYPE) {
      const auto allowed = static_cast<ACCESS_ALLOWED_ACE*>(ace);
      PSID sid = const_cast<DWORD*>(&allowed->SidStart);
      if (!EqualSid(sid, system) && !EqualSid(sid, admins) &&
          !(executable_control && EqualSid(sid, users) && (allowed->Mask & ~DWORD{0x1200a9}) == 0)) safe = false;
    } else if (header->AceType != ACCESS_DENIED_ACE_TYPE) safe = false;
  }
  LocalFree(system); LocalFree(admins); LocalFree(users); LocalFree(descriptor);
  if (!safe) throw std::runtime_error("unsafe_updater_acl");
}
void assert_protected_tree(const fs::path& path, bool executable_control) {
  assert_protected_directory(path, executable_control);
  for (const auto& entry : fs::recursive_directory_iterator(path))
    assert_protected_directory(entry.path(), executable_control, false);
}
static std::string hex(const uint8_t* bytes, size_t size) {
  std::ostringstream result; result << std::hex << std::setfill('0');
  for (size_t i = 0; i < size; ++i) result << std::setw(2) << static_cast<unsigned>(bytes[i]);
  return result.str();
}
std::string sha256_file(const fs::path& path) {
  reject_reparse_path(path);
  Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
  if (!file.valid()) throw std::runtime_error("hash_file_open_failed");
  BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) throw std::runtime_error("hash_provider_failed");
  DWORD size = 0, returned = 0;
  BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&size), sizeof(size), &returned, 0);
  std::vector<uint8_t> object(size), buffer(65536), digest(32);
  bool success = BCryptCreateHash(algorithm, &hash, object.data(), size, nullptr, 0, 0) >= 0;
  DWORD read = 0;
  while (success) {
    if (!ReadFile(file.get(), buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) { success = false; break; }
    if (!read) break;
    success = BCryptHashData(hash, buffer.data(), read, 0) >= 0;
  }
  success = success && BCryptFinishHash(hash, digest.data(), 32, 0) >= 0;
  if (hash) BCryptDestroyHash(hash); BCryptCloseAlgorithmProvider(algorithm, 0);
  if (!success) throw std::runtime_error("hash_failed");
  return hex(digest.data(), digest.size());
}
std::vector<uint8_t> decode_base64(const std::string& value) {
  DWORD size = 0;
  if (!CryptStringToBinaryA(value.c_str(), static_cast<DWORD>(value.size()), CRYPT_STRING_BASE64 | CRYPT_STRING_STRICT, nullptr, &size, nullptr, nullptr))
    throw std::runtime_error("invalid_base64");
  std::vector<uint8_t> bytes(size);
  if (!CryptStringToBinaryA(value.c_str(), static_cast<DWORD>(value.size()), CRYPT_STRING_BASE64 | CRYPT_STRING_STRICT, bytes.data(), &size, nullptr, nullptr))
    throw std::runtime_error("invalid_base64");
  bytes.resize(size); return bytes;
}
Json verify_manifest(const Json& envelope, const std::string& keys) {
  require_fields(envelope, {"formatVersion", "payloadBase64", "signatureBase64"});
  if (!envelope.at("formatVersion").is_number_unsigned() || envelope.at("formatVersion") != 1)
    throw std::runtime_error("unsupported_envelope");
  const auto payload = decode_base64(envelope.at("payloadBase64").get<std::string>());
  const auto signature = decode_base64(envelope.at("signatureBase64").get<std::string>());
  if (payload.size() > kMaxManifestBytes || signature.size() != 64) throw std::runtime_error("invalid_manifest_size");
  bool verified = false; std::istringstream stream(keys); std::string key;
  while (std::getline(stream, key, ',')) {
    const auto decoded = decode_base64(key);
    if (decoded.size() != 32) throw std::runtime_error("invalid_public_key");
    verified |= crypto_ed25519_check(signature.data(), decoded.data(), payload.data(), payload.size()) == 0;
  }
  if (!verified) throw std::runtime_error("manifest_signature_invalid");
  const std::string text(payload.begin(), payload.end());
  const auto manifest = parse_json(text, kMaxManifestBytes);
  validate_manifest(manifest);
  if (manifest.dump(-1, ' ', false) != text) throw std::runtime_error("noncanonical_manifest");
  return manifest;
}
std::string trusted_publisher(const fs::path& executable) {
  reject_reparse_path(executable);
  WINTRUST_FILE_INFO file{}; file.cbStruct = sizeof(file); file.pcwszFilePath = executable.c_str();
  WINTRUST_DATA data{}; data.cbStruct = sizeof(data); data.dwUIChoice = WTD_UI_NONE;
  data.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN; data.dwProvFlags = WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT;
  data.dwUnionChoice = WTD_CHOICE_FILE; data.pFile = &file; data.dwStateAction = WTD_STATEACTION_VERIFY;
  GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  const LONG result = WinVerifyTrust(nullptr, &action, &data);
  std::string thumbprint;
  if (result == ERROR_SUCCESS) {
    const auto provider = WTHelperProvDataFromStateData(data.hWVTStateData);
    const auto signer = provider ? WTHelperGetProvSignerFromChain(provider, 0, FALSE, 0) : nullptr;
    const auto certificate = signer ? WTHelperGetProvCertFromChain(signer, 0) : nullptr;
    if (certificate && certificate->pCert) {
      uint8_t digest[32]{}; DWORD size = sizeof(digest);
      if (CryptHashCertificate2(BCRYPT_SHA256_ALGORITHM, 0, nullptr, certificate->pCert->pbCertEncoded,
          certificate->pCert->cbCertEncoded, digest, &size)) thumbprint = hex(digest, size);
    }
  }
  data.dwStateAction = WTD_STATEACTION_CLOSE; WinVerifyTrust(nullptr, &action, &data);
  if (thumbprint.empty()) throw std::runtime_error("authenticode_unconfirmed");
  return thumbprint;
}
std::wstring quote(const std::wstring& value) {
  std::wstring result = L"\""; size_t slashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') { ++slashes; continue; }
    result.append(character == L'"' ? slashes * 2 + 1 : slashes, L'\\'); slashes = 0;
    result += character;
  }
  result.append(slashes * 2, L'\\'); return result + L"\"";
}
bool is_admin() {
  SID_IDENTIFIER_AUTHORITY authority = SECURITY_NT_AUTHORITY; PSID admins = nullptr; BOOL member = FALSE;
  if (!AllocateAndInitializeSid(&authority, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &admins)) return false;
  CheckTokenMembership(nullptr, admins, &member); FreeSid(admins); return member != FALSE;
}
std::string process_user_sid(HANDLE process) {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &raw)) throw std::runtime_error("process_token_unconfirmed");
  Handle token(raw);
  DWORD size = 0;
  GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  if (!size) throw std::runtime_error("process_token_unconfirmed");
  std::vector<uint8_t> bytes(size);
  if (!GetTokenInformation(token.get(), TokenUser, bytes.data(), size, &size))
    throw std::runtime_error("process_token_unconfirmed");
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &sid))
    throw std::runtime_error("process_sid_unconfirmed");
  const auto result = utf8(sid); LocalFree(sid); return result;
}
bool active_user_session(DWORD session, const std::string& sid) {
  if (session == 0) return false;
  LPWSTR information = nullptr; DWORD size = 0;
  if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, session, WTSConnectState, &information, &size))
    return false;
  const bool active = size == sizeof(WTS_CONNECTSTATE_CLASS) &&
      *reinterpret_cast<WTS_CONNECTSTATE_CLASS*>(information) == WTSActive;
  WTSFreeMemory(information);
  if (!active) return false;
  HANDLE raw = nullptr;
  if (!WTSQueryUserToken(session, &raw)) return false;
  Handle token(raw);
  size = 0; GetTokenInformation(token.get(), TokenUser, nullptr, 0, &size);
  if (!size) return false;
  std::vector<uint8_t> bytes(size);
  if (!GetTokenInformation(token.get(), TokenUser, bytes.data(), size, &size)) return false;
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &text)) return false;
  const bool matches = utf8(text) == sid; LocalFree(text); return matches;
}
Json load_policy(bool require_enabled) {
  assert_protected_directory(updater_root());
  assert_protected_directory(updater_root() / L"policy.json", false, false);
  const auto policy = parse_json(read_file(updater_root() / L"policy.json"));
  if (!policy.at("protocol").is_number_unsigned() || policy.at("protocol") != 1 ||
      !policy.at("enabled").is_boolean()) throw std::runtime_error("invalid_policy");
  if (require_enabled && !policy.at("enabled").get<bool>()) throw std::runtime_error("authorization_required");
  reject_reparse_path(fs::path(wide(policy.at("installDirectory").get<std::string>())));
  return policy;
}
std::string encode_base64(const std::vector<uint8_t>& bytes) {
  DWORD length = 0;
  if (!CryptBinaryToStringA(bytes.data(), static_cast<DWORD>(bytes.size()), CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &length))
    throw std::runtime_error("base64_encoding_failed");
  std::string output(length, '\0');
  if (!CryptBinaryToStringA(bytes.data(), static_cast<DWORD>(bytes.size()), CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, output.data(), &length))
    throw std::runtime_error("base64_encoding_failed");
  if (!output.empty() && output.back() == '\0') output.pop_back();
  return output;
}
std::vector<uint8_t> user_dpapi(const std::vector<uint8_t>& bytes, bool encrypting) {
  if (bytes.empty() || bytes.size() > 512 * 1024) throw std::runtime_error("user_snapshot_size_rejected");
  DATA_BLOB input{static_cast<DWORD>(bytes.size()), const_cast<BYTE*>(bytes.data())}, output{};
  const BOOL success = encrypting ? CryptProtectData(&input, L"Plug Agente exact update snapshot v1", nullptr,
      nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output) :
      CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output);
  if (!success) throw std::runtime_error("user_snapshot_dpapi_failed");
  std::vector<uint8_t> result(output.pbData, output.pbData + output.cbData);
  SecureZeroMemory(output.pbData, output.cbData); LocalFree(output.pbData); return result;
}
bool pipe_transfer(HANDLE pipe, void* buffer, DWORD size, bool writing, DWORD timeout_ms) {
  OVERLAPPED operation{}; Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr)); operation.hEvent = event.get();
  DWORD transferred = 0;
  const BOOL started = writing ? WriteFile(pipe, buffer, size, &transferred, &operation) : ReadFile(pipe, buffer, size, &transferred, &operation);
  if (!started) {
    if (GetLastError() != ERROR_IO_PENDING) return false;
    if (WaitForSingleObject(event.get(), timeout_ms) != WAIT_OBJECT_0) {
      CancelIoEx(pipe, &operation); GetOverlappedResult(pipe, &operation, &transferred, TRUE); return false;
    }
    if (!GetOverlappedResult(pipe, &operation, &transferred, FALSE)) return false;
  }
  return transferred == size;
}
Json pipe_call(const Json& request) {
  if (!WaitNamedPipeW(L"\\\\.\\pipe\\PlugAgenteUpdater.v1", 5000)) throw std::runtime_error("updater_unavailable");
  Handle pipe(CreateFileW(L"\\\\.\\pipe\\PlugAgenteUpdater.v1", FILE_READ_DATA | FILE_WRITE_DATA | SYNCHRONIZE,
      0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IMPERSONATION, nullptr));
  if (!pipe.valid()) throw std::runtime_error("updater_unavailable");
  // A local user can squat a named pipe while the service is stopped. Bind
  // its actual server PID to the machine's administratively registered SCM
  // service before transmitting an authenticated request or user snapshot.
  ULONG server_pid = 0;
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  SC_HANDLE service = manager ? OpenServiceW(manager, L"PlugAgenteUpdater", SERVICE_QUERY_STATUS | SERVICE_QUERY_CONFIG) : nullptr;
  SERVICE_STATUS_PROCESS service_status{}; DWORD needed = 0;
  bool trusted = service && GetNamedPipeServerProcessId(pipe.get(), &server_pid) &&
      QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<LPBYTE>(&service_status), sizeof(service_status), &needed) &&
      service_status.dwCurrentState == SERVICE_RUNNING && service_status.dwProcessId == server_pid;
  if (trusted) {
    QueryServiceConfigW(service, nullptr, 0, &needed);
    std::vector<uint8_t> bytes(needed);
    auto configuration = reinterpret_cast<QUERY_SERVICE_CONFIGW*>(bytes.data());
    trusted = needed != 0 && QueryServiceConfigW(service, configuration, needed, &needed) &&
        quote((control_root() / L"plug_update_service.exe").native()) == configuration->lpBinaryPathName &&
        _wcsicmp(configuration->lpServiceStartName, L"LocalSystem") == 0 &&
        configuration->dwServiceType == SERVICE_WIN32_OWN_PROCESS;
  }
  if (service) CloseServiceHandle(service);
  if (manager) CloseServiceHandle(manager);
  if (!trusted) throw std::runtime_error("updater_server_identity_rejected");
  auto bytes = request.dump(); DWORD length = static_cast<DWORD>(bytes.size());
  if (length > kMaxMessageBytes || !pipe_transfer(pipe.get(), &length, sizeof(length), true, 5000) ||
      !pipe_transfer(pipe.get(), bytes.data(), length, true, 5000) ||
      !pipe_transfer(pipe.get(), &length, sizeof(length), false, 10000) || length > kMaxMessageBytes)
    throw std::runtime_error("updater_ipc_failed");
  bytes.resize(length);
  if (!pipe_transfer(pipe.get(), bytes.data(), length, false, 10000)) throw std::runtime_error("updater_ipc_failed");
  return parse_json(bytes);
}
}  // namespace plug::updater
