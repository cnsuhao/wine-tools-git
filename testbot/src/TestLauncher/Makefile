CROSSCC32=i686-pc-mingw32-gcc
CROSSCC64=x86_64-w64-mingw32-gcc
BINDIR=../../bin

all: ${BINDIR}/TestLauncher32.exe ${BINDIR}/TestLauncher64.exe

${BINDIR}/TestLauncher32.exe: TestLauncher.c
	${CROSSCC32} -o ${BINDIR}/TestLauncher32.exe TestLauncher.c

${BINDIR}/TestLauncher64.exe: TestLauncher.c
	${CROSSCC64} -o ${BINDIR}/TestLauncher64.exe TestLauncher.c
