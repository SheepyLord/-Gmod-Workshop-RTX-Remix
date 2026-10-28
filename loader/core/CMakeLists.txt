configure_file(include/nl/version.h.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include/nl/version.h" @ONLY)

add_library(nl_core STATIC
  src/config.cpp
  src/crc32.cpp
  src/discovery.cpp
  src/gma.cpp
  src/json.cpp
  src/lzma.cpp
  src/manifest.cpp
  src/package.cpp
  src/paths.cpp
  src/planner.cpp
  src/utf8.cpp
  src/vdf.cpp
  src/version.cpp)
target_include_directories(nl_core PUBLIC
  include
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include")
target_link_libraries(nl_core PRIVATE nl_lzma nl_build_options)
