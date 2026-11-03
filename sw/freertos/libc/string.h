/*
 * The toolchain ships no C library headers; these are the routines the
 * FreeRTOS kernel uses, implemented in ../string.c.
 */
#ifndef ANV32_STRING_H
#define ANV32_STRING_H

#include <stddef.h>

void *memset(void *dst, int c, size_t n);
void *memcpy(void *dst, const void *src, size_t n);

#endif
