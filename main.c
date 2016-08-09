#include "tfont.h"

#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <SDL/SDL.h>

// A: B m0,4 m1,1 m2,0 m1,-1 m0,-4 EM0,2Bm4,0

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
	putpixel(screen, x, y, yellow);
	SDL_UpdateRect(screen, x, y, 1, 1);
	
	// Uncomment for epic
	// SDL_Delay(3);
}

struct glyph
{
	char code[128];
};

struct glyph font[256];

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

int main(int argc, const char **argv)
{
	SDL_Init(SDL_INIT_EVERYTHING);

	screen = SDL_SetVideoMode(800, 600, 32, SDL_SWSURFACE);

	yellow = SDL_MapRGB(screen->format, 0xff, 0xff, 0x00);
	
	tfont_setSize(24);
	tfont_setDotSize(2);
	tfont_setPainter(&tfput, NULL);
	
	load("test.tfn");
	
	char *testText = 
		"prall vom whisky flog quax den\njet zu bruch.\n"
		"PRALL VOM WHISKY FLOG QUAX DEN\nJET ZU BRUCH.\n"
		"Prall vom Whisky flog Quax den\nJet zu Bruch.\n"
		"(a) {a} [a]\n"
		"0123456789\n"
	;
	
	int x = 8;
	int y = 8 + tfont_getSize();
	
	printf("%s\n", testText);
	
	char *string = testText;
	while(*string)
	{
		if(*string == '\n') {
			x = 8;
			y += tfont_getSize() + 8;
		} else {
			if(x + tfont_width(font[*string].code) >= screen->w) {
				x = 8;
				y += tfont_getSize() + 8;
			}	
			x += tfont_render(x, y, font[*string].code);
		}
		string++;
	}
	x = 8;
	y += tfont_getSize() + 8;
	
	tfont_setSize(8);
	tfont_setDotSize(1);
	
	string = testText;
	while(*string)
	{
		if(*string == '\n') {
			x = 8;
			y += tfont_getSize() + 8;
		} else {
			if(x + tfont_width(font[*string].code) >= screen->w) {
				x = 8;
				y += tfont_getSize() + 8;
			}	
			x += tfont_render(x, y, font[*string].code);
		}
		string++;
	}
	
	while(true)
	{
		char *line;
		size_t len;
		int c = getline(&line, &len, stdin);
		if(c == EOF) break;
		// render(line);
	}


	return 0;
}