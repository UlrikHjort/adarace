--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

package body School is

   use Ada.Numerics.Elementary_Functions;
   use type Session.Mode_Kind;
   use type Track.Surface_Kind;
   use type Track.Note_Kind;

   Dt : constant := 0.001;

   --  Where each lesson stops, in metres from the line
   function Distance (L : Lesson_Id) return Float is
     (case L is
         when 1 => 2000.0,
         when 2 => 1600.0,
         when 3 => Track.Length - 30.0,
         when 4 => 1500.0,
         when 5 => 2500.0,
         when 6 => Track.Stage_End - 5.0);

   --  How much slower than the line's own time still passes
   function Par_Factor (L : Lesson_Id) return Float is
     (case L is
         when 1 => 1.8,
         when 2 => 1.7,
         when 3 => 1.25,
         when 4 => 2.0,
         when 5 => 1.5,
         when 6 => 1.3);

   function Title (L : Lesson_Id) return String is
     (case L is
         when 1 => "1. Follow the line",
         when 2 => "2. Brake before the corner",
         when 3 => "3. Slow in, fast out",
         when 4 => "4. Catch the slide",
         when 5 => "5. Stay on the gravel",
         when 6 => "6. The whole stage");

   function Goal (L : Lesson_Id) return String is
     (case L is
         when 1 => "Keep on the line: green go, yellow ease off, red brake. 70 % on it, within the time.",
         when 2 => "Brake on the red, in a straight line. At most two corners entered too fast.",
         when 3 => "A whole lap, nothing off the road. Give up entry speed to be early on the throttle.",
         when 4 => "Slide on purpose: lift or brake into a bend, then countersteer. Catch three, stay on.",
         when 5 => "Read the co-driver's arrows. No resets, no trees, nothing off the road.",
         when 6 => "All of it, at pace. No resets.");

   function Circuit (L : Lesson_Id) return Track.Track_Id is
     (case L is when 1 | 3 => 1, when 2 => 2, when others => 4);

   function Car (L : Lesson_Id) return Vehicle.Car_Kind is
     (case L is when 1 .. 3 => Vehicle.Road_GT, when others => Vehicle.Rally_4WD);

   function Prepare (L : Lesson_Id; S : Session.Settings) return Session.Settings is
      R : Session.Settings := S;
   begin
      R.Kind := Car (L);
      R.Mode := (if Track.Is_Stage then Session.Stage else Session.Hotlap);
      R.Opponents := 0;
      R.No_Records := True;
      R.Assist.Damage := 0.5;
      R.Tune := (others => <>);
      return R;
   end Prepare;

   --  The coach --------------------------------------------------------------

   type Corner_Watch is record
      Over, Under : Float := 0.0;   --  worst, m/s, against the line's speed
   end record;
   Watch : array (1 .. Track.Note_Array'Last) of Corner_Watch;
   Coach_Lap : Natural := 0;
   Coach_Done : Boolean := False;
   Lead_In : constant := 25.0;      --  metres before the corner it counts from

   procedure Say (Text : String) is
      N : constant Natural := Natural'Min (Text'Length, Tip_Size);
   begin
      Tip (1 .. N) := Text (Text'First .. Text'First + N - 1);
      Tip_Len := N;
      Tip_Serial := Tip_Serial + 1;
   end Say;

   function Km (S : Float) return String is
      Tenths : constant Natural := Natural (S / 100.0);
      W : constant String := Natural'Image (Tenths / 10);
      F : constant String := Natural'Image (Tenths mod 10);
   begin
      return W (W'First + 1 .. W'Last) & "." & F (F'First + 1 .. F'Last) & " km";
   end Km;

   function Kmh (V : Float) return String is
      W : constant String := Natural'Image (Natural (V * 3.6));
   begin
      return W (W'First + 1 .. W'Last);
   end Kmh;

   function Name_Of (N : Track.Note) return String is
      G : constant String := Positive'Image (N.Grade);
   begin
      return (if N.Kind = Track.Right then "Right " else "Left ") & G (G'First + 1 .. G'Last);
   end Name_Of;

   procedure Report is
      Worst_Over, Worst_Under : Natural := 0;
      Max_Over : Float := 2.8;      --  10 km/h: less is not worth a word
      Max_Under : Float := 5.5;     --  20 km/h
   begin
      for K in 1 .. Track.Note_Count loop
         if Track.Notes (K).Kind /= Track.Crest then
            if Watch (K).Over > Max_Over then
               Max_Over := Watch (K).Over;
               Worst_Over := K;
            end if;
            if Watch (K).Under > Max_Under then
               Max_Under := Watch (K).Under;
               Worst_Under := K;
            end if;
         end if;
      end loop;
      if Worst_Over > 0 then
         Say (Name_Of (Track.Notes (Worst_Over)) & " at " & Km (Track.Notes (Worst_Over).S) & ": "
              & Kmh (Max_Over) & " km/h too fast going in. Brake earlier.");
      elsif Worst_Under > 0 then
         Say (Name_Of (Track.Notes (Worst_Under)) & " at " & Km (Track.Notes (Worst_Under).S) & ": "
              & Kmh (Max_Under) & " km/h to spare. You can carry more speed.");
      else
         Say ("Clean: every corner close to the line's speed.");
      end if;
      Watch := (others => (0.0, 0.0));
   end Report;

   procedure Coach (C : Vehicle.Car; L : Session.Lap_Info) is
      Here : constant Float := L.S;
      V : constant Float := Vehicle.Speed (C);
      Line : constant Float := Track.Samples (C.Hint).Line_V;
   begin
      if L.On_Grid then
         return;
      end if;
      declare
         N : constant Natural := Track.Next_Note (Here);
      begin
         if N > 0 and then Track.Notes (N).Kind /= Track.Crest
           and then Track.Notes (N).S - Here < Lead_In
         then
            Watch (N).Over := Float'Max (Watch (N).Over, V - Line);
            --  Only slow if it was a matter of choice, not after a mishap
            if V > 5.0 then
               Watch (N).Under := Float'Max (Watch (N).Under, Line - V);
            end if;
         end if;
      end;
      if L.Lap /= Coach_Lap then
         Coach_Lap := L.Lap;
         Report;
      end if;
      if L.Finished and then not Coach_Done then
         Coach_Done := True;
         Report;
      end if;
   end Coach;

   --  The lesson -------------------------------------------------------------

   Progress, Travelled, Line_Metres : Float := 0.0;
   Line_Time_To_End : Float := 0.0;
   Slide_T : Float := 0.0;
   Sliding : Boolean := False;
   Was_Off : Boolean := False;
   Over_Corner : Natural := 0;
   Resets_At_Start : Natural := 0;

   procedure Begin_Lesson (L : Natural) is
   begin
      Current := (others => <>);
      Watch := (others => (0.0, 0.0));
      Coach_Lap := 0;
      Coach_Done := False;
      Tip_Len := 0;
      Progress := 0.0;
      Travelled := 0.0;
      Line_Metres := 0.0;
      Slide_T := 0.0;
      Sliding := False;
      Was_Off := False;
      Over_Corner := 0;
      Resets_At_Start := Session.Laps (1).Resets;
      if L in Lesson_Id then
         Current.Lesson := L;
         Current.Phase := Running;
         Line_Time_To_End := 0.0;
         declare
            Stop : constant Float := Distance (L);
         begin
            for I in 0 .. Track.Count - 1 loop
               exit when Track.Samples (I).S > Stop;
               Line_Time_To_End := Line_Time_To_End
                 + Track.Spacing / Float'Max (5.0, Track.Samples (I).Line_V);
            end loop;
         end;
         Current.Par := Line_Time_To_End * Par_Factor (L) + 4.0;
      end if;
   end Begin_Lesson;

   procedure Finish (L : Lesson_Id) is
      Share : constant Float := Line_Metres / Float'Max (1.0, Travelled);
      In_Time : constant Boolean := Current.Time <= Current.Par;
      Resets : constant Natural := Session.Laps (1).Resets - Resets_At_Start;
      Good : constant Boolean :=
        In_Time and then
        (case L is
            when 1 => Share >= 0.7,
            when 2 => Current.Too_Fast <= 2 and then Current.Offs = 0,
            when 3 => Current.Offs = 0,
            when 4 => Current.Slides >= 3 and then Current.Offs = 0,
            when 5 => Current.Offs = 0 and then Resets = 0
                        and then Session.Cars (1).Dmg_Aero = 0.0,
            when 6 => Resets = 0);
   begin
      Current.On_Line := Share;
      Current.Done := 1.0;
      Current.Phase := (if Good then Passed else Failed);
      Report;
   end Finish;

   procedure Step (Hands : Vehicle.Inputs) is
      pragma Unreferenced (Hands);
      C : Vehicle.Car renames Session.Cars (1);
      L : Session.Lap_Info renames Session.Laps (1);
   begin
      if Session.Config.Mode = Session.Demo then
         return;
      end if;
      if Current.Phase /= Running then
         if Current.Phase = Off then
            Coach (C, L);
         end if;
         return;
      end if;
      Coach (C, L);
      if L.On_Grid then
         return;
      end if;
      Current.Time := Current.Time + Dt;
      declare
         S : constant Float := Track.Samples (C.Hint).S;
         V : constant Float := Vehicle.Speed (C);
         Lesson : constant Lesson_Id := Current.Lesson;
         Idx : Natural;
         T, D : Float;
         Hint : Natural := C.Hint;
         All_Off : Boolean := True;
         Beta : constant Float := Arctan (C.Vy, Float'Max (2.0, abs C.Vx));
      begin
         if S >= Progress and then S < Progress + 60.0 then
            Progress := S;
         end if;
         Travelled := Travelled + V * Dt;
         Track.Locate (Float (C.X), Float (C.Z), Hint, Idx, T, D);
         if abs (D - Track.Samples (Idx).Line_D) < 2.5 then
            Line_Metres := Line_Metres + V * Dt;
         end if;
         Current.Done := Float'Min (1.0, Progress / Distance (Lesson));
         Current.On_Line := Line_Metres / Float'Max (1.0, Travelled);
         --  Off the road: all four
         for W in Vehicle.Wheel_Id loop
            All_Off := All_Off
              and then C.Wheels (W).Surf in Track.Grass | Track.Gravel;
         end loop;
         if All_Off and then not Was_Off then
            Current.Offs := Current.Offs + 1;
         end if;
         Was_Off := All_Off;
         --  Corners entered too fast
         declare
            N : constant Natural := Track.Next_Note (S);
         begin
            if N > 0 and then N /= Over_Corner
              and then Track.Notes (N).Kind /= Track.Crest
              and then Track.Notes (N).S - S < Lead_In
              and then V - Track.Samples (C.Hint).Line_V > 3.3
            then
               Over_Corner := N;
               Current.Too_Fast := Current.Too_Fast + 1;
            end if;
         end;
         --  A slide: well sideways for a moment, then straight again
         if V > 8.0 and then abs Beta > 0.17 then
            Slide_T := Slide_T + Dt;
            Sliding := Sliding or else Slide_T > 0.3;
         elsif abs Beta < 0.06 then
            if Sliding and then not All_Off then
               Current.Slides := Current.Slides + 1;
            end if;
            Sliding := False;
            Slide_T := 0.0;
         end if;
         if Progress >= Distance (Lesson) then
            Finish (Lesson);
         end if;
      end;
   end Step;

   function Result_Line return String is
      function Whole (F : Float) return String is
         W : constant String := Natural'Image (Natural (F));
      begin
         return W (W'First + 1 .. W'Last);
      end Whole;
      Time_Part : constant String :=
        "Time " & Whole (Current.Time) & " s, par " & Whole (Current.Par) & " s. ";
   begin
      if Current.Lesson not in Lesson_Id then
         return "";
      end if;
      return Time_Part &
        (case Lesson_Id'(Current.Lesson) is
            when 1 => "On the line " & Whole (Current.On_Line * 100.0) & " %, 70 needed.",
            when 2 => "Too fast into" & Current.Too_Fast'Image & " corners, 2 allowed; off" & Current.Offs'Image & ".",
            when 3 => "Off the road" & Current.Offs'Image & " times.",
            when 4 => "Slides caught" & Current.Slides'Image & ", 3 needed; off" & Current.Offs'Image & ".",
            when 5 => "Off the road" & Current.Offs'Image & " times.",
            when 6 => "Resets" & Session.Laps (1).Resets'Image & ".");
   end Result_Line;

end School;
