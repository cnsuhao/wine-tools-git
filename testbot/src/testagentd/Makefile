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

testagentd.o testagentd.obj: platform.h
platform_unix.o: platform.h list.h
platform_windows.obj: platform.h list.h

iso: winetestbot.iso

winetestbot.iso: TestAgentd.exe
	rm -rf winetest
	mkdir winetest
	cp TestAgentd.exe winetest
	mkisofs="mkisofs"; \
	type mkisofs >/dev/null 2>&1 || mkisofs="genisoimage"; \
	"$$mkisofs" -quiet -J -r -V "WineTestBot" -input-charset "ascii" -o "winetestbot.iso" winetest
	rm -rf winetest


clean:
	rm -f *.obj *.o
	rm -f TestAgentd.exe
	rm -f winetestbot.iso
