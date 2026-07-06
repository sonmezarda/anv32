#include "anv32_sysctrl.h"

unsigned int true_val  = 0b0101;
unsigned int false_val = 0b1100;

int main(void)
{
    int a =  5;
    int b = -10;

    int c;

    c = a*b;
    if(c == -50)
        set_true();
    else 
        set_false();

        
    c = b / a;

    if(c == -2)
        set_true();
    else 
        set_false();

    /*
    a = 888;
    b = -1;
    c = a*b;
    if(c == -888)
        set_true();
    else
        set_false();
    */
}


void set_true(){
    ANV32_SYSCTRL_LED = true_val;
}

void set_false(){
    ANV32_SYSCTRL_LED = false_val;
    stop();
}

void stop(){
    for(;;);
}
