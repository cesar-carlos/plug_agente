cmake_minimum_required(VERSION 3.20)
project(PlugPortMon CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Windows-specific definitions
if(WIN32)
    add_definitions(-DUNICODE -D_UNICODE)
    add_definitions(-DWIN32_LEAN_AND_MEAN)
    add_definitions(-DPLUGPORTMON_EXPORTS)
endif()

# Source files
set(SOURCES
    src/dll_main.cpp
    src/port_monitor.cpp
    src/monitor2_impl.cpp
    src/named_pipe_client.cpp
)

set(HEADERS
    src/port_monitor.h
    src/named_pipe_client.h
    include/exports.h
)

# Create DLL
add_library(PlugPortMon SHARED ${SOURCES} ${HEADERS})

# Include directories
target_include_directories(PlugPortMon
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Windows libraries to link
target_link_libraries(PlugPortMon
    PUBLIC
    winspool.lib
    kernel32.lib
    advapi32.lib
)

# DLL export settings
set_target_properties(PlugPortMon PROPERTIES
    VERSION 1.0.0
    SOVERSION 1
    PREFIX ""
    OUTPUT_NAME "PlugPortMon"
)

# Set runtime output directory
set_target_properties(PlugPortMon PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)
