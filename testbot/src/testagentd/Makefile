builddir = ../../bin/build

CROSSCC32    = i686-w64-mingw32-gcc
CROSSSTRIP32 = i686-w64-mingw32-strip

all: build iso
build: $(builddir)/testagentd
windows: TestAgentd.exe


$(builddir)/testagentd: testagentd.o platform_unix.o
	gcc -o $@ $^
	strip $@

.c.o:
	gcc -Wall -c -o $@ $<


TestAgentd.exe: testagentd.obj platform_windows.obj
	$(CROSSCC32) -o $@ $^ -lws2_32
	$(CROSSSTRIP32) $@

.SUFFIXES: .obj
.c.obj:
	$(CROSSCC32) -Wall -c -o $@ $<


iso: windows
	mkdir winetest
	cp TestAgentd.exe winetest
	mkisofs="mkisofs"; \
	type mkisofs >/dev/null 2>&1 || mkisofs="genisoimage"; \
	"$$mkisofs" -quiet -J -r -V "WineTestBot" -input-charset "ascii" -o "winetestbot.iso" winetest
	rm -rf winetest


clean:
	rm *.obj *.o
	rm TestAgentd.exe
	rm winetestbot.iso
