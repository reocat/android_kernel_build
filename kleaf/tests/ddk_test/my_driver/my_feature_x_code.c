#include <linux/kernel.h>

int debug_foo(void)  {
	printk(KERN_DEBUG "Running feature x code!\n");
	return 1;
}
