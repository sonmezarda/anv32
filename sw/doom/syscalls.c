/*
 * Just enough of a POSIX layer for picolibc: console output, a read-only
 * file for the IWAD that is linked into the image, and exit.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "platform.h"

#define WAD_FD 3

extern const char doom_wad_start[];
extern const char doom_wad_end[];

static int    wad_open;
static size_t wad_pos;

static int console_putc(char c, FILE *file)
{
    (void)file;
    PLATFORM_PUTC = (uint8_t)c;
    return (uint8_t)c;
}

static FILE console = FDEV_SETUP_STREAM(console_putc, NULL, NULL, _FDEV_SETUP_WRITE);

FILE *const stdin  = &console;
FILE *const stdout = &console;
FILE *const stderr = &console;

static size_t wad_size(void)
{
    return (size_t)(doom_wad_end - doom_wad_start);
}

static int is_wad_path(const char *path)
{
    const char *name = strrchr(path, '/');

    name = name ? name + 1 : path;
    return strcasecmp(name, "doom1.wad") == 0;
}

int open(const char *path, int flags, ...)
{
    if (!is_wad_path(path) || (flags & O_ACCMODE) != O_RDONLY || wad_open) {
        errno = ENOENT;
        return -1;
    }
    wad_open = 1;
    wad_pos = 0;
    return WAD_FD;
}

int close(int fd)
{
    if (fd == WAD_FD && wad_open) {
        wad_open = 0;
        return 0;
    }
    errno = EBADF;
    return -1;
}

ssize_t read(int fd, void *buf, size_t count)
{
    size_t left;

    if (fd != WAD_FD || !wad_open) {
        errno = EBADF;
        return -1;
    }
    left = wad_size() - wad_pos;
    if (count > left) {
        count = left;
    }
    memcpy(buf, doom_wad_start + wad_pos, count);
    wad_pos += count;
    return (ssize_t)count;
}

off_t lseek(int fd, off_t offset, int whence)
{
    off_t base;

    if (fd != WAD_FD || !wad_open) {
        errno = EBADF;
        return -1;
    }
    switch (whence) {
    case SEEK_SET: base = 0; break;
    case SEEK_CUR: base = (off_t)wad_pos; break;
    case SEEK_END: base = (off_t)wad_size(); break;
    default: errno = EINVAL; return -1;
    }
    if (base + offset < 0 || (size_t)(base + offset) > wad_size()) {
        errno = EINVAL;
        return -1;
    }
    wad_pos = (size_t)(base + offset);
    return (off_t)wad_pos;
}

ssize_t write(int fd, const void *buf, size_t count)
{
    const char *p = buf;

    if (fd != STDOUT_FILENO && fd != STDERR_FILENO) {
        errno = EBADF;
        return -1;
    }
    for (size_t i = 0; i < count; i++) {
        PLATFORM_PUTC = (uint8_t)p[i];
    }
    return (ssize_t)count;
}

int mkdir(const char *path, mode_t mode)
{
    (void)path;
    (void)mode;
    return 0;
}

/* No writable files: saving games and the config fails quietly */
int unlink(const char *path)
{
    (void)path;
    errno = ENOENT;
    return -1;
}

int rename(const char *old_path, const char *new_path)
{
    (void)old_path;
    (void)new_path;
    errno = ENOENT;
    return -1;
}

void _exit(int status)
{
    PLATFORM_EXIT = (uint32_t)status;
    for (;;) {
    }
}
