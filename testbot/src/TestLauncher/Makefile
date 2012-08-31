bindir = ../../bin

CROSSCC32    = i686-w64-mingw32-gcc
CROSSSTRIP32 = i686-w64-mingw32-strip
CROSSCC64    = x86_64-w64-mingw32-gcc
CROSSSTRIP64 = x86_64-w64-mingw32-strip

all: $(bindir)/TestLauncher32.exe $(bindir)/TestLauncher64.exe

$(bindir)/TestLauncher32.exe: TestLauncher.c
	$(CROSSCC32) -o $@ $<
	$(CROSSSTRIP32) $@

$(bindir)/TestLauncher64.exe: TestLauncher.c
	$(CROSSCC64) -o $@ $<
	$(CROSSSTRIP64) $@
