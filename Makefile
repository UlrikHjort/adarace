# AdaRace: a driving simulator in Ada
#
#   make         build the game
#   make run     build and start it
#   make check   is everything needed to build it here?
#   make dist    the prebuilt download
#   make demo    a demo video with sound (dist/adarace-demo.mp4)
#   make test    the headless physics and circuit checks
#   make wheel   read the wheel for three seconds (never applies a force)
#   make clean

all: game

check:
	@scripts/check_deps.sh

game: check
	gprbuild -p -P adarace.gpr -j0

run: game voice
	./bin/adarace

demo: game voice
	@scripts/make_demo.sh

dist: game
	@scripts/make_dist.sh

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

.PHONY: all check game run demo dist voice test wheel clean
