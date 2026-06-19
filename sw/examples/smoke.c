static int add(int a, int b)
{
    return a + b;
}

int main(void)
{
    volatile int a = 10;
    volatile int b = 20;
    return add(a, b);
}
