#include <windows.h>

// DLL entry point
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call,
                      LPVOID lpReserved)
{
    UNREFERENCED_PARAMETER(lpReserved);

    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH:
        // DLL is being loaded into a process's address space
        // Disable thread library calls to improve performance
        DisableThreadLibraryCalls(hModule);

        // Initialize any resources here if needed
        break;

    case DLL_THREAD_ATTACH:
        // A new thread is being created in the process
        break;

    case DLL_THREAD_DETACH:
        // A thread is exiting cleanly
        break;

    case DLL_PROCESS_DETACH:
        // DLL is being unloaded from a process's address space
        // Cleanup any resources here if needed
        break;
    }

    return TRUE;
}
