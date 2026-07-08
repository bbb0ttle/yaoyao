#ifndef Z_CANVAS_H
#define Z_CANVAS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the canvas state. Must be called before any other function.
void zc_init(void);

/// Return a pointer to the RGBA8 framebuffer owned by the Zig side.
/// The buffer is width * height * 4 bytes and remains valid until the next resize.
uintptr_t zc_get_framebuffer_ptr(void);

/// Return the current framebuffer width in pixels.
uint32_t zc_get_width(void);

/// Return the current framebuffer height in pixels.
uint32_t zc_get_height(void);

/// Resize the framebuffer. This reallocates the underlying buffer.
void zc_resize(uint32_t new_w, uint32_t new_h);

/// Advance one frame and render into the framebuffer.
/// elapsed: seconds since init()
/// unix_ms: Unix epoch time in milliseconds (used for the day counter text)
/// dpr:     device pixel ratio / content scale factor
void zc_update_frame(float elapsed, double unix_ms, float dpr);

/// Trigger a meteor shower toward the given screen coordinate.
void zc_show_meteor_shower(float click_x, float click_y);

#ifdef __cplusplus
}
#endif

#endif /* Z_CANVAS_H */
