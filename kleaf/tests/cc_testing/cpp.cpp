
#include <vector>

#include <pthread.h>

class MyClass {
 private:
  std::vector<int> myvec_;
};

void* routine(void*) {return nullptr;}

void foo() {
  pthread_t pt;
  pthread_create(&pt, nullptr, &routine, nullptr);
}

