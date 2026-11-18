#include "FNVDisplay.h"

// Configured on the main thread before the guest starts. Uses native desktop resolution.
static unsigned width = 1280, height = 720, client_width = 1280, client_height = 720;

void fnv_display_configure(unsigned nw, unsigned nh) {
    if (!nw || !nh) return;
    width = (nw / 2) * 2;
    height = (nh / 2) * 2;
    if (width < 640) width = 640;
    if (height < 480) height = 480;
    client_width = width;
    client_height = height;
}

unsigned fnv_display_width(void) { return width; }
unsigned fnv_display_height(void) { return height; }

void fnv_display_client(unsigned w, unsigned h) {
    if (w && h) {
        client_width = w;
        client_height = h;
    }
}

unsigned fnv_client_width(void) { return client_width; }
unsigned fnv_client_height(void) { return client_height; }

// Keep the established guest adapter identity stable. Startup compares it with
// sD3DDevice before deciding whether to tear down workers and invoke the launcher.
const char *fnv_display_adapter_description(void) { return "NVIDIA GeForce GTX 580"; }
