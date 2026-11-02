# Configure upstream in its own directory so its compiler flags stay scoped there.
set(OVERRIDE_CXX_FLAGS OFF CACHE BOOL "" FORCE)
set(INTERPROCEDURAL_OPTIMIZATION OFF CACHE BOOL "" FORCE)
set(FLOATING_POINT_EXCEPTIONS_ENABLED OFF CACHE BOOL "" FORCE)
set(CPP_EXCEPTIONS_ENABLED ON CACHE BOOL "" FORCE)
set(ENABLE_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(DEBUG_RENDERER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(PROFILER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
foreach(feature SSE4_1 SSE4_2 AVX AVX2 AVX512 LZCNT TZCNT F16C FMADD)
  set(USE_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
add_subdirectory("${CMAKE_SOURCE_DIR}/third_party/jolt/Build" "${CMAKE_CURRENT_BINARY_DIR}/jolt")
set_target_properties(Jolt PROPERTIES CXX_STANDARD 20)
# Upstream adds /Zi; /Z7 last avoids a shared compiler PDB under Ninja.
target_compile_options(Jolt PRIVATE /Z7 /W3)

add_library(nl_glass STATIC bsp.cpp fracture.cpp world.cpp)
target_include_directories(nl_glass PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(nl_glass SYSTEM PUBLIC "${CMAKE_SOURCE_DIR}/third_party/jolt")
target_link_libraries(nl_glass PUBLIC Jolt PRIVATE nl_lzma nl_build_options)

add_library(nl_glass_client SHARED module.cpp)
target_include_directories(nl_glass_client SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party/gmod/include")
target_link_libraries(nl_glass_client PRIVATE nl_glass nl_build_options)
set_target_properties(nl_glass_client PROPERTIES OUTPUT_NAME gmcl_nlglass_win64 PREFIX "")

add_executable(nl_glass_tests ../../loader/tests/test_main.cpp tests/test_glass.cpp tests/test_interaction.cpp tests/test_r9.cpp tests/test_binding.cpp module.cpp)
target_include_directories(nl_glass_tests PRIVATE ../../loader/tests)
target_include_directories(nl_glass_tests SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party/gmod/include")
target_link_libraries(nl_glass_tests PRIVATE nl_glass nl_build_options)
add_test(NAME nl_glass_tests COMMAND nl_glass_tests)
set_tests_properties(nl_glass_tests PROPERTIES TIMEOUT 180)

# Deliberate read-only probe; never runs against an installed map as part of CTest.
add_executable(nl_glass_import_probe tests/import_probe.cpp)
target_link_libraries(nl_glass_import_probe PRIVATE nl_glass nl_build_options)

# Python feeds real Lua snapshots into this offline generated-pile regression.
add_executable(nl_glass_scene_replay tests/scene_replay.cpp)
target_link_libraries(nl_glass_scene_replay PRIVATE nl_glass nl_build_options)
