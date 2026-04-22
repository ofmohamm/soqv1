#include "libfreenect.h"
#include "libfreenect_audio.h"
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

static freenect_context *f_ctx;
static freenect_device *f_dev;
static volatile int die = 0;

void sigint_handler(int s) {
    die = 1;
}

void in_callback(freenect_device *dev, int num_samples,
                 int32_t *mic1, int32_t *mic2,
                 int32_t *mic3, int32_t *mic4,
                 int16_t *cancelled, void *unknown) {
    int i;
    for (i = 0; i < num_samples; i++) {
        int32_t frame[4];
        frame[0] = mic1[i];
        frame[1] = mic2[i];
        frame[2] = mic3[i];
        frame[3] = mic4[i];
        fwrite(frame, sizeof(int32_t), 4, stdout);
    }
    fflush(stdout);
}

int main(int argc, char **argv) {
    signal(SIGINT, sigint_handler);

    if (freenect_init(&f_ctx, NULL) < 0) {
        fprintf(stderr, "freenect_init() failed\n");
        return 1;
    }

    freenect_set_log_level(f_ctx, FREENECT_LOG_WARNING);
    freenect_select_subdevices(f_ctx, FREENECT_DEVICE_AUDIO);

    int nr_devices = freenect_num_devices(f_ctx);
    fprintf(stderr, "Number of devices found: %d\n", nr_devices);
    if (nr_devices < 1) {
        freenect_shutdown(f_ctx);
        return 1;
    }

    if (freenect_open_device(f_ctx, &f_dev, 0) < 0) {
        fprintf(stderr, "Could not open device\n");
        freenect_shutdown(f_ctx);
        return 1;
    }

    freenect_set_audio_in_callback(f_dev, in_callback);
    freenect_start_audio(f_dev);
    fprintf(stderr, "Capturing audio. Press Ctrl+C to stop.\n");

    while (!die && freenect_process_events(f_ctx) >= 0) {
    }

    freenect_stop_audio(f_dev);
    freenect_close_device(f_dev);
    freenect_shutdown(f_ctx);
    fprintf(stderr, "Done.\n");
    return 0;
}