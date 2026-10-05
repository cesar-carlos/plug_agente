cmake_minimum_required(VERSION 3.15)
project(update_helper LANGUAGES CXX)

add_executable(plug_update_helper WIN32
  "main.cpp"
)
if(MSVC)
  set_property(TARGET plug_update_helper PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

if(COMMAND apply_standard_settings)
  apply_standard_settings(plug_update_helper)
else()
  target_compile_features(plug_update_helper PRIVATE cxx_std_17)
  target_compile_definitions(plug_update_helper PRIVATE UNICODE _UNICODE)
  target_compile_options(plug_update_helper PRIVATE /W4 /WX /EHsc /utf-8)
endif()
target_compile_definitions(plug_update_helper PRIVATE "NOMINMAX")
target_link_libraries(plug_update_helper PRIVATE "advapi32.lib" "shell32.lib" "wintrust.lib")

install(TARGETS plug_update_helper RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
