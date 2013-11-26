# #  -*- mode: cmake -*-

#
# ExternalProject_YAJL
#    Build the YAJL project
#
#

# --- Setup

# Projects/targets dependent on YAJL need this target
set(YAJL_BUILD_TARGET yajl)

# Define the version and archive file
set(EP_YAJL_VERSION_MAJOR 2)
set(EP_YAJL_VERSION_MINOR 0)
set(EP_YAJL_VERSION_PATCH 4)
set(EP_YAJL_VERSION ${EP_YAJL_VERSION_MAJOR}.${EP_YAJL_VERSION_MINOR}.${EP_YAJL_VERSION_PATCH})
set(EP_YAJL_ARCHIVE_FILE   yajl-${EP_YAJL_VERSION}.tar.gz)
set(EP_YAJL_MD5_SUM        204ed61f844ca49009f5edefa405f3e7) 


# Useful utility to build *FLAGS strings
include(BuildWhitespaceString)

# Make CMake files to run scripts and exit correctly 
include(MakeCMakeCommandFile)

# Construct library names
include(BuildLibraryName)

# ExternalProject directories, file and log settings
set(yajl_url_file     ${TruchasExternal_ARCHIVE_DIR}/${EP_YAJL_ARCHIVE_FILE})
set(yajl_prefix_dir   ${TruchasExternal_BINARY_DIR}/yajl)
set(yajl_source_dir   ${yajl_prefix_dir}/yajl-${EP_YAJL_VERSION}-source)
set(yajl_stamp_dir    ${yajl_prefix_dir}/yajl-timestamps)
set(yajl_tmp_dir      ${yajl_prefix_dir}/yajl-tmp)
set(yajl_install_dir  ${TruchasExternal_INSTALL_PREFIX})

# --- Add the -fPIC or -PIC (Position in code flag)
include(FindPICFlag)
find_pic_flag(yajl_pic_flag)
set(yajl_c_flags "${CMAKE_C_FLAGS} ${yajl_pic_flag}")

# --- Add the external project

ExternalProject_Add(${YAJL_BUILD_TARGET}
                    # -- Project directories
                    PREFIX      ${yajl_prefix_dir}   
                    TMP_DIR     ${yajl_tmp_dir}     
                    STAMP_DIR   ${yajl_stamp_dir}
                    SOURCE_DIR  ${yajl_source_dir}
		    #INSTALL_DIR ${yajl_install_dir}
		    # -- Archive file definitions
                    URL          ${yajl_url_file}
                    URL_MD5      ${EP_YAJL_MD5_SUM}   
                    # -- Configure (CMake)
		    CMAKE_CACHE_ARGS
		          ${TruchasExternal_CMAKE_COMPILER_ARGS}
			  ${TruchasExternal_CMAKE_BUILD_ARGS}
			  -DCMAKE_C_FLAGS:STRING=${yajl_c_flags}
	            CMAKE_ARGS
		          -DCMAKE_INSTALL_PREFIX:PATH=${yajl_install_dir}
                    # -- Output control
                    ${yajl_logging})

# --- Set the variables for other targets that need YAJL

# Version
set(YAJL_VERSION ${EP_YAJL_VERSION})
set(YAJL_VERSION_STRING ${EP_YAJL_VERSION})

# Include directory
set(YAJL_INCLUDE_DIR ${yajl_install_dir}/include)
set(YAJL_INCLUDE_DIRS ${YAJL_INCLUDE_DIRS})

# Library
build_library_name(yajl library APPEND_PATH ${yajl_install_dir}/lib)
set(YAJL_LIBRARY ${library})
set(YAJL_LIBRARIES ${library})
