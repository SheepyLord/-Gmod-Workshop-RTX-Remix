configure_file(include/nl/version.h.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include/nl/version.h" @ONLY)

add_library(nl_core STATIC
  src/activate.cpp
  src/cmdline.cpp
  src/config.cpp
  src/content.cpp
  src/crc32.cpp
  src/deploy.cpp
  src/discovery.cpp
  src/evidence.cpp
  src/fs.cpp
  src/gma.cpp
  src/gpu_diagnostics.cpp
  src/journal.cpp
  src/json.cpp
  src/legacy_detect.cpp
  src/legacy_migrate.cpp
  src/lzma.cpp
  src/manifest.cpp
  src/memory.cpp
  src/package.cpp
  src/patch.cpp
  src/paths.cpp
  src/performance.cpp
  src/planner.cpp
  src/reshade.cpp
  src/session.cpp
  src/sha256.cpp
  src/startup.cpp
  src/status.cpp
  src/utf8.cpp
  src/vdf.cpp
  src/version.cpp)
target_include_directories(nl_core PUBLIC
  include
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include")
target_link_libraries(nl_core PRIVATE nl_lzma nl_build_options)
