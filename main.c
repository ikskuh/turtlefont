#include "tfont.h"

#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <SDL/SDL.h>

// Press plus/minus to change font size.
// Any key refreshes the font file and code.

SDL_Surface *screen;
uint32_t yellow;

/*
 * Set the pixel at (x, y) to the given value
 * NOTE: The surface must be locked before calling this!
 */
void putpixel(SDL_Surface *surface, int x, int y, Uint32 pixel)
{	
	int bpp = surface->format->BytesPerPixel;
	/* Here p is the address to the pixel we want to set */
	Uint8 *p = (Uint8 *)surface->pixels + y * surface->pitch + x * bpp;

	switch(bpp) {
	case 1:
			*p = pixel;
			break;

	case 2:
			*(Uint16 *)p = pixel;
			break;

	case 3:
			if(SDL_BYTEORDER == SDL_BIG_ENDIAN) {
					p[0] = (pixel >> 16) & 0xff;
					p[1] = (pixel >> 8) & 0xff;
					p[2] = pixel & 0xff;
			} else {
					p[0] = pixel & 0xff;
					p[1] = (pixel >> 8) & 0xff;
					p[2] = (pixel >> 16) & 0xff;
			}
			break;

	case 4:
			*(Uint32 *)p = pixel;
			break;
	}
}

void tfput(int x, int y, void *arg)
{
	if(x < 0 || y < 0 || x >= screen->w || y >= screen->h)
		return;
	putpixel(screen, x, y, yellow);
	// SDL_UpdateRect(screen, x, y, 1, 1);
	
	// Uncomment for epic
	// SDL_Delay(4);
}

struct glyph
{
	char code[128];
};

struct glyph font[256];

char const *getGlyph(int codepoint) {
	if(codepoint < 128) {
		return font[codepoint].code;
	}
	switch(codepoint)
	{
		case 215: // ×
			return "a5 M08 p4-4 M48 p-4-4";
		case 228: // ä
			return "a6 M46 p0-4 p-30 p-11 p02 p11 p20 p1-1 M18d M38d";
		case 246: // ö
			return "a6 M03 p02 p11 p20 p1-1 p0-2 p-1-1 p-20 p-11 M18d M38d";
		case 223: // ß
			return "a6 M02 P09 p11 p10 p1-1 p0-1 p-1-1 p2-2 p0-2 p-1-1 p-10";
		case 247: // ÷
			return "a6 M06 p40 M28d M24d";
		case 252: // ü
			return "a6 M06 p0-3 p1-1 p20 p11 p03 M18d M38d";
		case 8230: // …
			return "a6 M02d M22d M42d";
		case 8592: // ←
			return "a6 M06 p40 M17 p-1-1 p1-1";
		case 8593: // ↑
			return "a4 M14 P18 M07 p11 p1-1";
		case 8594: // →
			return "a6 M06 p40 M37 p1-1 p-1-1";
		case 8595: // ↓
			return "a4 M14 P18 M05 p1-1 p11";
		default:
			printf("Unicode: %d\n", codepoint);
			return NULL;
	}
}

void load(const char *fileName)
{
	FILE *f = fopen(fileName, "r");
	
	memset(font, 0, sizeof(struct glyph) * 256);
	
	while(!feof(f))
	{
		char c = fgetc(f);
		if(c == EOF) break;
		if(fgetc(f) != ':') {
			printf("invalid font file.\n");
			break;
		}
		for(int i = 0; i < 127; i++)
		{
			font[c].code[i + 0] = fgetc(f);
			font[c].code[i + 1] = 0;
			if(font[c].code[i + 0] == '\n' || font[c].code[i + 0] == EOF) {
				font[c].code[i] = 0;
				break;
			}
		}
		printf("%c: %s\n", c, font[c].code);
	}
	fclose(f);
}

void render()
{
	load("test.tfn");
	
	FILE *f = fopen("tfont.c", "r");
	
	SDL_Rect rect = {
		0, 0,
		screen->w, screen->h
	};
	SDL_FillRect(screen, &rect, 0x00);
	
	int x = 8;
	int y = 8 + tfont_getSize();
	
	tfont_render_string(
		x, y,
		"Quäker würgen Meißen völlig übertrieben.\n"
		"f(x) = 10 × a ÷ 3\n"
		"↑ ↓ → ← '...' → '…'",
		0,
		tfNone);
	
	y += 4 * tfont_getLineHeight();
	
	while(!feof(f)) 
	{
		char buffer[256];
		int len = fread(buffer, 1, 256, f);
		
		for(int i = 0; i < len; i++) {
			char c = buffer[i];
			if(c == '\n') {
				x = 8;
				y += tfont_getLineHeight();
			} else {
				if(x + tfont_width(font[c].code) >= screen->w) {
					x = 8;
					y += tfont_getLineHeight();
				}	
				x += tfont_render_glyph(x, y, font[c].code);
			}
		}
	}
	SDL_UpdateRect(screen, 0, 0, screen->w, screen->h);
}

int main(int argc, const char **argv)
{
	SDL_Init(SDL_INIT_EVERYTHING);

	screen = SDL_SetVideoMode(800, 800, 32, SDL_SWSURFACE);

	yellow = SDL_MapRGB(screen->format, 0xff, 0xff, 0x00);
	
	tfont_setSize(24);
	tfont_setDotSize(0);
	tfont_setPainter(&tfput, NULL);
	tfont_setFont(&getGlyph);
	
	render();
	
	while(true)
	{
		SDL_Event e;
		while(SDL_PollEvent(&e))
		{
			if(e.type == SDL_QUIT) return 0;
			if(e.type == SDL_KEYDOWN)
			{
				switch(e.key.keysym.sym)
				{
					case SDLK_PLUS:
						tfont_setSize(tfont_getSize() + 2);
						break;
					case SDLK_MINUS:
						tfont_setSize(tfont_getSize() - 2);
						break;
					case SDLK_t:
						tfont_setStroke(tfont_getStroke() + 1);
						break;
					case SDLK_g:
						tfont_setStroke(tfont_getStroke() - 1);
						break;
				}
				if(tfont_getSize() < 16) {
					tfont_setDotSize(1);
				} else {
					tfont_setDotSize(2);
				}
						
				render();
			}
		}
		
		SDL_Delay(16);
	}

	return 0;
}