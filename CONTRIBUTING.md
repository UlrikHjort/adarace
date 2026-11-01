# Contributing

AdaRace is built mostly by an AI working from prompts (see the README), and contributions
from people are just as welcome: code, tuning, new roads or how a car feels.

- **New roads need no code:** add a file to `tracks/`, see "Your own roads" in the README.
- **Branches:** one per feature or fix, merged through a pull request. `main` should always
  build and pass the tests.
- **Before a pull request:** `make test`. It runs without a window or wheel, and drives the AI
  round every road with every car, so a new road or car is tested as soon as it exists.
  The game itself: `ADARACE_SELFTEST=1 ADARACE_AUTOSTART=1 ADARACE_NOWHEEL=1 make run`.
- **What tests cannot judge:** how it feels and sounds. Say what you drove and what felt wrong;
  a CSV from `~/.local/share/adarace/telemetry` helps a lot.

**Force feedback can hurt.** Never send a stronger force to a wheel without trying it by hand
first. Forces stay within the limit in `src/sim_loop.adb`.
