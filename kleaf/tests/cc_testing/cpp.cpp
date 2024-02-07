
#include <vector>

#include <pthread.h>

class MyClass {
 private:
  std::vector<int> myvec_;
};

void* routine(void*) {
  printf("child thread!\n");
  return nullptr;
}

int main() {
  pthread_t pt;
  pthread_create(&pt, nullptr, &routine, nullptr);
  printf("main thread!\n");
  pthread_join(pt, nullptr);
  return 0;
}
