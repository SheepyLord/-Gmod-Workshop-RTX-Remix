cmake_minimum_required(VERSION 3.25)

project(native_loader
  VERSION 0.7.0
  DESCRIPTION "Bootstrap that deploys and loads native packages (RTX Remix) for 64-bit Garry's Mod"
  LANGUAGES C CXX)

if(NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "native_loader targets 64-bit Garry's Mod: build with MSVC x64 (tools/build.ps1).")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Static CRT: the bootstrap loads into gmod.exe before anything else and must not
# depend on the VC++ redistributable being installed.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
# Debug info lives in the objects (/Z7), so parallel Ninja jobs never share a PDB;
# the linker still writes one PDB per binary.
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT Embedded)

# Compile and link settings every target in this repo links against.
add_library(nl_build_options INTERFACE)
target_compile_options(nl_build_options INTERFACE
  # M1 adds MASM/RC: C and C++ diagnostics are not assembler/resource switches.
  "$<$<COMPILE_LANGUAGE:C,CXX>:/W4;/WX;/permissive-;/utf-8;/Zc:__cplusplus;/Zc:preprocessor>")
target_compile_definitions(nl_build_options INTERFACE
  WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _WIN32_WINNT=0x0A00)
target_link_options(nl_build_options INTERFACE
  /DEBUG
  $<$<NOT:$<CONFIG:Debug>>:/OPT:REF>
  $<$<NOT:$<CONFIG:Debug>>:/OPT:ICF>)

enable_testing()
add_subdirectory(third_party/lzma)
add_subdirectory(loader)
