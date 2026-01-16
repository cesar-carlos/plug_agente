#pragma once

#include <windows.h>
#include <winsplp.h>
#include "named_pipe_client.h"

// Port context structure - stores state for each open port
struct PortContext {
    HANDLE hPort;
    wchar_t PortName[MAX_PATH];
    BOOL isConnected;
    BOOL isActive;
    CRITICAL_SECTION lock;
    NamedPipeClient* pPipeClient;
    DWORD jobId;
};

/**
 * PortMonitor - Main print monitor implementation
 * Implements the MONITOR2 interface functions required by Windows Spooler
 */
class PortMonitor {
public:
    // Get singleton instance
    static PortMonitor& GetInstance();

    // Delete copy constructor and assignment operator
    PortMonitor(const PortMonitor&) = delete;
    PortMonitor& operator=(const PortMonitor&) = delete;

    // MONITOR2 interface methods
    BOOL OpenPort(HANDLE hPrinter, LPWSTR pPortName, PHANDLE pHandle);
    BOOL StartDocPort(HANDLE hPort, LPWSTR pPrinterName,
                     DWORD JobId, DWORD Level, LPBYTE pDocInfo);
    BOOL WritePort(HANDLE hPort, LPBYTE pBuffer, DWORD cbBuf, LPDWORD pcbWritten);
    BOOL EndDocPort(HANDLE hPort);
    BOOL ClosePort(HANDLE hPort);

private:
    PortMonitor();
    ~PortMonitor();

    // Helper methods
    PortContext* CreatePortContext(LPWSTR pPortName);
    void DestroyPortContext(PortContext* pContext);
    BOOL EnsurePipeConnected(PortContext* pContext);

    HANDLE m_hHeap;
    CRITICAL_SECTION m_globalLock;
};
