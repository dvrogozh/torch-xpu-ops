# Copyright 2020-2026 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0

# ATen XPU sources

if(BUILD_EAGER_MODE)
  file(GLOB xpu_native_cpp "native/xpu/*.cpp" "native/sparse/*.cpp" "native/sparse/xpu/*.cpp" "native/nested/*.cpp" "native/nested/xpu/*.cpp" "native/transformers/*.cpp" "native/quantized/*.cpp" "native/transformers/xpu/flash_attn/*.cpp")
  file(GLOB xpu_sycl "native/xpu/sycl/*.cpp" "native/sparse/xpu/sycl/*.cpp" "native/nested/xpu/sycl/*.cpp" "native/transformers/sycl/*.cpp" "native/quantized/sycl/*.cpp")
  file(GLOB xpu_sycltla "native/transformers/xpu/flash_attn/sycltla/*.cpp")
  file(GLOB xpu_sleep "xpu/Sleep.cpp")
else()
  set(xpu_native_cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/Copy.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/Resize.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/TensorFactories.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/UnaryOps.cpp
  )
  set(xpu_sycl
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/AbsKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/CopyKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/ResizeKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryComplexKernels.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryFractionKernels.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGammaKernels.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricAcosKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricAcoshKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricAsinKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricAsinhKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricAtanKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricAtanhKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricCosKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricCoshKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricSinKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricSinhKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricTanKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryGeometricTanhKernel.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryKernels.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnaryLogKernels.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnarySignKernels.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/native/xpu/sycl/UnarySpecialOpsKernels.cpp
  )

endif()

if(USE_ONEMKL_XPU)
  file(GLOB xpu_mkl "native/xpu/mkl/*.cpp")
  list(APPEND ATen_XPU_MKL_SRCS ${xpu_mkl})
endif()
list(APPEND ATen_XPU_NATIVE_CPP_SRCS ${xpu_native_cpp})
list(APPEND ATen_XPU_SYCL_SRCS ${xpu_sycl} ${xpu_sleep})
list(APPEND ATen_XPU_SYCLTLA_SRCS ${xpu_sycltla})

set(ATen_XPU_MKL_SRCS ${ATen_XPU_MKL_SRCS} PARENT_SCOPE)
set(ATen_XPU_NATIVE_CPP_SRCS ${ATen_XPU_NATIVE_CPP_SRCS} PARENT_SCOPE)
set(ATen_XPU_SYCL_SRCS ${ATen_XPU_SYCL_SRCS} PARENT_SCOPE)
set(ATen_XPU_SYCLTLA_SRCS ${ATen_XPU_SYCLTLA_SRCS} PARENT_SCOPE)

# ATen XPU headers

macro(install_xpu_headers subdir)
  file(GLOB headers CONFIGURE_DEPENDS "${subdir}/*.h")
  if(headers)
    install(FILES ${headers} DESTINATION "${AT_INSTALL_INCLUDE_DIR}/ATen/${subdir}")
  endif()
endmacro()

install_xpu_headers("xpu")
install_xpu_headers("native/xpu")
install_xpu_headers("native/xpu/sycl")
install_xpu_headers("native/xpu/mkl")
install_xpu_headers("native/nested/xpu")
install_xpu_headers("native/nested/xpu/sycl")
install_xpu_headers("native/quantized/xpu")
install_xpu_headers("native/quantized/xpu/sycl")
install_xpu_headers("native/sparse/xpu")
install_xpu_headers("native/sparse/xpu/sycl")
install_xpu_headers("native/transformers/xpu")
install_xpu_headers("native/transformers/xpu/flash_attn")

if(xpu_ops_generated_headers)
  install(FILES ${xpu_ops_generated_headers} DESTINATION ${AT_INSTALL_INCLUDE_DIR}/ATen/ops)
endif()
