#pragma once
#include "contract.h"
#include <functional>

namespace plug::updater {
// Persist the update outcome before any finalization effect. The callbacks
// reconcile their own durable identities and must be safe to replay.
inline void finalize_terminal_job(Json& job, const std::function<void()>& persist,
    const std::function<void()>& release_guard, const std::function<void()>& relaunch) {
  if (!terminal_operation(job.value("state", ""))) throw std::runtime_error("finalization_not_safe");
  job["updateOutcome"] = job.at("state");
  job["finalizationPending"] = true;
  persist();
  release_guard();
  job["bootReleased"] = true;
  persist();
  if (!job.value("skipRelaunch", false)) relaunch();
  job["finalizationPending"] = false;
  persist();
}
}
