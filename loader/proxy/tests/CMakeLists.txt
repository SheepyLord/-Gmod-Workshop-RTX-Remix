add_executable(nl_proxy_tests
  ../../tests/test_main.cpp test_activation.cpp test_proxy.cpp)
target_include_directories(nl_proxy_tests PRIVATE ../../tests)
target_link_libraries(nl_proxy_tests PRIVATE nl_proxy_logic nl_build_options)
target_compile_definitions(nl_proxy_tests PRIVATE
  NL_PROXY_DLL_PATH="$<TARGET_FILE:nl_winmm>"
  NL_PROXY_HOST_PATH="$<TARGET_FILE:nl_proxy_host>"
  NL_PROXY_SCRATCH_ROOT="${CMAKE_CURRENT_BINARY_DIR}/scratch")

# The SDK import library gives this fixture a real static WINMM.dll import.
add_executable(nl_proxy_host host.cpp)
target_link_libraries(nl_proxy_host PRIVATE nl_build_options winmm)
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
