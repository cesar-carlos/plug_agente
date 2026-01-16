#include "port_monitor.h"
#include <new>

PortMonitor::PortMonitor()
{
    m_hHeap = HeapCreate(0, 0, 0);
    InitializeCriticalSection(&m_globalLock);
}

PortMonitor::~PortMonitor()
{
    if (m_hHeap) {
        HeapDestroy(m_hHeap);
    }
    DeleteCriticalSection(&m_globalLock);
}

PortMonitor& PortMonitor::GetInstance()
{
    static PortMonitor instance;
    return instance;
}

PortContext* PortMonitor::CreatePortContext(LPWSTR pPortName)
{
    PortContext* pContext = static_cast<PortContext*>(
        HeapAlloc(m_hHeap, HEAP_ZERO_MEMORY, sizeof(PortContext))
    );

    if (!pContext) {
        return nullptr;
    }

    // Initialize context
    if (pPortName) {
        wcscpy_s(pContext->PortName, MAX_PATH, pPortName);
    } else {
        wcscpy_s(pContext->PortName, MAX_PATH, L"PLUG001:");
    }

    pContext->hPort = nullptr;
    pContext->isConnected = FALSE;
    pContext->isActive = FALSE;
    pContext->jobId = 0;
    InitializeCriticalSection(&pContext->lock);

    // Create pipe client
    pContext->pPipeClient = new (std::nothrow) NamedPipeClient();
    if (!pContext->pPipeClient) {
        DeleteCriticalSection(&pContext->lock);
        HeapFree(m_hHeap, 0, pContext);
        return nullptr;
    }

    return pContext;
}

void PortMonitor::DestroyPortContext(PortContext* pContext)
{
    if (!pContext) {
        return;
    }

    EnterCriticalSection(&pContext->lock);

    if (pContext->pPipeClient) {
        delete pContext->pPipeClient;
        pContext->pPipeClient = nullptr;
    }

    LeaveCriticalSection(&pContext->lock);
    DeleteCriticalSection(&pContext->lock);

    HeapFree(m_hHeap, 0, pContext);
}

BOOL PortMonitor::EnsurePipeConnected(PortContext* pContext)
{
    if (!pContext || !pContext->pPipeClient) {
        return FALSE;
    }

    // Already connected
    if (pContext->isConnected && pContext->pPipeClient->IsConnected()) {
        return TRUE;
    }

    // Try to connect
    if (pContext->pPipeClient->Connect()) {
        pContext->isConnected = TRUE;
        return TRUE;
    }

    pContext->isConnected = FALSE;
    return FALSE;
}

BOOL PortMonitor::OpenPort(HANDLE hPrinter, LPWSTR pPortName, PHANDLE pHandle)
{
    UNREFERENCED_PARAMETER(hPrinter);

    // Create port context
    PortContext* pContext = CreatePortContext(pPortName);
    if (!pContext) {
        return FALSE;
    }

    // Try to connect to pipe (don't fail if not connected yet)
    EnsurePipeConnected(pContext);

    pContext->isActive = TRUE;
    *pHandle = reinterpret_cast<HANDLE>(pContext);

    return TRUE;
}

BOOL PortMonitor::StartDocPort(HANDLE hPort, LPWSTR pPrinterName,
                               DWORD JobId, DWORD Level, LPBYTE pDocInfo)
{
    UNREFERENCED_PARAMETER(pPrinterName);
    UNREFERENCED_PARAMETER(Level);
    UNREFERENCED_PARAMETER(pDocInfo);

    PortContext* pContext = reinterpret_cast<PortContext*>(hPort);
    if (!pContext || !pContext->isActive) {
        return FALSE;
    }

    EnterCriticalSection(&pContext->lock);
    pContext->jobId = JobId;

    // Ensure pipe is connected before starting document
    EnsurePipeConnected(pContext);

    LeaveCriticalSection(&pContext->lock);
    return TRUE;
}

BOOL PortMonitor::WritePort(HANDLE hPort, LPBYTE pBuffer, DWORD cbBuf, LPDWORD pcbWritten)
{
    PortContext* pContext = reinterpret_cast<PortContext*>(hPort);
    if (!pContext || !pContext->isActive) {
        return FALSE;
    }

    if (!pBuffer || cbBuf == 0 || !pcbWritten) {
        return FALSE;
    }

    EnterCriticalSection(&pContext->lock);

    // Ensure pipe is connected
    if (!EnsurePipeConnected(pContext)) {
        LeaveCriticalSection(&pContext->lock);
        *pcbWritten = 0;
        return FALSE;
    }

    // Write data to pipe
    BOOL result = pContext->pPipeClient->Write(pBuffer, cbBuf);

    if (result) {
        *pcbWritten = cbBuf;
    } else {
        *pcbWritten = 0;
    }

    LeaveCriticalSection(&pContext->lock);
    return result;
}

BOOL PortMonitor::EndDocPort(HANDLE hPort)
{
    PortContext* pContext = reinterpret_cast<PortContext*>(hPort);
    if (!pContext || !pContext->isActive) {
        return FALSE;
    }

    EnterCriticalSection(&pContext->lock);
    pContext->jobId = 0;
    LeaveCriticalSection(&p_context->lock);

    return TRUE;
}

BOOL PortMonitor::ClosePort(HANDLE hPort)
{
    PortContext* pContext = reinterpret_cast<PortContext*>(hPort);
    if (!pContext) {
        return FALSE;
    }

    EnterCriticalSection(&pContext->lock);
    pContext->isActive = FALSE;
    LeaveCriticalSection(&pContext->lock);

    DestroyPortContext(pContext);
    return TRUE;
}
