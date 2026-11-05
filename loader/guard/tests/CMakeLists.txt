add_executable(nl_render_guard_tests ../../tests/test_main.cpp test_early.cpp)

target_include_directories(nl_render_guard_tests PRIVATE ../../tests)

target_link_libraries(nl_render_guard_tests PRIVATE nl_render_guard nl_build_options)
add_test(NAME nl_render_guard_tests COMMAND nl_render_guard_tests)
set_tests_properties(nl_render_guard_tests PROPERTIES TIMEOUT 120)

# R19 (proxy F-02): the companion guard's installation decision, run under LuaJIT on the production
# file. Like tools/tests/test_render_guard.py, it needs LuaJIT; without it the test is not registered.
find_program(NL_LUAJIT NAMES luajit PATHS "$ENV{LOCALAPPDATA}/Programs/LuaJIT/bin")
if(NL_LUAJIT)
  add_test(NAME nl_guard_session_marker
    COMMAND "${NL_LUAJIT}" "${CMAKE_CURRENT_SOURCE_DIR}/guard_session_marker.lua"
      "${PROJECT_SOURCE_DIR}/companion/nativeloader/lua/autorun/_nativeloader_guard.lua")
  set_tests_properties(nl_guard_session_marker PROPERTIES TIMEOUT 60)
else()
  message(STATUS "LuaJIT not found: nl_guard_session_marker is not registered")
endif()
