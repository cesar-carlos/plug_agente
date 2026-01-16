#include "named_pipe_client.h"

NamedPipeClient::NamedPipeClient()
    : m_hPipe(INVALID_HANDLE_VALUE)
    , m_timeoutMs(PIPE_TIMEOUT_MS)
    , m_lastError(0)
{
}

NamedPipeClient::~NamedPipeClient()
{
    Disconnect();
}

BOOL NamedPipeClient::Connect()
{
    // Already connected
    if (m_hPipe != INVALID_HANDLE_VALUE) {
        return TRUE;
    }

    // Try to connect to the named pipe (client mode)
    m_hPipe = CreateFileW(
        PIPE_NAME,
        GENERIC_WRITE,
        0,                      // No sharing
        NULL,                   // Default security
        OPEN_EXISTING,          // Open existing pipe
        0,                      // Default attributes
        NULL                    // No template file
    );

    if (m_hPipe == INVALID_HANDLE_VALUE) {
        m_lastError = GetLastError();

        // Pipe might be busy, wait for it
        if (m_lastError == ERROR_PIPE_BUSY) {
            if (WaitForPipe()) {
                // Try again after waiting
                m_hPipe = CreateFileW(
                    PIPE_NAME,
                    GENERIC_WRITE,
                    0,
                    NULL,
                    OPEN_EXISTING,
                    0,
                    NULL
                );

                if (m_hPipe != INVALID_HANDLE_VALUE) {
                    m_lastError = 0;
                    return TRUE;
                }
            }
        }

        m_lastError = GetLastError();
        return FALSE;
    }

    m_lastError = 0;
    return TRUE;
}

void NamedPipeClient::Disconnect()
{
    if (m_hPipe != INVALID_HANDLE_VALUE) {
        CloseHandle(m_hPipe);
        m_hPipe = INVALID_HANDLE_VALUE;
    }
}

BOOL NamedPipeClient::Write(const BYTE* pData, DWORD cbSize)
{
    if (m_hPipe == INVALID_HANDLE_VALUE) {
        m_lastError = ERROR_INVALID_HANDLE;
        return FALSE;
    }

    if (pData == nullptr || cbSize == 0) {
        m_lastError = ERROR_INVALID_PARAMETER;
        return FALSE;
    }

    DWORD cbWritten = 0;
    BOOL result = WriteFile(
        m_hPipe,
        pData,
        cbSize,
        &cbWritten,
        NULL
    );

    if (!result) {
        m_lastError = GetLastError();

        // Pipe might be broken, try to reconnect next time
        if (m_lastError == ERROR_BROKEN_PIPE || m_lastError == ERROR_NO_DATA) {
            Disconnect();
        }

        return FALSE;
    }

    // Flush to ensure data is sent
    FlushFileBuffers(m_hPipe);

    m_lastError = 0;
    return (cbWritten == cbSize);
}

BOOL NamedPipeClient::WaitForPipe()
{
    return WaitNamedPipeW(PIPE_NAME, m_timeoutMs);
}
