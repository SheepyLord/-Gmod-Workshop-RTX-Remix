# SPDX-License-Identifier: GPL-2.0-only
add_executable(rtx_oversized_skinning_policy oversized_skinning_test.cpp)

# The test uses assert: Release's default NDEBUG must not turn its checks into no-ops.
target_compile_options(rtx_oversized_skinning_policy PRIVATE /UNDEBUG)
# Interface flags only; do not link this GPL test to any MIT loader implementation.
target_link_libraries(rtx_oversized_skinning_policy PRIVATE nl_build_options)

add_test(NAME rtx_oversized_skinning_policy COMMAND rtx_oversized_skinning_policy)
set_tests_properties(rtx_oversized_skinning_policy PROPERTIES TIMEOUT 30)
