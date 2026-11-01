--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The driving school: lessons with a goal that is measured, and the coach,
--  who watches every corner against the speed the racing line allows and
--  says after each lap what cost the most.  Pure simulation, like Session.

with Session;
with Track;
with Vehicle;

package School is

   Lesson_Count : constant := 6;
   subtype Lesson_Id is Positive range 1 .. Lesson_Count;

   function Title (L : Lesson_Id) return String;
   function Goal (L : Lesson_Id) return String;
   --  What to do, one line for the screen

   function Circuit (L : Lesson_Id) return Track.Track_Id;
   function Car (L : Lesson_Id) return Vehicle.Car_Kind;

   type Phase_Kind is (Off, Running, Passed, Failed);

   type Status is record
      Lesson   : Natural := 0;
      Phase    : Phase_Kind := Off;
      Done     : Float := 0.0;    --  0 .. 1 of the way
      On_Line  : Float := 0.0;    --  share of the distance on the line
      Too_Fast : Natural := 0;    --  corners entered well over the line's speed
      Slides   : Natural := 0;    --  slides caught
      Offs     : Natural := 0;    --  times right off the road
      Time     : Float := 0.0;
      Par      : Float := 0.0;    --  the time to beat
   end record;

   Current : Status;

   Tip_Size : constant := 100;
   Tip      : String (1 .. Tip_Size) := (others => ' ');
   Tip_Len  : Natural := 0;
   Tip_Serial : Natural := 0;     --  goes up with every new tip

   procedure Begin_Lesson (L : Natural);
   --  After Session.Start, 0 for none: the coach alone

   function Prepare (L : Lesson_Id; S : Session.Settings) return Session.Settings;
   --  The settings a lesson needs: its car, no opponents, no records

   procedure Step (Hands : Vehicle.Inputs);
   --  After each Session.Step

   function Result_Line return String;
   --  Why it passed or failed

end School;
