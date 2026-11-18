// SPDX-License-Identifier: GPL-2.0-only
/*
 * zmbuf: physically contiguous, uncached DMA buffers for PL masters (AXI HP/ACP ports) on the ZYNQ MINI.
 * A tiny replacement for the out-of-tree Xilinx xlnk driver: /dev/zmbuf
 *   ioctl ZMBUF_ALLOC {size in, phys out}: allocates with dma_alloc_coherent (CMA) and returns the physical address
 *   mmap(fd, offset = physical address, length)  maps that buffer into user space (write-combined, no cache maintenance needed)
 *   ioctl ZMBUF_FREE  {phys}                   frees it; everything is also freed when the file is closed
 */
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/slab.h>

struct zm_req { __u64 size; __u64 phys; };
#define ZMBUF_ALLOC _IOWR('Z', 1, struct zm_req)
#define ZMBUF_FREE  _IOW('Z', 2, struct zm_req)

struct zm_buf { struct list_head node; void *cpu; dma_addr_t dma; size_t size; };
struct zm_file { struct list_head bufs; struct mutex lock; };
static struct miscdevice zm_dev;

static int zm_open(struct inode *i, struct file *f)
{
	struct zm_file *z = kzalloc(sizeof(*z), GFP_KERNEL);
	if (!z) return -ENOMEM;
	INIT_LIST_HEAD(&z->bufs); mutex_init(&z->lock); f->private_data = z;
	return 0;
}

static void zm_free(struct zm_buf *b)
{
	dma_free_coherent(zm_dev.this_device, b->size, b->cpu, b->dma);
	list_del(&b->node); kfree(b);
}

static int zm_release(struct inode *i, struct file *f)
{
	struct zm_file *z = f->private_data; struct zm_buf *b, *n;
	list_for_each_entry_safe(b, n, &z->bufs, node) zm_free(b);
	kfree(z); return 0;
}

static struct zm_buf *zm_find(struct zm_file *z, u64 phys)
{
	struct zm_buf *b;
	list_for_each_entry(b, &z->bufs, node) if (phys >= b->dma && phys < b->dma + b->size) return b;
	return NULL;
}

static long zm_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
	struct zm_file *z = f->private_data; struct zm_req r; struct zm_buf *b; long ret = 0;
	if (copy_from_user(&r, (void __user *)arg, sizeof(r))) return -EFAULT;
	mutex_lock(&z->lock);
	switch (cmd) {
	case ZMBUF_ALLOC:
		if (!r.size || r.size > (256ull << 20)) { ret = -EINVAL; break; }
		b = kzalloc(sizeof(*b), GFP_KERNEL);
		if (!b) { ret = -ENOMEM; break; }
		b->size = PAGE_ALIGN(r.size);
		b->cpu = dma_alloc_coherent(zm_dev.this_device, b->size, &b->dma, GFP_KERNEL);
		if (!b->cpu) { kfree(b); ret = -ENOMEM; break; }
		list_add(&b->node, &z->bufs);
		r.phys = b->dma;
		if (copy_to_user((void __user *)arg, &r, sizeof(r))) ret = -EFAULT;
		break;
	case ZMBUF_FREE:
		b = zm_find(z, r.phys);
		if (b && b->dma == r.phys) zm_free(b); else ret = -ENOENT;
		break;
	default: ret = -ENOTTY;
	}
	mutex_unlock(&z->lock);
	return ret;
}

static int zm_mmap(struct file *f, struct vm_area_struct *vma)
{
	struct zm_file *z = f->private_data; struct zm_buf *b; u64 phys = (u64)vma->vm_pgoff << PAGE_SHIFT; int ret = -EINVAL;
	mutex_lock(&z->lock);
	b = zm_find(z, phys);
	if (b && b->dma == phys && vma->vm_end - vma->vm_start <= b->size) {
		vma->vm_pgoff = 0;
		ret = dma_mmap_coherent(zm_dev.this_device, vma, b->cpu, b->dma, b->size);
	}
	mutex_unlock(&z->lock);
	return ret;
}

static const struct file_operations zm_fops = {
	.owner = THIS_MODULE, .open = zm_open, .release = zm_release, .unlocked_ioctl = zm_ioctl, .compat_ioctl = zm_ioctl, .mmap = zm_mmap,
};
static struct miscdevice zm_dev = { .minor = MISC_DYNAMIC_MINOR, .name = "zmbuf", .fops = &zm_fops, .mode = 0600 };

static int __init zm_init(void)
{
	int r = misc_register(&zm_dev);
	if (r) return r;
	return dma_coerce_mask_and_coherent(zm_dev.this_device, DMA_BIT_MASK(32));
}
static void __exit zm_exit(void) { misc_deregister(&zm_dev); }
module_init(zm_init); module_exit(zm_exit);
MODULE_LICENSE("GPL"); MODULE_DESCRIPTION("Contiguous uncached DMA buffers for PL masters"); MODULE_AUTHOR("ZYNQ MINI open flow");
