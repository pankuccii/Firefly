// stdin: one 'R' per sample; stdout: validated capacity and charging (-1 = unknown).
// This isolated process lets the host cancel a blocked network call by closing the session.
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <plist/plist.h>
#include <libimobiledevice/heartbeat.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <string.h>
#include <unistd.h>

// Respond only to a paired phone's own heartbeat. A device may decline this
// optional service; the authenticated battery session still works independently.
typedef struct {
    heartbeat_client_t client;
    atomic_bool stopping;
    atomic_bool ended;
} heartbeat_state;

static void *reply_to_heartbeat(void *context) {
    heartbeat_state *state = context;
    while (!atomic_load(&state->stopping)) {
        plist_t request = NULL;
        heartbeat_error_t status = heartbeat_receive_with_timeout(state->client, &request, 60000);
        if (status == HEARTBEAT_E_TIMEOUT) { plist_free(request); continue; }
        if (status != HEARTBEAT_E_SUCCESS || !request) { plist_free(request); break; }
        plist_free(request);
        plist_t response = plist_new_dict();
        plist_dict_set_item(response, "Command", plist_new_string("Polo"));
        status = heartbeat_send(state->client, response);
        plist_free(response);
        if (status != HEARTBEAT_E_SUCCESS) break;
    }
    atomic_store(&state->ended, true);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 3 || (strcmp(argv[1], "wifi") && strcmp(argv[1], "usb"))) return 2;
    idevice_t device = NULL;
    lockdownd_client_t client = NULL;
    int result = 1;
    heartbeat_state heartbeat = {0};
    pthread_t thread;
    bool running = false;
    int options = !strcmp(argv[1], "wifi") ? IDEVICE_LOOKUP_NETWORK : IDEVICE_LOOKUP_USBMUX;
    if (idevice_new_with_options(&device, argv[2], options) != IDEVICE_E_SUCCESS) goto finish;
    if (lockdownd_client_new_with_handshake(device, &client, "Firefly") != LOCKDOWN_E_SUCCESS) goto finish;

    unsigned attempts = 0;
    time_t next_attempt = 0;
    while (getchar() == 'R') {
        // If the heartbeat channel alone goes away, retain the battery channel.
        // Only the main thread starts or releases transports.
        if (running && atomic_load(&heartbeat.ended)) {
            pthread_join(thread, NULL);
            heartbeat_client_free(heartbeat.client);
            heartbeat.client = NULL;
            running = false;
        }
        if (options == IDEVICE_LOOKUP_NETWORK && !running && attempts < 3 && time(NULL) >= next_attempt) {
            attempts++;
            next_attempt = time(NULL) + 60;
            lockdownd_service_descriptor_t service = NULL;
            if (lockdownd_start_service(client, HEARTBEAT_SERVICE_NAME, &service) == LOCKDOWN_E_SUCCESS &&
                service && heartbeat_client_new(device, service, &heartbeat.client) == HEARTBEAT_E_SUCCESS) {
                atomic_store(&heartbeat.ended, false);
                running = pthread_create(&thread, NULL, reply_to_heartbeat, &heartbeat) == 0;
                if (!running) {
                    heartbeat_client_free(heartbeat.client);
                    heartbeat.client = NULL;
                }
            }
            if (service) lockdownd_service_descriptor_free(service);
        }
        plist_t value = NULL;
        if (lockdownd_get_value(client, "com.apple.mobile.battery", NULL, &value) != LOCKDOWN_E_SUCCESS || !value) {
            plist_free(value);
            goto finish;
        }
        plist_t capacity = plist_dict_get_item(value, "BatteryCurrentCapacity");
        plist_t charging = plist_dict_get_item(value, "BatteryIsCharging");
        uint64_t percent = 101;
        int state = -1;
        if (capacity && plist_get_node_type(capacity) == PLIST_UINT) plist_get_uint_val(capacity, &percent);
        if (charging && plist_get_node_type(charging) == PLIST_BOOLEAN) {
            uint8_t b = 0;
            plist_get_bool_val(charging, &b);
            state = b ? 1 : 0;
        }
        plist_free(value);
        if (percent > 100) goto finish;
        // A single atomic write makes the response unambiguous on the private pipe.
        unsigned char packet[2] = {(unsigned char)percent, (unsigned char)(state + 1)};
        if (write(STDOUT_FILENO, packet, sizeof(packet)) != sizeof(packet)) goto finish;
    }
    result = 0;
finish:
    close(STDOUT_FILENO);
    if (running) {
        atomic_store(&heartbeat.stopping, true);
        pthread_join(thread, NULL);
    }
    if (heartbeat.client) heartbeat_client_free(heartbeat.client);
    if (client) lockdownd_client_free(client);
    if (device) idevice_free(device);
    return result;
}
