#ifndef OAYAO_H
#define OAYAO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the canvas state. Must be called before any other function.
void oy_init(void);

/// Initialize with an externally-provided buffer. Zig renders directly into this
/// buffer instead of owning its own allocation. The buffer must remain valid and
/// at least height * bytes_per_row bytes in size until the next resize call.
void oy_init_with_buffer(uint8_t* buf, uint32_t w, uint32_t h, uint32_t bpr);

/// Return a pointer to the RGBA8 framebuffer owned by the Zig side.
/// The buffer is width * height * 4 bytes and remains valid until the next resize.
uintptr_t oy_get_framebuffer_ptr(void);

/// Return the current framebuffer width in pixels.
uint32_t oy_get_width(void);

/// Return the current framebuffer height in pixels.
uint32_t oy_get_height(void);

/// Resize the framebuffer. This reallocates the underlying buffer.
void oy_resize(uint32_t new_w, uint32_t new_h);

/// Resize with a new externally-provided buffer. The old buffer is abandoned.
void oy_resize_with_buffer(uint8_t* buf, uint32_t w, uint32_t h, uint32_t bpr);

/// Swap the framebuffer pointer without resetting render state.
/// Dimensions must match the current buffer.
void oy_set_buffer(uint8_t* buf);

/// Advance one frame and render into the framebuffer.
/// elapsed: seconds since init()
/// unix_ms: Unix epoch time in milliseconds (used for the day counter text)
/// dpr:     device pixel ratio / content scale factor
void oy_update_frame(float elapsed, double unix_ms, float dpr);

/// Trigger a meteor shower toward the given screen coordinate.
void oy_show_meteor_shower(float click_x, float click_y);

#ifdef __cplusplus
}
#endif

#endif /* OAYAO_H */
