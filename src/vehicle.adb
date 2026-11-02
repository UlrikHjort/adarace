--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

package body Vehicle is

   use Ada.Numerics.Elementary_Functions;
   use Track;

   Pi : constant := 3.14159_26535;
   G  : constant := 9.81;
   Air : constant := 1.2;
   Fz_Nominal : constant := 3500.0;
   Relax_Len_X : constant := 0.25;
   Relax_Len_Y : constant := 0.45;
   Wear_Per_Joule : constant := 5.5E-8;

   function Clamp (V, Lo, Hi : Float) return Float is
     (Float'Max (Lo, Float'Min (Hi, V))) with Inline;

   function Name (K : Car_Kind) return String is
     (case K is
         when Road_GT  => "Nordic GT 420 (road)",
         when Race_GT3 => "Nordic GT3 (slicks, wings)",
         when Rally_4WD => "Nordic R4 (rally, four wheel drive)",
         when Classic_RWD => "Nordic 1600 (light classic, rear drive)",
         when Hyper_AWD => "Nordic Hyper (mid-engined, 540 kW)",
         when Sport_Bike => "Nordic 1000 R (motorcycle)");

   function Spec_Of (K : Car_Kind) return Spec is
     (case K is
         when Road_GT =>
           (Mass => 1480.0, Inertia => 2650.0, Pitch_I => 2400.0, Roll_I => 620.0,
            A => 1.30, B => 1.34, Track_F => 1.58, Track_R => 1.60, H_Cg => 0.48,
            K_F => 44_000.0, K_R => 50_000.0, C_F => 3_700.0, C_R => 3_800.0,
            Arb_F => 26_000.0, Arb_R => 15_000.0,
            Radius => 0.335, Wheel_I => 1.25,
            Mu => 1.12, Load_Sens => 0.09, Slip_X => 0.11, Slip_Y => 0.135, Rho_Shape => 1.30, Rear_Mu => 1.12, Rear_Stiff => 1.4, Loose_Mu => 0.58, Wet_Loss => 0.26, Snow_Keep => 0.48,
            Engine => (150.0, 300.0, 400.0, 460.0, 500.0, 520.0, 500.0, 450.0, 330.0, 150.0),
            Rpm_Step => 1000.0, Engine_I => 0.22, Idle => 900.0, Red_Line => 7400.0,
            Gears => (3.6, 2.3, 1.68, 1.3, 1.05, 0.86), Final => 3.42, Reverse_R => 3.4,
            Lsd_Preload => 60.0, Lsd_Ramp => 0.3, Front_Share => 0.0, Stop_Comp => 0.11,
            Clutch_Max => 800.0, Brake_Max => 7200.0, Brake_Bias => 0.64,
            Cd_A => 0.72, Cl_F => 0.06, Cl_R => 0.10,
            Steer_Lock => 0.58,
            Paint_R => 0.72, Paint_G => 0.03, Paint_B => 0.04),
         when Race_GT3 =>
           (Mass => 1300.0, Inertia => 2240.0, Pitch_I => 2100.0, Roll_I => 520.0,
            A => 1.36, B => 1.28, Track_F => 1.67, Track_R => 1.66, H_Cg => 0.42,
            K_F => 110_000.0, K_R => 125_000.0, C_F => 6_500.0, C_R => 6_500.0,
            Arb_F => 50_000.0, Arb_R => 34_000.0,
            Radius => 0.345, Wheel_I => 1.4,
            Mu => 1.52, Load_Sens => 0.12, Slip_X => 0.085, Slip_Y => 0.105, Rho_Shape => 1.30, Rear_Mu => 1.12, Rear_Stiff => 1.4, Loose_Mu => 0.42, Wet_Loss => 0.46, Snow_Keep => 0.30,
            Engine => (180.0, 340.0, 470.0, 540.0, 590.0, 620.0, 630.0, 610.0, 540.0, 300.0),
            Rpm_Step => 1000.0, Engine_I => 0.16, Idle => 1200.0, Red_Line => 8000.0,
            Gears => (3.1, 2.25, 1.8, 1.48, 1.25, 1.06), Final => 3.1, Reverse_R => 3.1,
            Lsd_Preload => 100.0, Lsd_Ramp => 0.45, Front_Share => 0.0, Stop_Comp => 0.11,
            Clutch_Max => 1200.0, Brake_Max => 9000.0, Brake_Bias => 0.6,
            Cd_A => 0.95, Cl_F => 0.75, Cl_R => 1.15,
            Steer_Lock => 0.48,
            Paint_R => 0.03, Paint_G => 0.18, Paint_B => 0.62),
         when Rally_4WD =>
           (Mass => 1290.0, Inertia => 1950.0, Pitch_I => 1900.0, Roll_I => 520.0,
            A => 1.24, B => 1.30, Track_F => 1.54, Track_R => 1.54, H_Cg => 0.54,
            K_F => 30_000.0, K_R => 30_000.0, C_F => 3_000.0, C_R => 3_000.0,
            Arb_F => 9_000.0, Arb_R => 7_000.0,
            Radius => 0.335, Wheel_I => 1.2,
            Mu => 1.02, Load_Sens => 0.07, Slip_X => 0.12, Slip_Y => 0.15, Rho_Shape => 1.28,
            Rear_Mu => 1.03, Rear_Stiff => 1.25, Loose_Mu => 0.74, Wet_Loss => 0.28, Snow_Keep => 0.72,
            Engine => (140.0, 280.0, 420.0, 500.0, 540.0, 520.0, 480.0, 400.0, 260.0, 100.0),
            Rpm_Step => 1000.0, Engine_I => 0.18, Idle => 1000.0, Red_Line => 7400.0,
            Gears => (3.1, 2.2, 1.72, 1.38, 1.14, 0.96), Final => 4.1, Reverse_R => 3.3,
            Lsd_Preload => 80.0, Lsd_Ramp => 0.4, Front_Share => 0.45, Stop_Comp => 0.27,
            Clutch_Max => 900.0, Brake_Max => 6200.0, Brake_Bias => 0.58,
            Cd_A => 0.78, Cl_F => 0.08, Cl_R => 0.14,
            Steer_Lock => 0.64,
            Paint_R => 0.74, Paint_G => 0.76, Paint_B => 0.80),
         when Classic_RWD =>
           (Mass => 1080.0, Inertia => 1800.0, Pitch_I => 1500.0, Roll_I => 420.0,
            A => 1.18, B => 1.22, Track_F => 1.42, Track_R => 1.42, H_Cg => 0.46,
            K_F => 28_000.0, K_R => 28_000.0, C_F => 2_200.0, C_R => 2_300.0,
            Arb_F => 12_000.0, Arb_R => 8_000.0,
            Radius => 0.31, Wheel_I => 1.0,
            Mu => 0.98, Load_Sens => 0.06, Slip_X => 0.13, Slip_Y => 0.16, Rho_Shape => 1.25,
            Rear_Mu => 1.08, Rear_Stiff => 1.45, Loose_Mu => 0.62, Wet_Loss => 0.24, Snow_Keep => 0.50,
            Engine => (100.0, 190.0, 240.0, 265.0, 275.0, 270.0, 250.0, 210.0, 130.0, 60.0),
            Rpm_Step => 1000.0, Engine_I => 0.16, Idle => 850.0, Red_Line => 6800.0,
            Gears => (3.3, 2.1, 1.5, 1.18, 0.96, 0.82), Final => 3.7, Reverse_R => 3.2,
            Lsd_Preload => 30.0, Lsd_Ramp => 0.2, Front_Share => 0.0, Stop_Comp => 0.16,
            Clutch_Max => 500.0, Brake_Max => 5800.0, Brake_Bias => 0.62,
            Cd_A => 0.68, Cl_F => 0.02, Cl_R => 0.03,
            Steer_Lock => 0.55,
            Paint_R => 0.03, Paint_G => 0.20, Paint_B => 0.11),
         when Hyper_AWD =>
           (Mass => 1320.0, Inertia => 2100.0, Pitch_I => 2100.0, Roll_I => 540.0,
            A => 1.42, B => 1.26, Track_F => 1.70, Track_R => 1.68, H_Cg => 0.40,
            K_F => 120_000.0, K_R => 135_000.0, C_F => 7_000.0, C_R => 7_000.0,
            Arb_F => 55_000.0, Arb_R => 40_000.0,
            Radius => 0.35, Wheel_I => 1.5,
            Mu => 1.30, Load_Sens => 0.11, Slip_X => 0.09, Slip_Y => 0.11, Rho_Shape => 1.30,
            Rear_Mu => 1.10, Rear_Stiff => 1.35, Loose_Mu => 0.50, Wet_Loss => 0.34, Snow_Keep => 0.38,
            Engine => (200.0, 380.0, 520.0, 620.0, 680.0, 720.0, 740.0, 740.0, 680.0, 400.0),
            Rpm_Step => 1000.0, Engine_I => 0.15, Idle => 1100.0, Red_Line => 8500.0,
            Gears => (3.0, 2.2, 1.72, 1.4, 1.18, 1.0), Final => 3.2, Reverse_R => 3.0,
            Lsd_Preload => 100.0, Lsd_Ramp => 0.4, Front_Share => 0.3, Stop_Comp => 0.10,
            Clutch_Max => 1300.0, Brake_Max => 9500.0, Brake_Bias => 0.60,
            Cd_A => 0.82, Cl_F => 0.55, Cl_R => 0.80,
            Steer_Lock => 0.50,
            Paint_R => 0.74, Paint_G => 0.58, Paint_B => 0.04),
         when Sport_Bike =>
           --  A litre sports bike with its rider: wheelbase 1.40 m, a high
           --  centre of gravity, 150 kW at 12 000 rpm
           (Mass => 275.0, Inertia => 120.0, Pitch_I => 150.0, Roll_I => 40.0,
            A => 0.70, B => 0.70, Track_F => 0.0, Track_R => 0.0, H_Cg => 0.62,
            K_F => 30_000.0, K_R => 40_000.0, C_F => 2_000.0, C_R => 2_000.0,
            Arb_F => 0.0, Arb_R => 0.0,
            Radius => 0.31, Wheel_I => 0.6,
            Mu => 1.18, Load_Sens => 0.05, Slip_X => 0.10, Slip_Y => 0.12, Rho_Shape => 1.3,
            Rear_Mu => 1.0, Rear_Stiff => 1.0, Loose_Mu => 0.55, Wet_Loss => 0.30, Snow_Keep => 0.40,
            Engine => (20.0, 45.0, 62.0, 75.0, 88.0, 100.0, 110.0, 115.0, 112.0, 95.0),
            Rpm_Step => 1450.0, Engine_I => 0.05, Idle => 1300.0, Red_Line => 13000.0,
            Gears => (2.6, 2.0, 1.65, 1.42, 1.28, 1.16), Final => 3.9, Reverse_R => 2.6,
            Lsd_Preload => 0.0, Lsd_Ramp => 0.0, Front_Share => 0.0, Stop_Comp => 0.12,
            Clutch_Max => 400.0, Brake_Max => 3000.0, Brake_Bias => 0.75,
            Cd_A => 0.32, Cl_F => 0.0, Cl_R => 0.0,
            Steer_Lock => 0.55,
            Paint_R => 0.70, Paint_G => 0.04, Paint_B => 0.05));

   function Tuned (K : Car_Kind; T : Setup) return Spec is
      S : Spec := Spec_Of (K);
      Wing : constant Float := Clamp (T.Wing, 0.0, 2.0);
   begin
      S.C_F := S.C_F * Sqrt (T.Spring_F);
      S.C_R := S.C_R * Sqrt (T.Spring_R);
      S.K_F := S.K_F * T.Spring_F;
      S.K_R := S.K_R * T.Spring_R;
      S.Arb_F := S.Arb_F * T.Bar_F;
      S.Arb_R := S.Arb_R * T.Bar_R;
      S.Brake_Bias := Clamp (S.Brake_Bias + T.Brake_Shift, 0.4, 0.85);
      S.Final := S.Final * T.Final_Drive;
      --  Downforce costs drag: a quarter as much, about what a wing does
      S.Cd_A := S.Cd_A * (1.0 + 0.25 * (Wing - 1.0) * (S.Cl_F + S.Cl_R) / S.Cd_A);
      S.Cl_F := S.Cl_F * Wing;
      S.Cl_R := S.Cl_R * Wing;
      S.Lsd_Ramp := S.Lsd_Ramp * T.Diff;
      return S;
   end Tuned;

   function Condition_Grip (S : Spec) return Float is
     (if Track.Is_Stage
      then (1.0 - Track.Wet * S.Wet_Loss * 0.6) * (1.0 - Track.Snow * (1.0 - S.Snow_Keep))
      else (1.0 - Track.Wet * S.Wet_Loss) * (1.0 - Track.Snow * (1.0 - (0.35 + 0.6 * S.Snow_Keep))));

   function Fuel_Per_Km (K : Car_Kind) return Float is
     (case K is when Road_GT => 0.27, when Race_GT3 => 0.33, when Rally_4WD => 0.27, when Classic_RWD => 0.16, when Hyper_AWD => 0.39, when Sport_Bike => 0.085);

   function Speed (C : Car) return Float is
     (Sqrt (C.Vx * C.Vx + C.Vy * C.Vy));

   procedure Forward (Heading : Float; FX, FZ : out Float) is
   begin
      FX := Sin (Heading);
      FZ := -Cos (Heading);
   end Forward;

   --  Where each wheel is on the body
   procedure Wheel_Pos (S : Spec; W : Wheel_Id; X_B, Y_B : out Float) is
   begin
      case W is
         when 1 => X_B := S.A;  Y_B := -S.Track_F / 2.0;
         when 2 => X_B := S.A;  Y_B := S.Track_F / 2.0;
         when 3 => X_B := -S.B; Y_B := -S.Track_R / 2.0;
         when 4 => X_B := -S.B; Y_B := S.Track_R / 2.0;
      end case;
   end Wheel_Pos;

   --  Spring compression standing still, keeping the body level
   function Static_Comp (S : Spec; W : Wheel_Id) return Float is
      L : constant Float := S.A + S.B;
   begin
      return (if W <= 2
              then S.Mass * G * S.B / L / 2.0 / S.K_F
              else S.Mass * G * S.A / L / 2.0 / S.K_R);
   end Static_Comp;

   function Engine_Torque (S : Spec; Rpm : Float) return Float is
      R : constant Float := Clamp (Rpm / S.Rpm_Step, 0.0, 8.999);
      I : constant Integer := Integer (Float'Floor (R));
      T : constant Float := R - Float (I);
   begin
      return S.Engine (I) + (S.Engine (I + 1) - S.Engine (I)) * T;
   end Engine_Torque;

   function Ratio (S : Spec; Gear : Integer) return Float is
     (case Gear is
         when -1 => -S.Reverse_R * S.Final,
         when 0  => 0.0,
         when others => S.Gears (Gear) * S.Final);

   procedure Place (C : in out Car; K : Car_Kind; X, Z, Heading : Float) is
      S : constant Spec := Spec_Of (K);
      Keep_Hint : constant Natural := Track.Find_Nearest (X, Z);
   begin
      C := (Kind => K, X => Long_Float (X), Z => Long_Float (Z), Heading => Heading,
            Hint => Keep_Hint, Rpm => S.Idle, Omega_E => S.Idle * 2.0 * Pi / 60.0,
            others => <>);
      declare
         Sum : Float := 0.0;
         FX, FZ : Float;
      begin
         Forward (Heading, FX, FZ);
         for W in Wheel_Id loop
            declare
               XB, YB : Float;
               Con : Track.Contact;
            begin
               Wheel_Pos (S, W, XB, YB);
               C.Wheels (W).Hint := Keep_Hint;
               Track.Query (X + FX * XB - FZ * YB, Z + FZ * XB + FX * YB, C.Wheels (W).Hint, Con);
               C.Wheels (W).Ground := Con.Y;
               C.Wheels (W).Comp := Static_Comp (S, W);
               Sum := Sum + Con.Y;
            end;
         end loop;
         C.Y := Sum / 4.0 + S.H_Cg;
         C.Pitch := Arctan ((C.Wheels (1).Ground + C.Wheels (2).Ground
                             - C.Wheels (3).Ground - C.Wheels (4).Ground) / (2.0 * (S.A + S.B)));
         C.Roll := (if Is_Bike (K) then 0.0
                    else Arctan ((C.Wheels (2).Ground + C.Wheels (4).Ground
                                  - C.Wheels (1).Ground - C.Wheels (3).Ground)
                                 / (S.Track_F + S.Track_R)));
      end;
   end Place;

   ---------------------------------------------------------------------------
   --  Tyre: the slip state gives the force by a magic formula on the
   --  combined slip, the whole limited by the friction circle
   ---------------------------------------------------------------------------

   --  On loose ground the tyre ploughs: its peak comes at far more slip and
   --  there is hardly any drop past it, so a slide can be held
   function Slip_Scale (Surf : Surface_Kind) return Float is
     (case Surf is
         when Asphalt | Kerb => 1.0,
         when Grass => 1.6,
         when Gravel => 1.9,
         when Dirt => 2.3);

   procedure Tyre_Force
     (W : in out Wheel_State; S : Spec; Rear : Boolean; V_Long, V_Lat : Float;
      Fx, Fy : out Float)
   is
      Vsx : constant Float := W.Omega * S.Radius - V_Long;
      Abs_V : constant Float := abs V_Long;
      --  The carcass follows the slip over a relaxation length; while it
      --  slides fast the state must not wind up
      Vr_X : constant Float := Abs_V + 0.5 * abs Vsx;
      Vr_Y : constant Float := Abs_V + 0.3 * abs V_Lat + 0.3 * abs (W.Omega * S.Radius);
   begin
      W.Ux := (W.Ux + Dt * Vsx) / (1.0 + Dt * Vr_X / Relax_Len_X);
      W.Uy := (W.Uy - Dt * V_Lat) / (1.0 + Dt * Vr_Y / Relax_Len_Y);
      declare
         Limit_X : constant Float := 1.2 * Relax_Len_X * Slip_Scale (W.Surf);
         Limit_Y : constant Float := 1.2 * Relax_Len_Y * Slip_Scale (W.Surf);
      begin
         W.Ux := Clamp (W.Ux, -Limit_X, Limit_X);
         W.Uy := Clamp (W.Uy, -Limit_Y, Limit_Y);
      end;
      declare
         Loose : constant Float := Slip_Scale (W.Surf);
         Shape : constant Float :=
           (case W.Surf is
               when Asphalt | Kerb => S.Rho_Shape,
               when Grass | Gravel => 1.18,
               when Dirt => 1.10);
         Sx  : constant Float := W.Ux / Relax_Len_X / S.Slip_X / Loose;
         Sy  : constant Float :=
           W.Uy / Relax_Len_Y / S.Slip_Y / Loose * (if Rear then S.Rear_Stiff else 1.0);
         Rho : constant Float := Sqrt (Sx * Sx + Sy * Sy) + 1.0E-6;
         B   : constant Float := Tan (Pi / (2.0 * Shape));
         F   : constant Float := Sin (Shape * Arctan (B * Rho));
         Weather_Mu : constant Float :=
           (1.0 - Track.Wet * (case W.Surf is
                                  when Asphalt | Kerb => S.Wet_Loss,
                                  when Dirt => S.Wet_Loss * 0.6,
                                  when Grass => 0.25,
                                  when Gravel => 0.1))
           * (1.0 - Track.Snow * (1.0 - (case W.Surf is
                                            when Asphalt | Kerb => 0.35 + 0.6 * S.Snow_Keep,
                                            when Dirt => S.Snow_Keep,
                                            when Grass | Gravel => 0.75)));
         Surface_Mu : constant Float := Weather_Mu *
           (case W.Surf is
               when Asphalt => 1.0,
               when Kerb    => 0.93,
               when Grass   => 0.48,
               when Gravel  => 0.42,
               when Dirt    => S.Loose_Mu);
         Load_Mu : constant Float :=
           Clamp (1.0 - S.Load_Sens * (W.Fz / Fz_Nominal - 1.0), 0.65, 1.2);
         Heat_Mu : constant Float :=
           Clamp (1.0 - ((W.Temp - 85.0) / 170.0) ** 2, 0.88, 1.0);
         Mu : constant Float :=
           S.Mu * Surface_Mu * Load_Mu * Heat_Mu * (if Rear then S.Rear_Mu else 1.0)
           * (1.0 - 0.25 * W.Wear ** 1.5);
         Peak : constant Float := Mu * W.Fz;
         --  At walking pace the slip state is a stiff spring: damp it
         Slow : constant Float := Clamp (1.0 - Abs_V / 4.0, 0.0, 1.0);
         Damp : constant Float := 3.0 * Slow * W.Fz / Fz_Nominal * 1000.0;
      begin
         Fx := Peak * F * Sx / Rho + Damp * Vsx;
         Fy := Peak * F * Sy / Rho - Damp * V_Lat;
         declare
            Total : constant Float := Sqrt (Fx * Fx + Fy * Fy);
         begin
            if Total > Peak * 1.02 and then Total > 0.0 then
               Fx := Fx * Peak * 1.02 / Total;
               Fy := Fy * Peak * 1.02 / Total;
            end if;
         end;
         W.Slide := Clamp (Rho - 1.0, 0.0, 1.5) / 1.5;
         --  Pneumatic trail: the force acts behind the contact centre, and
         --  falls away near the limit: the steering goes light.  The caster's
         --  mechanical trail stays, so a sliding car still pulls the wheel
         --  towards the countersteer.
         declare
            Trail : constant Float :=
              0.010 + 0.030 * Float'Max (0.0, 1.0 - Rho * 0.95);
         begin
            W.Mz := -Fy * Trail;
         end;
         --  Heating from the sliding, cooling by the air
         declare
            Slip_Power : constant Float :=
              (abs (Fx * Vsx) + abs (Fy * V_Lat)) * (if W.Surf = Dirt then 0.2 else 1.0);
            Cool : constant Float := 0.012 + 0.0007 * Abs_V;
         begin
            W.Temp := W.Temp + Dt * (Slip_Power * 2.0E-4 - Cool * (W.Temp - 28.0));
         end;
      end;
   end Tyre_Force;

   ---------------------------------------------------------------------------
   --  Gearbox
   ---------------------------------------------------------------------------

   procedure Gear_Logic (C : in out Car; S : Spec; I : Inputs; A : Assists) is
      Shaft_Rpm : constant Float :=
        abs ((C.Wheels (3).Omega + C.Wheels (4).Omega) * 0.5) * 60.0 / (2.0 * Pi);

      procedure Request (To : Integer) is
      begin
         if To = C.Gear or else C.Shift_T > 0.0 then
            return;
         end if;
         --  No money shifts: refuse a change down that would over-rev
         if To > 0 and then To < C.Gear
           and then Shaft_Rpm * abs (Ratio (S, To)) > S.Red_Line + 500.0
         then
            return;
         end if;
         C.Shift_To := To;
         C.Shift_T := 0.09;
         C.Shift_Blip := To > 0 and then To < C.Gear;
      end Request;
   begin
      C.Shift_Cool := Float'Max (0.0, C.Shift_Cool - Dt);
      case A.Mode is
         when Paddles =>
            if I.Shift_Up and then C.Gear < 6 then
               Request (C.Gear + 1);
            elsif I.Shift_Down and then C.Gear > -1 then
               --  Only into reverse when nearly stopped
               if C.Gear > 0 or else abs C.Vx < 1.5 then
                  Request (C.Gear - 1);
               end if;
            end if;
         when H_Auto_Clutch =>
            if I.Lever /= C.Lever_Last then
               Request (I.Lever);
               C.Lever_Last := I.Lever;
            end if;
         when H_Clutch =>
            C.Grind := False;
            if I.Lever /= C.Gear then
               if I.Lever = 0 then
                  C.Gear := 0;
               elsif I.Clutch > 0.55 then
                  C.Gear := I.Lever;
               else
                  C.Grind := True;
                  C.Gear := 0;
               end if;
            end if;
         when Automatic =>
            if I.Reverse_Req and then abs C.Vx < 1.5 then
               C.Gear := -1;
            elsif C.Gear <= 0 and then I.Throttle > 0.02 and then not I.Reverse_Req
              and then C.Vx > -1.5
            then
               C.Gear := 1;
            elsif C.Gear >= 1 and then C.Shift_T = 0.0 and then C.Shift_Cool = 0.0 then
               declare
                  Up_At : constant Float := S.Idle + (S.Red_Line - 300.0 - S.Idle)
                    * Clamp (0.35 + I.Throttle * 0.9, 0.0, 1.0);
                  --  (in a car's revs; a motorcycle's spin higher, and want to)
                  Rev : constant Float := (if Is_Bike (C.Kind) then 2.2 else 1.0);
                  Down_At : constant Float := S.Idle + (700.0
                    + 2200.0 * I.Throttle + 1200.0 * I.Brake) * Rev;
               begin
                  --  (with the traction control busy: up early, for less torque at the wheels)
                  if C.Gear < 6 and then C.Clutch_Eng > 0.9
                    and then (C.Rpm > Up_At or else (C.Tc_Active and then not Is_Bike (C.Kind) and then C.Rpm > S.Idle + 2800.0))
                  then
                     Request (C.Gear + 1);
                     C.Shift_Cool := 0.4;
                  elsif C.Gear > 1 and then C.Rpm < Down_At then
                     Request (C.Gear - 1);
                     C.Shift_Cool := 0.4;
                  end if;
               end;
            end if;
      end case;
      if C.Shift_T > 0.0 then
         declare
            Before : constant Float := C.Shift_T;
         begin
            C.Shift_T := Float'Max (0.0, C.Shift_T - Dt);
            if Before > 0.045 and then C.Shift_T <= 0.045 then
               C.Gear := C.Shift_To;
            end if;
         end;
      end if;
   end Gear_Logic;

   ---------------------------------------------------------------------------
   --  One step
   ---------------------------------------------------------------------------

   procedure Walls (C : in out Car; S : Spec);

   Bike_Slip : constant := 0.05;

   function Lean_Limit (S : Spec) return Float is
     (Arctan (S.Mu * 0.95));

   ---------------------------------------------------------------------------
   --  A motorcycle: one track, steered by leaning
   ---------------------------------------------------------------------------

   procedure Bike_Step (C : in out Car; S : Spec; I : Inputs; A : Assists) is
      G_Acc : constant := 9.81;
      L : constant Float := S.A + S.B;
      V : constant Float := Float'Max (0.0, C.Vx);
      FX : constant Float := Sin (C.Heading);
      FZ : constant Float := -Cos (C.Heading);
      RX : constant Float := Cos (C.Heading);
      RZ : constant Float := Sin (C.Heading);
      Front, Rear : Track.Contact;
      Grip_F, Grip_R : Float;
      Ground_Pitch : Float;   --  the slope of the road under the bike

      function Surface_Grip (Surf : Surface_Kind) return Float is
        ((case Surf is
            when Asphalt | Kerb => 1.0, when Dirt => S.Loose_Mu,
            when Grass => 0.5, when Gravel => 0.42)
         * (1.0 - Track.Wet * S.Wet_Loss) * (1.0 - Track.Snow * (1.0 - S.Snow_Keep)));
   begin
      --  The ground under each wheel
      declare
         --  (a positive roll tips the top to the left: the tyres are to the right)
         Contact_X : constant Float := Float (C.X) + RX * S.H_Cg * Sin (C.Roll);
         Contact_Z : constant Float := Float (C.Z) + RZ * S.H_Cg * Sin (C.Roll);
      begin
         Track.Query (Contact_X + FX * S.A, Contact_Z + FZ * S.A, C.Wheels (1).Hint, Front);
         Track.Query (Contact_X - FX * S.B, Contact_Z - FZ * S.B, C.Wheels (3).Hint, Rear);
      end;
      for W in Wheel_Id loop
         C.Wheels (W).Surf := (if W <= 2 then Front.Surf else Rear.Surf);
         C.Wheels (W).Off_Y := S.Radius;
      end loop;
      Ground_Pitch := Arctan ((Front.Y - Rear.Y) / L);
      Grip_F := S.Mu * Surface_Grip (Front.Surf);
      Grip_R := S.Mu * Surface_Grip (Rear.Surf);

      --  Down: it slides along on its side until it stops
      if C.Fallen_T > 0.0 then
         C.Fallen_T := C.Fallen_T + Dt;
         C.Vx := Float'Max (0.0, C.Vx - Dt * 0.55 * G_Acc);
         C.Vy := C.Vy * (1.0 - Dt * 3.0);
         C.Rate := C.Rate * (1.0 - Dt * 2.0);
         C.Roll := C.Roll + (Float'Copy_Sign (1.35, C.Roll) - C.Roll) * Dt * 6.0;
         C.Throttle_Eff := 0.0;
         C.Rpm := Float'Max (S.Idle, C.Rpm - Dt * 4000.0);
         for W in Wheel_Id loop
            C.Wheels (W).Slide := (if C.Vx > 1.0 then 1.0 else 0.0);
         end loop;
      else
         declare
            --  Where the rider means to go, as with a car: a curvature
            Kappa : constant Float := Tan (Clamp (I.Steer, -1.0, 1.0) * S.Steer_Lock * 0.5) / L;
            Limit : constant Float := Lean_Limit (S) * Clamp (Float'Min (Grip_F, Grip_R) / S.Mu, 0.3, 1.0);
            Want : constant Float := Clamp (Arctan (V * V * Kappa / G_Acc), -Limit, Limit);
            Lean_Rate : constant Float := 0.6 + 1.6 * Clamp (V / 20.0, 0.0, 1.0);
            Low_Speed : constant Float := Clamp ((V - 2.0) / 5.0, 0.0, 1.0);
            Pedal : constant Float := Clamp (I.Brake, 0.0, 1.0);
            Rear_Pedal : constant Float := (if I.Handbrake then 1.0 else 0.0);
            Throttle : Float := Clamp (I.Throttle, 0.0, 1.0);
            Ratio_Now : constant Float := Ratio (S, Integer'Max (1, C.Gear));
            Wheel_Rpm : constant Float := V / S.Radius * 60.0 / (2.0 * Pi);
            Load_F, Load_R : Float;
            Drive, Brake_F, Brake_R, Drag : Float;
            Ax_Want, Ay, Used : Float;
         begin
            --  Leaning into what the corner needs, as fast as the bike can roll
            --  (into a right hand turn the top goes right: a negative roll)
            C.Roll := C.Roll + Clamp (-Want * Low_Speed - C.Roll, -Lean_Rate * Dt, Lean_Rate * Dt);

            --  Gears: the car's logic, on the rear wheel's speed
            C.Wheels (3).Omega := V / S.Radius;
            C.Wheels (4).Omega := C.Wheels (3).Omega;
            C.Wheels (1).Omega := C.Wheels (3).Omega;
            C.Wheels (2).Omega := C.Wheels (3).Omega;
            C.Clutch_Eng := 1.0;
            Gear_Logic (C, S, I, A);
            if C.Gear = 0 and then A.Mode /= H_Clutch and then Throttle > 0.05 then
               C.Gear := 1;
            end if;

            --  The engine: a slipping clutch below the gear's speed
            C.Rpm := Float'Max (Wheel_Rpm * Ratio_Now, S.Idle + Throttle * 5000.0 * (1.0 - Clamp (V / 6.0, 0.0, 1.0)));
            if C.Gear <= 0 then
               C.Rpm := S.Idle + Throttle * (S.Red_Line - S.Idle);
            end if;
            C.Rpm := Float'Min (C.Rpm, S.Red_Line + 200.0);
            if C.Rpm >= S.Red_Line or else C.Shift_T > 0.0
              or else (A.Fuel_Use and then C.Fuel <= 0.0)
            then
               Throttle := 0.0;
            end if;
            C.Omega_E := C.Rpm * 2.0 * Pi / 60.0;
            --  About 290 g for each kWh made, as in a car
            if A.Fuel_Use and then C.Gear /= 0 then
               C.Fuel := Float'Max
                 (0.0, C.Fuel - Dt * Throttle * Engine_Torque (S, C.Rpm) * C.Omega_E * 8.0E-8);
            end if;

            --  Weight on each wheel, shifting with the acceleration
            Load_F := S.Mass * G_Acc * S.B / L - S.Mass * C.Ax * S.H_Cg / L;
            Load_R := S.Mass * G_Acc - Load_F;
            Load_F := Float'Max (0.0, Load_F);
            Load_R := Float'Max (0.0, Load_R);

            Drive := (if C.Gear > 0
                      then Throttle * Engine_Torque (S, C.Rpm) * Ratio_Now / S.Radius
                      else 0.0);
            Brake_F := Pedal * S.Brake_Max * S.Brake_Bias / S.Radius;
            Brake_R := (Pedal * (1.0 - S.Brake_Bias) + 0.5 * Rear_Pedal) * S.Brake_Max / S.Radius;
            Drag := 0.5 * 1.2 * S.Cd_A * V * V + 0.015 * S.Mass * G_Acc;

            --  Cornering takes grip from braking and driving: the friction circle
            Ay := V * C.Rate;
            declare
               Lat_Use_F : constant Float := Clamp (abs Ay / (Grip_F * G_Acc), 0.0, 1.0);
               Lat_Use_R : constant Float := Clamp (abs Ay / (Grip_R * G_Acc), 0.0, 1.0);
               Room_F : constant Float := Grip_F * Load_F * Sqrt (1.0 - Lat_Use_F ** 2);
               Room_R : constant Float := Grip_R * Load_R * Sqrt (1.0 - Lat_Use_R ** 2);
               Abs_Hold : constant Boolean := A.Abs_On and then V > 3.0;
               Over_F : constant Float := Brake_F / Float'Max (1.0, Room_F);
               Over_R : Float;
            begin
               C.Abs_Active := Abs_Hold and then (Over_F > 1.0 or else Over_R > 1.0) and then Pedal > 0.0;
               --  Traction control: no more drive than the rear can take
               C.Tc_Active := A.Tc_On and then Drive > Room_R;
               if A.Tc_On then
                  Drive := Float'Min (Drive, Room_R);
               end if;
               --  (what the ABS lets through, it does not lock)
               Over_R := Float'Max ((if Abs_Hold then Float'Min (Brake_R, Room_R) else Brake_R), Drive)
                 / Float'Max (1.0, Room_R);
               Ax_Want := (Drive
                           - Float'Min (Brake_F, (if Abs_Hold then Room_F else Room_F * 1.1))
                           - Float'Min (Brake_R, Room_R) - Drag) / S.Mass;
               --  Too much asked of a leaned tyre: it lets go, and the bike goes down
               Used := (Over_F + Over_R) * 0.5;
               if (Over_F > 1.25 and then not Abs_Hold and then abs C.Roll > 0.35)
                 or else (Over_R > 1.6 and then abs C.Roll > 0.6)
                 or else (Front.Surf in Grass | Gravel and then abs C.Roll > 0.45 and then V > 12.0)
               then
                  C.Fallen_T := Dt;
               end if;
               for W in Wheel_Id loop
                  C.Wheels (W).Slide := Clamp ((if W <= 2 then Over_F else Over_R) - 1.0, 0.0, 1.0);
               end loop;
            end;
            pragma Unreferenced (Used);

            --  Wheelie and stoppie: the front lifts when the drive tips the bike
            --  back; the anti-wheelie cuts the throttle first
            declare
               Tip : constant Float := Ax_Want * S.H_Cg - G_Acc * S.B;   --  > 0: front lifts
               Dive : constant Float := -Ax_Want * S.H_Cg - G_Acc * S.A; --  > 0: rear lifts
               Target : Float := 0.0;
            begin
               if A.Stunt and then abs C.Roll < 0.12 and then I.Throttle > 0.7
                 and then V > 8.0 and then V < 62.0
                 and then (Tip > -4.5 or else (C.Pitch - Ground_Pitch > 0.1 and then Tip > -9.0))
               then
                  --  A show rider: up on the back wheel down the straights,
                  --  held at the balance with the throttle
                  Target := Float'Min (0.42, 0.24 + Float'Max (0.0, Tip + 4.5) * 0.05);
               elsif A.Stunt and then abs C.Roll < 0.12 and then Dive > -1.5 and then Pedal > 0.5 then
                  --  and the back wheel up under the brakes
                  Target := -Float'Min (0.22, 0.08 + (Dive + 1.5) * 0.06);
               elsif Tip > 0.0 then
                  Target := Float'Min (0.6, Tip * 0.3);
                  if A.Tc_On then
                     Ax_Want := G_Acc * S.B / S.H_Cg;   --  held at the balance
                     Target := 0.05;
                  end if;
               elsif Dive > 0.0 then
                  Target := -Float'Min (0.4, Dive * 0.2);
                  if A.Abs_On then
                     Ax_Want := -G_Acc * S.A / S.H_Cg;
                     Target := -0.03;
                  end if;
               end if;
               C.Pitch_V := 0.0;
               C.Pitch := C.Pitch + (Ground_Pitch + Target - C.Pitch) * Clamp (Dt * 5.0, 0.0, 1.0);
               if abs (C.Pitch - Ground_Pitch) > 0.55 then
                  C.Fallen_T := Dt;   --  over the back, or over the bars
               end if;
            end;

            --  Rubber goes with the work the tyres do, a few per cent of it
            --  sliding; the rear carries the drive
            if A.Wear_Rate > 0.0 then
               declare
                  Work : constant Float := S.Mass * V * Bike_Slip
                    * (abs Ax_Want + abs (V * C.Rate));
               begin
                  for W in Wheel_Id loop
                     C.Wheels (W).Wear := Float'Min
                       (1.0, C.Wheels (W).Wear + Dt * A.Wear_Rate * Wear_Per_Joule * Work
                          * (if W >= 3 then 0.6 else 0.4));
                  end loop;
               end;
            end if;

            C.Throttle_Eff := Throttle;
            C.Vx := Float'Max (0.0, C.Vx + Dt * Ax_Want);
            C.Ax := C.Ax + (Ax_Want - C.Ax) * 0.02;
            --  Turning: by the lean at speed, by the bars when slow
            C.Rate := Low_Speed * G_Acc * Tan (-C.Roll) / Float'Max (V, 2.0)
              + (1.0 - Low_Speed) * Kappa * V;
            C.Ay := C.Ay + (V * C.Rate - C.Ay) * 0.02;
            C.Vy := 0.0;
            C.Steer := Arctan (Kappa * L);
         end;
      end if;

      --  Along the ground, the body upright on its lean
      C.Heading := C.Heading + Dt * C.Rate;
      if C.Heading > Pi then
         C.Heading := C.Heading - 2.0 * Pi;
      elsif C.Heading < -Pi then
         C.Heading := C.Heading + 2.0 * Pi;
      end if;
      C.X := C.X + Long_Float (Dt * (C.Vx * FX + C.Vy * RX));
      C.Z := C.Z + Long_Float (Dt * (C.Vx * FZ + C.Vy * RZ));
      --  Up on one wheel, the bike turns about the one still down
      C.Y := (Front.Y + Rear.Y) * 0.5 + S.H_Cg * Cos (C.Roll)
        + (if C.Pitch > Ground_Pitch then S.B * Sin (C.Pitch - Ground_Pitch)
           else S.A * Sin (Ground_Pitch - C.Pitch));
      C.Vz := 0.0;
      for W in Wheel_Id loop
         C.Wheels (W).Angle := C.Wheels (W).Angle + C.Vx / S.Radius * Dt;
         if C.Wheels (W).Angle > 2.0 * Pi then
            C.Wheels (W).Angle := C.Wheels (W).Angle - 2.0 * Pi;
         end if;
      end loop;
      Walls (C, S);
      if C.Impact > 9.0 and then C.Fallen_T = 0.0 then
         C.Fallen_T := Dt;
      end if;
      C.Impact := Float'Max (0.0, C.Impact - Dt * 4.0);
      C.Scrape := Float'Max (0.0, C.Scrape - Dt * 5.0);
      C.Rack := 0.0;
   end Bike_Step;

   procedure Step (C : in out Car; S : Spec; I : Inputs; A : Assists) is
      Sin_H : constant Float := Sin (C.Heading);
      Cos_H : constant Float := Cos (C.Heading);
      FX : constant Float := Sin_H;
      FZ : constant Float := -Cos_H;
      RX : constant Float := Cos_H;
      RZ : constant Float := Sin_H;
      PX : constant Float := Float (C.X);
      PZ : constant Float := Float (C.Z);
      XB, YB : array (Wheel_Id) of Float;
      Sum_Fx, Sum_Fy, Sum_Mz : Float := 0.0;
      Heave, M_Pitch, M_Roll : Float := 0.0;
      Steer : constant Float := Clamp (I.Steer, -1.0, 1.0) * S.Steer_Lock + C.Toe;
      Mass_Now : constant Float :=
        S.Mass + (if A.Fuel_Use then C.Fuel - Fuel_Reference else 0.0);
      V2 : constant Float := C.Vx * C.Vx + C.Vy * C.Vy;
      Lost_Aero : constant Float := 1.0 - 0.6 * C.Dmg_Aero;
      Down_F : constant Float := 0.5 * Air * S.Cl_F * V2 * Lost_Aero;
      Down_R : constant Float := 0.5 * Air * S.Cl_R * V2 * Lost_Aero;
      --  Gravity along the ground
      Grade, Side_Slope : Float;
   begin
      if C.Kind = Sport_Bike then
         Bike_Step (C, S, I, A);
         return;
      end if;
      C.Steer := Steer;
      --  A new hit since last time: above a knock, something breaks
      if A.Damage > 0.0 and then C.Impact > C.Seen_Impact + 3.0 then
         declare
            Hurt : constant Float := Clamp ((C.Impact - 5.0) / 22.0, 0.0, 1.0) * A.Damage;
            Front : constant Boolean := C.Hit_X > 0.5;
            Rear : constant Boolean := C.Hit_X < -0.5;
         begin
            C.Dmg_Aero := Float'Min (1.0, C.Dmg_Aero + Hurt * (if Front or Rear then 1.0 else 0.4));
            C.Dmg_Engine := Float'Min
              (1.0, C.Dmg_Engine + Hurt * (if Front then 0.7 elsif Rear then 0.4 else 0.2));
            if Front then
               C.Toe := Clamp (C.Toe + Hurt * 0.07 * (if C.Hit_Y >= 0.0 then -1.0 else 1.0),
                               -0.07, 0.07);
            end if;
         end;
      end if;
      C.Seen_Impact := C.Impact;
      for W in Wheel_Id loop
         Wheel_Pos (S, W, XB (W), YB (W));
      end loop;

      Gear_Logic (C, S, I, A);

      --  Suspension: each corner against the ground under its wheel
      for W in Wheel_Id loop
         declare
            WS : Wheel_State renames C.Wheels (W);
            Con : Track.Contact;
            K : constant Float := (if W <= 2 then S.K_F else S.K_R);
            D : constant Float := (if W <= 2 then S.C_F else S.C_R);
            --  Height of this corner of the body, relative to the C of G
            Corner : constant Float := C.Y + XB (W) * C.Pitch + YB (W) * C.Roll;
         begin
            Track.Query (PX + FX * XB (W) + RX * YB (W), PZ + FZ * XB (W) + RZ * YB (W),
                         WS.Hint, Con);
            WS.Surf := Con.Surf;
            --  The tyre itself takes the sharp edge off
            declare
               Before : constant Float := WS.Ground;
            begin
               WS.Ground := WS.Ground + (Con.Y - WS.Ground) * 0.22;
               WS.Bump := WS.Ground - Before;
            end;
            declare
               Rest : constant Float := S.H_Cg + Static_Comp (S, W);
               Comp : constant Float := WS.Ground + Rest - Corner;
            begin
               WS.Comp_V := (Comp - WS.Comp) / Dt;
               WS.Comp := Comp;
               WS.Off_Y := S.Radius + WS.Ground - Corner + S.H_Cg;
            end;
            pragma Unreferenced (K, D);
         end;
      end loop;

      --  Springs, dampers, bars
      declare
         Roll_F : constant Float := C.Wheels (1).Comp - C.Wheels (2).Comp;
         Roll_R : constant Float := C.Wheels (3).Comp - C.Wheels (4).Comp;
      begin
         for W in Wheel_Id loop
            declare
               WS : Wheel_State renames C.Wheels (W);
               K : constant Float := (if W <= 2 then S.K_F else S.K_R);
               D : constant Float := (if W <= 2 then S.C_F else S.C_R);
               Damper : constant Float :=
                 D * (if WS.Comp_V > 0.0
                      then Float'Min (WS.Comp_V, 0.3 + 0.35 * WS.Comp_V)
                      else WS.Comp_V);
               Stop : constant Float := Float'Max (0.0, WS.Comp - S.Stop_Comp) * 300_000.0;
               Bar : constant Float :=
                 (case W is
                     when 1 => S.Arb_F * Roll_F,
                     when 2 => -S.Arb_F * Roll_F,
                     when 3 => S.Arb_R * Roll_R,
                     when 4 => -S.Arb_R * Roll_R);
               F : constant Float := Float'Max (0.0, K * WS.Comp + Damper + Stop + Bar);
            begin
               WS.Fz := (if WS.Comp < 0.0 then 0.0 else F)
                 + (if W <= 2 then Down_F / 2.0 else Down_R / 2.0);
               Heave := Heave + WS.Fz;
               M_Pitch := M_Pitch + WS.Fz * XB (W);
               M_Roll := M_Roll + WS.Fz * YB (W);
            end;
         end loop;
      end;

      --  The downforce pushes the body down as hard as it presses the tyres
      Heave := Heave - Down_F - Down_R;
      M_Pitch := M_Pitch - Down_F * S.A + Down_R * S.B;

      --  Engine demand
      declare
         Throttle : Float := Clamp (I.Throttle, 0.0, 1.0);
      begin
         --  Traction control: cut when the rear spins
         C.Tc_Active := False;
         if A.Tc_On and then C.Gear /= 0 then
            declare
               Slip : constant Float :=
                 Float'Max (abs C.Wheels (3).Ux, abs C.Wheels (4).Ux) / Relax_Len_X / S.Slip_X
                 / Slip_Scale (C.Wheels (3).Surf);
            begin
               if Slip > 1.25 and then C.Gear > 0 then
                  C.Tc_Cut := Float'Max (0.2, C.Tc_Cut - Dt * 6.0);
                  C.Tc_Active := True;
               else
                  C.Tc_Cut := Float'Min (1.0, C.Tc_Cut + Dt * 5.0);
               end if;
            end;
            Throttle := Throttle * C.Tc_Cut;
         else
            C.Tc_Cut := 1.0;
         end if;
         if C.Shift_T > 0.0 then
            Throttle := (if C.Shift_Blip then 0.7 else 0.0);
         end if;
         C.Rpm := C.Omega_E * 60.0 / (2.0 * Pi);
         if C.Rpm > S.Red_Line + 150.0 then
            Throttle := 0.0;
         end if;
         --  The idle control holds the engine up
         if C.Rpm < S.Idle then
            Throttle := Float'Max (Throttle, Clamp ((S.Idle - C.Rpm) / 150.0, 0.0, 0.5));
         end if;
         --  An empty tank stops all of that
         if A.Fuel_Use and then C.Fuel <= 0.0 then
            Throttle := 0.0;
         end if;
         C.Throttle_Eff := Throttle;
      end;

      --  Clutch engagement
      declare
         Slip_Wanted : constant Boolean := C.Gear /= 0;
      begin
         case A.Mode is
            when H_Clutch =>
               C.Clutch_Eng := Clamp ((0.82 - I.Clutch) / 0.5, 0.0, 1.0);
            when others =>
               if C.Shift_T > 0.0 then
                  C.Clutch_Eng := 0.0;
               elsif Slip_Wanted then
                  --  Automatic clutch: lets in with the revs
                  declare
                     Low : constant Float := S.Idle + 150.0;
                     Bite : constant Float := Clamp ((C.Rpm - Low) / 1400.0, 0.0, 1.0);
                  begin
                     C.Clutch_Eng := Bite * Bite;
                  end;
               else
                  C.Clutch_Eng := 0.0;
               end if;
         end case;
         --  Never stalls: below idle the clutch slips whatever the pedal says
         if C.Rpm < S.Idle * 0.85 then
            C.Clutch_Eng := C.Clutch_Eng * Clamp ((C.Rpm - S.Idle * 0.6) / (S.Idle * 0.25), 0.0, 1.0);
         end if;
      end;

      --  Grade from the ground under the wheels
      Grade := (C.Wheels (1).Ground + C.Wheels (2).Ground
                - C.Wheels (3).Ground - C.Wheels (4).Ground) / (2.0 * (S.A + S.B));
      Side_Slope := (C.Wheels (2).Ground + C.Wheels (4).Ground
                     - C.Wheels (1).Ground - C.Wheels (3).Ground) / (S.Track_F + S.Track_R);

      --  Tyres
      C.Abs_Active := False;
      declare
         Sum_Mz_Rack : Float := 0.0;
         Feel : Float := 0.0;
      begin
         for W in Wheel_Id loop
            declare
               WS : Wheel_State renames C.Wheels (W);
               Ack : constant Float :=
                 (if W <= 2 then Steer + 0.08 * Steer * Steer * (if YB (W) > 0.0 then 1.0 else -1.0)
                                    * (if Steer > 0.0 then 1.0 else -1.0)
                  else 0.0);
               V_XB : constant Float := C.Vx - C.Rate * YB (W);
               V_YB : constant Float := C.Vy + C.Rate * XB (W);
               Cs : constant Float := Cos (Ack);
               Sn : constant Float := Sin (Ack);
               V_Long : constant Float := V_XB * Cs + V_YB * Sn;
               V_Lat  : constant Float := -V_XB * Sn + V_YB * Cs;
               Fx, Fy : Float;
               T_Brake : Float;
            begin
               Tyre_Force (WS, S, W >= 3, V_Long, V_Lat, Fx, Fy);
               --  Rubber goes with the work done sliding
               if A.Wear_Rate > 0.0 then
                  WS.Wear := Float'Min
                    (1.0, WS.Wear + Dt * A.Wear_Rate * Wear_Per_Joule
                                    * (abs (Fx * (WS.Omega * S.Radius - V_Long)) + abs (Fy * V_Lat)));
               end if;
               WS.Fx := Fx;
               WS.Fy := Fy;
               Sum_Fx := Sum_Fx + Fx * Cs - Fy * Sn;
               Sum_Fy := Sum_Fy + Fx * Sn + Fy * Cs;
               Sum_Mz := Sum_Mz + XB (W) * (Fx * Sn + Fy * Cs) - YB (W) * (Fx * Cs - Fy * Sn);

               if W <= 2 then
                  Sum_Mz_Rack := Sum_Mz_Rack + WS.Mz + 0.02 * Fx * Sn;
                  Feel := Feel + WS.Bump * (if W = 1 then 1.0 else -1.0);
               end if;

               --  Wheel: tyre torque now, the brake as dry friction afterwards
               WS.Omega := WS.Omega - Dt * Fx * S.Radius / S.Wheel_I;
               declare
                  Pedal : constant Float := Clamp (I.Brake, 0.0, 1.0) ** 1.25;
                  Max_T : constant Float :=
                    (if W <= 2
                     then S.Brake_Max * S.Brake_Bias / 2.0
                     else S.Brake_Max * (1.0 - S.Brake_Bias) / 2.0);
               begin
                  --  ABS: hold the wheel at the peak of its slip
                  if A.Abs_On and then Pedal > 0.02 and then abs V_Long > 3.0 then
                     if WS.Ux < -Relax_Len_X * S.Slip_X * 1.1 * Slip_Scale (WS.Surf) then
                        WS.Abs_Mod := Float'Max (0.15, WS.Abs_Mod - Dt * 14.0);
                        C.Abs_Active := True;
                     else
                        WS.Abs_Mod := Float'Min (1.0, WS.Abs_Mod + Dt * 7.0);
                     end if;
                  else
                     WS.Abs_Mod := 1.0;
                  end if;
                  T_Brake := Pedal * Max_T * WS.Abs_Mod;
                  if I.Handbrake and then W >= 3 then
                     T_Brake := Float'Max (T_Brake, 3000.0);
                  end if;
               end;
               --  Rolling resistance acts the same way; more off the road
               T_Brake := T_Brake + WS.Fz * S.Radius *
                 (case WS.Surf is
                     when Asphalt | Kerb => 0.012,
                     when Dirt => 0.024,
                     when Grass => 0.05,
                     when Gravel => 0.13);
               declare
                  Stop : constant Float := T_Brake * Dt / S.Wheel_I;
               begin
                  if abs WS.Omega <= Stop then
                     WS.Omega := 0.0;
                  elsif WS.Omega > 0.0 then
                     WS.Omega := WS.Omega - Stop;
                  else
                     WS.Omega := WS.Omega + Stop;
                  end if;
               end;
            end;
         end loop;
         C.Rack := Sum_Mz_Rack;
         C.Road_Feel := Feel;
      end;

      --  Engine, clutch, differential.  The clutch and the limited slip are
      --  dry friction solved for the torque that would just stop them
      --  slipping, so a stiff lockup stays stable.
      declare
         R_Total : constant Float := Ratio (S, C.Gear);
         T_E : constant Float :=
           C.Throttle_Eff * Engine_Torque (S, C.Rpm) * (1.0 - 0.55 * C.Dmg_Engine)
           - (1.0 - C.Throttle_Eff) * (20.0 + C.Rpm * 0.012);
         T_Clutch : Float := 0.0;
         I_A : constant Float := 2.0 * S.Wheel_I;
         Fl : Wheel_State renames C.Wheels (1);
         Fr : Wheel_State renames C.Wheels (2);
         Wl : Wheel_State renames C.Wheels (3);
         Wr : Wheel_State renames C.Wheels (4);
         Share_F : constant Float := S.Front_Share;
         Share_R : constant Float := 1.0 - Share_F;

         --  A limited slip between two wheels
         procedure Diff_Lock (A, B : in out Wheel_State; Input : Float) is
            Cap : constant Float := S.Lsd_Preload + S.Lsd_Ramp * abs Input;
            Needed : constant Float := (A.Omega - B.Omega) * S.Wheel_I / (2.0 * Dt);
            T : constant Float := Clamp (Needed, -Cap, Cap);
            Dw : constant Float := Dt * T / S.Wheel_I;
         begin
            A.Omega := A.Omega - Dw;
            B.Omega := B.Omega + Dw;
         end Diff_Lock;
      begin
         C.Omega_E := C.Omega_E + Dt * T_E / S.Engine_I;
         --  About 290 g for each kWh made
         if A.Fuel_Use and then T_E > 0.0 then
            C.Fuel := Float'Max (0.0, C.Fuel - Dt * T_E * C.Omega_E * 8.0E-8);
         end if;
         if R_Total /= 0.0 then
            declare
               Mean_F : constant Float := (Fl.Omega + Fr.Omega) * 0.5;
               Mean_R : constant Float := (Wl.Omega + Wr.Omega) * 0.5;
               Omega_S : constant Float :=
                 (Share_F * Mean_F + Share_R * Mean_R) * R_Total;
               A_E : constant Float := 1.0 / S.Engine_I;
               A_S : constant Float :=
                 R_Total * R_Total * (Share_F * Share_F + Share_R * Share_R) / I_A;
               Needed : constant Float := (C.Omega_E - Omega_S) / (Dt * (A_E + A_S));
               Cap : constant Float := C.Clutch_Eng * S.Clutch_Max;
            begin
               T_Clutch := Clamp (Needed, -Cap, Cap);
               C.Omega_E := C.Omega_E - Dt * T_Clutch * A_E;
               declare
                  Dw : constant Float := Dt * T_Clutch * R_Total / I_A;
               begin
                  Wl.Omega := Wl.Omega + Dw * Share_R;
                  Wr.Omega := Wr.Omega + Dw * Share_R;
                  if Share_F > 0.0 then
                     Fl.Omega := Fl.Omega + Dw * Share_F;
                     Fr.Omega := Fr.Omega + Dw * Share_F;
                  end if;
               end;
            end;
         end if;
         C.Omega_E := Float'Max (C.Omega_E, S.Idle * 0.5 * 2.0 * Pi / 60.0);
         Diff_Lock (Wl, Wr, T_Clutch * R_Total * Share_R);
         if Share_F > 0.0 then
            Diff_Lock (Fl, Fr, T_Clutch * R_Total * Share_F);
            --  The centre differential: the axles held near each other's speed
            declare
               Cap : constant Float := 150.0 + 0.35 * abs (T_Clutch * R_Total);
               Needed : constant Float :=
                 ((Fl.Omega + Fr.Omega) - (Wl.Omega + Wr.Omega)) * 0.5 * I_A / (2.0 * Dt);
               T : constant Float := Clamp (Needed, -Cap, Cap);
               Dw : constant Float := Dt * T / I_A;
            begin
               Fl.Omega := Fl.Omega - Dw;
               Fr.Omega := Fr.Omega - Dw;
               Wl.Omega := Wl.Omega + Dw;
               Wr.Omega := Wr.Omega + Dw;
            end;
         end if;
      end;

      for W in Wheel_Id loop
         declare
            WS : Wheel_State renames C.Wheels (W);
         begin
            WS.Angle := WS.Angle + WS.Omega * Dt;
            if WS.Angle > 2.0 * Pi then
               WS.Angle := WS.Angle - 2.0 * Pi;
            elsif WS.Angle < -2.0 * Pi then
               WS.Angle := WS.Angle + 2.0 * Pi;
            end if;
         end;
      end loop;

      --  Aerodynamic drag
      declare
         Sp : constant Float := Sqrt (V2);
         Drag : constant Float := 0.5 * Air * S.Cd_A * (1.0 + 0.5 * C.Dmg_Aero) * Sp;
      begin
         Sum_Fx := Sum_Fx - Drag * C.Vx;
         Sum_Fy := Sum_Fy - Drag * C.Vy;
      end;

      --  Body
      declare
         Ax : constant Float := Sum_Fx / Mass_Now;
         Ay : constant Float := Sum_Fy / Mass_Now;
         G_X : constant Float := -G * Grade / Sqrt (1.0 + Grade * Grade);
         G_Y : constant Float := -G * Side_Slope / Sqrt (1.0 + Side_Slope * Side_Slope);
      begin
         C.Ax := C.Ax + (Ax - C.Ax) * 0.02;
         C.Ay := C.Ay + (Ay - C.Ay) * 0.02;
         C.Vx := C.Vx + Dt * (Ax + G_X + C.Rate * C.Vy);
         C.Vy := C.Vy + Dt * (Ay + G_Y - C.Rate * C.Vx);
         C.Rate := C.Rate + Dt * Sum_Mz / S.Inertia;
         --  Weight transfer: the forces act on the ground, below the centre
         M_Pitch := M_Pitch + S.H_Cg * Sum_Fx;
         M_Roll := M_Roll + S.H_Cg * Sum_Fy;
         C.Vz := C.Vz + Dt * (Heave / Mass_Now - G);
         C.Y := C.Y + Dt * C.Vz;
         C.Pitch_V := C.Pitch_V + Dt * M_Pitch / S.Pitch_I;
         C.Pitch := C.Pitch + Dt * C.Pitch_V;
         C.Roll_V := C.Roll_V + Dt * M_Roll / S.Roll_I;
         C.Roll := C.Roll + Dt * C.Roll_V;
      end;
      C.Heading := C.Heading + Dt * C.Rate;
      if C.Heading > Pi then
         C.Heading := C.Heading - 2.0 * Pi;
      elsif C.Heading < -Pi then
         C.Heading := C.Heading + 2.0 * Pi;
      end if;
      C.X := C.X + Long_Float (Dt * (C.Vx * FX + C.Vy * RX));
      C.Z := C.Z + Long_Float (Dt * (C.Vx * FZ + C.Vy * RZ));

      Walls (C, S);
      C.Impact := Float'Max (0.0, C.Impact - Dt * 4.0);
      C.Scrape := Float'Max (0.0, C.Scrape - Dt * 5.0);
   end Step;

   ---------------------------------------------------------------------------
   --  Impacts
   ---------------------------------------------------------------------------

   --  An impulse at a point of the body (world direction; X_B, Y_B on the body)
   procedure Hit (C : in out Car; S : Spec; X_B, Y_B, JX, JY : Float) is
   begin
      C.Vx := C.Vx + JX / S.Mass;
      C.Vy := C.Vy + JY / S.Mass;
      C.Rate := C.Rate + (X_B * JY - Y_B * JX) / S.Inertia;
   end Hit;

   Half_Len : constant := 2.25;
   Half_Wid : constant := 0.95;

   --  A trunk does not give way.  The body is a box: the nearest point of it
   --  to the tree takes the blow.
   procedure Trunks (C : in out Car; S : Spec) is
      Found : Boolean;
      TX, TZ : Float;
   begin
      Track.Nearest_Tree (Float (C.X), Float (C.Z), Half_Len + 1.0, Found, TX, TZ);
      if not Found then
         return;
      end if;
      declare
         FX : constant Float := Sin (C.Heading);
         FZ : constant Float := -Cos (C.Heading);
         RX : constant Float := Cos (C.Heading);
         RZ : constant Float := Sin (C.Heading);
         DX : constant Float := TX - Float (C.X);
         DZ : constant Float := TZ - Float (C.Z);
         --  The tree in body axes
         Bx : constant Float := DX * FX + DZ * FZ;
         By : constant Float := DX * RX + DZ * RZ;
         Cx : constant Float := Clamp (Bx, -Half_Len, Half_Len);
         Cy : constant Float := Clamp (By, -Half_Wid, Half_Wid);
         Gap : constant Float := Sqrt ((Cx - Bx) ** 2 + (Cy - By) ** 2);
         R : constant Float := Track.Tree_Radius;
         --  Pushing the car away from the tree, in body axes
         NB_X, NB_Y, Over : Float;
      begin
         if Gap >= R then
            return;
         elsif Gap > 0.001 then
            NB_X := (Cx - Bx) / Gap;
            NB_Y := (Cy - By) / Gap;
            Over := R - Gap;
         elsif Half_Len - abs Bx < Half_Wid - abs By then
            --  Inside the box already: out by the nearer end or side
            NB_X := (if Bx > 0.0 then -1.0 else 1.0);
            NB_Y := 0.0;
            Over := R + Half_Len - abs Bx;
         else
            NB_X := 0.0;
            NB_Y := (if By > 0.0 then -1.0 else 1.0);
            Over := R + Half_Wid - abs By;
         end if;
         C.X := C.X + Long_Float ((NB_X * FX + NB_Y * RX) * Over);
         C.Z := C.Z + Long_Float ((NB_X * FZ + NB_Y * RZ) * Over);
         declare
            VF : constant Float := C.Vx - C.Rate * Cy;
            VR : constant Float := C.Vy + C.Rate * Cx;
            Vn : constant Float := VF * NB_X + VR * NB_Y;
            Vt : constant Float := -VF * NB_Y + VR * NB_X;
            Arm_N : constant Float := Cx * NB_Y - Cy * NB_X;
            Inv : constant Float := 1.0 / S.Mass + Arm_N * Arm_N / S.Inertia;
         begin
            if Vn < 0.0 then
               declare
                  Jn : constant Float := -1.2 * Vn / Inv;
                  TF : constant Float := -NB_Y;
                  TR : constant Float := NB_X;
                  Arm_T : constant Float := Cx * TR - Cy * TF;
                  Inv_T : constant Float := 1.0 / S.Mass + Arm_T * Arm_T / S.Inertia;
                  Jt_Max : constant Float := 0.4 * Jn;
                  Jt : constant Float := Clamp (-Vt / Inv_T, -Jt_Max, Jt_Max);
               begin
                  Hit (C, S, Cx, Cy, Jn * NB_X + Jt * TF, Jn * NB_Y + Jt * TR);
                  C.Impact := Float'Max (C.Impact, -Vn);
                  C.Hit_X := Cx;
                  C.Hit_Y := Cy;
               end;
            end if;
         end;
      end;
   end Trunks;

   procedure Walls (C : in out Car; S : Spec) is
      Px : constant array (1 .. 6) of Float :=
        (Half_Len, Half_Len, 0.0, 0.0, -Half_Len, -Half_Len);
      Py : constant array (1 .. 6) of Float :=
        (-Half_Wid, Half_Wid, -Half_Wid, Half_Wid, -Half_Wid, Half_Wid);
      Cos_H : constant Float := Cos (C.Heading);
      Sin_H : constant Float := Sin (C.Heading);
      FX : constant Float := Sin_H;
      FZ : constant Float := -Cos_H;
      RX : constant Float := Cos_H;
      RZ : constant Float := Sin_H;
      I : Natural;
      T, D : Float;
   begin
      --  Where along the road: everyone needs it, whatever else is near
      Track.Locate (Float (C.X), Float (C.Z), C.Hint, I, T, D);
      if Track.Is_Stage then
         Trunks (C, S);
         return;
      end if;
      --  Quick look: is the body anywhere near a barrier
      if abs D + Half_Len + 0.5
        < Float'Min (Track.Samples (I).Wall_L, Track.Samples (I).Wall_R)
      then
         return;
      end if;
      for K in Px'Range loop
         declare
            WX : constant Float := Float (C.X) + FX * Px (K) + RX * Py (K);
            WZ : constant Float := Float (C.Z) + FZ * Px (K) + RZ * Py (K);
            Hint : Natural := C.Hint;
            PI_I : Natural;
            PT, PD : Float;
         begin
            Track.Locate (WX, WZ, Hint, PI_I, PT, PD);
            declare
               A : Track.Sample renames Track.Samples (PI_I);
               Wall : constant Float := (if PD > 0.0 then A.Wall_R else A.Wall_L);
               Over : constant Float := abs PD - Wall;
            begin
               if Over > 0.0 then
                  declare
                     Sign : constant Float := (if PD > 0.0 then -1.0 else 1.0);
                     --  Normal (world), pointing back to the road
                     NX : constant Float := A.RX * Sign;
                     NZ : constant Float := A.RZ * Sign;
                     --  In body axes
                     N_F : constant Float := NX * FX + NZ * FZ;
                     N_R : constant Float := NX * RX + NZ * RZ;
                     --  Velocity of this point, body axes
                     VF : constant Float := C.Vx - C.Rate * Py (K);
                     VR : constant Float := C.Vy + C.Rate * Px (K);
                     Vn : constant Float := VF * N_F + VR * N_R;
                     --  Along the wall
                     TF : constant Float := -N_R;
                     TR : constant Float := N_F;
                     Vt : constant Float := VF * TF + VR * TR;
                     Arm_N : constant Float := Px (K) * N_R - Py (K) * N_F;
                     Inv : constant Float := 1.0 / S.Mass + Arm_N * Arm_N / S.Inertia;
                  begin
                     C.X := C.X + Long_Float (NX * Over);
                     C.Z := C.Z + Long_Float (NZ * Over);
                     if Vn < 0.0 then
                        declare
                           Jn : constant Float := -(1.25) * Vn / Inv;
                           Arm_T : constant Float := Px (K) * TR - Py (K) * TF;
                           Inv_T : constant Float := 1.0 / S.Mass + Arm_T * Arm_T / S.Inertia;
                           Jt_Max : constant Float := 0.3 * Jn;
                           Jt : constant Float := Clamp (-Vt / Inv_T, -Jt_Max, Jt_Max);
                        begin
                           Hit (C, S, Px (K), Py (K),
                                Jn * N_F + Jt * TF, Jn * N_R + Jt * TR);
                           C.Impact := Float'Max (C.Impact, -Vn);
                           C.Hit_X := Px (K);
                           C.Hit_Y := Py (K);
                           C.Scrape := Float'Max (C.Scrape, Clamp (abs Vt / 20.0, 0.0, 1.0));
                        end;
                     end if;
                     return;
                  end;
               end if;
            end;
         end;
      end loop;
   end Walls;

   procedure Collide (A, B : in out Car; Spec_A, Spec_B : Spec) is
      DX0 : constant Float := Float (B.X - A.X);
      DZ0 : constant Float := Float (B.Z - A.Z);
      Offs : constant array (1 .. 3) of Float := (1.5, 0.0, -1.5);
      R : constant := 0.95;
   begin
      if DX0 * DX0 + DZ0 * DZ0 > 36.0 then
         return;
      end if;
      declare
         AFX : constant Float := Sin (A.Heading);
         AFZ : constant Float := -Cos (A.Heading);
         BFX : constant Float := Sin (B.Heading);
         BFZ : constant Float := -Cos (B.Heading);
         ARX : constant Float := -AFZ;
         ARZ : constant Float := AFX;
         BRX : constant Float := -BFZ;
         BRZ : constant Float := BFX;
      begin
         for I in Offs'Range loop
            for J in Offs'Range loop
               declare
                  OX : constant Float := DX0 + BFX * Offs (J) - AFX * Offs (I);
                  OZ : constant Float := DZ0 + BFZ * Offs (J) - AFZ * Offs (I);
                  Dist : constant Float := Sqrt (OX * OX + OZ * OZ);
               begin
                  if Dist < 2.0 * R and then Dist > 0.01 then
                     declare
                        NX : constant Float := OX / Dist;   --  from A to B
                        NZ : constant Float := OZ / Dist;
                        Over : constant Float := 2.0 * R - Dist;
                        --  World velocities of the two points
                        AVX : constant Float := AFX * (A.Vx) + ARX * (A.Vy + A.Rate * Offs (I));
                        AVZ : constant Float := AFZ * (A.Vx) + ARZ * (A.Vy + A.Rate * Offs (I));
                        BVX : constant Float := BFX * (B.Vx) + BRX * (B.Vy + B.Rate * Offs (J));
                        BVZ : constant Float := BFZ * (B.Vx) + BRZ * (B.Vy + B.Rate * Offs (J));
                        Closing : constant Float := (AVX - BVX) * NX + (AVZ - BVZ) * NZ;
                        Inv : constant Float := 1.0 / Spec_A.Mass + 1.0 / Spec_B.Mass;
                     begin
                        A.X := A.X - Long_Float (NX * Over * 0.5);
                        A.Z := A.Z - Long_Float (NZ * Over * 0.5);
                        B.X := B.X + Long_Float (NX * Over * 0.5);
                        B.Z := B.Z + Long_Float (NZ * Over * 0.5);
                        if Closing > 0.0 then
                           declare
                              J_N : constant Float := 1.3 * Closing / Inv;
                              JAX : constant Float := -J_N * NX;
                              JAZ : constant Float := -J_N * NZ;
                           begin
                              Hit (A, Spec_A, Offs (I), 0.0,
                                   JAX * AFX + JAZ * AFZ, JAX * ARX + JAZ * ARZ);
                              Hit (B, Spec_B, Offs (J), 0.0,
                                   -JAX * BFX - JAZ * BFZ, -JAX * BRX - JAZ * BRZ);
                              A.Impact := Float'Max (A.Impact, Closing);
                              B.Impact := Float'Max (B.Impact, Closing);
                              A.Hit_X := Offs (I);
                              A.Hit_Y := 0.0;
                              B.Hit_X := Offs (J);
                              B.Hit_Y := 0.0;
                           end;
                        end if;
                     end;
                     return;
                  end if;
               end;
            end loop;
         end loop;
      end;
   end Collide;

end Vehicle;
