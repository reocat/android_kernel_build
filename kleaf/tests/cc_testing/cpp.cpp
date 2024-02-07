
#include <pthread.h>

#include <vector>

class MyClass {
 private:
  std::vector<int> myvec_;
};

void* routine(void*) { return nullptr; }

static void foo() {
  pthread_t pt;
  pthread_create(&pt, nullptr, &routine, nullptr);
}

int main() {
  foo();
  return 0;
}
