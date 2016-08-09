#pragma once

typedef void (*tfont_put)(int x, int y, void * arg);

void tfont_setSize(int size);

int tfont_getSize();

void tfont_setPainter(tfont_put put, void *arg);

int tfont_width(char const *code);

int tfont_render(int x, int y, char const *code);