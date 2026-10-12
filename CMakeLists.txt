cmake_minimum_required(VERSION 3.20)
project(xef CXX ASM)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "-O0 -g")
add_compile_options(-Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers
                    -fno-exceptions -fno-rtti -march=x86-64-v2)
include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_ok OUTPUT ipo_msg)
if(ipo_ok AND CMAKE_BUILD_TYPE STREQUAL "Release")
  set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
endif()

file(GLOB_RECURSE XEF_SRC CONFIGURE_DEPENDS src/*.cpp src/*.S)
add_executable(xef ${XEF_SRC})
target_include_directories(xef PRIVATE src)
target_link_libraries(xef PRIVATE pthread ${CMAKE_DL_LIBS})
