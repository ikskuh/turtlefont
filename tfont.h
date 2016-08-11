#pragma once

typedef enum tfont_option
{
	tfNone = 0,
} tfont_option_t;

/**
 * Function pointer type that is used for the drawing callback.
 * @param x   The x coordinate of the pixel
 * @param y   The y coordinate of the pixel
 * @param arg The argument passed to tfont_setPainter.
 */
typedef void (*tfont_put)(int x, int y, void * arg);

/**
 * Function pointer type for font indexing.
 * @param codepoint The codepoint of the glyph to get.
 * @return          Glyph definition for the given codepoint. If NULL, no glyph will be rendered.
 */
typedef char const * (*tfont_getglyph)(int codepoint);

/**
 * Sets the render font size.
 * @param size The font size in pixels
 * @remarks    The font size is clamped to a minimum of 8 pixels height as the font format does not look good at lower resolutions.
 */
void tfont_setSize(int size);

/**
 * Gets the render font size.
 * @return Returns the currently set font size.
 */
int tfont_getSize();

/**
 * Sets the stroke width.
 * @param stroke The stroke width in pixels.
 * @remarks The stroke is clamped to a minimum of 1 pixel.
 */
void tfont_setStroke(int stroke);

/**
 * Returns the currently set stroke.
 */
int tfont_getStroke();

/**
 * Sets the render dot size.
 * @param size The radius of the dot in pixels.
 * @remarks    The dot size is clamped to a minimum of 1 pixel.
 */
void tfont_setDotSize(int size);

/**
 * Gets the current render dot size.
 * @return The current render dot size.
 */
int tfont_getDotSize();

/**
 * Sets the line spacing.
 * @param The spacing between the lines.
 * @remarks Default is 1.2
 */
void tfont_setLineSpacing(float spacing);

/**
 * Gets the current line spacing.
 * @return The currently set line spacing.
 */
float tfont_getLineSpacing();

/**
 * Gets the current line height from ascender height to descender height.
 */
int tfont_getLineHeight();

/**
 * Sets the painter used by turtle font.
 * @param put The callback that is used to render pixels.
 * @param arg The argument that is passed to the put function.
 */
void tfont_setPainter(tfont_put put, void *arg);

/**
 * Sets the font for turtlefont.
 * @param getGlyph The function callback that will be invoked when a glyph is requested.
 */
void tfont_setFont(tfont_getglyph getGlyph);

/**
 * Measures the width of a glyph.
 * @param code The glyph definition.
 * @return     The width of the glyph in pixels.
 */
int tfont_width(char const *code);

/**
 * Renders the given glyph at the given position.
 * @param x    left x coordinate in pixels
 * @param y    top y coordinate of the baseline in pixels
 * @param code The glyph definition.
 * @return     The width of the glyph. Can be used to advance the font rendering.
 */
int tfont_render_glyph(int x, int y, char const *code);

/**
 * Renders a string.
 * @param x        The left coordinate of the string
 * @param y        The baseline distance of the string
 * @param text     The string to render
 * @param maxWidth The maximum width of the string. If this is less or equal to zero, no wrapping will happen.
 * @param flags    Modifies the string rendering behaviour
 */
int tfont_render_string(int x, int y, char const *text, int maxWidth, enum tfont_option flags);


/**
 * Measures the width of a string.
 * @param text     The string to render
 * @param maxWidth The maximum width of the string. If this is less or equal to zero, no wrapping will happen.
 * @param flags    Modifies the string rendering behaviour
 */
int tfont_measure_string(char const *text, int maxWidth, enum tfont_option flags);