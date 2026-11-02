--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;

with Math3D;
with Track;

package body Scenery is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use Mesh;

   Pi : constant := 3.14159_26535;

   function Clamp (V, Lo, Hi : Float) return Float is
     (Float'Max (Lo, Float'Min (Hi, V)));

   function Smooth (A, B, V : Float) return Float is
      T : constant Float := Clamp ((V - A) / (B - A), 0.0, 1.0);
   begin
      return T * T * (3.0 - 2.0 * T);
   end Smooth;

   --  The ground at a lateral distance, without the fine bumps: as the
   --  physics see it
   function Height_At (I : Natural; D : Float) return Float is
      S : Track.Sample renames Track.Samples (I);
      Edge : constant Float := (if D > 0.0 then S.W_R else S.W_L);
      Kerb_W : constant Float := (if D > 0.0 then S.Kerb_R else S.Kerb_L);
      Over : constant Float := abs D - Edge;
      Road_Y : constant Float := Track.Road_Height (I, D);
   begin
      if Over <= 0.0 then
         return Road_Y;
      elsif Over < Kerb_W then
         return Road_Y + 0.045 * Smooth (0.0, 0.5, Over) + 0.006;
      end if;
      declare
         X : constant Float := S.X + S.RX * D;
         Z : constant Float := S.Z + S.RZ * D;
         Blend : constant Float := Smooth (0.0, Track.Shoulder, Over - Kerb_W);
      begin
         return Road_Y + (Track.Terrain_Height (X, Z) - Road_Y) * Blend;
      end;
   end Height_At;

   function Point_At (I : Natural; D : Float; Up : Float := 0.0) return Vec3 is
      S : Track.Sample renames Track.Samples (I);
   begin
      return (S.X + S.RX * D, Height_At (I, D) + Up, S.Z + S.RZ * D);
   end Point_At;

   --  Barriers and trees are kept in tiles, so that only those near need
   --  drawing into the sharp shadow map
   Tile_Size : constant := 250.0;
   Tiles_N   : constant := 24;
   type Tile_Builders is array (0 .. Tiles_N - 1, 0 .. Tiles_N - 1) of Builder;
   type Tile_Meshes is array (0 .. Tiles_N - 1, 0 .. Tiles_N - 1) of Mesh.GPU;
   type Tile_Builders_Access is access Tile_Builders;
   Tiles : Tile_Meshes;
   TB : Tile_Builders_Access;

   function Tile_X (X : Float) return Natural is
     (Natural (Clamp (Float'Floor ((X - Track.Grid_X0) / Tile_Size), 0.0, Float (Tiles_N - 1))));
   function Tile_Z (Z : Float) return Natural is
     (Natural (Clamp (Float'Floor ((Z - Track.Grid_Z0) / Tile_Size), 0.0, Float (Tiles_N - 1))));

   procedure Draw_Near (X, Z, Radius : Float) is
      X0 : constant Natural := Tile_X (X - Radius);
      X1 : constant Natural := Tile_X (X + Radius);
      Z0 : constant Natural := Tile_Z (Z - Radius);
      Z1 : constant Natural := Tile_Z (Z + Radius);
   begin
      for IZ in Z0 .. Z1 loop
         for IX in X0 .. X1 loop
            Draw (Tiles (IX, IZ));
         end loop;
      end loop;
   end Draw_Near;

   procedure Draw_View (X, Z, Dir_X, Dir_Z : Float) is
   begin
      for IZ in 0 .. Tiles_N - 1 loop
         for IX in 0 .. Tiles_N - 1 loop
            declare
               CX : constant Float := Track.Grid_X0 + (Float (IX) + 0.5) * Tile_Size - X;
               CZ : constant Float := Track.Grid_Z0 + (Float (IZ) + 0.5) * Tile_Size - Z;
            begin
               --  Not those well behind the eye
               if CX * Dir_X + CZ * Dir_Z > -Tile_Size then
                  Draw (Tiles (IX, IZ));
               end if;
            end;
         end loop;
      end loop;
   end Draw_View;

   ---------------------------------------------------------------------------
   --  Road surface: strips between the sample cross sections
   ---------------------------------------------------------------------------

   procedure Build_Road (B : in out Builder) is
      Strips : constant := 8;

      function Vert (I, K : Natural) return Vertex is
         S : Track.Sample renames Track.Samples (I);
         Frac : constant Float := Float (K) / Float (Strips);
         D : constant Float := -S.W_L + (S.W_L + S.W_R) * Frac;
         Rubber_Amt : constant Float :=
           Clamp (1.3 - abs (D - S.Line_D) / 1.5, 0.0, 1.0);
         Up : constant Vec3 := Normalize ((-S.RX * S.Bank, 1.0, -S.RZ * S.Bank));
      begin
         return (Point_At (I, D), Up,
                 Rubber_Amt, D + S.W_L, S.W_R - D,
                 (if Track.Is_Stage then Mesh.Dirt_Road else Asphalt), S.S, D);
      end Vert;
   begin
      for I in 0 .. Track.Count - 1 loop
         declare
            J : constant Natural := Track.Next (I);
         begin
            for K in 0 .. Strips - 1 loop
               declare
                  A : constant Vertex := Vert (I, K);
                  C : constant Vertex := Vert (I, K + 1);
                  D : Vertex := Vert (J, K + 1);
                  E : Vertex := Vert (J, K);
               begin
                  --  (the loop closes: keep the along coordinate running on)
                  if J = 0 then
                     D.U := Track.Length;
                     E.U := Track.Length;
                  end if;
                  --  Winding from above: counter clockwise
                  Add (B, A); Add (B, E); Add (B, D);
                  Add (B, A); Add (B, D); Add (B, C);
               end;
            end loop;
         end;
      end loop;
   end Build_Road;

   --  Kerbs and the run-off ground out to the barrier, both sides
   procedure Build_Edges (Road_B, Ground_B : in out Builder) is
      Up : constant Vec3 := (0.0, 1.0, 0.0);

      procedure Kerb_Strip (I, J : Natural; Sign : Float) is
         A : Track.Sample renames Track.Samples (I);
         B : Track.Sample renames Track.Samples (J);
         EA : constant Float := (if Sign > 0.0 then A.W_R else A.W_L);
         EB : constant Float := (if Sign > 0.0 then B.W_R else B.W_L);
         KA : constant Float := (if Sign > 0.0 then A.Kerb_R else A.Kerb_L);
         KB : constant Float := (if Sign > 0.0 then B.Kerb_R else B.Kerb_L);
         UB : constant Float := (if J = 0 then Track.Length else B.S);
      begin
         if KA <= 0.0 or else KB <= 0.0 then
            return;
         end if;
         for Seg in 0 .. 2 loop
            declare
               F0 : constant Float := Float (Seg) / 3.0;
               F1 : constant Float := Float (Seg + 1) / 3.0;
               P00 : constant Vec3 := Point_At (I, Sign * (EA + KA * F0));
               P01 : constant Vec3 := Point_At (I, Sign * (EA + KA * F1));
               P10 : constant Vec3 := Point_At (J, Sign * (EB + KB * F0));
               P11 : constant Vec3 := Point_At (J, Sign * (EB + KB * F1));
            begin
               if Sign > 0.0 then
                  Add (Road_B, (P00, Up, 1.0, 1.0, 1.0, Mesh.Kerb, A.S, F0));
                  Add (Road_B, (P10, Up, 1.0, 1.0, 1.0, Mesh.Kerb, UB, F0));
                  Add (Road_B, (P11, Up, 1.0, 1.0, 1.0, Mesh.Kerb, UB, F1));
                  Add (Road_B, (P00, Up, 1.0, 1.0, 1.0, Mesh.Kerb, A.S, F0));
                  Add (Road_B, (P11, Up, 1.0, 1.0, 1.0, Mesh.Kerb, UB, F1));
                  Add (Road_B, (P01, Up, 1.0, 1.0, 1.0, Mesh.Kerb, A.S, F1));
               else
                  Add (Road_B, (P00, Up, 1.0, 1.0, 1.0, Mesh.Kerb, A.S, F0));
                  Add (Road_B, (P11, Up, 1.0, 1.0, 1.0, Mesh.Kerb, UB, F1));
                  Add (Road_B, (P10, Up, 1.0, 1.0, 1.0, Mesh.Kerb, UB, F0));
                  Add (Road_B, (P00, Up, 1.0, 1.0, 1.0, Mesh.Kerb, A.S, F0));
                  Add (Road_B, (P01, Up, 1.0, 1.0, 1.0, Mesh.Kerb, A.S, F1));
                  Add (Road_B, (P11, Up, 1.0, 1.0, 1.0, Mesh.Kerb, UB, F1));
               end if;
            end;
         end loop;
      end Kerb_Strip;

      --  Lateral stations from the road edge outwards
      Steps : constant := 7;
      function Station (I : Natural; Sign : Float; K : Natural) return Float is
         A : Track.Sample renames Track.Samples (I);
         E : constant Float :=
           (if Sign > 0.0 then A.W_R + A.Kerb_R else A.W_L + A.Kerb_L);
         Wall : constant Float := (if Sign > 0.0 then A.Wall_R else A.Wall_L);
         Far : constant Float := Float'Max (E + Track.Shoulder + 3.0, Wall + 3.0);
      begin
         return (case K is
                    when 0 => E,
                    when 1 => E + 0.15 * Track.Shoulder,
                    when 2 => E + 0.35 * Track.Shoulder,
                    when 3 => E + 0.6 * Track.Shoulder,
                    when 4 => E + 0.85 * Track.Shoulder,
                    when 5 => E + Track.Shoulder,
                    when 6 => E + Track.Shoulder + (Far - E - Track.Shoulder) * 0.5,
                    when others => Far);
      end Station;

      procedure Shoulder_Strip (I, J : Natural; Sign : Float) is
         function V (Idx : Natural; K : Natural) return Vertex is
            S : Track.Sample renames Track.Samples (Idx);
            D : constant Float := Station (Idx, Sign, K);
            G_Here : constant Boolean := (if Sign > 0.0 then S.Gravel_R else S.Gravel_L);
            E : constant Float :=
              (if Sign > 0.0 then S.W_R + S.Kerb_R else S.W_L + S.Kerb_L);
            Gv : constant Float :=
              (if G_Here and then D - E < 22.0 then 1.0 else 0.0);
         begin
            return (Point_At (Idx, Sign * D, 0.012 + 0.012 * Float (K)),
                    Up, Gv, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0);
         end V;
      begin
         for K in 0 .. Steps - 1 loop
            declare
               A : constant Vertex := V (I, K);
               C : constant Vertex := V (I, K + 1);
               D : constant Vertex := V (J, K + 1);
               E : constant Vertex := V (J, K);
            begin
               if Sign > 0.0 then
                  Add (Ground_B, A); Add (Ground_B, E); Add (Ground_B, D);
                  Add (Ground_B, A); Add (Ground_B, D); Add (Ground_B, C);
               else
                  Add (Ground_B, A); Add (Ground_B, D); Add (Ground_B, E);
                  Add (Ground_B, A); Add (Ground_B, C); Add (Ground_B, D);
               end if;
            end;
         end loop;
      end Shoulder_Strip;
   begin
      for I in 0 .. Track.Count - 1 loop
         declare
            J : constant Natural := Track.Next (I);
         begin
            Kerb_Strip (I, J, 1.0);
            Kerb_Strip (I, J, -1.0);
            Shoulder_Strip (I, J, 1.0);
            Shoulder_Strip (I, J, -1.0);
         end;
      end loop;
   end Build_Edges;

   ---------------------------------------------------------------------------
   --  Terrain: the grid, sunk where the road ribbon lies over it
   ---------------------------------------------------------------------------

   procedure Build_Terrain (B : in out Builder) is
      NX : constant Natural := Track.Grid_NX;
      NZ : constant Natural := Track.Grid_NZ;
      type Sink_Grid is array (Natural range <>) of Float;
      type Sink_Access is access Sink_Grid;
      Sink : constant Sink_Access := new Sink_Grid (0 .. NX * NZ - 1);

      function H (IX, IZ : Natural) return Float is
        (Track.Grid (IZ * NX + IX) - Sink (IZ * NX + IX));

      function P (IX, IZ : Natural) return Vec3 is
        (Track.Grid_X0 + Float (IX) * Track.Grid_Cell, H (IX, IZ),
         Track.Grid_Z0 + Float (IZ) * Track.Grid_Cell);

      function Nrm (IX, IZ : Natural) return Vec3 is
         L : constant Float := Track.Grid (IZ * NX + Natural'Max (IX, 1) - 1);
         R : constant Float := Track.Grid (IZ * NX + Natural'Min (IX + 1, NX - 1));
         U : constant Float := Track.Grid (Natural'Max (IZ, 1) * NX - NX + IX);
         D : constant Float := Track.Grid (Natural'Min (IZ + 1, NZ - 1) * NX + IX);
      begin
         return Normalize ((L - R, 2.0 * Track.Grid_Cell, U - D));
      end Nrm;
   begin
      Sink.all := (others => 0.0);
      --  Under road and shoulder the grid goes down out of sight
      for I in 0 .. Track.Count - 1 loop
         declare
            S : Track.Sample renames Track.Samples (I);
            Reach : constant Float :=
              Float'Max (S.W_L, S.W_R) + 3.0 + Track.Shoulder
              + Float'Max (0.0, Float'Max (S.Wall_L - S.W_L, S.Wall_R - S.W_R));
            C : constant Integer := Integer (Reach / Track.Grid_Cell) + 1;
            CX : constant Integer := Integer ((S.X - Track.Grid_X0) / Track.Grid_Cell);
            CZ : constant Integer := Integer ((S.Z - Track.Grid_Z0) / Track.Grid_Cell);
         begin
            for IZ in Integer'Max (0, CZ - C) .. Integer'Min (NZ - 1, CZ + C) loop
               for IX in Integer'Max (0, CX - C) .. Integer'Min (NX - 1, CX + C) loop
                  declare
                     PX : constant Float := Track.Grid_X0 + Float (IX) * Track.Grid_Cell - S.X;
                     PZ : constant Float := Track.Grid_Z0 + Float (IZ) * Track.Grid_Cell - S.Z;
                     Lat : constant Float := PX * S.RX + PZ * S.RZ;
                     Along : constant Float := PX * S.TX + PZ * S.TZ;
                     Edge : constant Float := (if Lat > 0.0 then S.W_R else S.W_L);
                     Wall : constant Float := (if Lat > 0.0 then S.Wall_R else S.Wall_L);
                     Keep : constant Float := Float'Max (Edge + Track.Shoulder + 1.0, Wall + 1.0);
                  begin
                     if abs Along < 8.0 then
                        if abs Lat < Keep - 5.0 then
                           Sink (IZ * NX + IX) := 1.2;
                        elsif abs Lat < Keep + 5.0 then
                           Sink (IZ * NX + IX) := Float'Max (Sink (IZ * NX + IX), 0.25);
                        end if;
                     end if;
                  end;
               end loop;
            end loop;
         end;
      end loop;
      for IZ in 0 .. NZ - 2 loop
         for IX in 0 .. NX - 2 loop
            declare
               P0 : constant Vec3 := P (IX, IZ);
               P1 : constant Vec3 := P (IX + 1, IZ);
               P2 : constant Vec3 := P (IX + 1, IZ + 1);
               P3 : constant Vec3 := P (IX, IZ + 1);
               N0 : constant Vec3 := Nrm (IX, IZ);
               N1 : constant Vec3 := Nrm (IX + 1, IZ);
               N2 : constant Vec3 := Nrm (IX + 1, IZ + 1);
               N3 : constant Vec3 := Nrm (IX, IZ + 1);
            begin
               Add (B, (P0, N0, 0.0, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0));
               Add (B, (P3, N3, 0.0, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0));
               Add (B, (P2, N2, 0.0, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0));
               Add (B, (P0, N0, 0.0, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0));
               Add (B, (P2, N2, 0.0, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0));
               Add (B, (P1, N1, 0.0, 0.0, 0.0, Mesh.Terrain, 0.0, 0.0));
            end;
         end loop;
      end loop;
   end Build_Terrain;

   --  Far hills on the horizon, in big cells, outside the detailed grid
   procedure Build_Horizon (B : in out Builder) is
      Cell : constant := 220.0;
      N : constant := 70;
      CX : constant Float := Track.Grid_X0 + Float (Track.Grid_NX) * Track.Grid_Cell * 0.5;
      CZ : constant Float := Track.Grid_Z0 + Float (Track.Grid_NZ) * Track.Grid_Cell * 0.5;
      HX : constant Float := Float (Track.Grid_NX) * Track.Grid_Cell * 0.5;
      HZ : constant Float := Float (Track.Grid_NZ) * Track.Grid_Cell * 0.5;

      function P (IX, IZ : Integer) return Vec3 is
         X : constant Float := CX + Float (IX) * Cell;
         Z : constant Float := CZ + Float (IZ) * Cell;
         Out_D : constant Float :=
           Float'Max (abs (X - CX) - HX, abs (Z - CZ) - HZ);
         Rise : constant Float := Smooth (0.0, 3500.0, Out_D);
         Bump : constant Float := (Track.Fbm (X / 2600.0, Z / 2600.0, 5) - 0.42);
      begin
         return (X, 6.0 + Rise * Float'Max (-10.0, Bump * 900.0), Z);
      end P;
      Green : constant Color := (0.0, 0.0, 0.0);
   begin
      for IZ in -N .. N - 1 loop
         for IX in -N .. N - 1 loop
            declare
               X : constant Float := CX + (Float (IX) + 0.5) * Cell;
               Z : constant Float := CZ + (Float (IZ) + 0.5) * Cell;
            begin
               --  Under the detailed grid: leave out
               if abs (X - CX) > HX - Cell or else abs (Z - CZ) > HZ - Cell then
                  Quad (B, P (IX, IZ), P (IX, IZ + 1), P (IX + 1, IZ + 1), P (IX + 1, IZ),
                        Green, Mesh.Terrain);
               end if;
            end;
         end loop;
      end loop;
   end Build_Horizon;

   ---------------------------------------------------------------------------
   --  Barriers
   ---------------------------------------------------------------------------

   procedure Build_Barriers is
      Steel : constant Color := (0.52, 0.54, 0.56);
      Post  : constant Color := (0.28, 0.29, 0.30);
      Red   : constant Color := (0.72, 0.08, 0.06);
      White : constant Color := (0.85, 0.85, 0.82);
      Pole  : constant Color := (0.25, 0.25, 0.27);
      Y_Up  : constant Vec3 := (0.0, 1.0, 0.0);

      --  Advertising colours along the barriers
      Ad_Cols : constant array (0 .. 5) of Color :=
        ((0.04, 0.12, 0.34), (0.58, 0.42, 0.05), (0.42, 0.06, 0.05),
         (0.04, 0.24, 0.13), (0.09, 0.09, 0.10), (0.62, 0.62, 0.60));

      procedure Side (Sign : Float) is
         function Wall_D (I : Natural) return Float is
           (Sign * (if Sign > 0.0 then Track.Samples (I).Wall_R else Track.Samples (I).Wall_L));
      begin
         for I in 0 .. Track.Count - 1 loop
            declare
               J : constant Natural := Track.Next (I);
               A0 : constant Vec3 := Point_At (I, Wall_D (I));
               B0 : constant Vec3 := Point_At (J, Wall_D (J));
               DY : constant Vec3 := (0.0, 1.0, 0.0);
               S  : Track.Sample renames Track.Samples (I);
               B  : Builder renames TB (Tile_X (A0.X), Tile_Z (A0.Z));
               Gravel_Here : constant Boolean := (if Sign > 0.0 then S.Gravel_R else S.Gravel_L);
               Thick : constant Float := 0.12;
               --  Direction towards the road
               ToR : constant Vec3 := ((-Sign) * S.RX, 0.0, (-Sign) * S.RZ);
               Band : constant Natural := I / 12;
            begin
               if Gravel_Here then
                  --  Tyre wall: stacks in red and white
                  declare
                     C : constant Color := (if I mod 4 < 2 then Red else White);
                     H : constant Float := 1.1;
                     Off : constant Vec3 := (-0.5) * ToR;
                  begin
                     Quad (B, A0 + Thick * ToR, B0 + Thick * ToR,
                           B0 + Thick * ToR + H * DY, A0 + Thick * ToR + H * DY, C);
                     Quad (B, A0 + H * DY + Thick * ToR, B0 + H * DY + Thick * ToR,
                           B0 + H * DY + Off, A0 + H * DY + Off, C);
                  end;
               else
                  --  Steel rail, sometimes painted with an advert behind
                  declare
                     Y0 : constant Float := 0.3;
                     Y1 : constant Float := 0.78;
                     C : constant Color :=
                       (if Band mod 7 < 3 then Ad_Cols (Band mod 6) else Steel);
                     Y_T : constant Float := (if Band mod 7 < 3 then 1.05 else Y1);
                  begin
                     --  Whole along the circuit, so that what is painted on
                     --  it is not cut at every sample
                     declare
                        N : constant Vec3 := ToR;
                        U0 : constant Float := Float (I) * Track.Spacing;
                        U1 : constant Float := U0 + Track.Spacing;
                        M : constant Float := (if Band mod 7 < 3 then Board else Armco);
                        V1 : constant Float := Y_T - Y0;
                     begin
                        Add (B, (A0 + Y0 * DY, N, C.R, C.G, C.B, M, U0, 0.0));
                        Add (B, (B0 + Y0 * DY, N, C.R, C.G, C.B, M, U1, 0.0));
                        Add (B, (B0 + Y_T * DY, N, C.R, C.G, C.B, M, U1, V1));
                        Add (B, (A0 + Y0 * DY, N, C.R, C.G, C.B, M, U0, 0.0));
                        Add (B, (B0 + Y_T * DY, N, C.R, C.G, C.B, M, U1, V1));
                        Add (B, (A0 + Y_T * DY, N, C.R, C.G, C.B, M, U0, V1));
                     end;
                  end;
                  if I mod 2 = 0 then
                     Oriented_Box (B, A0 + 0.35 * DY + (-0.06) * ToR, Y_Up, ToR,
                                   0.42, 0.06, 0.06, Post);
                  end if;
               end if;
               --  Catch fence behind gravel traps and along the fast bits
               if Gravel_Here or else (I / 40) mod 4 = 0 then
                  declare
                     Back : constant Vec3 := (-0.8) * ToR;
                     Y0 : constant Float := 1.0;
                     Y1 : constant Float := 3.6;
                     U0 : constant Float := Float (I) * Track.Spacing;
                     P0 : constant Vec3 := A0 + Back + Y0 * DY;
                     P1 : constant Vec3 := B0 + Back + Y0 * DY;
                     P2 : constant Vec3 := B0 + Back + Y1 * DY;
                     P3 : constant Vec3 := A0 + Back + Y1 * DY;
                     N  : constant Vec3 := ToR;
                  begin
                     Add (B, (P0, N, 0.3, 0.3, 0.32, Mesh.Fence, U0, Y0));
                     Add (B, (P1, N, 0.3, 0.3, 0.32, Mesh.Fence, U0 + Track.Spacing, Y0));
                     Add (B, (P2, N, 0.3, 0.3, 0.32, Mesh.Fence, U0 + Track.Spacing, Y1));
                     Add (B, (P0, N, 0.3, 0.3, 0.32, Mesh.Fence, U0, Y0));
                     Add (B, (P2, N, 0.3, 0.3, 0.32, Mesh.Fence, U0 + Track.Spacing, Y1));
                     Add (B, (P3, N, 0.3, 0.3, 0.32, Mesh.Fence, U0, Y1));
                     if I mod 5 = 0 then
                        Oriented_Box (B, A0 + Back + 1.8 * DY, Y_Up, ToR, 1.8, 0.05, 0.05, Pole);
                     end if;
                  end;
               end if;
            end;
         end loop;
      end Side;
   begin
      Side (1.0);
      Side (-1.0);
   end Build_Barriers;

   ---------------------------------------------------------------------------
   --  Start line furniture, pits, grandstands
   ---------------------------------------------------------------------------

   procedure Build_Start (B : in out Builder; Road_B : in out Builder) is
      S0 : Track.Sample renames Track.Samples (0);
      Up : constant Vec3 := (0.0, 1.0, 0.0);
      Dark : constant Color := (0.12, 0.12, 0.14);
   begin
      --  Chequered line across the road
      declare
         W : constant Float := 0.012;
         AL : constant Vec3 := Point_At (0, -S0.W_L, W);
         AR : constant Vec3 := Point_At (0, S0.W_R, W);
         BL : constant Vec3 := Point_At (1, -S0.W_L, W);
         BR : constant Vec3 := Point_At (1, S0.W_R, W);
         Across : constant Float := S0.W_L + S0.W_R;
      begin
         Add (Road_B, (AL, Up, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
         Add (Road_B, (BL, Up, 1.0, 1.0, 1.0, Checker, 0.0, Track.Spacing));
         Add (Road_B, (BR, Up, 1.0, 1.0, 1.0, Checker, Across, Track.Spacing));
         Add (Road_B, (AL, Up, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
         Add (Road_B, (BR, Up, 1.0, 1.0, 1.0, Checker, Across, Track.Spacing));
         Add (Road_B, (AR, Up, 1.0, 1.0, 1.0, Checker, Across, 0.0));
      end;
      --  Grid boxes
      for P in 1 .. 8 loop
         declare
            I : constant Natural := Track.Next (0, -(6 + (P - 1) * 5));
            J : constant Natural := Track.Next (I, 1);
            K : constant Natural := Track.Next (I, -2);
            Side : constant Float := (if P mod 2 = 1 then -2.6 else 2.6);
            W : constant Float := 0.012;
            White : constant Color := (0.8, 0.8, 0.78);
         begin
            Quad (Road_B, Point_At (J, Side - 1.2, W), Point_At (J, Side + 1.2, W),
                  Point_At (I, Side + 1.2, W), Point_At (I, Side - 1.2, W), White);
            Quad (Road_B, Point_At (K, Side - 1.2, W), Point_At (K, Side - 1.05, W),
                  Point_At (J, Side - 1.05, W), Point_At (J, Side - 1.2, W), White);
            Quad (Road_B, Point_At (K, Side + 1.05, W), Point_At (K, Side + 1.2, W),
                  Point_At (J, Side + 1.2, W), Point_At (J, Side + 1.05, W), White);
         end;
      end loop;
      --  Gantry
      declare
         L : constant Vec3 := Point_At (0, -S0.W_L - 2.5);
         R : constant Vec3 := Point_At (0, S0.W_R + 2.5);
         Top : constant Float := 7.0;
         Mid_Y : constant Float := Float'Max (L.Y, R.Y) + Top;
         Mid : constant Vec3 := (0.5 * (L.X + R.X), Mid_Y, 0.5 * (L.Z + R.Z));
         Across : constant Vec3 := (S0.RX, 0.0, S0.RZ);
         Half : constant Float := Length (R - L) * 0.5;
      begin
         Oriented_Box (B, L + 3.6 * Up, Up, Across, 3.7, 0.25, 0.25, Dark);
         Oriented_Box (B, R + 3.6 * Up, Up, Across, 3.7, 0.25, 0.25, Dark);
         Oriented_Box (B, Mid, Across, Up, Half, 0.7, 0.3, Dark);
         --  The banner, chequered, both faces
         declare
            T : constant Vec3 := (S0.TX, 0.0, S0.TZ);
            Back : constant Vec3 := Mid + (-0.32) * T;
            Front : constant Vec3 := Mid + 0.32 * T;
            A : constant Vec3 := (-Half) * Across + (-0.6) * Up;
            C : constant Vec3 := Half * Across + (-0.6) * Up;
            D : constant Vec3 := Half * Across + 0.6 * Up;
            E : constant Vec3 := (-Half) * Across + 0.6 * Up;
            N1 : constant Vec3 := (-1.0) * T;
            N2 : constant Vec3 := T;
         begin
            Add (B, (Back + A, N1, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
            Add (B, (Back + C, N1, 1.0, 1.0, 1.0, Checker, 2.0 * Half, 0.0));
            Add (B, (Back + D, N1, 1.0, 1.0, 1.0, Checker, 2.0 * Half, 1.2));
            Add (B, (Back + A, N1, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
            Add (B, (Back + D, N1, 1.0, 1.0, 1.0, Checker, 2.0 * Half, 1.2));
            Add (B, (Back + E, N1, 1.0, 1.0, 1.0, Checker, 0.0, 1.2));
            Add (B, (Front + A, N2, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
            Add (B, (Front + D, N2, 1.0, 1.0, 1.0, Checker, 2.0 * Half, 1.2));
            Add (B, (Front + C, N2, 1.0, 1.0, 1.0, Checker, 2.0 * Half, 0.0));
            Add (B, (Front + A, N2, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
            Add (B, (Front + E, N2, 1.0, 1.0, 1.0, Checker, 0.0, 1.2));
            Add (B, (Front + D, N2, 1.0, 1.0, 1.0, Checker, 2.0 * Half, 1.2));
         end;
      end;

      --  The pit box, on the apron off the left of the road
      for I in 0 .. Track.Count - 1 loop
         declare
            A : Track.Sample renames Track.Samples (I);
            J : constant Natural := Track.Next (I);
            N : Track.Sample renames Track.Samples (J);
         begin
            if A.S >= Track.Pit_From and then A.S < Track.Pit_To then
               declare
                  function Spot (P : Track.Sample; Out_D, Lift : Float) return Vec3 is
                    (P.X - P.RX * (P.W_L + P.Kerb_L + Out_D),
                     P.Y - P.W_L * P.Bank + Lift,
                     P.Z - P.RZ * (P.W_L + P.Kerb_L + Out_D));
                  Up : constant Vec3 := (0.0, 1.0, 0.0);
                  Line : constant Color := (0.62, 0.60, 0.20);
               begin
                  Add (B, (Spot (A, 0.0, 0.03), Up, 0.0, 9.0, 9.0, Asphalt, A.S, 0.0));
                  Add (B, (Spot (N, 0.0, 0.03), Up, 0.0, 9.0, 9.0, Asphalt, N.S, 0.0));
                  Add (B, (Spot (N, Track.Pit_Wide, 0.03), Up, 0.0, 9.0, 9.0, Asphalt, N.S, 5.5));
                  Add (B, (Spot (A, 0.0, 0.03), Up, 0.0, 9.0, 9.0, Asphalt, A.S, 0.0));
                  Add (B, (Spot (N, Track.Pit_Wide, 0.03), Up, 0.0, 9.0, 9.0, Asphalt, N.S, 5.5));
                  Add (B, (Spot (A, Track.Pit_Wide, 0.03), Up, 0.0, 9.0, 9.0, Asphalt, A.S, 5.5));
                  --  Yellow lines round it, and across every car's length
                  Quad (B, Spot (A, Track.Pit_Wide - 0.25, 0.04), Spot (N, Track.Pit_Wide - 0.25, 0.04),
                        Spot (N, Track.Pit_Wide - 0.05, 0.04), Spot (A, Track.Pit_Wide - 0.05, 0.04), Line);
                  if (I mod 5) = 0 then
                     Quad (B, Spot (A, 0.05, 0.04), Spot (N, 0.05, 0.04) ,
                           Spot (N, Track.Pit_Wide, 0.04), Spot (A, Track.Pit_Wide, 0.04), Line);
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Pit building on the left, grandstands on the right of the straight
      declare
         Wall_C : constant Color := (0.82, 0.82, 0.80);
         Roof_C : constant Color := (0.25, 0.27, 0.30);
         Door_C : constant Color := (0.10, 0.12, 0.16);
         Span : constant := 9;  --  garages
      begin
         for G in -Span .. Span loop
            declare
               I : constant Natural := Track.Next (0, G * 6);
               S : Track.Sample renames Track.Samples (I);
               D : constant Float := -(S.Wall_L + 5.0);
               C : constant Vec3 := Point_At (I, D);
               Along : constant Vec3 := (S.TX, 0.0, S.TZ);
            begin
               Oriented_Box (B, C + 2.4 * Up, Along, Up, 6.1, 2.4, 3.5, Wall_C);
               Oriented_Box (B, C + 5.0 * Up, Along, Up, 6.3, 0.25, 4.5, Roof_C);
               Oriented_Box (B, C + 1.8 * Up + (3.52) * Vec3'(S.RX, 0.0, S.RZ), Along, Up,
                             4.6, 1.75, 0.05, Door_C);
            end;
         end loop;
      end;
      for G in -5 .. 5 loop
         declare
            I : constant Natural := Track.Next (0, G * 12 - 10);
            S : Track.Sample renames Track.Samples (I);
            Along : constant Vec3 := (S.TX, 0.0, S.TZ);
            Out_V : constant Vec3 := (S.RX, 0.0, S.RZ);
            Base : constant Float := S.Wall_R + 6.0;
         begin
            --  Steps rising away from the track, people on them
            for Row in 0 .. 9 loop
               declare
                  P : constant Vec3 := Point_At (I, Base + Float (Row) * 1.3);
                  H : constant Float := 0.8 + Float (Row) * 0.75;
               begin
                  Oriented_Box (B, P + (H * 0.5) * Up, Along, Up, 12.05, H * 0.5, 0.65,
                                (0.38, 0.38, 0.40));
                  --  The front of each step: seats and spectators
                  declare
                     Near : constant Vec3 := P + (-0.66) * Out_V;
                     E1 : constant Vec3 := (-12.05) * Along;
                     E2 : constant Vec3 := 12.05 * Along;
                     Lo : constant Vec3 := (H - 0.75) * Up;
                     Hi : constant Vec3 := H * Up;
                     N : constant Vec3 := (-1.0) * Out_V;
                  begin
                     Add (B, (Near + E2 + Lo, N, 0.5, 0.5, 0.5, Mesh.Crowd, 24.0, 0.0));
                     Add (B, (Near + E1 + Lo, N, 0.5, 0.5, 0.5, Mesh.Crowd, 0.0, 0.0));
                     Add (B, (Near + E1 + Hi, N, 0.5, 0.5, 0.5, Mesh.Crowd, 0.0, 0.75));
                     Add (B, (Near + E2 + Lo, N, 0.5, 0.5, 0.5, Mesh.Crowd, 24.0, 0.0));
                     Add (B, (Near + E1 + Hi, N, 0.5, 0.5, 0.5, Mesh.Crowd, 0.0, 0.75));
                     Add (B, (Near + E2 + Hi, N, 0.5, 0.5, 0.5, Mesh.Crowd, 24.0, 0.75));
                  end;
               end;
            end loop;
            --  Roof over the back rows
            declare
               P : constant Vec3 := Point_At (I, Base + 6.0);
            begin
               Oriented_Box (B, P + 12.0 * Up, Along, Up, 12.3, 0.15, 8.0, (0.75, 0.76, 0.78));
               if G mod 2 = 0 then
                  Oriented_Box (B, Point_At (I, Base + 13.0) + 6.0 * Up, Up, Along,
                                6.0, 0.15, 0.15, (0.3, 0.3, 0.32));
               end if;
            end;
         end;
      end loop;
   end Build_Start;

   --  Braking boards before the slow corners, and a bridge over the road
   procedure Build_Boards (B : in out Builder) is
      Up : constant Vec3 := (0.0, 1.0, 0.0);
   begin
      declare
         I : Natural := 0;
      begin
         while I < Track.Count loop
            declare
               V_Now : constant Float := Track.Samples (I).Line_V;
               V_Then : constant Float := Track.Samples (Track.Next (I, 60)).Line_V;
            begin
               if V_Now > V_Then + 14.0 and then V_Now > 40.0 then
                  --  Three boards, 150, 100 and 50 metres from here
                  for Board in 1 .. 3 loop
                     declare
                        K : constant Natural := Track.Next (I, (Board - 1) * 25);
                        S : Track.Sample renames Track.Samples (K);
                        Sign : constant Float := (if S.Line_D > 0.0 then 1.0 else -1.0);
                        D : constant Float :=
                          Sign * ((if Sign > 0.0 then S.W_R else S.W_L) + 2.3);
                        P : constant Vec3 := Point_At (K, D);
                        Along : constant Vec3 := (S.TX, 0.0, S.TZ);
                        Across : constant Vec3 := (S.RX, 0.0, S.RZ);
                     begin
                        Oriented_Box (B, P + 0.5 * Up, Up, Along, 0.5, 0.04, 0.04, (0.2, 0.2, 0.2));
                        Oriented_Box (B, P + 1.15 * Up, Across, Up, 0.42, 0.42, 0.03,
                                      (0.9, 0.9, 0.88));
                        for Stripe in 1 .. 4 - Board loop
                           Oriented_Box (B, P + (0.85 + 0.2 * Float (Stripe)) * Up + (-0.04) * Along,
                                         Across, Up, 0.34, 0.05, 0.02, (0.1, 0.1, 0.1));
                        end loop;
                     end;
                  end loop;
                  I := I + 200;
               end if;
            end;
            I := I + 5;
         end loop;
      end;

      --  An advertising bridge a third of the way round
      declare
         I : constant Natural := Track.Count / 3;
         S : Track.Sample renames Track.Samples (I);
         L : constant Vec3 := Point_At (I, -S.Wall_L + 0.6);
         R : constant Vec3 := Point_At (I, S.Wall_R - 0.6);
         Across : constant Vec3 := Normalize (R - L);
         Mid_Y : constant Float := Float'Max (L.Y, R.Y) + 6.5;
         Mid : constant Vec3 := (0.5 * (L.X + R.X), Mid_Y, 0.5 * (L.Z + R.Z));
         Half : constant Float := Length (R - L) * 0.5 + 1.0;
         Colour : constant Color := (0.08, 0.20, 0.50);
      begin
         Oriented_Box (B, L + 3.5 * Up, Up, Across, 3.6, 0.5, 0.5, (0.45, 0.45, 0.48));
         Oriented_Box (B, R + 3.5 * Up, Up, Across, 3.6, 0.5, 0.5, (0.45, 0.45, 0.48));
         Oriented_Box (B, Mid, Across, Up, Half, 1.0, 0.9, Colour);
      end;
   end Build_Boards;

   ---------------------------------------------------------------------------
   --  Trees
   ---------------------------------------------------------------------------

   --  A flat card of foliage, seen from both sides; its normal is given, so
   --  a crown of cards is lit like one round mass
   procedure Card (B : in out Builder; P0, P1, P2, P3 : Vec3; N : Vec3; G : Color; Mat : Float) is
   begin
      Add (B, (P0, N, G.R, G.G, G.B, Mat, 0.0, 0.0));
      Add (B, (P1, N, G.R, G.G, G.B, Mat, 1.0, 0.0));
      Add (B, (P2, N, G.R, G.G, G.B, Mat, 1.0, 1.0));
      Add (B, (P0, N, G.R, G.G, G.B, Mat, 0.0, 0.0));
      Add (B, (P2, N, G.R, G.G, G.B, Mat, 1.0, 1.0));
      Add (B, (P3, N, G.R, G.G, G.B, Mat, 0.0, 1.0));
   end Card;

   --  A dark, plain cone or lump behind the cards: nothing to see through
   --  to the sky in the heart of the tree
   procedure Core (B : in out Builder; Base : Vec3; R, H : Float; Col : Color) is
      Sides : constant := 6;
      Tip : constant Vec3 := Base + Vec3'(0.0, H, 0.0);
   begin
      for S in 0 .. Sides - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (S) / Float (Sides);
            A1 : constant Float := 2.0 * Pi * Float (S + 1) / Float (Sides);
            V0 : constant Vec3 := Base + Vec3'(R * Cos (A0), 0.0, R * Sin (A0));
            V1 : constant Vec3 := Base + Vec3'(R * Cos (A1), 0.0, R * Sin (A1));
            N0 : constant Vec3 := Normalize ((Cos (A0), 0.6, Sin (A0)));
            N1 : constant Vec3 := Normalize ((Cos (A1), 0.6, Sin (A1)));
         begin
            Add (B, (V0, N0, Col.R, Col.G, Col.B, Plain, 0.0, 0.0));
            Add (B, (Tip, (0.0, 1.0, 0.0), Col.R, Col.G, Col.B, Plain, 0.0, 0.0));
            Add (B, (V1, N1, Col.R, Col.G, Col.B, Plain, 0.0, 0.0));
         end;
      end loop;
   end Core;

   procedure Pine (B : in out Builder; P : Vec3; H, Tint : Float) is
      Trunk : constant Color := (0.13, 0.085, 0.055);
      --  Multiplies a grey card; a dark blue-green, each tree its own
      Green : constant Color := (0.15 + 0.08 * Tint, 0.27 + 0.09 * Tint, 0.15);
      Dark : constant Color := (0.012, 0.028, 0.014);
      Tiers : constant := 10;
      Per_Tier : constant := 5;
      R0 : constant Float := H * 0.24;
   begin
      Oriented_Box (B, P + (H * 0.36) * Vec3'(0.0, 1.0, 0.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
                    H * 0.36, H * 0.012, H * 0.012, Trunk);
      Core (B, P + Vec3'(0.0, H * 0.20, 0.0), R0 * 0.34, H * 0.68, Dark);
      for Tier in 0 .. Tiers - 1 loop
         declare
            T : constant Float := Float (Tier) / Float (Tiers - 1);
            Y : constant Float := H * (0.20 + 0.70 * T);
            R : constant Float := R0 * (1.08 - 0.88 * T);
            W : constant Float := R * 0.72;
            Droop : constant Float := R * (0.62 - 0.32 * T);
            Turn : constant Float := Float (Tier) * 2.2 + Tint * 6.0;
         begin
            for S in 0 .. Per_Tier - 1 loop
               declare
                  A : constant Float := Turn + 2.0 * Pi * Float (S) / Float (Per_Tier);
                  Out_V : constant Vec3 := (Cos (A), 0.0, Sin (A));
                  Side : constant Vec3 := (-Sin (A), 0.0, Cos (A));
                  Inner : constant Vec3 := P + Vec3'(0.0, Y, 0.0);
                  Outer : constant Vec3 := Inner + R * Out_V + Vec3'(0.0, -Droop, 0.0);
                  N : constant Vec3 := Normalize ((Cos (A) * 0.8, 0.7, Sin (A) * 0.8));
               begin
                  Card (B, Inner + (-W) * Side, Inner + W * Side,
                        Outer + W * Side, Outer + (-W) * Side, N, Green, Needles);
               end;
            end loop;
         end;
      end loop;
   end Pine;

   procedure Broadleaf (B : in out Builder; P : Vec3; H, Tint : Float) is
      Trunk : constant Color := (0.15, 0.11, 0.075);
      Green : constant Color := (0.26 + 0.20 * Tint, 0.46 + 0.14 * Tint, 0.14 + 0.03 * Tint);
      Dark : constant Color := (0.018, 0.038, 0.012);
      R : constant Float := H * 0.34;
      C : constant Vec3 := P + Vec3'(0.0, H * 0.62, 0.0);
      Clumps : constant := 16;
      Golden : constant := 2.399963;
   begin
      Oriented_Box (B, P + (H * 0.3) * Vec3'(0.0, 1.0, 0.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0),
                    H * 0.3, H * 0.022, H * 0.022, Trunk);
      Core (B, C + Vec3'(0.0, -R * 0.55, 0.0), R * 0.68, R * 1.2, Dark);
      --  Spread evenly over the crown, each clump facing out of it
      for K in 0 .. Clumps - 1 loop
         declare
            Y : constant Float := 1.0 - 2.0 * (Float (K) + 0.5) / Float (Clumps);
            Ring : constant Float := Sqrt (Float'Max (0.0, 1.0 - Y * Y));
            A : constant Float := Float (K) * Golden + Tint * 6.0;
            N : constant Vec3 := (Ring * Cos (A), Y, Ring * Sin (A));
            Reach : constant Float := 0.62 + 0.14 * Sin (Float (K) * 3.1 + Tint * 11.0);
            Mid : constant Vec3 := C + Vec3'(N.X * R * Reach, N.Y * R * 0.82 * Reach, N.Z * R * Reach);
            Size : constant Float := R * (0.56 + 0.1 * Sin (Float (K) * 1.3));
            Spin : constant Vec3 :=
              (if abs N.Y > 0.9 then Vec3'(Cos (A), 0.0, Sin (A)) else Vec3'(0.0, 1.0, 0.0));
            E1 : constant Vec3 := Normalize (Cross (Spin, N));
            E2 : constant Vec3 := Cross (N, E1);
         begin
            Card (B, Mid + (-Size) * E1 + (-Size) * E2, Mid + Size * E1 + (-Size) * E2,
                  Mid + Size * E1 + Size * E2, Mid + (-Size) * E1 + Size * E2, N, Green, Leaves);
         end;
      end loop;
   end Broadleaf;

   --  A street circuit: concrete walls with adverts and a catch fence, lamp
   --  posts along the kerb, the buildings, and the harbour
   procedure Build_City (O : in out Builder) is
      Concrete : constant Color := (0.62, 0.62, 0.60);
      Pole : constant Color := (0.22, 0.23, 0.25);
      Ad_Cols : constant array (0 .. 5) of Color :=
        ((0.04, 0.12, 0.34), (0.58, 0.42, 0.05), (0.42, 0.06, 0.05),
         (0.04, 0.24, 0.13), (0.09, 0.09, 0.10), (0.62, 0.62, 0.60));
      Up : constant Vec3 := (0.0, 1.0, 0.0);
   begin
      for Side in 0 .. 1 loop
         declare
            Sign : constant Float := (if Side = 0 then -1.0 else 1.0);
         begin
            for I in 0 .. Track.Count - 1 loop
               declare
                  J : constant Natural := Track.Next (I);
                  S : Track.Sample renames Track.Samples (I);
                  SJ : Track.Sample renames Track.Samples (J);
                  WI : constant Float := Sign * (if Sign > 0.0 then S.Wall_R else S.Wall_L);
                  WJ : constant Float := Sign * (if Sign > 0.0 then SJ.Wall_R else SJ.Wall_L);
                  A0 : constant Vec3 := Point_At (I, WI);
                  B0 : constant Vec3 := Point_At (J, WJ);
                  ToR : constant Vec3 := ((-Sign) * S.RX, 0.0, (-Sign) * S.RZ);
                  B : Builder renames TB (Tile_X (A0.X), Tile_Z (A0.Z));
                  Band : constant Natural := I / 10;
                  H : constant := 1.15;
                  U0 : constant Float := Float (I) * Track.Spacing;
                  U1 : constant Float := U0 + Track.Spacing;
               begin
                  --  The wall's face and top
                  Add (B, (A0, ToR, Concrete.R, Concrete.G, Concrete.B, Plain, U0, 0.0));
                  Add (B, (B0, ToR, Concrete.R, Concrete.G, Concrete.B, Plain, U1, 0.0));
                  Add (B, (B0 + H * Up, ToR, Concrete.R, Concrete.G, Concrete.B, Plain, U1, H));
                  Add (B, (A0, ToR, Concrete.R, Concrete.G, Concrete.B, Plain, U0, 0.0));
                  Add (B, (B0 + H * Up, ToR, Concrete.R, Concrete.G, Concrete.B, Plain, U1, H));
                  Add (B, (A0 + H * Up, ToR, Concrete.R, Concrete.G, Concrete.B, Plain, U0, H));
                  Quad (B, A0 + H * Up, B0 + H * Up, B0 + H * Up + (-0.5) * ToR,
                        A0 + H * Up + (-0.5) * ToR, Concrete);
                  --  An advert along the top, now and then
                  if Band mod 3 = 0 then
                     declare
                        C : constant Color := Ad_Cols (Band mod 6);
                        V1 : constant := 0.9;
                        F : constant Vec3 := (0.04 * ToR) + (H + 0.05) * Up;
                     begin
                        Add (B, (A0 + F, ToR, C.R, C.G, C.B, Board, U0, 0.0));
                        Add (B, (B0 + F, ToR, C.R, C.G, C.B, Board, U1, 0.0));
                        Add (B, (B0 + F + V1 * Up, ToR, C.R, C.G, C.B, Board, U1, V1));
                        Add (B, (A0 + F, ToR, C.R, C.G, C.B, Board, U0, 0.0));
                        Add (B, (B0 + F + V1 * Up, ToR, C.R, C.G, C.B, Board, U1, V1));
                        Add (B, (A0 + F + V1 * Up, ToR, C.R, C.G, C.B, Board, U0, V1));
                     end;
                  end if;
                  --  The catch fence above it
                  Add (B, (A0 + 2.1 * Up, ToR, 0.3, 0.3, 0.32, Fence, U0, 2.1));
                  Add (B, (B0 + 2.1 * Up, ToR, 0.3, 0.3, 0.32, Fence, U1, 2.1));
                  Add (B, (B0 + 4.2 * Up, ToR, 0.3, 0.3, 0.32, Fence, U1, 4.2));
                  Add (B, (A0 + 2.1 * Up, ToR, 0.3, 0.3, 0.32, Fence, U0, 2.1));
                  Add (B, (B0 + 4.2 * Up, ToR, 0.3, 0.3, 0.32, Fence, U1, 4.2));
                  Add (B, (A0 + 4.2 * Up, ToR, 0.3, 0.3, 0.32, Fence, U0, 4.2));
                  if I mod 5 = 0 then
                     Oriented_Box (B, A0 + 2.1 * Up + (-0.1) * ToR, Up, ToR, 2.1, 0.05, 0.05, Pole);
                  end if;
                  --  Street lamps over the road, every 30 m on alternate sides
                  if I mod 15 = (if Side = 0 then 0 else 7) then
                     declare
                        Foot : constant Vec3 := A0 + (-0.6) * ToR;
                        Arm : constant Vec3 := Foot + 8.0 * Up + 1.6 * ToR;
                     begin
                        Oriented_Box (B, Foot + 4.0 * Up, Up, ToR, 4.0, 0.09, 0.09, Pole);
                        Oriented_Box (B, Foot + 8.0 * Up + 0.8 * ToR, ToR, Up, 0.8, 0.05, 0.05, Pole);
                        Box (B, Arm + Vec3'(-0.35, -0.12, -0.35), Arm + Vec3'(0.35, 0.02, 0.35),
                             (1.6, 1.3, 0.8), Glow);
                     end;
                  end if;
               end;
            end loop;
         end;
      end loop;

      --  The buildings: four fronts with windows, and a flat roof
      for Bd of Track.Buildings.all loop
         declare
            Along : constant Vec3 := (Bd.TX, 0.0, Bd.TZ);
            Side : constant Vec3 := (-Bd.TZ, 0.0, Bd.TX);
            C : constant Vec3 := (Bd.X, Bd.Y - 1.0, Bd.Z);
            HL : constant Float := Bd.Len / 2.0;
            HD : constant Float := Bd.Depth / 2.0;
            Top : constant Float := Bd.Height + 1.0;
            B : Builder renames TB (Tile_X (Bd.X), Tile_Z (Bd.Z));
            T : constant Float := Bd.Tint;
            Roof : constant Color := (0.16, 0.16, 0.17);
            procedure Front (P0, P1 : Vec3; Width : Float) is
               N : constant Vec3 := Normalize (Cross (P1 - P0, Up));
            begin
               Add (B, (P0, N, T, 0.0, 0.0, Facade, 0.0, -1.0));
               Add (B, (P1, N, T, 0.0, 0.0, Facade, Width, -1.0));
               Add (B, (P1 + Top * Up, N, T, 0.0, 0.0, Facade, Width, Top - 1.0));
               Add (B, (P0, N, T, 0.0, 0.0, Facade, 0.0, -1.0));
               Add (B, (P1 + Top * Up, N, T, 0.0, 0.0, Facade, Width, Top - 1.0));
               Add (B, (P0 + Top * Up, N, T, 0.0, 0.0, Facade, 0.0, Top - 1.0));
            end Front;
            K00 : constant Vec3 := C + (-HL) * Along + (-HD) * Side;
            K10 : constant Vec3 := C + HL * Along + (-HD) * Side;
            K11 : constant Vec3 := C + HL * Along + HD * Side;
            K01 : constant Vec3 := C + (-HL) * Along + HD * Side;
         begin
            Front (K10, K00, Bd.Len);
            Front (K11, K10, Bd.Depth);
            Front (K01, K11, Bd.Len);
            Front (K00, K01, Bd.Depth);
            Quad (B, K00 + Top * Up, K01 + Top * Up, K11 + Top * Up, K10 + Top * Up, Roof);
         end;
      end loop;

      --  The harbour basin
      if Track.Has_Water then
         declare
            R : constant Float := Track.Water_R + 30.0;
            X : constant Float := Track.Water_X;
            Z : constant Float := Track.Water_Z;
            Y : constant Float := Track.Water_Y;
            N : constant Vec3 := (0.0, 1.0, 0.0);
         begin
            Add (O, ((X - R, Y, Z - R), N, 0.0, 0.0, 0.0, Water, 0.0, 0.0));
            Add (O, ((X - R, Y, Z + R), N, 0.0, 0.0, 0.0, Water, 0.0, 0.0));
            Add (O, ((X + R, Y, Z + R), N, 0.0, 0.0, 0.0, Water, 0.0, 0.0));
            Add (O, ((X - R, Y, Z - R), N, 0.0, 0.0, 0.0, Water, 0.0, 0.0));
            Add (O, ((X + R, Y, Z + R), N, 0.0, 0.0, 0.0, Water, 0.0, 0.0));
            Add (O, ((X + R, Y, Z - R), N, 0.0, 0.0, 0.0, Water, 0.0, 0.0));
         end;
      end if;
   end Build_City;

   procedure Build_Trees is
   begin
      for T of Track.Trees.all loop
         declare
            P : constant Vec3 := (T.X, T.Y, T.Z);
         begin
            if T.Pine then
               Pine (TB (Tile_X (T.X), Tile_Z (T.Z)), P, T.H, T.Tint);
            else
               Broadleaf (TB (Tile_X (T.X), Tile_Z (T.Z)), P, T.H, T.Tint);
            end if;
         end;
      end loop;
   end Build_Trees;

   --  A stage: nothing but an arch over the road where the clock starts and
   --  one where it stops, on a chequered line
   procedure Build_Stage (B : in out Builder; Road_B : in out Builder) is
      procedure Arch (I : Natural; Col : Color) is
         S : Track.Sample renames Track.Samples (I);
         L : constant Vec3 := Point_At (I, -S.W_L - 1.0);
         R : constant Vec3 := Point_At (I, S.W_R + 1.0);
         Up : constant Vec3 := (0.0, 1.0, 0.0);
         Top : constant := 5.2;
         Along : constant Vec3 := (S.TX, 0.0, S.TZ);
         Post : constant Color := (0.2, 0.2, 0.22);
      begin
         Oriented_Box (B, L + (Top / 2.0) * Up, Up, Along, Top / 2.0, 0.1, 0.1, Post);
         Oriented_Box (B, R + (Top / 2.0) * Up, Up, Along, Top / 2.0, 0.1, 0.1, Post);
         Oriented_Box (B, 0.5 * (L + R) + (Top - 0.45) * Up, R - L, Up,
                       0.5 * Length (R - L), 0.55, 0.06, Col, Board);
         declare
            AL : constant Vec3 := Point_At (I, -S.W_L, 0.03);
            AR : constant Vec3 := Point_At (I, S.W_R, 0.03);
            BL : constant Vec3 := Point_At (Track.Next (I), -S.W_L, 0.03);
            BR : constant Vec3 := Point_At (Track.Next (I), S.W_R, 0.03);
            W : constant Float := S.W_L + S.W_R;
         begin
            Add (Road_B, (AL, Up, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
            Add (Road_B, (BL, Up, 1.0, 1.0, 1.0, Checker, 0.0, Track.Spacing));
            Add (Road_B, (BR, Up, 1.0, 1.0, 1.0, Checker, W, Track.Spacing));
            Add (Road_B, (AL, Up, 1.0, 1.0, 1.0, Checker, 0.0, 0.0));
            Add (Road_B, (BR, Up, 1.0, 1.0, 1.0, Checker, W, Track.Spacing));
            Add (Road_B, (AR, Up, 1.0, 1.0, 1.0, Checker, W, 0.0));
         end;
      end Arch;
   begin
      Arch (0, (0.05, 0.28, 0.10));
      Arch (Natural (Track.Stage_End / Track.Spacing), (0.42, 0.06, 0.05));
   end Build_Stage;

   procedure Build_Guide is
      B : Builder;
      Half : constant := 0.2;
      Lift : constant := 0.05;
   begin
      Delete (Guide_Line);
      for I in 0 .. Track.Count - 1 loop
         declare
            A : Track.Sample renames Track.Samples (I);
            N : Track.Sample renames Track.Samples (Track.Next (I));
            A_L : constant Vec3 := Point_At (I, A.Line_D - Half, Lift);
            A_R : constant Vec3 := Point_At (I, A.Line_D + Half, Lift);
            N_L : constant Vec3 := Point_At (Track.Next (I), N.Line_D - Half, Lift);
            N_R : constant Vec3 := Point_At (Track.Next (I), N.Line_D + Half, Lift);
            Up : constant Vec3 := (0.0, 1.0, 0.0);
            U0 : constant Float := A.S;
            U1 : constant Float := A.S + Track.Spacing;
         begin
            Add (B, (A_L, Up, A.Line_V, 0.0, 0.0, Mesh.Guide, U0, 0.0));
            Add (B, (N_L, Up, N.Line_V, 0.0, 0.0, Mesh.Guide, U1, 0.0));
            Add (B, (N_R, Up, N.Line_V, 0.0, 0.0, Mesh.Guide, U1, 0.0));
            Add (B, (A_L, Up, A.Line_V, 0.0, 0.0, Mesh.Guide, U0, 0.0));
            Add (B, (N_R, Up, N.Line_V, 0.0, 0.0, Mesh.Guide, U1, 0.0));
            Add (B, (A_R, Up, A.Line_V, 0.0, 0.0, Mesh.Guide, U0, 0.0));
         end;
      end loop;
      Guide_Line := Upload (B);
   end Build_Guide;

   procedure Build is
      G, R, O : Builder;
   begin
      Delete (Ground);
      Delete (Road);
      Delete (Static);
      for IZ in 0 .. Tiles_N - 1 loop
         for IX in 0 .. Tiles_N - 1 loop
            Delete (Tiles (IX, IZ));
         end loop;
      end loop;
      if TB = null then
         TB := new Tile_Builders;
      end if;
      Build_Terrain (G);
      Build_Horizon (G);
      Build_Road (R);
      Build_Edges (R, G);
      if Track.Is_Stage then
         Build_Stage (O, R);
      elsif Track.Is_City then
         Build_City (O);
         Build_Start (O, R);
      else
         Build_Barriers;
         Build_Start (O, R);
         Build_Boards (O);
      end if;
      Build_Trees;
      Ground := Upload (G);
      Road := Upload (R);
      Static := Upload (O);
      for IZ in 0 .. Tiles_N - 1 loop
         for IX in 0 .. Tiles_N - 1 loop
            Tiles (IX, IZ) := Upload (TB (IX, IZ));
         end loop;
      end loop;
   end Build;

end Scenery;
