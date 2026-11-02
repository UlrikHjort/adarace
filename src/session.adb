--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Streams.Stream_IO;

with Track;

package body Session is

   use Ada.Numerics.Elementary_Functions;
   use Vehicle;
   use type Track.Surface_Kind;
   use type Track.Note_Kind;

   Pi : constant := 3.14159_26535;

   type AI_State is record
      Skill     : Float := 0.95;
      Rush_Until : Float := -1.0;   --  a mistake under way: on until this S
      Last_Roll  : Float := 0.0;    --  where the dice were last thrown
      Offset    : Float := 0.0;   --  lateral, avoiding others
      Stuck_T   : Float := 0.0;
      Inputs    : Vehicle.Inputs;
      Throttle_I : Float := 0.0;
   end record;

   AI : array (Car_Index) of AI_State;
   Tick : Natural := 0;
   Dice : Ada.Numerics.Float_Random.Generator;

   --  Lap being driven, for the ghost and the delta
   Cur_Ghost  : constant Ghost_Access := new Ghost_Array;
   Cur_Frames : Natural := 0;
   Delta_Size : constant := 4000;
   type Delta_Table is array (0 .. Delta_Size) of Float;   --  time at each point of the lap
   type Delta_Access is access Delta_Table;
   Cur_Delta, Best_Delta : Delta_Access;

   function Clamp (V, Lo, Hi : Float) return Float is
     (Float'Max (Lo, Float'Min (Hi, V))) with Inline;

   Parked : Float := 0.0;

   function Character_Of (I : Car_Index) return Character is
     (case I is
         when 2 => (Pace => 0.012, Aggression => 0.3, Defence => 0.5, Mistakes => 0.05, Fatigue => 0.002),
         when 3 => (Pace => 0.006, Aggression => 0.9, Defence => 0.3, Mistakes => 0.30, Fatigue => 0.003),
         when 4 => (Pace => 0.000, Aggression => 0.4, Defence => 0.95, Mistakes => 0.10, Fatigue => 0.002),
         when 5 => (Pace => 0.004, Aggression => 0.2, Defence => 0.4, Mistakes => 0.04, Fatigue => 0.008),
         when 6 => (Pace => -0.004, Aggression => 1.0, Defence => 0.6, Mistakes => 0.45, Fatigue => 0.004),
         when 7 => (Pace => -0.008, Aggression => 0.5, Defence => 0.5, Mistakes => 0.12, Fatigue => 0.003),
         when 8 => (Pace => -0.012, Aggression => 0.6, Defence => 0.7, Mistakes => 0.15, Fatigue => 0.005),
         when others => (Pace => 0.0, Aggression => 0.0, Defence => 0.0, Mistakes => 0.0, Fatigue => 0.0));

   function VSC_On return Boolean is (Time < VSC_Until);
   function VSC_Pace return Float is (0.6);

   Stopped_T : array (Car_Index) of Float := (others => 0.0);
   Too_Fast_T : Float := 0.0;

   --  Every twentieth of a second: has someone stopped on the circuit?
   procedure Watch_Race is
   begin
      if Config.Mode /= Race or else not Lights_Out then
         return;
      end if;
      for K in 1 .. Car_Count loop
         declare
            L : Lap_Info renames Laps (K);
         begin
            if not L.On_Grid and then not L.Finished and then Speed (Cars (K)) < 3.0 then
               Stopped_T (K) := Stopped_T (K) + 0.05;
               if Stopped_T (K) > 1.5 then
                  Yellow_S := Track.Samples (Cars (K).Hint).S;
                  Yellow_Until := Time + 12.0;
               end if;
               if Stopped_T (K) > 5.0 and then not VSC_On then
                  VSC_Until := Time + 25.0;
               end if;
            else
               Stopped_T (K) := 0.0;
            end if;
            if Cars (K).Impact > 16.0 then
               Yellow_S := Track.Samples (Cars (K).Hint).S;
               Yellow_Until := Time + 12.0;
            end if;
         end;
      end loop;
      if Time > Yellow_Until then
         Yellow_S := -1.0;
      end if;
      --  The player under the safety car: too fast for long, five seconds
      if VSC_On and then not Laps (1).Finished then
         if Speed (Cars (1)) > VSC_Pace * Track.Samples (Cars (1).Hint).Line_V + 3.0 then
            Too_Fast_T := Too_Fast_T + 0.05;
            if Too_Fast_T > 2.0 then
               Laps (1).Penalty := Laps (1).Penalty + VSC_Penalty;
               Too_Fast_T := 0.0;
            end if;
         else
            Too_Fast_T := Float'Max (0.0, Too_Fast_T - 0.05);
         end if;
      end if;
   end Watch_Race;

   function AI_Drives (I : Car_Index) return Boolean is
     ((I > 1 and then not (Config.Two_Players and then I = 2))
      or else Config.Mode = Demo or else Force_AI);

   function Save_Name return String is
      Home : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME") else ".");
      Dir : constant String := Home & "/.local/share/adarace";
      Tr : constant String := Track.Loaded'Image;
      Ca : constant String := Vehicle.Car_Kind'Image (Config.Kind);
      --  A lap in the rain is not to be held against one in the sun
      Wx : constant String :=
        (if Config.Weather = Clear then "" else "_" & Weather_Kind'Image (Config.Weather));
      Se : constant String :=
        (if Config.Season = Winter then "_WINTER" else "");
   begin
      return Dir & "/best_" & Tr (Tr'First + 1 .. Tr'Last) & "_" & Ca & Wx & Se & ".lap";
   end Save_Name;

   procedure Save_Best is
      use Ada.Streams.Stream_IO;
      F : File_Type;
      N : constant String := Save_Name;
   begin
      if Config.No_Records then
         return;
      end if;
      Ada.Directories.Create_Path (Ada.Directories.Containing_Directory (N));
      Create (F, Out_File, N);
      Float'Write (Stream (F), Laps (1).Best_Time);
      Natural'Write (Stream (F), Best_Frames);
      for I in 1 .. Best_Frames loop
         Ghost_Frame'Write (Stream (F), Best_Ghost (I));
      end loop;
      Delta_Table'Write (Stream (F), Best_Delta.all);
      Close (F);
   exception
      when others => null;   --  no best lap saved is no reason to stop
   end Save_Best;

   procedure Load_Best is
      use Ada.Streams.Stream_IO;
      F : File_Type;
      N : constant String := Save_Name;
      T : Float;
   begin
      Best_Frames := 0;
      if Best_Ghost = null then
         Best_Ghost := new Ghost_Array;
         Best_Delta := new Delta_Table;
         Cur_Delta := new Delta_Table;
      end if;
      if not Ada.Directories.Exists (N) then
         return;
      end if;
      Open (F, In_File, N);
      Float'Read (Stream (F), T);
      Natural'Read (Stream (F), Best_Frames);
      for I in 1 .. Best_Frames loop
         Ghost_Frame'Read (Stream (F), Best_Ghost (I));
      end loop;
      Delta_Table'Read (Stream (F), Best_Delta.all);
      Close (F);
      Laps (1).Best_Time := T;
   exception
      when others =>
         Best_Frames := 0;
         Laps (1).Best_Time := 0.0;
   end Load_Best;

   function Ghost_At (Time_In_Lap : Float) return Ghost_Frame is
      F : constant Float := Time_In_Lap * 20.0;
      I : constant Integer := Integer (Float'Floor (F));
   begin
      if Best_Frames < 2 or else I < 0 or else I + 2 > Best_Frames then
         return (others => 0.0);
      end if;
      declare
         A : Ghost_Frame renames Best_Ghost (I + 1);
         B : Ghost_Frame renames Best_Ghost (I + 2);
         T : constant Float := F - Float (I);
         DH : Float := B.Heading - A.Heading;
      begin
         if DH > Pi then
            DH := DH - 2.0 * Pi;
         elsif DH < -Pi then
            DH := DH + 2.0 * Pi;
         end if;
         return (A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T, A.Z + (B.Z - A.Z) * T,
                 A.Heading + DH * T, A.Pitch + (B.Pitch - A.Pitch) * T,
                 A.Roll + (B.Roll - A.Roll) * T);
      end;
   end Ghost_At;

   ---------------------------------------------------------------------------
   --  The AI driver: pure pursuit along the racing line, and pedals by the
   --  speed the line allows
   ---------------------------------------------------------------------------

   procedure Drive_AI (I : Car_Index) is
      C : Car renames Cars (I);
      St : AI_State renames AI (I);
      Ch : constant Character := Character_Of (I);
      V : constant Float := C.Vx;
      Idx : Natural;
      T, D : Float;
      Sp : constant Float := Speed (C);
   begin
      Track.Locate (Float (C.X), Float (C.Z), C.Hint, Idx, T, D);

      --  Make room for a car just ahead, or alongside
      declare
         Want : Float := 0.0;
         Self_S : constant Float := Track.Samples (Idx).S;
      begin
         for K in 1 .. Car_Count loop
            if K /= I then
               declare
                  DS0 : constant Float := Track.Samples (Cars (K).Hint).S - Self_S;
                  DS : constant Float :=
                    (if DS0 > Track.Length / 2.0 then DS0 - Track.Length
                     elsif DS0 < -Track.Length / 2.0 then DS0 + Track.Length else DS0);
                  Closing : constant Float := Sp - Speed (Cars (K));
                  Other_D : constant Float :=
                    Float (Cars (K).X - Long_Float (Track.Samples (Cars (K).Hint).X))
                    * Track.Samples (Cars (K).Hint).RX
                    + Float (Cars (K).Z - Long_Float (Track.Samples (Cars (K).Hint).Z))
                    * Track.Samples (Cars (K).Hint).RZ;
               begin
                  if (DS > -6.0 and then DS < 12.0 + Float'Max (0.0, Closing) * 2.5) then
                     declare
                        Line_Here : constant Float := Track.Samples (Idx).Line_D;
                        Rel : constant Float := Other_D - Line_Here;
                        Room_R : constant Float := Track.Samples (Idx).W_R - Other_D;
                        Room_L : constant Float := Other_D + Track.Samples (Idx).W_L;
                     begin
                        if abs Rel < 2.8 then
                           Want := (if Room_R > Room_L then Other_D + 3.0 else Other_D - 3.0)
                             - Line_Here;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
         --  Defend: a car close behind, a corner coming, cover the inside
         if Want = 0.0 and then Ch.Defence > 0.0 then
            for K in 1 .. Car_Count loop
               if K /= I then
                  declare
                     DS0 : constant Float := Track.Samples (Cars (K).Hint).S - Self_S;
                     DS : constant Float :=
                       (if DS0 > Track.Length / 2.0 then DS0 - Track.Length
                        elsif DS0 < -Track.Length / 2.0 then DS0 + Track.Length else DS0);
                     Bend : constant Float :=
                       Track.Samples (Track.Next (Idx, Integer (40.0 / Track.Spacing))).Kappa;
                  begin
                     if DS < -2.0 and then DS > -18.0 and then Speed (Cars (K)) > Sp - 1.0
                       and then abs Bend > 1.0 / 250.0
                     then
                        Want := (if Bend > 0.0 then 1.0 else -1.0) * 2.4 * Ch.Defence
                          - (Track.Samples (Idx).Line_D
                             - (if Bend > 0.0 then Track.Samples (Idx).W_R - 1.6
                                else -(Track.Samples (Idx).W_L - 1.6)))
                          * 0.0;
                     end if;
                  end;
               end if;
            end loop;
         end if;
         St.Offset := St.Offset + Clamp (Want - St.Offset, -0.03, 0.03);
      end;

      declare
         Look : constant Float := 5.0 + 0.32 * Float'Max (0.0, V);
         Steps : constant Integer := Integer (Look / Track.Spacing);
         J : constant Natural := Track.Next (Idx, Steps);
         A : Track.Sample renames Track.Samples (J);
         Off : constant Float :=
           Clamp (A.Line_D + St.Offset, -(A.W_L - 1.1), A.W_R - 1.1);
         TX : constant Float := A.X + A.RX * Off - Float (C.X);
         TZ : constant Float := A.Z + A.RZ * Off - Float (C.Z);
         FX : constant Float := Sin (C.Heading);
         FZ : constant Float := -Cos (C.Heading);
         RX : constant Float := -FZ;
         RZ : constant Float := FX;
         Ahead : constant Float := TX * FX + TZ * FZ;
         Side  : constant Float := TX * RX + TZ * RZ;
         L2 : constant Float := Ahead * Ahead + Side * Side;
         Wb : constant Float := Spec.A + Spec.B;
         Curv : constant Float := 2.0 * Side / Float'Max (1.0, L2);
         Delta_A : constant Float := Arctan (Wb * Curv);
         --  Yaw the car at the rate the arc asks for, and catch a slide
         Beta : constant Float :=
           (if abs V > 3.0 then Arctan (C.Vy, abs V) else 0.0);
         Rate_Err : constant Float := Curv * Float'Max (0.0, V) - C.Rate;
         Cmd : constant Float :=
           (Delta_A + 0.25 * Beta + 0.04 * Rate_Err) / Spec.Steer_Lock;
      begin
         St.Inputs.Steer := St.Inputs.Steer
           + Clamp (Cmd - St.Inputs.Steer, -0.04, 0.04);
      end;

      --  Pedals
      declare
         Slow_Ahead : Float := 1000.0;
         Self_S : constant Float := Track.Samples (Idx).S;
      begin
         --  Brake for a car straight ahead
         for K in 1 .. Car_Count loop
            if K /= I then
               declare
                  DS0 : constant Float := Track.Samples (Cars (K).Hint).S - Self_S;
                  DS : constant Float :=
                    (if DS0 < -Track.Length / 2.0 then DS0 + Track.Length else DS0);
                  Lat : constant Float :=
                    Float (Cars (K).X - C.X) * Track.Samples (Idx).RX
                    + Float (Cars (K).Z - C.Z) * Track.Samples (Idx).RZ;
               begin
                  if DS > 0.0 and then DS < 25.0 and then abs Lat < 1.9 - 0.4 * Ch.Aggression then
                     Slow_Ahead := Float'Min
                       (Slow_Ahead,
                        Speed (Cars (K)) + Float'Max (0.0, DS - 6.0 + 2.5 * Ch.Aggression) * 0.8);
                  end if;
               end;
            end if;
         end loop;
         declare
            Look : constant Natural := Track.Next (Idx, 1 + Integer (Sp * 0.14));
            Here_S : constant Float := Track.Samples (Idx).S;
            Tired : constant Float := 1.0 - Ch.Fatigue * Float (Laps (I).Lap);
            Rushing : constant Boolean :=
              St.Rush_Until >= 0.0 and then Here_S < St.Rush_Until
              and then Here_S > St.Rush_Until - 200.0;
            Target : constant Float := Float'Min
              (Track.Samples (Look).Line_V * St.Skill * Tired
               * (1.0 + 0.012 * Ch.Aggression)
               * (if Rushing then 1.10 else 1.0)
               * (if VSC_On then VSC_Pace
                  elsif Yellow_S >= 0.0
                    and then (Yellow_S - Here_S >= 0.0 and then Yellow_S - Here_S < 300.0)
                  then 0.8
                  else 1.0),
               Slow_Ahead);
            Err : constant Float := Target - Sp;
         begin
            if not Lights_Out then
               St.Inputs.Throttle := 0.25;
               St.Inputs.Brake := 1.0;
            elsif Err > 0.0 then
               St.Inputs.Brake := 0.0;
               St.Inputs.Throttle := Clamp (Err * 0.5 + 0.15, 0.0, 1.0);
               --  Gentle in the slide
               declare
                  Used : constant Float := abs C.Ay / (Spec.Mu * 9.81);
               begin
                  St.Inputs.Throttle := St.Inputs.Throttle
                    * Clamp (1.25 - Used * Used, 0.15, 1.0);
               end;
               if abs C.Vy > 1.2 then
                  St.Inputs.Throttle := St.Inputs.Throttle * 0.4;
               end if;
            else
               St.Inputs.Throttle := 0.0;
               St.Inputs.Brake := Clamp (-Err * 0.3, 0.0, 1.0);
            end if;
         end;
      end;

      --  Now and then, at a corner coming up, the dice say: too fast into it
      declare
         Here_S : constant Float := Track.Samples (Idx).S;
         Gone : constant Float :=
           (if Here_S >= St.Last_Roll then Here_S - St.Last_Roll
            else Here_S + Track.Length - St.Last_Roll);
      begin
         if Lights_Out and then Ch.Mistakes > 0.0 and then Gone > 100.0 then
            St.Last_Roll := Here_S;
            declare
               N : constant Natural := Track.Next_Note (Here_S);
            begin
               if N > 0 and then Track.Notes (N).Kind /= Track.Crest
                 and then Track.Notes (N).S - Here_S < 120.0
                 and then Ada.Numerics.Float_Random.Random (Dice) < Ch.Mistakes * 0.1
               then
                  St.Rush_Until := Track.Notes (N).S + 40.0;
                  AI_Mistakes := AI_Mistakes + 1;
               end if;
            end;
         end if;
      end;

      --  Lost on the grass or against a wall: back on the track
      if Lights_Out and then Sp < 1.0 then
         St.Stuck_T := St.Stuck_T + 0.01;
         if St.Stuck_T > 4.0 then
            declare
               S : Track.Sample renames Track.Samples (Idx);
               X : constant Float := S.X + S.RX * S.Line_D;
               Z : constant Float := S.Z + S.RZ * S.Line_D;
               Keep : constant Float := Arctan (S.TX, -S.TZ);
            begin
               Vehicle.Place (C, Config.Kind, X, Z, Keep);
               St.Stuck_T := 0.0;
            end;
         end if;
      else
         St.Stuck_T := 0.0;
      end if;
   end Drive_AI;

   ---------------------------------------------------------------------------
   --  Laps
   ---------------------------------------------------------------------------

   procedure Update_Lap (I : Car_Index) is
      C : Car renames Cars (I);
      L : Lap_Info renames Laps (I);
      S : constant Float := Track.Samples (C.Hint).S;
      Start_Line_Crossed : constant Boolean :=
        L.Last_S > Track.Length * 0.8 and then S < Track.Length * 0.2;
      Going_Back : constant Boolean :=
        L.Last_S < Track.Length * 0.2 and then S > Track.Length * 0.8;
   begin
      if Lights_Out and then not (Config.Mode = Stage and then L.Finished) then
         L.Lap_Time := L.Lap_Time + Dt;
      end if;
      if I = 1 and then Config.Mode /= Stage then
         --  All four wheels off: this lap does not count
         declare
            Off : Boolean := True;
         begin
            for W in Wheel_Id loop
               Off := Off and then
                 (C.Wheels (W).Surf = Track.Grass or else C.Wheels (W).Surf = Track.Gravel);
            end loop;
            if Off then
               L.Invalid := True;
            end if;
         end;
      end if;
      --  A stage: along the road, no short cuts, to the flying finish
      if Config.Mode = Stage and then I = 1 and then not L.On_Grid and then not L.Finished then
         if S >= L.Progress and then S < L.Progress + 60.0 then
            L.Progress := S;
         end if;
         if L.Progress >= Track.Stage_End then
            L.Finished := True;
            L.Finish_Time := L.Lap_Time;
            L.Last_Time := L.Lap_Time;
            Race_Over := True;
            if L.Best_Time = 0.0 or else L.Lap_Time < L.Best_Time then
               L.Best_Time := L.Lap_Time;
               New_Best := True;
               Best_Ghost.all := Cur_Ghost.all;
               Best_Frames := Cur_Frames;
               Best_Delta.all := Cur_Delta.all;
               for K in 1 .. Delta_Size loop
                  if Best_Delta (K) < Best_Delta (K - 1) then
                     Best_Delta (K) := Best_Delta (K - 1);
                  end if;
               end loop;
               Save_Best;
            end if;
         end if;
      end if;
      if Going_Back then
         L.Last_S := S;
         return;
      end if;
      declare
         Sec : constant Natural :=
           Natural'Min (2, Natural (Float'Floor (S / Track.Length * 3.0)));
      begin
         if Sec /= L.Sector and then not Start_Line_Crossed then
            L.Sector_Times (L.Sector) := L.Lap_Time;
            L.Sector := Sec;
         end if;
      end;
      if I = 1 and then Best_Delta /= null
        and then not L.On_Grid and then not Start_Line_Crossed
        and then not (Config.Mode = Stage and then L.Finished)
      then
         declare
            Pt : constant Natural :=
              Natural'Min (Delta_Size, Natural (S / Track.Length * Float (Delta_Size)));
         begin
            Cur_Delta (Pt) := L.Lap_Time;
            if L.Best_Time > 0.0 and then Best_Delta (Pt) > 0.0 then
               L.Delta_T := L.Lap_Time - Best_Delta (Pt);
               L.Has_Delta := True;
            end if;
         end;
         --  (20 frames a second, 50 steps each)
         if Tick mod 50 = 0 and then Cur_Frames < Ghost_Max
           and then (Config.Mode /= Stage or else (Lights_Out and then not L.Finished))
         then
            Cur_Frames := Cur_Frames + 1;
            Cur_Ghost (Cur_Frames) :=
              (Float (C.X), C.Y, Float (C.Z), C.Heading, C.Pitch, C.Roll);
         end if;
      end if;
      if Start_Line_Crossed and then L.On_Grid then
         --  Rolling over the line from the grid: the first lap starts
         L.On_Grid := False;
         L.Sector := 0;
         if Config.Mode not in Race | Stage then
            L.Lap_Time := 0.0;
         end if;
         if I = 1 and then Config.Mode = Stage then
            --  The clock has been running since the lights; so has the ghost
            L.Has_Delta := False;
         elsif I = 1 then
            Cur_Frames := 0;
            Cur_Delta.all := (others => 0.0);
            L.Has_Delta := False;
            L.Invalid := False;
         end if;
      elsif Start_Line_Crossed then
         L.Lap := L.Lap + 1;
         L.Last_Time := L.Lap_Time;
         L.Sector_Times (2) := L.Lap_Time;
         L.Sector := 0;
         if I = 1 then
            Lap_Done := True;
            --  The first lap from a standing or rolling start counts too
            if Config.Mode = Demo then
               --  The AI showing off behind the menu sets no records
               null;
            elsif not L.Invalid
              and then (L.Best_Time = 0.0 or else L.Lap_Time < L.Best_Time)
            then
               L.Best_Time := L.Lap_Time;
               New_Best := True;
               Best_Ghost.all := Cur_Ghost.all;
               Best_Frames := Cur_Frames;
               Best_Delta.all := Cur_Delta.all;
               --  A point the lap skipped takes the one before it
               for K in 1 .. Delta_Size loop
                  if Best_Delta (K) < Best_Delta (K - 1) then
                     Best_Delta (K) := Best_Delta (K - 1);
                  end if;
               end loop;
               Save_Best;
            end if;
            Cur_Frames := 0;
            Cur_Delta.all := (others => 0.0);
            L.Has_Delta := False;
            L.Invalid := False;
         elsif L.Best_Time = 0.0 or else L.Lap_Time < L.Best_Time then
            L.Best_Time := L.Lap_Time;
         end if;
         L.Lap_Time := 0.0;
         if Config.Mode = Race and then L.Lap >= Config.Laps and then not L.Finished then
            L.Finished := True;
            L.Finish_Time := Time + L.Penalty;
         end if;
      end if;
      L.Last_S := S;
      L.S := S;
   end Update_Lap;

   procedure Update_Order is
      Done : array (Car_Index) of Boolean := (others => False);
   begin
      for P in 1 .. Car_Count loop
         declare
            Best : Natural := 0;
            Best_V : Float := Float'First;
         begin
            for I in 1 .. Car_Count loop
               if not Done (I) then
                  declare
                     V : constant Float :=
                       (if Laps (I).Finished
                        then 1.0E7 - Laps (I).Finish_Time
                        else Float (Laps (I).Lap) * Track.Length + Laps (I).Last_S
                             --  Still behind the line: that is before the lap, not at its end
                             - (if Laps (I).On_Grid then Track.Length else 0.0));
                  begin
                     if V > Best_V then
                        Best_V := V;
                        Best := I;
                     end if;
                  end;
               end if;
            end loop;
            Done (Best) := True;
            Laps (Best).Position := P;
         end;
      end loop;
   end Update_Order;

   ---------------------------------------------------------------------------

   procedure Grid_Slot (P : Positive; X, Z, H : out Float) is
      --  Staggered rows behind the line
      Back : constant Integer := (if Track.Is_Stage then -3 else -(6 + (P - 1) * 5));
      I : constant Natural := Track.Next (0, Back);
      S : Track.Sample renames Track.Samples (I);
      Side : constant Float :=
        (if Track.Is_Stage then 0.0 elsif P mod 2 = 1 then -2.6 else 2.6);
   begin
      X := S.X + S.RX * Side;
      Z := S.Z + S.RZ * Side;
      H := Arctan (S.TX, -S.TZ);
   end Grid_Slot;

   --  Enough for that many laps, and a little over; what the tank takes
   function Fuel_For_Laps (N : Natural) return Float is
     (Float'Min (Vehicle.Tank,
                 2.0 + Float (N) * 1.08 * Track.Length / 1000.0 * Vehicle.Fuel_Per_Km (Config.Kind)));

   procedure Restart is
      Best_Keep : constant Float := Laps (1).Best_Time;
   begin
      Time := 0.0;
      Tick := 0;
      Race_Over := False;
      Lap_Done := False;
      New_Best := False;
      Cur_Frames := 0;
      Spec := Spec_Of (Config.Kind);
      Player_Spec := Tuned (Config.Kind, Config.Tune);
      Service_Left := 0.0;
      Service_Offer := False;
      In_Pit_Lane := False;
      Yellow_S := -1.0;
      Yellow_Until := 0.0;
      VSC_Until := 0.0;
      Stopped_T := (others => 0.0);
      Too_Fast_T := 0.0;
      Parked := 0.0;
      Laps := (others => <>);
      Laps (1).Best_Time := Best_Keep;
      if Cur_Delta /= null then
         Cur_Delta.all := (others => 0.0);
      end if;
      case Config.Mode is
         when Race =>
            Car_Count := 1 + Config.Opponents;
            Lights := 0;
            Lights_Out := False;
         when Hotlap =>
            Car_Count := (if Config.Two_Players then 2 else 1);
            Lights_Out := True;
         when Stage =>
            Car_Count := 1;
            Lights := 0;
            Lights_Out := False;
         when Demo =>
            Car_Count := 1 + Natural'Min (Config.Opponents, 4);
            Lights_Out := True;
      end case;
      for I in 1 .. Car_Count loop
         declare
            X, Z, H : Float;
            --  In a race the player starts at the back
            Slot : constant Positive :=
              (if Config.Mode = Race then (if I = 1 then Car_Count else I - 1) else I);
         begin
            Grid_Slot (Slot, X, Z, H);
            if Config.Mode = Demo then
               declare
                  K : constant Natural := Track.Next (0, (I - 1) * Track.Count / Car_Count);
                  S : Track.Sample renames Track.Samples (K);
               begin
                  X := S.X + S.RX * S.Line_D;
                  Z := S.Z + S.RZ * S.Line_D;
                  H := Arctan (S.TX, -S.TZ);
               end;
            end if;
            Vehicle.Place (Cars (I), Config.Kind, X, Z, H);
            Laps (I).Last_S := Track.Samples (Cars (I).Hint).S;
            AI (I) := (Skill => Config.AI_Skill + Character_Of (I).Pace
                         + 0.01 * (Ada.Numerics.Float_Random.Random (Dice) - 0.5),
                       others => <>);
            AI (I).Inputs.Throttle := 0.0;
            if I = 1 and then Config.Assist.Mode = Paddles then
               Cars (I).Gear := 1;
            end if;
         end;
      end loop;
      Cars (1).Fuel := Fuel_For_Laps (Config.Laps);
   end Restart;

   procedure Start (S : Settings) is
   begin
      Config := S;
      --  Hot laps compare like with like: always fresh tyres and light on fuel
      if S.Mode in Hotlap | Stage then
         Config.Assist.Wear_Rate := 0.0;
         Config.Assist.Fuel_Use := False;
      end if;
      Spec := Spec_Of (S.Kind);
      Laps (1).Best_Time := 0.0;
      --  What the sky does to the ground (winter rain falls as snow)
      if S.Season = Winter and then S.Weather = Rain then
         Config.Weather := Snowing;
      end if;
      Track.Wet := (case Config.Weather is
                       when Clear | Snowing => 0.0, when Rain => 1.0, when Fog => 0.3);
      Track.Snow := (if Config.Weather = Snowing or else S.Season = Winter then 1.0 else 0.0);
      Track.Compute_Speeds
        (Mu => Spec.Mu * 0.81 * Condition_Grip (Spec)
              * (if Track.Is_Stage then Spec.Loose_Mu * 0.78 else 1.0),
         Down_Per_V2 => 0.5 * 1.2 * (Spec.Cl_F + Spec.Cl_R) / Spec.Mass,
         Power_Per_Mass => 0.9 * (case S.Kind is when Road_GT => 310_000.0,
                                                 when Race_GT3 => 410_000.0,
                                                 when Rally_4WD => 230_000.0,
                                                 when Classic_RWD => 155_000.0,
                                                 when Hyper_AWD => 510_000.0) / Spec.Mass,
         Drag_Per_V2 => 0.5 * 1.2 * Spec.Cd_A / Spec.Mass,
         Brake_Acc => Spec.Mu * 9.81 * 0.62 * Condition_Grip (Spec)
           * (if Track.Is_Stage then Spec.Loose_Mu * 0.78 else 1.0));
      Load_Best;
      Restart;
   end Start;

   procedure Reset_Player is
      C : Car renames Cars (1);
      --  What is broken or used stays so
      Old : constant Car := C;
      --  A stage: only back to where it has really got to
      At_I : constant Natural :=
        (if Config.Mode = Stage and then not Laps (1).On_Grid
           and then abs (Track.Samples (C.Hint).S - Laps (1).Progress) > 60.0
         then Natural (Laps (1).Progress / Track.Spacing)
         else C.Hint);
   begin
      if Config.Mode = Stage and then Laps (1).Finished then
         return;
      end if;
      declare
         S : Track.Sample renames Track.Samples (At_I);
      begin
         Vehicle.Place (C, Config.Kind, S.X + S.RX * S.Line_D, S.Z + S.RZ * S.Line_D,
                        Arctan (S.TX, -S.TZ));
      end;
      if Config.Assist.Mode = Paddles then
         C.Gear := 1;
      end if;
      C.Fuel := Old.Fuel;
      C.Dmg_Aero := Old.Dmg_Aero;
      C.Dmg_Engine := Old.Dmg_Engine;
      C.Toe := Old.Toe;
      for W in Wheel_Id loop
         C.Wheels (W).Wear := Old.Wheels (W).Wear;
         C.Wheels (W).Temp := Old.Wheels (W).Temp;
      end loop;
      if Config.Mode = Stage then
         Laps (1).Lap_Time := Laps (1).Lap_Time + Reset_Penalty;
         Laps (1).Resets := Laps (1).Resets + 1;
      else
         Laps (1).Invalid := True;
      end if;
   end Reset_Player;

   --  The pit box: stop in it with something to mend and the crew gets to work
   procedure Pit_Service (Hold : in out Vehicle.Inputs) is
      C : Car renames Cars (1);
      Worn : Float := 0.0;
   begin
      for W in Wheel_Id loop
         Worn := Float'Max (Worn, C.Wheels (W).Wear);
      end loop;
      if Service_Left > 0.0 then
         Hold.Throttle := 0.0;
         Hold.Brake := 1.0;
         Service_Left := Service_Left - Dt;
         if Service_Left <= 0.0 then
            Service_Left := 0.0;
            Parked := 0.0;
            C.Dmg_Aero := 0.0;
            C.Dmg_Engine := 0.0;
            C.Toe := 0.0;
            for W in Wheel_Id loop
               C.Wheels (W).Wear := 0.0;
            end loop;
            if Config.Assist.Fuel_Use then
               C.Fuel := Float'Max
                 (C.Fuel, Fuel_For_Laps (Natural'Max (0, Config.Laps - Laps (1).Lap)));
            end if;
         end if;
      elsif Tick mod 50 = 0 then
         declare
            Idx : Natural;
            T, D : Float;
            Hint : Natural := C.Hint;
            Needed : constant Float :=
              (if Config.Assist.Fuel_Use
               then Float'Max (0.0, Fuel_For_Laps (Natural'Max (0, Config.Laps - Laps (1).Lap)) - C.Fuel)
               else 0.0);
            Broken : constant Float :=
              Float'Max (C.Dmg_Aero, Float'Max (C.Dmg_Engine, abs C.Toe / 0.07));
            Work : constant Float :=
              (if Broken > 0.01 then 20.0 * Broken else 0.0)
              + (if Worn > 0.05 then 6.0 else 0.0)
              + Needed * 0.35;
         begin
            Track.Locate (Float (C.X), Float (C.Z), Hint, Idx, T, D);
            Service_Offer := Work > 0.0 and then Track.In_Pit_Box (Idx, D);
            In_Pit_Lane := Track.In_Pit_Lane (Idx, D);
            if Service_Offer and then Speed (C) < 0.8 then
               Parked := Parked + 0.05;
               if Parked >= 1.0 then
                  Service_Left := 3.0 + Work;
               end if;
            else
               Parked := 0.0;
            end if;
         end;
      end if;
   end Pit_Service;

   procedure Step (Player : Vehicle.Inputs) is
      Ai_Assists : constant Assists := (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>);
      --  (Car 1 in the menu's demo keeps its wear switches, for the tests)
      Demo_Assists : constant Assists :=
        (Abs_On => True, Tc_On => True, Mode => Automatic,
         Wear_Rate => Config.Assist.Wear_Rate, Fuel_Use => Config.Assist.Fuel_Use,
         Damage => Config.Assist.Damage);
      Hands : Vehicle.Inputs := Player;
   begin
      Tick := Tick + 1;
      Time := Time + Dt;

      --  Start lights: one red a second, then out at a moment not quite known
      if not Lights_Out then
         declare
            Showing : constant Natural := Natural (Float'Floor (Float'Max (0.0, Time - 1.0)));
         begin
            Lights := Natural'Min (5, Showing);
            if Time > 6.3 then
               Lights_Out := True;
               Lights := 0;
            end if;
         end;
      end if;

      if Tick mod 10 = 0 then
         for I in 1 .. Car_Count loop
            if AI_Drives (I) then
               Drive_AI (I);
            end if;
         end loop;
      end if;

      for I in 1 .. Car_Count loop
         if AI_Drives (I) then
            if I = 1 then
               Vehicle.Step (Cars (I), Player_Spec, AI (I).Inputs, Demo_Assists);
            else
               Vehicle.Step (Cars (I), Spec, AI (I).Inputs, Ai_Assists);
            end if;
         else
            --  Past the finish: the marshals wave it down
            if Config.Mode = Stage and then Laps (1).Finished then
               Hands.Throttle := 0.0;
               Hands.Brake := Float'Max (Hands.Brake, 0.5);
            elsif Config.Mode = Stage and then not Lights_Out then
               Hands.Brake := Float'Max (Hands.Brake, 0.2);   --  on the line, held
               Hands.Throttle := 0.0;
            end if;
            if I = 1 then
               Pit_Service (Hands);
               --  The limiter in the pit lane
               if In_Pit_Lane and then Speed (Cars (1)) > Track.Pit_Limit then
                  Hands.Throttle := 0.0;
                  if Speed (Cars (1)) > Track.Pit_Limit + 1.0 then
                     Hands.Brake := Float'Max
                       (Hands.Brake, Float'Min (0.8, (Speed (Cars (1)) - Track.Pit_Limit) * 0.15));
                  end if;
               end if;
            end if;
            if I = 1 then
               Vehicle.Step (Cars (I), Player_Spec, Hands, Config.Assist);
            else
               --  The second player: on the keys, so the gearbox shifts itself
               Vehicle.Step (Cars (I), Player_Spec, Second_Hands,
                             (Abs_On => Config.Assist.Abs_On, Tc_On => Config.Assist.Tc_On,
                              Mode => Automatic, Damage => Config.Assist.Damage, others => <>));
            end if;
         end if;
         Update_Lap (I);
      end loop;

      if Car_Count > 1 and then Tick mod 2 = 0 then
         for I in 1 .. Car_Count - 1 loop
            for J in I + 1 .. Car_Count loop
               Vehicle.Collide (Cars (I), Cars (J), Spec, Spec);
            end loop;
         end loop;
      end if;

      if Tick mod 50 = 0 then
         Watch_Race;
         Update_Order;
         if Config.Mode in Race | Stage and then Laps (1).Finished then
            Race_Over := True;
         end if;
      end if;
   end Step;

begin
   Ada.Numerics.Float_Random.Reset (Dice);
end Session;
