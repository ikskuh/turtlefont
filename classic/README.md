# Turtlefont (Classic)
Turtlefont is a small vector graphics font file format with an example font. It uses simple [turtle graphics](https://en.wikipedia.org/wiki/Turtle_graphics) rendering which allows flexible scaling.

## Glyph Format
Turtlefont has a simple glyph description language which contains commands with or without parameters. A command is a single character,
a parameter as well.

Parameters can only be numeric with a pretty restricted format: It is only a single hexadecimal character in the range of `0` to `F`. If a negative number is needed, the character can be prefixed with a `-`.

Whitespace is ignored.

### Commands

| Command | Parameters | Name        | Description                         |
|---------|------------|-------------|-------------------------------------|
|       a | n          | Advance     | Sets the glyph width to n elements. |
|       M | x y        | Move (abs)  | Moves the cursor without drawing.   |
|       m | x y        | Move (rel)  | Moves the cursor without drawing.   |
|       P | x y        | Print (abs) | Draws a line and moves the cursor.  |
|       p | x y        | Print (rel) | Draws a line and moves the cursor.  |
|       d |            | Dot         | Draws a dot at the cursor position. |

## Font Format
The demo features an example font format which allows the definition of multiple glyphs.

The format is line based and does not allow any other lines except for lines in the following format:

	C:CODE\n

`C` is the character for which a glyph should be defined.

`CODE` is a glyph definition in the format specified in *Glyph Format*.

`\n` is a newline character.

## Build Instructions
To build the demo, install SDL 1, then type:

	gcc -lSDL main.c tfont.c

The demo is then runnable with

	./a.out

## Example
This image will emerge when compiling the demo. It shows the capability of decoding and rendering UTF-8:

![Font Demo](https://mq32.de/public/bfbfd68e53aa2b58605249a970c317312d6e6e8b.png)
