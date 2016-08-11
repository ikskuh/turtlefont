all: demo

demo: $(wildcard *.c) $(wildcard *.h)
	gcc -g -O3 -lSDL -o $@ $(wildcard *.c)