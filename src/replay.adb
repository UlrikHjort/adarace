--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
package body Replay is

   type Frame_Array is array (0 .. Most - 1) of Sim_Loop.Frame;
   type Frame_Access is access Frame_Array;

   Store : Frame_Access;
   Count : Natural := 0;       --  held
   Head  : Natural := 0;       --  where the next goes
   Last_Time : Long_Float := -1.0;
   Watch : Float := 0.0;       --  seconds from the oldest held

   procedure Clear is
   begin
      Count := 0;
      Head := 0;
      Last_Time := -1.0;
      Active := False;
   end Clear;

   procedure Keep (F : Sim_Loop.Frame) is
   begin
      if Store = null then
         Store := new Frame_Array;
      end if;
      if Last_Time >= 0.0 and then F.Time - Last_Time < Long_Float (1.0 / Rate) then
         return;
      end if;
      Last_Time := F.Time;
      Store (Head) := F;
      Head := (Head + 1) mod Most;
      Count := Natural'Min (Most, Count + 1);
   end Keep;

   function Length return Float is
     (Float'Max (0.0, Float (Count - 1) / Rate));

   --  The K'th frame held, oldest first
   function At_Index (K : Natural) return Sim_Loop.Frame is
     (Store ((Head - Count + Natural'Min (K, Count - 1) + Most) mod Most));

   procedure Start is
   begin
      if Count >= 2 then
         Active := True;
         Speed := 1.0;
         --  From a little before the end: what just happened
         Watch := Float'Max (0.0, Length - 30.0);
      end if;
   end Start;

   procedure Stop is
   begin
      Active := False;
   end Stop;

   procedure Seek (Seconds : Float) is
   begin
      Watch := Float'Max (0.0, Float'Min (Length, Watch + Seconds));
   end Seek;

   procedure Advance (Dt : Float) is
   begin
      Seek (Dt * Speed);
   end Advance;

   function Position return Float is (Watch);

   procedure Pair (Now : Long_Float; Prev, Cur : out Sim_Loop.Frame) is
      Exact : constant Float := Watch * Rate;
      K : constant Natural := Natural (Float'Floor (Exact));
      Part : constant Float := Exact - Float (K);
      Step : constant Long_Float := Long_Float (1.0 / Rate);
   begin
      Prev := At_Index (K);
      Cur := At_Index (K + 1);
      --  The renderer slides from one to the other by the clock
      Prev.Time := Now - Long_Float (Part) * Step;
      Cur.Time := Prev.Time + Step;
   end Pair;

end Replay;
