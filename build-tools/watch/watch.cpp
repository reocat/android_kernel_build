#include <stdint.h>
#include <stdio.h>
#include <sys/inotify.h>
#include <unistd.h>

#include <iostream>
#include <string_view>
#include <vector>
#include <map>

namespace {

std::string join(const std::vector<std::string>& strings, const std::string& sep) {
  if (strings.empty()) {
    return "";
  }
  auto ret = strings[0];
  for (size_t i = 1; i < strings.size(); i++) {
    ret += sep + strings[i];
  }
  return ret;
}

uint32_t parse_event(std::string_view event_name) {
  if (event_name == "access") {
    return IN_ACCESS;
  }
  if (event_name == "open") {
    return IN_OPEN;
  }
  std::cerr << "ERROR: Unrecognized event." << std::endl;
  exit(EXIT_FAILURE);
}

std::string event_to_string(uint32_t event) {
  std::vector<std::string> events;
  if (event & IN_ACCESS) {
    events.push_back("access");
    event &= ~IN_ACCESS;
  }
  if (event & IN_OPEN) {
    events.push_back("open");
    event &= ~IN_OPEN;
  }
  if (event) {
    events.push_back(std::to_string(event));
  }
  return join(events, "+");
}

template <typename Closer>
class unique_fd {
 public:
  unique_fd(int fd, Closer closer) : fd_(fd), closer_(std::move(closer)) {}
  ~unique_fd() {
    if (!ok()) return;
    closer_(fd_);
  }
  bool ok() const { return fd_ != -1; }
  int operator*() const { return fd_; }

 private:
  int fd_;
  Closer closer_;
};

}  // namespace

int main(int argc, char** argv) {
  uint32_t events = 0;
  std::vector<std::string> files;
  int opt = 0;
  while ((opt = getopt(argc, argv, "e:")) != -1) {
    switch (opt) {
      case 'e':
        events |= parse_event(optarg);
        break;
      default: /* '?' */
        perror("Usage: watch [-e <event> [...]] [file [...]]");
        exit(EXIT_FAILURE);
    }
  }
  for (int index = optind; index < argc; index++) {
    files.push_back(argv[index]);
  }

  if (events == 0) events = IN_ALL_EVENTS;

  perror(("events: " + std::to_string(events)).c_str());

  unique_fd fd(inotify_init1(IN_CLOEXEC), close);
  perror(("init fd " + std::to_string(*fd)).c_str());
  if (!fd.ok()) {
    perror("inotify_init1");
    exit(EXIT_FAILURE);
  }

  std::map<int, std::string> wd_to_name;

  for (const auto& file : files) {
    int wd = inotify_add_watch(*fd, file.c_str(), events);
    if (wd == -1) {
      perror(("inotify_add_watch " + file).c_str());
      exit(EXIT_FAILURE);
    }
    wd_to_name[wd] = file;
  }

  std::vector<uint8_t> buf(4096);
  while (true) {
    int len = read(*fd, buf.data(), buf.size() * sizeof(uint8_t));
    if (len == -1) {
      if (errno == EAGAIN) {
        continue;
      }
      if (errno == EINTR) {
        break; // better ways to exit the program?
      }
      perror(("read() inotify fd " + std::to_string(*fd)).c_str());
      exit(EXIT_FAILURE);
    }
    if (len <= 0) {
      perror("WARNING: read() gets zero bytes!");
      break;
    }

    uint8_t *ptr = nullptr;
    const inotify_event* event = nullptr;
    for (ptr = buf.data(), event = reinterpret_cast<const inotify_event*>(ptr);
         ptr < buf.data() + len; ptr += sizeof(inotify_event) + event->len) {

      std::cout << event_to_string(event->mask) << ": " << wd_to_name.at(event->wd) << std::endl;
    }
  }

  return 0;
}
