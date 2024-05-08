// Copyright (C) 2024 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Helper wrapper for hermetic tools to wrap arguments.
//
// This roughly equivalent to:
// 1. readlink /proc/self/exe, then dirname multiple times to determine the path
//    internal_dir =
//    <execroot>/build/kernel/hermetic-tools/kleaf_internal_do_not_use
// 2. toolname = basename($0)
// 3. call <internal_dir>/<tool_name> $@ $(cat
// <internal_dir>/<tool_name>_args.txt)
//
// This is a C++ binary instead of a shell / Python script so that
// /proc/self/exe is a proper anchor to find internal_dir. If this were a
// script, /proc/self/exe would be the path to the interpreter.
// This also avoids using any hermetic tools in order to determine the path to
// them.

#include <linux/limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#include <optional>
#include <string>
#include <vector>

namespace {

// <execroot>/build/kernel/hermetic-tools/kleaf_internal_do_not_use
std::optional<std::filesystem::path> get_kleaf_internal_dir() {
  std::string buf(PATH_MAX, '\0');

  ssize_t bufsize = readlink("/proc/self/exe", buf.data(), buf.size());
  if (bufsize == -1) {
    perror("ERROR: readlink /proc/self/exe");
    return std::nullopt;
  }
  // <execroot>/build/kernel/kleaf/impl/arg_wrapper
  std::filesystem::path realpath(buf.substr(0, bufsize));

  return realpath.parent_path().parent_path().parent_path() / "hermetic-tools" /
         "kleaf_internal_do_not_use";
}

// Loads <tool_name>_args.txt
std::optional<std::vector<std::string>> load_arg_file(
    const std::filesystem::path& path) {
  std::ifstream ifs(path);
  if (!ifs) {
    fprintf(stderr, "Unable to open %s", path.c_str());
    return std::nullopt;
  }
  std::vector<std::string> args;
  for (std::string arg; std::getline(ifs, arg);) {
    args.push_back(arg);
  }
  return args;
}

class ArgWrapper {
 public:
  static std::optional<ArgWrapper> Make(
      const std::filesystem::path& real_binary,
      const std::filesystem::path& internal_dir, const std::string& toolname,
      int argc, char* argv[]) {
    std::vector<std::string> new_argv;
    new_argv.push_back(real_binary);

    auto arg_file = internal_dir / (toolname + "_args.txt");
    auto preset_args = load_arg_file(arg_file);
    if (!preset_args.has_value()) {
      return std::nullopt;
    }
    for (int i = 1; i < argc; i++) {
      new_argv.push_back(argv[i]);
    }
    for (const auto& arg : *preset_args) {
      new_argv.push_back(arg);
    }
    return ArgWrapper(real_binary, new_argv);
  }

  int Exec() {
    std::vector<char*> cargv;
    for (auto& arg : argv_) {
      cargv.push_back(arg.data());
    }
    cargv.push_back(nullptr);
    return execv(real_binary_.c_str(), cargv.data());
  }

 private:
  ArgWrapper(std::filesystem::path real_binary, std::vector<std::string> argv)
      : real_binary_(std::move(real_binary)), argv_(std::move(argv)) {}

  std::filesystem::path real_binary_;
  std::vector<std::string> argv_;
};

}  // namespace

int main(int argc, char* argv[]) {
  auto internal_dir = get_kleaf_internal_dir();
  if (!internal_dir.has_value()) {
    return 1;
  }

  if (argc <= 0) {
    fprintf(stderr, "ERROR: argc == %d <= 0\n", argc);
    return 1;
  }
  std::string toolname(std::filesystem::path(argv[0]).filename());

  auto real_binary = (*internal_dir) / toolname;

  auto arg_wrapper =
      ArgWrapper::Make(real_binary, *internal_dir, toolname, argc, argv);

  if (-1 == arg_wrapper->Exec()) {
    // Use fprintf instead of std::cerr::operator<< to avoid modifying errno
    // before the message is printed.
    fprintf(stderr, "ERROR: execv %s: %s\n", real_binary.c_str(),
            strerror(errno));
    return 1;
  }
  perror("ERROR: execv returns!");
  return 1;
}
