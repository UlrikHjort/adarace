# AdaRace

A driving simulator in Ada and GtkAda, in the spirit of Assetto Corsa, made for
a Logitech G29 (an Xbox controller or the keyboard work too): circuits and a rally stage, a
motorcycle, a driving school, night, weather and seasons.

> **Built with AI.** Nearly all of this project was written by
> [Claude](https://www.anthropic.com/claude) Opus 5.5, Anthropic's AI model, working in
> Claude Code from the author's prompts. The AI wrote the code, shaders, tests
> and documentation; the author set the direction, drove the game on a real wheel and reported
> what felt right and what was broken. See [How this was made](#how-this-was-made).

![A forest rally stage](docs/gifs/rally.gif)

| | |
|---|---|
| ![The stage at night](docs/gifs/night.gif) | ![The stage in winter](docs/gifs/winter.gif) |
| Night, on the headlamps | Winter, snow falling |
| ![Rain from the cockpit](docs/gifs/rain.gif) | ![A night race on the street circuit](docs/gifs/race.gif) |
| Rain, from the cockpit | A night race through Havnebyen |
| ![The driving line in a lesson](docs/gifs/school.gif) | ![Autumn at dawn](docs/screenshots/autumn-dawn.jpg) |
| The driving school and its coloured line | Autumn at dawn |
| ![The Hyper on Boulevard Royal at dusk](docs/screenshots/boulevard.jpg) | ![Two players, split screen](docs/screenshots/split-screen.jpg) |
| The Hyper on Boulevard Royal, at dusk | Two players on one screen |
| ![A wheelie on the motorcycle](docs/gifs/bike-wheelie.gif) | ![The motorcycle from the helmet](docs/gifs/bike-helmet.gif) |
| The motorcycle, up on the back wheel | From the helmet at night, the horizon tilting with the bike |
| ![A GT3 in the golden hour](docs/screenshots/gt3-golden.jpg) | ![Fog on the stage](docs/screenshots/rally-fog.jpg) |
| A GT3 in the golden hour | Fog on the stage |
| ![A lesson passed](docs/screenshots/lesson-passed.jpg) | ![The menu and car setup](docs/screenshots/menu.jpg) |
| A lesson passed, with the coach's word | The menu and car setup |

All of it is the game itself with the AI driver at the wheel, made by
`scripts/make_media.sh`. `make demo` records a demo video with sound in the same way, and
`scripts/make_demo.sh bike` one of the motorcycle, ridden for show with wheelies and stoppies.

## Getting started

**Download:** take the Linux package from [Releases](../../releases), unpack it and run
`./adarace`; `README-FIRST.txt` says what it needs. Or build it yourself:

    make run

That needs GNAT, gprbuild, GtkAda, libepoxy and PulseAudio. `make check` says what is missing
and how to install it. On Debian, Ubuntu and Mint:

    sudo apt install gnat gprbuild libgtkada-dev libgtk-3-dev libepoxy-dev libpulse-dev pkg-config

The game needs a graphics card with OpenGL 4.5. A Logitech G29 and an Xbox controller are
found by themselves, and the keyboard always works. `ffmpeg` is optional, for F9 recordings and the co-driver's voice.

## The co-driver's voice

The co-driver speaks with clips made on your own machine the first time you run `make run`
(by `scripts/make_voice.sh`, which needs `ffmpeg`). Without a speech program it stays silent
and the arrows on the screen do the job. Two programs can make the voice:

- **espeak-ng**, the quick way: a clear but robotic voice.

      sudo apt install espeak-ng ffmpeg

- **Piper**, a natural voice: a neural speech program that runs on your own machine. Install
  it, for example with `pipx install piper-tts` (or `pip install --user piper-tts`), so that
  the `piper` command is found. Then download a voice: both its `.onnx` and `.onnx.json` files,
  for instance `en_US-lessac-medium` from the
  [Piper voices](https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/lessac/medium),
  into `~/.local/share/piper/`. Each voice has its own licence: see its model card.

The script uses Piper when it finds both `piper` and an English voice under your home folder,
and espeak-ng otherwise. The clips are made once; after installing Piper, make them again:

    FORCE=1 scripts/make_voice.sh

Elsewhere: `PIPER=/path/to/piper PIPER_VOICE=/path/to/voice.onnx FORCE=1 scripts/make_voice.sh`.
Your own voice works too: record each word to `sounds/codriver/<word>.pcm` (44.1 kHz, 16 bit,
mono, raw); the words are in the script.

## How this was made

AdaRace is an experiment in how far AI-led development can go on a real-time program in
Ada. Development was a conversation: the author asked for something ("let's do rally", "shall
we add weather?"), and Claude designed it, wrote it, tested it and reported back.

- **The AI's part:** the architecture, nearly all of the code, the physics and its tuning,
  the procedural graphics, the automated tests and this README.
- **The human's part:** the idea and the priorities, the driving, the bug reports and the
  judgement of how it feels, which no test can give. The stuck co-driver arrow and the
  look-back button that could not be undone were both found this way.
- **Reused code:** the G29, OpenGL and window layers began as code from the author's earlier
  driving project, and were extended here.

Code is checked by `make test` and by screenshots, but much of the tuning has had little
human driving yet, so expect rough edges. Commits made by the AI are marked with a
`Co-Authored-By` line.

## The simulation

Physics run at 1 kHz in an Ada task of their own, independent of the frame rate.

- **Tyres**: combined slip through a magic formula, carcass relaxation, load
  sensitivity, a temperature that changes the grip, and less grip on kerbs,
  grass and gravel.
- **Body**: four sprung corners with dampers and anti-roll bars, so weight
  moves under braking, acceleration and cornering. Elevation and banking act
  on the car, and aerodynamic drag and downforce grow with speed.
- **Drivetrain**: a torque curve, clutch, six gears, a limited slip
  differential. ABS and traction control are optional.
- **Force feedback**: comes from the aligning torque of the front tyres, so the
  wheel goes light at the limit, with kerbs, road surface and impacts on top.
  Sent at 125 Hz.

Five cars: a road GT, a GT3 with slicks and wings, a four wheel drive rally car, a light
classic and a mid-engined hypercar, and a motorcycle (see below). Five circuits: Søndersø Ring (4.9 km), Monte Ferro
(3.2 km, 64 m of climb), Kalvø Speedway (3.2 km, banked oval), the Havnebyen street circuit
(2.8 km, between walls along a harbour) and the Boulevard Royal street circuit on real
city streets (3.8 km), and three rally stages.

Hot laps against the ghost of your best lap, which is kept per car and circuit
in `~/.local/share/adarace`, or races against up to seven AI cars on the same
physics. A lap with all four wheels off the track does not count.

The cars have their own shapes: the GT3 low with flared arches, the R4 a tall hatchback.
From the cockpit, live gauges replace the speed panel. Bodywork crumples and scratches with
damage, and collects mud, dust or road salt on loose ground, which rain washes off.

## The motorcycle

![The motorcycle leaning through the bends of Monte Ferro](docs/gifs/bike-lean.gif)

The Nordic 1000 R is a litre sports bike: 150 kW, 275 kg with its rider, on one track.
It steers by leaning, as a real one does. The rider asks for a curve, and the bike rolls
towards the lean that curve needs, tan(lean) = v² / (g·r), as fast as a bike can roll.
It turns from that lean, not from the bars.

- **Grip:** the tyres share their grip between cornering and braking or driving. Grab the
  front brake hard at full lean, or spin the rear with too much throttle, and it goes down.
  The same happens if you ride onto grass leaned over or hit a wall hard. The rider gets up
  and is back on the road three seconds later.
- **Wheelies and stoppies:** the front lifts under full power in the low gears, and the
  rear under hard braking. With the aids on, the anti-wheelie and ABS keep both wheels down.
- **Controls:** the front brake is the brake pedal, and the rear brake is the handbrake
  (X on a controller, Space on the keyboard). On a controller, the stick asks for a share
  of the lean the tyres allow, so full stick is the most the bike can lean at any speed.
- **Views:** in the cockpit camera you look out of the helmet, over the clocks, and the
  horizon tilts with the lean.

The AI rides it too, round every circuit and stage.

## Controls

| Wheel | Xbox controller | Keyboard | |
|---|---|---|---|
| Steering, pedals | Left stick, RT / LT | Arrow keys | drive |
| Paddles | LB / RB | A / Z | shift up / down |
| H-shifter | | | choose an H-shifter gearbox in the menu (only with the wheel; the motorcycle is always sequential) |
| L3 | X (hold) | Space | handbrake (on the motorcycle: the rear brake) |
| | | X (hold) | reverse, automatic gearbox |
| Triangle | Y | C | camera: cockpit, hood, chase, far chase, trackside |
| Share | Back | V | mirror |
| | | G | ghost |
| | | H | panels |
| | | L | driving line |
| | | B | co-driver's voice |
| Square | Click the left stick | R | back on the track (the lap is lost; +15 s on a stage) |
| + / - or dial | | + / - | force feedback strength |
| R3 (press again for the front) | Click the right stick | W (hold) | look back |
| | | Q / E (hold) | look left / right |
| | | [ / ] | field of view |
| Options | Start | Esc | pause; then F5 / Square (X) restarts, F10 / Circle (B) goes to the menu |
| | F11 | fullscreen |
| Triangle in pause | F2 | replay the last ten minutes: arrows go back and forward, up/down set the speed, space stops it, C changes camera |
| | F9 | record a video with sound, F9 again stops (saved in `~/Videos/AdaRace`, needs ffmpeg) |

In the menu the d-pad moves between rows and changes values, and X starts (A on a
controller).

The controller rumbles on kerbs, on knocks and when you fall. Its light motor buzzes while a
tyre slides, and with the engine on the motorcycle. With two players, the controller belongs
to the second player.
Choices are remembered in `~/.adaracerc`.

## Checks

`make test` runs without a window or wheel: a parked car stays parked, standing
start and braking figures are believable, the gearbox modes work, the steering
pulls the right way, barriers hold, and the AI gets round every circuit.

`make wheel` shows what the wheel reports and applies no force. `make pad` does the same for
a controller and gives one short, light rumble.

`ADARACE_NOWHEEL=1` leaves the wheel alone. `ADARACE_SELFTEST=1` together with
`ADARACE_AUTOSTART=1` walks through pause, restart, menu, change of circuit and
car, and drives again by itself.

## Telemetry and tuning

Every drive is logged at 100 Hz and written as CSV when it ends, to
`~/.local/share/adarace/telemetry/` (the newest 20 files are kept). It holds
inputs, speed, slip, tyre loads and temperatures, steering torque and the force
sent to the wheel.

`bin/catch` (built by `make test`) measures how forgiving slides are: a simulated
driver with a 0.2 s reaction time overcooks a corner and countersteers. Handling
values can be tried without rebuilding, e.g. `bin/catch shape=1.25,rear_mu=1.15`.

If frame pacing misbehaves, `ADARACE_FRAME_SYNC=1` restores GTK's compositor
handshake, which is off by default because it halved the frame rate in testing.

## Graphics

Surfaces are painted by the program at start-up (`src/textures.adb`), so there are
no image files: asphalt aggregate, grass blades, gravel, and cut-out leaf and pine
cards, all with mipmaps. `shaders/world.frag` adds bump, tar snakes, corrugated
Armco, advert boards and the cars' wheel arches and door lines; `shaders/post.frag`
does bloom, tone mapping and grading.

## Setup, wear, fuel, damage and pit stops

The panel on the right of the menu sets springs, anti-roll bars, brake balance, final
drive, wing (GT3) and differential, remembered for each car. They apply to your car
only; the AI runs factory settings.

In races, tyres wear and fuel burns (menu: off, normal, three times as fast). Hot laps
always run on fresh tyres, so laps stay comparable. Hits damage aero, engine and steering
(off, light, full), and going back on the track with R mends nothing. To repair and
refuel, stop in the pit box: the yellow lines left of the road just past the start line.
The HUD darkens each tyre as it wears and shows fuel and damage.

## Rally

Choose *Skovvej (rally stage)* as the circuit and, ideally, the *Nordic R4*. The stage is
about 5 km of gravel road through a forest, timed from the lights to the finish arch.

- **Loose surface:** tyres peak at far more slip with little drop past it, so slides can
  be held. Grip depends on the tyre: the R4's gravel tyres are the best, slicks the worst.
- **Nordic R4:** four wheel drive with a centre differential and long-travel suspension.
- **Co-driver:** arrows at the top of the screen, read from the road's shape: L/R, then
  1 (hairpin) to 6 (nearly flat), LONG, and crests. Next corner on the left.
- **Spoken calls:** the same notes read out over the intercom ("right four long, over
  crest"), early enough to act on. `make run` makes the voice on your machine with Piper or
  espeak-ng: see [The co-driver's voice](#the-co-drivers-voice). The clips are not in git,
  because a voice has its own licence. B turns it off.
- **Trees are solid** and hurt the car. R puts you back on the road at +15 s and repairs
  nothing. Short cuts don't count: the stage only finishes along the road.

The road continues beyond the finish back to the start (it closes the loop in the data),
but a stage ends at the finish, and the marshals brake the car.

Mode *Rally* runs every stage in turn: Skovvej, Granbakken (tight, with hairpins) and Søvej
(wide and fast). Your times add up against five crews whose pace follows the AI strength, and
damage goes with you, half of it mended at each service.

The rivals each drive their own way, all season: Holm is quick and clean, Virta brave and
error-prone, Moreau hard to pass, Silva steady but tiring late in a race, Nagy wild. They brake
later or earlier, follow closer, cover the inside, and now and then overcook a corner.

Mode *Championship* races at every circuit in turn, with points for the first eight places
(25, 18, 15, 12, 10, 8, 6, 4) and the same named rivals all season.

Mode *Two players* splits the screen: player one above, on the wheel (or the arrow keys),
player two below, on a controller if there is one, and on the arrow keys when there is a
wheel or W A S D when there is not, with the gears changing by themselves. AI cars can race the two as well.

In races a car stopped on the circuit brings out a yellow flag, and if it stays stopped the
virtual safety car: everyone slows to about 60 % of racing speed, and going faster than that
for long costs five seconds at the finish. The pit lane runs along the left of the start and
finish straight with a 60 km/h limiter, the pit box in the middle of it.

Online on your home network: one machine chooses *Online: host a race* and the circuit and
laps; the other chooses *Online: join a race*, types the host's address (or its name) in *Host
to join* and presses DRIVE. Both start on the same lights. Each machine drives its own car and
sends where it is thirty times a second (UDP port 41000); the other car is drawn there, carried
on by its speed between messages. Each side draws the other in its own car's shape, and only
two can race; it is meant for a home network, not the internet.

## Your own roads

Roads are text files in `tracks/`, read at start in the order of their names, so a new circuit
or stage needs no code. `tracks/04-skovvej.track` is a good one to start from:

    name My Road
    kind stage             # or circuit
    finish 400 500         # a stage only: where the clock stops
    points
    #    x      z  height  half-width  banking
         0      0      10         4.2        0
       300     40      12         4.2        0
    ...

A street circuit adds `setting city`: walls at the kerb with a catch fence, street lamps, a
town of buildings and square corners. `water x z radius` digs a harbour basin there.

Real streets: `scripts/osm_road.py` makes a street circuit from OpenStreetMap data. Give it the
map and a few points to pass through, and it routes along drivable roads, rounds the corners,
and brings the real buildings beside the route (as `block` lines, at their size and height)
and the river (as `water`). `tracks/08-boulevard.track`, Boulevard Royal, was made so from a
real city centre: a long boulevard, a turn down an avenue to the river and back along the quay.

The points are in metres and join into a closed loop, so a stage has a road home after its
finish. Banking is in degrees, positive when the right side is lower. Keep parts of the road
40 m apart and corners over about 12 m radius. A bad file is left out with a message naming
the line, and `make test` drives the AI round everything in the folder.

## Driving school and coach

Mode *Driving school* has six lessons with measured goals: following the line, braking,
slow in fast out, catching a slide, staying on gravel and the whole stage. A lesson sets
its own circuit and car and saves no records. F5 tries again.

*Driving aids* in the menu turn on the driving line in any mode (L toggles it): dashes on
the road, green below the speed the line allows, yellow near it, red above it. With the
coach on, a tip after each lap names the corner that cost most. The line's speeds are the
AI's, so a good driver can beat them.

## Light, weather and seasons

- **Light:** morning, noon, golden hour, overcast, dawn, dusk and night, with headlamps.
- **Weather:** clear, rain, fog and snow. Rain and snow change the grip for every car and
  the AI's speeds; slicks suffer most in the wet, the R4 least on snow. Laps in rain, fog,
  snow or winter keep their own records.
- **Seasons:** summer, autumn colours, winter (snow on everything; rain falls as snow) and
  spring blossom. Winter grips like snow even under a clear sky.

## Development

`main` should always build and pass `make test`, which GitHub checks on every pull request.
Work happens on a branch per feature or fix. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT: see [LICENSE](LICENSE). The Boulevard Royal road file, `tracks/08-boulevard.track`, is
made from OpenStreetMap data: map data © OpenStreetMap contributors, available under the
[Open Database Licence](https://www.openstreetmap.org/copyright).
