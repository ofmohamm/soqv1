#include "libfreenect.h"
#include "libfreenect_audio.h"
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <math.h>

#define BLOCK_SIZE 128

static freenect_context *f_ctx;
static freenect_device *f_dev;
static volatile int die = 0;

static int32_t buf[BLOCK_SIZE];
static int buf_idx = 0;

void sigint_handler(int s) {
    die = 1;
}

void in_callback(freenect_device *dev, int num_samples,
                 int32_t *mic1, int32_t *mic2,
                 int32_t *mic3, int32_t *mic4,
                 int16_t *cancelled, void *unknown) {
    int i;
    for (i = 0; i < num_samples; i++) {
        buf[buf_idx++] = mic1[i];

        if (buf_idx >= BLOCK_SIZE) {
            double rms = 0.0;
            int j;
            for (j = 0; j < BLOCK_SIZE; j++) {
                double s = (double)buf[j];
                rms += s * s;
            }
            rms = sqrt(rms / BLOCK_SIZE);
            printf("%.0f\n", rms);
            fflush(stdout);
            buf_idx = 0;
        }
    }
}

int main(int argc, char **argv) {
    signal(SIGINT, sigint_handler);

    if (freenect_init(&f_ctx, NULL) < 0) {
        fprintf(stderr, "freenect_init() failed\n");
        return 1;
    }

    freenect_set_log_level(f_ctx, FREENECT_LOG_WARNING);
    freenect_select_subdevices(f_ctx, FREENECT_DEVICE_AUDIO);

    if (freenect_num_devices(f_ctx) < 1) {
        fprintf(stderr, "No devices found\n");
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
    fprintf(stderr, "Measuring RMS. Ctrl+C to stop.\n");

    while (!die && freenect_process_events(f_ctx) >= 0) {
    }

    freenect_stop_audio(f_dev);
    freenect_close_device(f_dev);
    freenect_shutdown(f_ctx);
    return 0;
}