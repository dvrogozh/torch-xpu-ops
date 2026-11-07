# Copyright 2020-2026 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0

set(TEST_SYCL_ROOT ${TORCH_XPU_OPS_ROOT}/test/sycl)
set(TEST_SYCL_SYCL_SRCS ${TEST_SYCL_ROOT}/simple_kernel.cpp)
set(TEST_SYCL_CXX_SRCS ${TEST_SYCL_ROOT}/main.cpp)

# test building executable
add_executable(
  test_sycl_build_standalone
  ${TEST_SYCL_CXX_SRCS})
torch_xpu_ops_add_sycl_sources(test_sycl_build_standalone ${TEST_SYCL_SYCL_SRCS})
target_link_libraries(test_sycl_build_standalone ${SYCL_LIBRARY})

if(INSTALL_TEST)
  install(TARGETS test_sycl_build_standalone DESTINATION bin)
endif()

# test building archive static library
add_library(sycl_simple_kernel_test STATIC)
torch_xpu_ops_add_sycl_sources(sycl_simple_kernel_test ${TEST_SYCL_SYCL_SRCS})

# The archive carries its linked device code (SYCL_RESOLVE_DEVICE_SYMBOLS), so
# the host C++ linker links it. Without LINKER_LANGUAGE CXX CMake would select
# the SYCL driver, which links the device code again.
add_executable(
  test_sycl_build_archive
  ${TEST_SYCL_CXX_SRCS})
target_link_libraries(test_sycl_build_archive
  $<LINK_LIBRARY:WHOLE_ARCHIVE,sycl_simple_kernel_test>
  ${SYCL_LIBRARY})
set_target_properties(test_sycl_build_archive PROPERTIES LINKER_LANGUAGE CXX)

if(INSTALL_TEST)
  install(TARGETS test_sycl_build_archive DESTINATION bin)
endif()
