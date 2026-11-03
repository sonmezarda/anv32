/*
 * FreeRTOS smoke test on the SoC (tb_soc_test, 32 KiB BRAM, im1/im2 core).
 * A check task at the highest priority walks through:
 *   1. the tick: vTaskDelay() lasts the right number of ticks and of mtime
 *   2. a queue between a producer and a faster consumer, filled to the brim
 *      so both sides block
 *   3. an interrupt waking a task: msip -> handler -> semaphore
 *   4. preemption: two register test tasks (regtest.S) at the same priority,
 *      time-sliced by the tick, each checking that its registers survive
 * Results go through the SYSCTRL LED register (sw/tests/soc/soc_test.h).
 */
#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#include "anv32_clint.h"
#include "soc_test.h"

#define CHECK_PRIO          4
#define CONSUMER_PRIO       3
#define PRODUCER_PRIO       2
#define REGTEST_PRIO        1

#define MTIME_PER_TICK      (configCPU_CLOCK_HZ / configTICK_RATE_HZ)
#define QUEUE_ITEMS         64u
#define QUEUE_LENGTH        4u
#define MSIP_ROUNDS         3u

#define MCAUSE_MSI          0x80000003u

extern void freertos_risc_v_trap_handler(void);
extern void vRegTest1Task(void *arg);
extern void vRegTest2Task(void *arg);

extern volatile uint32_t ulRegTest1Counter;
extern volatile uint32_t ulRegTest2Counter;

static QueueHandle_t queue;
static SemaphoreHandle_t consumer_done;
static SemaphoreHandle_t msip_sem;
static volatile uint32_t msip_count;
static volatile uint32_t consumed;

/* Failure codes: 1-9 kernel hooks, 10+ the steps of check_task */
void vAssertCalled(const char *file, int line)
{
    (void)file;
    (void)line;
    taskDISABLE_INTERRUPTS();
    test_fail(1);
}

void vApplicationMallocFailedHook(void)
{
    test_fail(2);
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    (void)name;
    test_fail(3);
}

void vRegTestFailed(void)
{
    test_fail(4);
}

void freertos_risc_v_application_exception_handler(uint32_t mcause)
{
    (void)mcause;
    test_fail(5);
}

void freertos_risc_v_application_interrupt_handler(uint32_t mcause)
{
    BaseType_t woken = pdFALSE;

    if (mcause != MCAUSE_MSI) {
        test_fail(6);
    }
    ANV32_CLINT_MSIP = 0u;
    msip_count++;
    xSemaphoreGiveFromISR(msip_sem, &woken);
    portYIELD_FROM_ISR(woken);
}

static void producer_task(void *arg)
{
    (void)arg;
    for (uint32_t i = 0; i < QUEUE_ITEMS; i++) {
        xQueueSend(queue, &i, portMAX_DELAY);
    }
    vTaskDelete(NULL);
}

/* Higher priority than the producer, but naps every few items so the queue
   fills up and the producer blocks on a full queue too. */
static void consumer_task(void *arg)
{
    uint32_t value;

    (void)arg;
    for (uint32_t i = 0; i < QUEUE_ITEMS; i++) {
        if (xQueueReceive(queue, &value, portMAX_DELAY) != pdPASS || value != i) {
            test_fail(20);
        }
        consumed++;
        if ((i % 8u) == 7u) {
            vTaskDelay(1);
        }
    }
    xSemaphoreGive(consumer_done);
    vTaskDelete(NULL);
}

static void check_tick(void)
{
    TickType_t t0 = xTaskGetTickCount();
    uint64_t m0 = anv32_mtime_read();
    TickType_t dt;
    uint64_t dm;

    vTaskDelay(10);
    dt = xTaskGetTickCount() - t0;
    dm = anv32_mtime_read() - m0;
    CHECK(dt == 10u, 10);
    /* Waking up takes up to one tick to line up with the next tick edge */
    CHECK(dm >= 9u * MTIME_PER_TICK, 11);
    CHECK(dm <= 11u * MTIME_PER_TICK, 12);
}

static void check_queue(void)
{
    queue = xQueueCreate(QUEUE_LENGTH, sizeof(uint32_t));
    consumer_done = xSemaphoreCreateBinary();
    CHECK(queue != NULL && consumer_done != NULL, 13);
    CHECK(xTaskCreate(consumer_task, "cons", configMINIMAL_STACK_SIZE, NULL,
                      CONSUMER_PRIO, NULL) == pdPASS, 14);
    CHECK(xTaskCreate(producer_task, "prod", configMINIMAL_STACK_SIZE, NULL,
                      PRODUCER_PRIO, NULL) == pdPASS, 14);
    CHECK(xSemaphoreTake(consumer_done, 100) == pdPASS, 15);
    CHECK(consumed == QUEUE_ITEMS, 16);
}

static void check_irq(void)
{
    msip_sem = xSemaphoreCreateBinary();
    CHECK(msip_sem != NULL, 30);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 3));
    for (uint32_t i = 1; i <= MSIP_ROUNDS; i++) {
        ANV32_CLINT_MSIP = 1u;
        CHECK(xSemaphoreTake(msip_sem, 10) == pdPASS, 31);
        CHECK(msip_count == i, 32);
    }
    CHECK(ANV32_CLINT_MSIP == 0u, 33);
}

static void check_preemption(void)
{
    TaskHandle_t t1, t2;
    uint32_t c1, c2;

    CHECK(xTaskCreate(vRegTest1Task, "reg1", configMINIMAL_STACK_SIZE, NULL,
                      REGTEST_PRIO, &t1) == pdPASS, 40);
    CHECK(xTaskCreate(vRegTest2Task, "reg2", configMINIMAL_STACK_SIZE, NULL,
                      REGTEST_PRIO, &t2) == pdPASS, 40);

    /* Both spin forever, so they only make progress by being time-sliced */
    vTaskDelay(10);
    c1 = ulRegTest1Counter;
    c2 = ulRegTest2Counter;
    CHECK(c1 != 0u, 41);
    CHECK(c2 != 0u, 42);
    vTaskDelay(10);
    CHECK(ulRegTest1Counter != c1, 43);
    CHECK(ulRegTest2Counter != c2, 44);

    vTaskDelete(t1);
    vTaskDelete(t2);
}

static void check_task(void *arg)
{
    (void)arg;
    check_tick();
    check_queue();
    check_irq();
    check_preemption();
    test_pass();
}

int main(void)
{
    __asm__ volatile ("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    if (xTaskCreate(check_task, "check", 2 * configMINIMAL_STACK_SIZE, NULL,
                    CHECK_PRIO, NULL) != pdPASS) {
        test_fail(7);
    }
    vTaskStartScheduler();
    test_fail(8);   /* only returns if the idle task could not be created */
    return 0;
}
