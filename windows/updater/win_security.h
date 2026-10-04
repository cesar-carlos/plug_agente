#pragma once
#include <windows.h>
#include <filesystem>
#include <memory>
#include "contract.h"

namespace plug::updater {
namespace fs = std::filesystem;
class Handle {
 public:
  explicit Handle(HANDLE value = nullptr) : value_(value) {}
  ~Handle() { if (value_ && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE get() const { return value_; }
  bool valid() const { return value_ && value_ != INVALID_HANDLE_VALUE; }
 private:
  HANDLE value_;
};
/// Holds every ancestor against rename/delete. The leaf is opened without
/// following reparse points and, for files, without permitting writes/deletes.
class PinnedPath {
 public:
  explicit PinnedPath(const fs::path& path, DWORD leaf_access = GENERIC_READ);
  HANDLE leaf() const { return handles_.back()->get(); }
 private:
  std::vector<std::unique_ptr<Handle>> handles_;
};
std::wstring wide(const std::string& value);
std::string utf8(const std::wstring& value);
fs::path updater_root();
fs::path control_root();
fs::path registered_worker(const Json& policy);
std::string read_file(const fs::path& path, size_t limit = kMaxMessageBytes);
void write_atomic(const fs::path& path, const std::string& bytes);
void reject_reparse_path(const fs::path& path);
void protect_directory(const fs::path& path, bool executable_control = false);
void assert_protected_directory(const fs::path& path, bool executable_control = false, bool require_explicit = true);
void assert_protected_tree(const fs::path& path, bool executable_control = false);
std::string sha256_file(const fs::path& path);
std::vector<uint8_t> decode_base64(const std::string& value);
std::string encode_base64(const std::vector<uint8_t>& bytes);
std::vector<uint8_t> user_dpapi(const std::vector<uint8_t>& bytes, bool encrypting);
Json verify_manifest(const Json& envelope, const std::string& keys);
std::string trusted_publisher(const fs::path& executable);
std::wstring quote(const std::wstring& value);
bool is_admin();
Json load_policy(bool require_enabled = true);
std::string process_user_sid(HANDLE process);
bool active_user_session(DWORD session, const std::string& sid);
Json pipe_call(const Json& request);
bool pipe_transfer(HANDLE pipe, void* buffer, DWORD size, bool writing, DWORD timeout_ms);
}  // namespace plug::updater
