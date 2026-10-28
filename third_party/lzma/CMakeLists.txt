# LZMA SDK decoder (public domain, see README.md), compiled as C. Third-party code keeps its own
# warning level and is not built with /WX, so a newer compiler warning cannot break the build.
add_library(nl_lzma STATIC LzmaDec.c)
target_include_directories(nl_lzma PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(nl_lzma PRIVATE /W3)
