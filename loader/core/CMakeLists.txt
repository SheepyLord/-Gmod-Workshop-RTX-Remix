configure_file(include/nl/version.h.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include/nl/version.h" @ONLY)

add_library(nl_core STATIC
  src/version.cpp)
target_include_directories(nl_core PUBLIC
  include
  "${CMAKE_CURRENT_BINARY_DIR}/generated/include")
target_link_libraries(nl_core PRIVATE nl_build_options)
