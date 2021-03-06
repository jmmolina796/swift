# SWIFTLIB_DIR is the directory in the build tree where Swift resource files
# should be placed.  Note that $CMAKE_CFG_INTDIR expands to "." for
# single-configuration builds.
set(SWIFTLIB_DIR
    "${CMAKE_BINARY_DIR}/${CMAKE_CFG_INTDIR}/lib/swift")
set(SWIFTSTATICLIB_DIR
    "${CMAKE_BINARY_DIR}/${CMAKE_CFG_INTDIR}/lib/swift_static")

function(_list_add_string_suffix input_list suffix result_var_name)
  set(result)
  foreach(element ${input_list})
    list(APPEND result "${element}${suffix}")
  endforeach()
  set("${result_var_name}" "${result}" PARENT_SCOPE)
endfunction()

function(_list_escape_for_shell input_list result_var_name)
  set(result "")
  foreach(element ${input_list})
    string(REPLACE " " "\\ " element "${element}")
    set(result "${result}${element} ")
  endforeach()
  set("${result_var_name}" "${result}" PARENT_SCOPE)
endfunction()

function(add_dependencies_multiple_targets)
  cmake_parse_arguments(
      ADMT # prefix
      "" # options
      "" # single-value args
      "TARGETS;DEPENDS" # multi-value args
      ${ARGN})
  if(NOT "${ADMT_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "unrecognized arguments: ${ADMT_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT "${ADMT_DEPENDS}" STREQUAL "")
    foreach(target ${ADMT_TARGETS})
      add_dependencies("${target}" ${ADMT_DEPENDS})
    endforeach()
  endif()
endfunction()

# Compute the library subdirectory to use for the given sdk and
# architecture, placing the result in 'result_var_name'.
function(compute_library_subdir result_var_name sdk arch)
  set("${result_var_name}" "${SWIFT_SDK_${sdk}_LIB_SUBDIR}/${arch}" PARENT_SCOPE)
endfunction()

# Usage:
# _add_variant_c_compile_link_flags(
#   SDK sdk
#   ARCH arch
#   BUILD_TYPE build_type
#   ENABLE_LTO enable_lto
#   ANALYZE_CODE_COVERAGE analyze_code_coverage
#   RESULT_VAR_NAME result_var_name
#   DEPLOYMENT_VERSION_IOS deployment_version_ios # If provided, overrides the default value of the iOS deployment target set by the Swift project for this compilation only.
# 
# )
function(_add_variant_c_compile_link_flags)
  set(oneValueArgs SDK ARCH BUILD_TYPE RESULT_VAR_NAME ENABLE_LTO ANALYZE_CODE_COVERAGE DEPLOYMENT_VERSION_IOS)
  cmake_parse_arguments(CFLAGS
    ""
    "${oneValueArgs}"
    ""
    ${ARGN})
  
  set(result
    ${${CFLAGS_RESULT_VAR_NAME}}
    "-target" "${SWIFT_SDK_${CFLAGS_SDK}_ARCH_${CFLAGS_ARCH}_TRIPLE}")

  list(APPEND result
    "-isysroot" "${SWIFT_SDK_${CFLAGS_SDK}_PATH}")

  if("${CFLAGS_SDK}" STREQUAL "ANDROID")
    list(APPEND result
      "--sysroot=${SWIFT_ANDROID_SDK_PATH}"
      # Use the linker included in the Android NDK.
      "-B" "${SWIFT_ANDROID_NDK_PATH}/toolchains/arm-linux-androideabi-${SWIFT_ANDROID_NDK_GCC_VERSION}/prebuilt/linux-x86_64/arm-linux-androideabi/bin/")
  endif()


  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
    
    # Check if there's a specific iOS deployment version needed for this invocation
    if("${CFLAGS_SDK}" STREQUAL "IOS" OR "${CFLAGS_SDK}" STREQUAL "IOS_SIMULATOR")
      set(DEPLOYMENT_VERSION ${CFLAGS_DEPLOYMENT_VERSION_IOS})
    endif()
    
    if("${DEPLOYMENT_VERSION}" STREQUAL "")
      set(DEPLOYMENT_VERSION "${SWIFT_SDK_${CFLAGS_SDK}_DEPLOYMENT_VERSION}")
    endif()
    
    list(APPEND result
      "-arch" "${CFLAGS_ARCH}"
      "-F" "${SWIFT_SDK_${CFLAGS_SDK}_PATH}/../../../Developer/Library/Frameworks"
      "-m${SWIFT_SDK_${CFLAGS_SDK}_VERSION_MIN_NAME}-version-min=${DEPLOYMENT_VERSION}")
      
    if(CFLAGS_ANALYZE_CODE_COVERAGE)
      list(APPEND result "-fprofile-instr-generate"
                         "-fcoverage-mapping")
    endif()
  endif()

  if(CFLAGS_ENABLE_LTO)
    list(APPEND result "-flto")
  endif()

  set("${CFLAGS_RESULT_VAR_NAME}" "${result}" PARENT_SCOPE)
endfunction()

function(_add_variant_c_compile_flags)
  set(oneValueArgs SDK ARCH BUILD_TYPE ENABLE_ASSERTIONS ANALYZE_CODE_COVERAGE DEPLOYMENT_VERSION_IOS RESULT_VAR_NAME)
  cmake_parse_arguments(CFLAGS
    ""
    "${oneValueArgs}"
    ""
    ${ARGN})

  set(result ${${CFLAGS_RESULT_VAR_NAME}})

  _add_variant_c_compile_link_flags(
    SDK "${CFLAGS_SDK}"
    ARCH "${CFLAGS_ARCH}"
    BUILD_TYPE "${CFLAGS_BUILD_TYPE}"
    ENABLE_ASSERTIONS "${CFLAGS_ENABLE_ASSERTIONS}"
    ENABLE_LTO "${SWIFT_ENABLE_LTO}"
    ANALYZE_CODE_COVERAGE FALSE
    DEPLOYMENT_VERSION_IOS "${CFLAGS_DEPLOYMENT_VERSION_IOS}"
    RESULT_VAR_NAME result)

  is_build_type_optimized("${CFLAGS_BUILD_TYPE}" optimized)
  if(optimized)
    list(APPEND result "-O2")

    # Add -momit-leaf-frame-pointer on x86.
    if("${CFLAGS_ARCH}" STREQUAL "i386" OR "${CFLAGS_ARCH}" STREQUAL "x86_64")
      list(APPEND result "-momit-leaf-frame-pointer")
    endif()
  else()
    list(APPEND result "-O0")
  endif()

  is_build_type_with_debuginfo("${CFLAGS_BUILD_TYPE}" debuginfo)
  if(debuginfo)
    if(SWIFT_ENABLE_LTO)
      list(APPEND result "-gline-tables-only")
    else()
      list(APPEND result "-g")
    endif()
  else()
    list(APPEND result "-g0")
  endif()

  if(CFLAGS_ENABLE_ASSERTIONS)
    list(APPEND result "-UNDEBUG")
  else()
    list(APPEND result "-DNDEBUG")
  endif()

  if(CFLAGS_ANALYZE_CODE_COVERAGE)
    list(APPEND result "-fprofile-instr-generate"
                       "-fcoverage-mapping")
  endif()

  if("${CFLAGS_SDK}" STREQUAL "ANDROID")
    list(APPEND result
        "-I${SWIFT_ANDROID_NDK_PATH}/sources/cxx-stl/llvm-libc++/libcxx/include"
        "-I${SWIFT_ANDROID_NDK_PATH}/sources/cxx-stl/llvm-libc++abi/libcxxabi/include"
        "-I${SWIFT_ANDROID_NDK_PATH}/sources/android/support/include")
  endif()

  set("${CFLAGS_RESULT_VAR_NAME}" "${result}" PARENT_SCOPE)
endfunction()

function(_add_variant_swift_compile_flags
    sdk arch build_type enable_assertions result_var_name)
  set(result ${${result_var_name}})

  list(APPEND result
      "-sdk" "${SWIFT_SDK_${sdk}_PATH}"
      "-target" "${SWIFT_SDK_${sdk}_ARCH_${arch}_TRIPLE}")

  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
    list(APPEND result
        "-F" "${SWIFT_SDK_${sdk}_PATH}/../../../Developer/Library/Frameworks")
  endif()

  is_build_type_optimized("${build_type}" optimized)
  if(optimized)
    list(APPEND result "-O")
  else()
    list(APPEND result "-Onone")
  endif()

  is_build_type_with_debuginfo("${build_type}" debuginfo)
  if(debuginfo)
    list(APPEND result "-g")
  endif()

  if(enable_assertions)
    list(APPEND result "-D" "INTERNAL_CHECKS_ENABLED")
  endif()

  set("${result_var_name}" "${result}" PARENT_SCOPE)
endfunction()

function(_add_variant_link_flags)
  set(oneValueArgs SDK ARCH BUILD_TYPE ENABLE_ASSERTIONS ANALYZE_CODE_COVERAGE DEPLOYMENT_VERSION_IOS RESULT_VAR_NAME)
  cmake_parse_arguments(LFLAGS
    ""
    "${oneValueArgs}"
    ""
    ${ARGN})
  
  if("${LFLAGS_SDK}" STREQUAL "")
    message(FATAL_ERROR "Should specify an SDK")
  endif()

  if("${LFLAGS_ARCH}" STREQUAL "")
    message(FATAL_ERROR "Should specify an architecture")
  endif()

  set(result ${${LFLAGS_RESULT_VAR_NAME}})

  _add_variant_c_compile_link_flags(
    SDK "${LFLAGS_SDK}"
    ARCH "${LFLAGS_ARCH}"
    BUILD_TYPE "${LFLAGS_BUILD_TYPE}"
    ENABLE_ASSERTIONS "${LFLAGS_ENABLE_ASSERTIONS}"
    ENABLE_LTO "${SWIFT_ENABLE_LTO}"
    ANALYZE_CODE_COVERAGE "${LFLAGS_ANALYZE_CODE_COVERAGE}"
    DEPLOYMENT_VERSION_IOS "${LFLAGS_DEPLOYMENT_VERSION_IOS}"
    RESULT_VAR_NAME result)

  if("${LFLAGS_SDK}" STREQUAL "LINUX")
    list(APPEND result "-lpthread" "-ldl")
  elseif("${LFLAGS_SDK}" STREQUAL "FREEBSD")
    list(APPEND result "-lpthread")
  elseif("${LFLAGS_SDK}" STREQUAL "CYGWIN")
    # No extra libraries required.
  elseif("${LFLAGS_SDK}" STREQUAL "ANDROID")
    list(APPEND result
        "-ldl"
        "-L${SWIFT_ANDROID_NDK_PATH}/toolchains/arm-linux-androideabi-${SWIFT_ANDROID_NDK_GCC_VERSION}/prebuilt/linux-x86_64/lib/gcc/arm-linux-androideabi/${SWIFT_ANDROID_NDK_GCC_VERSION}"
        "${SWIFT_ANDROID_NDK_PATH}/sources/cxx-stl/llvm-libc++/libs/armeabi-v7a/libc++_shared.so"
        "-L${SWIFT_ANDROID_ICU_UC}" "-L${SWIFT_ANDROID_ICU_I18N}")
  else()
    list(APPEND result "-lobjc")
  endif()

  set("${LFLAGS_RESULT_VAR_NAME}" "${result}" PARENT_SCOPE)
endfunction()

# Look up extra flags for a module that matches a regexp.
function(_add_extra_swift_flags_for_module module_name result_var_name)
  set(result_list)
  list(LENGTH SWIFT_EXPERIMENTAL_EXTRA_REGEXP_FLAGS listlen)
  if (${listlen} GREATER 0)
    math(EXPR listlen "${listlen}-1")
    foreach(i RANGE 0 ${listlen} 2)
      list(GET SWIFT_EXPERIMENTAL_EXTRA_REGEXP_FLAGS ${i} regex)
      if (module_name MATCHES "${regex}")
        math(EXPR ip1 "${i}+1")
        list(GET SWIFT_EXPERIMENTAL_EXTRA_REGEXP_FLAGS ${ip1} flags)
        list(APPEND result_list ${flags})
        message(STATUS "Matched '${regex}' to module '${module_name}'. Compiling ${module_name} with special flags: ${flags}")
      endif()
    endforeach()
  endif()
  list(LENGTH SWIFT_EXPERIMENTAL_EXTRA_NEGATIVE_REGEXP_FLAGS listlen)
  if (${listlen} GREATER 0)
    math(EXPR listlen "${listlen}-1")
    foreach(i RANGE 0 ${listlen} 2)
      list(GET SWIFT_EXPERIMENTAL_EXTRA_NEGATIVE_REGEXP_FLAGS ${i} regex)
      if (NOT module_name MATCHES "${regex}")
        math(EXPR ip1 "${i}+1")
        list(GET SWIFT_EXPERIMENTAL_EXTRA_NEGATIVE_REGEXP_FLAGS ${ip1} flags)
        list(APPEND result_list ${flags})
        message(STATUS "Matched NEGATIVE '${regex}' to module '${module_name}'. Compiling ${module_name} with special flags: ${flags}")
      endif()
    endforeach()
  endif()
  set("${result_var_name}" ${result_list} PARENT_SCOPE)
endfunction()

# Add a universal binary target created from the output of the given
# set of targets by running 'lipo'.
#
# Usage:
#   _add_swift_lipo_target(
#     target              # The name of the target to create
#     output              # The file to be created by this target
#     source_targets...   # The source targets whose outputs will be
#                         # lipo'd into the output.
#   )
function(_add_swift_lipo_target target output)
  if("${target}" STREQUAL "")
    message(FATAL_ERROR "target is required")
  endif()

  if("${output}" STREQUAL "")
    message(FATAL_ERROR "output is required")
  endif()

  set(source_targets ${ARGN})

  # Gather the source binaries.
  set(source_binaries)
  foreach(source_target ${source_targets})
    if(SWIFT_CMAKE_HAS_GENERATOR_EXPRESSIONS)
      list(APPEND source_binaries $<TARGET_FILE:${source_target}>)
    else()
      get_property(source_binary
          TARGET ${source_target}
          PROPERTY LOCATION)
      list(APPEND source_binaries "${source_binary}")
    endif()
  endforeach()

  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
    # Use lipo to create the final binary.
    add_custom_command_target(unused_var
        COMMAND "${LIPO}" "-create" "-output" "${output}" ${source_binaries}
        CUSTOM_TARGET_NAME "${target}"
        OUTPUT "${output}"
        DEPENDS ${source_targets})
  else()
    # We don't know how to create fat binaries for other platforms.
    add_custom_command_target(unused_var
        COMMAND "${CMAKE_COMMAND}" "-E" "copy" "${source_binaries}" "${output}"
        CUSTOM_TARGET_NAME "${target}"
        OUTPUT "${output}"
        DEPENDS ${source_targets})
  endif()
endfunction()

# After target 'dst_target' is built from its own object files, merge the
# contents of 'src_target' into it. 'dst_target' and 'src_target' must be
# static-library targets.
function(_target_merge_static_library dst_target src_target)
  add_dependencies("${dst_target}" "${src_target}")
  set(unpack_dir "${CMAKE_BINARY_DIR}/tmp/unpack/${dst_target}")
  add_custom_command(TARGET "${dst_target}" POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${unpack_dir}"
    COMMAND cd "${unpack_dir}"
    COMMAND "${CMAKE_AR}" x "$<TARGET_FILE:${src_target}>"
    COMMAND "${CMAKE_AR}" r "$<TARGET_FILE:${dst_target}>" ./*.o
    COMMAND cd "${CMAKE_BINARY_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E remove_directory "${unpack_dir}"
  )
endfunction()

# Add a single variant of a new Swift library.
#
# Usage:
#   _add_swift_library_single(
#     target
#     name
#     [SHARED]
#     [SDK sdk]
#     [ARCHITECTURE architecture]
#     [DEPENDS dep1 ...]
#     [LINK_LIBRARIES dep1 ...]
#     [FRAMEWORK_DEPENDS dep1 ...]
#     [FRAMEWORK_DEPENDS_WEAK dep1 ...]
#     [COMPONENT_DEPENDS comp1 ...]
#     [C_COMPILE_FLAGS flag1...]
#     [SWIFT_COMPILE_FLAGS flag1...]
#     [LINK_FLAGS flag1...]
#     [API_NOTES_NON_OVERLAY]
#     [FILE_DEPENDS target1 ...]
#     [DONT_EMBED_BITCODE]
#     [IS_STDLIB]
#     [IS_STDLIB_CORE]
#     [IS_SDK_OVERLAY]
#     INSTALL_IN_COMPONENT comp
#     source1 [source2 source3 ...])
#
# target
#   Name of the target (e.g., swiftParse-IOS-armv7).
#
# name
#   Name of the library (e.g., swiftParse).
#
# SHARED
#   Build a shared library.
#
# SDK sdk
#   SDK to build for.
#
# ARCHITECTURE
#   Architecture to build for.
#
# DEPENDS
#   Targets that this library depends on.
#
# LINK_LIBRARIES
#   Libraries this library depends on.
#
# FRAMEWORK_DEPENDS
#   System frameworks this library depends on.
#
# FRAMEWORK_DEPENDS_WEAK
#   System frameworks this library depends on that should be weakly-linked.
#
# COMPONENT_DEPENDS
#   LLVM components this library depends on.
#
# C_COMPILE_FLAGS
#   Extra compile flags (C, C++, ObjC).
#
# SWIFT_COMPILE_FLAGS
#   Extra compile flags (Swift).
#
# LINK_FLAGS
#   Extra linker flags.
#
# API_NOTES_NON_OVERLAY
#   Generate API notes for non-overlayed modules with this target.
#
# FILE_DEPENDS
#   Additional files this library depends on.
#
# DONT_EMBED_BITCODE
#   Don't embed LLVM bitcode in this target, even if it is enabled globally.
#
# IS_STDLIB
#   Install library dylib and swift module files to lib/swift.
#
# IS_STDLIB_CORE
#   Compile as the standard library core.
#
# IS_SDK_OVERLAY
#   Treat the library as a part of the Swift SDK overlay.
#
# INSTALL_IN_COMPONENT comp
#   The Swift installation component that this library belongs to.
#
# source1 ...
#   Sources to add into this library
function(_add_swift_library_single target name)
  set(SWIFTLIB_SINGLE_options
      SHARED IS_STDLIB IS_STDLIB_CORE IS_SDK_OVERLAY
      TARGET_LIBRARY HOST_LIBRARY
      API_NOTES_NON_OVERLAY DONT_EMBED_BITCODE)
  cmake_parse_arguments(SWIFTLIB_SINGLE
    "${SWIFTLIB_SINGLE_options}"
    "SDK;ARCHITECTURE;INSTALL_IN_COMPONENT;DEPLOYMENT_VERSION_IOS"
    "DEPENDS;LINK_LIBRARIES;FRAMEWORK_DEPENDS;FRAMEWORK_DEPENDS_WEAK;COMPONENT_DEPENDS;C_COMPILE_FLAGS;SWIFT_COMPILE_FLAGS;LINK_FLAGS;PRIVATE_LINK_LIBRARIES;INTERFACE_LINK_LIBRARIES;FILE_DEPENDS"
    ${ARGN})

  set(SWIFTLIB_SINGLE_SOURCES ${SWIFTLIB_SINGLE_UNPARSED_ARGUMENTS})

  translate_flags(SWIFTLIB_SINGLE "${SWIFTLIB_SINGLE_options}")

  # Check arguments.
  if ("${SWIFTLIB_SINGLE_SDK}" STREQUAL "")
    message(FATAL_ERROR "Should specify an SDK")
  endif()

  if ("${SWIFTLIB_SINGLE_ARCHITECTURE}" STREQUAL "")
    message(FATAL_ERROR "Should specify an architecture")
  endif()

  if("${SWIFTLIB_SINGLE_INSTALL_IN_COMPONENT}" STREQUAL "")
    message(FATAL_ERROR "INSTALL_IN_COMPONENT is required")
  endif()
  
  # Determine the subdirectory where this library will be installed.
  set(SWIFTLIB_SINGLE_SUBDIR
      "${SWIFT_SDK_${SWIFTLIB_SINGLE_SDK}_LIB_SUBDIR}/${SWIFTLIB_SINGLE_ARCHITECTURE}")

  # Include LLVM Bitcode slices for iOS, Watch OS, and Apple TV OS device libraries.
  if(SWIFT_EMBED_BITCODE_SECTION AND NOT SWIFTLIB_DONT_EMBED_BITCODE)
    if("${SWIFTLIB_SINGLE_SDK}" STREQUAL "IOS" OR "${SWIFTLIB_SINGLE_SDK}" STREQUAL "TVOS" OR "${SWIFTLIB_SINGLE_SDK}" STREQUAL "WATCHOS")
      list(APPEND SWIFTLIB_SINGLE_C_COMPILE_FLAGS "-fembed-bitcode")
      list(APPEND SWIFTLIB_SINGLE_SWIFT_COMPILE_FLAGS "-embed-bitcode")
      list(APPEND SWIFTLIB_SINGLE_LINK_FLAGS "-Xlinker" "-bitcode_bundle" "-Xlinker" "-bitcode_hide_symbols" "-Xlinker" "-lto_library" "-Xlinker" "${LLVM_LIBRARY_DIR}/libLTO.dylib")
    endif()
  endif()

  if (SWIFT_COMPILER_VERSION)
    if ("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
      list(APPEND SWIFTLIB_SINGLE_LINK_FLAGS "-Xlinker" "-current_version" "-Xlinker" "${SWIFT_COMPILER_VERSION}" "-Xlinker" "-compatibility_version" "-Xlinker" "1")
    endif()
  endif()

  if(XCODE)
    string(REGEX MATCHALL "/[^/]+" split_path ${CMAKE_CURRENT_SOURCE_DIR})
    list(GET split_path -1 dir)
    file(GLOB_RECURSE SWIFTLIB_SINGLE_HEADERS
      ${SWIFT_SOURCE_DIR}/include/swift${dir}/*.h
      ${SWIFT_SOURCE_DIR}/include/swift${dir}/*.def
      ${CMAKE_CURRENT_SOURCE_DIR}/*.def)

    file(GLOB_RECURSE SWIFTLIB_SINGLE_TDS
      ${SWIFT_SOURCE_DIR}/include/swift${dir}/*.td)
    source_group("TableGen descriptions" FILES ${SWIFTLIB_SINGLE_TDS})

    set(SWIFTLIB_SINGLE_SOURCES ${SWIFTLIB_SINGLE_SOURCES} ${SWIFTLIB_SINGLE_HEADERS} ${SWIFTLIB_SINGLE_TDS})
  endif()

  if(MODULE)
    set(libkind MODULE)
  elseif(SWIFTLIB_SINGLE_SHARED)
    set(libkind SHARED)
  else()
    set(libkind)
  endif()

  handle_gyb_sources(
      gyb_dependency_targets
      SWIFTLIB_SINGLE_SOURCES
      "${SWIFTLIB_SINGLE_ARCHITECTURE}")

  # Figure out whether and which API notes to create.
  set(SWIFTLIB_SINGLE_API_NOTES)
  if(SWIFTLIB_SINGLE_API_NOTES_NON_OVERLAY)
    # Adopt all of the non-overlay API notes.
    foreach(framework_name ${SWIFT_API_NOTES_INPUTS})
      if (${framework_name} STREQUAL "WatchKit" AND
          ${SWIFTLIB_SINGLE_SDK} STREQUAL "OSX")
        # HACK: don't build WatchKit API notes for OS X.
      else()
        if (NOT IS_DIRECTORY "${SWIFT_SOURCE_DIR}/stdlib/public/SDK/${framework_name}")
          list(APPEND SWIFTLIB_SINGLE_API_NOTES "${framework_name}")
        endif()
      endif()
    endforeach()
  endif()

  # Remove the "swift" prefix from the name to determine the module name.
  string(REPLACE swift "" module_name "${name}")
  list(FIND SWIFT_API_NOTES_INPUTS "${module_name}" overlay_index)
  if(NOT ${overlay_index} EQUAL -1)
    set(SWIFTLIB_SINGLE_API_NOTES "${module_name}")
  endif()

  # On platforms that use ELF binaries (for now that is Linux and FreeBSD)
  # we add markers for metadata sections in the shared libraries using 
  # these object files.  This wouldn't be necessary if the link was done by
  # the swift binary: rdar://problem/19007002
  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux" OR
     "${CMAKE_SYSTEM_NAME}" STREQUAL "FreeBSD")

    if("${libkind}" STREQUAL "SHARED")
      set(arch_subdir "${SWIFTLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR}")

      set(SWIFT_SECTIONS_OBJECT_BEGIN "${arch_subdir}/swift_begin.o")
      set(SWIFT_SECTIONS_OBJECT_END   "${arch_subdir}/swift_end.o")
    endif()

  endif()

  # FIXME: don't actually depend on the libraries in SWIFTLIB_SINGLE_LINK_LIBRARIES,
  # just any swiftmodule files that are associated with them.
  handle_swift_sources(
      swift_object_dependency_target
      SWIFTLIB_SINGLE_SOURCES
      SWIFTLIB_SINGLE_EXTERNAL_SOURCES ${name}
      DEPENDS
        ${gyb_dependency_targets}
        ${SWIFTLIB_SINGLE_FILE_DEPENDS}
        ${SWIFTLIB_SINGLE_LINK_LIBRARIES}
        ${SWIFTLIB_SINGLE_INTERFACE_LINK_LIBRARIES}
      SDK ${SWIFTLIB_SINGLE_SDK}
      ARCHITECTURE ${SWIFTLIB_SINGLE_ARCHITECTURE}
      API_NOTES ${SWIFTLIB_SINGLE_API_NOTES}
      COMPILE_FLAGS ${SWIFTLIB_SINGLE_SWIFT_COMPILE_FLAGS}
      ${SWIFTLIB_SINGLE_IS_STDLIB_keyword}
      ${SWIFTLIB_SINGLE_IS_STDLIB_CORE_keyword}
      ${SWIFTLIB_SINGLE_IS_SDK_OVERLAY_keyword}
      INSTALL_IN_COMPONENT "${SWIFTLIB_INSTALL_IN_COMPONENT}")
  add_swift_source_group("${SWIFTLIB_SINGLE_EXTERNAL_SOURCES}")

  add_library("${target}" ${libkind}
      ${SWIFT_SECTIONS_OBJECT_BEGIN}
      ${SWIFTLIB_SINGLE_SOURCES}
      ${SWIFTLIB_SINGLE_EXTERNAL_SOURCES}
      ${SWIFT_SECTIONS_OBJECT_END})

  # The section metadata objects are generated sources, and we need to tell CMake
  # not to expect to find them prior to their generation.
  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux" OR
     "${CMAKE_SYSTEM_NAME}" STREQUAL "FreeBSD")
    if("${libkind}" STREQUAL "SHARED")
      set_source_files_properties(${SWIFT_SECTIONS_OBJECT_BEGIN} PROPERTIES GENERATED 1)
      set_source_files_properties(${SWIFT_SECTIONS_OBJECT_END} PROPERTIES GENERATED 1)
      add_dependencies("${target}" section_magic)
    endif()
  endif()

  llvm_update_compile_flags(${target})

  set_output_directory(${target}
      BINARY_DIR ${SWIFT_RUNTIME_OUTPUT_INTDIR}
      LIBRARY_DIR ${SWIFT_LIBRARY_OUTPUT_INTDIR})

  if(MODULE)
    set_target_properties("${target}" PROPERTIES
        PREFIX ""
        SUFFIX ${LLVM_PLUGIN_EXT})
  endif()

  if(SWIFTLIB_SINGLE_TARGET_LIBRARY)
    # Install runtime libraries to lib/swift instead of lib. This works around
    # the fact that -isysroot prevents linking to libraries in the system
    # /usr/lib if Swift is installed in /usr.
    set_target_properties("${target}" PROPERTIES
      LIBRARY_OUTPUT_DIRECTORY ${SWIFTLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR}
      ARCHIVE_OUTPUT_DIRECTORY ${SWIFTLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR})

    foreach(config ${CMAKE_CONFIGURATION_TYPES})
      string(TOUPPER ${config} config_upper)
      apply_xcode_substitutions("${config}" "${SWIFTLIB_DIR}" config_lib_dir)
      set_target_properties(${target} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY_${config_upper} ${config_lib_dir}/${SWIFTLIB_SINGLE_SUBDIR}
        ARCHIVE_OUTPUT_DIRECTORY_${config_upper} ${config_lib_dir}/${SWIFTLIB_SINGLE_SUBDIR})
    endforeach()
  endif()

  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
    set(install_name_dir "@rpath")

    if(SWIFTLIB_SINGLE_IS_STDLIB)
      # Always use @rpath for XCTest.
      if(NOT "${module_name}" STREQUAL "XCTest")
        set(install_name_dir "${SWIFT_DARWIN_STDLIB_INSTALL_NAME_DIR}")
      endif()
    endif()

    set_target_properties("${target}"
      PROPERTIES
      INSTALL_NAME_DIR "${install_name_dir}")
  elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux" AND NOT "${SWIFTLIB_SINGLE_SDK}" STREQUAL "ANDROID")
    set_target_properties("${target}"
      PROPERTIES
      INSTALL_RPATH "$ORIGIN:/usr/lib/swift/linux")
  elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Cygwin")
    set_target_properties("${target}"
      PROPERTIES
      INSTALL_RPATH "$ORIGIN:/usr/lib/swift/windows")
  endif()

  set_target_properties("${target}" PROPERTIES BUILD_WITH_INSTALL_RPATH YES)
  set_target_properties("${target}" PROPERTIES FOLDER "Swift libraries")

  # Configure the static library target.
  # Set compile and link flags for the non-static target.
  # Do these LAST.

  set(target_static)
  if(SWIFTLIB_SINGLE_IS_STDLIB AND SWIFT_BUILD_STATIC_STDLIB)
    set(target_static "${target}-static")

    # We have already compiled Swift sources.  Link everything into a static
    # library.
    add_library(${target_static} STATIC
        ${SWIFTLIB_SINGLE_SOURCES}

        # Note: the dummy.c source file provides no definitions. However,
        # it forces Xcode to properly link the static library.
        ${SWIFT_SOURCE_DIR}/cmake/dummy.c)

    set_output_directory(${target_static}
        BINARY_DIR ${SWIFT_RUNTIME_OUTPUT_INTDIR}
        LIBRARY_DIR ${SWIFT_LIBRARY_OUTPUT_INTDIR})

    foreach(config ${CMAKE_CONFIGURATION_TYPES})
      string(TOUPPER ${config} config_upper)
      apply_xcode_substitutions(
          "${config}" "${SWIFTSTATICLIB_DIR}" config_lib_dir)
      set_target_properties(${target_static} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY_${config_upper} ${config_lib_dir}/${SWIFTLIB_SINGLE_SUBDIR}
        ARCHIVE_OUTPUT_DIRECTORY_${config_upper} ${config_lib_dir}/${SWIFTLIB_SINGLE_SUBDIR})
    endforeach()

    set_target_properties(${target_static} PROPERTIES
      LIBRARY_OUTPUT_DIRECTORY ${SWIFTSTATICLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR}
      ARCHIVE_OUTPUT_DIRECTORY ${SWIFTSTATICLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR})
  endif()

  set_target_properties(${target}
      PROPERTIES
      # Library name (without the variant information)
      OUTPUT_NAME ${name})
  if(target_static)
    set_target_properties(${target_static}
        PROPERTIES
        OUTPUT_NAME ${name})
  endif()

  # Don't build standard libraries by default.  We will enable building
  # standard libraries that the user requested; the rest can be built on-demand.
  if(SWIFTLIB_SINGLE_TARGET_LIBRARY)
    foreach(t "${target}" ${target_static})
      set_target_properties(${t} PROPERTIES EXCLUDE_FROM_ALL TRUE)
    endforeach()
  endif()

  # Handle linking and dependencies.
  add_dependencies_multiple_targets(
      TARGETS "${target}" ${target_static}
      DEPENDS
        ${SWIFTLIB_SINGLE_DEPENDS}
        ${gyb_dependency_targets}
        "${swift_object_dependency_target}"
        ${LLVM_COMMON_DEPENDS})

  # HACK: On some systems or build directory setups, CMake will not find static
  # archives of Clang libraries in the Clang build directory, and it will pass
  # them as '-lclangFoo'.  Some other logic in CMake would reorder libraries
  # specified with this syntax, which breaks linking.
  set(prefixed_link_libraries)
  foreach(dep ${SWIFTLIB_SINGLE_LINK_LIBRARIES})
    if("${dep}" MATCHES "^clang")
      set(dep "${LLVM_LIBRARY_OUTPUT_INTDIR}/lib${dep}.a")
    endif()
    if("${dep}" STREQUAL "cmark")
      set(dep "${CMARK_LIBRARY_DIR}/lib${dep}.a")
    endif()
    list(APPEND prefixed_link_libraries "${dep}")
  endforeach()
  set(SWIFTLIB_SINGLE_LINK_LIBRARIES "${prefixed_link_libraries}")

  if("${libkind}" STREQUAL "SHARED")
    target_link_libraries("${target}" PRIVATE ${SWIFTLIB_SINGLE_LINK_LIBRARIES})
  else()
    target_link_libraries("${target}" INTERFACE ${SWIFTLIB_SINGLE_LINK_LIBRARIES})
  endif()

  # Don't add the icucore target.
  set(SWIFTLIB_SINGLE_LINK_LIBRARIES_WITHOUT_ICU)
  foreach(item ${SWIFTLIB_SINGLE_LINK_LIBRARIES})
    if(NOT "${item}" STREQUAL "icucore")
      list(APPEND SWIFTLIB_SINGLE_LINK_LIBRARIES_WITHOUT_ICU "${item}")
    endif()
  endforeach()

  if(target_static)
    _list_add_string_suffix(
        "${SWIFTLIB_SINGLE_LINK_LIBRARIES_WITHOUT_ICU}"
        "-static"
        target_static_depends)
    # FIXME: should this be target_link_libraries?
    add_dependencies_multiple_targets(
        TARGETS "${target_static}"
        DEPENDS ${target_static_depends})
  endif()

  # Link against system frameworks.
  foreach(FRAMEWORK ${SWIFTLIB_SINGLE_FRAMEWORK_DEPENDS})
    foreach(t "${target}" ${target_static})
      target_link_libraries("${t}" PUBLIC "-framework ${FRAMEWORK}")
    endforeach()
  endforeach()
  foreach(FRAMEWORK ${SWIFTLIB_SINGLE_FRAMEWORK_DEPENDS_WEAK})
    foreach(t "${target}" ${target_static})
      target_link_libraries("${t}" PUBLIC "-weak_framework ${FRAMEWORK}")
    endforeach()
  endforeach()

  swift_common_llvm_config("${target}" ${SWIFTLIB_SINGLE_COMPONENT_DEPENDS})

  # Collect compile and link flags for the static and non-static targets.
  # Don't set PROPERTY COMPILE_FLAGS or LINK_FLAGS directly.
  set(c_compile_flags ${SWIFTLIB_SINGLE_C_COMPILE_FLAGS})
  set(link_flags ${SWIFTLIB_SINGLE_LINK_FLAGS})

  # Add variant-specific flags.
  if(SWIFTLIB_SINGLE_IS_STDLIB)
    set(build_type "${SWIFT_STDLIB_BUILD_TYPE}")
    set(enable_assertions "${SWIFT_STDLIB_ASSERTIONS}")
  else()
    set(build_type "${CMAKE_BUILD_TYPE}")
    set(enable_assertions "${LLVM_ENABLE_ASSERTIONS}")
    set(analyze_code_coverage "${SWIFT_ANALYZE_CODE_COVERAGE}")
  endif()
  _add_variant_c_compile_flags(
    SDK "${SWIFTLIB_SINGLE_SDK}"
    ARCH "${SWIFTLIB_SINGLE_ARCHITECTURE}"
    BUILD_TYPE "${build_type}"
    ENABLE_ASSERTIONS "${enable_assertions}"
    ANALYZE_CODE_COVERAGE "${analyze_code_coverage}"
    DEPLOYMENT_VERSION_IOS "${SWIFTLIB_DEPLOYMENT_VERSION_IOS}"
    RESULT_VAR_NAME c_compile_flags
    )
  _add_variant_link_flags(
    SDK "${SWIFTLIB_SINGLE_SDK}"
    ARCH "${SWIFTLIB_SINGLE_ARCHITECTURE}"
    BUILD_TYPE "${build_type}"
    ENABLE_ASSERTIONS "${enable_assertions}"
    ANALYZE_CODE_COVERAGE "${analyze_code_coverage}"
    DEPLOYMENT_VERSION_IOS "${SWIFTLIB_DEPLOYMENT_VERSION_IOS}"
    RESULT_VAR_NAME link_flags
      )

  if(SWIFT_ENABLE_GOLD_LINKER)
    list(APPEND link_flags "-fuse-ld=gold")
  endif()

  # Configure plist creation for OS X.
  set(PLIST_INFO_PLIST "Info.plist" CACHE STRING "Plist name")
  if(APPLE AND SWIFTLIB_SINGLE_IS_STDLIB)
    set(PLIST_INFO_NAME ${name})
    set(PLIST_INFO_UTI "com.apple.dt.runtime.${name}")
    set(PLIST_INFO_VERSION "${SWIFT_VERSION}")
    if (SWIFT_COMPILER_VERSION)
      set(PLIST_INFO_BUILD_VERSION
        "${SWIFT_COMPILER_VERSION}")
    endif()

    set(PLIST_INFO_PLIST_OUT "${PLIST_INFO_PLIST}")
    list(APPEND link_flags
         "-Wl,-sectcreate,__TEXT,__info_plist,${CMAKE_CURRENT_BINARY_DIR}/${PLIST_INFO_PLIST_OUT}")
    configure_file(
        "${SWIFT_SOURCE_DIR}/stdlib/${PLIST_INFO_PLIST}.in"
        "${PLIST_INFO_PLIST_OUT}"
        @ONLY
        NEWLINE_STYLE UNIX)

    # If Application Extensions are enabled, pass the linker flag marking
    # the dylib as safe.
    if (CXX_SUPPORTS_FAPPLICATION_EXTENSION AND (NOT DISABLE_APPLICATION_EXTENSION))
      list(APPEND link_flags "-Wl,-application_extension")
    endif()

    set(PLIST_INFO_UTI)
    set(PLIST_INFO_NAME)
    set(PLIST_INFO_VERSION)
    set(PLIST_INFO_BUILD_VERSION)
  endif()

  # Convert variables to space-separated strings.
  _list_escape_for_shell("${c_compile_flags}" c_compile_flags)
  _list_escape_for_shell("${link_flags}" link_flags)

  # Set compilation and link flags.
  set_property(TARGET "${target}" APPEND_STRING PROPERTY
      COMPILE_FLAGS " ${c_compile_flags}")
  set_property(TARGET "${target}" APPEND_STRING PROPERTY
    LINK_FLAGS " ${link_flags} -L${SWIFTLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR} -L${SWIFT_NATIVE_SWIFT_TOOLS_PATH}/../lib/swift/${SWIFTLIB_SINGLE_SUBDIR} -L${SWIFT_NATIVE_SWIFT_TOOLS_PATH}/../lib/swift/${SWIFT_SDK_${SWIFTLIB_SINGLE_SDK}_LIB_SUBDIR}")
  target_link_libraries("${target}" PRIVATE
      ${SWIFTLIB_SINGLE_PRIVATE_LINK_LIBRARIES})
  target_link_libraries("${target}" INTERFACE
      ${SWIFTLIB_SINGLE_INTERFACE_LINK_LIBRARIES})
  set_property(TARGET "${target}" PROPERTY
      LINKER_LANGUAGE "CXX")

  if(target_static)
    set_property(TARGET "${target_static}" APPEND_STRING PROPERTY
        COMPILE_FLAGS " ${c_compile_flags}")
    set_property(TARGET "${target_static}" APPEND_STRING PROPERTY
      LINK_FLAGS " ${link_flags} -L${SWIFTSTATICLIB_DIR}/${SWIFTLIB_SINGLE_SUBDIR} -L${SWIFT_NATIVE_SWIFT_TOOLS_PATH}/../lib/swift/${SWIFTLIB_SINGLE_SUBDIR} -L${SWIFT_NATIVE_SWIFT_TOOLS_PATH}/../lib/swift/${SWIFT_SDK_${SWIFTLIB_SINGLE_SDK}_LIB_SUBDIR}")
    target_link_libraries("${target_static}" PRIVATE
        ${SWIFTLIB_SINGLE_PRIVATE_LINK_LIBRARIES})

    if("${name}" STREQUAL "swiftCore")
      # Have libswiftCore.a include the contents of the private Swift libraries
      # it depends on, so statically linking clients don't have to know about
      # them.
      foreach(private_link_library ${SWIFTLIB_SINGLE_PRIVATE_LINK_LIBRARIES})
        if(TARGET "${private_link_library}")
          _target_merge_static_library("${target_static}" "${private_link_library}")
        endif()
      endforeach()
    endif()
  endif()

  # Do not add code here.
endfunction()

# Add a new Swift library.
#
# Usage:
#   add_swift_library(name
#     [SHARED]
#     [DEPENDS dep1 ...]
#     [LINK_LIBRARIES dep1 ...]
#     [INTERFACE_LINK_LIBRARIES dep1 ...]
#     [SWIFT_MODULE_DEPENDS dep1 ...]
#     [FRAMEWORK_DEPENDS dep1 ...]
#     [FRAMEWORK_DEPENDS_WEAK dep1 ...]
#     [COMPONENT_DEPENDS comp1 ...]
#     [FILE_DEPENDS target1 ...]
#     [TARGET_SDKS sdk1...]
#     [C_COMPILE_FLAGS flag1...]
#     [SWIFT_COMPILE_FLAGS flag1...]
#     [LINK_FLAGS flag1...]
#     [DONT_EMBED_BITCODE]
#     [API_NOTES_NON_OVERLAY]
#     [INSTALL]
#     [IS_STDLIB]
#     [IS_STDLIB_CORE]
#     [TARGET_LIBRARY]
#     INSTALL_IN_COMPONENT comp
#     DEPLOYMENT_VERSION_IOS version
#     source1 [source2 source3 ...])
#
# name
#   Name of the library (e.g., swiftParse).
#
# SHARED
#   Build a shared library.
#
# DEPENDS
#   Targets that this library depends on.
#
# LINK_LIBRARIES
#   Libraries this library depends on.
#
# SWIFT_MODULE_DEPENDS
#   Swift modules this library depends on.
#
# SWIFT_MODULE_DEPENDS_OSX
#   Swift modules this library depends on when built for OS X.
#
# SWIFT_MODULE_DEPENDS_IOS
#   Swift modules this library depends on when built for iOS.
#
# SWIFT_MODULE_DEPENDS_TVOS
#   Swift modules this library depends on when built for tvOS.
#
# SWIFT_MODULE_DEPENDS_WATCHOS
#   Swift modules this library depends on when built for watchOS.
#
# FRAMEWORK_DEPENDS
#   System frameworks this library depends on.
#
# FRAMEWORK_DEPENDS_WEAK
#   System frameworks this library depends on that should be weak-linked
#
# COMPONENT_DEPENDS
#   LLVM components this library depends on.
#
# FILE_DEPENDS
#   Additional files this library depends on.
#
# TARGET_SDKS
#   The set of SDKs in which this library is included. If empty, the library
#   is included in all SDKs.
#
# C_COMPILE_FLAGS
#   Extra compiler flags (C, C++, ObjC).
#
# SWIFT_COMPILE_FLAGS
#   Extra compiler flags (Swift).
#
# LINK_FLAGS
#   Extra linker flags.
#
# API_NOTES_NON_OVERLAY
#   Generate API notes for non-overlayed modules with this target.
#
# DONT_EMBED_BITCODE
#   Don't embed LLVM bitcode in this target, even if it is enabled globally.
#
# IS_STDLIB
#   Treat the library as a part of the Swift standard library.
#   IS_STDLIB implies TARGET_LIBRARY.
#
# IS_STDLIB_CORE
#   Compile as the Swift standard library core.
#
# IS_SDK_OVERLAY
#   Treat the library as a part of the Swift SDK overlay.
#   IS_SDK_OVERLAY implies TARGET_LIBRARY and IS_STDLIB.
#
# TARGET_LIBRARY
#   Build library for the target SDKs.
#
# INSTALL_IN_COMPONENT comp
#   The Swift installation component that this library belongs to.
#
# DEPLOYMENT_VERSION_IOS
#   The minimum deployment version to build for if this is an iOS library.
#
# source1 ...
#   Sources to add into this library.
function(add_swift_library name)
  set(SWIFTLIB_options
      SHARED IS_STDLIB IS_STDLIB_CORE IS_SDK_OVERLAY
      TARGET_LIBRARY HOST_LIBRARY
      API_NOTES_NON_OVERLAY DONT_EMBED_BITCODE HAS_SWIFT_CONTENT)
  cmake_parse_arguments(SWIFTLIB
    "${SWIFTLIB_options}"
    "INSTALL_IN_COMPONENT;DEPLOYMENT_VERSION_IOS"
    "DEPENDS;LINK_LIBRARIES;SWIFT_MODULE_DEPENDS;SWIFT_MODULE_DEPENDS_OSX;SWIFT_MODULE_DEPENDS_IOS;SWIFT_MODULE_DEPENDS_TVOS;SWIFT_MODULE_DEPENDS_WATCHOS;FRAMEWORK_DEPENDS;FRAMEWORK_DEPENDS_WEAK;FRAMEWORK_DEPENDS_OSX;FRAMEWORK_DEPENDS_IOS_TVOS;COMPONENT_DEPENDS;FILE_DEPENDS;TARGET_SDKS;C_COMPILE_FLAGS;SWIFT_COMPILE_FLAGS;SWIFT_COMPILE_FLAGS_OSX;SWIFT_COMPILE_FLAGS_IOS;SWIFT_COMPILE_FLAGS_TVOS;SWIFT_COMPILE_FLAGS_WATCHOS;LINK_FLAGS;PRIVATE_LINK_LIBRARIES;INTERFACE_LINK_LIBRARIES"
    ${ARGN})
  set(SWIFTLIB_SOURCES ${SWIFTLIB_UNPARSED_ARGUMENTS})

  # Infer arguments.

  if(SWIFTLIB_IS_SDK_OVERLAY)
    set(SWIFTLIB_HAS_SWIFT_CONTENT TRUE)
    set(SWIFTLIB_SHARED TRUE)
    set(SWIFTLIB_IS_STDLIB TRUE)
    set(SWIFTLIB_TARGET_LIBRARY TRUE)

    # There are no experimental SDK overlays.
    set(SWIFTLIB_INSTALL_IN_COMPONENT sdk-overlay)
  endif()

  # Standard library is always a target library.
  if(SWIFTLIB_IS_STDLIB)
    set(SWIFTLIB_HAS_SWIFT_CONTENT TRUE)
    set(SWIFTLIB_TARGET_LIBRARY TRUE)
  endif()

  if(NOT SWIFTLIB_TARGET_LIBRARY)
    set(SWIFTLIB_INSTALL_IN_COMPONENT dev)
  endif()

  # If target SDKs are not specified, build for all known SDKs.
  if("${SWIFTLIB_TARGET_SDKS}" STREQUAL "")
    set(SWIFTLIB_TARGET_SDKS ${SWIFT_SDKS})
  endif()

  # All Swift code depends on the standard library, except for the standard
  # library itself.
  if(SWIFTLIB_TARGET_LIBRARY AND SWIFTLIB_HAS_SWIFT_CONTENT AND NOT SWIFTLIB_IS_STDLIB_CORE)
    list(APPEND SWIFTLIB_SWIFT_MODULE_DEPENDS Core)
  endif()

  if((NOT "${SWIFT_BUILD_STDLIB}") AND
     (NOT "${SWIFTLIB_SWIFT_MODULE_DEPENDS}" STREQUAL ""))
    list(REMOVE_ITEM SWIFTLIB_SWIFT_MODULE_DEPENDS
        Core)
  endif()

  is_build_type_optimized("${SWIFT_STDLIB_BUILD_TYPE}" optimized)
  if(NOT optimized)
    # All Swift code depends on the SwiftOnoneSupport in non-optimized mode,
    # except for the standard library itself.
    if(SWIFTLIB_TARGET_LIBRARY AND NOT SWIFTLIB_IS_STDLIB_CORE)
      list(APPEND SWIFTLIB_SWIFT_MODULE_DEPENDS SwiftOnoneSupport)
    endif()
  endif()

  if((NOT "${SWIFT_BUILD_STDLIB}") AND
    (NOT "${SWIFTLIB_SWIFT_MODULE_DEPENDS}" STREQUAL ""))
    list(REMOVE_ITEM SWIFTLIB_SWIFT_MODULE_DEPENDS
        SwiftOnoneSupport)
  endif()

  # swiftSwiftOnoneSupport does not depend on itself,
  # obviously.
  if("${name}" STREQUAL "swiftSwiftOnoneSupport")
    list(REMOVE_ITEM SWIFTLIB_SWIFT_MODULE_DEPENDS
        SwiftOnoneSupport)
  endif()

  translate_flags(SWIFTLIB "${SWIFTLIB_options}")

  if("${SWIFTLIB_INSTALL_IN_COMPONENT}" STREQUAL "")
    message(FATAL_ERROR "INSTALL_IN_COMPONENT is required")
  endif()
  
  if(SWIFTLIB_TARGET_LIBRARY)
    # If we are building this library for targets, loop through the various
    # SDKs building the variants of this library.
    list_intersect(
        "${SWIFTLIB_TARGET_SDKS}" "${SWIFT_SDKS}" SWIFTLIB_TARGET_SDKS)
    if(SWIFTLIB_HOST_LIBRARY)
      list_union(
          "${SWIFTLIB_TARGET_SDKS}" "${SWIFT_HOST_VARIANT_SDK}"
          SWIFTLIB_TARGET_SDKS)
    endif()
    foreach(sdk ${SWIFTLIB_TARGET_SDKS})
      set(THIN_INPUT_TARGETS)

      # For each architecture supported by this SDK
      foreach(arch ${SWIFT_SDK_${sdk}_ARCHITECTURES})
        # Configure variables for this subdirectory.
        set(VARIANT_SUFFIX "-${SWIFT_SDK_${sdk}_LIB_SUBDIR}-${arch}")
        set(VARIANT_NAME "${name}${VARIANT_SUFFIX}")

        # Map dependencies over to the appropriate variants.
        set(swiftlib_link_libraries)
        foreach(lib ${SWIFTLIB_LINK_LIBRARIES})
          if(TARGET "${lib}${VARIANT_SUFFIX}")
            list(APPEND swiftlib_link_libraries "${lib}${VARIANT_SUFFIX}")
          else()
            list(APPEND swiftlib_link_libraries "${lib}")
          endif()
        endforeach()

        set(swiftlib_module_depends_flattened ${SWIFTLIB_SWIFT_MODULE_DEPENDS})
        if("${sdk}" STREQUAL "OSX")
          list(APPEND swiftlib_module_depends_flattened
              ${SWIFTLIB_SWIFT_MODULE_DEPENDS_OSX})
        elseif("${sdk}" STREQUAL "IOS" OR "${sdk}" STREQUAL "IOS_SIMULATOR")
          list(APPEND swiftlib_module_depends_flattened
              ${SWIFTLIB_SWIFT_MODULE_DEPENDS_IOS})
        elseif("${sdk}" STREQUAL "TVOS" OR "${sdk}" STREQUAL "TVOS_SIMULATOR")
          list(APPEND swiftlib_module_depends_flattened
              ${SWIFTLIB_SWIFT_MODULE_DEPENDS_TVOS})
        elseif("${sdk}" STREQUAL "WATCHOS" OR "${sdk}" STREQUAL "WATCHOS_SIMULATOR")
          list(APPEND swiftlib_module_depends_flattened
              ${SWIFTLIB_SWIFT_MODULE_DEPENDS_WATCHOS})
        endif()

        set(swiftlib_module_dependency_targets)
        foreach(mod ${swiftlib_module_depends_flattened})
          list(APPEND swiftlib_module_dependency_targets
              "swift${mod}${VARIANT_SUFFIX}")
        endforeach()

        set(swiftlib_framework_depends_flattened ${SWIFTLIB_FRAMEWORK_DEPENDS})
        if("${sdk}" STREQUAL "OSX")
          list(APPEND swiftlib_framework_depends_flattened
              ${SWIFTLIB_FRAMEWORK_DEPENDS_OSX})
        elseif("${sdk}" STREQUAL "IOS" OR "${sdk}" STREQUAL "IOS_SIMULATOR" OR "${sdk}" STREQUAL "TVOS" OR "${sdk}" STREQUAL "TVOS_SIMULATOR")
          list(APPEND swiftlib_framework_depends_flattened
              ${SWIFTLIB_FRAMEWORK_DEPENDS_IOS_TVOS})
        endif()

        set(swiftlib_private_link_libraries_targets
            ${swiftlib_module_dependency_targets})
        foreach(lib ${SWIFTLIB_PRIVATE_LINK_LIBRARIES})
          if(TARGET "${lib}${VARIANT_SUFFIX}")
            list(APPEND swiftlib_private_link_libraries_targets
                "${lib}${VARIANT_SUFFIX}")
          else()
            list(APPEND swiftlib_private_link_libraries_targets "${lib}")
          endif()
        endforeach()

        # Collect compiler flags
        set(swiftlib_swift_compile_flags_all ${SWIFTLIB_SWIFT_COMPILE_FLAGS})
        if("${sdk}" STREQUAL "OSX")
          list(APPEND swiftlib_swift_compile_flags_all
              ${SWIFTLIB_SWIFT_COMPILE_FLAGS_OSX})
        elseif("${sdk}" STREQUAL "IOS" OR "${sdk}" STREQUAL "IOS_SIMULATOR")
          list(APPEND swiftlib_swift_compile_flags_all
              ${SWIFTLIB_SWIFT_COMPILE_FLAGS_IOS})
        elseif("${sdk}" STREQUAL "TVOS" OR "${sdk}" STREQUAL "TVOS_SIMULATOR")
          list(APPEND swiftlib_swift_compile_flags_all
              ${SWIFTLIB_SWIFT_COMPILE_FLAGS_TVOS})
        elseif("${sdk}" STREQUAL "WATCHOS" OR "${sdk}" STREQUAL "WATCHOS_SIMULATOR")
          list(APPEND swiftlib_swift_compile_flags_all
              ${SWIFTLIB_SWIFT_COMPILE_FLAGS_WATCHOS})
        endif()

        # Add this library variant.
        _add_swift_library_single(
          ${VARIANT_NAME}
          ${name}
          ${SWIFTLIB_SHARED_keyword}
          ${SWIFTLIB_SOURCES}
          SDK ${sdk}
          ARCHITECTURE ${arch}
          DEPENDS ${SWIFTLIB_DEPENDS}
          LINK_LIBRARIES ${swiftlib_link_libraries}
          FRAMEWORK_DEPENDS ${swiftlib_framework_depends_flattened}
          FRAMEWORK_DEPENDS_WEAK ${SWIFTLIB_FRAMEWORK_DEPENDS_WEAK}
          COMPONENT_DEPENDS ${SWIFTLIB_COMPONENT_DEPENDS}
          FILE_DEPENDS ${SWIFTLIB_FILE_DEPENDS} ${swiftlib_module_dependency_targets}
          C_COMPILE_FLAGS ${SWIFTLIB_C_COMPILE_FLAGS}
          SWIFT_COMPILE_FLAGS ${swiftlib_swift_compile_flags_all}
          LINK_FLAGS ${SWIFTLIB_LINK_FLAGS}
          PRIVATE_LINK_LIBRARIES ${swiftlib_private_link_libraries_targets}
          ${SWIFTLIB_DONT_EMBED_BITCODE_keyword}
          ${SWIFTLIB_API_NOTES_NON_OVERLAY_keyword}
          ${SWIFTLIB_IS_STDLIB_keyword}
          ${SWIFTLIB_IS_STDLIB_CORE_keyword}
          ${SWIFTLIB_IS_SDK_OVERLAY_keyword}
          ${SWIFTLIB_TARGET_LIBRARY_keyword}
          ${SWIFTLIB_HOST_LIBRARY_keyword}
          INSTALL_IN_COMPONENT "${SWIFTLIB_INSTALL_IN_COMPONENT}"
          DEPLOYMENT_VERSION_IOS "${SWIFTLIB_DEPLOYMENT_VERSION_IOS}"
        )

        # Add dependencies on the (not-yet-created) custom lipo target.
        foreach(DEP ${SWIFTLIB_LINK_LIBRARIES})
          if (NOT "${DEP}" STREQUAL "icucore")
            add_dependencies(${VARIANT_NAME}
              "${DEP}-${SWIFT_SDK_${sdk}_LIB_SUBDIR}")
          endif()
        endforeach()

        if (SWIFT_BUILD_STATIC_STDLIB AND SWIFTLIB_IS_STDLIB)
          # Add dependencies on the (not-yet-created) custom lipo target.
          foreach(DEP ${SWIFTLIB_LINK_LIBRARIES})
            if (NOT "${DEP}" STREQUAL "icucore")
              add_dependencies("${VARIANT_NAME}-static"
                "${DEP}-${SWIFT_SDK_${sdk}_LIB_SUBDIR}-static")
            endif()
          endforeach()
        endif()

        # Note this thin library.
        list(APPEND THIN_INPUT_TARGETS ${VARIANT_NAME})
      endforeach()

      # Determine the name of the universal library.
      if(SWIFTLIB_SHARED)
        set(UNIVERSAL_LIBRARY_NAME
          "${SWIFTLIB_DIR}/${SWIFT_SDK_${sdk}_LIB_SUBDIR}/${CMAKE_SHARED_LIBRARY_PREFIX}${name}${CMAKE_SHARED_LIBRARY_SUFFIX}")
      else()
        set(UNIVERSAL_LIBRARY_NAME
          "${SWIFTLIB_DIR}/${SWIFT_SDK_${sdk}_LIB_SUBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${name}${CMAKE_STATIC_LIBRARY_SUFFIX}")
      endif()


      set(lipo_target "${name}-${SWIFT_SDK_${sdk}_LIB_SUBDIR}")
      _add_swift_lipo_target(
          ${lipo_target}
          "${UNIVERSAL_LIBRARY_NAME}"
          ${THIN_INPUT_TARGETS})

      # Cache universal libraries for dependency purposes
      set(UNIVERSAL_LIBRARY_NAMES_${SWIFT_SDK_${sdk}_LIB_SUBDIR}
        ${UNIVERSAL_LIBRARY_NAMES_${SWIFT_SDK_${sdk}_LIB_SUBDIR}}
        ${lipo_target}
        CACHE INTERNAL "UNIVERSAL_LIBRARY_NAMES_${SWIFT_SDK_${sdk}_LIB_SUBDIR}")

      # Determine the subdirectory where this library will be installed.
      set(resource_dir_sdk_subdir "${SWIFT_SDK_${sdk}_LIB_SUBDIR}")

      if("${resource_dir_sdk_subdir}" STREQUAL "")
        message(FATAL_ERROR "internal error: the variable should be non-empty")
      endif()

      if(SWIFTLIB_IS_STDLIB)
        if(SWIFTLIB_SHARED)
          set(resource_dir "swift")
          set(file_permissions
              OWNER_READ OWNER_WRITE OWNER_EXECUTE
              GROUP_READ GROUP_EXECUTE
              WORLD_READ WORLD_EXECUTE)
        else()
          set(resource_dir "swift_static")
          set(file_permissions
              OWNER_READ OWNER_WRITE
              GROUP_READ
              WORLD_READ)
        endif()

        swift_install_in_component("${SWIFTLIB_INSTALL_IN_COMPONENT}"
            FILES "${UNIVERSAL_LIBRARY_NAME}"
            DESTINATION "lib${LLVM_LIBDIR_SUFFIX}/${resource_dir}/${resource_dir_sdk_subdir}"
            PERMISSIONS ${file_permissions})
      endif()

      # If we built static variants of the library, create a lipo target for
      # them.
      set(lipo_target_static)
      if (SWIFT_BUILD_STATIC_STDLIB AND SWIFTLIB_IS_STDLIB)
        set(THIN_INPUT_TARGETS_STATIC)
        foreach(TARGET ${THIN_INPUT_TARGETS})
          list(APPEND THIN_INPUT_TARGETS_STATIC "${TARGET}-static")
        endforeach()

        set(lipo_target_static
            "${name}-${SWIFT_SDK_${sdk}_LIB_SUBDIR}-static")
        set(UNIVERSAL_LIBRARY_NAME
            "${SWIFTSTATICLIB_DIR}/${SWIFT_SDK_${sdk}_LIB_SUBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${name}${CMAKE_STATIC_LIBRARY_SUFFIX}")
        _add_swift_lipo_target(
            ${lipo_target_static}
            "${UNIVERSAL_LIBRARY_NAME}"
            ${THIN_INPUT_TARGETS_STATIC})
        swift_install_in_component("${SWIFTLIB_INSTALL_IN_COMPONENT}"
            FILES "${UNIVERSAL_LIBRARY_NAME}"
            DESTINATION "lib${LLVM_LIBDIR_SUFFIX}/swift_static/${resource_dir_sdk_subdir}"
            PERMISSIONS
              OWNER_READ OWNER_WRITE
              GROUP_READ
              WORLD_READ)
      endif()

      # Add Swift standard library targets as dependencies to the top-level
      # convenience target.
      if(SWIFTLIB_TARGET_LIBRARY)
        foreach(arch ${SWIFT_SDK_${sdk}_ARCHITECTURES})
          set(VARIANT_SUFFIX "-${SWIFT_SDK_${sdk}_LIB_SUBDIR}-${arch}")
          if(TARGET "swift-stdlib${VARIANT_SUFFIX}" AND TARGET "swift-test-stdlib${VARIANT_SUFFIX}")
            add_dependencies("swift-stdlib${VARIANT_SUFFIX}"
                ${lipo_target}
                ${lipo_target_static})
            if(NOT "${name}" STREQUAL "swiftStdlibCollectionUnittest")
              add_dependencies("swift-test-stdlib${VARIANT_SUFFIX}"
                  ${lipo_target}
                  ${lipo_target_static})
            endif()
          endif()
        endforeach()
      endif()
    endforeach()
  else()
    set(sdk "${SWIFT_HOST_VARIANT_SDK}")
    set(arch "${SWIFT_HOST_VARIANT_ARCH}")

    # Collect compiler flags
    set(swiftlib_swift_compile_flags_all ${SWIFTLIB_SWIFT_COMPILE_FLAGS})
    if("${sdk}" STREQUAL "OSX")
      list(APPEND swiftlib_swift_compile_flags_all
        ${SWIFTLIB_SWIFT_COMPILE_FLAGS_OSX})
    elseif("${sdk}" STREQUAL "IOS" OR "${sdk}" STREQUAL "IOS_SIMULATOR")
      list(APPEND swiftlib_swift_compile_flags_all
        ${SWIFTLIB_SWIFT_COMPILE_FLAGS_IOS})
    elseif("${sdk}" STREQUAL "TVOS" OR "${sdk}" STREQUAL "TVOS_SIMULATOR")
      list(APPEND swiftlib_swift_compile_flags_all
        ${SWIFTLIB_SWIFT_COMPILE_FLAGS_TVOS})
    elseif("${sdk}" STREQUAL "WATCHOS" OR "${sdk}" STREQUAL "WATCHOS_SIMULATOR")
      list(APPEND swiftlib_swift_compile_flags_all
        ${SWIFTLIB_SWIFT_COMPILE_FLAGS_WATCHOS})
    endif()

    _add_swift_library_single(
      ${name}
      ${name}
      ${SWIFTLIB_SHARED_keyword}
      ${SWIFTLIB_SOURCES}
      SDK ${sdk}
      ARCHITECTURE ${arch}
      DEPENDS ${SWIFTLIB_DEPENDS}
      LINK_LIBRARIES ${SWIFTLIB_LINK_LIBRARIES}
      FRAMEWORK_DEPENDS ${SWIFTLIB_FRAMEWORK_DEPENDS}
      FRAMEWORK_DEPENDS_WEAK ${SWIFTLIB_FRAMEWORK_DEPENDS_WEAK}
      COMPONENT_DEPENDS ${SWIFTLIB_COMPONENT_DEPENDS}
      FILE_DEPENDS ${SWIFTLIB_FILE_DEPENDS}
      C_COMPILE_FLAGS ${SWIFTLIB_C_COMPILE_FLAGS}
      SWIFT_COMPILE_FLAGS ${swiftlib_swift_compile_flags_all}
      LINK_FLAGS ${SWIFTLIB_LINK_FLAGS}
      PRIVATE_LINK_LIBRARIES ${SWIFTLIB_PRIVATE_LINK_LIBRARIES}
      INTERFACE_LINK_LIBRARIES ${SWIFTLIB_INTERFACE_LINK_LIBRARIES}
      ${SWIFTLIB_DONT_EMBED_BITCODE_keyword}
      ${SWIFTLIB_API_NOTES_NON_OVERLAY_keyword}
      ${SWIFTLIB_IS_STDLIB_keyword}
      ${SWIFTLIB_IS_STDLIB_CORE_keyword}
      ${SWIFTLIB_IS_SDK_OVERLAY_keyword}
      INSTALL_IN_COMPONENT "${SWIFTLIB_INSTALL_IN_COMPONENT}"
      DEPLOYMENT_VERSION_IOS "${SWIFTLIB_DEPLOYMENT_VERSION_IOS}"
      )
  endif()
endfunction()

# Add an executable compiled for a given variant.
#
# Don't use directly, use add_swift_executable and add_swift_target_executable
# instead.
#
# See add_swift_executable for detailed documentation.
#
# Additional parameters:
#   [SDK sdk]
#     SDK to build for.
#
#   [ARCHITECTURE architecture]
#     Architecture to build for.
#
#   [LINK_FAT_LIBRARIES lipo_target1 ...]
#     Fat libraries to link with.
function(_add_swift_executable_single name)
  # Parse the arguments we were given.
  cmake_parse_arguments(SWIFTEXE_SINGLE
    "EXCLUDE_FROM_ALL;DONT_STRIP_NON_MAIN_SYMBOLS;DISABLE_ASLR"
    "SDK;ARCHITECTURE"
    "DEPENDS;COMPONENT_DEPENDS;LINK_LIBRARIES;LINK_FAT_LIBRARIES"
    ${ARGN})

  set(SWIFTEXE_SINGLE_SOURCES ${SWIFTEXE_SINGLE_UNPARSED_ARGUMENTS})

  translate_flag(${SWIFTEXE_SINGLE_EXCLUDE_FROM_ALL}
      "EXCLUDE_FROM_ALL"
      SWIFTEXE_SINGLE_EXCLUDE_FROM_ALL_FLAG)

  # Check arguments.
  if (NOT SWIFTEXE_SINGLE_SDK)
    message(FATAL_ERROR "Should specify an SDK")
  endif()

  if (NOT SWIFTEXE_SINGLE_ARCHITECTURE)
    message(FATAL_ERROR "Should specify an architecture")
  endif()

  # Determine compiler flags.
  set(c_compile_flags)
  set(link_flags)
  
  # Add variant-specific flags.
  _add_variant_c_compile_flags(
    SDK "${SWIFTEXE_SINGLE_SDK}"
    ARCH "${SWIFTEXE_SINGLE_ARCHITECTURE}"
    BUILD_TYPE "${CMAKE_BUILD_TYPE}"
    ENABLE_ASSERTIONS "${LLVM_ENABLE_ASSERTIONS}"
    ANALYZE_CODE_COVERAGE "${SWIFT_ANALYZE_CODE_COVERAGE}"
    RESULT_VAR_NAME c_compile_flags)
  _add_variant_link_flags(
    SDK "${SWIFTEXE_SINGLE_SDK}"
    ARCH "${SWIFTEXE_SINGLE_ARCHITECTURE}"
    BUILD_TYPE "${CMAKE_BUILD_TYPE}"
    ENABLE_ASSERTIONS "${LLVM_ENABLE_ASSERTIONS}"
    ANALYZE_CODE_COVERAGE "${SWIFT_ANALYZE_CODE_COVERAGE}"
    RESULT_VAR_NAME link_flags)

  list(APPEND link_flags
      "-L${SWIFTLIB_DIR}/${SWIFT_SDK_${SWIFTEXE_SINGLE_SDK}_LIB_SUBDIR}")

  if(SWIFTEXE_SINGLE_DISABLE_ASLR)
    list(APPEND link_flags "-Wl,-no_pie")
  endif()

  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
    list(APPEND link_flags
        "-Xlinker" "-rpath"
        "-Xlinker" "@executable_path/../lib/swift/${SWIFT_SDK_${SWIFTEXE_SINGLE_SDK}_LIB_SUBDIR}")
  endif()

  if(SWIFT_ENABLE_GOLD_LINKER AND
     ( "${SWIFTEXE_SINGLE_SDK}" STREQUAL "LINUX" ) )
    # Extend the link_flags for the gold linker.
    list(APPEND link_flags "-fuse-ld=gold")
  endif()

  # Find the names of dependency library targets.
  #
  # We don't add the ${ARCH} to the target suffix because we want to link
  # against fat libraries.
  _list_add_string_suffix(
      "${SWIFTEXE_SINGLE_LINK_FAT_LIBRARIES}"
      "-${SWIFT_SDK_${SWIFTEXE_SINGLE_SDK}_LIB_SUBDIR}"
      SWIFTEXE_SINGLE_LINK_FAT_LIBRARIES_TARGETS)

  handle_swift_sources(
      dependency_target
      SWIFTEXE_SINGLE_SOURCES SWIFTEXE_SINGLE_EXTERNAL_SOURCES ${name}
      DEPENDS
        ${SWIFTEXE_SINGLE_DEPENDS}
        ${SWIFTEXE_SINGLE_LINK_FAT_LIBRARIES_TARGETS}
      SDK ${SWIFTEXE_SINGLE_SDK}
      ARCHITECTURE ${SWIFTEXE_SINGLE_ARCHITECTURE}
      IS_MAIN)
  add_swift_source_group("${SWIFTEXE_SINGLE_EXTERNAL_SOURCES}")

  add_executable(${name}
      ${SWIFTEXE_SINGLE_EXCLUDE_FROM_ALL_FLAG}
      ${SWIFTEXE_SINGLE_SOURCES}
      ${SWIFTEXE_SINGLE_EXTERNAL_SOURCES})

  add_dependencies_multiple_targets(
      TARGETS "${name}"
      DEPENDS
        ${dependency_target}
        ${LLVM_COMMON_DEPENDS}
        ${SWIFTEXE_SINGLE_DEPENDS}
        ${SWIFTEXE_SINGLE_LINK_FAT_LIBRARIES_TARGETS})
  llvm_update_compile_flags("${name}")

  # Convert variables to space-separated strings.
  _list_escape_for_shell("${c_compile_flags}" c_compile_flags)
  _list_escape_for_shell("${link_flags}" link_flags)

  set_property(TARGET ${name} APPEND_STRING PROPERTY
      COMPILE_FLAGS " ${c_compile_flags}")
  set_property(TARGET ${name} APPEND_STRING PROPERTY
      LINK_FLAGS " ${link_flags}")
  if (SWIFT_PARALLEL_LINK_JOBS)
    set_property(TARGET ${name} PROPERTY JOB_POOL_LINK swift_link_job_pool)
  endif()
  set_output_directory(${name}
      BINARY_DIR ${SWIFT_RUNTIME_OUTPUT_INTDIR}
      LIBRARY_DIR ${SWIFT_LIBRARY_OUTPUT_INTDIR})

  target_link_libraries("${name}" ${SWIFTEXE_SINGLE_LINK_LIBRARIES} ${SWIFTEXE_SINGLE_LINK_FAT_LIBRARIES})
  swift_common_llvm_config("${name}" ${SWIFTEXE_SINGLE_COMPONENT_DEPENDS})

  set_target_properties(${name}
      PROPERTIES FOLDER "Swift executables")
endfunction()

# Add an executable for each target variant. Executables are given suffixes
# with the variant SDK and ARCH.
#
# See add_swift_executable for detailed documentation.
#
# Additional parameters:
#   [LINK_FAT_LIBRARIES lipo_target1 ...]
#     Fat libraries to link with.
function(add_swift_target_executable name)
  # Parse the arguments we were given.
  cmake_parse_arguments(SWIFTEXE_TARGET
    "EXCLUDE_FROM_ALL;DONT_STRIP_NON_MAIN_SYMBOLS;DISABLE_ASLR;BUILD_WITH_STDLIB"
    ""
    "DEPENDS;COMPONENT_DEPENDS;LINK_FAT_LIBRARIES"
    ${ARGN})

  set(SWIFTEXE_TARGET_SOURCES ${SWIFTEXE_TARGET_UNPARSED_ARGUMENTS})

  translate_flag(${SWIFTEXE_TARGET_EXCLUDE_FROM_ALL}
      "EXCLUDE_FROM_ALL"
      SWIFTEXE_TARGET_EXCLUDE_FROM_ALL_FLAG)
  translate_flag(${SWIFTEXE_TARGET_DONT_STRIP_NON_MAIN_SYMBOLS}
      "DONT_STRIP_NON_MAIN_SYMBOLS"
      SWIFTEXE_TARGET_DONT_STRIP_NON_MAIN_SYMBOLS_FLAG)
  translate_flag(${SWIFTEXE_TARGET_DISABLE_ASLR}
      "DISABLE_ASLR"
      SWIFTEXE_DISABLE_ASLR_FLAG)

  # All Swift executables depend on the standard library.
  list(APPEND SWIFTEXE_TARGET_LINK_FAT_LIBRARIES swiftCore)
  # All Swift executables depend on the swiftSwiftOnoneSupport library.
  list(APPEND SWIFTEXE_TARGET_DEPENDS swiftSwiftOnoneSupport)

  if(NOT "${SWIFT_BUILD_STDLIB}")
    list(REMOVE_ITEM SWIFTEXE_TARGET_LINK_FAT_LIBRARIES
        swiftCore)
  endif()

  foreach(sdk ${SWIFT_SDKS})
    foreach(arch ${SWIFT_SDK_${sdk}_ARCHITECTURES})
      set(VARIANT_SUFFIX "-${SWIFT_SDK_${sdk}_LIB_SUBDIR}-${arch}")
      set(VARIANT_NAME "${name}${VARIANT_SUFFIX}")

      set(SWIFTEXE_TARGET_EXCLUDE_FROM_ALL_FLAG_CURRENT
          ${SWIFTEXE_TARGET_EXCLUDE_FROM_ALL_FLAG})
      if(NOT "${VARIANT_SUFFIX}" STREQUAL "${SWIFT_PRIMARY_VARIANT_SUFFIX}")
        # By default, don't build executables for target SDKs to avoid building
        # target stdlibs.
        set(SWIFTEXE_TARGET_EXCLUDE_FROM_ALL_FLAG_CURRENT "EXCLUDE_FROM_ALL")
      endif()

      if(SWIFTEXE_TARGET_BUILD_WITH_STDLIB)
        add_dependencies("swift-test-stdlib${VARIANT_SUFFIX}" ${VARIANT_NAME})
      endif()

      # Don't add the ${arch} to the suffix.  We want to link against fat
      # libraries.
      _list_add_string_suffix(
          "${SWIFTEXE_TARGET_DEPENDS}"
          "-${SWIFT_SDK_${sdk}_LIB_SUBDIR}"
          SWIFTEXE_TARGET_DEPENDS_with_suffix)
      _add_swift_executable_single(
          ${VARIANT_NAME}
          ${SWIFTEXE_TARGET_SOURCES}
          DEPENDS ${SWIFTEXE_TARGET_DEPENDS_with_suffix}
          COMPONENT_DEPENDS ${SWIFTEXE_TARGET_COMPONENT_DEPENDS}
          SDK "${sdk}"
          ARCHITECTURE "${arch}"
          LINK_FAT_LIBRARIES ${SWIFTEXE_TARGET_LINK_FAT_LIBRARIES}
          ${SWIFTEXE_TARGET_EXCLUDE_FROM_ALL_FLAG_CURRENT}
          ${SWIFTEXE_TARGET_DONT_STRIP_NON_MAIN_SYMBOLS_FLAG}
          ${SWIFTEXE_DISABLE_ASLR_FLAG})
    endforeach()
  endforeach()
endfunction()

# Add an executable for the host machine.
#
# Usage:
#   add_swift_executable(name
#     [DEPENDS dep1 ...]
#     [COMPONENT_DEPENDS comp1 ...]
#     [FILE_DEPENDS target1 ...]
#     [LINK_LIBRARIES target1 ...]
#     [EXCLUDE_FROM_ALL]
#     [DONT_STRIP_NON_MAIN_SYMBOLS]
#     [DISABLE_ASLR]
#     source1 [source2 source3 ...])
#
#   name
#     Name of the executable (e.g., swift).
#
#   LIBRARIES
#     Libraries this executable depends on, without variant suffixes.
#
#   COMPONENT_DEPENDS
#     LLVM components this executable depends on.
#
#   FILE_DEPENDS
#     Additional files this executable depends on.
#
#   LINK_LIBRARIES
#     Libraries to link with.
#
#   EXCLUDE_FROM_ALL
#     Whether to exclude this executable from the ALL_BUILD target.
#
#   DONT_STRIP_NON_MAIN_SYMBOLS
#     Should we not strip non main symbols.
#
#   DISABLE_ASLR
#     Should we compile with -Wl,-no_pie so that ASLR is disabled?
#
#   source1 ...
#     Sources to add into this executable.
#
# Note:
#   Host executables are not given a variant suffix. To build an executable for
#   each SDK and ARCH variant, use add_swift_target_executable.
function(add_swift_executable name)
  # Parse the arguments we were given.
  cmake_parse_arguments(SWIFTEXE
    "EXCLUDE_FROM_ALL;DONT_STRIP_NON_MAIN_SYMBOLS;DISABLE_ASLR"
    ""
    "DEPENDS;COMPONENT_DEPENDS;LINK_LIBRARIES"
    ${ARGN})

  translate_flag(${SWIFTEXE_EXCLUDE_FROM_ALL}
      "EXCLUDE_FROM_ALL"
      SWIFTEXE_EXCLUDE_FROM_ALL_FLAG)
  translate_flag(${SWIFTEXE_DONT_STRIP_NON_MAIN_SYMBOLS}
      "DONT_STRIP_NON_MAIN_SYMBOLS"
      SWIFTEXE_DONT_STRIP_NON_MAIN_SYMBOLS_FLAG)
  translate_flag(${SWIFTEXE_DISABLE_ASLR}
      "DISABLE_ASLR"
      SWIFTEXE_DISABLE_ASLR_FLAG)

  set(SWIFTEXE_SOURCES ${SWIFTEXE_UNPARSED_ARGUMENTS})

  _add_swift_executable_single(
      ${name}
      ${SWIFTEXE_SOURCES}
      DEPENDS ${SWIFTEXE_DEPENDS}
      COMPONENT_DEPENDS ${SWIFTEXE_COMPONENT_DEPENDS}
      LINK_LIBRARIES ${SWIFTEXE_LINK_LIBRARIES}
      SDK ${SWIFT_HOST_VARIANT_SDK}
      ARCHITECTURE ${SWIFT_HOST_VARIANT_ARCH}
      ${SWIFTEXE_EXCLUDE_FROM_ALL_FLAG}
      ${SWIFTEXE_DONT_STRIP_NON_MAIN_SYMBOLS_FLAG}
      ${SWIFTEXE_DISABLE_ASLR_FLAG})
endfunction()
