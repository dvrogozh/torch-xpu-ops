# Copyright 2020-2026 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0

# SYCL compiler and runtime setup
if(NOT SYCLTOOLKIT_FOUND)
  # Avoid package conflict introduced in PyTorch cmake
  # find_package(SYCLToolkit REQUIRED)
  include(${TORCH_XPU_OPS_ROOT}/cmake/Modules/FindSYCLToolkit.cmake)
  if(NOT SYCLTOOLKIT_FOUND)
    message("Can NOT find SYCL compiler tool kit!")
    return()
  endif()
endif()

# SYCL kernels are compiled with the native CMake SYCL language. It is
# experimental in CMake 4.5 and gated by CMAKE_EXPERIMENTAL_SYCL, see
# Help/dev/experimental.rst in the CMake sources. The gate UUID is specific to
# the CMake version which introduced it and may change in future versions.
if(CMAKE_VERSION VERSION_LESS 4.5)
  message(FATAL_ERROR
    "torch-xpu-ops requires CMake >= 4.5 for native SYCL language support, "
    "found ${CMAKE_VERSION}.")
endif()

# PyTorch enables SYCL from its top-level directory, so that targets linking
# torch-xpu-ops libraries see the SYCL toolchain. Enable it here for
# standalone builds.
get_property(_torch_xpu_ops_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
if(NOT "SYCL" IN_LIST _torch_xpu_ops_languages)
  set(CMAKE_EXPERIMENTAL_SYCL "c0d1fb10-2ece-420e-9d29-7d7f2b300f25")
  if(NOT CMAKE_SYCL_COMPILER AND NOT DEFINED ENV{SYCLCXX})
    # SYCL_COMPILER is the C driver (icx) for oneAPI. Use the C++ driver
    # from the same installation on Linux. On Windows icx is the MSVC-like
    # driver which handles C++ as well.
    get_filename_component(_sycl_compiler_name "${SYCL_COMPILER}" NAME_WE)
    if(NOT WIN32 AND _sycl_compiler_name STREQUAL "icx")
      get_filename_component(_sycl_compiler_dir "${SYCL_COMPILER}" DIRECTORY)
      set(CMAKE_SYCL_COMPILER "${_sycl_compiler_dir}/icpx")
    else()
      set(CMAKE_SYCL_COMPILER "${SYCL_COMPILER}")
    endif()
  endif()
  enable_language(SYCL)
endif()
unset(_torch_xpu_ops_languages)

if(NOT CMAKE_SYCL_COMPILER_ID MATCHES "^(IntelLLVM|DPClang)$")
  message(FATAL_ERROR
    "torch-xpu-ops requires the DPC++ SYCL compiler (icpx/icx or dpclang++), "
    "found ${CMAKE_SYCL_COMPILER_ID} (${CMAKE_SYCL_COMPILER}).")
endif()

# CMake workaround: the default device link rules append <LINK_LIBRARIES>
# (including the SYCL runtime libraries CMake adds implicitly) to the
# "icpx -fsycl-link" command. icpx rejects any library input in this mode with
# "cannot specify -o when generating multiple output files". Device code of
# torch-xpu-ops comes only from the target's own objects, so drop the libraries.
string(JOIN " " _sycl_device_link_pic_options ${CMAKE_SYCL_COMPILE_OPTIONS_PIC})
string(JOIN " " _sycl_device_link_options ${CMAKE_SYCL_DEVICE_LINK_OPTIONS})
set(CMAKE_SYCL_DEVICE_LINK_LIBRARY
  "<CMAKE_SYCL_COMPILER> <LANGUAGE_COMPILE_FLAGS> <LINK_FLAGS> ${_sycl_device_link_pic_options} ${_sycl_device_link_options} -o <TARGET> <OBJECTS>")
set(CMAKE_SYCL_DEVICE_LINK_EXECUTABLE "${CMAKE_SYCL_DEVICE_LINK_LIBRARY}")
unset(_sycl_device_link_pic_options)
unset(_sycl_device_link_options)

# ccache versions before 4.11 do not support DPC++ (icx) compiler. Additionally,
# versions before 4.12.1 do not correctly pass -Xarch_host flags to LLVM compilers
# family in general: they can strip -Xarch_host -fPIC, producing objects without
# -fPIC that fail the PIE link. ccache 4.12.1 includes the fix for that, see:
#
# * https://github.com/ccache/ccache/issues/1632
#
# The launcher applies to both SYCL object compilation and SYCL device link,
# so disable it for SYCL entirely if ccache is too old.
if(CMAKE_SYCL_COMPILER_LAUNCHER)
  list(GET CMAKE_SYCL_COMPILER_LAUNCHER 0 _sycl_launcher)
  get_filename_component(_sycl_launcher_name "${_sycl_launcher}" NAME)
  if(_sycl_launcher_name MATCHES "^[Cc][Cc]ache")
    execute_process(
      COMMAND ${_sycl_launcher} --version
      OUTPUT_VARIABLE _sycl_launcher_version
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE
      TIMEOUT 5
    )
    if(_sycl_launcher_version MATCHES "ccache version ([0-9]+\\.[0-9]+(\\.[0-9]+)?)")
      set(_sycl_ccache_version "${CMAKE_MATCH_1}")
      if(_sycl_ccache_version VERSION_GREATER_EQUAL "4.12.1")
        message(STATUS "Found compatible ccache ${_sycl_ccache_version} for SYCL compilation")
      else()
        message(WARNING
          "ccache launcher '${CMAKE_SYCL_COMPILER_LAUNCHER}' has version "
          "'${_sycl_ccache_version}' which is older than 4.12.1; "
          "disabling it for SYCL compilation. Upgrade to ccache >= 4.12.1.")
        # Shadows the cache entry for torch-xpu-ops targets only.
        set(CMAKE_SYCL_COMPILER_LAUNCHER "")
      endif()
    else()
      message(WARNING "Found ccache but could not parse its version string.")
    endif()
  endif()
  unset(_sycl_launcher)
  unset(_sycl_launcher_name)
endif()

# SYCL sources use only SYCL flags (CMAKE_SYCL_FLAGS) and the SYCL standard
# (SYCL_CXX_STANDARD). The default APPEND mode would also pass CMAKE_CXX_FLAGS,
# which carry host compiler (GCC) specific options unknown to the SYCL
# compiler. CMAKE_SYCL_FLAGS is composed from CMAKE_CXX_FLAGS in BuildFlags.cmake.
set(CMAKE_SYCL_EXTENSION_MODE REPLACE)
