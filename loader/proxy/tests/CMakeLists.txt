add_executable(nl_backend_tests ../../tests/test_main.cpp test_backend.cpp)
target_include_directories(nl_backend_tests PRIVATE ../../tests)
target_link_libraries(nl_backend_tests PRIVATE nl_proxy_logic nl_core nl_build_options)
add_test(NAME nl_backend_tests COMMAND nl_backend_tests)

add_executable(nl_proxy_tests
  ../../tests/test_main.cpp test_activation.cpp test_proxy.cpp test_presentation.cpp test_presentation_hooks.cpp ../modules.cpp)
target_include_directories(nl_proxy_tests PRIVATE ../../tests)
target_link_libraries(nl_proxy_tests PRIVATE nl_proxy_logic nl_proxy_presentation nl_build_options)
target_compile_definitions(nl_proxy_tests PRIVATE
  NL_PROXY_DLL_PATH="$<TARGET_FILE:nl_winmm>"
  NL_PROXY_HOST_PATH="$<TARGET_FILE:nl_proxy_host>"
  NL_PROXY_SCRATCH_ROOT="${CMAKE_CURRENT_BINARY_DIR}/scratch")

# The SDK import library gives this fixture a real static WINMM.dll import.
add_executable(nl_proxy_host host.cpp activation_probe.cpp session_probe.cpp)
target_link_libraries(nl_proxy_host PRIVATE nl_build_options nl_core winmm)
add_dependencies(nl_proxy_tests nl_winmm nl_proxy_host)
add_test(NAME nl_proxy_tests COMMAND nl_proxy_tests)
set_tests_properties(nl_proxy_tests PROPERTIES TIMEOUT 120)
add_test(NAME nl_proxy_generated_exports
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/../generate_exports.py" --check)
find_program(NL_POWERSHELL NAMES pwsh powershell REQUIRED)
add_test(NAME nl_proxy_installer
  COMMAND "${NL_POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/install_tests.ps1"
    -Repo "${PROJECT_SOURCE_DIR}" -Config "$<CONFIG>")
set_tests_properties(nl_proxy_installer PROPERTIES TIMEOUT 60)
add_test(NAME nl_proxy_kernel32_imports
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/check_imports.py" "$<TARGET_FILE:nl_winmm>")
add_test(NAME nl_telemetry_integration
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/telemetry_integration.py"
    --host "$<TARGET_FILE:nl_proxy_host>" --proxy "$<TARGET_FILE:nl_winmm>" --nlctl "$<TARGET_FILE:nlctl>"
    --scratch "${PROJECT_SOURCE_DIR}/out/tmp/telemetry-$<CONFIG>")
set_tests_properties(nl_telemetry_integration PROPERTIES TIMEOUT 90)

add_library(nl_m4_static SHARED fixture_static.cpp)
add_library(nl_m4_delay SHARED fixture_delay.cpp)
add_library(nl_m4_runtime SHARED fixture_runtime.cpp)
foreach(target IN ITEMS nl_m4_static nl_m4_delay nl_m4_runtime)
  target_link_libraries(${target} PRIVATE nl_build_options)
  set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/runtime")
endforeach()
set_target_properties(nl_m4_runtime PROPERTIES OUTPUT_NAME d3d9)
target_link_libraries(nl_m4_runtime PRIVATE nl_m4_static nl_m4_delay delayimp)
target_link_options(nl_m4_runtime PRIVATE "/DELAYLOAD:nl_m4_delay.dll")
add_test(NAME nl_activation_integration
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/activation_integration.py"
    --repo "${PROJECT_SOURCE_DIR}" --host "$<TARGET_FILE:nl_proxy_host>" --proxy "$<TARGET_FILE:nl_winmm>"
    --runtime "$<TARGET_FILE_DIR:nl_m4_runtime>" --nlctl "$<TARGET_FILE:nlctl>"
    --scratch "${PROJECT_SOURCE_DIR}/out/tmp/m4-activation-$<CONFIG>" --config "$<CONFIG>")
set_tests_properties(nl_activation_integration PROPERTIES TIMEOUT 240)

# M5: a fake engine.dll whose marker a patch set rewrites, a stdshader_dx6.dll to override, and a
# filesystem_stdio.dll that lists folders the way GMod mounts add-ons (ADR 0013).
add_library(nl_m5_engine SHARED fixture_engine.cpp)
add_library(nl_m5_shader SHARED fixture_shader.cpp)
add_library(nl_m5_filesystem SHARED fixture_filesystem.cpp)
foreach(target IN ITEMS nl_m5_engine nl_m5_shader nl_m5_filesystem)
  target_link_libraries(${target} PRIVATE nl_build_options)
  set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/m5")
endforeach()
set_target_properties(nl_m5_engine PROPERTIES OUTPUT_NAME engine)
set_target_properties(nl_m5_shader PROPERTIES OUTPUT_NAME stdshader_dx6)
set_target_properties(nl_m5_filesystem PROPERTIES OUTPUT_NAME filesystem_stdio)
target_compile_definitions(nl_proxy_tests PRIVATE NL_PRESENTATION_FIXTURE_PATH="$<TARGET_FILE:nl_m5_filesystem>")
add_dependencies(nl_proxy_tests nl_m5_filesystem)
# ADR 0024: a lua_shared.dll that loads binary modules as GMod's does, and a module whose static import
# (its runtime) lives only in garrysmod\lua\bin.
add_library(nl_dep_runtime SHARED fixture_dep_runtime.cpp)
add_library(nl_dep_module SHARED fixture_dep_module.cpp)
add_library(nl_dep_luashared SHARED fixture_luashared.cpp)
foreach(target IN ITEMS nl_dep_runtime nl_dep_module nl_dep_luashared)
  target_link_libraries(${target} PRIVATE nl_build_options)
  set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/m5")
endforeach()
set_target_properties(nl_dep_runtime PROPERTIES OUTPUT_NAME nl_dep_runtime_win64)
set_target_properties(nl_dep_module PROPERTIES OUTPUT_NAME gmcl_nl_dep_win64)
set_target_properties(nl_dep_luashared PROPERTIES OUTPUT_NAME lua_shared)
target_link_libraries(nl_dep_module PRIVATE nl_dep_runtime)
add_test(NAME nl_session_integration
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/session_integration.py"
    --repo "${PROJECT_SOURCE_DIR}" --host "$<TARGET_FILE:nl_proxy_host>" --proxy "$<TARGET_FILE:nl_winmm>"
    --runtime "$<TARGET_FILE_DIR:nl_m4_runtime>" --fixtures "$<TARGET_FILE_DIR:nl_m5_engine>"
    --scratch "${PROJECT_SOURCE_DIR}/out/tmp/m5-session-$<CONFIG>" --config "$<CONFIG>")
set_tests_properties(nl_session_integration PROPERTIES TIMEOUT 240)
