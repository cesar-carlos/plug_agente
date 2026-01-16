#pragma once

#ifdef PLUGPORTMON_EXPORTS
#define PORTMON_API __declspec(dllexport)
#else
#define PORTMON_API __declspec(dllimport)
#endif

// Forward declarations
struct PMONITORINIT;
typedef void* HANDLE;

extern "C" {
    // Print Monitor API entry point
    // This is the main function that Windows Spooler calls when loading the monitor
    PORTMON_API BOOL WINAPI InitializePrintMonitor2(
        struct PMONITORINIT* pMonitorInit,
        HANDLE* phMonitor
    );
}
