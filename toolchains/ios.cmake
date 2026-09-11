# Native iOS ARM64 toolchain for the Foundation shell.
# A macOS host with Xcode is required.

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)

set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum supported iOS version")
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "iOS device architecture")

if(NOT DEFINED CMAKE_OSX_SYSROOT)
    set(CMAKE_OSX_SYSROOT "iphoneos" CACHE STRING "Apple SDK")
endif()

if(NOT CMAKE_GENERATOR STREQUAL "Xcode")
    message(WARNING "The iOS target is intended to use the Xcode generator.")
endif()
