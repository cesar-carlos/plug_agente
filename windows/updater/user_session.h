#pragma once
#include "win_security.h"

namespace plug::updater {
// Returned process is suspended. Journal its identity before resuming it.
PROCESS_INFORMATION create_original_user_process(const Json& job, const std::wstring& arguments);
uint64_t unix_time_ms();
uint64_t process_creation_time(HANDLE process);
DWORD find_original_user_session(const Json& job);
void require_validation_process(const Json& job, DWORD pid, const std::string& sid);
}
