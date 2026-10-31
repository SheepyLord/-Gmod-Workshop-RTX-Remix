add_executable(nl_render_guard_tests ../../tests/test_main.cpp test_early.cpp)

target_include_directories(nl_render_guard_tests PRIVATE ../../tests)

target_link_libraries(nl_render_guard_tests PRIVATE nl_render_guard nl_build_options)
add_test(NAME nl_render_guard_tests COMMAND nl_render_guard_tests)
set_tests_properties(nl_render_guard_tests PROPERTIES TIMEOUT 120)
