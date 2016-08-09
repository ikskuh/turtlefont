#include "tfont.h"

#include <stdbool.h>
#include <stdlib.h>

#if TFONT_DEBUG
#include <stdio.h>
#endif 

struct tpainter 
{
	tfont_put put;
	void *arg;
};

static struct tpainter painter;

static int fontSize = 16;
static int dotSize = 0;

static void put(int x, int y)
{
	if(painter.put) {
		painter.put(x, y, painter.arg);
	}
}

char sgetrawc(char const **code)
{
	return *(*code)++;
}

char sgetc(char const **code)
{
	while(true)
	{
		char c = sgetrawc(code);
		switch(c)
		{
			case ' ':
			case '\n':
			case '\r':
			case '\t':
				continue;
			default:
#if TFONT_DEBUG
				printf("[%c]", c);
#endif
				return c;
		}
	}
}

int sgetn(char const **code)
{
	int factor = 1;
	while(true)
	{
		char c = sgetc(code);
		if(c == '-') {
			factor = -1;
		}
		if(c >= '0' && c <= '9') {
			return factor * (c - '0');
		}
		if(c >= 'A' && c <= 'F') {
			return factor * (10 + c - 'A');
		}
		if(c >= 'a' && c <= 'f') {
			return factor * (10 + c - 'a');
		}
	}
}

static void line(int x0, int y0, int x1, int y1)
{
  int dx =  abs(x1-x0), sx = x0<x1 ? 1 : -1;
  int dy = -abs(y1-y0), sy = y0<y1 ? 1 : -1;
  int err = dx+dy, e2; /* error value e_xy */

  while(1) {
		put(x0, y0);
    if (x0==x1 && y0==y1) break;
    e2 = 2*err;
    if (e2 > dy) { err += dy; x0 += sx; } /* e_xy+e_x > 0 */
    if (e2 < dx) { err += dx; y0 += sy; } /* e_xy+e_y < 0 */
  }
}

static void dot(int x, int y)
{
	for(int dy = -dotSize; dy <= dotSize; dy++) { 
		for(int dx = -dotSize; dx <= dotSize; dx++) {
			if(dx*dx + dy*dy <= dotSize*dotSize) {
				put(x + dx, y + dy);
			}
		}
	}
}

int scale(int v)
{
	// return fontSize * v / 16;
	return (float)fontSize * v / 8.0;
}

int scalex(int x) { return scale(x); }
int scaley(int y) { return scale(y - 2); }

int tfont_width(char const *code)
{
	while(*code)
	{
		char c = sgetc(&code);
		switch(c)
		{
			case 0:
			case -1:
				return 0;
			case 'a':
				return scalex(sgetn(&code));
		}
	}
	return 0;
}

int tfont_render(int tx, int ty, char const *code)
{
	int advance = 0;
	int x = 0;
	int y = 0;
	int px = 0;
	int py = 0;
	while(*code)
	{
		char c = sgetc(&code);
		switch(c)
		{
			case 0:
			case -1:
				return scale(advance);
			case 'a':
				advance = sgetn(&code);
				break;
			case 'M':
				x = sgetn(&code);
				y = sgetn(&code);
				break;
			case 'm':
				x += sgetn(&code);
				y += sgetn(&code);
				break;
			case 'P':
				x = sgetn(&code);
				y = sgetn(&code);
				line(
					tx + scalex(px), 
					ty - scaley(py), 
					tx + scalex(x), 
					ty - scaley(y));
				break;
			case 'p':
				x += sgetn(&code);
				y += sgetn(&code);
				line(
					tx + scalex(px),
					ty - scaley(py), 
					tx + scalex(x), 
					ty - scaley(y));
				break;
			case 'd':
				dot(
					tx + scalex(x),
					ty - scaley(y));
			default:
#if TFONT_DEBUG
				printf("Unknown command: %c(%d)?\n", c, c);
#endif
				break;
		}
		px = x;
		py = y;
	}
	return scalex(advance);
}















static int max(int a, int b)
{
	if(a > b)
		return a;
	else
		return b;
}

void tfont_setSize(int size) { fontSize = max(8, size); }

int tfont_getSize() { return fontSize; }

void tfont_setPainter(tfont_put put, void *arg)
{
	painter.put = put;
	painter.arg = arg;
}

void tfont_setDotSize(int size) { dotSize = max(size - 1, 0); }

int tfont_getDotSize() { return dotSize; }