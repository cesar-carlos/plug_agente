#include "win_security.h"
#include <iostream>

using namespace plug::updater;
int main(int argc, char** argv) {
  try {
    if (argc == 2) {
      const auto fixture = parse_json(read_file(fs::absolute(argv[1])));
      const auto verified = verify_manifest(fixture.at("envelope"), fixture.at("publicKey"));
      if (verified != fixture.at("payload")) throw std::runtime_error("cross_language_contract_mismatch");
      auto altered = fixture.at("envelope"); altered["signatureBase64"] = std::string(88, 'A');
      bool invalid = false;
      try { verify_manifest(altered, fixture.at("publicKey")); } catch (const std::exception&) { invalid = true; }
      if (!invalid) throw std::runtime_error("tampered_vector_accepted");
      std::cout << "Cross-language signature checks passed\n"; return 0;
    }
    bool rejected = false;
    if (!requires_authenticode(Json::object()) || requires_authenticode(Json{{"requireAuthenticode", false}}))
      throw std::runtime_error("authenticode_policy_default_changed");
    const Json hashes{{"binaryHashes", {{"app", std::string(64, 'a')}}}};
    require_binary_hash(hashes, "app", std::string(64, 'a'));
    for (const auto& digest : {std::string(64, 'b'), std::string(63, 'a'), std::string()}) {
      rejected = false;
      try { require_binary_hash(hashes, "app", digest); } catch (...) { rejected = true; }
      if (!rejected) throw std::runtime_error("registered_binary_tampering_accepted");
    }
    rejected = false;
    try { parse_json("{\"version\":1,\"version\":2}"); } catch (...) { rejected = true; }
    if (!rejected) throw std::runtime_error("duplicates_accepted");
    const auto manifest = parse_json(R"({"formatVersion":1,"version":"1.8.6+1","channel":"stable","installer":{"name":"PlugAgente-Setup-1.8.6.exe","size":123,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"protocol":{"host":1,"worker":1},"data":{"schema":30,"rollbackProtocol":1},"requirements":["app.files","firewall.new"],"release":{"commit":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","tag":"v1.8.6"}})");
    validate_manifest(manifest);
    for (const auto& state : {"waitingForExit", "snapshotting", "installing", "verifying", "rollingBack", "restoringUserData", "recoveryRequired", "unknown"})
      if (can_prepare_operation(state)) throw std::runtime_error("unsafe_operation_overwritten");
    for (const auto& state : {"idle", "preparing", "deferred", "completed", "rolledBack"})
      if (!can_prepare_operation(state)) throw std::runtime_error("confirmed_operation_not_reusable");
    for (const auto& invalid : {Json(true), Json(1.0)}) {
      auto changed = manifest; changed["protocol"]["host"] = invalid;
      rejected = false;
      try { validate_manifest(changed); } catch (...) { rejected = true; }
      if (!rejected) throw std::runtime_error("invalid_protocol_type_accepted");
    }
    const auto missing = missing_capabilities(manifest, Json{{"capabilities", {"app.files"}}});
    if (missing != std::vector<std::string>{"firewall.new"}) throw std::runtime_error("authorization_diff_incorrect");
    rejected = false;
    try { verify_manifest(Json::object(), ""); } catch (...) { rejected = true; }
    if (!rejected) throw std::runtime_error("unsigned_accepted");
    if (!newer_version("2.0.0+1", "1.99.99+999") || !newer_version("1.2.3+10", "1.2.3+9") ||
        newer_version("1.2.3+1", "1.2.3+1") || newer_version("1.0.0+1000", "2.0.0+1"))
      throw std::runtime_error("version_replay_check_failed");
    if (quote(L"C:\\path\\") != L"\"C:\\path\\\\\"") throw std::runtime_error("incorrect_windows_quoting");
    const std::vector<uint8_t> plaintext{'u', 'n', 'i', 't'};
    if (!std::regex_match(process_user_sid(GetCurrentProcess()), std::regex("S-1-[0-9-]+")))
      throw std::runtime_error("process_sid_contract_failed");
    if (active_user_session(0, "S-1-5-18")) throw std::runtime_error("service_session_accepted");
    if (registered_worker(Json{{"workerVersion", "1.8.6+1"}}) != control_root() / L"workers" / L"1.8.6+1" / L"plug_update_worker.exe")
      throw std::runtime_error("worker_version_path_incorrect");
    for (const auto& version : {"../outside", "1.0.0", "1.0.0+1/other", "1.0.0+1:stream"}) {
      rejected = false;
      try { registered_worker(Json{{"workerVersion", version}}); } catch (...) { rejected = true; }
      if (!rejected) throw std::runtime_error("worker_version_path_injection_accepted");
    }
    if (user_dpapi(user_dpapi(plaintext, true), false) != plaintext) throw std::runtime_error("dpapi_roundtrip_failed");
    const auto temporary = fs::temp_directory_path() / (L"plug_updater_pin_" + std::to_wstring(GetCurrentProcessId()));
    fs::create_directory(temporary);
    const auto file = temporary / L"fixture.bin";
    write_atomic(file, "test");
    {
      PinnedPath pinned(file);
      Handle write(CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr));
      if (write.valid()) throw std::runtime_error("pinned_file_is_writable");
      if (MoveFileExW(file.c_str(), (temporary / L"moved.bin").c_str(), 0)) throw std::runtime_error("pinned_file_can_be_renamed");
      if (MoveFileExW(temporary.c_str(), fs::path(temporary.native() + L"_moved").c_str(), 0))
        throw std::runtime_error("pinned_parent_can_be_renamed");
    }
    const auto alias = temporary / L"alias.bin";
    if (!CreateHardLinkW(alias.c_str(), file.c_str(), nullptr)) throw std::runtime_error("hardlink_fixture_failed");
    rejected = false;
    try { PinnedPath pinned(alias); } catch (...) { rejected = true; }
    if (!rejected) throw std::runtime_error("hardlinked_file_accepted");
    fs::remove(alias); fs::remove(file); fs::remove(temporary);
    std::cout << "Updater contract checks passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
