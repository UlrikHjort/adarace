--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  How forgiving is a slide?  A simulated driver with a human's reaction
--  time turns in too hard, lifts off and catches the car by countersteering.
--  Prints a table per tyre shape, for comparing the handling while tuning:
--
--     bin/catch [name=value,... ...]    e.g. shape=1.3,rear_mu=1.1

with Ada.Command_Line;
with Ada.Numerics.Elementary_Functions;
with Ada.Text_IO; use Ada.Text_IO;

with Track;
with Vehicle; use Vehicle;

procedure Catch is
   use Ada.Numerics.Elementary_Functions;

   package F_IO is new Float_IO (Float);

   function Img (V : Float; Aft : Natural := 1) return String is
      B : String (1 .. 12);
   begin
      F_IO.Put (B, V, Aft => Aft, Exp => 0);
      return B;
   end Img;

   Reaction : constant := 0.20;       --  seconds until the hands respond
   Hand_Rate : constant := 2.5;       --  of full lock per second (1100 deg/s)

   type Result is record
      Peak_Beta : Float := 0.0;
      Recover   : Float := -1.0;      --  seconds; -1: did not
      Spun      : Boolean := False;
   end record;

   type Float_List is array (Positive range <>) of Float;

   function Try (K : Car_Kind; S : Spec; Kmh, Turn_In : Float) return Result is
      A : constant Assists := (Abs_On => True, Tc_On => True, Mode => Automatic, others => <>);
      C : Car;
      N : Inputs;
      R : Result;
      History : array (0 .. 1000) of Float := (others => 0.0);
      Caught_At : Integer := -1;
      Hand : Float := 0.0;
      I0 : Track.Sample renames Track.Samples (0);
      H0 : constant Float := Arctan (I0.RZ, I0.RX);
   begin
      Place (C, K, I0.X, I0.Z, H0);
      for I in 1 .. 2000 loop
         Step (C, S, (others => <>), A);
      end loop;
      C.Vx := Kmh / 3.6;
      for W in Wheel_Id loop
         C.Wheels (W).Omega := C.Vx / S.Radius;
      end loop;
      C.Gear := 4;
      for I in 1 .. 8000 loop
         declare
            Beta : constant Float :=
              Arctan (C.Vy, Float'Max (1.0, abs C.Vx));
            Delayed : constant Float :=
              History ((I + History'Length - Natural (Reaction * 1000.0)) mod History'Length);
         begin
            History (I mod History'Length) := Beta;
            if Caught_At < 0 then
               --  Too much lock, on and off the throttle, until it lets go
               if abs Delayed < 0.10 and then I < 1500 then
                  Hand := Hand + Float'Max (-Hand_Rate * 0.001, Float'Min (Hand_Rate * 0.001, Turn_In - Hand));
                  N.Throttle := 0.0;
               else
                  Caught_At := I;
               end if;
            else
               --  Countersteer: point the front wheels where the car is going
               declare
                  Want : constant Float :=
                    (Delayed + 0.06 * C.Rate) / S.Steer_Lock;
                  Target : constant Float := Float'Max (-1.0, Float'Min (1.0, Want));
               begin
                  Hand := Hand + Float'Max (-Hand_Rate * 0.001,
                                            Float'Min (Hand_Rate * 0.001, Target - Hand));
               end;
               N.Throttle := 0.0;
               N.Brake := 0.0;
            end if;
            N.Steer := Hand;
            Step (C, S, N, A);
            R.Peak_Beta := Float'Max (R.Peak_Beta, abs Beta);
            if Caught_At > 0 and then R.Recover < 0.0
              and then abs Beta < 0.035 and then abs C.Rate < 0.15
            then
               R.Recover := Float (I - Caught_At) / 1000.0;
               exit;
            end if;
            if abs Beta > 1.2 then
               R.Spun := True;
               exit;
            end if;
            exit when Speed (C) < 8.0;
         end;
      end loop;
      return R;
   end Try;

   procedure Table (K : Car_Kind; Label : String; S : Spec) is
      Caught, Tries : Natural := 0;
      Sum_Peak, Sum_Rec : Float := 0.0;
   begin
      for Kmh of Float_List'(70.0, 90.0, 110.0, 130.0, 150.0) loop
         for Turn of Float_List'(0.10, 0.15, 0.20, 0.30, 0.45) loop
            declare
               R : constant Result := Try (K, S, Kmh, Turn);
            begin
               if R.Peak_Beta > 0.10 then
                  Tries := Tries + 1;
                  Sum_Peak := Sum_Peak + R.Peak_Beta;
                  if R.Recover >= 0.0 and then not R.Spun then
                     Caught := Caught + 1;
                     Sum_Rec := Sum_Rec + R.Recover;
                  end if;
               end if;
            end;
         end loop;
      end loop;
      Put_Line (K'Image & " " & Label & ": slides" & Tries'Image
                & ", caught" & Caught'Image
                & ", peak" & Img (Sum_Peak / Float'Max (1.0, Float (Tries)) * 57.3)
                & " deg, recovery"
                & Img (Sum_Rec / Float'Max (1.0, Float (Caught)), 2) & " s");
   end Table;

   --  An argument: name=value[,name=value]; applied over the car's spec
   procedure Apply (S : in out Spec; Arg : String) is
      Start : Positive := Arg'First;
   begin
      for I in Arg'First .. Arg'Last + 1 loop
         if I > Arg'Last or else Arg (I) = ',' then
            for E in Start .. I - 1 loop
               if Arg (E) = '=' then
                  declare
                     N : constant String := Arg (Start .. E - 1);
                     V : constant Float := Float'Value (Arg (E + 1 .. I - 1));
                  begin
                     if N = "shape" then S.Rho_Shape := V;
                     elsif N = "inertia" then S.Inertia := S.Inertia * V;
                     elsif N = "rear_mu" then S.Rear_Mu := V;
                     elsif N = "rear_stiff" then S.Rear_Stiff := V;
                     elsif N = "arb_f" then S.Arb_F := S.Arb_F * V;
                     elsif N = "arb_r" then S.Arb_R := S.Arb_R * V;
                     elsif N = "lock" then S.Steer_Lock := V;
                     else raise Constraint_Error with "unknown " & N;
                     end if;
                  end;
               end if;
            end loop;
            Start := I + 1;
         end if;
      end loop;
   end Apply;

begin
   Track.Load (Track.Track_Id'First);
   for K in Car_Kind loop
      Table (K, "as built", Spec_Of (K));
      for I in 1 .. Ada.Command_Line.Argument_Count loop
         declare
            S : Spec := Spec_Of (K);
         begin
            Apply (S, Ada.Command_Line.Argument (I));
            Table (K, Ada.Command_Line.Argument (I), S);
         end;
      end loop;
   end loop;
end Catch;
