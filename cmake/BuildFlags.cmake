# Copyright 2020-2026 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0

# Setup building flags for SYCL device and host codes.
#
# SYCL sources are compiled with the native CMake SYCL language (see SYCL.cmake).
# set_build_flags() composes the flags, torch_xpu_ops_sycl_target_flags()
# applies them to a target compiling SYCL sources.

include(CheckCompilerFlag)

# Check that the SYCL compiler accepts FLAG (a list) when building a SYCL
# program. The result is cached in VARIABLE_NAME.
function(CHECK_SYCL_FLAG FLAG VARIABLE_NAME)
  check_compiler_flag(SYCL "${FLAG}" ${VARIABLE_NAME})
endfunction()

macro(set_build_flags)
 set(_TORCH_XPU_OPS_SUPPORTED_COMPILERS "GNU" "Clang" "MSVC")
  if(NOT CMAKE_CXX_COMPILER_ID IN_LIST _TORCH_XPU_OPS_SUPPORTED_COMPILERS)
    message(WARNING "Not compiling with XPU. Currently only support GCC/Clang compiler on Linux and MSVC compiler on Windows as CXX compiler.")
    return()
  endif()
  # Host C++ flags, applied to all torch-xpu-ops sources (TORCH_XPU_OPS_FLAGS).
  set(SYCL_HOST_FLAGS)
  # CMAKE_CXX_FLAGS entries omitted from CMAKE_SYCL_FLAGS.
  set(SYCL_HOST_FLAGS_EXCLUDED_FROM_SYCL)
  # Warning flags for SYCL compilation only.
  set(SYCL_HOST_FLAGS_ONLY_FOR_SYCL)
  set(SYCL_DEVICE_COMPILE_DEFINITIONS)
  # Per-config host-only flags for SYCL compilation (wrapped with -Xarch_host).
  set(SYCL_HOST_PER_CONFIG_FLAGS)
  # -fsycl is added by CMake. -std= comes from SYCL_CXX_STANDARD and
  # -fsycl-targets= from SYCL_DEVICE_TARGETS.
  set(SYCL_COMPILE_FLAGS)
  set(SYCL_DEVICE_TARGETS)
  set(SYCL_DEVICE_LINK_FLAGS)
  set(SYCL_OFFLINE_COMPILER_AOT_OPTIONS)
  set(SYCL_OFFLINE_COMPILER_CG_OPTIONS)
  set(SYCL_OFFLINE_COMPILER_FLAGS)

  # Definitions that must reach the SYCL compiler only, not the host C++
  # compilation of non-SYCL sources.
  if(NOT DEFINED SYCL_COMPILER_VERSION OR NOT DEFINED USE_XPU)
    message(FATAL_ERROR "SYCL_COMPILER_VERSION and USE_XPU must be defined. "
      "Ensure SYCLToolkit is found before building torch-xpu-ops.")
  endif()
  list(APPEND SYCL_DEVICE_COMPILE_DEFINITIONS SYCL_COMPILER_VERSION=${SYCL_COMPILER_VERSION})
  # Keep the bare spelling: it must match PyTorch's add_compile_definitions(USE_XPU)
  # so CMake's exact-string dedup drops it instead of redefining the macro.
  list(APPEND SYCL_DEVICE_COMPILE_DEFINITIONS USE_XPU)

  set(CPP_STD c++20)
  # -- Host flags (SYCL_CXX_FLAGS)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    list(APPEND SYCL_HOST_FLAGS /std:${CPP_STD})
    list(APPEND SYCL_HOST_FLAGS /MD)
    list(APPEND SYCL_HOST_FLAGS /EHsc) # exception handling
    # SYCL headers warnings
    list(APPEND SYCL_HOST_FLAGS /wd4996) # allow usage of deprecated functions
    list(APPEND SYCL_HOST_FLAGS /wd4018) # allow signed and unsigned comparison

    # SYCL compilation never sees CMAKE_CXX_FLAGS_<CONFIG>, so spell per-config
    # host flags here via $<CONFIG:>. /Z7 (not /Zi) avoids PDB contention.
    set(SYCL_HOST_PER_CONFIG_FLAGS
      "$<$<CONFIG:Debug>:SHELL:-Xarch_host /Od;SHELL:-Xarch_host /Z7>"
      "$<$<CONFIG:RelWithDebInfo>:SHELL:-Xarch_host /O2;SHELL:-Xarch_host /Z7>")
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    list(APPEND SYCL_HOST_FLAGS -fPIC)
    list(APPEND SYCL_HOST_FLAGS -std=${CPP_STD})
    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      list(APPEND SYCL_COMPILE_FLAGS -Qunused-arguments)
    endif()
    # These GCC warning options remain available to regular host compilation,
    # but are not supported by the Intel SYCL/Clang host frontend.
    list(APPEND SYCL_HOST_FLAGS_EXCLUDED_FROM_SYCL
      -Wno-stringop-overflow
      -Wno-dangling-reference
      -Wno-error=dangling-reference
      -Wno-interference-size)
    CHECK_SYCL_FLAG("-Wno-maybe-uninitialized;-Werror=unknown-warning-option" SUPPORTS_NO_MAYBE_UNINITIALIZED)
    if(NOT SUPPORTS_NO_MAYBE_UNINITIALIZED)
      list(APPEND SYCL_HOST_FLAGS_EXCLUDED_FROM_SYCL -Wno-maybe-uninitialized)
    endif()
    # Excluding warnings which flood the compilation output
    # TODO: fix warnings in the source code and then reenable them in compilation
    list(APPEND SYCL_HOST_FLAGS -Wno-sign-compare)

    # PyTorch forces -O2 into the base CMAKE_CXX_FLAGS this path inherits, so
    # Debug must override it back to -O0; RelWithDebInfo only adds debug info.
    # Host only: device debug is controlled by XPU_DEVICE_DEBUG/DEBUG_XPU below.
    set(SYCL_HOST_PER_CONFIG_FLAGS
      "$<$<CONFIG:Debug>:SHELL:-Xarch_host -g;SHELL:-Xarch_host -fno-omit-frame-pointer;SHELL:-Xarch_host -O0>"
      "$<$<CONFIG:RelWithDebInfo>:SHELL:-Xarch_host -g>")
  endif()

  if(USE_PER_OPERATOR_HEADERS)
    list(APPEND SYCL_HOST_FLAGS -DAT_PER_OPERATOR_HEADERS)
  endif()
  # -- Common SYCL compile flags (SYCL_COMPILE_FLAGS)
  # The fast-math will be enabled by default in SYCL compiler.
  # Refer to [https://clang.llvm.org/docs/UsersManual.html#cmdoption-fno-fast-math]
  # 1. We enable below flags here to be warn about NaN and Infinity,
  # which will be hidden by fast-math by default.
  # 2. The associative-math in fast-math allows floating point
  # operations to be reassociated, which will lead to non-deterministic
  # results compared with CUDA backend.
  # 3. The approx-func allows certain math function calls (such as log, sqrt, pow, etc)
  # to be replaced with an approximately equivalent set of instructions or
  # alternative math function calls, which have great errors.
  #
  # PSEUDO of the default Linux pure icpx build (BUILD_SEPARATE_OPS disabled).
  # 1. Kernel source compilation (icpx handles both host and device code):
  # icpx -fsycl ${CMAKE_SYCL_FLAGS} -std=c++20 -fsycl-targets=${SYCL_DEVICE_TARGETS} -fgpu-rdc ${SYCL_COMPILE_FLAGS} kernel.cpp -o kernel.o
  # 2. Device code linkage (SYCL_RESOLVE_DEVICE_SYMBOLS):
  # icpx ${CMAKE_SYCL_FLAGS} -fsycl-targets=${SYCL_DEVICE_TARGETS} ${SYCL_DEVICE_LINK_FLAGS} -Xs '${SYCL_OFFLINE_COMPILER_FLAGS}' -fsycl -fsycl-link host.o kernel.o -o cmake_device_link.o
  # 3. Host only source compilation:
  # gcc ${CMAKE_CXX_FLAGS} host.cpp -o host.o
  # 4. Archive torch-xpu-ops objects:
  # ar qc libtorch_xpu_ops.a host.o kernel.o cmake_device_link.o
  # 5. Link the final PyTorch XPU shared library:
  # gcc -shared -Wl,--whole-archive libtorch_xpu_ops.a -Wl,--no-whole-archive -o libtorch_xpu.so
  list(APPEND SYCL_COMPILE_FLAGS -fno-sycl-unnamed-lambda)
  list(APPEND SYCL_COMPILE_FLAGS -fno-sycl-id-queries-fit-in-int)
  list(APPEND SYCL_COMPILE_FLAGS -sycl-std=2020)
  list(APPEND SYCL_COMPILE_FLAGS -foffload-fp32-prec-div)
  list(APPEND SYCL_COMPILE_FLAGS -foffload-fp32-prec-sqrt)

  # SYCL defaults fast-math ON, which strips the inf/NaN our kernels check.
  # Probe the compiler for the strict-FP flag and fail if it is rejected. Keep
  # it before /Qfma and -ffp-contract=fast, which re-add the FMA we do want.
  if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    set(_sycl_strict_fp_flag /fp:strict)
  else()
    set(_sycl_strict_fp_flag -fno-fast-math)
  endif()
  CHECK_SYCL_FLAG("${_sycl_strict_fp_flag}" _supports_strict_fp)
  if(NOT _supports_strict_fp)
    message(FATAL_ERROR
      "SYCL compiler ${CMAKE_SYCL_COMPILER} rejects ${_sycl_strict_fp_flag}; its "
      "default fast-math would silently break kernel inf/NaN semantics.")
  endif()
  list(APPEND SYCL_COMPILE_FLAGS ${_sycl_strict_fp_flag})

  if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    # The C++ standard comes from SYCL_CXX_STANDARD, which CMake spells as
    # -Qstd:c++20 for the MSVC-like icx driver.
    list(APPEND SYCL_COMPILE_FLAGS /Qfma)
    list(APPEND SYCL_COMPILE_FLAGS /Qftz-)
    # Suppress warnings about dllexport.
    list(APPEND SYCL_COMPILE_FLAGS -Wno-ignored-attributes)
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    list(APPEND SYCL_COMPILE_FLAGS -Wno-absolute-value)
    # -fma which we used before is an alias used for -ffp-contract=fast for compatibility reasons
    # with very old version of the ICX compiler. The -ffp-contract=fast is supported by both closed
    # source and open source DPC++ compiler versions.
    list(APPEND SYCL_COMPILE_FLAGS -ffp-contract=fast)
    # -no-ftz is supported only by ICX compiler shipped with oneAPI Toolkits. For the
    # DPCLANG open source compiler that's the default mode and no option is needed.
    CHECK_SYCL_FLAG("-no-ftz" SUPPORTS_NO_FTZ)
    if(SUPPORTS_NO_FTZ)
      list(APPEND SYCL_COMPILE_FLAGS -no-ftz)
    endif()
  endif()

  if(WIN32)
    list(APPEND _sycl_intel_lib_libirc_flag "/Qno-intel-lib:libirc")
  else()
    list(APPEND _sycl_intel_lib_libirc_flag "-no-intel-lib=libirc")
  endif()

  CHECK_SYCL_FLAG("${_sycl_intel_lib_libirc_flag}" SUPPORTS_INTEL_LIB_LIBIRC_FLAG)
  if(SUPPORTS_INTEL_LIB_LIBIRC_FLAG)
    list(APPEND SYCL_COMPILE_FLAGS ${_sycl_intel_lib_libirc_flag})
  endif()

  # -- Device debug flags (aligned with CUDA behavior)
  # XPU_DEVICE_DEBUG=1: full device debug, disables optimization (like CUDA's -g -G)
  #   Orthogonal to build type, always forces device debug.
  # DEBUG_XPU=1: line-table-only debug info (like CUDA's -lineinfo)
  #   Only effective in Debug/RelWithDebInfo builds.
  # DEBUG=1 alone: does NOT affect device code (same as CUDA).
  if(DEFINED ENV{XPU_DEVICE_DEBUG} AND "$ENV{XPU_DEVICE_DEBUG}" STREQUAL "1")
    list(APPEND SYCL_COMPILE_FLAGS -g -O0 -Rno-debug-disables-optimization)
  elseif(DEFINED ENV{DEBUG_XPU} AND "$ENV{DEBUG_XPU}" STREQUAL "1")
    list(APPEND SYCL_COMPILE_FLAGS
      $<$<CONFIG:Debug,RelWithDebInfo>:-gline-tables-only;-O2>)
  endif()

  CHECK_SYCL_FLAG("-fsycl-fp64-conv-emu" SUPPORTS_FP64_CONV_EMU)
  if(NOT SUPPORTS_FP64_CONV_EMU)
    message(WARNING "The compiler does not support the '-fsycl-fp64-conv-emu' flag, \
    will disable it. On some platforms that don't support FP64, \
    running operations with the FP64 datatype will raise a Runtime error: Required aspect fp64 is not supported on the device \
    or a Native API failed error.")
  endif()

  # TORCH_XPU_OPS_FLAGS stays config-agnostic: its target_compile_options
  # consumers already get PyTorch's per-config host flags via
  # CMAKE_CXX_FLAGS_<CONFIG> (which carries -fno-omit-frame-pointer/-O0 in
  # Debug, and /Z7 in place of /Zi through MSVC_Z7_OVERRIDE). The per-config
  # genexes in SYCL_HOST_PER_CONFIG_FLAGS feed only SYCL compilation.
  # TORCH_XPU_OPS_FLAGS applies to SYCL sources as well.
  set(TORCH_XPU_OPS_FLAGS ${SYCL_HOST_FLAGS})

  # -- SYCL device object linkage flags
  include(ProcessorCount)
  ProcessorCount(proc_cnt)
  if((DEFINED ENV{MAX_JOBS}) AND ("$ENV{MAX_JOBS}" LESS_EQUAL ${proc_cnt}))
    set(SYCL_MAX_PARALLEL_LINK_JOBS $ENV{MAX_JOBS})
  else()
    set(SYCL_MAX_PARALLEL_LINK_JOBS ${proc_cnt})
  endif()
  list(APPEND SYCL_DEVICE_LINK_FLAGS -fsycl-max-parallel-link-jobs=${SYCL_MAX_PARALLEL_LINK_JOBS})
  list(APPEND SYCL_DEVICE_LINK_FLAGS --offload-compress)
  list(APPEND SYCL_DEVICE_LINK_FLAGS -foffload-fp32-prec-sqrt)
  list(APPEND SYCL_DEVICE_LINK_FLAGS -foffload-fp32-prec-div)
  list(APPEND SYCL_DEVICE_LINK_FLAGS -fno-sycl-id-queries-fit-in-int)

  string(APPEND SYCL_OFFLINE_COMPILER_CG_OPTIONS " -options -cl-poison-unsupported-fp64-kernels")
  string(APPEND SYCL_OFFLINE_COMPILER_CG_OPTIONS " -options -cl-intel-enable-auto-large-GRF-mode")
  string(APPEND SYCL_OFFLINE_COMPILER_CG_OPTIONS " -options -cl-intel-greater-than-4GB-buffer-required")

  if(REPLACE_FLAGS_FOR_SYCLTLA)
    set(SYCL_DEVICE_TARGETS spir64_gen)
    # FlashAttention's softmax subtracts a rounded row maximum from s * scale.
    # Contracting those into an FMA leaves the product unrounded, so the
    # largest element no longer cancels to zero; the residual is ~ulp(s*scale)
    # and exp2 turns it into inf for large inputs, which poisons the output
    # with NaN. See pytorch/pytorch#121558, which CUDA addresses via its
    # UNFUSE_FMA macro. This must stay after the -ffp-contract=fast set above;
    # the last setting wins.
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
      set(_sycltla_no_fma_flag /Qfma-)
    else()
      set(_sycltla_no_fma_flag -ffp-contract=off)
    endif()
    CHECK_SYCL_FLAG("${_sycltla_no_fma_flag}" _supports_no_fma)
    if(NOT _supports_no_fma)
      message(FATAL_ERROR
        "SYCL compiler ${CMAKE_SYCL_COMPILER} rejects ${_sycltla_no_fma_flag}; FMA "
        "contraction would make FlashAttention return NaN for large inputs.")
    endif()
    list(APPEND SYCL_COMPILE_FLAGS ${_sycltla_no_fma_flag})
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      # Keep third-party SYCL-TLA diagnostics visible without making them
      # errors in WERROR builds. This flag set is captured only by the
      # torch-xpu-ops-sycltla target.
      list(APPEND SYCL_HOST_FLAGS_ONLY_FOR_SYCL
        -Wno-error=logical-op-parentheses
        -Wno-error=deprecated-copy-with-user-provided-copy
        -Wno-error=unused-but-set-variable
        -Wno-error=uninitialized)
    endif()
    list(APPEND SYCL_DEVICE_LINK_FLAGS "-Xspirv-translator;-spirv-ext=+SPV_INTEL_split_barrier,+SPV_INTEL_2d_block_io,+SPV_INTEL_subgroup_matrix_multiply_accumulate")
    if(TORCH_XPU_ARCH_LIST STREQUAL "cri")
      set(SYCL_OFFLINE_COMPILER_AOT_OPTIONS "-device cri")
    else()
      set(SYCL_OFFLINE_COMPILER_AOT_OPTIONS "-device pvc,bmg")
    endif()
  else()
    if(WIN32)
      set(AOT_TARGETS "mtl,mtl-h,bmg,dg2,arl-h,lnl-m,ptl")
    else()
      set(AOT_TARGETS "pvc,bmg,dg2,arl-h,mtl-h,lnl-m,ptl-h,ptl-u")
    endif()
    if(TORCH_XPU_ARCH_LIST)
      set(AOT_TARGETS "${TORCH_XPU_ARCH_LIST}")
    endif()
    if(AOT_TARGETS STREQUAL "none")
      set(TORCH_XPU_ARCH_LIST "" PARENT_SCOPE)
    else()
      if(SUPPORTS_FP64_CONV_EMU)
        string(FIND "${AOT_TARGETS}" "dg2" _dg2_index)
        string(FIND "${AOT_TARGETS}" "ats-m" _atsm_index)
        if(_dg2_index GREATER_EQUAL 0 OR _atsm_index GREATER_EQUAL 0)
          list(APPEND SYCL_COMPILE_FLAGS -fsycl-fp64-conv-emu)
          list(APPEND SYCL_DEVICE_LINK_FLAGS -fsycl-fp64-conv-emu)
        endif()
      endif()
      set(SYCL_DEVICE_TARGETS spir64_gen spir64)
      set(SYCL_OFFLINE_COMPILER_AOT_OPTIONS "-device ${AOT_TARGETS}")
      set(TORCH_XPU_ARCH_LIST ${AOT_TARGETS} PARENT_SCOPE)
    endif()
    message(STATUS "Compile Intel GPU AOT Targets for ${AOT_TARGETS}")
  endif()

  set(SYCL_OFFLINE_COMPILER_FLAGS "${SYCL_OFFLINE_COMPILER_AOT_OPTIONS}${SYCL_OFFLINE_COMPILER_CG_OPTIONS}")

  # -- SYCL language flags (CMAKE_SYCL_FLAGS), used with SYCL_EXTENSION_MODE
  # REPLACE: the host C++ flags minus those unknown to the SYCL compiler. They
  # apply to both host and device compilation of SYCL sources.
  separate_arguments(_sycl_cxx_flags NATIVE_COMMAND "${CMAKE_CXX_FLAGS}")
  list(REMOVE_DUPLICATES _sycl_cxx_flags)
  if(SYCL_HOST_FLAGS_EXCLUDED_FROM_SYCL)
    list(REMOVE_ITEM _sycl_cxx_flags ${SYCL_HOST_FLAGS_EXCLUDED_FROM_SYCL})
  endif()
  list(JOIN _sycl_cxx_flags " " CMAKE_SYCL_FLAGS)
  # Per-config host flags come from SYCL_HOST_PER_CONFIG_FLAGS, device debug
  # flags from XPU_DEVICE_DEBUG/DEBUG_XPU. Drop CMake's per-config defaults
  # (e.g. -O3 -DNDEBUG) so the device optimization level does not change.
  foreach(_sycl_config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set(CMAKE_SYCL_FLAGS_${_sycl_config} "")
  endforeach()
  unset(_sycl_cxx_flags)
endmacro()

# Apply the SYCL flags composed by set_build_flags() to a target which
# compiles SYCL sources. The flags in effect at call time are captured.
function(torch_xpu_ops_sycl_target_flags target)
  set_target_properties(${target} PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    SYCL_CXX_STANDARD 20
    SYCL_CXX_STANDARD_REQUIRED ON
    SYCL_EXTENSIONS OFF
    # Device code is compiled in RDC mode (the DPC++ default) and linked with
    # the AOT compilation in a separate device link step.
    SYCL_SEPARABLE_COMPILATION ON
    SYCL_DEVICE_TARGETS "${SYCL_DEVICE_TARGETS}")
  get_target_property(_type ${target} TYPE)
  if(_type STREQUAL "STATIC_LIBRARY")
    # Link the device code into the archive, so that consumers can link it
    # with the host C++ linker.
    set_target_properties(${target} PROPERTIES SYCL_RESOLVE_DEVICE_SYMBOLS ON)
  endif()
  target_compile_definitions(${target} PRIVATE
    "$<$<COMPILE_LANGUAGE:SYCL>:${SYCL_DEVICE_COMPILE_DEFINITIONS}>")
  target_compile_options(${target} PRIVATE
    "$<$<COMPILE_LANGUAGE:SYCL>:${SYCL_COMPILE_FLAGS};${SYCL_HOST_FLAGS_ONLY_FOR_SYCL};${SYCL_HOST_PER_CONFIG_FLAGS}>")
  # $<DEVICE_LINK:...> takes comma separated arguments, escape commas in flags
  # such as "-device pvc,bmg".
  set(_device_link_flags ${SYCL_DEVICE_LINK_FLAGS} -Xs "${SYCL_OFFLINE_COMPILER_FLAGS}")
  string(REPLACE "," "$<COMMA>" _device_link_flags "${_device_link_flags}")
  target_link_options(${target} PRIVATE "$<DEVICE_LINK:${_device_link_flags}>")
endfunction()

# Add SYCL sources to a target, compiled with the native CMake SYCL language,
# and apply the SYCL flags in effect.
function(torch_xpu_ops_add_sycl_sources target)
  target_sources(${target} PRIVATE
    FILE_SET sycl_sources TYPE SYCL
    BASE_DIRS ${TORCH_XPU_OPS_ROOT}
    FILES ${ARGN})
  torch_xpu_ops_sycl_target_flags(${target})
endfunction()

# Shared options/includes/links for every torch_xpu_ops target.
# ARGN = extra PUBLIC libs (Windows: c10_xpu torch_cpu).
function(torch_xpu_ops_finalize_targets)
  foreach(lib ${TORCH_XPU_OPS_LIBRARIES})
    # Align with PyTorch compile options PYTORCH_SRC_DIR/cmake/public/utils.cmake
    torch_compile_options(${lib})
    target_compile_options_if_supported(${lib} "-Wno-deprecated-copy")
    target_compile_options(${lib} PRIVATE ${TORCH_XPU_OPS_FLAGS})

    target_include_directories(${lib} PUBLIC
        ${TORCH_XPU_OPS_INCLUDE_DIRS} ${ATen_XPU_INCLUDE_DIRS} ${SYCL_INCLUDE_DIR})

    target_link_libraries(${lib}
        PUBLIC  ${SYCL_LIBRARY} ${ARGN}
        PRIVATE ATEN_XPU_FILES_GEN_LIB)

    # Sources depend on generated ATen headers.
    if(TORCH_XPU_OPS_PYTORCH_DEPS)
      add_dependencies(${lib} ${TORCH_XPU_OPS_PYTORCH_DEPS})
    endif()
  endforeach()
endfunction()
