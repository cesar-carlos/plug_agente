#include <windows.h>
#include <sql.h>
#include <sqlext.h>

#include <filesystem>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace fs = std::filesystem;
namespace {
constexpr int kOptionalFailure = 2;
constexpr int kCoreFailure = 3;
constexpr DWORD kCoreTimeoutMs = 30000;

int failure(const char* code, const fs::path& resource, int severity,
            DWORD error = GetLastError()) {
  std::cout << "code=" << code << " resource=" << resource.u8string()
            << " win32_error=" << error << '\n';
  return severity;
}

fs::path bundle_directory() {
  std::vector<wchar_t> filename(32768);
  const DWORD length = GetModuleFileNameW(nullptr, filename.data(),
                                         static_cast<DWORD>(filename.size()));
  if (!length || length >= filename.size()) throw std::runtime_error("module_path_unavailable");
  return fs::path(filename.data()).parent_path();
}

int check_core(const fs::path& root) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
  for (const auto* name : {L"plug_agente.exe", L"flutter_windows.dll", L"msvcp140.dll",
                          L"vcruntime140.dll", L"vcruntime140_1.dll", L"data\\app.so",
                          L"data\\icudtl.dat", L"data\\flutter_assets\\AssetManifest.bin"}) {
    const auto file = root / name;
    if (!fs::is_regular_file(file) || fs::file_size(file) == 0)
      return failure("core_file_missing", file, kCoreFailure, ERROR_FILE_NOT_FOUND);
  }
  for (const auto* name : {L"flutter_windows.dll", L"msvcp140.dll", L"vcruntime140.dll",
                          L"vcruntime140_1.dll", L"sqlite3.dll"}) {
    const auto path = root / name;
    HMODULE library = LoadLibraryExW(path.c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!library) return failure("native_library_unavailable", path, kCoreFailure);
    if (std::wstring(name) == L"sqlite3.dll") {
      using Open = int (*)(const char*, void**);
      using Close = int (*)(void*);
      const auto open = reinterpret_cast<Open>(GetProcAddress(library, "sqlite3_open"));
      const auto close = reinterpret_cast<Close>(GetProcAddress(library, "sqlite3_close"));
      void* database = nullptr;
      const bool opened = open && close && open(":memory:", &database) == 0;
      const bool closed = !database || (close && close(database) == 0);
      FreeLibrary(library);
      if (!opened || !closed) return failure("local_database_unavailable", path, kCoreFailure, 0);
      continue;
    }
    FreeLibrary(library);
  }
  const auto application = root / L"plug_agente.exe";
  std::wstring command = L"\"" + application.native() + L"\" --installation-check";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(application.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, root.c_str(), &startup, &process))
    return failure("core_process_unavailable", application, kCoreFailure);
  CloseHandle(process.hThread);
  const DWORD wait = WaitForSingleObject(process.hProcess, kCoreTimeoutMs);
  DWORD code = kCoreFailure;
  if (wait != WAIT_OBJECT_0) {
    TerminateProcess(process.hProcess, kCoreFailure);
    WaitForSingleObject(process.hProcess, 5000);
  } else if (!GetExitCodeProcess(process.hProcess, &code)) {
    code = kCoreFailure;
  }
  CloseHandle(process.hProcess);
  if (wait != WAIT_OBJECT_0) return failure("core_check_timeout", application, kCoreFailure, wait);
  if (code != 0) return failure("core_boot_failed", application, kCoreFailure, code);
  std::cout << "code=core_ready resource=" << root.u8string() << '\n';
  return 0;
}

int check_odbc() {
  const auto engine = bundle_directory() / L"odbc_engine.dll";
  HMODULE library = LoadLibraryExW(engine.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!library) return failure("odbc_engine_unavailable", engine, kOptionalFailure);
  FreeLibrary(library);
  SQLHENV environment = SQL_NULL_HENV;
  if (!SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &environment)))
    return failure("odbc_manager_unavailable", L"odbc32.dll", kOptionalFailure, 0);
  if (!SQL_SUCCEEDED(SQLSetEnvAttr(environment, SQL_ATTR_ODBC_VERSION,
                                  reinterpret_cast<SQLPOINTER>(SQL_OV_ODBC3), 0))) {
    SQLFreeHandle(SQL_HANDLE_ENV, environment);
    return failure("odbc_environment_unavailable", L"odbc32.dll", kOptionalFailure, 0);
  }
  SQLWCHAR name[1024], attributes[4096];
  SQLSMALLINT name_length = 0, attributes_length = 0;
  const SQLRETURN status = SQLDriversW(environment, SQL_FETCH_FIRST, name, 1024,
                                      &name_length, attributes, 4096, &attributes_length);
  SQLFreeHandle(SQL_HANDLE_ENV, environment);
  if (status == SQL_NO_DATA)
    return failure("odbc_driver_missing", L"ODBC x64", kOptionalFailure, 0);
  if (!SQL_SUCCEEDED(status))
    return failure("odbc_enumeration_failed", L"ODBC x64", kOptionalFailure, 0);
  std::cout << "code=odbc_driver_available database_connection=not_tested\n";
  return 0;
}

int check_data(const fs::path& directory) {
  if (!fs::is_directory(directory))
    return failure("data_directory_missing", directory, kOptionalFailure, ERROR_PATH_NOT_FOUND);
  const auto probe = directory / (L".installation-check-" + std::to_wstring(GetCurrentProcessId()) + L".tmp");
  HANDLE file = CreateFileW(probe.c_str(), GENERIC_READ | GENERIC_WRITE | DELETE, 0,
                            nullptr, CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
  if (file == INVALID_HANDLE_VALUE) return failure("data_write_denied", directory, kOptionalFailure);
  const char contents[] = "installation-check";
  char readback[sizeof(contents)]{};
  DWORD written = 0, read = 0;
  const bool writable = WriteFile(file, contents, sizeof(contents), &written, nullptr) &&
      written == sizeof(contents) && SetFilePointer(file, 0, nullptr, FILE_BEGIN) != INVALID_SET_FILE_POINTER &&
      ReadFile(file, readback, sizeof(readback), &read, nullptr) && read == sizeof(contents) &&
      std::memcmp(readback, contents, sizeof(contents)) == 0;
  const DWORD error = writable ? ERROR_SUCCESS : GetLastError();
  CloseHandle(file);
  if (!writable) return failure("data_read_write_failed", directory, kOptionalFailure, error);
  std::cout << "code=data_ready resource=" << directory.u8string() << '\n';
  return 0;
}
}

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 2 && std::wstring(argv[1]) == L"--core") return check_core(bundle_directory());
    if (argc == 2 && std::wstring(argv[1]) == L"--odbc") return check_odbc();
    if (argc == 3 && std::wstring(argv[1]) == L"--data") return check_data(fs::path(argv[2]));
    return failure("invalid_check_arguments", L"plug_install_check", kCoreFailure, 0);
  } catch (const std::exception&) {
    return failure("check_io_failed", L"plug_install_check", kCoreFailure);
  }
}
