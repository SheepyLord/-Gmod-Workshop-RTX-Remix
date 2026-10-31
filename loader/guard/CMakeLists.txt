add_library(nl_render_guard STATIC early.cpp)
target_include_directories(nl_render_guard PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nl_render_guard PUBLIC nl_client_catalog PRIVATE nl_build_options)
add_subdirectory(tests)
