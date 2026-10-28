add_executable(nl_proxy_tests
  ../../tests/test_main.cpp test_activation.cpp test_proxy.cpp)
target_include_directories(nl_proxy_tests PRIVATE ../../tests)
target_link_libraries(nl_proxy_tests PRIVATE nl_proxy_logic nl_build_options)
target_compile_definitions(nl_proxy_tests PRIVATE
  NL_PROXY_DLL_PATH="$<TARGET_FILE:nl_winmm>"
  NL_PROXY_HOST_PATH="$<TARGET_FILE:nl_proxy_host>"
  NL_PROXY_SCRATCH_ROOT="${CMAKE_CURRENT_BINARY_DIR}/scratch")

# The SDK import library gives this fixture a real static WINMM.dll import.
add_executable(nl_proxy_host host.cpp activation_probe.cpp)
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
