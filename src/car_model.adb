--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

with Math3D;

package body Car_Model is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use Mesh;
   use Vehicle;

   Pi : constant := 3.14159_26535;

   --  The body is lofted through cross sections from the nose to the tail.
   type Station is record
      Z      : Float;   --  along the car, forward is -Z
      W      : Float;   --  half width at the shoulder
      Bottom : Float;
      Belt   : Float;   --  top of the doors, the hood, the rear deck
      Roof   : Float;   --  top of the greenhouse (= Belt where there is none)
      Roof_W : Float;
   end record;

   type Station_Array is array (Positive range <>) of Station;

   Profile : constant Station_Array :=
     ((-2.32, 0.55, 0.26, 0.40, 0.40, 0.30),
      (-2.26, 0.75, 0.20, 0.54, 0.54, 0.50),
      (-2.10, 0.86, 0.17, 0.62, 0.62, 0.62),
      (-1.80, 0.93, 0.15, 0.70, 0.70, 0.68),
      (-1.40, 0.96, 0.15, 0.76, 0.76, 0.70),
      (-1.05, 0.96, 0.15, 0.80, 0.80, 0.70),
      (-0.80, 0.96, 0.15, 0.84, 0.86, 0.66),   --  base of the windscreen
      (-0.45, 0.96, 0.15, 0.87, 1.05, 0.62),
      (-0.10, 0.96, 0.15, 0.88, 1.22, 0.58),   --  top of the windscreen
      ( 0.25, 0.97, 0.15, 0.88, 1.25, 0.57),
      ( 0.55, 0.98, 0.15, 0.89, 1.22, 0.57),
      ( 0.90, 0.99, 0.16, 0.90, 1.11, 0.58),   --  rear window
      ( 1.25, 0.98, 0.17, 0.90, 0.98, 0.60),
      ( 1.55, 0.97, 0.18, 0.90, 0.92, 0.64),   --  the deck
      ( 1.85, 0.95, 0.21, 0.90, 0.90, 0.70),
      ( 2.08, 0.93, 0.26, 0.90, 0.90, 0.70),
      ( 2.24, 0.88, 0.32, 0.89, 0.89, 0.68),
      ( 2.30, 0.80, 0.38, 0.87, 0.87, 0.62));

   Arch_R       : constant := 0.40;
   Last_Profile_Z : constant := 2.30;

   function Mix (A, B, T : Float) return Float is (A + (B - A) * T);

   --  A station anywhere along the car, by interpolation
   function Base_Z (Z : Float) return Station is
   begin
      for I in Profile'First .. Profile'Last - 1 loop
         if Z <= Profile (I + 1).Z then
            declare
               A : Station renames Profile (I);
               B : Station renames Profile (I + 1);
               T0 : constant Float := Float'Max (0.0, (Z - A.Z) / (B.Z - A.Z));
               T : constant Float := T0 * T0 * (3.0 - 2.0 * T0) * 0.35 + T0 * 0.65;
            begin
               return (Z, Mix (A.W, B.W, T), Mix (A.Bottom, B.Bottom, T), Mix (A.Belt, B.Belt, T),
                       Mix (A.Roof, B.Roof, T), Mix (A.Roof_W, B.Roof_W, T));
            end;
         end if;
      end loop;
      return Profile (Profile'Last);
   end Base_Z;

   --  The cars are one family, each its own shape: the GT3 low with flared
   --  arches, the R4 a tall hatchback, its roof running on to a steep tail
   function At_Z (Z : Float; Kind : Car_Kind) return Station is
      S : Station := Base_Z (Z);
      Sp : constant Spec := Spec_Of (Kind);
      function Near (Axle, Reach : Float) return Float is
        (Exp (-((Z - Axle) / Reach) ** 2));
   begin
      case Kind is
         when Road_GT =>
            null;
         when Race_GT3 =>
            S.W := S.W + 0.085 * (Near (-Sp.A, 0.62) + Near (Sp.B, 0.66)) + 0.02;
            S.Roof_W := S.Roof_W - 0.02;
            if S.Roof > S.Belt then
               S.Roof := S.Belt + (S.Roof - S.Belt) * 0.86;
            end if;
            S.Bottom := S.Bottom - 0.03;
         when Classic_RWD =>
            --  Narrow and upright, a boxy little saloon
            S.W := S.W * 0.90;
            S.Roof_W := S.Roof_W * 0.95;
            if S.Roof > S.Belt then
               S.Roof := S.Belt + (S.Roof - S.Belt) * 1.05;
            end if;
         when Hyper_AWD =>
            --  Low, with big haunches and a cab pushed forward
            S.W := S.W + 0.07 + 0.1 * Near (Sp.B, 0.72) + 0.06 * Near (-Sp.A, 0.55);
            S.Belt := S.Belt - 0.06 * Near (-Sp.A, 1.0);
            if S.Roof > S.Belt then
               S.Roof := S.Belt + (S.Roof - S.Belt) * 0.7;
            end if;
            S.Roof_W := S.Roof_W - 0.04;
            S.Bottom := S.Bottom - 0.05;
         when Rally_4WD =>
            S.W := S.W * 0.97 + 0.05 * (Near (-Sp.A, 0.55) + Near (Sp.B, 0.55));
            if Z > 0.25 then
               declare
                  T : constant Float := Float'Min (1.0, (Z - 0.25) / 1.2);
                  Fall : constant Float :=
                    Float'Max (0.0, (Z - 1.45) / (Last_Profile_Z - 1.45));
                  Top : constant Float := 1.25 - 0.015 * T;
               begin
                  --  Roof carried back, then down the tailgate
                  S.Roof := Float'Max (S.Belt, Top - 0.38 * Fall ** 1.3);
                  S.Roof_W := 0.57 + 0.02 * T - 0.08 * Fall;
               end;
            end if;
      end case;
      return S;
   end At_Z;

   Ring_Points : constant := 12;
   Fine : constant := 2 * Ring_Points - 1;   --  with a point between each two

   --  The right half of a cross section, from under the car over to the top
   function Ring_Point (S : Station; K : Natural) return Vec3 is
      H : constant Float := S.Belt - S.Bottom;
      Has_Roof : constant Boolean := S.Roof > S.Belt + 0.015;
      Top_Y : constant Float := Float'Max (S.Roof, S.Belt);
   begin
      return
        (case K is
            when 0  => (0.0, S.Bottom, S.Z),
            when 1  => (S.W * 0.80, S.Bottom, S.Z),
            when 2  => (S.W * 0.96, S.Bottom + H * 0.08, S.Z),
            when 3  => (S.W, S.Bottom + H * 0.25, S.Z),
            when 4  => (S.W, S.Bottom + H * 0.50, S.Z),
            when 5  => (S.W * 0.995, S.Bottom + H * 0.75, S.Z),
            when 6  => (S.W * 0.96, S.Bottom + H * 0.93, S.Z),
            when 7  => (S.W * 0.90, S.Belt, S.Z),
            when 8  =>
              (if Has_Roof
               then (Mix (S.W * 0.90, S.Roof_W, 0.5), Mix (S.Belt, S.Roof, 0.55), S.Z)
               else (S.W * 0.70, S.Belt + 0.005, S.Z)),
            when 9  =>
              (if Has_Roof
               then (S.Roof_W, Top_Y - 0.015, S.Z)
               else (S.W * 0.45, S.Belt + 0.01, S.Z)),
            when 10 => (S.Roof_W * 0.55, Top_Y + 0.003, S.Z),
            when others => (0.0, Top_Y + 0.006, S.Z));
   end Ring_Point;

   type Float_Pair is array (1 .. 2) of Float;

   procedure Loft (B : in out Builder; Kind : Car_Kind) is
      Slices : constant := 90;
      First_Z : constant Float := Profile (Profile'First).Z;
      Last_Z : constant Float := Profile (Profile'Last).Z;
      type Grid is array (0 .. Slices, 0 .. Fine - 1) of Vec3;
      type Grid_Access is access Grid;
      P : constant Grid_Access := new Grid;
      N : constant Grid_Access := new Grid;
      Black : constant Color := (0.02, 0.02, 0.025);
      Front_Axle_Z : constant Float := -Spec_Of (Kind).A;
      Rear_Axle_Z  : constant Float := Spec_Of (Kind).B;

      function Z_Of (I : Natural) return Float is
        (First_Z + (Last_Z - First_Z) * Float (I) / Float (Slices));

      --  The wheel arch: no bodywork here
      function In_Arch (C : Vec3) return Boolean is
        (C.X > 0.55
         and then (Sqrt ((C.Z - Front_Axle_Z) ** 2 + (C.Y - 0.34) ** 2) < Arch_R
                   or else Sqrt ((C.Z - Rear_Axle_Z) ** 2 + (C.Y - 0.34) ** 2) < Arch_R));

      procedure Face (A, C, D, E : Vec3; NA, NC, ND, NE : Vec3; Col : Color; Mat : Float) is
      begin
         Add (B, (A, NA, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
         Add (B, (C, NC, Col.R, Col.G, Col.B, Mat, 1.0, 0.0));
         Add (B, (D, ND, Col.R, Col.G, Col.B, Mat, 1.0, 1.0));
         Add (B, (A, NA, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
         Add (B, (D, ND, Col.R, Col.G, Col.B, Mat, 1.0, 1.0));
         Add (B, (E, NE, Col.R, Col.G, Col.B, Mat, 0.0, 1.0));
      end Face;

      function Mirror (V : Vec3) return Vec3 is ((-V.X, V.Y, V.Z));
   begin
      for I in 0 .. Slices loop
         declare
            S : constant Station := At_Z (Z_Of (I), Kind);
         begin
            --  Every other point between those of the section, on a curve
            --  through them: round shoulders instead of facets
            for F in 0 .. Fine - 1 loop
               if F mod 2 = 0 then
                  P (I, F) := Ring_Point (S, F / 2);
               else
                  declare
                     K : constant Natural := F / 2;
                     function R (J : Integer) return Vec3 is
                       (Ring_Point (S, Natural (Integer'Max (0, Integer'Min (Ring_Points - 1, J)))));
                     P0 : constant Vec3 := R (K - 1);
                     P1 : constant Vec3 := R (K);
                     P2 : constant Vec3 := R (K + 1);
                     P3 : constant Vec3 := R (K + 2);
                  begin
                     P (I, F) := 0.5625 * (P1 + P2) - 0.0625 * (P0 + P3);
                  end;
               end if;
            end loop;
         end;
      end loop;
      --  Smooth normals: pointing out of the grid
      for I in 0 .. Slices loop
         for K in 0 .. Fine - 1 loop
            declare
               A : constant Vec3 := P (Natural'Min (I + 1, Slices), K)
                 - P (Natural'Max (I, 1) - 1, K);
               C : constant Vec3 := P (I, Natural'Min (K + 1, Fine - 1))
                 - P (I, Natural'Max (K, 1) - 1);
               Nr : constant Vec3 := Cross (C, A);
            begin
               N (I, K) := Normalize (Nr + Vec3'(0.0, 1.0E-5, 0.0));
            end;
         end loop;
      end loop;

      for I in 0 .. Slices - 1 loop
         declare
            Zm : constant Float := Z_Of (I) + (Last_Z - First_Z) / Float (Slices) * 0.5;
            S : constant Station := At_Z (Zm, Kind);
            Cabin : constant Boolean := S.Roof > S.Belt + 0.05;
         begin
            for F in 0 .. Fine - 2 loop
               declare
                  K : constant Natural := F / 2;   --  the section's own band
                  P00 : constant Vec3 := P (I, F);
                  P10 : constant Vec3 := P (I + 1, F);
                  P11 : constant Vec3 := P (I + 1, F + 1);
                  P01 : constant Vec3 := P (I, F + 1);
                  N00 : constant Vec3 := N (I, F);
                  N10 : constant Vec3 := N (I + 1, F);
                  N11 : constant Vec3 := N (I + 1, F + 1);
                  N01 : constant Vec3 := N (I, F + 1);
                  Mid : constant Vec3 := 0.25 * (P00 + P10 + P11 + P01);
                  Is_Under : constant Boolean := K = 0;
                  --  Side windows above the belt, between the pillars
                  Side_Glass : constant Boolean :=
                    Cabin and then K in 7 .. 8 and then Zm > -0.62
                    and then Zm < (if Kind = Rally_4WD then 1.62 else 1.05);
                  Windscreen : constant Boolean :=
                    Cabin and then K >= 8 and then Zm > -0.80 and then Zm < -0.12
                    and then Mid.X < 0.55;
                  Rear_Glass : constant Boolean :=
                    Cabin and then K >= 8
                    and then Zm > (if Kind = Rally_4WD then 1.68 else 0.62)
                    and then Zm < (if Kind = Rally_4WD then 2.14 else 1.28)
                    and then Mid.X < 0.48;
                  Grille : constant Boolean :=
                    Zm < -2.16 and then K in 3 .. 4 and then Mid.X < 0.62;
                  Tail_Lamp : constant Boolean :=
                    Zm > 2.12 and then K in 5 .. 6 and then Mid.X > 0.28;
                  Head_Lamp : constant Boolean :=
                    Zm < -1.95 and then Zm > -2.2 and then K in 6 .. 8 and then Mid.X > 0.42;
                  Col : Color := (0.0, 0.0, 0.0);
                  Mat : Float := Mesh.Paint;
               begin
                  if Is_Under then
                     Col := Black;
                     Mat := Plain;
                  elsif Tail_Lamp then
                     Col := (0.8, 0.02, 0.02);
                     Mat := Lamp;
                  elsif Head_Lamp then
                     Col := (0.9, 0.92, 1.0);
                     Mat := Glow;
                  elsif Grille then
                     Col := Black;
                     Mat := Plain;
                  elsif Side_Glass or else Windscreen or else Rear_Glass then
                     Col := (0.02, 0.03, 0.04);
                     Mat := Mesh.Glass;
                  elsif K <= 1 then
                     Col := Black;
                     Mat := Plain;
                  end if;
                  if Mat = Mesh.Paint and then K in 2 .. 6 then
                     --  The flanks: the shader cuts the round wheel arches and
                     --  draws the door lines, knowing where on the car it is
                     declare
                        Fl : constant Color := (Front_Axle_Z, Rear_Axle_Z, 1.0);
                     begin
                        Add (B, (P00, N00, Fl.R, Fl.G, Fl.B, Mat, P00.Z, P00.Y));
                        Add (B, (P01, N01, Fl.R, Fl.G, Fl.B, Mat, P01.Z, P01.Y));
                        Add (B, (P11, N11, Fl.R, Fl.G, Fl.B, Mat, P11.Z, P11.Y));
                        Add (B, (P00, N00, Fl.R, Fl.G, Fl.B, Mat, P00.Z, P00.Y));
                        Add (B, (P11, N11, Fl.R, Fl.G, Fl.B, Mat, P11.Z, P11.Y));
                        Add (B, (P10, N10, Fl.R, Fl.G, Fl.B, Mat, P10.Z, P10.Y));
                        Add (B, (Mirror (P00), Mirror (N00), Fl.R, Fl.G, Fl.B, Mat, P00.Z, P00.Y));
                        Add (B, (Mirror (P10), Mirror (N10), Fl.R, Fl.G, Fl.B, Mat, P10.Z, P10.Y));
                        Add (B, (Mirror (P11), Mirror (N11), Fl.R, Fl.G, Fl.B, Mat, P11.Z, P11.Y));
                        Add (B, (Mirror (P00), Mirror (N00), Fl.R, Fl.G, Fl.B, Mat, P00.Z, P00.Y));
                        Add (B, (Mirror (P11), Mirror (N11), Fl.R, Fl.G, Fl.B, Mat, P11.Z, P11.Y));
                        Add (B, (Mirror (P01), Mirror (N01), Fl.R, Fl.G, Fl.B, Mat, P01.Z, P01.Y));
                     end;
                  elsif not In_Arch (Mid) then
                     --  Right side: slices run along +Z, rings go up and over
                     Face (P00, P01, P11, P10, N00, N01, N11, N10, Col, Mat);
                     Face (Mirror (P00), Mirror (P10), Mirror (P11), Mirror (P01),
                           Mirror (N00), Mirror (N10), Mirror (N11), Mirror (N01), Col, Mat);
                  end if;
               end;
            end loop;
         end;
      end loop;

      --  The nose and the tail close the loft
      for End_I in 0 .. 1 loop
         declare
            I : constant Natural := (if End_I = 0 then 0 else Slices);
            Out_N : constant Vec3 := (0.0, 0.0, (if End_I = 0 then -1.0 else 1.0));
            Col : constant Color := (if End_I = 0 then Black else (0.0, 0.0, 0.0));
            Cap_Mat : constant Float := (if End_I = 0 then Plain else Mesh.Paint);
            Mid : constant Vec3 := (0.0, 0.5 * (P (I, 0).Y + P (I, Fine - 1).Y), P (I, 0).Z);
         begin
            for K in 0 .. Fine - 2 loop
               if End_I = 0 then
                  Add (B, (Mid, Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (P (I, K + 1), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (P (I, K), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (Mid, Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (Mirror (P (I, K)), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (Mirror (P (I, K + 1)), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
               else
                  Add (B, (Mid, Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (P (I, K), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (P (I, K + 1), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (Mid, Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (Mirror (P (I, K + 1)), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
                  Add (B, (Mirror (P (I, K)), Out_N, Col.R, Col.G, Col.B, Cap_Mat, 0.0, 0.0));
               end if;
            end loop;
         end;
      end loop;

      --  Tail lamps, number plate, and the bumper below them
      Box (B, (-0.76, 0.70, 2.26), (-0.30, 0.80, 2.32), (0.8, 0.02, 0.02), Lamp);
      Box (B, (0.30, 0.70, 2.26), (0.76, 0.80, 2.32), (0.8, 0.02, 0.02), Lamp);
      Box (B, (-0.30, 0.74, 2.27), (0.30, 0.78, 2.32), (0.35, 0.01, 0.01), Lamp);
      Box (B, (-0.2, 0.52, 2.27), (0.2, 0.62, 2.325), (0.75, 0.75, 0.72));
      Box (B, (-0.70, 0.30, 2.14), (0.70, 0.47, 2.33), (0.015, 0.015, 0.017));
      --  Front: the air intake and the running lights
      Box (B, (-0.56, 0.24, -2.33), (0.56, 0.4, -2.2), (0.01, 0.01, 0.012));
      Box (B, (-0.8, 0.52, -2.16), (-0.52, 0.56, -2.0), (1.0, 1.0, 1.1), Glow);
      Box (B, (0.52, 0.52, -2.16), (0.8, 0.56, -2.0), (1.0, 1.0, 1.1), Glow);

      --  Inside the arches and under the car: black, so nothing shows through
      Box (B, (-0.58, 0.14, -2.05), (0.58, 0.62, 2.0), Black);
      --  (stepped, to stay under the hood where it falls away forward)
      for Axle of Float_Pair'(Front_Axle_Z, Rear_Axle_Z) loop
         Box (B, (-0.90, 0.15, Axle - 0.43), (-0.56, 0.62, Axle + 0.43), Black);
         Box (B, (0.56, 0.15, Axle - 0.43), (0.90, 0.62, Axle + 0.43), Black);
         Box (B, (-0.90, 0.62, Axle - 0.30), (-0.56, 0.745, Axle + 0.30), Black);
         Box (B, (0.56, 0.62, Axle - 0.30), (0.90, 0.745, Axle + 0.30), Black);
      end loop;

      --  Brake calipers, seen through the spokes: red on the fast ones
      declare
         Sp : constant Spec := Spec_Of (Kind);
         Caliper : constant Color :=
           (if Kind in Race_GT3 | Hyper_AWD then (0.62, 0.05, 0.03)
            elsif Kind = Rally_4WD then (0.75, 0.55, 0.05) else (0.05, 0.05, 0.06));
      begin
         for Corner in 0 .. 3 loop
            declare
               Z : constant Float := (if Corner < 2 then Front_Axle_Z else Rear_Axle_Z);
               Half : constant Float := (if Corner < 2 then Sp.Track_F else Sp.Track_R) / 2.0;
               X : constant Float := (if Corner mod 2 = 0 then -1.0 else 1.0) * (Half - 0.13);
               Y : constant Float := Sp.Radius;
            begin
               Box (B, (X - 0.035, Y + 0.02, Z - 0.17), (X + 0.035, Y + 0.17, Z - 0.02), Caliper);
            end;
         end loop;
      end;

      --  Door mirrors
      for Sg in 0 .. 1 loop
         declare
            X : constant Float := (if Sg = 0 then -1.0 else 1.0);
         begin
            Box (B, (Float'Min (X * 0.92, X * 1.08), 0.90, -0.68),
                 (Float'Max (X * 0.92, X * 1.08), 1.0, -0.56), (0.05, 0.05, 0.05));
         end;
      end loop;

      case Kind is
         when Rally_4WD =>
            --  Mud flaps, a roof vent, spot lamps low on the nose, a rear
            --  spoiler and a sump guard
            for Sg in 0 .. 1 loop
               declare
                  X0 : constant Float := (if Sg = 0 then -0.92 else 0.62);
               begin
                  Box (B, (X0, 0.06, Rear_Axle_Z + 0.38), (X0 + 0.30, 0.42, Rear_Axle_Z + 0.40), (0.05, 0.05, 0.06));
                  Box (B, (X0, 0.06, Front_Axle_Z + 0.42), (X0 + 0.30, 0.34, Front_Axle_Z + 0.44), (0.05, 0.05, 0.06));
               end;
            end loop;
            Box (B, (-0.14, 1.235, 0.0), (0.14, 1.285, 0.28), (0.12, 0.13, 0.15));
            for K in 0 .. 3 loop
               declare
                  X0 : constant Float := -0.50 + Float (K) * 0.28;
               begin
                  Box (B, (X0, 0.44, -2.40), (X0 + 0.16, 0.56, -2.31), (1.0, 1.0, 0.85), Glow);
               end;
            end loop;
            Box (B, (-0.62, 1.21, 1.52), (0.62, 1.25, 1.92), (0.04, 0.04, 0.05));
            Box (B, (-0.60, 0.11, -2.30), (0.60, 0.15, -1.0), (0.32, 0.33, 0.35), Metal);
            Box (B, (-0.62, 0.28, 2.23), (-0.42, 0.38, 2.34), (0.12, 0.12, 0.13), Metal);
         when Classic_RWD =>
            --  Chrome bumpers and a single exhaust
            Box (B, (-0.80, 0.34, 2.28), (0.80, 0.44, 2.36), (0.5, 0.5, 0.52), Metal);
            Box (B, (-0.80, 0.30, -2.40), (0.80, 0.40, -2.30), (0.5, 0.5, 0.52), Metal);
            Box (B, (0.42, 0.24, 2.23), (0.54, 0.32, 2.40), (0.15, 0.15, 0.16), Metal);
         when Hyper_AWD =>
            --  Splitter, diffuser, a low wing and side intakes
            Box (B, (-1.0, 0.07, -2.44), (1.0, 0.10, -1.9), Black);
            Box (B, (-0.8, 0.14, 2.1), (0.8, 0.28, 2.38), Black);
            Box (B, (-1.05, 0.92, 2.08), (1.05, 0.95, 2.42), (0.03, 0.03, 0.035));
            Box (B, (-0.7, 0.78, 2.2), (-0.65, 0.93, 2.3), (0.03, 0.03, 0.035));
            Box (B, (0.65, 0.78, 2.2), (0.7, 0.93, 2.3), (0.03, 0.03, 0.035));
            Box (B, (-1.14, 0.42, 0.50), (-1.04, 0.62, 0.90), Black);
            Box (B, (1.04, 0.42, 0.50), (1.14, 0.62, 0.90), Black);
         when Road_GT =>
            --  Exhausts
            Box (B, (-0.62, 0.28, 2.23), (-0.42, 0.38, 2.34), (0.12, 0.12, 0.13), Metal);
            Box (B, (0.42, 0.28, 2.23), (0.62, 0.38, 2.34), (0.12, 0.12, 0.13), Metal);
         when Race_GT3 =>
            --  Splitter, wing, diffuser
            Box (B, (-0.98, 0.10, -2.42), (0.98, 0.14, -1.9), Black);
            Box (B, (-1.0, 1.22, 2.0), (1.0, 1.26, 2.42), (0.03, 0.03, 0.035));
            Box (B, (-1.02, 1.1, 1.98), (-0.98, 1.32, 2.46), (0.03, 0.03, 0.035));
            Box (B, (0.98, 1.1, 1.98), (1.02, 1.32, 2.46), (0.03, 0.03, 0.035));
            Box (B, (-0.55, 0.88, 2.1), (-0.5, 1.24, 2.22), (0.03, 0.03, 0.035));
            Box (B, (0.5, 0.88, 2.1), (0.55, 1.24, 2.22), (0.03, 0.03, 0.035));
            Box (B, (-0.7, 0.2, 2.1), (0.7, 0.29, 2.36), Black);
      end case;
   end Loft;

   ---------------------------------------------------------------------------
   --  Wheel
   ---------------------------------------------------------------------------

   procedure Wheel (B : in out Builder; Radius, Width : Float) is
      Segs : constant := 28;
      Tyre : constant Color := (0.022, 0.022, 0.024);
      Rim_C : constant Color := (0.55, 0.56, 0.58);
      Disc_C : constant Color := (0.30, 0.30, 0.31);
      Rim_R : constant Float := Radius * 0.66;
      HW : constant Float := Width / 2.0;

      function Pt (X, R : Float; A : Float) return Vec3 is
        ((X, R * Sin (A), R * Cos (A)));

      procedure Side (X, Nx : Float) is
         N : constant Vec3 := (Nx, 0.0, 0.0);
      begin
         for S in 0 .. Segs - 1 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (S) / Float (Segs);
               A1 : constant Float := 2.0 * Pi * Float (S + 1) / Float (Segs);
               procedure Ring (R0, R1, X0, X1 : Float; Col : Color; Mat : Float) is
                  P0 : constant Vec3 := Pt (X0, R0, A0);
                  P1 : constant Vec3 := Pt (X1, R1, A0);
                  P2 : constant Vec3 := Pt (X1, R1, A1);
                  P3 : constant Vec3 := Pt (X0, R0, A1);
               begin
                  if Nx > 0.0 then
                     Add (B, (P0, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P1, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P2, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P0, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P2, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P3, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                  else
                     Add (B, (P0, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P2, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P1, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P0, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P3, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                     Add (B, (P2, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
                  end if;
               end Ring;
            begin
               Ring (Rim_R, Radius * 0.97, X, X, Tyre, Rubber);
               Ring (Rim_R * 0.9, Rim_R, X - Nx * 0.03, X, Rim_C, Metal);
               Ring (0.0, Rim_R * 0.9, X - Nx * 0.08, X - Nx * 0.08, Disc_C, Metal);
            end;
         end loop;
      end Side;
   begin
      for S in 0 .. Segs - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (S) / Float (Segs);
            A1 : constant Float := 2.0 * Pi * Float (S + 1) / Float (Segs);
            N0 : constant Vec3 := (0.0, Sin (A0), Cos (A0));
            N1 : constant Vec3 := (0.0, Sin (A1), Cos (A1));
         begin
            --  Tread, with the shoulders rounded off
            Add (B, (Pt (-HW, Radius, A0), N0, Tyre.R, Tyre.G, Tyre.B, Rubber, 0.0, 0.0));
            Add (B, (Pt (HW, Radius, A1), N1, Tyre.R, Tyre.G, Tyre.B, Rubber, 0.0, 0.0));
            Add (B, (Pt (HW, Radius, A0), N0, Tyre.R, Tyre.G, Tyre.B, Rubber, 0.0, 0.0));
            Add (B, (Pt (-HW, Radius, A0), N0, Tyre.R, Tyre.G, Tyre.B, Rubber, 0.0, 0.0));
            Add (B, (Pt (-HW, Radius, A1), N1, Tyre.R, Tyre.G, Tyre.B, Rubber, 0.0, 0.0));
            Add (B, (Pt (HW, Radius, A1), N1, Tyre.R, Tyre.G, Tyre.B, Rubber, 0.0, 0.0));
         end;
      end loop;
      Side (HW, 1.0);
      Side (-HW, -1.0);
      --  Five spokes, both faces (seen from either side of the car)
      for Sg in 0 .. 1 loop
         declare
            X : constant Float := (if Sg = 0 then HW - 0.04 else -HW + 0.04);
         begin
            for Sp in 0 .. 4 loop
               declare
                  A : constant Float := 2.0 * Pi * Float (Sp) / 5.0;
                  Dir : constant Vec3 := (0.0, Sin (A), Cos (A));
               begin
                  Oriented_Box (B, Vec3'(X, 0.0, 0.0) + (Rim_R * 0.5) * Dir, Dir,
                                (1.0, 0.0, 0.0), Rim_R * 0.5, 0.03, 0.035, Rim_C, Metal);
               end;
            end loop;
            Oriented_Box (B, (X, 0.0, 0.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
                          0.06, 0.04, 0.06, Rim_C, Metal);
         end;
      end loop;
   end Wheel;

   ---------------------------------------------------------------------------
   --  From the driver's seat
   ---------------------------------------------------------------------------

   procedure Cockpit (B : in out Builder; Kind : Car_Kind) is
      Dash : constant Color := (0.028, 0.027, 0.027);
      Trim : constant Color := (0.085, 0.08, 0.078);
      Pillar : constant Color := (0.03, 0.03, 0.032);
      Soft : constant Color := (0.14, 0.125, 0.11);
      Left_X : constant := -0.86;
      Right_X : constant := 0.86;
   begin
      --  The dash top, and the hood seen beyond the glass is the real body
      Quad (B, (Left_X, 0.79, -0.40), (Right_X, 0.79, -0.40),
            (Right_X, 0.81, -0.80), (Left_X, 0.81, -0.80), Dash);
      Quad (B, (Left_X, 0.79, -0.40), (Left_X, 0.45, -0.32), (Right_X, 0.45, -0.32),
            (Right_X, 0.79, -0.40), Trim);
      --  The instrument binnacle, in the opening of the wheel: a rev counter,
      --  a speedometer and the gear between them, drawn live by the shader
      Box (B, (Steering_X - 0.15, 0.78, -0.60), (Steering_X + 0.15, 0.925, -0.50), Dash);
      Oriented_Box (B, (Steering_X, 0.933, -0.52), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.155, 0.008, 0.05, Pillar);
      declare
         N : constant Vec3 := (0.0, 0.0, 1.0);
         procedure Dial (X0, Y0, Half, Which : Float) is
            Z : constant := -0.4985;
            Lo_L : constant Vec3 := (Steering_X + X0 - Half, Y0 - Half, Z);
            Lo_R : constant Vec3 := (Steering_X + X0 + Half, Y0 - Half, Z);
            Hi_R : constant Vec3 := (Steering_X + X0 + Half, Y0 + Half, Z);
            Hi_L : constant Vec3 := (Steering_X + X0 - Half, Y0 + Half, Z);
         begin
            Add (B, (Lo_L, N, Which, 0.0, 0.0, Mesh.Dial, 0.0, 0.0));
            Add (B, (Lo_R, N, Which, 0.0, 0.0, Mesh.Dial, 1.0, 0.0));
            Add (B, (Hi_R, N, Which, 0.0, 0.0, Mesh.Dial, 1.0, 1.0));
            Add (B, (Lo_L, N, Which, 0.0, 0.0, Mesh.Dial, 0.0, 0.0));
            Add (B, (Hi_R, N, Which, 0.0, 0.0, Mesh.Dial, 1.0, 1.0));
            Add (B, (Hi_L, N, Which, 0.0, 0.0, Mesh.Dial, 0.0, 1.0));
         end Dial;
      begin
         Dial (-0.088, 0.858, 0.058, 0.0);
         Dial (0.088, 0.858, 0.058, 1.0);
         Dial (0.0, 0.858, 0.027, 2.0);
      end;

      --  Doors
      Box (B, (-0.98, 0.3, -0.45), (-0.82, 0.86, 1.0), Trim);
      Box (B, (0.82, 0.3, -0.45), (0.98, 0.86, 1.0), Trim);
      Box (B, (-0.96, 0.62, -0.1), (-0.78, 0.68, 0.45), Soft);
      Box (B, (0.78, 0.62, -0.1), (0.96, 0.68, 0.45), Soft);

      --  Centre console
      Box (B, (-0.14, 0.3, -0.4), (0.14, 0.58, 0.55), Trim);
      --  Seats
      Box (B, (-0.60, 0.25, 0.22), (-0.14, 0.42, 0.75), Soft);
      Box (B, (-0.60, 0.42, 0.55), (-0.14, 1.08, 0.75), Soft);
      Box (B, (0.14, 0.25, 0.22), (0.60, 0.42, 0.75), Soft);
      Box (B, (0.14, 0.42, 0.55), (0.60, 1.08, 0.75), Soft);

      --  Roof lining, seen from below, and the pillars
      Quad (B, (-0.62, 1.20, -0.14), (0.62, 1.20, -0.14), (0.62, 1.20, 1.0), (-0.62, 1.20, 1.0), Soft);
      Quad (B, (-0.68, 1.195, -0.14), (0.68, 1.195, -0.14), (0.62, 1.2, -0.20), (-0.62, 1.2, -0.20), Pillar);
      --  A pillars, both sides
      Oriented_Box (B, (-0.84, 1.0, -0.47), (0.17, 0.37, 0.36), (0.0, 1.0, 0.0), 0.34, 0.02, 0.03, Pillar);
      Oriented_Box (B, (0.84, 1.0, -0.47), (-0.17, 0.37, 0.36), (0.0, 1.0, 0.0), 0.34, 0.02, 0.03, Pillar);
      --  B pillars and the door tops
      Box (B, (-0.84, 0.86, 0.72), (-0.72, 1.2, 0.9), Pillar);
      Box (B, (0.72, 0.86, 0.72), (0.84, 1.2, 0.9), Pillar);
      Box (B, (-0.90, 0.86, -0.45), (-0.82, 0.875, 0.72), Pillar);
      Box (B, (0.82, 0.86, -0.45), (0.90, 0.875, 0.72), Pillar);
      --  Rear of the cabin
      Quad (B, (-0.8, 0.86, 1.1), (0.8, 0.86, 1.1), (0.55, 1.18, 1.0), (-0.55, 1.18, 1.0), Pillar);

      if Kind in Race_GT3 | Rally_4WD then
         --  Roll cage
         Oriented_Box (B, (0.0, 1.13, 0.05), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.68, 0.025, 0.025, (0.6, 0.6, 0.62));
         Oriented_Box (B, (-0.55, 1.0, 0.45), (0.1, 0.1, 1.0), (0.0, 1.0, 0.0), 0.6, 0.025, 0.025, (0.6, 0.6, 0.62));
         Oriented_Box (B, (0.55, 1.0, 0.45), (-0.1, 0.1, 1.0), (0.0, 1.0, 0.0), 0.6, 0.025, 0.025, (0.6, 0.6, 0.62));
      end if;
   end Cockpit;

   --  The steering wheel: a rim round the Z axis, the driver looks along -Z
   procedure Steering_Wheel (B : in out Builder; Kind : Car_Kind) is
      R : constant Float := (if Kind in Race_GT3 | Hyper_AWD then 0.155 else 0.185);
      Th : constant := 0.016;
      Segs : constant := 36;
      Sides : constant := 8;
      Col : constant Color := (0.025, 0.025, 0.028);
      Spoke : constant Color := (0.08, 0.08, 0.085);
   begin
      for S in 0 .. Segs - 1 loop
         for K in 0 .. Sides - 1 loop
            declare
               A0 : constant Float := 2.0 * Pi * Float (S) / Float (Segs);
               A1 : constant Float := 2.0 * Pi * Float (S + 1) / Float (Segs);
               B0 : constant Float := 2.0 * Pi * Float (K) / Float (Sides);
               B1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (Sides);
               function P (A, C : Float) return Vec3 is
                 ((R + Th * Cos (C)) * Sin (A), (R + Th * Cos (C)) * Cos (A), Th * Sin (C));
               function Nn (A, C : Float) return Vec3 is
                 (Cos (C) * Sin (A), Cos (C) * Cos (A), Sin (C));
               Top : constant Boolean := S in 0 .. 1 or else S = Segs - 1;
               C : constant Color := (if Top then (0.75, 0.05, 0.03) else Col);
            begin
               Add (B, (P (A0, B0), Nn (A0, B0), C.R, C.G, C.B, Plain, 0.0, 0.0));
               Add (B, (P (A1, B0), Nn (A1, B0), C.R, C.G, C.B, Plain, 0.0, 0.0));
               Add (B, (P (A1, B1), Nn (A1, B1), C.R, C.G, C.B, Plain, 0.0, 0.0));
               Add (B, (P (A0, B0), Nn (A0, B0), C.R, C.G, C.B, Plain, 0.0, 0.0));
               Add (B, (P (A1, B1), Nn (A1, B1), C.R, C.G, C.B, Plain, 0.0, 0.0));
               Add (B, (P (A0, B1), Nn (A0, B1), C.R, C.G, C.B, Plain, 0.0, 0.0));
            end;
         end loop;
      end loop;
      --  Spokes and hub
      Box (B, (-R, -0.015, -0.012), (R, 0.015, 0.012), Spoke);
      Box (B, (-0.015, -R, -0.012), (0.015, 0.0, 0.012), Spoke);
      Box (B, (-0.05, -0.05, -0.03), (0.05, 0.04, 0.02), Spoke);
      --  Paddles behind the rim
      Box (B, (0.07, -0.02, -0.04), (0.17, 0.05, -0.03), (0.5, 0.5, 0.52), Metal);
      Box (B, (-0.17, -0.02, -0.04), (-0.07, 0.05, -0.03), (0.5, 0.5, 0.52), Metal);
   end Steering_Wheel;

   procedure Build is
   begin
      for K in Car_Kind loop
         declare
            S : constant Spec := Spec_Of (K);
            Body_B, Wheel_B, Cock_B, Steer_B : Builder;
         begin
            Loft (Body_B, K);
            Wheel (Wheel_B, S.Radius, (case K is when Race_GT3 | Hyper_AWD => 0.30,
                                                  when Classic_RWD => 0.19,
                                                  when others => 0.26));
            Cockpit (Cock_B, K);
            Steering_Wheel (Steer_B, K);
            Meshes (K) := (Upload (Body_B), Upload (Wheel_B), Upload (Cock_B), Upload (Steer_B));
         end;
      end loop;
   end Build;

end Car_Model;
