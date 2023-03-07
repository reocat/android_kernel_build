#include <linux/kernel.h>

int debug_foo(void)  {
	printk(KERN_DEBUG "Running debug code!\n");
	return 1;
}
