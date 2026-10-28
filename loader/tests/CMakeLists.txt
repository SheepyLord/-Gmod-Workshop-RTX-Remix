add_executable(nl_tests
  test_main.cpp
  test_crc32.cpp
  test_gma.cpp
  test_json.cpp
  test_lzma.cpp
  test_manifest.cpp
  test_package.cpp
  test_paths.cpp
  test_version.cpp)
target_link_libraries(nl_tests PRIVATE nl_core nl_build_options)

# Tests write scratch files below their working directory, which stays in the build tree.
add_test(NAME nl_tests COMMAND nl_tests WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
