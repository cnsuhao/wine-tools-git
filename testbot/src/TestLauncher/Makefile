bindir = ../../bin/windows

CROSSCC32    = i686-w64-mingw32-gcc
CROSSSTRIP32 = i686-w64-mingw32-strip
CROSSCC64    = x86_64-w64-mingw32-gcc
CROSSSTRIP64 = x86_64-w64-mingw32-strip

all: TestLauncher32.exe TestLauncher64.exe

TestLauncher32.exe: TestLauncher.c
	$(CROSSCC32) -Wall -o $@ $<
	$(CROSSSTRIP32) $@

TestLauncher64.exe: TestLauncher.c
	$(CROSSCC64) -Wall -o $@ $<
	$(CROSSSTRIP64) $@

clean:
	rm -f TestLauncher32.exe TestLauncher64.exe
