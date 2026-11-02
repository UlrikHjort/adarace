--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Headless checks of the physics and the circuits: no window, no wheel.
--  A car standing still must stay still, the straight line figures must
--  be believable, and the AI must get round every circuit in a sane time.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Championship;
with Codriver;
with Rally;
with School;
with Session;
with Telemetry;
with Track;
with Vehicle;

procedure Simtest is

   use Ada.Text_IO;
   use Ada.Numerics.Elementary_Functions;
   use Vehicle;
   use type Track.Surface_Kind;
   use type Track.Note_Kind;
   use type Session.Weather_Kind;
   use type School.Phase_Kind;
   use type Session.Mode_Kind;

   Failed : Natural := 0;

   package FIO is new Ada.Text_IO.Float_IO (Float);

   function Img (V : Float; Aft : Natural := 2) return String is
      S : String (1 .. 16);
   begin
      FIO.Put (S, V, Aft => Aft, Exp => 0);
      for I in S'Range loop
         if S (I) /= ' ' then
            return S (I .. S'Last);
         end if;
      end loop;
      return S;
   end Img;

   procedure Check (Ok : Boolean; What : String) is
   begin
      if not Ok then
         Failed := Failed + 1;
      end if;
      Put_Line ((if Ok then "  ok    " else "  FAIL  ") & What);
   end Check;

   function Hotlap (K : Car_Kind) return Session.Settings is
     (Mode => Session.Hotlap, Kind => K,
      Assist => (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>),
      Opponents => 0, Laps => 3, AI_Skill => 0.95, others => <>);

   ---------------------------------------------------------------------------

   procedure Track_Shape (T : Track.Track_Id) is
      Max_K : Float := 0.0;
      Min_Y, Max_Y : Float := 0.0;
      Min_Sep : Float := Float'Last;
      Min_Room : Float := Float'Last;
   begin
      Track.Load (T);
      Min_Y := Track.Samples (0).Y;
      Max_Y := Min_Y;
      for I in 0 .. Track.Count - 1 loop
         declare
            S : Track.Sample renames Track.Samples (I);
         begin
            Max_K := Float'Max (Max_K, abs S.Kappa);
            Min_Y := Float'Min (Min_Y, S.Y);
            Max_Y := Float'Max (Max_Y, S.Y);
            Min_Room := Float'Min (Min_Room, Float'Min (S.Wall_L - S.W_L, S.Wall_R - S.W_R));
            --  Another part of the road this close?
            if I mod 4 = 0 then
               for J in 0 .. Track.Count - 1 loop
                  if J mod 4 = 0 then
                     declare
                        Sep : constant Integer := abs (I - J);
                        Circ : constant Integer := Integer'Min (Sep, Track.Count - Sep);
                     begin
                        if Float (Circ) * Track.Spacing > 150.0 then
                           Min_Sep := Float'Min
                             (Min_Sep, Sqrt ((Track.Samples (J).X - S.X) ** 2
                                             + (Track.Samples (J).Z - S.Z) ** 2));
                        end if;
                     end;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      Put_Line (Track.Name (T) & ": " & Img (Track.Length, 0) & " m, tightest radius "
                & Img (1.0 / Max_K, 1) & " m, climb " & Img (Max_Y - Min_Y, 1)
                & " m, nearest other road " & Img (Min_Sep, 1)
                & " m, least run-off " & Img (Min_Room, 1) & " m");
      Check (Min_Sep > 40.0, "the road does not cross or touch itself");
      Check (1.0 / Max_K > 12.0, "no impossibly tight corner");
   end Track_Shape;

   ---------------------------------------------------------------------------

   procedure Stand_Still is
      N : Vehicle.Inputs;
      Max_V : Float := 0.0;
   begin
      Track.Load (2);
      Session.Start (Hotlap (Road_GT));
      --  On the hill: find the steepest part of the road, hold the brake
      declare
         Steep : Natural := 0;
         Best  : Float := 0.0;
      begin
         for I in 0 .. Track.Count - 1 loop
            declare
               G : constant Float := abs (Track.Samples (Track.Next (I, 2)).Y - Track.Samples (I).Y);
            begin
               if G > Best then
                  Best := G;
                  Steep := I;
               end if;
            end;
         end loop;
         declare
            S : Track.Sample renames Track.Samples (Steep);
         begin
            Vehicle.Place (Session.Cars (1), Road_GT, S.X, S.Z, Arctan (S.TX, -S.TZ));
            Put_Line ("Parked on grade " & Img (Best / Track.Spacing * 100.0, 1) & " %");
         end;
      end;
      N.Brake := 1.0;
      declare
         X0 : Long_Float;
      begin
         for I in 1 .. 8000 loop
            Session.Step (N);
            if I = 3000 then
               X0 := Session.Cars (1).X;
            end if;
            if I > 3000 then
               Max_V := Float'Max (Max_V, Speed (Session.Cars (1)));
            end if;
         end loop;
         declare
            Moved : constant Float := abs Float (Session.Cars (1).X - X0);
         begin
            Check (Max_V < 0.03 and then Moved < 0.02,
                   "held on the brake: top speed " & Img (Max_V, 4) & " m/s, moved "
                   & Img (Moved, 4) & " m");
         end;
      end;
      Check (abs Session.Cars (1).Roll < 0.1 and then abs Session.Cars (1).Pitch < 0.25,
             "body settled: pitch " & Img (Session.Cars (1).Pitch, 3)
             & " roll " & Img (Session.Cars (1).Roll, 3));
      declare
         Sum : Float := 0.0;
      begin
         for W in Wheel_Id loop
            Sum := Sum + Session.Cars (1).Wheels (W).Fz;
         end loop;
         Check (abs (Sum - Session.Spec.Mass * 9.81) < Session.Spec.Mass * 9.81 * 0.03,
                "wheel loads carry the weight: " & Img (Sum, 0) & " N");
      end;
   end Stand_Still;

   ---------------------------------------------------------------------------
   --  On the speedway's flat straight, repeatedly put back at the start of it

   procedure Straight (K : Car_Kind) is
      N : Vehicle.Inputs;
      T : Float := 0.0;
      T100, T200 : Float := 0.0;
      A : constant Assists := (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>);
      S : constant Spec := Spec_Of (K);
      C : Car;
      Top : Float := 0.0;
   begin
      Track.Load (1);
      Session.Start (Hotlap (K));
      declare
         A0 : Track.Sample renames Track.Samples (0);
      begin
         Vehicle.Place (C, K, A0.X, A0.Z, Arctan (A0.TX, -A0.TZ));
      end;
      N.Throttle := 1.0;
      --  Hold the steering straight along the road by a light hand
      while T < 40.0 loop
         declare
            Hdg : constant Float := Arctan (Track.Samples (C.Hint).TX, -Track.Samples (C.Hint).TZ);
            E : Float := Hdg - C.Heading;
            Lat : Float;
            I : Natural;
            Tt : Float;
         begin
            if E > 3.14159 then
               E := E - 6.28318;
            elsif E < -3.14159 then
               E := E + 6.28318;
            end if;
            Track.Locate (Float (C.X), Float (C.Z), C.Hint, I, Tt, Lat);
            N.Steer := (E * 2.0 - Lat * 0.05) / S.Steer_Lock * 0.4;
            --  Round the bends in the road the same; only the first seconds count
         end;
         Vehicle.Step (C, S, N, A);
         T := T + Dt;
         if T100 = 0.0 and then C.Vx >= 100.0 / 3.6 then
            T100 := T;
         end if;
         if T200 = 0.0 and then C.Vx >= 200.0 / 3.6 then
            T200 := T;
         end if;
         Top := Float'Max (Top, C.Vx);
         exit when T200 > 0.0 and then T > T200 + 0.5;
      end loop;
      Put_Line (Name (K) & ": 0-100 " & Img (T100) & " s, 0-200 " & Img (T200)
                & " s, reached " & Img (Top * 3.6, 0) & " km/h in gear" & C.Gear'Image);
      Check (T100 > 2.2 and then T100 < 7.0, "0-100 km/h is believable");

      --  Brake from where we are, straight on
      declare
         V0 : constant Float := 100.0 / 3.6;
         Dist : Float := 0.0;
      begin
         --  (a fresh car at speed)
         declare
            A0 : Track.Sample renames Track.Samples (0);
            Omega0 : constant Float := V0 / S.Radius;
         begin
            Vehicle.Place (C, K, A0.X, A0.Z, Arctan (A0.TX, -A0.TZ));
            C.Vx := V0;
            for W in Wheel_Id loop
               C.Wheels (W).Omega := Omega0;
            end loop;
         end;
         N := (Brake => 1.0, others => <>);
         T := 0.0;
         while C.Vx > 0.2 and then T < 10.0 loop
            Vehicle.Step (C, S, N, A);
            Dist := Dist + C.Vx * Dt;
            T := T + Dt;
         end loop;
         Put_Line ("  100-0 km/h in " & Img (Dist, 1) & " m (ABS on)");
         --  (the classic's narrow tyres are allowed their longer stop)
         Check (Dist > 22.0 and then Dist < (if K = Classic_RWD then 50.0 else 45.0),
                "braking distance is believable");
      end;
   end Straight;

   ---------------------------------------------------------------------------

   function Saved_By_Demo return Boolean is
     (Ada.Directories.Exists (Session.Save_Name));

   procedure AI_Lap (T : Track.Track_Id; K : Car_Kind) is
      S : Session.Settings := Hotlap (K);
      N : Vehicle.Inputs;
      Max_Lat, Max_V : Float := 0.0;
      Max_Temp : Float := 0.0;
      Off_Count, Hits : Natural := 0;
      Was_Off : Boolean := False;
      Laps_Done : Natural := 0;
   begin
      S.Mode := Session.Demo;
      S.Opponents := 0;
      S.AI_Skill := 0.98;
      Track.Load (T);
      Session.Start (S);
      Session.Laps (1).Best_Time := 0.0;
      for I in 1 .. 1_500_000 loop
         Session.Step (N);
         declare
            C : Car renames Session.Cars (1);
            Off : constant Boolean :=
              C.Wheels (1).Surf in Track.Grass | Track.Gravel
              and then C.Wheels (2).Surf in Track.Grass | Track.Gravel
              and then C.Wheels (3).Surf in Track.Grass | Track.Gravel
              and then C.Wheels (4).Surf in Track.Grass | Track.Gravel;
         begin
            if Session.Laps (1).Lap >= 1 then
               Max_Lat := Float'Max (Max_Lat, abs C.Ay);
               Max_V := Float'Max (Max_V, Speed (C));
               Max_Temp := Float'Max (Max_Temp, C.Wheels (3).Temp);
               if Off and then not Was_Off then
                  Off_Count := Off_Count + 1;
                  Put_Line ("    off at s=" & Img (Track.Samples (C.Hint).S, 0) & " v=" & Img (C.Vx * 3.6, 0)
                            & " vy=" & Img (C.Vy, 1));
               end if;
               if C.Impact > 1.0 then
                  Hits := Hits + 1;
               end if;
            end if;
            Was_Off := Off;
         end;
         Laps_Done := Session.Laps (1).Lap;
         exit when Laps_Done >= 3;
      end loop;
      Put_Line (Track.Name (T) & " / " & Name (K) & ": last lap " & Img (Session.Laps (1).Last_Time, 3)
                & " s, top " & Img (Max_V * 3.6, 0) & " km/h, lateral "
                & Img (Max_Lat / 9.81) & " g, tyres " & Img (Max_Temp, 0)
                & " C, off" & Off_Count'Image & ", wall ms" & Hits'Image);
      Check (Laps_Done >= 3, "the AI completes its laps");
      Check (not Saved_By_Demo,
             "laps by the AI are not saved as records");
      Check (Off_Count = 0, "the AI stays on the circuit");
      Check (Hits < 50, "the AI keeps off the barriers");
   end AI_Lap;

   --  What the player's hands and feet do
   procedure Controls is
      S : constant Spec := Spec_Of (Road_GT);
      C : Car;

      procedure Fresh is
         A0 : Track.Sample renames Track.Samples (0);
      begin
         Vehicle.Place (C, Road_GT, A0.X, A0.Z, Arctan (A0.TX, -A0.TZ));
      end Fresh;

      procedure Run (N : Vehicle.Inputs; Modes : Assists; Seconds : Float) is
      begin
         for I in 1 .. Integer (Seconds * 1000.0) loop
            Vehicle.Step (C, S, N, Modes);
         end loop;
      end Run;

      Paddle : constant Assists := (Abs_On => False, Tc_On => False, Mode => Paddles, others => <>);
      H_C : constant Assists := (Abs_On => False, Tc_On => False, Mode => H_Clutch, others => <>);
      H_A : constant Assists := (Abs_On => False, Tc_On => False, Mode => H_Auto_Clutch, others => <>);
      N : Vehicle.Inputs;
   begin
      Track.Load (1);
      Session.Start (Hotlap (Road_GT));

      --  Paddles: first gear, launch, shift up by request
      Fresh;
      C.Gear := 1;
      N := (Throttle => 1.0, others => <>);
      Run (N, Paddle, 2.5);
      Check (C.Vx > 8.0, "paddles: launches in first, " & Img (C.Vx * 3.6, 0) & " km/h in 2.5 s");
      N.Shift_Up := True;
      Vehicle.Step (C, S, N, Paddle);
      N.Shift_Up := False;
      Run (N, Paddle, 0.3);
      Check (C.Gear = 2, "paddles: up to second");
      N := (others => <>);
      Run (N, Paddle, 8.0);
      Check (C.Rpm >= S.Idle * 0.8, "never stalls, coasting in gear: " & Img (C.Rpm, 0) & " rpm");

      --  Steering: to the right is to the right, with the rack pulling back
      Fresh;
      C.Gear := 1;
      N := (Throttle => 0.6, others => <>);
      Run (N, Paddle, 3.0);
      declare
         H0 : constant Float := C.Heading;
      begin
         N := (Throttle => 0.3, Steer => 0.08, others => <>);
         Run (N, Paddle, 0.6);
         Check (C.Heading > H0 + 0.02, "steering right turns the car right");
         Check (C.Rack < -2.0, "the tyres pull the wheel back to the centre: rack "
                & Img (C.Rack, 1) & " N m, force" & Img (C.Rack / 260.0));
      end;

      --  H-shifter with the clutch: no gear without the pedal
      Fresh;
      N := (Lever => 1, Clutch => 0.0, others => <>);
      Run (N, H_C, 0.2);
      Check (C.Gear = 0 and then C.Grind, "H-shifter: the gear grinds without the clutch");
      N := (Lever => 1, Clutch => 1.0, others => <>);
      Run (N, H_C, 0.2);
      Check (C.Gear = 1, "H-shifter: goes in with the pedal down");
      N := (Lever => 1, Clutch => 0.0, Throttle => 0.7, others => <>);
      Run (N, H_C, 2.0);
      Check (C.Vx > 5.0, "H-shifter: drives off, " & Img (C.Vx * 3.6, 0) & " km/h");

      --  H-shifter, automatic clutch; reverse goes backwards
      Fresh;
      N := (Lever => -1, Throttle => 0.5, others => <>);
      Run (N, H_A, 3.0);
      Check (C.Gear = -1 and then C.Vx < -1.0, "reverse: " & Img (C.Vx * 3.6, 0) & " km/h");

      --  Off the grid, the handbrake locks the rear
      Fresh;
      C.Vx := 15.0;
      for W in Wheel_Id loop
         C.Wheels (W).Omega := 15.0 / S.Radius;
      end loop;
      N := (Handbrake => True, others => <>);
      Run (N, Paddle, 0.4);
      Check (abs C.Wheels (3).Omega < 1.0, "the handbrake locks the rear wheels");

      --  Grass slows the car and lets it slide
      declare
         A0 : Track.Sample renames Track.Samples (Track.Count / 2);
         Side : constant Float := A0.W_R + 6.0;
         X : constant Float := A0.X + A0.RX * Side;
         Z : constant Float := A0.Z + A0.RZ * Side;
      begin
         Vehicle.Place (C, Road_GT, X, Z, Arctan (A0.TX, -A0.TZ));
         Run ((others => <>), Paddle, 0.1);
         Check (C.Wheels (1).Surf in Track.Grass | Track.Gravel, "the verge is grass or gravel");
      end;

      --  Into a barrier at speed: stopped by it, never through it
      declare
         A0 : Track.Sample renames Track.Samples (0);
         Inside : Boolean := True;
         Hit_It : Boolean := False;
      begin
         Vehicle.Place (C, Road_GT, A0.X, A0.Z, Arctan (A0.TX, -A0.TZ) + 1.2);
         C.Vx := 40.0;
         for W in Wheel_Id loop
            C.Wheels (W).Omega := 40.0 / S.Radius;
         end loop;
         for I in 1 .. 3000 loop
            Vehicle.Step (C, S, (others => <>), Paddle);
            Hit_It := Hit_It or else C.Impact > 5.0;
            declare
               Idx : Natural;
               T, D : Float;
               H : Natural := C.Hint;
            begin
               Track.Locate (Float (C.X), Float (C.Z), H, Idx, T, D);
               Inside := Inside and then
                 abs D < Float'Max (Track.Samples (Idx).Wall_L, Track.Samples (Idx).Wall_R) + 0.1;
            end;
         end loop;
         Check (Hit_It and then Inside, "a barrier stops the car and holds it in");
      end;
   end Controls;

   procedure Race_Run is
      S : Session.Settings := Hotlap (Road_GT);
      N : Vehicle.Inputs;
      Max_Pos : Float := 0.0;
   begin
      S.Mode := Session.Race;
      S.Opponents := 5;
      S.Laps := 2;
      Track.Load (1);
      Session.Start (S);
      --  The player's car just stands on the grid in the way
      N.Brake := 1.0;
      for I in 1 .. 300_000 loop
         Session.Step (N);
         for K in 2 .. Session.Car_Count loop
            Max_Pos := Float'Max (Max_Pos, Speed (Session.Cars (K)));
         end loop;
         exit when Session.Laps (2).Finished;
      end loop;
      Put ("Race, two laps:");
      for K in 2 .. Session.Car_Count loop
         Put (" P" & Session.Laps (K).Position'Image & " " & Img (Session.Laps (K).Last_Time, 1));
      end loop;
      New_Line;
      Check (Session.Laps (2).Lap >= 2 or else Session.Laps (3).Lap >= 2,
             "AI cars finish a race, with traffic and contact");
   end Race_Run;

   --  The player's lap: the AI takes the car round, then hands over just
   --  before the line, so what crosses it is a lap of the player's
   procedure Player_Lap is
      use Ada.Directories;
      S : constant Session.Settings := Hotlap (Road_GT);
      N : Vehicle.Inputs;
      Lap_T : Float;
      Lines : Natural := 0;
      Check_Grid : Boolean := False;
   begin
      Track.Load (Track.Track_Id'First);
      Session.Start (S);
      Session.Config.Mode := Session.Demo;
      for I in 1 .. 400_000 loop
         Session.Step (N);
         if Session.Config.Mode = Session.Demo
           and then not Session.Laps (1).On_Grid
           and then Session.Laps (1).S > Track.Length - 20.0
         then
            Session.Config.Mode := Session.Hotlap;
            N.Throttle := 0.5;
         end if;
         if I mod 10 = 0 then
            Telemetry.Sample (N, 0.1);
         end if;
         exit when Session.Laps (1).Lap >= 1;
      end loop;
      Lap_T := Session.Laps (1).Best_Time;
      Check (Session.Laps (1).Lap >= 1 and then Lap_T > 0.0, "a player's lap is timed");
      Check (Exists (Session.Save_Name), "a player's best lap is saved");
      Telemetry.Write;
      Check (Telemetry.Last_File /= "" and then Exists (Telemetry.Last_File),
             "the telemetry is written");
      if Telemetry.Last_File /= "" then
         declare
            F : File_Type;
         begin
            Open (F, In_File, Telemetry.Last_File);
            while not End_Of_File (F) loop
               Skip_Line (F);
               Lines := Lines + 1;
            end loop;
            Close (F);
         end;
      end if;
      Check (Lines > 5000, "the telemetry holds the lap:" & Lines'Image & " lines");
      Session.Start (S);
      Check (abs (Session.Laps (1).Best_Time - Lap_T) < 0.001,
             "the best lap comes back at the next sitting");
      Check (Session.Best_Frames > 100, "and its ghost with it");
      declare
         G : constant Session.Ghost_Frame := Session.Ghost_At (Lap_T / 2.0);
      begin
         Check (G.X /= 0.0 or else G.Z /= 0.0, "the ghost is somewhere mid-lap");
      end;
      --  Round again: the delta must run against that best
      Session.Config.Mode := Session.Demo;
      for I in 1 .. 60_000 loop
         Session.Step (N);
         Check_Grid := Check_Grid
           or else (Session.Laps (1).On_Grid and then Session.Laps (1).Has_Delta);
         exit when not Session.Laps (1).On_Grid and then Session.Laps (1).S > 500.0
           and then Session.Laps (1).S < 1000.0;
      end loop;
      Check (not Check_Grid, "no delta before the line is crossed");
      Check (Session.Laps (1).Has_Delta and then abs Session.Laps (1).Delta_T < 15.0,
             "the delta runs against it:" & Img (Session.Laps (1).Delta_T) & " s");
   end Player_Lap;

   --  The steering must keep aligning when the tyre has let go
   procedure Sliding_Rack is
      S : constant Spec := Spec_Of (Road_GT);
      C : Car;
      N : Vehicle.Inputs;
      A : constant Assists := (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>);
      I0 : Track.Sample renames Track.Samples (0);
   begin
      Track.Load (Track.Track_Id'First);
      Place (C, Road_GT, I0.X, I0.Z, Arctan (I0.RZ, I0.RX));
      for I in 1 .. 2000 loop
         Step (C, S, N, A);
      end loop;
      C.Vx := 30.0;
      C.Vy := 8.0;       --  sliding to the right, about 15 degrees, wheels straight
      for W in Wheel_Id loop
         C.Wheels (W).Omega := C.Vx / S.Radius;
      end loop;
      for I in 1 .. 60 loop
         Step (C, S, N, A);
      end loop;
      Check (C.Rack > 0.0,
             "a slide to the right pulls the wheel right, to the countersteer:" & Img (C.Rack) & " N m");
   end Sliding_Rack;

   --  Setup: each knob must do what it says
   procedure Setups is
      procedure Top (N : Setup; V : out Float; Rpm : out Float) is
         C : Car;
         I0 : Track.Sample renames Track.Samples (0);
         A : constant Assists := (Abs_On => True, Tc_On => True, Mode => Paddles, others => <>);
         S : constant Spec := Tuned (Road_GT, N);
         In_1 : Vehicle.Inputs;
      begin
         Place (C, Road_GT, I0.X, I0.Z, Arctan (I0.RZ, I0.RX));
         C.Gear := 2;
         In_1.Throttle := 1.0;
         for I in 1 .. 4000 loop
            Step (C, S, In_1, A);
         end loop;
         V := Speed (C);
         Rpm := C.Rpm;
      end Top;
      V0, V1, R0, R1 : Float;
      Short : Setup;
      Winged : Setup;
   begin
      Track.Load (Track.Track_Id'First);
      Top ((others => <>), V0, R0);
      Short.Final_Drive := 1.15;
      Top (Short, V1, R1);
      Check (R1 / V1 > 1.1 * R0 / V0, "a shorter final drive turns the engine faster for the speed");
      Winged.Wing := 1.5;
      declare
         S0 : constant Spec := Spec_Of (Race_GT3);
         S1 : constant Spec := Tuned (Race_GT3, Winged);
      begin
         Check (S1.Cl_R > S0.Cl_R * 1.4 and then S1.Cd_A > S0.Cd_A, "more wing: more downforce and more drag");
      end;
      Check (Tuned (Road_GT, (Brake_Shift => 0.05, others => <>)).Brake_Bias
             > Spec_Of (Road_GT).Brake_Bias, "brake balance moves forward");
      --  The AI's cars do not get the player's setup
      declare
         S : Session.Settings := Hotlap (Road_GT);
      begin
         S.Tune.Final_Drive := 1.15;
         Session.Start (S);
         Check (Session.Player_Spec.Final > Session.Spec.Final, "the setup is the player's alone");
      end;
   end Setups;

   --  A lap's worth of use, by the AI, with the switches on
   procedure Wear_And_Fuel (K : Car_Kind) is
      S : Session.Settings := Hotlap (K);
      N : Vehicle.Inputs;
      Worn_Laps : Float;
   begin
      Track.Load (Track.Track_Id'First);
      S.Mode := Session.Demo;
      S.Opponents := 0;
      S.AI_Skill := 0.98;
      S.Assist.Wear_Rate := 1.0;
      S.Assist.Fuel_Use := True;
      S.Laps := 10;
      Session.Start (S);
      declare
         F0 : constant Float := Session.Cars (1).Fuel;
         Lap_S : Natural := 0;
         F1, F2 : Float := 0.0;
         W1 : Float := 0.0;
         W2 : Float := 0.0;
      begin
         Check (F0 > 0.0 and then F0 <= Tank, "fuelled for the race:" & Img (F0) & " kg");
         for I in 1 .. 1_000_000 loop
            Session.Step (N);
            if Session.Laps (1).Lap = 1 and then Lap_S = 0 then
               Lap_S := 1;
               F1 := Session.Cars (1).Fuel;
               W1 := Session.Cars (1).Wheels (3).Wear;
            elsif Session.Laps (1).Lap = 3 then
               F2 := Session.Cars (1).Fuel;
               W2 := Session.Cars (1).Wheels (3).Wear;
               exit;
            end if;
         end loop;
         Worn_Laps := (W2 - W1) / 2.0;
         Put_Line ("  " & Name (K) & ": fuel" & Img ((F1 - F2) / 2.0) & " kg a lap, "
                   & Img ((F1 - F2) / 2.0 / (Track.Length / 1000.0), 3) & " kg/km; rear tyre "
                   & Img (Worn_Laps * 100.0) & " % a lap");
         Check ((F1 - F2) / 2.0 / (Track.Length / 1000.0) < Fuel_Per_Km (K) * 1.05,
                "the fuel table is not short of what is burnt");
         Check ((F1 - F2) / 2.0 / (Track.Length / 1000.0) > Fuel_Per_Km (K) * 0.75,
                "and not far over");
         Check (Worn_Laps > 0.015 and then Worn_Laps < 0.07,
                "tyres last a sensible number of laps");
      end;
   end Wear_And_Fuel;

   --  A rally stage, driven whole under the stage's rules
   procedure Rally_Stage is
      S : Session.Settings := Hotlap (Rally_4WD);
      N : Vehicle.Inputs;
      Hits : Natural := 0;
      Off : Natural := 0;
      Dirt_Seen : Boolean := False;
   begin
      Track.Load (4);
      Check (Track.Is_Stage and then Track.Stage_End > 4000.0
             and then Track.Stage_End < Track.Length - 500.0,
             "the stage is" & Img (Track.Stage_End, 0) & " m of a" & Img (Track.Length, 0) & " m road");
      Check (Track.Trees'Length > 3000, "a forest:" & Track.Trees'Length'Image & " trees");
      --  No tree on the road
      declare
         Clear : Boolean := True;
         Hint : Natural := 0;
      begin
         for T of Track.Trees.all loop
            declare
               Nearest : constant Natural := Track.Find_Nearest (T.X, T.Z);
               I : Natural;
               Tt, D : Float;
            begin
               Hint := Nearest;
               Track.Locate (T.X, T.Z, Hint, I, Tt, D);
               Clear := Clear and then abs D > Track.Samples (I).W_L + 0.5;
            end;
         end loop;
         Check (Clear, "no tree stands on the road");
      end;
      --  Pace notes
      Check (Track.Note_Count > 20, "the co-driver has" & Track.Note_Count'Image & " notes");
      declare
         Good : Boolean := True;
         Tight : Natural := 0;
      begin
         for N of Track.Notes (1 .. Track.Note_Count) loop
            if N.Kind /= Track.Crest then
               declare
                  I : constant Natural := Natural (N.S / Track.Spacing);
                  K : constant Float := Track.Samples (Track.Next (I, 3)).Kappa;
               begin
                  Good := Good and then (K > 0.0) = (N.Kind = Track.Right);
                  Tight := Tight + (if N.Grade <= 3 then 1 else 0);
               end;
            end if;
         end loop;
         Check (Good, "each note turns the way the road does");
         Check (Tight > 3, "and some of them are serious:" & Tight'Image);
         for K in 2 .. Track.Note_Count loop
            Good := Good and then Track.Notes (K).S >= Track.Notes (K - 1).S;
         end loop;
         Check (Good, "they come in order");
      end;

      S.Mode := Session.Stage;
      S.Assist.Damage := 1.0;
      Session.Force_AI := True;
      Session.Start (S);
      Check (not Session.Lights_Out, "a stage starts on the lights");
      for I in 1 .. 3000 loop
         Session.Step (N);
      end loop;
      Check (Speed (Session.Cars (1)) < 0.5, "and nobody goes before them");
      declare
         L : Session.Lap_Info renames Session.Laps (1);
         C : Car renames Session.Cars (1);
      begin
         for I in 1 .. 700_000 loop
            Session.Step (N);
            Dirt_Seen := Dirt_Seen or else C.Wheels (1).Surf = Track.Dirt;
            if C.Impact > 2.0 and then I mod 100 = 0 then
               Hits := Hits + 1;
            end if;
            if C.Wheels (1).Surf = Track.Grass and then C.Wheels (4).Surf = Track.Grass
              and then I mod 100 = 0
            then
               Off := Off + 1;
            end if;
            exit when L.Finished;
         end loop;
         Check (L.Finished, "the AI's rally car finishes the stage");
         Check (Dirt_Seen, "on a dirt road");
         Put_Line ("  stage time " & Img (L.Finish_Time, 1) & " s, average "
                   & Img (Track.Stage_End / Float'Max (1.0, L.Finish_Time) * 3.6, 0)
                   & " km/h, hits" & Hits'Image & ", off" & Off'Image
                   & ", damage" & Img (C.Dmg_Aero));
         Check (L.Finish_Time > 150.0 and then L.Finish_Time < 500.0, "in a sensible time");
         Check (Hits < 30, "without wrecking the trees");
         Check (Ada.Directories.Exists (Session.Save_Name), "the stage record is saved");
         Check (Session.Race_Over, "and the stage is over");
         Session.Force_AI := False;
         declare
            T0 : constant Float := L.Lap_Time;
         begin
            for I in 1 .. 8000 loop
               Session.Step (N);
            end loop;
            Check (L.Lap_Time = T0, "the clock has stopped");
            Check (Speed (C) < 12.0, "and the car is being brought to a halt");
         end;
      end;
      Session.Force_AI := False;

      --  What the player must face: into a tree, and back on the road
      Session.Start (S);
      declare
         C : Car renames Session.Cars (1);
         L : Session.Lap_Info renames Session.Laps (1);
         T : Track.Tree renames Track.Trees (Track.Trees'First);
         Near : Float := Float'Last;
         Which : Positive := 1;
      begin
         --  A tree near the road, about half way
         for K in Track.Trees'Range loop
            declare
               P : Track.Sample renames Track.Samples (Track.Count / 3);
               D2 : constant Float := (Track.Trees (K).X - P.X) ** 2 + (Track.Trees (K).Z - P.Z) ** 2;
            begin
               if D2 < Near then
                  Near := D2;
                  Which := K;
               end if;
            end;
         end loop;
         pragma Unreferenced (T);
         declare
            Tr : Track.Tree renames Track.Trees (Which);
            Hdg : constant Float := 0.7;
         begin
            Place (C, Rally_4WD, Tr.X - Sin (Hdg) * 25.0, Tr.Z + Cos (Hdg) * 25.0, Hdg);
            C.Vx := 28.0;
            for W in Wheel_Id loop
               C.Wheels (W).Omega := C.Vx / Session.Player_Spec.Radius;
            end loop;
            declare
               Peak : Float := 0.0;
            begin
               for I in 1 .. 4000 loop
                  Session.Step (N);
                  Peak := Float'Max (Peak, C.Impact);
               end loop;
               Check (Peak > 10.0, "a tree stops the car:" & Img (Peak) & " m/s");
               Check (C.Dmg_Aero > 0.1, "and breaks it");
               Check ((Float (C.X) - Tr.X) ** 2 + (Float (C.Z) - Tr.Z) ** 2 > 0.5,
                      "and the car is not inside the tree");
            end;
         end;
         --  Put back: it costs time, keeps the damage, and is on the road again
         L.On_Grid := False;
         L.Progress := 500.0;
         declare
            T0 : constant Float := L.Lap_Time;
            A0 : constant Float := C.Dmg_Aero;
         begin
            Session.Reset_Player;
            Check (L.Lap_Time >= T0 + Session.Reset_Penalty - 0.01, "putting the car back costs 15 s");
            Check (C.Dmg_Aero = A0, "and mends nothing");
            Check (abs (Track.Samples (C.Hint).S - 500.0) < 10.0,
                   "and it is back where it left the road, no further");
            Check (not L.Invalid, "the stage still counts");
         end;
         --  A short cut does not reach the finish
         L.Progress := 500.0;
         C.Hint := Natural (Track.Stage_End / Track.Spacing) + 4;
         Session.Step (N);
         Check (not L.Finished, "jumping ahead does not finish the stage");
      end;
   end Rally_Stage;

   --  A stage driven by the player's controls, not the AI's: a plain driver
   --  who looks ahead along the road, as a person's hands would
   procedure Stage_By_Hand is
      S : Session.Settings := Hotlap (Rally_4WD);
      N : Vehicle.Inputs;
      Hint : Natural := 0;
      Notes_Seen : Natural := 0;
      Last_Note : Natural := 0;
   begin
      Track.Load (4);
      S.Mode := Session.Stage;
      Session.Force_AI := False;
      Session.Start (S);
      declare
         C : Car renames Session.Cars (1);
         L : Session.Lap_Info renames Session.Laps (1);
      begin
         Hint := C.Hint;
         for I in 1 .. 900_000 loop
            declare
               Idx : Natural;
               T, D : Float;
            begin
               Track.Locate (Float (C.X), Float (C.Z), Hint, Idx, T, D);
               declare
                  P : Track.Sample renames Track.Samples (Track.Next (Idx, 6 + Natural (Speed (C) / 5.0)));
                  Aim : constant Float :=
                    Arctan (P.X - Float (C.X), -(P.Z - Float (C.Z)));
                  E : Float := Aim - C.Heading;
                  V_Want : constant Float :=
                    Track.Samples (Track.Next (Idx, 10)).Line_V * 0.7;
               begin
                  if E > 3.14159 then
                     E := E - 6.28318;
                  elsif E < -3.14159 then
                     E := E + 6.28318;
                  end if;
                  N.Steer := E * 1.6;
                  N.Throttle := (if Speed (C) < V_Want then 0.7 else 0.0);
                  N.Brake := (if Speed (C) > V_Want + 3.0 then 0.5 else 0.0);
               end;
            end;
            Session.Step (N);
            declare
               Now : constant Natural := Track.Next_Note (L.S);
            begin
               if Now /= Last_Note then
                  Last_Note := Now;
                  Notes_Seen := Notes_Seen + 1;
               end if;
            end;
            exit when L.Finished;
         end loop;
         Check (not L.On_Grid, "by hand: the car crosses the start line");
         Check (Notes_Seen > Track.Note_Count / 2,
                "the co-driver's notes move on:" & Notes_Seen'Image & " of" & Track.Note_Count'Image);
         Check (L.Progress > Track.Stage_End * 0.99, "the distance to go counts down");
         Check (L.Finished, "by hand: the stage finishes,"
                & Img (L.Finish_Time, 1) & " s");
      end;
   end Stage_By_Hand;

   --  Weather: the same car, the same road, what the tyres have left
   procedure Conditions is
      function Stop (K : Car_Kind; W : Session.Weather_Kind; Se : Session.Season_Kind) return Float is
         C : Car;
         S : constant Spec := Spec_Of (K);
         R : Session.Settings := Hotlap (K);
         N : constant Vehicle.Inputs := (Brake => 1.0, others => <>);
         A : constant Assists := (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>);
         D : Float := 0.0;
      begin
         R.Weather := W;
         R.Season := Se;
         Session.Start (R);
         declare
            A0 : Track.Sample renames Track.Samples (20);
         begin
            Place (C, K, A0.X, A0.Z, Arctan (A0.TX, -A0.TZ));
         end;
         C.Vx := 22.0;
         for I in Wheel_Id loop
            C.Wheels (I).Omega := C.Vx / S.Radius;
         end loop;
         for I in 1 .. 15000 loop
            Vehicle.Step (C, S, N, A);
            D := D + C.Vx * Dt;
            exit when C.Vx < 0.5;
         end loop;
         return D;
      end Stop;
   begin
      Track.Load (1);
      declare
         Dry : constant Float := Stop (Road_GT, Session.Clear, Session.Summer);
         Wet : constant Float := Stop (Road_GT, Session.Rain, Session.Summer);
         Ice : constant Float := Stop (Road_GT, Session.Clear, Session.Winter);
         Slick_Dry : constant Float := Stop (Race_GT3, Session.Clear, Session.Summer);
         Slick_Wet : constant Float := Stop (Race_GT3, Session.Rain, Session.Summer);
      begin
         Put_Line ("  80-0 km/h, road car: dry " & Img (Dry, 1) & " m, rain " & Img (Wet, 1)
                   & " m, winter " & Img (Ice, 1) & " m; slicks dry " & Img (Slick_Dry, 1)
                   & " m, rain " & Img (Slick_Wet, 1) & " m");
         Check (Wet > Dry * 1.15, "rain takes longer to stop in");
         Check (Ice > Wet, "and winter longer still");
         Check (Slick_Wet / Slick_Dry > Wet / Dry, "slicks suffer more in the wet");
      end;
      --  The winter name does not overwrite the summer record
      declare
         R : Session.Settings := Hotlap (Road_GT);
      begin
         Session.Start (R);
         declare
            Name_Dry : constant String := Session.Save_Name;
         begin
            R.Weather := Session.Rain;
            Session.Start (R);
            Check (Name_Dry /= Session.Save_Name, "rain keeps its own records");
         end;
         R.Weather := Session.Rain;
         R.Season := Session.Winter;
         Session.Start (R);
         Check (Session.Config.Weather = Session.Snowing, "in winter the rain comes down as snow");
      end;
      --  The AI gets round in all of it, slower
      for W in Session.Weather_Kind loop
         for Ci in 1 .. 2 loop
            declare
               T : constant Track.Track_Id := (if Ci = 1 then 2 else 4);
               R : Session.Settings := Hotlap (Rally_4WD);
               N : Vehicle.Inputs;
               Hit : Float := 0.0;
            begin
               Track.Load (T);
               R.Mode := Session.Demo;
               R.AI_Skill := 0.95;
               R.Weather := W;
               Session.Start (R);
               for I in 1 .. 1_500_000 loop
                  Session.Step (N);
                  Hit := Float'Max (Hit, Session.Cars (1).Impact);
                  exit when Session.Laps (1).Lap >= 2;
               end loop;
               Put_Line ("  " & Track.Name (T) & " in " & W'Image & ": lap "
                         & Img (Session.Laps (1).Last_Time, 1) & " s, worst hit " & Img (Hit, 1)
                         & ", laps" & Session.Laps (1).Lap'Image & ", t" & Img (Session.Time, 0)
                         & ", S" & Img (Session.Laps (1).S, 0) & " v" & Img (Speed (Session.Cars (1)), 1));
               Check (Session.Laps (1).Lap >= 2, "the AI gets round");
               Check (Hit < 6.0, "without a real crash");
            end;
         end loop;
      end loop;
      Track.Wet := 0.0;
      Track.Snow := 0.0;
   end Conditions;

   --  The driving school: run each lesson by the AI, which drives it well,
   --  and by a heavy foot, which must fail
   procedure Lessons is
      procedure Run (L : School.Lesson_Id; Heavy : Boolean; Phase : out School.Phase_Kind) is
         R : Session.Settings := Hotlap (School.Car (L));
         N : Vehicle.Inputs;
         Hint : Natural := 0;
      begin
         Track.Load (School.Circuit (L));
         R := School.Prepare (L, R);
         R.Assist.Mode := Automatic;
         R.AI_Skill := 0.92;
         Session.Force_AI := not Heavy;
         Session.Start (R);
         School.Begin_Lesson (L);
         Check (School.Current.Par > 10.0, "lesson" & L'Image & " has a time to beat:"
                & Img (School.Current.Par, 0) & " s");
         for I in 1 .. 700_000 loop
            if Heavy then
               --  Steers fine, but no brakes: flat out
               declare
                  C : Car renames Session.Cars (1);
                  Idx : Natural;
                  T, D : Float;
               begin
                  Track.Locate (Float (C.X), Float (C.Z), Hint, Idx, T, D);
                  declare
                     P : Track.Sample renames Track.Samples (Track.Next (Idx, 6 + Natural (Speed (C) / 5.0)));
                     E0 : constant Float :=
                       Arctan (P.X - Float (C.X), -(P.Z - Float (C.Z))) - C.Heading;
                     E : constant Float :=
                       (if E0 > 3.14159 then E0 - 6.28318 elsif E0 < -3.14159 then E0 + 6.28318 else E0);
                  begin
                     N.Steer := E * 1.6;
                     N.Throttle := 1.0;
                  end;
               end;
            end if;
            Session.Step (N);
            School.Step (N);
            exit when School.Current.Phase /= School.Running;
         end loop;
         Phase := School.Current.Phase;
         Put_Line ("  " & School.Title (L) & (if Heavy then " (heavy foot): " else " (AI): ")
                   & School.Phase_Kind'Image (Phase) & ". " & School.Result_Line);
         Session.Force_AI := False;
      end Run;
      Got : School.Phase_Kind;
   begin
      for L in School.Lesson_Id loop
         if L /= 4 then
            Run (L, False, Got);
            Check (Got = School.Passed, "a good driver passes lesson" & L'Image);
         end if;
      end loop;
      Run (2, True, Got);
      Check (Got = School.Failed, "a heavy foot fails the braking lesson");
      Check (School.Tip_Len > 0, "the coach has something to say: " & School.Tip (1 .. School.Tip_Len));
      Check (School.Tip (1 .. Natural'Min (School.Tip_Len, 200)) /= "", "and it is not empty");
      --  Nothing saved by a lesson
      Check (not Ada.Directories.Exists (Session.Save_Name), "a lesson sets no record");
      --  Lesson 4 counts slides: fed one by hand
      declare
         R : Session.Settings := Hotlap (Rally_4WD);
      begin
         Track.Load (4);
         R := School.Prepare (4, R);
         Session.Start (R);
         School.Begin_Lesson (4);
         declare
            C : Car renames Session.Cars (1);
            L : Session.Lap_Info renames Session.Laps (1);
            N : Vehicle.Inputs;
         begin
            L.On_Grid := False;
            for Rep in 1 .. 3 loop
               C.Vx := 20.0;
               C.Vy := 6.0;
               for I in 1 .. 500 loop
                  C.Vy := 6.0;
                  School.Step (N);
               end loop;
               C.Vy := 0.0;
               School.Step (N);
            end loop;
            Check (School.Current.Slides = 3, "slides are counted:" & School.Current.Slides'Image);
         end;
      end;
      School.Begin_Lesson (0);
      --  The coach on a plain lap, the AI over its own limit: says brake earlier
      Track.Load (2);
      declare
         R : Session.Settings := Hotlap (Road_GT);
         N : Vehicle.Inputs;
      begin
         R.AI_Skill := 1.16;
         Session.Force_AI := True;
         Session.Start (R);
         School.Begin_Lesson (0);
         for I in 1 .. 300_000 loop
            Session.Step (N);
            School.Step (N);
            exit when School.Tip_Len > 0;
         end loop;
         Session.Force_AI := False;
         Put_Line ("  coach: " & School.Tip (1 .. School.Tip_Len));
         Check (Ada.Strings.Fixed.Index (School.Tip (1 .. School.Tip_Len), "too fast") > 0,
                "the coach says who is going in too fast");
      end;
   end Lessons;

   --  A street circuit: walls at the kerb, and no building on the road
   procedure Street_Circuit is
      City : Natural := 0;
   begin
      for T in 1 .. Track.Track_Count loop
         Track.Load (T);
         if Track.Is_City then
            City := T;
            exit;
         end if;
      end loop;
      Check (City > 0, "there is a street circuit");
      if City = 0 then
         return;
      end if;
      declare
         Close : Boolean := True;
         Clear : Boolean := True;
      begin
         for I in 0 .. Track.Count - 1 loop
            declare
               S : Track.Sample renames Track.Samples (I);
            begin
               if S.S > Track.Pit_To + 30.0 then
                  Close := Close and then S.Wall_L - S.W_L < 4.0 and then S.Wall_R - S.W_R < 4.0;
               end if;
            end;
         end loop;
         Check (Close, "the walls stand close to the road");
         Check (Track.Buildings'Length > 60, "a town:" & Track.Buildings'Length'Image & " buildings");
         for B of Track.Buildings.all loop
            declare
               H : Natural := Track.Find_Nearest (B.X, B.Z);
               I : Natural;
               Tt, D : Float;
            begin
               Track.Locate (B.X, B.Z, H, I, Tt, D);
               Clear := Clear and then abs D - 0.5 * Float'Max (B.Len, B.Depth)
                 > Float'Max (Track.Samples (I).Wall_L, Track.Samples (I).Wall_R);
            end;
         end loop;
         Check (Clear, "no building stands in the road or its walls");
         Check (Track.Has_Water and then Track.Water_Y < Track.Samples (0).Y,
                "the harbour lies below the quay");
      end;
   end Street_Circuit;

   --  Road files: bad ones are named, by line, and the game goes on
   procedure Road_Files is
      use Ada.Text_IO;
      Dir : constant String := Ada.Environment_Variables.Value ("HOME") & "/tracks";
      procedure Try (Text : String; Want_Good : Boolean; What : String; Want_Line : Natural := 0) is
         F : File_Type;
         Name : constant String := Dir & "/try.track";
         Good : Boolean;
         Why : Positive;
      begin
         Ada.Directories.Create_Path (Dir);
         Create (F, Out_File, Name);
         Put (F, Text);
         Close (F);
         Track.Check_File (Name, Good, Why);
         Check (Good = Want_Good and then (Want_Line = 0 or else Why = Want_Line),
                What & (if Good then "" else ", line" & Why'Image));
      end Try;
      LF : constant Character := ASCII.LF;
      Pts : constant String :=
        "points" & LF & "0 0 1 4 0" & LF & "100 0 1 4 0" & LF & "100 100 1 4 0" & LF & "0 100 1 4 0" & LF;
   begin
      Try ("name A" & LF & "kind circuit" & LF & Pts, True, "a good road is read");
      Try ("# c" & LF & "name A # t" & LF & "kind stage" & LF & "finish 100 100" & LF & Pts, True,
           "with comments, and a stage");
      Try ("kind circuit" & LF & Pts, False, "a road without a name is refused");
      Try ("name A" & LF & "kind stage" & LF & Pts, False, "a stage without a finish is refused");
      Try ("name A" & LF & "kind boat" & LF & Pts, False, "an unknown kind is refused, naming the line", 2);
      Try ("name A" & LF & "kind circuit" & LF & "points" & LF & "1 2 3" & LF, False,
           "a short point is refused, naming the line", 4);
      Try ("name A" & LF & "kind circuit" & LF & "points" & LF & "a 2 3 4 5" & LF, False,
           "words for numbers are refused", 4);
      Try ("name A" & LF & "kind circuit" & LF & "points" & LF & "0 0 1 4 0" & LF, False,
           "too few points are refused");
      Try ("name A" & LF & "kind circuit" & LF & "points" & LF & "0 0 1 0.5 0" & LF, False,
           "a road too narrow is refused", 4);
      Check (Track.Track_Count >= 6, "the shipped roads are all read:" & Track.Track_Count'Image);
      declare
         Stages : Natural := 0;
      begin
         for T in 1 .. Track.Track_Count loop
            Stages := Stages + (if Track.Stage_Road (T) then 1 else 0);
         end loop;
         Check (Stages >= 3, "of them, stages:" & Stages'Image);
      end;
   end Road_Files;

   --  A season, every round raced by the AI in all the cars
   procedure Season is
      R : Session.Settings := Hotlap (Race_GT3);
      N : Vehicle.Inputs;
      Total : Natural := 0;
   begin
      R.Mode := Session.Race;
      R.Opponents := 3;
      R.Laps := 1;
      Championship.Begin_Season (R.Opponents + 1);
      Check (Championship.Round_Total >= 4, "a season has" & Championship.Round_Total'Image & " rounds");
      for Round in 1 .. Championship.Round_Total loop
         Track.Load (Championship.Current_Road);
         Check (not Track.Is_Stage, "round" & Round'Image & " is a circuit");
         Session.Force_AI := True;
         Session.Start (R);
         for I in 1 .. 900_000 loop
            Session.Step (N);
            exit when Session.Race_Over;
         end loop;
         Check (Session.Race_Over, Track.Name (Championship.Current_Road) & " raced");
         Championship.Finish_Round;
         Championship.Finish_Round;   --  (twice: counted once)
         if Round < Championship.Round_Total then
            Championship.Next_Round;
         end if;
      end loop;
      Session.Force_AI := False;
      declare
         T : constant Championship.Table := Championship.Standings;
      begin
         for E of T loop
            Total := Total + E.Points;
         end loop;
         Check (Total = Championship.Round_Total * (25 + 18 + 15 + 12),
                "every round gave out its points, once:" & Total'Image);
         Check (T (T'First).Points >= T (T'Last).Points, "the table is in order");
         Put_Line ("    champion " & Championship.Driver_Name (T (T'First).Car)
                   & T (T'First).Points'Image & " points");
      end;
      Championship.Active := False;
   end Season;

   --  Two players: car 2 answers to the second pair of hands, not the AI
   procedure Two_Up is
      R : Session.Settings := Hotlap (Road_GT);
      N : Vehicle.Inputs;
   begin
      Track.Load (1);
      R.Mode := Session.Race;
      R.Two_Players := True;
      R.Opponents := 2;
      Session.Start (R);
      Check (not Session.AI_Drives (2) and then Session.AI_Drives (3),
             "car 2 is the second player's, car 3 the AI's");
      Session.Second_Hands := (others => <>);
      declare
         X2 : constant Long_Float := Session.Cars (2).X;
         Z2 : constant Long_Float := Session.Cars (2).Z;
         X3 : constant Long_Float := Session.Cars (3).X;
         Z3 : constant Long_Float := Session.Cars (3).Z;
         function Moved (C : Car; X, Z : Long_Float) return Float is
           (Float (Sqrt (Float ((C.X - X) ** 2 + (C.Z - Z) ** 2))));
         Knocks : Float := 0.0;
      begin
         for I in 1 .. 14000 loop
            Session.Step (N);
            Knocks := Float'Max (Knocks, Session.Cars (2).Impact);
         end loop;
         Put_Line ("    car 2, untouched by its player, was knocked at up to" & Img (Knocks) & " m/s");
         --  (the AI going past may nudge it; driving it would take it hundreds of metres)
         Check (Moved (Session.Cars (2), X2, Z2) < 0.3 * Moved (Session.Cars (3), X3, Z3) and then Moved (Session.Cars (3), X3, Z3) > 40.0,
                "with no hands on it car 2 stays put, while the AI goes:"
                & Img (Moved (Session.Cars (2), X2, Z2), 1) & " m against"
                & Img (Moved (Session.Cars (3), X3, Z3), 0) & " m");
      end;
      Session.Second_Hands := (Throttle => 1.0, others => <>);
      for I in 1 .. 4000 loop
         Session.Step (N);
      end loop;
      Check (Speed (Session.Cars (2)) > 10.0, "on the second player's throttle it goes:"
             & Img (Speed (Session.Cars (2)) * 3.6, 0) & " km/h");
      Session.Second_Hands := (others => <>);
   end Two_Up;

   --  A rally from end to end, the AI driving, damage going along
   procedure Rally_Event is
      R : Session.Settings := Hotlap (Rally_4WD);
      N : Vehicle.Inputs;
   begin
      R.Mode := Session.Stage;
      R.Assist.Damage := 1.0;
      Rally.Begin_Rally (0.93);
      Check (Rally.Stage_Total >= 3, "a rally has" & Rally.Stage_Total'Image & " stages");
      for Stage in 1 .. Rally.Stage_Total loop
         Track.Load (Rally.Current_Road);
         Session.Force_AI := True;
         Session.Start (R);
         if Stage = 2 then
            Session.Cars (1).Dmg_Aero := 0.4;    --  (fed in, to follow it along)
         end if;
         Rally.Carry_Over (Session.Cars (1));
         if Stage = 3 then
            Check (abs (Session.Cars (1).Dmg_Aero - 0.2) < 0.05 or else Session.Cars (1).Dmg_Aero < 0.3,
                   "the service mended half of what was bent");
         end if;
         if Stage = 2 then
            Session.Cars (1).Dmg_Aero := 0.4;
         end if;
         for I in 1 .. 900_000 loop
            Session.Step (N);
            exit when Session.Laps (1).Finished;
         end loop;
         Check (Session.Laps (1).Finished, Track.Name (Rally.Current_Road) & ": finished in"
                & Img (Session.Laps (1).Finish_Time, 1) & " s");
         Rally.Finish_Stage (Session.Laps (1).Finish_Time, Session.Cars (1));
         Check (Rally.Standings (1).Total <= Rally.Standings (2).Total, "the table is in order");
         Put_Line ("    leader " & Rally.Crew_Name (Rally.Standings (1).Crew) & Img (Rally.Standings (1).Total, 1)
                   & ", you P" & Rally.Position'Image);
         if Stage < Rally.Stage_Total then
            Rally.Next_Stage;
         end if;
      end loop;
      Check (Rally.Is_Last, "and the last stage is the last");
      Session.Force_AI := False;
      Rally.Active := False;
   end Rally_Event;

   --  The co-driver: everything read out, in order, in time to act on it
   procedure Spoken_Notes is
      use type Codriver.Word;
      R : Session.Settings := Hotlap (Rally_4WD);
      N : Vehicle.Inputs;
      Words : Natural := 0;
      Calls : Natural := 0;
      Late : Natural := 0;
      Finish_Heard : Boolean := False;
      Busy_Until : Float := 0.0;
      Over_Talk : Natural := 0;
      Tightest_Heard : Boolean := False;
      Per_Word : constant := 0.42;   --  seconds a word takes, about
   begin
      Track.Load (4);
      R.Mode := Session.Stage;
      Session.Force_AI := True;
      Session.Start (R);
      Codriver.Reset;
      declare
         L : Session.Lap_Info renames Session.Laps (1);
         Last_Next : Natural := 0;
      begin
         for I in 1 .. 700_000 loop
            Session.Step (N);
            exit when L.Finished;
            if I mod 16 = 0 and then not L.On_Grid then
               Codriver.Update (L.S, Speed (Session.Cars (1)), Track.Stage_End - L.Progress);
               declare
                  W : Codriver.Word;
                  Got : Boolean := True;
                  Said : Natural := 0;
                  Now : constant Float := Session.Time;
               begin
                  while Got loop
                     Codriver.Next_Word (W, Got);
                     if Got then
                        Said := Said + 1;
                        Words := Words + 1;
                        Finish_Heard := Finish_Heard or else W = Codriver.Finish;
                        Tightest_Heard := Tightest_Heard or else W in Codriver.Two | Codriver.Three | Codriver.Hairpin;
                     end if;
                  end loop;
                  if Said > 0 then
                     Calls := Calls + 1;
                     if Now < Busy_Until then
                        Over_Talk := Over_Talk + 1;
                     end if;
                     Busy_Until := Float'Max (Now, Busy_Until) + Float (Said) * Per_Word;
                     --  The corner called must still be seconds away
                     declare
                        Nx : constant Natural := Track.Next_Note (L.S);
                     begin
                        if Nx > 0 and then Nx /= Last_Next
                          and then Track.Notes (Nx).S - L.S < Speed (Session.Cars (1)) * 1.5
                        then
                           Late := Late + 1;
                        end if;
                        Last_Next := Nx;
                     end;
                  end if;
               end;
            end if;
         end loop;
      end;
      Session.Force_AI := False;
      Put_Line ("  co-driver:" & Calls'Image & " calls," & Words'Image & " words over"
                & Track.Note_Count'Image & " notes; called late" & Late'Image
                & ", still speaking at the next" & Over_Talk'Image);
      Check (Calls >= Track.Note_Count * 3 / 4, "every note gets called");
      Check (Late = 0, "and in time to act on it");
      Check (Over_Talk <= Calls / 5, "without talking over itself much");
      Check (Finish_Heard, "the finish is called");
      Check (Tightest_Heard, "and so is the tightest corner");
      Check (Codriver.File_Name (Codriver.Hairpin) = "sounds/codriver/hairpin.pcm", "the clip names");
      --  Put back on the road, it reads the corners again; no repeat otherwise
      declare
         W : Codriver.Word;
         Got : Boolean;
         Heard : Natural := 0;
         Far : constant Float := Track.Notes (10).S - 300.0;
      begin
         Codriver.Reset;
         Codriver.Update (Track.Notes (10).S - 5.0, 20.0, 3000.0);
         for K in 1 .. 50 loop
            Codriver.Update (Track.Notes (10).S - 5.0, 20.0, 3000.0);
         end loop;
         loop
            Codriver.Next_Word (W, Got);
            exit when not Got;
            Heard := Heard + 1;
         end loop;
         Check (Heard in 1 .. 6, "a call is made once:" & Heard'Image & " words");
         Codriver.Update (Far, 20.0, 3000.0);
         Codriver.Update (Far + 280.0, 20.0, 3000.0);
         Codriver.Next_Word (W, Got);
         Check (Got, "after going back along the road, the corners are read again");
      end;
   end Spoken_Notes;

   --  Loose surface: the same car, the same pedal, less grip and more slide
   procedure Loose_Surface is
      function Stop_Distance (Stage : Boolean) return Float is
         C : Car;
         S : constant Spec := Spec_Of (Rally_4WD);
         N : constant Vehicle.Inputs := (Brake => 1.0, others => <>);
         A : constant Assists := (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>);
         D : Float := 0.0;
      begin
         Track.Load (if Stage then 4 else 1);
         declare
            A0 : Track.Sample renames Track.Samples (20);
         begin
            Place (C, Rally_4WD, A0.X, A0.Z, Arctan (A0.TX, -A0.TZ));
         end;
         C.Vx := 22.0;
         for W in Wheel_Id loop
            C.Wheels (W).Omega := C.Vx / S.Radius;
         end loop;
         for I in 1 .. 8000 loop
            Vehicle.Step (C, S, N, A);
            D := D + C.Vx * Dt;
            exit when C.Vx < 0.5;
         end loop;
         return D;
      end Stop_Distance;
      Tar : constant Float := Stop_Distance (False);
      Mud : constant Float := Stop_Distance (True);
   begin
      Put_Line ("  80-0 km/h: tarmac " & Img (Tar, 1) & " m, dirt " & Img (Mud, 1) & " m");
      Check (Mud > Tar * 1.1, "a dirt road takes longer to stop on");
      Check (Mud < Tar * 2.2, "but not absurdly");
   end Loose_Surface;

   procedure Damage_And_Pits is
      S : Session.Settings := Hotlap (Road_GT);
      N : Vehicle.Inputs;
   begin
      --  Left standing on the grid, the player is last
      Track.Load (Track.Track_Id'First);
      declare
         R : Session.Settings := Hotlap (Road_GT);
      begin
         R.Mode := Session.Race;
         R.Opponents := 3;
         Session.Start (R);
         for I in 1 .. 25_000 loop
            Session.Step (N);
         end loop;
         Check (Session.Laps (1).Position = 4,
                "whoever stays on the grid is last, not first: P" & Session.Laps (1).Position'Image);
      end;
      --  Room for the box inside the barrier, at every circuit
      for T in 1 .. Track.Track_Count loop
         Track.Load (T);
         declare
            Clear : Boolean := True;
         begin
            for I in 0 .. Track.Count - 1 loop
               declare
                  P : Track.Sample renames Track.Samples (I);
               begin
                  if P.S in Track.Pit_From .. Track.Pit_To then
                     Clear := Clear and then P.W_L + P.Kerb_L + Track.Pit_Wide < P.Wall_L - 0.5;
                  end if;
               end;
            end loop;
            Check (Clear, "the pit box fits at " & Track.Name (T));
         end;
      end loop;
      Track.Load (Track.Track_Id'First);
      S.Mode := Session.Race;
      S.Opponents := 1;
      S.Assist.Damage := 1.0;
      S.Assist.Wear_Rate := 1.0;
      S.Assist.Fuel_Use := True;
      S.Assist.Mode := Automatic;
      S.Laps := 3;
      Session.Start (S);
      --  Into the barrier: flat out, square on
      declare
         C : Car renames Session.Cars (1);
         I0 : Track.Sample renames Track.Samples (Track.Next (0, 60));
         Facing : constant Float := Arctan (-I0.TZ, -I0.TX);
         Fast : Float := 0.0;
         V_Before, V_After : Float;

         function Top_Speed return Float is
         begin
            return Float (Session.Cars (1).Dmg_Engine);
         end Top_Speed;
         pragma Unreferenced (Top_Speed);
      begin
         Place (C, Road_GT, I0.X, I0.Z, Arctan (I0.TX, -I0.TZ) + 1.57);
         C.Vx := 45.0;
         for W in Wheel_Id loop
            C.Wheels (W).Omega := C.Vx / Session.Player_Spec.Radius;
         end loop;
         for I in 1 .. 3000 loop
            Session.Step (N);
            Fast := Float'Max (Fast, C.Impact);
         end loop;
         pragma Unreferenced (Facing, V_Before, V_After);
         Check (Fast > 15.0, "the test does hit the barrier:" & Img (Fast) & " m/s");
         Check (C.Dmg_Aero > 0.3 and then C.Dmg_Engine > 0.2,
                "a big hit does damage: aero" & Img (C.Dmg_Aero) & ", engine" & Img (C.Dmg_Engine));
         Check (abs C.Toe > 0.01, "and bends the steering");
         declare
            A0 : constant Float := C.Dmg_Aero;
         begin
            Session.Reset_Player;
            Check (C.Dmg_Aero = A0, "going back on the track does not mend it");
         end;
      end;
      --  A small knock does nothing
      declare
         C : Car renames Session.Cars (1);
         A0 : constant Float := C.Dmg_Aero;
      begin
         C.Hit_X := 2.0;
         C.Impact := 4.5;
         Session.Step (N);
         Check (C.Dmg_Aero = A0, "a knock costs nothing");
      end;
      --  The pit box: to it, stopped
      declare
         C : Car renames Session.Cars (1);
         Box : Natural := 0;
      begin
         for I in 0 .. Track.Count - 1 loop
            if Track.Samples (I).S > (Track.Pit_From + Track.Pit_To) / 2.0 then
               Box := I;
               exit;
            end if;
         end loop;
         declare
            P : Track.Sample renames Track.Samples (Box);
            D : constant Float := P.W_L + P.Kerb_L + 2.5;
            Fuel0 : constant Float := 2.0;
         begin
            Check (Track.In_Pit_Box (Box, -D), "the pit box is where it says");
            Check (D + 1.0 < P.Wall_L, "and inside the barrier");
            declare
               Keep_Aero : constant Float := C.Dmg_Aero;
               Keep_Eng : constant Float := C.Dmg_Engine;
               Keep_Toe : constant Float := C.Toe;
            begin
               Place (C, Road_GT, P.X - P.RX * D, P.Z - P.RZ * D, Arctan (P.TX, -P.TZ));
               C.Dmg_Aero := Keep_Aero;
               C.Dmg_Engine := Keep_Eng;
               C.Toe := Keep_Toe;
            end;
            C.Fuel := Fuel0;
            C.Wheels (3).Wear := 0.4;
            Session.Laps (1).Lap := 1;
            for I in 1 .. 2000 loop
               Session.Step (N);
            end loop;
            Check (Session.Service_Left > 0.0, "stopping there starts the service:"
                   & Img (Session.Service_Left) & " s");
            N.Throttle := 1.0;
            for I in 1 .. 2000 loop
               Session.Step (N);
            end loop;
            Check (Speed (C) < 0.5, "the crew holds the car");
            for I in 1 .. 120_000 loop
               exit when Session.Service_Left = 0.0;
               Session.Step (N);
            end loop;
            Check (C.Dmg_Aero = 0.0 and then C.Dmg_Engine = 0.0 and then C.Toe = 0.0
                   and then C.Wheels (3).Wear < 0.001,
                   "and sends it out mended, on new tyres");
            Check (C.Fuel > Fuel0 + 1.0, "and fuelled:" & Img (C.Fuel) & " kg");
         end;
      end;
      --  Running dry
      declare
         C : Car renames Session.Cars (1);
         V : Float;
      begin
         N.Throttle := 0.0;
         N.Brake := 0.0;
         --  (out on the road: in the box the crew would simply fill it up)
         declare
            P : Track.Sample renames Track.Samples (Track.Next (0, 200));
         begin
            Place (C, Road_GT, P.X, P.Z, Arctan (P.TX, -P.TZ));
         end;
         C.Fuel := 0.0;
         N.Throttle := 1.0;
         V := Speed (C);
         for I in 1 .. 8000 loop
            Session.Step (N);
         end loop;
         Check (Speed (C) <= V + 0.1, "with an empty tank it does not go:" & Img (V) & " to"
                & Img (Speed (C)) & " m/s");
      end;
   end Damage_And_Pits;

begin
   --  Never touch the player's own saved laps
   Ada.Environment_Variables.Set
     ("HOME", Ada.Directories.Current_Directory & "/obj/test/home");
   if Ada.Directories.Exists (Ada.Environment_Variables.Value ("HOME")) then
      Ada.Directories.Delete_Tree (Ada.Environment_Variables.Value ("HOME"));
   end if;
   for T in 1 .. Track.Track_Count loop
      Track_Shape (T);
   end loop;
   Stand_Still;
   for K in Car_Kind loop
      Straight (K);
   end loop;
   for T in 1 .. Track.Track_Count loop
      for K in Car_Kind loop
         AI_Lap (T, K);
      end loop;
   end loop;
   Controls;
   Race_Run;
   Sliding_Rack;
   Player_Lap;
   Setups;
   for K in Car_Kind loop
      Wear_And_Fuel (K);
   end loop;
   Damage_And_Pits;
   Loose_Surface;
   Rally_Stage;
   Stage_By_Hand;
   Road_Files;
   Street_Circuit;
   Rally_Event;
   Season;
   Two_Up;
   Spoken_Notes;
   Conditions;
   Lessons;
   New_Line;
   Put_Line (if Failed = 0 then "All passed" else Failed'Image & " FAILED");
   Ada.Command_Line.Set_Exit_Status (if Failed = 0 then 0 else 1);
end Simtest;
