CROSSCC32    = i686-w64-mingw32-gcc
CROSSSTRIP32 = i686-w64-mingw32-strip
CROSSWINDRES = i686-w64-mingw32-windres
CROSSZIPEXE  = upx-ucl

all: ReportTest.exe

ReportTest.exe: reporttest.obj reporttest.res
	$(CROSSCC32) -Wall -o $@ $^
	$(CROSSSTRIP32) $@
	if which $(CROSSZIPEXE); \
	then \
	    $(CROSSZIPEXE) --best -q -q $@; \
	fi

.SUFFIXES: .obj
.c.obj:
	$(CROSSCC32) -Wall -g -c -o $@ $<

.SUFFIXES: .rc .res
.rc.res:
	$(CROSSWINDRES) -O coff -o $@ $<

reporttest.res: report.template

clean:
	rm -f *.obj *.res
	rm -f ReportTest.exe
