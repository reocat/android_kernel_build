#include <linux/module.h>
#include <linux/kernel.h>

#include "my_public_header.h"
#include "my_private_header.h"

int foo(void)
{
	printk(KERN_INFO "Welcome to my driver!\n");
	return 0;
}

int init_module(void)
{
	return 0;
}

void cleanup_module(void)
{
	printk(KERN_INFO "Goodbye!\n");
}

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("my driver");
