--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  One sitting at the circuit: the cars, the AI drivers, the lap timing,
--  the start lights, the race order and the ghost of the best lap.  Pure
--  simulation: runs the same under the real-time loop and in the tests.

with Vehicle;

package Session is

   Max_Cars : constant := 8;
   subtype Car_Index is Positive range 1 .. Max_Cars;

   type Mode_Kind is (Hotlap, Race, Demo, Stage);
   --  Demo: the AI drives car 1 too (the menu's background)

   type Weather_Kind is (Clear, Rain, Fog, Snowing);
   type Season_Kind is (Summer, Autumn, Winter, Spring);

   type Settings is record
      Mode     : Mode_Kind := Hotlap;
      Kind     : Vehicle.Car_Kind := Vehicle.Road_GT;
      Assist   : Vehicle.Assists;
      Opponents : Natural range 0 .. Max_Cars - 1 := 5;
      Laps     : Positive := 5;
      AI_Skill : Float := 0.95;
      Tune     : Vehicle.Setup;
      Weather  : Weather_Kind := Clear;
      Season   : Season_Kind := Summer;
      No_Records : Boolean := False;   --  a lesson: nothing saved, no ghost
   end record;

   type Sector_Array is array (0 .. 2) of Float;

   type Lap_Info is record
      Lap        : Natural := 0;      --  laps completed
      Lap_Time   : Float := 0.0;      --  running
      Last_Time  : Float := 0.0;
      Best_Time  : Float := 0.0;      --  0: none yet
      Invalid    : Boolean := False;  --  this lap: went off the track
      Sector     : Natural := 0;      --  0 .. 2
      Sector_Times : Sector_Array := (others => 0.0);
      Delta_T    : Float := 0.0;      --  against the best lap
      Has_Delta  : Boolean := False;
      S          : Float := 0.0;
      Last_S     : Float := 0.0;
      Position   : Positive := 1;
      Finished   : Boolean := False;
      Finish_Time : Float := 0.0;
      On_Grid    : Boolean := True;   --  still to cross the line the first time
      Progress   : Float := 0.0;      --  a stage: how far along it, no short cuts
      Resets     : Natural := 0;      --  a stage: times put back on the road
   end record;

   type Ghost_Frame is record
      X, Y, Z, Heading, Pitch, Roll : Float := 0.0;
   end record;
   Ghost_Max : constant := 12_000;     --  20 frames a second: ten minutes
   type Ghost_Array is array (1 .. Ghost_Max) of Ghost_Frame;
   type Ghost_Access is access Ghost_Array;
   type Lap_Array is array (Car_Index) of Lap_Info;
   type Car_Array is array (Car_Index) of Vehicle.Car;

   Cars    : Car_Array;
   Laps    : Lap_Array;
   Car_Count : Natural := 1;
   Config  : Settings;
   Spec    : Vehicle.Spec := Vehicle.Spec_Of (Vehicle.Road_GT);
   Player_Spec : Vehicle.Spec := Vehicle.Spec_Of (Vehicle.Road_GT);
   --  With the driver's setup; the AI's cars run as Spec

   Service_Left : Float := 0.0;   --  in the pit box: seconds until done
   Service_Offer : Boolean := False;  --  in the box, with something to mend

   Time        : Float := 0.0;
   Lights      : Natural := 0;     --  race start: 0 .. 5 red, then out
   Lights_Out  : Boolean := True;
   Race_Over   : Boolean := False;

   Best_Ghost  : Ghost_Access;
   Best_Frames : Natural := 0;

   Lap_Done    : Boolean := False;  --  set when the player finishes a lap
   New_Best    : Boolean := False;

   procedure Start (S : Settings);
   --  Track.Load must be done

   procedure Restart;

   procedure Step (Player : Vehicle.Inputs);
   --  One millisecond

   Reset_Penalty : constant := 15.0;   --  seconds, on a rally stage

   procedure Reset_Player;
   --  Back onto the racing line, stopped (costs the lap; on a stage, time)

   Force_AI : Boolean := False;
   --  (for the tests) the AI drives the player's car, under the player's rules

   function AI_Drives (I : Car_Index) return Boolean;

   function Save_Name return String;
   --  The file holding the best lap of this car at this circuit

   function Ghost_At (Time_In_Lap : Float) return Ghost_Frame;

end Session;
