configure_file(include/nl/version.h.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include/nl/version.h" @ONLY)

add_library(nl_core STATIC
  src/activate.cpp
  src/cmdline.cpp
  src/config.cpp
  src/crc32.cpp
  src/deploy.cpp
  src/discovery.cpp
  src/fs.cpp
  src/gma.cpp
  src/journal.cpp
  src/json.cpp
  src/lzma.cpp
  src/manifest.cpp
  src/package.cpp
  src/paths.cpp
  src/planner.cpp
  src/sha256.cpp
  src/utf8.cpp
  src/vdf.cpp
  src/version.cpp)
target_include_directories(nl_core PUBLIC
  include
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include")
target_link_libraries(nl_core PRIVATE nl_lzma nl_build_options)
