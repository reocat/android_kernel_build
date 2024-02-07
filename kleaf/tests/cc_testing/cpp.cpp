
#include <vector>

#include <pthread.h>

class MyClass {
 private:
  std::vector<int> myvec_;
};

void* routine(void*) {return nullptr;}

int main() {
  pthread_t pt;
  pthread_create(&pt, nullptr, &routine, nullptr);
  return 0;
}
