--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The real-time loop: a task of its own that reads the wheel, steps the
--  physics at 1 kHz and sends the force feedback at 125 Hz, whatever the
--  graphics are doing.  The screen reads finished frames from here.

with School;
with Session;
with Vehicle;
with Wheel;

package Sim_Loop is

   type Float4 is array (Vehicle.Wheel_Id) of Float;

   type Car_Pose is record
      X, Y, Z, Heading, Pitch, Roll : Float := 0.0;
      Steer : Float := 0.0;
      Wheel_Y, Wheel_Angle, Slide : Float4 := (others => 0.0);
      Brake : Float := 0.0;
      Speed : Float := 0.0;
      Rpm   : Float := 0.0;
      Gear  : Integer := 0;
      Fallen, Rider_Gap : Float := 0.0;   --  a motorcycle down, its rider behind it
   end record;

   type Pose_Array is array (Session.Car_Index) of Car_Pose;

   type Frame is record
      Time     : Long_Float := 0.0;   --  seconds of real time
      Poses    : Pose_Array;
      Count    : Natural := 1;
      --  The player's car
      Speed, Rpm, Throttle, Brake, Clutch, Steer_In : Float := 0.0;
      Ax, Ay   : Float := 0.0;
      Gear     : Integer := 0;
      Temps    : Float4 := (others => 0.0);
      Slides   : Float4 := (others => 0.0);
      On_Kerb, Off_Road, On_Dirt : Boolean := False;
      Abs_On, Tc_On, Grind : Boolean := False;
      Impact, Scrape : Float := 0.0;
      Load     : Float := 0.0;
      Laps     : Session.Lap_Array;
      Lights   : Natural := 0;
      Lights_Out, Race_Over : Boolean := True;
      Ghost    : Session.Ghost_Frame;
      Red_Line : Float := 7000.0;
      New_Best : Boolean := False;
      Wear     : Float4 := (others => 0.0);
      Fuel     : Float := 0.0;
      Uses_Fuel : Boolean := False;
      Dmg_Aero, Dmg_Engine, Toe : Float := 0.0;
      Service_Left : Float := 0.0;
      Service_Offer : Boolean := False;
      In_Pit_Lane : Boolean := False;
      Waiting_For_Peer : Boolean := False;
      Yellow_Ahead : Boolean := False;
      VSC_Left : Float := 0.0;
      Penalty : Float := 0.0;
      School   : Standard.School.Status;
      Tip      : String (1 .. Standard.School.Tip_Size) := (others => ' ');
      Tip_Len  : Natural := 0;
      Tip_Serial : Natural := 0;
   end record;

   type Keys is record
      Left, Right, Throttle, Brake, Handbrake, Clutch : Boolean := False;
      --  The second player's, in a race of two
      Left_2, Right_2, Throttle_2, Brake_2 : Boolean := False;
   end record;

   procedure Set_Keys (K : Keys);

   procedure Request_Shift (Up : Boolean);
   procedure Request_Reverse (On : Boolean);

   procedure Boot (Use_Wheel : Boolean);
   --  Start the task and look for a wheel

   procedure Halt;
   --  Stop stepping; on return Track and Session may be changed.  The
   --  wheel keeps a centring spring.

   procedure Resume;

   procedure Pause (On : Boolean);
   function Paused return Boolean;
   procedure Restart;
   procedure Reset_Car;

   procedure Set_FFB (Gain : Float);

   procedure Shutdown;
   --  Stop the task, take the force off the wheel

   procedure Latest (Prev, Cur : out Frame);

   function Now return Long_Float;

   function Wheel_Present return Boolean;

   function Next_Button (B : out Wheel.Button) return Boolean;
   --  A wheel button pressed since asked last

   function Pad_Steer return Float;
   --  The wheel's position, for the menu

   function Physics_Load return Float;
   --  Share of the real-time budget the physics use, 0 .. 1

end Sim_Loop;
