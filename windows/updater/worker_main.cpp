#include "win_security.h"
#include <iostream>
#include <tlhelp32.h>

using namespace plug::updater;
namespace {
fs::path job_directory;
Json job;
void save() { write_atomic(updater_root() / L"journal.json", job.dump()); }
void phase(const char* state) { job["state"] = state; save(); }
uint64_t created(HANDLE process) {
  FILETIME start{}, end{}, kernel{}, user{};
  if (!GetProcessTimes(process, &start, &end, &kernel, &user)) throw std::runtime_error("process_identity_unconfirmed");
  return (static_cast<uint64_t>(start.dwHighDateTime) << 32) | start.dwLowDateTime;
}
void assert_no_running_agent() {
  const auto expected = fs::path(wide(job.at("installDirectory").get<std::string>())) / L"plug_agente.exe";
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  if (!snapshot.valid()) throw std::runtime_error("agent_process_inventory_unconfirmed");
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
  if (!Process32FirstW(snapshot.get(), &entry)) throw std::runtime_error("agent_process_inventory_unconfirmed");
  do {
    if (_wcsicmp(entry.szExeFile, L"plug_agente.exe") != 0) continue;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, entry.th32ProcessID));
    if (!process.valid()) {
      if (GetLastError() == ERROR_INVALID_PARAMETER) continue;
      throw std::runtime_error("agent_process_identity_unconfirmed");
    }
    wchar_t path[32768]{}; DWORD length = 32768;
    if (!QueryFullProcessImageNameW(process.get(), 0, path, &length)) throw std::runtime_error("agent_process_identity_unconfirmed");
    if (_wcsicmp(path, expected.c_str()) == 0 && WaitForSingleObject(process.get(), 0) != WAIT_OBJECT_0)
      throw std::runtime_error("agent_process_still_active");
  } while (Process32NextW(snapshot.get(), &entry));
  if (GetLastError() != ERROR_NO_MORE_FILES) throw std::runtime_error("agent_process_inventory_unconfirmed");
}
void copy_tree(const fs::path& source, const fs::path& target, Json& inventory) {
  reject_reparse_path(source); reject_reparse_path(target);
  PinnedPath source_root(source);
  fs::create_directories(target);
  PinnedPath target_root(target);
  for (const auto& entry : fs::recursive_directory_iterator(source)) {
    reject_reparse_path(entry.path());
    const auto relative = entry.path().lexically_relative(source);
    const auto destination = target / relative;
    if (entry.is_directory()) { fs::create_directories(destination); continue; }
    if (!entry.is_regular_file()) throw std::runtime_error("snapshot_file_type_rejected");
    fs::create_directories(destination.parent_path());
    PinnedPath pinned_source(entry.path());
    PinnedPath pinned_destination_parent(destination.parent_path());
    // Never follow links or copy ACLs from writable app data into protected storage.
    if (!CopyFileW(entry.path().c_str(), destination.c_str(), TRUE)) throw std::runtime_error("snapshot_copy_failed");
    inventory[utf8(relative.generic_wstring())] = Json{{"sha256", sha256_file(destination)}, {"size", fs::file_size(destination)}};
  }
}
void delete_contents(const fs::path& directory) {
  PinnedPath root(directory);
  for (const auto& entry : fs::directory_iterator(directory)) {
    if (entry.is_directory()) delete_contents(entry.path());
    // Remove the exact opened object, never recursively follow a pathname
    // that another user could replace with a junction between checks.
    PinnedPath child(entry.path(), DELETE | FILE_READ_ATTRIBUTES);
    FILE_ATTRIBUTE_TAG_INFO attributes{};
    if (!GetFileInformationByHandleEx(child.leaf(), FileAttributeTagInfo, &attributes, sizeof(attributes)))
      throw std::runtime_error("restore_object_unconfirmed");
    FILE_DISPOSITION_INFO disposition{TRUE};
    if (!SetFileInformationByHandle(child.leaf(), FileDispositionInfo, &disposition, sizeof(disposition)))
      throw std::runtime_error("restore_delete_unconfirmed");
  }
}
uint64_t tree_size(const fs::path& root) {
  uint64_t total = 0;
  for (const auto& entry : fs::recursive_directory_iterator(root)) {
    reject_reparse_path(entry.path());
    if (entry.is_regular_file()) total += entry.file_size();
  }
  return total;
}
void verify_tree(const fs::path& directory, const Json& inventory) {
  for (const auto& entry : inventory.items()) {
    const auto file = directory / wide(entry.key());
    reject_reparse_path(file);
    if (fs::file_size(file) != entry.value().at("size").get<uint64_t>() || sha256_file(file) != entry.value().at("sha256"))
      throw std::runtime_error("snapshot_hash_mismatch");
  }
}
void restore_tree(const fs::path& source, const fs::path& target, const Json& inventory) {
  verify_tree(source, inventory);
  reject_reparse_path(target);
  // Only the administratively registered app directory and fixed app-data directory are allowed.
  const auto policy = load_policy(false);
  if (target != fs::path(wide(policy.at("installDirectory").get<std::string>())) &&
      target != updater_root().parent_path() / L"PlugAgente") throw std::runtime_error("restore_destination_rejected");
  PinnedPath pinned_target(target);
  // Preserve the registered root's ACL and remove only confirmed objects.
  delete_contents(target);
  Json ignored; copy_tree(source, target, ignored);
  verify_tree(target, inventory);
}
void snapshot() {
  const auto install = fs::path(wide(job.at("installDirectory").get<std::string>()));
  const auto data = fs::path(wide(job.at("dataDirectory").get<std::string>()));
  const auto baseline = updater_root() / L"baseline" / L"setup.exe";
  PinnedPath pinned_baseline(baseline);
  const auto policy = load_policy();
  const auto publisher = trusted_publisher(baseline);
  if (std::find(policy.at("publishers").begin(), policy.at("publishers").end(), publisher) == policy.at("publishers").end())
    throw std::runtime_error("baseline_publisher_rejected");
  const uint64_t required = 2 * (tree_size(install) + tree_size(data)) + fs::file_size(job_directory / L"setup.exe") + 256ull * 1024 * 1024;
  ULARGE_INTEGER free{};
  if (!GetDiskFreeSpaceExW(updater_root().c_str(), &free, nullptr, nullptr) || free.QuadPart < required)
    throw std::runtime_error("snapshot_space_unavailable");
  const auto directory = job_directory / L"snapshot"; protect_directory(directory);
  Json inventory{{"complete", false}, {"workerProtocol", 1}, {"secretsSha256", sha256_file(job_directory / L"secrets.dpapi")},
                 {"bundle", Json::object()}, {"data", Json::object()}};
  copy_tree(install, directory / L"bundle", inventory["bundle"]);
  // The app has explicitly checkpointed and closed SQLite before exiting. Copy all files,
  // including any sidecars, rather than using portable backup sanitization.
  copy_tree(data, directory / L"data", inventory["data"]);
  if (!CopyFileW(baseline.c_str(), (directory / L"previous-setup.exe").c_str(), TRUE)) throw std::runtime_error("baseline_snapshot_failed");
  if (sha256_file(directory / L"previous-setup.exe") != sha256_file(baseline) ||
      trusted_publisher(directory / L"previous-setup.exe") != publisher) throw std::runtime_error("baseline_snapshot_unconfirmed");
  const auto worker = registered_worker(job);
  PinnedPath pinned_worker(worker);
  if (!CopyFileW(worker.c_str(), (directory / L"previous-worker.exe").c_str(), TRUE)) throw std::runtime_error("worker_snapshot_failed");
  inventory["previousWorkerSha256"] = sha256_file(directory / L"previous-worker.exe");
  if (inventory["previousWorkerSha256"] != sha256_file(worker)) throw std::runtime_error("worker_snapshot_unconfirmed");
  inventory["previousInstallerSha256"] = sha256_file(directory / L"previous-setup.exe");
  verify_tree(directory / L"bundle", inventory["bundle"]); verify_tree(directory / L"data", inventory["data"]);
  inventory["complete"] = true;
  write_atomic(directory / L"inventory.json", inventory.dump()); job["snapshotComplete"] = true; save();
}
void validate_setup(const Json& policy, const Json& manifest) {
  const auto setup = job_directory / L"setup.exe";
  if (fs::file_size(setup) != manifest.at("installer").at("size").get<uint64_t>() ||
      sha256_file(setup) != manifest.at("installer").at("sha256")) throw std::runtime_error("installer_hash_mismatch");
  const auto publisher = trusted_publisher(setup);
  if (std::find(policy.at("publishers").begin(), policy.at("publishers").end(), publisher) == policy.at("publishers").end())
    throw std::runtime_error("installer_publisher_rejected");
  if (manifest.at("channel") != policy.at("channel") || !missing_capabilities(manifest, policy).empty())
    throw std::runtime_error("authorization_required");
}
void install() {
  const auto policy = load_policy();
  const auto manifest = verify_manifest(parse_json(read_file(job_directory / L"manifest.json")), policy.at("publicKeys").get<std::string>());
  validate_setup(policy, manifest);
  const auto setup = job_directory / L"setup.exe";
  // Keep the actual executable immutable throughout validation and execution.
  Handle pinned(CreateFileW(setup.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr));
  if (!pinned.valid()) throw std::runtime_error("installer_pin_failed");
  validate_setup(policy, manifest);
  std::wstring arguments = quote(setup.native()) + L" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /ALLUSERS /UPDATERSERVICE=1 /LAUNCHAFTERUPDATE=0 /MERGETASKS=\"!desktopicon,!startup\" /DIR=" +
      quote(wide(policy.at("installDirectory").get<std::string>())) + L" /CHANNEL=" + wide(policy.at("channel").get<std::string>()) +
      L" /LOG=" + quote((job_directory / L"setup.log").native());
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
  if (!CreateProcessW(setup.c_str(), arguments.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW | CREATE_SUSPENDED,
      nullptr, job_directory.c_str(), &startup, &process)) throw std::runtime_error("setup_start_failed");
  Handle child(process.hProcess), thread(process.hThread);
  job["setupPid"] = process.dwProcessId; job["setupCreated"] = created(child.get());
  phase("installing");
  if (ResumeThread(thread.get()) == static_cast<DWORD>(-1)) throw std::runtime_error("setup_resume_unconfirmed");
  if (WaitForSingleObject(child.get(), kInstallTimeoutMs) != WAIT_OBJECT_0) {
    // Do not kill an installer or release the machine lock while it is still active.
    job["reason"] = "setup_deadline_exceeded"; phase("recoveryRequired");
    while (true) {
      const auto waiting = WaitForSingleObject(child.get(), 1000);
      if (waiting == WAIT_OBJECT_0) break;
      DWORD actual = STILL_ACTIVE;
      if (GetExitCodeProcess(child.get(), &actual) && actual != STILL_ACTIVE) break;
      if (waiting == WAIT_FAILED) Sleep(1000);
    }
    // Reconcile a now-confirmed exit before releasing the machine lock. A
    // successful late setup still needs health verification; failure rolls back.
    job["setupDeadlineExceeded"] = true; phase("installing");
  }
  DWORD code = 1;
  if (!GetExitCodeProcess(child.get(), &code)) throw std::runtime_error("setup_exit_unconfirmed");
  job["setupExitCode"] = code; job["rebootPending"] = code == 3010; save();
  if (code != 0 && code != 3010) throw std::runtime_error("setup_failed");
}
void rollback() {
  if (!job.value("snapshotComplete", false) || job.value("rollbackAttempted", false)) throw std::runtime_error("automatic_rollback_unavailable");
  job["rollbackAttempted"] = true; phase("rollingBack");
  const auto snapshot_directory = job_directory / L"snapshot";
  const auto inventory = parse_json(read_file(snapshot_directory / L"inventory.json", 32 * 1024 * 1024), 32 * 1024 * 1024);
  if (!inventory.at("complete").get<bool>() || sha256_file(job_directory / L"secrets.dpapi") != inventory.at("secretsSha256"))
    throw std::runtime_error("snapshot_incomplete");
  if (sha256_file(snapshot_directory / L"previous-setup.exe") != inventory.at("previousInstallerSha256") ||
      sha256_file(snapshot_directory / L"previous-worker.exe") != inventory.at("previousWorkerSha256"))
    throw std::runtime_error("snapshot_binary_hash_mismatch");
  verify_tree(snapshot_directory / L"bundle", inventory.at("bundle"));
  verify_tree(snapshot_directory / L"data", inventory.at("data"));
  assert_no_running_agent();
  // Restoration requires the validation process to have exited cooperatively.
  if (job.contains("validationPid")) {
    Handle app(OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, job.at("validationPid").get<DWORD>()));
    if (app.valid() && created(app.get()) == job.at("validationCreated").get<uint64_t>() && WaitForSingleObject(app.get(), 10000) != WAIT_OBJECT_0)
      throw std::runtime_error("validation_process_still_active");
  }
  restore_tree(snapshot_directory / L"bundle", fs::path(wide(job.at("installDirectory").get<std::string>())), inventory.at("bundle"));
  restore_tree(snapshot_directory / L"data", fs::path(wide(job.at("dataDirectory").get<std::string>())), inventory.at("data"));
  // A failed promotion must not leave the failed release as the next baseline.
  PinnedPath previous_setup(snapshot_directory / L"previous-setup.exe");
  const auto baseline = updater_root() / L"baseline" / L"setup.exe";
  if (!CopyFileW((snapshot_directory / L"previous-setup.exe").c_str(), baseline.c_str(), FALSE) ||
      sha256_file(baseline) != inventory.at("previousInstallerSha256")) throw std::runtime_error("baseline_restore_unconfirmed");
  auto policy = load_policy(false); policy["workerVersion"] = job.at("workerVersion");
  write_atomic(updater_root() / L"policy.json", policy.dump());
  job["blockedVersion"] = job.at("version");
  if (!job.contains("blockedVersions")) job["blockedVersions"] = Json::array();
  if (std::find(job["blockedVersions"].begin(), job["blockedVersions"].end(), job.at("version")) == job["blockedVersions"].end())
    job["blockedVersions"].push_back(job.at("version"));
  // The original-session launcher restores DPAPI secrets before starting the previous app.
  phase("restoringUserData");
}
void execute() {
  for (unsigned i = 0; !fs::exists(job_directory / L"start.ready") && i < 100; ++i) Sleep(100);
  if (!fs::exists(job_directory / L"start.ready")) throw std::runtime_error("start_not_confirmed");
  job = parse_json(read_file(updater_root() / L"journal.json"));
  Handle app(OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, job.at("appPid").get<DWORD>()));
  if (app.valid() && created(app.get()) == job.at("appCreated").get<uint64_t>() && WaitForSingleObject(app.get(), 60000) != WAIT_OBJECT_0) {
    job["reason"] = "agent_did_not_exit_safely"; phase("deferred"); return;
  }
  if (!app.valid() && GetLastError() == ERROR_ACCESS_DENIED) throw std::runtime_error("agent_exit_unconfirmed");
  assert_no_running_agent();
  phase("snapshotting"); snapshot(); assert_no_running_agent(); install(); phase("verifying");
  const auto started = GetTickCount64();
  while (GetTickCount64() - started < kHealthTimeoutMs) {
    if (fs::exists(job_directory / L"health.json")) {
      const auto health = parse_json(read_file(job_directory / L"health.json"));
      if (health.at("nonce") == job.at("healthNonce") && health.at("version") == job.at("version")) {
        auto policy = load_policy(false);
        policy["workerVersion"] = job.at("version");
        const auto next_worker = registered_worker(policy);
        PinnedPath pinned_next_worker(next_worker);
        const auto publisher = trusted_publisher(next_worker);
        if (std::find(policy.at("publishers").begin(), policy.at("publishers").end(), publisher) == policy.at("publishers").end())
          throw std::runtime_error("healthy_worker_publisher_rejected");
        PinnedPath pinned_setup(job_directory / L"setup.exe");
        const auto baseline = updater_root() / L"baseline" / L"setup.exe";
        if (!CopyFileW((job_directory / L"setup.exe").c_str(), baseline.c_str(), FALSE) ||
            sha256_file(baseline) != sha256_file(job_directory / L"setup.exe"))
          throw std::runtime_error("healthy_baseline_promotion_failed");
        write_atomic(updater_root() / L"policy.json", policy.dump());
        job["lastHealthyVersion"] = job.at("version"); phase("completed"); return;
      }
    }
    Sleep(250);
  }
  throw std::runtime_error("health_deadline_exceeded");
}
}
int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 3 || std::wstring(argv[1]) != L"--operation" || !is_hex(utf8(argv[2]), 32)) throw std::runtime_error("invalid_worker_arguments");
    if (!is_admin()) throw std::runtime_error("worker_identity_rejected");
    assert_protected_tree(updater_root()); assert_protected_tree(control_root(), true);
    job_directory = updater_root() / L"operations" / argv[2]; assert_protected_directory(job_directory);
    Handle lock(CreateMutexW(nullptr, FALSE, L"Global\\PlugAgenteUpdater.Operation.v1"));
    if (!lock.valid() || WaitForSingleObject(lock.get(), 0) != WAIT_OBJECT_0) throw std::runtime_error("update_machine_locked");
    try { execute(); }
    catch (const std::exception& error) {
      job["reason"] = error.what(); save();
      if (job.value("state", "") == "installing" || job.value("state", "") == "verifying") {
        try { rollback(); }
        catch (const std::exception& recovery) { job["recoveryReason"] = recovery.what(); phase("recoveryRequired"); }
      } else if (job.value("state", "") != "deferred") phase("recoveryRequired");
    }
    ReleaseMutex(lock.get()); return job.value("state", "") == "completed" ? 0 : 1;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
