#ifndef ZIG_FONT_RENDERER_H
#define ZIG_FONT_RENDERER_H

/*
 * C API for libzig_font_renderer.
 *
 * This header exposes a small stable ABI around the Zig implementation. The
 * current API renders a font file and UTF-8 text into an allocated SVG string.
 *
 * Ownership rule:
 *   Strings returned through this API are allocated by libzig_font_renderer.
 *   Callers must release them with zfr_free_string(), passing the exact pointer
 *   and length returned by zfr_render_svg_file().
 *
 * Threading:
 *   The API does not keep per-call global render state. Distinct calls may be
 *   made independently, but callers should still avoid mutating shared option
 *   structures or output pointers from multiple threads at the same time.
 *
 * Encoding:
 *   font_path is interpreted by Zig's filesystem layer for the host platform.
 *   text must be UTF-8. Generated SVG data is UTF-8 and NUL-terminated for C
 *   convenience; out_len excludes the trailing NUL byte.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * zfr_status describes the result of a C API call.
 *
 * ZFR_OK:
 *   The operation completed successfully.
 *
 * ZFR_ERROR_INVALID_ARGUMENT:
 *   One or more required pointers were NULL, an option value was invalid, or
 *   an enum value was outside the supported range.
 *
 * ZFR_ERROR_OUT_OF_MEMORY:
 *   The library could not allocate memory for parsing, rendering, or returning
 *   the SVG string.
 *
 * ZFR_ERROR_IO:
 *   The font file could not be opened, read, or was larger than max_font_bytes.
 *
 * ZFR_ERROR_PARSE:
 *   The font data was not a supported or valid font at the requested face.
 *
 * ZFR_ERROR_RENDER:
 *   Rendering failed after the font was parsed, for example because of an
 *   unsupported outline or SVG option.
 */
typedef enum zfr_status {
    ZFR_OK = 0,
    ZFR_ERROR_INVALID_ARGUMENT = 1,
    ZFR_ERROR_OUT_OF_MEMORY = 2,
    ZFR_ERROR_IO = 3,
    ZFR_ERROR_PARSE = 4,
    ZFR_ERROR_RENDER = 5,
} zfr_status;

/*
 * Text direction used by the shaping stage.
 *
 * AUTO resolves direction from the text content using the renderer's current
 * heuristic. LTR and RTL force horizontal left-to-right or right-to-left
 * shaping. TTB requests top-to-bottom vertical layout.
 */
typedef enum zfr_direction {
    ZFR_DIRECTION_AUTO = 0,
    ZFR_DIRECTION_LTR = 1,
    ZFR_DIRECTION_RTL = 2,
    ZFR_DIRECTION_TTB = 3,
} zfr_direction;

/*
 * Rendering options for zfr_render_svg_file().
 *
 * Use zfr_default_render_options() to initialize this struct, then override
 * only the fields you need. This makes future additions safer for callers.
 *
 * font_size_px:
 *   Output font size in CSS pixels. Must be finite and greater than 0.
 *
 * margin_px:
 *   Margin around the rendered glyph bounds in CSS pixels. Must be finite and
 *   greater than or equal to 0.
 *
 * face_index:
 *   Face index for TrueType/OpenType collections. Use 0 for standalone fonts
 *   and for the first face of a collection.
 *
 * max_font_bytes:
 *   Maximum number of bytes to read from font_path. This protects callers from
 *   accidentally reading huge files. Must be greater than 0.
 *
 * fill:
 *   SVG fill color string, for example "black", "#111827", or "rgb(0,0,0)".
 *   If NULL, the renderer uses "black". Invalid SVG color strings cause
 *   ZFR_ERROR_RENDER.
 *
 * background:
 *   Optional SVG background color string. If NULL, no background rectangle is
 *   emitted. Invalid SVG color strings cause ZFR_ERROR_RENDER.
 *
 * direction:
 *   Text direction. See zfr_direction.
 */
typedef struct zfr_render_options {
    double font_size_px;
    double margin_px;
    uint32_t face_index;
    size_t max_font_bytes;
    const char *fill;
    const char *background;
    zfr_direction direction;
} zfr_render_options;

/*
 * Return the default render options.
 *
 * Defaults:
 *   font_size_px   = 64.0
 *   margin_px      = 8.0
 *   face_index     = 0
 *   max_font_bytes = 256 MiB
 *   fill           = "black"
 *   background     = NULL
 *   direction      = ZFR_DIRECTION_AUTO
 */
zfr_render_options zfr_default_render_options(void);

/*
 * Render UTF-8 text from a font file into an SVG string.
 *
 * Parameters:
 *   font_path:
 *     NUL-terminated path to a TTF, OTF, or TTC font file. Must not be NULL.
 *
 *   text:
 *     NUL-terminated UTF-8 text to render. Must not be NULL.
 *
 *   options:
 *     Optional render options. If NULL, zfr_default_render_options() is used.
 *
 *   out_svg:
 *     Output pointer that receives a newly allocated, NUL-terminated SVG
 *     string on success. Must not be NULL. On failure, it is set to NULL.
 *
 *   out_len:
 *     Output length in bytes, excluding the trailing NUL. Must not be NULL.
 *     On failure, it is set to 0.
 *
 * Return:
 *   ZFR_OK on success, otherwise a zfr_status error code.
 *
 * Ownership:
 *   On success, the caller owns *out_svg and must call:
 *
 *       zfr_free_string(*out_svg, *out_len);
 *
 *   Do not free the returned pointer with free(), delete, or another allocator.
 */
zfr_status zfr_render_svg_file(
    const char *font_path,
    const char *text,
    const zfr_render_options *options,
    char **out_svg,
    size_t *out_len
);

/*
 * Free a string returned by libzig_font_renderer.
 *
 * ptr may be NULL, in which case this function does nothing. len must be the
 * exact length returned alongside ptr by the producing API. Passing a different
 * length, a non-library pointer, or a pointer already freed is undefined
 * behavior.
 */
void zfr_free_string(char *ptr, size_t len);

/*
 * Return a static, NUL-terminated message for a status code.
 *
 * The returned pointer is owned by the library and must not be freed. Unknown
 * numeric status values return "unknown status".
 */
const char *zfr_status_message(zfr_status status);

#ifdef __cplusplus
}
#endif

#endif
