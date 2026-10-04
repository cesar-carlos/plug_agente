#pragma once
#include <algorithm>
#include <cstdint>
#include <set>
#include <regex>
#include <stdexcept>
#include <string>
#include <vector>
#include "third_party/json.hpp"

namespace plug::updater {
using Json = nlohmann::json;
constexpr int kProtocolVersion = 1;
// Fail closed until launcher, probation bootstrap and data recovery are wired
// and validated. Editing a policy cannot activate an unfinished implementation.
constexpr bool kApplicationContractImplemented = false;
constexpr size_t kMaxMessageBytes = 1024 * 1024;
constexpr size_t kMaxManifestBytes = 65536;
constexpr unsigned long kInstallTimeoutMs = 30 * 60 * 1000;
constexpr unsigned long kHealthTimeoutMs = 120 * 1000;
inline const std::set<std::string> kCapabilities = {
    "app.files", "app.protocol", "autostart.user", "runtime.vc", "updater.worker"};

inline bool can_prepare_operation(const std::string& state) {
  // Unknown/new states never authorize overwriting a potentially active job.
  return state == "idle" || state == "preparing" || state == "deferred" ||
      state == "completed" || state == "rolledBack";
}

inline Json parse_json(const std::string& bytes, size_t limit = kMaxMessageBytes) {
  if (bytes.size() > limit) throw std::runtime_error("message_too_large");
  std::vector<std::set<std::string>> keys;
  return Json::parse(bytes, [&](int depth, Json::parse_event_t event, Json& value) {
    if (depth > 32) throw std::runtime_error("message_too_deep");
    if (event == Json::parse_event_t::object_start) keys.emplace_back();
    if (event == Json::parse_event_t::key && !keys.back().insert(value.get<std::string>()).second)
      throw std::runtime_error("duplicate_json_field");
    if (event == Json::parse_event_t::object_end) keys.pop_back();
    return true;
  });
}

inline bool is_hex(const std::string& value, size_t length) {
  return value.size() == length && value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
inline bool newer_version(const std::string& candidate, const std::string& installed) {
  const std::regex syntax("[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+");
  if (!std::regex_match(candidate, syntax) || !std::regex_match(installed, syntax))
    throw std::runtime_error("invalid_version");
  const auto parts = [](std::string version) {
    std::replace(version.begin(), version.end(), '+', '.');
    std::vector<std::string> result;
    size_t start = 0;
    while (start < version.size()) {
      const auto end = version.find('.', start);
      auto part = version.substr(start, end == std::string::npos ? end : end - start);
      const auto nonzero = part.find_first_not_of('0');
      result.push_back(nonzero == std::string::npos ? "0" : part.substr(nonzero));
      if (end == std::string::npos) break;
      start = end + 1;
    }
    return result;
  };
  const auto left = parts(candidate), right = parts(installed);
  for (size_t index = 0; index < left.size(); ++index) {
    if (left[index].size() != right[index].size()) return left[index].size() > right[index].size();
    if (left[index] != right[index]) return left[index] > right[index];
  }
  return false;
}

inline void require_fields(const Json& object, const std::set<std::string>& expected) {
  if (!object.is_object() || object.size() != expected.size()) throw std::runtime_error("invalid_fields");
  for (const auto& key : expected) if (!object.contains(key)) throw std::runtime_error("missing_field");
}

inline void validate_manifest(const Json& value) {
  require_fields(value, {"formatVersion", "version", "channel", "installer", "requirements", "protocol", "data", "release"});
  if (!value.at("formatVersion").is_number_unsigned() || value.at("formatVersion") != 1) throw std::runtime_error("unsupported_manifest");
  const auto version = value.at("version").get<std::string>();
  const auto plus = version.find('+');
  if (version.size() > 128 || !std::regex_match(version, std::regex("[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+")))
    throw std::runtime_error("invalid_version");
  const auto channel = value.at("channel").get<std::string>();
  if (channel != "stable" && channel != "beta" && channel != "internal") throw std::runtime_error("invalid_channel");
  require_fields(value.at("release"), {"commit", "tag"});
  if (!is_hex(value.at("release").at("commit").get<std::string>(), 40) ||
      value.at("release").at("tag") != "v" + version.substr(0, plus)) throw std::runtime_error("invalid_release_source");
  const auto& installer = value.at("installer");
  require_fields(installer, {"name", "size", "sha256"});
  if (installer.at("name") != "PlugAgente-Setup-" + version.substr(0, plus) + ".exe" ||
      !installer.at("size").is_number_unsigned() || installer.at("size").get<uint64_t>() == 0 ||
      !is_hex(installer.at("sha256").get<std::string>(), 64)) throw std::runtime_error("invalid_installer");
  require_fields(value.at("protocol"), {"host", "worker"});
  if (!value.at("protocol").at("host").is_number_unsigned() || !value.at("protocol").at("worker").is_number_unsigned() ||
      value.at("protocol").at("host") != 1 || value.at("protocol").at("worker") != 1)
    throw std::runtime_error("unsupported_protocol");
  require_fields(value.at("data"), {"schema", "rollbackProtocol"});
  if (!value.at("data").at("schema").is_number_unsigned() || value.at("data").at("schema").get<unsigned>() == 0 ||
      !value.at("data").at("rollbackProtocol").is_number_unsigned() ||
      value.at("data").at("rollbackProtocol") != 1) throw std::runtime_error("unsupported_data_protocol");
  std::set<std::string> requirements;
  if (!value.at("requirements").is_array()) throw std::runtime_error("invalid_requirements");
  for (const auto& item : value.at("requirements")) {
    const auto name = item.get<std::string>();
    if (name.empty() || name.size() > 64 || name.front() < 'a' || name.front() > 'z' || name.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789._-") != std::string::npos ||
        !requirements.insert(name).second) throw std::runtime_error("invalid_capability");
  }
}

inline std::vector<std::string> missing_capabilities(const Json& manifest, const Json& policy) {
  std::set<std::string> approved;
  for (const auto& entry : policy.at("capabilities")) approved.insert(entry.get<std::string>());
  std::vector<std::string> missing;
  for (const auto& entry : manifest.at("requirements")) {
    const auto capability = entry.get<std::string>();
    if (!approved.count(capability)) missing.push_back(capability);
  }
  return missing;
}
}  // namespace plug::updater
