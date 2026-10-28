# MASM emits register-preserving leaf jumps; RC supplies the install identity.
enable_language(ASM_MASM)
enable_language(RC)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

add_library(nl_proxy_logic STATIC activation.cpp)
target_include_directories(nl_proxy_logic PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nl_proxy_logic PRIVATE nl_build_options)

configure_file(version.rc.in "${CMAKE_CURRENT_BINARY_DIR}/version.rc" @ONLY)
add_library(nl_winmm SHARED bootstrap.cpp startup.cpp runtime.cpp modules.cpp generated/thunks.asm
  generated/winmm.def "${CMAKE_CURRENT_BINARY_DIR}/version.rc")
set_target_properties(nl_winmm PROPERTIES OUTPUT_NAME winmm)
target_link_libraries(nl_winmm PRIVATE nl_proxy_logic nl_core nl_build_options)
# C++ switches from nl_build_options do not apply to ml64.exe or rc.exe.
set_source_files_properties(generated/thunks.asm PROPERTIES COMPILE_OPTIONS "/nologo")

add_custom_target(nl_check_winmm_exports
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/generate_exports.py" --check
  VERBATIM)
add_dependencies(nl_winmm nl_check_winmm_exports)

add_subdirectory(tests)
