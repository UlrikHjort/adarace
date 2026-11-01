--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Synthesised sound, mixed in a task of its own and played through
--  PulseAudio: the engine from its firing pulses, tyres, wind, kerbs and the
--  other cars.  Without a sound server the game is simply silent.

with Codriver;

package Audio is

   type Engine_Kind is (V8, V10, Turbo_Four, Old_Four);

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
      Engine   : Engine_Kind := V8;
      Rain     : Float := 0.0;    --  0 .. 1
      Snowy    : Boolean := False; --  what is under the tyres is soft
      Wipers   : Boolean := False;
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

   procedure Speak (W : Codriver.Word);
   --  Over the intercom: one word after another; silent if it has no clip

   function Has_Voice return Boolean;

   procedure Start_Capture (File : String);
   procedure Stop_Capture;
   --  The mix into a raw file (16 bit, 44.1 kHz, stereo), at a fixed level
   --  whatever the volume is set to

   function Playing return Boolean;
   --  There is a sound server, and the mixer is running

   function Peak return Float;
   --  The loudest sample of the last block, before the volume (a check)

end Audio;
