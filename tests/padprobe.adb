--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Read the game controller for a few seconds and say what it reports:
--  move the stick and squeeze the triggers.  A short, light rumble at the end.

with Ada.Text_IO; use Ada.Text_IO;
with Gamepad;
with Wheel;

procedure Padprobe is
   B : Wheel.Button;
   package F is new Float_IO (Float);
begin
   Gamepad.Open;
   if not Gamepad.Present then
      Put_Line ("No controller found");
      return;
   end if;
   for I in 1 .. 30 loop
      Gamepad.Poll;
      while Gamepad.Next_Press (B) loop
         Put_Line ("  button " & B'Image);
      end loop;
      if I mod 5 = 0 then
         Put ("  steer ");
         F.Put (Gamepad.State.Steer, 2, 2, 0);
         Put ("  throttle ");
         F.Put (Gamepad.State.Throttle, 2, 2, 0);
         Put ("  brake ");
         F.Put (Gamepad.State.Brake, 2, 2, 0);
         New_Line;
      end if;
      delay 0.1;
   end loop;
   Gamepad.Rumble (0.0, 0.25);
   delay 0.3;
   Gamepad.Rumble (0.0, 0.0);
   Gamepad.Close;
end Padprobe;
