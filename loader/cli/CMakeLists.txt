find_package(Python3 REQUIRED COMPONENTS Interpreter)

add_executable(nlctl nlctl.cpp)
target_link_libraries(nlctl PRIVATE nl_core nl_build_options)

# The Python reference reader (tools/gmapack) and nlctl must agree on every archive it writes.
add_test(NAME nlctl_crosscheck_gmapack
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/tests/crosscheck_gmapack.py"
          --nlctl "$<TARGET_FILE:nlctl>"
          --gmapack "${PROJECT_SOURCE_DIR}/tools/gmapack/gmapack.py"
          --scratch "${CMAKE_CURRENT_BINARY_DIR}/scratch/crosscheck")

# The whole M2 chain on gmapack-built packages: config, discovery, package loading, plan.
add_test(NAME nlctl_e2e_plan
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/tests/e2e_plan.py"
          --nlctl "$<TARGET_FILE:nlctl>"
          --gmapack "${PROJECT_SOURCE_DIR}/tools/gmapack/gmapack.py"
          --scratch "${CMAKE_CURRENT_BINARY_DIR}/scratch/e2e_plan")

# M3: apply, status, rollback and uninstall end to end, including the refusals.
add_test(NAME nlctl_e2e_deploy
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/tests/e2e_deploy.py"
          --nlctl "$<TARGET_FILE:nlctl>"
          --gmapack "${PROJECT_SOURCE_DIR}/tools/gmapack/gmapack.py"
          --scratch "${CMAKE_CURRENT_BINARY_DIR}/scratch/e2e_deploy")

# tools\uninstall-loader.ps1 with the bootstrap and nlctl of this build, in synthetic game folders.
find_program(NL_POWERSHELL NAMES pwsh powershell REQUIRED)
add_test(NAME nlctl_uninstall_loader
  COMMAND "${NL_POWERSHELL}" -NoProfile -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/uninstall_tests.ps1"
          -Repo "${PROJECT_SOURCE_DIR}" -Config "$<CONFIG>" -Python "${Python3_EXECUTABLE}"
          -Scratch "${CMAKE_CURRENT_BINARY_DIR}/scratch/uninstall_loader")
set_tests_properties(nlctl_uninstall_loader PROPERTIES TIMEOUT 120)
