// MSL source -> metallib (AIR-shaped LLVM bitcode) for the xef-mtlc pipeline.
#pragma once
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace mtlc::msl {
bool compile_msl(const std::string& source, std::vector<uint8_t>& metallib, std::string& err);
std::vector<uint8_t> make_metallib(const std::vector<std::pair<std::string, uint8_t>>& fns, const std::vector<uint8_t>& bc);
}
