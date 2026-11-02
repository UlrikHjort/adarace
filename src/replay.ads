--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The last ten minutes of a drive, kept as the frames the picture was made
--  from (twenty a second), to be watched again from the trackside: forward,
--  back, slower, faster.

with Sim_Loop;

package Replay is

   Rate : constant := 20.0;                  --  frames kept a second
   Most : constant := 12_000;                --  ten minutes

   procedure Clear;
   procedure Keep (F : Sim_Loop.Frame);
   --  Each frame drawn while driving; kept when it is due

   function Length return Float;
   --  Seconds held

   Active : Boolean := False;
   Speed  : Float := 1.0;                    --  0 stands still

   procedure Start;
   procedure Stop;

   procedure Advance (Dt : Float);
   procedure Seek (Seconds : Float);

   procedure Pair (Now : Long_Float; Prev, Cur : out Sim_Loop.Frame);
   --  The two frames around the moment being watched, timed so that the
   --  picture slides between them as it does live

   function Position return Float;

end Replay;
