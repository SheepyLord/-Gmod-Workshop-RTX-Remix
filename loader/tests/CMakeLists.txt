add_executable(nl_tests
  test_main.cpp
  test_activate.cpp
  test_cmdline.cpp
  test_config.cpp
  test_content.cpp
  test_crc32.cpp
  test_dependencies.cpp
  test_deploy.cpp
  test_discovery.cpp
  test_evidence.cpp
  test_fs.cpp
  test_gma.cpp
  test_journal.cpp
  test_json.cpp
  test_legacy_detect.cpp
  test_legacy_migrate.cpp
  test_lzma.cpp
  test_m5.cpp
  test_manifest.cpp
  test_package.cpp
  test_paths.cpp
  test_planner.cpp
  test_reshade.cpp
  test_sha256.cpp
  test_startup.cpp
  test_status.cpp
  test_vdf.cpp
  test_version.cpp)
target_link_libraries(nl_tests PRIVATE nl_core nl_build_options)

add_executable(nl_cmdline_host cmdline_host.cpp)
target_link_libraries(nl_cmdline_host PRIVATE nl_core nl_build_options)
add_test(NAME nl_cmdline_roundtrip COMMAND nl_cmdline_host "original argument with spaces" "用户")

# Tests write scratch files below their working directory, which stays in the build tree. The
# exhaustive fault-injection cases take most of the time, so each is its own CTest and they run in
# parallel with the rest (the test presets set the job count).
add_test(NAME nl_tests COMMAND nl_tests "--skip=deploy faults:" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME nl_tests_faults_upgrade COMMAND nl_tests "deploy faults: an upgrade" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME nl_tests_faults_other COMMAND nl_tests "deploy faults: first deployments" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME nl_tests_faults_errors COMMAND nl_tests "deploy faults: a failure" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME nl_tests_faults_unsubscribe COMMAND nl_tests "deploy faults: an unsubscribe" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME nl_tests_faults_legacy COMMAND nl_tests "deploy faults: legacy migration" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
add_test(NAME nl_tests_faults_legacy_stock COMMAND nl_tests "deploy faults: legacy stock" WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")

# Test-only host for the kill tests: one deployer command that can end itself before any change.
add_executable(nl_fault_host fault_host.cpp)
target_link_libraries(nl_fault_host PRIVATE nl_core nl_build_options)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
add_test(NAME nl_deploy_faults
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/deploy_faults.py"
          --host "$<TARGET_FILE:nl_fault_host>"
          --gmapack "${PROJECT_SOURCE_DIR}/tools/gmapack/gmapack.py"
          --scratch "${CMAKE_CURRENT_BINARY_DIR}/scratch/deploy_faults")
