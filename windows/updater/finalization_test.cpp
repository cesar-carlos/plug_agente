#include "finalization.h"
#include "win_security.h"
#include "user_session.h"
#include <fstream>
#include <iostream>

using namespace plug::updater;
namespace {
void interrupted_finalization(const fs::path& root, int interrupt_after) {
  fs::create_directory(root);
  const auto journal = root / L"journal.json";
  const auto guard = root / L"boot-blocked";
  const auto output = root / L"child.txt";
  Json job{{"state", "completed"}, {"operationId", std::string(32, 'a')}};
  write_atomic(journal, job.dump()); write_atomic(guard, std::string(32, 'a'));
  int checkpoint = 0, creations = 0;
  bool interrupt = true;
  std::unique_ptr<Handle> child, thread;
  const auto step = [&] { if (interrupt && ++checkpoint == interrupt_after) throw std::runtime_error("interruption"); };
  const auto persist = [&] { write_atomic(journal, job.dump()); step(); };
  const auto release = [&] {
    if (fs::exists(guard)) {
      if (read_file(guard, 64) != job.at("operationId")) throw std::runtime_error("wrong_guard");
      fs::remove(guard);
    }
    step();
  };
  const auto relaunch = [&] {
    if (!job.contains("relaunchedPid")) {
      wchar_t executable[32768]{}; GetModuleFileNameW(nullptr, executable, 32768);
      std::wstring line = quote(executable) + L" --child " + quote(output.native());
      STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
      if (!CreateProcessW(executable, line.data(), nullptr, nullptr, FALSE, CREATE_SUSPENDED | CREATE_NO_WINDOW,
          nullptr, root.c_str(), &startup, &process)) throw std::runtime_error("child_creation_failed");
      child = std::make_unique<Handle>(process.hProcess); thread = std::make_unique<Handle>(process.hThread); ++creations;
      job["relaunchedPid"] = process.dwProcessId;
      job["relaunchedCreated"] = process_creation_time(child->get());
      job["relaunchStage"] = "created";
      persist(); // Production also records the suspended child's identity before resume.
    }
    if (process_creation_time(child->get()) != job.at("relaunchedCreated")) throw std::runtime_error("child_identity_changed");
    if (job.at("relaunchStage") == "created") {
      if (ResumeThread(thread->get()) == static_cast<DWORD>(-1)) throw std::runtime_error("child_resume_failed");
      step();
      job["relaunchStage"] = "dispatched"; persist();
    }
  };
  try { finalize_terminal_job(job, persist, release, relaunch); }
  catch (const std::exception& error) { if (std::string(error.what()) != "interruption") throw; }
  // Discard memory and reconcile the last durable journal with the real process.
  job = parse_json(read_file(journal)); interrupt = false;
  finalize_terminal_job(job, persist, release, relaunch);
  finalize_terminal_job(job, persist, release, relaunch);
  if (fs::exists(guard) || job.at("finalizationPending") != false || job.at("updateOutcome") != "completed" || creations != 1)
    throw std::runtime_error("finalization_not_idempotent");
  if (WaitForSingleObject(child->get(), 10000) != WAIT_OBJECT_0 || read_file(output, 32) != "started\n")
    throw std::runtime_error("duplicate_or_missing_relaunch");
  thread.reset(); child.reset();
  fs::remove(output); fs::remove(journal); fs::remove(root);
}
}
int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 3 && std::wstring(argv[1]) == L"--child") {
      std::ofstream output(fs::path(argv[2]), std::ios::app | std::ios::binary); output << "started\n"; output.close();
      Sleep(1000); return 0;
    }
    const auto root = fs::temp_directory_path() / (L"plug_finalization_" + std::to_wstring(GetCurrentProcessId()));
    for (int step = 1; step <= 7; ++step) interrupted_finalization(fs::path(root.native() + std::to_wstring(step)), step);
    for (const auto& state : {"completed", "rolledBack", "deferred"}) {
      Json job{{"state", state}};
      if (!finalization_needed(job, true) || finalization_needed(job, false)) throw std::runtime_error("legacy_terminal_incorrect");
      job["finalizationPending"] = true;
      if (!finalization_needed(job, false)) throw std::runtime_error("pending_finalization_lost");
      bool session = false; int relaunches = 0;
      try { finalize_terminal_job(job, [] {}, [] {}, [&] { if (!session) throw std::runtime_error("session_unavailable"); }); }
      catch (...) {}
      if (!job.at("finalizationPending").get<bool>()) throw std::runtime_error("unavailable_session_lost");
      session = true;
      finalize_terminal_job(job, [] {}, [] {}, [&] { ++relaunches; });
      if (relaunches != 1 || job.at("updateOutcome") != state) throw std::runtime_error("outcome_changed");
    }
    Json active{{"state", "installing"}, {"finalizationPending", true}};
    bool rejected = false;
    try { finalize_terminal_job(active, [] {}, [] {}, [] {}); } catch (...) { rejected = true; }
    if (!rejected) throw std::runtime_error("active_installation_finalized");
    std::cout << "Finalization interruption checks passed\n"; return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
