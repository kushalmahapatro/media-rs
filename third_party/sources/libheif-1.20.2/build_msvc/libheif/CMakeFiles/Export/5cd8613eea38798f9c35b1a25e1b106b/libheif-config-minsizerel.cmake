#----------------------------------------------------------------
# Generated CMake target import file for configuration "MinSizeRel".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "heif" for configuration "MinSizeRel"
set_property(TARGET heif APPEND PROPERTY IMPORTED_CONFIGURATIONS MINSIZEREL)
set_target_properties(heif PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_MINSIZEREL "CXX"
  IMPORTED_LOCATION_MINSIZEREL "${_IMPORT_PREFIX}/lib/heif.lib"
  )

list(APPEND _cmake_import_check_targets heif )
list(APPEND _cmake_import_check_files_for_heif "${_IMPORT_PREFIX}/lib/heif.lib" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
