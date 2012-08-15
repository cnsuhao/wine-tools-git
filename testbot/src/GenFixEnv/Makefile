CROSSCC32=i686-pc-mingw32-gcc
CROSSSTRIP=i686-pc-mingw32-strip
BINDIR=../../bin

all: ${BINDIR}/GenFixEnv.exe

${BINDIR}/GenFixEnv.exe: GenFixEnv.c
	${CROSSCC32} -o ${BINDIR}/GenFixEnv.exe -O2 -D_WIN32_IE=0x0500 GenFixEnv.c
	${CROSSSTRIP} ${BINDIR}/GenFixEnv.exe
