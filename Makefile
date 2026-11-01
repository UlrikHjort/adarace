# AdaRace: a driving simulator in Ada
#
#   make         build the game
#   make run     build and start it
#   make test    the headless physics and circuit checks
#   make wheel   read the wheel for three seconds (never applies a force)
#   make clean

all: game

game:
	gprbuild -p -P adarace.gpr -j0

run: game voice
	./bin/adarace

voice:
	@scripts/make_voice.sh

test:
	gprbuild -p -P simtest.gpr -j0
	./bin/simtest

wheel:
	gprbuild -p -P wheelprobe.gpr
	./bin/wheelprobe

clean:
	gprclean -q -P adarace.gpr
	gprclean -q -P simtest.gpr
	gprclean -q -P wheelprobe.gpr

.PHONY: all game run voice test wheel clean
