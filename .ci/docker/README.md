# Docker images for GitHub CI and CD

This directory contains everything needed to build the Docker images that are used in our CI tests.

## Docker CI builds

* `pytorch/manylinux2_28-builder:xpu-main` -- can use pytorch CICD image directly

## Docker CI tests

To build specific image for tests:

```bash
docker build --build-arg UBUNTU_VERSION=22.04 --build-arg XPU_DRIVER_TYPE=LTS2 --build-arg GCC_VERSION=13 --file ubuntu/Dockerfile .
```

Build arguments:

| Option | Possible values|
| --- | --- |
| `UBUNTU_VERSION` | `22.04`, `24.04`, etc. |
| `XPU_DRIVER_TYPE` | `LTS`, `LTS2`, `rolling` |
| `GCC_VERSION` | `11`, `13`, etc. |

To use image for builds, need additionally install Intel® Deep Learning Essentials. Refer to [PyTorch Prerequisites for Intel GPUs](https://www.intel.com/content/www/us/en/developer/articles/tool/pytorch-prerequisites-for-intel-gpu.html)).
