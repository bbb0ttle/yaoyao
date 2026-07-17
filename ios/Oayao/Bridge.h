#ifndef OAYAO_BRIDGE_H
#define OAYAO_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Spawn an immortal floating heart for a calendar event.
// event_id is a null-terminated string uniquely identifying the EKEvent.
void oayao_spawn_heart(const char *event_id);

// Remove the heart associated with a calendar event.
void oayao_remove_heart(const char *event_id);

// Synchronize hearts with active event identifiers.
// active_ids is a null-terminated string of newline-separated event identifiers.
// Hearts for IDs not present will begin a fade-out animation.
void oayao_sync_hearts(const char *active_ids);

// Register a callback invoked when the user taps a calendar heart.
// The callback receives the event_id of the tapped event.
typedef void (*oayao_heart_tap_callback_t)(const char *event_id);
void oayao_set_heart_tap_callback(oayao_heart_tap_callback_t callback);

// Set the start timestamp (Unix epoch ms) for the day counter display.
void oayao_set_days_counter_start_ms(double ms);

// Built-in default start timestamp (Unix epoch ms) for the day counter,
// applied when no calendar event anchors the counter.
double oayao_days_counter_default_start_ms(void);

#ifdef __cplusplus
}
#endif

#endif // OAYAO_BRIDGE_H
