#ifndef OAYAO_BRIDGE_H
#define OAYAO_BRIDGE_H

#include <stdint.h>

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

// Register a callback invoked when the user taps either of the two
// floating hearts beside the day counter.
typedef void (*oayao_counter_tap_callback_t)(void);
void oayao_set_counter_tap_callback(oayao_counter_tap_callback_t callback);

// Set the start timestamp (Unix epoch ms) for the day counter display.
void oayao_set_days_counter_start_ms(double ms);

// Built-in default start timestamp (Unix epoch ms) for the day counter,
// applied when no calendar event anchors the counter.
double oayao_days_counter_default_start_ms(void);

// Transition the canvas to a theme with an animated color fade.
// theme_id: 0 = mint, 1 = peach, 2 = custom. Unknown ids are ignored.
void oayao_transition_to_theme(uint32_t theme_id);

// Update one color of the custom theme. If the custom theme is currently
// active, the canvas fades to the new color.
// role: 0 = background, 1 = heart fill, 2 = heart stroke, 3 = timer text.
void oayao_set_custom_theme_color(uint32_t role, uint8_t r, uint8_t g, uint8_t b);

// Big-heart behaviour configuration. All values clamp to valid ranges.
// opacity: 0.0 (invisible) to 1.0 (fully opaque).
void oayao_set_heart_opacity(float opacity);

// Overall size multiplier, clamped to [0.3, 3.0]. 1.0 is the default size.
void oayao_set_heart_size_scale(float size_scale);

// Motion style: 0 = beat (pulsing), 1 = breath (gentle sinusoid).
void oayao_set_heart_motion(uint32_t mode);

// Vertical position as a fraction of canvas height (0.0 = top, 1.0 = bottom).
void oayao_set_heart_y(float fraction);

// Restore the built-in vertical position (undoes oayao_set_heart_y).
void oayao_reset_heart_y(void);

// Restore all big-heart settings (size, opacity, motion, position)
// to their defaults.
void oayao_reset_heart_config(void);

// Toggle the nebula background effect (0 = off, 1 = on). Default off.
void oayao_set_nebula_enabled(uint32_t enabled);

// Built-in vertical position as a fraction of the current canvas height.
float oayao_default_heart_y(void);

#ifdef __cplusplus
}
#endif

#endif // OAYAO_BRIDGE_H
