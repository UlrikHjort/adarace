--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Synthesised sound, mixed in a task of its own and played through
--  PulseAudio: the engine from its firing pulses, tyres, wind, kerbs and the
--  other cars.  Without a sound server the game is simply silent.

package Audio is

   type Voice is record
      Rpm   : Float := 0.0;
      Level : Float := 0.0;   --  0 .. 1 by distance
      Pan   : Float := 0.0;   --  -1 left .. 1 right
   end record;

   type Voice_List is array (1 .. 4) of Voice;

   type Params is record
      Rpm      : Float := 1000.0;
      Load     : Float := 0.0;    --  throttle 0 .. 1
      Speed    : Float := 0.0;    --  m/s
      Squeal   : Float := 0.0;    --  0 .. 1
      Rumble   : Float := 0.0;    --  0 .. 1: kerb
      Dirt     : Float := 0.0;    --  0 .. 1: grass, gravel
      Scrape   : Float := 0.0;    --  0 .. 1: along a barrier
      Inside   : Boolean := True; --  heard from the cockpit
      Master   : Float := 0.8;
      Others_V : Voice_List;
   end record;

   procedure Start;
   procedure Stop;

   procedure Set (P : Params);

   procedure Thud (Strength : Float);
   --  A hit, 0 .. 1

   procedure Clunk;
   --  A gear going in

   procedure Beep (High : Boolean);
   --  Start lights

   function Peak return Float;
   --  The loudest sample of the last block, before the volume (a check)

end Audio;
