# Install script for directory: /home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/home/kushal/project/media-rs/third_party/libheif_build_linux_x86_64")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "1")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/plugins/cmake_install.cmake")
endif()

if("x${CMAKE_INSTALL_COMPONENT}x" STREQUAL "xUnspecifiedx" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" TYPE STATIC_LIBRARY FILES "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/libheif.a")
endif()

if("x${CMAKE_INSTALL_COMPONENT}x" STREQUAL "xUnspecifiedx" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/libheif" TYPE FILE FILES
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_library.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_image.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_color.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_error.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_plugin.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_properties.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_regions.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_items.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_sequences.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_tai_timestamps.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_brands.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_metadata.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_aux_images.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_entity_groups.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_security.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_encoding.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_decoding.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_image_handle.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_context.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_tiling.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_uncompressed.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/libheif/api/libheif/heif_cxx.h"
    "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/heif_version.h"
    )
endif()

if("x${CMAKE_INSTALL_COMPONENT}x" STREQUAL "xUnspecifiedx" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif/libheif-config.cmake")
    file(DIFFERENT EXPORT_FILE_CHANGED FILES
         "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif/libheif-config.cmake"
         "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/CMakeFiles/Export/lib/cmake/libheif/libheif-config.cmake")
    if(EXPORT_FILE_CHANGED)
      file(GLOB OLD_CONFIG_FILES "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif/libheif-config-*.cmake")
      if(OLD_CONFIG_FILES)
        message(STATUS "Old export file \"$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif/libheif-config.cmake\" will be replaced.  Removing files [${OLD_CONFIG_FILES}].")
        file(REMOVE ${OLD_CONFIG_FILES})
      endif()
    endif()
  endif()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif" TYPE FILE FILES "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/CMakeFiles/Export/lib/cmake/libheif/libheif-config.cmake")
  if("${CMAKE_INSTALL_CONFIG_NAME}" MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif" TYPE FILE FILES "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/CMakeFiles/Export/lib/cmake/libheif/libheif-config-release.cmake")
  endif()
endif()

if("x${CMAKE_INSTALL_COMPONENT}x" STREQUAL "xUnspecifiedx" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/libheif" TYPE FILE FILES "/home/kushal/project/media-rs/third_party/sources/libheif-1.20.2/build_linux/libheif/libheif-config-version.cmake")
endif()

