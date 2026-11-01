--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The car.  A body with weight transfer on four sprung corners, four
--  wheels of their own with combined-slip tyres (load sensitive, with
--  temperature and carcass flex), and a drivetrain from the engine's
--  torque curve through clutch, gearbox and limited slip differential.
--  Stepped at 1 kHz.  Body axes: x forward, y to the right.

with Track;

package Vehicle is

   Dt : constant := 0.001;

   type Car_Kind is (Road_GT, Race_GT3, Rally_4WD);

   function Name (K : Car_Kind) return String;

   type Curve is array (0 .. 9) of Float;   --  N m at 0, 1000 .. 9000 rpm
   type Ratios is array (1 .. 6) of Float;

   type Spec is record
      Mass      : Float;   --  kg
      Inertia   : Float;   --  yaw, kg m^2
      Pitch_I, Roll_I : Float;
      A, B      : Float;   --  centre of gravity to front, rear axle
      Track_F, Track_R : Float;
      H_Cg      : Float;   --  height of the centre of gravity
      K_F, K_R  : Float;   --  springs, N/m at the wheel
      C_F, C_R  : Float;   --  dampers, N s/m
      Arb_F, Arb_R : Float;  --  anti-roll bars, N/m
      Radius    : Float;   --  tyre
      Wheel_I   : Float;   --  kg m^2
      Mu        : Float;   --  peak friction at nominal load
      Load_Sens : Float;
      Slip_X, Slip_Y : Float;  --  slip at the peak
      Rho_Shape : Float;   --  magic formula C
      Rear_Mu, Rear_Stiff : Float;   --  the wider rear tyres: more grip, stiffer
      Loose_Mu  : Float;   --  how much of its grip the tyre keeps on a dirt road
      Wet_Loss  : Float;   --  grip it loses on a wet road
      Snow_Keep : Float;   --  grip it keeps on snow
      Engine    : Curve;
      Engine_I  : Float;
      Idle, Red_Line : Float;
      Gears     : Ratios;
      Final     : Float;
      Reverse_R : Float;
      Lsd_Preload, Lsd_Ramp : Float;
      Front_Share : Float;  --  of the drive to the front axle; 0 rear wheel drive
      Stop_Comp : Float;   --  spring compression where the bump stop starts
      Clutch_Max : Float;  --  N m
      Brake_Max : Float;   --  N m, all four wheels
      Brake_Bias : Float;  --  front share
      Cd_A, Cl_F, Cl_R : Float;  --  drag area, lift areas (downforce)
      Steer_Lock : Float;  --  road wheel angle (rad) at full wheel lock
      Paint_R, Paint_G, Paint_B : Float;
   end record;

   function Spec_Of (K : Car_Kind) return Spec;

   --  What the driver may change.  Factors on the car's own values, 1.0 as it
   --  left the factory, but for the brake balance, added to the front's share.
   type Setup is record
      Spring_F, Spring_R : Float := 1.0;
      Bar_F, Bar_R       : Float := 1.0;
      Brake_Shift        : Float := 0.0;
      Final_Drive        : Float := 1.0;
      Wing               : Float := 1.0;
      Diff               : Float := 1.0;
   end record;

   function Tuned (K : Car_Kind; T : Setup) return Spec;

   Tank : constant := 90.0;           --  kg of fuel it can hold, at most
   Fuel_Reference : constant := 30.0; --  the fuel Spec.Mass already counts

   function Condition_Grip (S : Spec) return Float;
   --  What the weather leaves of this tyre's grip on the road, 0 .. 1

   function Fuel_Per_Km (K : Car_Kind) return Float;
   --  At racing pace, kg

   type Gearbox_Mode is (Paddles, H_Auto_Clutch, H_Clutch, Automatic);

   type Inputs is record
      Steer    : Float := 0.0;   --  -1 .. 1
      Throttle : Float := 0.0;
      Brake    : Float := 0.0;
      Clutch   : Float := 0.0;   --  pedal, 0 released .. 1 down
      Handbrake : Boolean := False;
      Shift_Up, Shift_Down : Boolean := False;  --  one step only
      Lever    : Integer range -1 .. 6 := 0;
      Reverse_Req : Boolean := False;           --  automatic: into reverse
   end record;

   type Assists is record
      Abs_On : Boolean := True;
      Tc_On  : Boolean := True;
      Mode   : Gearbox_Mode := Paddles;
      --  0 is off
      Wear_Rate : Float := 0.0;      --  how fast the tyres go, 1 as in life
      Fuel_Use  : Boolean := False;
      Damage    : Float := 0.0;      --  how much a hit does, 1 as in life
   end record;

   subtype Wheel_Id is Positive range 1 .. 4;   --  FL, FR, RL, RR

   type Wheel_State is record
      Omega  : Float := 0.0;     --  rad/s
      Angle  : Float := 0.0;     --  rotation for the picture
      Ux, Uy : Float := 0.0;     --  tyre deflection (slip state), m
      Fz     : Float := 3000.0;
      Fx, Fy : Float := 0.0;
      Comp   : Float := 0.0;     --  spring compression
      Comp_V : Float := 0.0;
      Ground : Float := 0.0;     --  smoothed by the tyre
      Hint   : Natural := 0;
      Surf   : Track.Surface_Kind := Track.Asphalt;
      Temp   : Float := 72.0;    --  degrees C
      Slide  : Float := 0.0;     --  0 .. 1: how far past the peak
      Abs_Mod : Float := 1.0;
      Mz     : Float := 0.0;     --  aligning torque
      Off_Y  : Float := 0.0;     --  wheel centre over the body origin (picture)
      Bump   : Float := 0.0;     --  what the road did to it this step
      Wear   : Float := 0.0;     --  0 new .. 1 gone
   end record;

   type Wheel_Array is array (Wheel_Id) of Wheel_State;

   type Car is record
      Kind     : Car_Kind := Road_GT;
      X, Z     : Long_Float := 0.0;
      Y        : Float := 0.0;   --  centre of gravity
      Heading  : Float := 0.0;   --  0 north (-Z), + clockwise
      Vx, Vy   : Float := 0.0;   --  body frame, m/s
      Rate     : Float := 0.0;   --  yaw rate
      Vz, Pitch, Pitch_V, Roll, Roll_V : Float := 0.0;
      Steer    : Float := 0.0;   --  road wheel angle
      Wheels   : Wheel_Array;
      Rpm      : Float := 1000.0;
      Omega_E  : Float := 100.0;
      Gear     : Integer range -1 .. 6 := 0;
      Lever_Last : Integer := 99;
      Shift_T  : Float := 0.0;   --  gear change under way, seconds left
      Shift_To : Integer := 0;
      Shift_Blip : Boolean := False;
      Shift_Cool : Float := 0.0;
      Grind    : Boolean := False;
      Clutch_Eng : Float := 0.0;
      Throttle_Eff : Float := 0.0;
      Brake_In : Float := 0.0;
      Tc_Active, Abs_Active : Boolean := False;
      Tc_Cut   : Float := 1.0;
      Hint     : Natural := 0;   --  where along the track the body is
      Ax, Ay   : Float := 0.0;   --  accelerations felt, m/s^2
      Impact   : Float := 0.0;   --  last hit, m/s, decays
      Scrape   : Float := 0.0;   --  rubbing along a barrier
      Rack     : Float := 0.0;   --  steering torque from the tyres, N m
      Road_Feel : Float := 0.0;  --  bumps for the steering
      Fuel     : Float := Fuel_Reference;   --  kg
      Dmg_Aero, Dmg_Engine : Float := 0.0;  --  0 .. 1
      Toe      : Float := 0.0;   --  bent steering, rad: + pulls right
      Hit_X, Hit_Y : Float := 0.0;  --  where on the body it was hit last
      Seen_Impact : Float := 0.0;
   end record;

   procedure Place (C : in out Car; K : Car_Kind; X, Z, Heading : Float);
   --  Standing still and settled on the ground

   procedure Step (C : in out Car; S : Spec; I : Inputs; A : Assists);
   --  One millisecond

   function Speed (C : Car) return Float;
   --  Over the ground, m/s

   procedure Forward (Heading : Float; FX, FZ : out Float) with Inline;
   procedure Collide (A, B : in out Car; Spec_A, Spec_B : Spec);
   --  Two cars touching

end Vehicle;
