--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Draws one frame: shadows, the scene in high dynamic range with
--  multisampling, the mirror, tone mapping.  (The panels are in Hud.)

with Sim_Loop;

package Renderer is

   type Camera_Kind is (Cockpit, Hood, Chase, Chase_Far, Trackside);

   type Time_Of_Day is (Morning, Noon, Golden_Hour, Overcast, Dawn, Dusk, Night);

   type View_Options is record
      Camera   : Camera_Kind := Cockpit;
      Fov      : Float := 55.0;     --  degrees, vertical
      Look     : Float := 0.0;      --  radians, sideways from the cockpit
      Orbit    : Float := 0.0;      --  radians round the car, the chase camera (videos)
      Mirror   : Boolean := True;
      Day      : Time_Of_Day := Noon;
      Ghost    : Boolean := True;
      Guide    : Boolean := False;  --  the driving line on the road
      Cabin    : Boolean := False;
      Dt       : Float := 0.016;
   end record;

   procedure Create;
   --  (GL context current) programs and framebuffers

   procedure New_Track;
   --  After the scenery was rebuilt

   function Pose_Between (A, B : Sim_Loop.Frame; I : Positive; T : Float) return Sim_Loop.Car_Pose;
   --  In-between pose for a car; T beyond 1 runs on a little

   procedure Draw (A, B : Sim_Loop.Frame; Options : View_Options; Width, Height : Natural;
                   Focus : Positive := 1; Y0 : Natural := 0);
   --  The view from car Focus, into the window from line Y0 up (two players:
   --  each a half)
   --  Scene into the frame buffer that GTK has bound

   function Listener_Inside (Options : View_Options) return Boolean;

   procedure Hearing (Pose : Sim_Loop.Car_Pose; Level, Pan : out Float);
   --  How another car sounds from the camera

end Renderer;
