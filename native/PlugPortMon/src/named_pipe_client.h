#pragma once

#include <windows.h>

// Named Pipe configuration
constexpr wchar_t PIPE_NAME[] = L"\\\\.\\pipe\\PlugAgentPipe";
constexpr DWORD PIPE_BUFFER_SIZE = 4096;
constexpr DWORD PIPE_TIMEOUT_MS = 5000;

/**
 * NamedPipeClient - Handles communication with the Flutter app via Named Pipe
 * The DLL acts as a client, connecting to the pipe server created by Flutter
 */
class NamedPipeClient {
public:
    NamedPipeClient();
    ~NamedPipeClient();

    // Connect to the named pipe server
    BOOL Connect();

    // Disconnect from the pipe
    void Disconnect();

    // Write data to the pipe
    BOOL Write(const BYTE* pData, DWORD cbSize);

    // Check if connected
    BOOL IsConnected() const { return m_hPipe != INVALID_HANDLE_VALUE; }

    // Get last error
    DWORD GetLastErrorCode() const { return m_lastError; }

private:
    HANDLE m_hPipe;
    DWORD m_timeoutMs;
    DWORD m_lastError;

    // Try to wait for pipe to become available
    BOOL WaitForPipe();
};
