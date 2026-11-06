// The few libc routines GCC may call on its own (struct copies, zeroing
// local arrays) even in freestanding code. The optimize attribute stops GCC
// from turning these loops back into calls to themselves.
#include <stddef.h>

#define NO_LIBCALL __attribute__((optimize("no-tree-loop-distribute-patterns")))

NO_LIBCALL void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char       *d = dst;
    const unsigned char *s = src;
    while (n--)
        *d++ = *s++;
    return dst;
}

NO_LIBCALL void *memset(void *dst, int c, size_t n)
{
    unsigned char *d = dst;
    while (n--)
        *d++ = (unsigned char)c;
    return dst;
}
