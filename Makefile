all: demo

demo: $(wildcard *.c) $(wildcard *.h)
	gcc -lSDL -o $@ $(wildcard *.c)