add_executable(nl_tests
  test_main.cpp
  test_version.cpp)
target_link_libraries(nl_tests PRIVATE nl_core nl_build_options)

add_test(NAME nl_tests COMMAND nl_tests)
