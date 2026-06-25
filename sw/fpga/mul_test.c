#define LED_MMIO (*(volatile unsigned int *)0x10000000u)

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
    LED_MMIO = true_val;
}

void set_false(){
    LED_MMIO = false_val;
    stop();
}

void stop(){
    for(;;);
}