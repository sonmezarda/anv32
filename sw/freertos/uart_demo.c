/*
 * FreeRTOS on the Tang Nano 9K with the default SoC parameters (32 KiB BRAM,
 * no NN accelerator), core im1 or im2.
 *
 *   make fpga FILE=sw/freertos/uart_demo.c
 *
 * Four tasks:
 *   blink   toggles LED0 every 250 ms
 *   uptime  queues the uptime once a second
 *   print   prints each queued uptime over UART0 (115200 8N1)
 *   button  woken from the GPIO interrupt (button S1, on release), counts presses
 * A kernel error prints its name and freezes with all four LEDs on.
 */
#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#include "anv32_clint.h"
#include "anv32_gpio.h"
#include "anv32_sysctrl.h"
#include "lib/uart_lib.h"

#define BLINK_PRIO          1
#define UPTIME_PRIO         2
#define PRINT_PRIO          3
#define BUTTON_PRIO         3

#define MCAUSE_MEI          0x8000000Bu

extern void freertos_risc_v_trap_handler(void);

static QueueHandle_t uptime_queue;
static SemaphoreHandle_t button_sem;
static SemaphoreHandle_t uart_mutex;

static void put_dec(uint32_t v)
{
    char buf[11];
    int i = 0;

    do {
        buf[i++] = (char)('0' + v % 10u);
        v /= 10u;
    } while (v != 0u);
    while (i > 0) {
        uart_putc(&UART0, buf[--i]);
    }
}

static void halt(const char *why)
{
    taskDISABLE_INTERRUPTS();
    uart_puts(&UART0, "\r\nFreeRTOS error: ");
    uart_puts(&UART0, why);
    uart_puts(&UART0, "\r\n");
    ANV32_SYSCTRL_LED = 0xFu;
    for (;;) {
    }
}

void vAssertCalled(const char *file, int line)
{
    taskDISABLE_INTERRUPTS();
    uart_puts(&UART0, "\r\nassert ");
    uart_puts(&UART0, file);
    uart_putc(&UART0, ':');
    put_dec((uint32_t)line);
    halt("assert");
}

void vApplicationMallocFailedHook(void)
{
    halt("out of heap");
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    taskDISABLE_INTERRUPTS();
    uart_puts(&UART0, "\r\ntask ");
    uart_puts(&UART0, name);
    halt("stack overflow");
}

void freertos_risc_v_application_exception_handler(uint32_t mcause)
{
    (void)mcause;
    halt("unexpected exception");
}

/* The port enables the external interrupt alongside the tick; here it is the
   GPIO interrupt input, a rising edge on button S1 (pulled up, low while held). */
void freertos_risc_v_application_interrupt_handler(uint32_t mcause)
{
    BaseType_t woken = pdFALSE;

    if (mcause != MCAUSE_MEI) {
        halt("unexpected interrupt");
    }
    ANV32_GPIO0_IRQ_PENDING = 1u;
    xSemaphoreGiveFromISR(button_sem, &woken);
    portYIELD_FROM_ISR(woken);
}

static void blink_task(void *arg)
{
    (void)arg;
    for (;;) {
        ANV32_SYSCTRL_LED ^= 0x1u;
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}

static void uptime_task(void *arg)
{
    TickType_t wake = xTaskGetTickCount();
    uint32_t seconds = 0;

    (void)arg;
    for (;;) {
        xTaskDelayUntil(&wake, pdMS_TO_TICKS(1000));
        seconds++;
        xQueueSend(uptime_queue, &seconds, 0);
    }
}

static void print_task(void *arg)
{
    uint32_t seconds;

    (void)arg;
    for (;;) {
        xQueueReceive(uptime_queue, &seconds, portMAX_DELAY);
        xSemaphoreTake(uart_mutex, portMAX_DELAY);
        uart_puts(&UART0, "uptime ");
        put_dec(seconds);
        uart_puts(&UART0, " s, ticks ");
        put_dec(xTaskGetTickCount());
        uart_puts(&UART0, "\r\n");
        xSemaphoreGive(uart_mutex);
    }
}

static void button_task(void *arg)
{
    uint32_t presses = 0;

    (void)arg;
    for (;;) {
        xSemaphoreTake(button_sem, portMAX_DELAY);
        presses++;
        ANV32_SYSCTRL_LED ^= 0x2u;
        xSemaphoreTake(uart_mutex, portMAX_DELAY);
        uart_puts(&UART0, "button ");
        put_dec(presses);
        uart_puts(&UART0, "\r\n");
        xSemaphoreGive(uart_mutex);
        /* Debounce: GPIO cannot read the pin level yet, only edges, and the
           contact bounces on press too. Treat every edge within 300 ms of a
           counted one as the same press. */
        vTaskDelay(pdMS_TO_TICKS(300));
        xSemaphoreTake(button_sem, 0);
    }
}

int main(void)
{
    uart_begin(&UART0, 115200);
    uart_puts(&UART0, "\r\nanv32 FreeRTOS " tskKERNEL_VERSION_NUMBER "\r\n");

    __asm__ volatile ("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    /* The GPIO edge detector starts from 0, so the pulled-up button input
       looks like a rising edge right after reset; drop that stale event. */
    ANV32_GPIO0_IRQ_PENDING = 1u;

    uptime_queue = xQueueCreate(4, sizeof(uint32_t));
    button_sem = xSemaphoreCreateBinary();
    uart_mutex = xSemaphoreCreateMutex();
    if (uptime_queue == NULL || button_sem == NULL || uart_mutex == NULL ||
        xTaskCreate(blink_task, "blink", configMINIMAL_STACK_SIZE, NULL,
                    BLINK_PRIO, NULL) != pdPASS ||
        xTaskCreate(uptime_task, "uptime", configMINIMAL_STACK_SIZE, NULL,
                    UPTIME_PRIO, NULL) != pdPASS ||
        xTaskCreate(print_task, "print", configMINIMAL_STACK_SIZE, NULL,
                    PRINT_PRIO, NULL) != pdPASS ||
        xTaskCreate(button_task, "button", configMINIMAL_STACK_SIZE, NULL,
                    BUTTON_PRIO, NULL) != pdPASS) {
        halt("setup");
    }
    vTaskStartScheduler();
    halt("scheduler returned");
    return 0;
}
