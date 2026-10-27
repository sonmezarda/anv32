/*
 * doomgeneric port for the anv32 simulation platform. The game draws into an
 * 8-bit indexed 320x200 buffer (CMAP256); each finished frame is handed to
 * the testbench together with the palette. There is no input yet, so the
 * game runs its attract mode: title screen and demo playback.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "doomgeneric.h"
#include "i_video.h"
#include "platform.h"

static uint64_t read_cycles(void)
{
    uint32_t hi, lo, hi2;

    do {
        __asm__ volatile ("rdcycleh %0" : "=r"(hi));
        __asm__ volatile ("rdcycle %0" : "=r"(lo));
        __asm__ volatile ("rdcycleh %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

__attribute__((interrupt("machine"), aligned(4)))
static void trap_handler(void)
{
    uint32_t mcause, mepc, mtval;

    __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
    __asm__ volatile ("csrr %0, mepc" : "=r"(mepc));
    __asm__ volatile ("csrr %0, mtval" : "=r"(mtval));
    printf("\ntrap: mcause=%lu mepc=%08lx mtval=%08lx\n",
           (unsigned long)mcause, (unsigned long)mepc, (unsigned long)mtval);
    _exit(-2);
}

void DG_Init(void)
{
}

void DG_DrawFrame(void)
{
    PLATFORM_PALETTE = (uint32_t)(uintptr_t)colors;
    PLATFORM_FRAME = (uint32_t)(uintptr_t)DG_ScreenBuffer;
}

uint32_t DG_GetTicksMs(void)
{
    return (uint32_t)(read_cycles() / (PLATFORM_CPU_HZ / 1000u));
}

void DG_SleepMs(uint32_t ms)
{
    uint32_t start = DG_GetTicksMs();

    while (DG_GetTicksMs() - start < ms) {
    }
}

int DG_GetKey(int *pressed, unsigned char *key)
{
    (void)pressed;
    (void)key;
    return 0;
}

void DG_SetWindowTitle(const char *title)
{
    (void)title;
}

int main(void)
{
    static char *argv[] = { "doom", "-iwad", "doom1.wad", NULL };

    __asm__ volatile ("csrw mtvec, %0" : : "r"(trap_handler));

    doomgeneric_Create(3, argv);
    for (;;) {
        doomgeneric_Tick();
    }
}
