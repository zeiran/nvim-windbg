
#include <stdio.h>

void app(int argc)
{
    printf("argc=%d", argc);
}

int main(int argc, char** argv)
{
    app(argc);
    return 0;
}
