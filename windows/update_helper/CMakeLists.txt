cmake_minimum_required(VERSION 3.14)
project(update_helper LANGUAGES CXX)

add_executable(plug_update_helper WIN32
  "main.cpp"
)

apply_standard_settings(plug_update_helper)
target_compile_definitions(plug_update_helper PRIVATE "NOMINMAX")
target_link_libraries(plug_update_helper PRIVATE "advapi32.lib" "shell32.lib" "wintrust.lib")

install(TARGETS plug_update_helper RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
