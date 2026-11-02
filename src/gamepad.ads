--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A game controller (an Xbox pad and its like): the left stick steers, the
--  triggers are throttle and brake, the buttons speak the same names as the
--  wheel's, so the menus and the pause work the same; and it rumbles.

with Wheel;

package Gamepad is

   type Input is record
      Steer    : Float := 0.0;   --  -1 left .. 1 right
      Throttle : Float := 0.0;   --  0 .. 1
      Brake    : Float := 0.0;
   end record;

   procedure Open;
   --  Look for a controller under /dev/input/by-id; quietly nothing if none

   procedure Close;

   procedure Poll;
   --  What it sent since the last call; one plugged in later is found too

   function Present return Boolean;
   function State return Input;
   function Name return String;

   function Next_Press (B : out Wheel.Button) return Boolean;
   --  Buttons pressed since the last Poll: A Cross, B Circle, X Square,
   --  Y Triangle, LB/RB the paddles, Back Share, Start Options, the d-pad

   function Held (B : Wheel.Button) return Boolean;

   procedure Rumble (Strong, Weak : Float);
   --  0 .. 1, the heavy motor and the light one

   --  How a stick's raw reading becomes steering: a dead zone, then finer
   --  near the middle (for the tests)
   function Shape (Raw, Low, High : Float) return Float;

end Gamepad;
