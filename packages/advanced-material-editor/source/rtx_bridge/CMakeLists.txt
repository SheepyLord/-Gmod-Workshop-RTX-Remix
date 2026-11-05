cmake_minimum_required(VERSION 3.20)
project(advmat_rtx_bridge VERSION 1.0.0 LANGUAGES CXX)

option(ADVMAT_RTX_BUILD_TESTS "Build the pure writer contract tests" ON)
option(ADVMAT_RTX_BUILD_GMOD_MODULE "Build an experimental standalone gmcl module" OFF)
set(GARRYSMOD_COMMON_INCLUDE_DIR "" CACHE PATH
    "Path containing GarrysMod/Lua/Interface.h (garrysmod_common/include)")

function(advmat_rtx_strict_compile target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /WX /permissive- /EHsc)
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
endfunction()

add_library(advmat_rtx_writer STATIC
    src/bridge.cpp
    src/filesystem_utils.cpp
    src/texture_ingest.cpp
    src/usda_writer.cpp)
target_include_directories(advmat_rtx_writer PUBLIC include PRIVATE src)
target_compile_features(advmat_rtx_writer PUBLIC cxx_std_17)
set_target_properties(advmat_rtx_writer PROPERTIES POSITION_INDEPENDENT_CODE ON)

advmat_rtx_strict_compile(advmat_rtx_writer)

if(WIN32)
    target_link_libraries(advmat_rtx_writer PRIVATE windowscodecs ole32)
endif()

if(ADVMAT_RTX_BUILD_GMOD_MODULE)
    if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
        message(FATAL_ERROR "RTX Remix standalone module builds require 64-bit Windows")
    endif()
    if(NOT EXISTS "${GARRYSMOD_COMMON_INCLUDE_DIR}/GarrysMod/Lua/Interface.h")
        message(FATAL_ERROR "Set GARRYSMOD_COMMON_INCLUDE_DIR to garrysmod_common/include")
    endif()
    add_library(advmat_rtx_bridge_gmod MODULE
        src/lua_bindings.cpp
        src/standalone_module.cpp)
    target_include_directories(advmat_rtx_bridge_gmod PRIVATE
        include "${GARRYSMOD_COMMON_INCLUDE_DIR}")
    target_compile_features(advmat_rtx_bridge_gmod PRIVATE cxx_std_17)
    target_link_libraries(advmat_rtx_bridge_gmod PRIVATE advmat_rtx_writer)
    set_target_properties(advmat_rtx_bridge_gmod PROPERTIES
        PREFIX ""
        OUTPUT_NAME "gmcl_advmat_rtx_bridge_win64")
    advmat_rtx_strict_compile(advmat_rtx_bridge_gmod)
endif()

if(ADVMAT_RTX_BUILD_TESTS)
    enable_testing()
    add_executable(advmat_rtx_writer_tests tests/writer_tests.cpp)
    target_link_libraries(advmat_rtx_writer_tests PRIVATE advmat_rtx_writer)
    target_compile_features(advmat_rtx_writer_tests PRIVATE cxx_std_17)
    advmat_rtx_strict_compile(advmat_rtx_writer_tests)
    add_test(NAME advmat_rtx_writer_tests COMMAND advmat_rtx_writer_tests)
endif()

if(ADVMAT_RTX_BUILD_TESTS AND ADVMAT_RTX_BUILD_GMOD_MODULE)
    # The Lua boundary (src/lua_bindings.cpp) against an in-memory ILuaBase:
    # string lengths checked before copying, no C++ exception left uncaught.
    add_executable(advmat_rtx_lua_tests tests/lua_binding_tests.cpp)
    target_include_directories(advmat_rtx_lua_tests PRIVATE
        include "${GARRYSMOD_COMMON_INCLUDE_DIR}")
    target_link_libraries(advmat_rtx_lua_tests PRIVATE advmat_rtx_writer)
    target_compile_features(advmat_rtx_lua_tests PRIVATE cxx_std_17)
    advmat_rtx_strict_compile(advmat_rtx_lua_tests)
    add_test(NAME advmat_rtx_lua_tests COMMAND advmat_rtx_lua_tests)
endif()
