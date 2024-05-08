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
// 2. tool_name = basename($0)
// 3. call <internal_dir>/<tool_name> $@ \\
//      $(cat <internal_dir>/<tool_name>_args.txt)
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
#include <iostream>
#include <optional>
#include <string>
#include <vector>

namespace {

// Inspired by android-base ErrnoError, but with reduced functionality.
class DieErrorHelper {
 public:
  // Save errno on construction to prevent the evaluation of |thing| or
  // operator<< from modifying it.
  DieErrorHelper(bool append_errno)
      : errno_(append_errno ? std::make_optional(errno) : std::nullopt) {}
  template <typename T>
  DieErrorHelper& operator<<(const T& thing) {
    std::cerr << thing;
    return (*this);
  }
  [[noreturn]] ~DieErrorHelper() {
    if (errno_.has_value()) {
      std::cerr << ": " << strerror(*errno_) << std::endl;
    }
    exit(1);
  }

 private:
  std::optional<int> errno_;
};

DieErrorHelper die() {
  return DieErrorHelper(false);
}

DieErrorHelper die_error() {
  return DieErrorHelper(true);
}

// <execroot>/build/kernel/hermetic-tools/kleaf_internal_do_not_use
std::filesystem::path get_kleaf_internal_dir() {
  std::error_code ec;
  auto my_path = std::filesystem::read_symlink("/proc/self/exe", ec);
  if (ec.value() != 0) {
    die() << "ERROR: read_symlink /proc/self/exe: " << ec.message();
  }
  return my_path.parent_path().parent_path().parent_path() / "hermetic-tools" /
         "kleaf_internal_do_not_use";
}

// Loads <tool_name>_args.txt from hermetic_tools.extra_args
std::vector<std::string> load_arg_file(const std::filesystem::path& path) {
  std::ifstream ifs(path);
  if (ifs.fail()) {
    die_error() << "Unable to open " << path;
  }
  std::vector<std::string> args;
  for (std::string arg; std::getline(ifs, arg);) {
    args.push_back(arg);
  }
  return args;
}

// Helper class that manages the constructed argv.
class ArgWrapper : public std::vector<std::string> {
 public:
  [[noreturn]] void Exec(const std::filesystem::path& executable) {
    std::vector<char*> cargv;
    for (auto& arg : (*this)) {
      cargv.push_back(arg.data());
    }
    cargv.push_back(nullptr);

    if (-1 != execv(executable.c_str(), cargv.data())) {
      die_error() << "ERROR: execv: " << executable;
    }
    die() << "ERROR: execv returns!";
  }
};

}  // namespace

int main(int argc, char* argv[]) {
  auto internal_dir = get_kleaf_internal_dir();

  if (argc < 1) {
    die() << "ERROR: argc == " << argc << " < 1";
  }
  std::string tool_name(std::filesystem::path(argv[0]).filename());

  // The actual executable we are going to call.
  auto real_executable = internal_dir / tool_name;

  ArgWrapper new_argv;
  new_argv.push_back(real_executable);

  for (int i = 1; i < argc; i++) {
    new_argv.push_back(argv[i]);
  }

  auto extra_args_file = internal_dir / (tool_name + "_args.txt");
  auto preset_args = load_arg_file(extra_args_file);
  new_argv.insert(new_argv.end(), preset_args.begin(), preset_args.end());

  new_argv.Exec(real_executable);
}
