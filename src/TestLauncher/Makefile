CROSSCC32=i686-pc-mingw32-gcc
CROSSCC64=x86_64-w64-mingw32-gcc

all: TestLauncher32.exe TestLauncher64.exe

TestLauncher32.exe: TestLauncher.c
	${CROSSCC32} -o TestLauncher32.exe TestLauncher.c

TestLauncher64.exe: TestLauncher.c
	${CROSSCC64} -o TestLauncher64.exe TestLauncher.c
