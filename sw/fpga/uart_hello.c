#include "anv32_sysctrl.h"
#include "lib/uart_lib.h"

void delay(volatile unsigned long delay){
    while(delay > 0)
        delay -= 1;
}

int main(void)
{
    uart_begin(&UART0, 115200);

    while(1){
        uart_puts(&UART0, "Hello");
        uart_putc(&UART0, '\n');
        delay(400000u);
    }
    
    return 0;
}
