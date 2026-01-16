#include "port_monitor.h"
#include "include/exports.h"
#include <winsplp.h>

// Forward declarations for MONITOR2 interface functions
static BOOL WINAPI OpenPortFn(HANDLE hMonitor, HANDLE hPrinter,
                             LPWSTR pPortName, PHANDLE pHandle);
static BOOL WINAPI StartDocPortFn(HANDLE hMonitor, HANDLE hPort,
                                  LPWSTR pPrinterName, DWORD JobId,
                                  DWORD Level, LPBYTE pDocInfo);
static BOOL WINAPI WritePortFn(HANDLE hMonitor, HANDLE hPort,
                               LPBYTE pBuffer, DWORD cbBuf,
                               LPDWORD pcbWritten);
static BOOL WINAPI EndDocPortFn(HANDLE hMonitor, HANDLE hPort);
static BOOL WINAPI ClosePortFn(HANDLE hMonitor, HANDLE hPort);

// MONITOR2 structure - This defines the interface that Windows Spooler uses
static MONITOR2 g_Monitor2 = {
    sizeof(MONITOR2),         // cbSize
    1,                        // dwMonitorSize (version)
    OpenPortFn,               // pfnOpenPort
    nullptr,                  // pfnOpenPortEx (not required)
    StartDocPortFn,           // pfnStartDocPort
    WritePortFn,              // pfnWritePort
    EndDocPortFn,             // pfnEndDocPort
    ClosePortFn,              // pfnClosePort
    nullptr,                  // pfnAddPort (optional)
    nullptr,                  // pfnAddPortEx (optional)
    nullptr,                  // pfnConfigurePort (optional)
    nullptr,                  // pfnDeletePort (optional)
    nullptr,                  // pfnGetPrinterDataFromPort (optional)
    nullptr,                  // pfnSetPortTimeOuts (optional)
    nullptr,                  // pfnXcvOpenPort (optional)
    nullptr,                  // pfnXcvDataPort (optional)
    nullptr,                  // pfnXcvClosePort (optional)
    nullptr,                  // pfnShutdown (optional)
};

// Implementation of MONITOR2 interface functions
// These are static wrapper functions that call the PortMonitor singleton

static BOOL WINAPI OpenPortFn(HANDLE hMonitor, HANDLE hPrinter,
                             LPWSTR pPortName, PHANDLE pHandle)
{
    UNREFERENCED_PARAMETER(hMonitor);
    return PortMonitor::GetInstance().OpenPort(hPrinter, pPortName, pHandle);
}

static BOOL WINAPI StartDocPortFn(HANDLE hMonitor, HANDLE hPort,
                                  LPWSTR pPrinterName, DWORD JobId,
                                  DWORD Level, LPBYTE pDocInfo)
{
    UNREFERENCED_PARAMETER(hMonitor);
    return PortMonitor::GetInstance().StartDocPort(hPort, pPrinterName,
                                                   JobId, Level, pDocInfo);
}

static BOOL WINAPI WritePortFn(HANDLE hMonitor, HANDLE hPort,
                               LPBYTE pBuffer, DWORD cbBuf,
                               LPDWORD pcbWritten)
{
    UNREFERENCED_PARAMETER(hMonitor);
    return PortMonitor::GetInstance().WritePort(hPort, pBuffer,
                                               cbBuf, pcbWritten);
}

static BOOL WINAPI EndDocPortFn(HANDLE hMonitor, HANDLE hPort)
{
    UNREFERENCED_PARAMETER(hMonitor);
    return PortMonitor::GetInstance().EndDocPort(hPort);
}

static BOOL WINAPI ClosePortFn(HANDLE hMonitor, HANDLE hPort)
{
    UNREFERENCED_PARAMETER(hMonitor);
    return PortMonitor::GetInstance().ClosePort(hPort);
}

// DLL entry point - Called by Windows Spooler when loading the monitor
extern "C" PORTMON_API BOOL WINAPI InitializePrintMonitor2(
    PMONITORINIT pMonitorInit,
    PHANDLE phMonitor)
{
    // Validate parameters
    if (!pMonitorInit || !phMonitor) {
        return FALSE;
    }

    // Initialize the port monitor singleton
    PortMonitor& monitor = PortMonitor::GetInstance();

    // Return a pointer to our MONITOR2 structure as the monitor handle
    // The spooler will use this to call our functions
    *phMonitor = reinterpret_cast<HANDLE>(&g_Monitor2);

    return TRUE;
}
