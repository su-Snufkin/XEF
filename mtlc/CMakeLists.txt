# xef-mtlc: Metal AIR -> Vulkan SPIR-V compiler (separate process, links LLVM)
find_package(LLVM REQUIRED CONFIG)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(MTLC_STDLIB ${CMAKE_CURRENT_SOURCE_DIR}/msl/include/metal_stdlib)
add_custom_command(OUTPUT ${MTLC_STDLIB}
  COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/msl/gen_metal_stdlib.py
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/msl/gen_metal_stdlib.py)
add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/metal_stdlib_data.inc
  COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/msl/embed.py ${MTLC_STDLIB} ${CMAKE_CURRENT_BINARY_DIR}/metal_stdlib_data.inc
  DEPENDS ${MTLC_STDLIB} ${CMAKE_CURRENT_SOURCE_DIR}/msl/embed.py)
add_executable(xef-mtlc main.cpp compile.cpp prepare.cpp memlower.cpp structurize.cpp intlegal.cpp emit.cpp emit_air.cpp msl/frontend.cpp
  ${CMAKE_CURRENT_BINARY_DIR}/metal_stdlib_data.inc)
target_include_directories(xef-mtlc PRIVATE ${LLVM_INCLUDE_DIRS} ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})
separate_arguments(LLVM_DEFS NATIVE_COMMAND ${LLVM_DEFINITIONS})
target_compile_definitions(xef-mtlc PRIVATE ${LLVM_DEFS})
target_compile_options(xef-mtlc PRIVATE -Wno-unused-function)
if(LLVM_LINK_LLVM_DYLIB)
  target_link_libraries(xef-mtlc PRIVATE clang-cpp LLVM SPIRV-Tools-shared)
else()
  llvm_map_components_to_libnames(MTLC_LLVM_LIBS core bitreader passes transformutils scalaropts ipo instcombine analysis support)
  target_link_libraries(xef-mtlc PRIVATE ${MTLC_LLVM_LIBS} SPIRV-Tools-shared)
endif()
