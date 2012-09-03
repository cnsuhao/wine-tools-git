bindir = ../../bin/windows

CROSSCC32    = i686-w64-mingw32-gcc
CROSSSTRIP32 = i686-w64-mingw32-strip

all: $(bindir)/GenFixEnv.exe

$(bindir)/GenFixEnv.exe: GenFixEnv.c
	$(CROSSCC32) -o $@ $<
	$(CROSSSTRIP32) $@
