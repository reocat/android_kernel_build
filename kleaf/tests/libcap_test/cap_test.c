#include <stdio.h>
#include <stdlib.h>
#include <sys/capability.h>

int test_get_process_capabilities() {
    cap_t caps;
    char *caps_text;

    caps = cap_get_proc();
    caps_text = cap_to_text(caps, NULL);

    if (caps_text == NULL) {
        perror("Failed to convert capabilities to text");
        cap_free(caps);
        return -1;
    }

    printf("Current process capabilities: %s\n", caps_text);
    cap_free(caps_text);
    cap_free(caps);

    return 0;
}

int main() {
    if (test_get_process_capabilities() == 0) {
        printf("Test passed: Successfully retrieved and displayed process capabilities.\n");
        return EXIT_SUCCESS;
    } else {
        printf("Test failed: Error retrieving or displaying process capabilities.\n");
        return EXIT_FAILURE;
    }
}
