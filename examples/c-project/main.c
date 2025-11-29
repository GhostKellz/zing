#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    printf("Hello from C compiled with zmake! 🔥\n");
    printf("Arguments: %d\n", argc);
    
    for (int i = 0; i < argc; i++) {
        printf("  [%d]: %s\n", i, argv[i]);
    }
    
    #ifdef DEBUG
    printf("Debug mode enabled\n");
    #endif
    
    #ifdef NDEBUG
    printf("Release mode (optimized)\n");
    #endif
    
    return 0;
}