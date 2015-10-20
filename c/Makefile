CC         = gcc 
CFLAGS     = -g -Wall -Wextra -O3 -std=gnu11 -Isrc
LIBS       = -ldl -lm -lz

all: build genome_cadd genome_hasher genome_scorer
	
clean:
	rm -rf bin/

build:
	@mkdir -p bin 

install: all
	cp bin/genome_cadd bin/genome_hasher bin/genome_scorer ~/bin

genome_cadd: build
	$(CC) $(CFLAGS) $(LIBS) src/$@.c src/argtable3.c -o bin/$@

genome_hasher: build
	$(CC) $(CFLAGS) $(LIBS) src/$@.c src/argtable3.c -o bin/$@

genome_scorer: build
	$(CC) $(CFLAGS) $(LIBS) src/$@.c src/argtable3.c -o bin/$@

## end of Makefile
# DO NOT DELETE THIS LINE -- make depend depends on it.
