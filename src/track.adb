--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Interfaces;

package body Track is

   use Ada.Numerics.Elementary_Functions;
   use Ada.Strings.Unbounded;

   type Float_List is array (Natural range <>) of Float;

   Pi : constant := 3.14159_26535;

   --  X, Z and height in metres, half width of the road, banking in degrees
   --  (+ the right side lower, for a right hander)
   type Point is record
      X, Z, Y, W, B : Float;
   end record;
   type Point_Array is array (Positive range <>) of Point;
   type Point_Access is access Point_Array;

   type Road_Info is record
      Name : Unbounded_String;
      Stage : Boolean := False;
      Finish_X, Finish_Z : Float := 0.0;
      Points : Point_Access;
   end record;

   Roads : array (Track_Id) of Road_Info;
   Road_Count : Natural := 0;
   Read_Yet : Boolean := False;

   Current : Track_Id := 1;

   --  One road from its file; on a fault, Bad_Track with the line it was on
   procedure Read_Road (File : String; R : out Road_Info) is
      use Ada.Text_IO;
      F : File_Type;
      Line_No : Natural := 0;
      Buffer : array (1 .. 400) of Point;
      Used : Natural := 0;
      In_Points : Boolean := False;
      Has_Kind, Has_Name, Has_Finish : Boolean := False;

      procedure Fail (Why : String) is
      begin
         raise Bad_Track with File & ":" & Line_No'Image & ": " & Why;
      end Fail;

      function Word_End (S : String; From : Positive) return Natural is
         E : Natural := From;
      begin
         while E <= S'Last and then S (E) not in ' ' | ASCII.HT loop
            E := E + 1;
         end loop;
         return E - 1;
      end Word_End;

      procedure Numbers (S : String; V : out Float_List; Count : out Natural) is
         I : Natural := S'First;
      begin
         Count := 0;
         while I <= S'Last loop
            if S (I) in ' ' | ASCII.HT then
               I := I + 1;
            else
               declare
                  E : constant Natural := Word_End (S, I);
               begin
                  Count := Count + 1;
                  if Count > V'Length then
                     Fail ("too many numbers");
                  end if;
                  begin
                     V (V'First + Count - 1) := Float'Value (S (I .. E));
                  exception
                     when Constraint_Error =>
                        Fail ("not a number: " & S (I .. E));
                  end;
                  I := E + 1;
               end;
            end if;
         end loop;
      end Numbers;
   begin
      Open (F, In_File, File);
      R := (others => <>);
      while not End_Of_File (F) loop
         Line_No := Line_No + 1;
         declare
            Raw : constant String := Get_Line (F);
            Hash : constant Natural := Ada.Strings.Fixed.Index (Raw, "#");
            Line : constant String :=
              Ada.Strings.Fixed.Trim ((if Hash > 0 then Raw (Raw'First .. Hash - 1) else Raw),
                                      Ada.Strings.Both);
         begin
            if Line = "" then
               null;
            elsif In_Points then
               declare
                  V : Float_List (1 .. 5);
                  N : Natural;
               begin
                  Numbers (Line, V, N);
                  if N /= 5 then
                     Fail ("a point is x z height half-width banking");
                  end if;
                  if V (4) < 2.0 or else V (4) > 30.0 then
                     Fail ("half-width should be 2 to 30 metres");
                  end if;
                  if Used = Buffer'Last then
                     Fail ("more points than a road may have");
                  end if;
                  Used := Used + 1;
                  Buffer (Used) := (V (1), V (2), V (3), V (4), V (5));
               end;
            else
               declare
                  E : constant Natural := Word_End (Line, Line'First);
                  Key : constant String := Line (Line'First .. E);
                  Rest : constant String :=
                    Ada.Strings.Fixed.Trim (Line (E + 1 .. Line'Last), Ada.Strings.Both);
               begin
                  if Key = "name" then
                     R.Name := To_Unbounded_String (Rest);
                     Has_Name := Rest /= "";
                  elsif Key = "kind" then
                     if Rest = "stage" then
                        R.Stage := True;
                     elsif Rest /= "circuit" then
                        Fail ("kind is circuit or stage");
                     end if;
                     Has_Kind := True;
                  elsif Key = "finish" then
                     declare
                        V : Float_List (1 .. 2);
                        N : Natural;
                     begin
                        Numbers (Rest, V, N);
                        if N /= 2 then
                           Fail ("finish is x z");
                        end if;
                        R.Finish_X := V (1);
                        R.Finish_Z := V (2);
                        Has_Finish := True;
                     end;
                  elsif Key = "points" then
                     In_Points := True;
                  else
                     Fail ("not a setting: " & Key);
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F);
      if not Has_Name then
         Fail ("it has no name");
      elsif not Has_Kind then
         Fail ("it has no kind");
      elsif R.Stage and then not Has_Finish then
         Fail ("a stage needs a finish");
      elsif Used < 4 then
         Fail ("a road needs at least four points");
      end if;
      R.Points := new Point_Array'(Point_Array (Buffer (1 .. Used)));
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
   end Read_Road;

   procedure Catalogue (Folder : String) is
      use Ada.Directories;
      package Names is new Ada.Containers.Indefinite_Ordered_Sets (String);
      Found : Names.Set;
      It : Search_Type;
      E : Directory_Entry_Type;
   begin
      Road_Count := 0;
      Read_Yet := True;
      Start_Search (It, Folder, "*.track", (Ordinary_File => True, others => False));
      while More_Entries (It) loop
         Get_Next_Entry (It, E);
         Found.Include (Full_Name (E));
      end loop;
      End_Search (It);
      for File of Found loop
         begin
            if Road_Count < Max_Tracks then
               Read_Road (File, Roads (Road_Count + 1));
               Road_Count := Road_Count + 1;
            end if;
         exception
            when X : Bad_Track =>
               --  One bad file does not stop the game; say which and why
               Ada.Text_IO.Put_Line ("Track left out: " & Ada.Exceptions.Exception_Message (X));
         end;
      end loop;
      if Road_Count = 0 then
         raise Bad_Track with "no roads in " & Folder;
      end if;
   end Catalogue;

   procedure Need_Roads is
   begin
      if not Read_Yet then
         Catalogue ("tracks");
      end if;
   end Need_Roads;

   function Track_Count return Natural is
   begin
      Need_Roads;
      return Road_Count;
   end Track_Count;

   function Name (T : Track_Id) return String is
   begin
      Need_Roads;
      return To_String (Roads (T).Name);
   end Name;

   function Stage_Road (T : Track_Id) return Boolean is
   begin
      Need_Roads;
      return Roads (T).Stage;
   end Stage_Road;

   procedure Check_File (File : String; Good : out Boolean; Why : out Positive) is
      R : Road_Info;
   begin
      Good := True;
      Why := 1;
      Read_Road (File, R);
   exception
      when X : Bad_Track =>
         Good := False;
         declare
            M : constant String := Ada.Exceptions.Exception_Message (X);
            C : constant Natural := Ada.Strings.Fixed.Index (M, ":");
            D : constant Natural := Ada.Strings.Fixed.Index (M (C + 1 .. M'Last), ":");
         begin
            Why := Integer'Max (1, Integer'Value (M (C + 1 .. D - 1)));
         end;
   end Check_File;

   function Loaded return Track_Id is (Current);

   function Is_Stage return Boolean is (Roads (Current).Stage);

   function Next (I : Natural; N : Integer := 1) return Natural is
     (Natural ((Integer (I) + N) mod Count));

   ---------------------------------------------------------------------------
   --  Noise
   ---------------------------------------------------------------------------

   function Hash (I, J : Integer) return Float is
      use Interfaces;
      A : Unsigned_32 := Unsigned_32'Mod (Long_Long_Integer (I) * 73_856_093)
        xor Unsigned_32'Mod (Long_Long_Integer (J) * 19_349_663);
   begin
      A := (A xor Shift_Right (A, 13)) * 1_274_126_177;
      A := A xor Shift_Right (A, 16);
      return Float (A and 16#FF_FFFF#) / 16777215.0;
   end Hash;

   function Noise (X, Y : Float) return Float is
      FX : constant Float := Float'Floor (X);
      FY : constant Float := Float'Floor (Y);
      IX : constant Integer := Integer (FX);
      IY : constant Integer := Integer (FY);
      TX : constant Float := X - FX;
      TY : constant Float := Y - FY;
      SX : constant Float := TX * TX * (3.0 - 2.0 * TX);
      SY : constant Float := TY * TY * (3.0 - 2.0 * TY);
      A  : constant Float := Hash (IX, IY);
      B  : constant Float := Hash (IX + 1, IY);
      C  : constant Float := Hash (IX, IY + 1);
      D  : constant Float := Hash (IX + 1, IY + 1);
   begin
      return (A + (B - A) * SX) * (1.0 - SY) + (C + (D - C) * SX) * SY;
   end Noise;

   function Fbm (X, Y : Float; Octaves : Positive := 4) return Float is
      Sum : Float := 0.0;
      Amp : Float := 0.5;
      F   : Float := 1.0;
      Tot : Float := 0.0;
   begin
      for I in 1 .. Octaves loop
         Sum := Sum + Amp * Noise (X * F + Float (I) * 17.3, Y * F - Float (I) * 9.1);
         Tot := Tot + Amp;
         Amp := Amp * 0.5;
         F := F * 2.03;
      end loop;
      return Sum / Tot;
   end Fbm;

   function Clamp (V, Lo, Hi : Float) return Float is
     (Float'Max (Lo, Float'Min (Hi, V)));

   function Smooth (A, B, V : Float) return Float is
      T : constant Float := Clamp ((V - A) / (B - A), 0.0, 1.0);
   begin
      return T * T * (3.0 - 2.0 * T);
   end Smooth;

   ---------------------------------------------------------------------------
   --  The centre line
   ---------------------------------------------------------------------------

   function Catmull (P0, P1, P2, P3, T : Float) return Float is
     (0.5 * (2.0 * P1 + (P2 - P0) * T + (2.0 * P0 - 5.0 * P1 + 4.0 * P2 - P3) * T * T
             + (3.0 * P1 - P0 - 3.0 * P2 + P3) * T * T * T));

   procedure Free is new Ada.Unchecked_Deallocation (Sample_Array, Sample_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Float_Grid, Float_Grid_Access);

   --  Moving average round the loop, Passes times
   procedure Circular_Smooth (V : in out Float_List; Radius : Positive; Passes : Positive := 1) is
      N : constant Integer := V'Length;
      O : Float_List (V'Range);
   begin
      for P in 1 .. Passes loop
         declare
            Sum : Float := 0.0;
         begin
            for K in -Radius .. Radius loop
               Sum := Sum + V (V'First + (K mod N));
            end loop;
            for I in 0 .. N - 1 loop
               O (V'First + I) := Sum / Float (2 * Radius + 1);
               Sum := Sum - V (V'First + ((I - Radius) mod N))
                 + V (V'First + ((I + Radius + 1) mod N));
            end loop;
         end;
         V := O;
      end loop;
   end Circular_Smooth;

   procedure Build_Line (P : Point_Array) is
      Sub   : constant := 24;
      M     : constant Natural := P'Length;
      Total : constant Natural := M * Sub;
      type Dense is record
         X, Y, Z, W, B, L : Float;
      end record;
      type Dense_Array is array (0 .. Total) of Dense;
      type Dense_Access is access Dense_Array;
      procedure Free_Dense is new Ada.Unchecked_Deallocation (Dense_Array, Dense_Access);
      D : Dense_Access := new Dense_Array;

      function At_P (I : Integer) return Point is (P (P'First + (I mod M)));
   begin
      for I in 0 .. M - 1 loop
         for J in 0 .. Sub - 1 loop
            declare
               T  : constant Float := Float (J) / Float (Sub);
               A  : constant Point := At_P (I - 1);
               B  : constant Point := At_P (I);
               C  : constant Point := At_P (I + 1);
               E  : constant Point := At_P (I + 2);
            begin
               D (I * Sub + J) :=
                 (X => Catmull (A.X, B.X, C.X, E.X, T),
                  Y => Catmull (A.Y, B.Y, C.Y, E.Y, T),
                  Z => Catmull (A.Z, B.Z, C.Z, E.Z, T),
                  W => B.W + (C.W - B.W) * T,
                  B => B.B + (C.B - B.B) * T,
                  L => 0.0);
            end;
         end loop;
      end loop;
      D (Total) := D (0);
      for I in 1 .. Total loop
         D (I).L := D (I - 1).L
           + Sqrt ((D (I).X - D (I - 1).X) ** 2 + (D (I).Z - D (I - 1).Z) ** 2);
      end loop;
      Length := D (Total).L;
      Count := Natural (Length / 2.0);
      Spacing := Length / Float (Count);
      if Samples /= null then
         Free (Samples);
      end if;
      Samples := new Sample_Array (0 .. Count - 1);
      declare
         J : Natural := 0;
      begin
         for I in 0 .. Count - 1 loop
            declare
               S : constant Float := Float (I) * Spacing;
            begin
               while J < Total - 1 and then D (J + 1).L < S loop
                  J := J + 1;
               end loop;
               declare
                  T : constant Float := (S - D (J).L) / Float'Max (0.001, D (J + 1).L - D (J).L);
                  A : Dense renames D (J);
                  B : Dense renames D (J + 1);
               begin
                  Samples (I) :=
                    (X => A.X + (B.X - A.X) * T,
                     Y => A.Y + (B.Y - A.Y) * T,
                     Z => A.Z + (B.Z - A.Z) * T,
                     W_L => A.W + (B.W - A.W) * T,
                     W_R => A.W + (B.W - A.W) * T,
                     Bank => -Tan ((A.B + (B.B - A.B) * T) * Pi / 180.0),
                     S => S,
                     others => <>);
               end;
            end;
         end loop;
      end;
      Free_Dense (D);
   end Build_Line;

   procedure Frames is
      subtype R is Natural range 0 .. Count - 1;
      Y, Bk, Wd, H, PX, PZ : Float_List (R);
   begin
      --  Smooth the heights, banking and width along the road, and take
      --  the ripple out of the curvature that the spline leaves in a bend
      for I in R loop
         PX (I) := Samples (I).X;
         PZ (I) := Samples (I).Z;
         Y (I) := Samples (I).Y;
         Bk (I) := Samples (I).Bank;
         Wd (I) := Samples (I).W_L;
      end loop;
      Circular_Smooth (PX, 9, 3);
      Circular_Smooth (PZ, 9, 3);
      Circular_Smooth (Y, 12, 3);
      Circular_Smooth (Bk, 20, 2);
      Circular_Smooth (Wd, 25, 2);
      for I in R loop
         Samples (I).X := PX (I);
         Samples (I).Z := PZ (I);
         Samples (I).Y := Y (I);
         Samples (I).Bank := Bk (I);
         Samples (I).W_L := Wd (I);
         Samples (I).W_R := Wd (I);
      end loop;
      for I in R loop
         declare
            A : Sample renames Samples (Next (I, -1));
            B : Sample renames Samples (Next (I, 1));
            DX : constant Float := B.X - A.X;
            DZ : constant Float := B.Z - A.Z;
            L  : constant Float := Sqrt (DX * DX + DZ * DZ);
         begin
            Samples (I).TX := DX / L;
            Samples (I).TZ := DZ / L;
            Samples (I).RX := -DZ / L;
            Samples (I).RZ := DX / L;
            H (I) := Arctan (DX, -DZ);
         end;
      end loop;
      declare
         K : Float_List (R);
      begin
         for I in R loop
            declare
               D : Float := H (Next (I, 2)) - H (Next (I, -2));
            begin
               if D > Pi then
                  D := D - 2.0 * Pi;
               elsif D < -Pi then
                  D := D + 2.0 * Pi;
               end if;
               K (I) := D / (4.0 * Spacing);
            end;
         end loop;
         Circular_Smooth (K, 3, 2);
         for I in R loop
            Samples (I).Kappa := K (I);
         end loop;
      end;
   end Frames;

   procedure Edges is
      subtype R is Natural range 0 .. Count - 1;
      Thr : constant Float := 1.0 / 170.0;
      Near_R, Near_L, WR, WL : Float_List (R);
   begin
      --  A forest road has none of this: the trees are the barrier
      if Is_Stage then
         for I in R loop
            Samples (I).Kerb_L := 0.0;
            Samples (I).Kerb_R := 0.0;
            Samples (I).Gravel_L := False;
            Samples (I).Gravel_R := False;
            Samples (I).Wall_L := Samples (I).W_L + 14.0;
            Samples (I).Wall_R := Samples (I).W_R + 14.0;
         end loop;
         return;
      end if;
      --  Kerbs: on the inside of a bend, and on the outside coming out of it
      for I in R loop
         declare
            In_R, In_L, Exit_R, Exit_L : Boolean := False;
         begin
            for K in -12 .. 12 loop
               In_R := In_R or else Samples (Next (I, K)).Kappa > Thr;
               In_L := In_L or else Samples (Next (I, K)).Kappa < -Thr;
            end loop;
            for K in 1 .. 26 loop
               Exit_R := Exit_R or else Samples (Next (I, -K)).Kappa > Thr;
               Exit_L := Exit_L or else Samples (Next (I, -K)).Kappa < -Thr;
            end loop;
            Exit_R := Exit_R and then Samples (I).Kappa < Thr * 0.7;
            Exit_L := Exit_L and then Samples (I).Kappa > -Thr * 0.7;
            Samples (I).Kerb_R := (if In_R or else Exit_L then 1.3 else 0.0);
            Samples (I).Kerb_L := (if In_L or else Exit_R then 1.3 else 0.0);
         end;
      end loop;

      --  Run-off: wide on the outside of the bends, gravel there, and the
      --  barrier beyond
      for I in R loop
         Near_R (I) := Float'Max (0.0, Samples (I).Kappa);
         Near_L (I) := Float'Max (0.0, -Samples (I).Kappa);
      end loop;
      Circular_Smooth (Near_R, 30, 2);
      Circular_Smooth (Near_L, 30, 2);
      for I in R loop
         declare
            S : Sample renames Samples (I);
            --  (the outside of a right hander is the left)
            Out_L : constant Float := Clamp (Near_R (I) * 110.0, 0.0, 1.0);
            Out_R : constant Float := Clamp (Near_L (I) * 110.0, 0.0, 1.0);
         begin
            WL (I) := S.W_L + 7.0 + 26.0 * Out_L;
            WR (I) := S.W_R + 7.0 + 26.0 * Out_R;
            --  Not across the centre of a tight bend
            if S.Kappa > 0.002 then
               WR (I) := Float'Min (WR (I), Float'Max (S.W_R + 4.0, 0.8 / S.Kappa));
            elsif S.Kappa < -0.002 then
               WL (I) := Float'Min (WL (I), Float'Max (S.W_L + 4.0, 0.8 / (-S.Kappa)));
            end if;
            S.Gravel_L := Out_L > 0.55;
            S.Gravel_R := Out_R > 0.55;
         end;
      end loop;

      --  Where another part of the circuit runs close by, the barrier
      --  stands half way between them
      declare
         I : Natural := 0;
      begin
         while I < Count loop
            declare
               A : Sample renames Samples (I);
               J : Natural := 0;
            begin
               while J < Count loop
                  declare
                     Sep : constant Integer := abs (I - J);
                     Circ : constant Integer := Integer'Min (Sep, Count - Sep);
                  begin
                     if Float (Circ) * Spacing > 90.0 then
                        declare
                           B : Sample renames Samples (J);
                           DX : constant Float := B.X - A.X;
                           DZ : constant Float := B.Z - A.Z;
                           Lat : constant Float := DX * A.RX + DZ * A.RZ;
                           Along : constant Float := DX * A.TX + DZ * A.TZ;
                           Limit : constant Float := abs Lat * 0.5;
                        begin
                           if abs Along < abs Lat and then abs Lat < 150.0 then
                              for K in -2 .. 2 loop
                                 if Lat > 0.0 then
                                    WR (Next (I, K)) := Float'Min
                                      (WR (Next (I, K)), Float'Max (A.W_R + 3.0, Limit));
                                 else
                                    WL (Next (I, K)) := Float'Min
                                      (WL (Next (I, K)), Float'Max (A.W_L + 3.0, Limit));
                                 end if;
                              end loop;
                           end if;
                        end;
                     end if;
                  end;
                  J := J + 3;
               end loop;
            end;
            I := I + 3;
         end loop;
      end;
      --  (a low barrier never jumps: the smallest nearby, then smoothed)
      declare
         Min_L, Min_R : Float_List (R);
      begin
         for I in R loop
            Min_L (I) := WL (I);
            Min_R (I) := WR (I);
            for K in -10 .. 10 loop
               Min_L (I) := Float'Min (Min_L (I), WL (Next (I, K)));
               Min_R (I) := Float'Min (Min_R (I), WR (Next (I, K)));
            end loop;
         end loop;
         Circular_Smooth (Min_L, 10, 2);
         Circular_Smooth (Min_R, 10, 2);
         for I in R loop
            Samples (I).Wall_L := Float'Max (Samples (I).W_L + 2.6, Min_L (I));
            Samples (I).Wall_R := Float'Max (Samples (I).W_R + 2.6, Min_R (I));
         end loop;
      end;
   end Edges;

   ---------------------------------------------------------------------------
   --  Terrain: follows the road near it, rolls into hills further away
   ---------------------------------------------------------------------------

   procedure Build_Terrain is
      Min_X, Min_Z : Float := Float'Last;
      Max_X, Max_Z : Float := Float'First;
      Margin : constant := 450.0;
   begin
      for I in 0 .. Count - 1 loop
         Min_X := Float'Min (Min_X, Samples (I).X);
         Max_X := Float'Max (Max_X, Samples (I).X);
         Min_Z := Float'Min (Min_Z, Samples (I).Z);
         Max_Z := Float'Max (Max_Z, Samples (I).Z);
      end loop;
      Grid_X0 := Min_X - Margin;
      Grid_Z0 := Min_Z - Margin;
      Grid_NX := Natural ((Max_X - Min_X + 2.0 * Margin) / Grid_Cell) + 1;
      Grid_NZ := Natural ((Max_Z - Min_Z + 2.0 * Margin) / Grid_Cell) + 1;
      if Grid /= null then
         Free (Grid);
      end if;
      Grid := new Float_Grid (0 .. Grid_NX * Grid_NZ - 1);

      declare
         Stride : constant := 4;   --  every 8 m of track
         N : constant Natural := Count / Stride;
         type Coarse is record
            X, Z, Y : Float;
         end record;
         C : array (0 .. N - 1) of Coarse;
      begin
         for I in C'Range loop
            C (I) := (Samples (I * Stride).X, Samples (I * Stride).Z, Samples (I * Stride).Y);
         end loop;
         for IZ in 0 .. Grid_NZ - 1 loop
            for IX in 0 .. Grid_NX - 1 loop
               declare
                  X : constant Float := Grid_X0 + Float (IX) * Grid_Cell;
                  Z : constant Float := Grid_Z0 + Float (IZ) * Grid_Cell;
                  Sum_W, Sum_H : Float := 0.0;
                  Best : Float := Float'Last;
                  Hills : constant Float :=
                    (Fbm (X / 340.0, Z / 340.0, 4) - 0.5) * 70.0
                    + (Fbm (X / 60.0 + 40.0, Z / 60.0, 3) - 0.5) * 5.0;
               begin
                  for K in C'Range loop
                     declare
                        D2 : constant Float := (C (K).X - X) ** 2 + (C (K).Z - Z) ** 2 + 16.0;
                        W  : constant Float := 1.0 / (D2 * D2);
                     begin
                        Sum_W := Sum_W + W;
                        Sum_H := Sum_H + W * C (K).Y;
                        Best := Float'Min (Best, D2);
                     end;
                  end loop;
                  declare
                     Dist : constant Float := Sqrt (Best);
                     Road : constant Float := Sum_H / Sum_W;
                     Far  : constant Float := Smooth (28.0, 170.0, Dist);
                  begin
                     Grid (IZ * Grid_NX + IX) := Road - 0.2 + Far * (Hills + Far * 12.0);
                  end;
               end;
            end loop;
         end loop;
      end;
   end Build_Terrain;

   function Terrain_Height (X, Z : Float) return Float is
      FX : constant Float := (X - Grid_X0) / Grid_Cell;
      FZ : constant Float := (Z - Grid_Z0) / Grid_Cell;
      IX : constant Integer := Integer'Max (0, Integer'Min (Grid_NX - 2, Integer (Float'Floor (FX))));
      IZ : constant Integer := Integer'Max (0, Integer'Min (Grid_NZ - 2, Integer (Float'Floor (FZ))));
      TX : constant Float := Clamp (FX - Float (IX), 0.0, 1.0);
      TZ : constant Float := Clamp (FZ - Float (IZ), 0.0, 1.0);
      A  : constant Float := Grid (IZ * Grid_NX + IX);
      B  : constant Float := Grid (IZ * Grid_NX + IX + 1);
      C  : constant Float := Grid ((IZ + 1) * Grid_NX + IX);
      D  : constant Float := Grid ((IZ + 1) * Grid_NX + IX + 1);
   begin
      return (A + (B - A) * TX) * (1.0 - TZ) + (C + (D - C) * TX) * TZ;
   end Terrain_Height;

   function Road_Height (I : Natural; D : Float) return Float is
      S : Sample renames Samples (I);
      E : constant Float := Clamp (D, -S.W_L, S.W_R);
   begin
      return S.Y + E * S.Bank;
   end Road_Height;

   ---------------------------------------------------------------------------
   --  Where am I
   ---------------------------------------------------------------------------

   function Find_Nearest (X, Z : Float) return Natural is
      Best : Natural := 0;
      B_D  : Float := Float'Last;
   begin
      for I in 0 .. Count - 1 loop
         declare
            D : constant Float := (Samples (I).X - X) ** 2 + (Samples (I).Z - Z) ** 2;
         begin
            if D < B_D then
               B_D := D;
               Best := I;
            end if;
         end;
      end loop;
      return Best;
   end Find_Nearest;

   procedure Locate (X, Z : Float; Hint : in out Natural; Index : out Natural;
                     T, D : out Float)
   is
      function D2 (I : Natural) return Float is
        ((Samples (I).X - X) ** 2 + (Samples (I).Z - Z) ** 2);
      I : Natural := (if Hint < Count then Hint else 0);
      Cur : Float := D2 (I);
      Tries : Natural := 0;
   begin
      --  Downhill along the track, from the last answer
      loop
         declare
            F : constant Natural := Next (I, 1);
            B : constant Natural := Next (I, -1);
            DF : constant Float := D2 (F);
            DB : constant Float := D2 (B);
         begin
            if DF < Cur then
               I := F;
               Cur := DF;
            elsif DB < Cur then
               I := B;
               Cur := DB;
            else
               exit;
            end if;
         end;
         Tries := Tries + 1;
         exit when Tries > 200;
      end loop;
      Hint := I;
      declare
         A : Sample renames Samples (I);
         Along : constant Float := (X - A.X) * A.TX + (Z - A.Z) * A.TZ;
      begin
         if Along < 0.0 then
            I := Next (I, -1);
         end if;
      end;
      declare
         A : Sample renames Samples (I);
         B : Sample renames Samples (Next (I, 1));
         Along : constant Float := (X - A.X) * A.TX + (Z - A.Z) * A.TZ;
      begin
         T := Clamp (Along / Spacing, 0.0, 1.0);
         declare
            RX : constant Float := A.RX + (B.RX - A.RX) * T;
            RZ : constant Float := A.RZ + (B.RZ - A.RZ) * T;
            CX : constant Float := A.X + (B.X - A.X) * T;
            CZ : constant Float := A.Z + (B.Z - A.Z) * T;
         begin
            D := (X - CX) * RX + (Z - CZ) * RZ;
         end;
      end;
      Index := I;
   end Locate;

   function In_Pit_Box (Index : Natural; D : Float) return Boolean is
      S : Sample renames Samples (Index);
   begin
      return S.S in Pit_From .. Pit_To
        and then not Is_Stage
        and then D < 0.0
        and then -D > S.W_L + S.Kerb_L
        and then -D - S.W_L - S.Kerb_L < Pit_Wide;
   end In_Pit_Box;

   procedure Query (X, Z : Float; Hint : in out Natural; C : out Contact) is
      I : Natural;
      T, D : Float;
   begin
      Locate (X, Z, Hint, I, T, D);
      declare
         A : Sample renames Samples (I);
         B : Sample renames Samples (Next (I, 1));
         W_L : constant Float := A.W_L + (B.W_L - A.W_L) * T;
         W_R : constant Float := A.W_R + (B.W_R - A.W_R) * T;
         Y0  : constant Float := A.Y + (B.Y - A.Y) * T;
         Bk  : constant Float := A.Bank + (B.Bank - A.Bank) * T;
         S   : constant Float := A.S + Spacing * T;
         Edge : constant Float := (if D > 0.0 then W_R else W_L);
         Over : constant Float := abs D - Edge;
         Kerb_W : constant Float := (if D > 0.0 then A.Kerb_R else A.Kerb_L);
         Gravel_Here : constant Boolean := (if D > 0.0 then A.Gravel_R else A.Gravel_L);
         Road : constant Float := Y0 + Clamp (D, -W_L, W_R) * Bk;
      begin
         C.Index := I;
         C.T := T;
         C.D := D;
         if Is_Stage and then Over <= 0.0 then
            --  Loose gravel over hard earth: long waves, washboard, stones
            --  and the ruts of every car before
            C.Surf := Dirt;
            C.Y := Road
              + 0.11 * (Noise (S / 17.0, D / 7.0) - 0.5)
              + 0.035 * (Noise (S / 2.9, D / 2.2 + 9.0) - 0.5)
              + 0.014 * (Noise (S / 0.65, D / 0.6 + 30.0) - 0.5)
              - 0.02 * Smooth (0.0, 0.5, 1.0 - abs (abs (D) - 0.85));
         elsif Over <= 0.0 or else In_Pit_Box (I, D) then
            C.Surf := Asphalt;
            C.Y := Road + 0.0035 * (Noise (S / 3.5, D / 2.5) - 0.5)
                        + 0.0016 * (Noise (S / 1.1, D / 0.8 + 50.0) - 0.5);
         elsif Kerb_W > 0.0 and then Over < Kerb_W then
            --  Raised, with ribs that rattle the car
            declare
               Rib : constant Float := abs (S / 1.5 - Float'Floor (S / 1.5) - 0.5) * 2.0;
            begin
               C.Surf := Kerb;
               C.Y := Road + 0.045 * Smooth (0.0, 0.5, Over) + 0.012 * Rib;
            end;
         else
            declare
               Out_D : constant Float := Over - Kerb_W;
               Blend : constant Float := Smooth (0.0, Shoulder, Out_D);
               Earth : constant Float :=
                 (if Blend > 0.0 then Terrain_Height (X, Z) else Road);
            begin
               C.Surf := (if Gravel_Here and then Out_D < 22.0 then Gravel else Grass);
               C.Y := Road + (Earth - Road) * Blend
                 + (if C.Surf = Gravel
                    then 0.025 * (Noise (X / 0.7, Z / 0.7) - 0.5)
                    else 0.05 * (Noise (X / 2.2, Z / 2.2) - 0.5));
            end;
         end if;
      end;
   end Query;

   function Line_Point (I : Natural; Extra_D : Float := 0.0;
                        X, Z : out Float) return Boolean is
      S : Sample renames Samples (I);
      D : constant Float := S.Line_D + Extra_D;
   begin
      X := S.X + S.RX * D;
      Z := S.Z + S.RZ * D;
      return True;
   end Line_Point;

   ---------------------------------------------------------------------------
   --  The racing line: an elastic band pulled tight between the kerbs
   ---------------------------------------------------------------------------

   procedure Build_Racing_Line is
      subtype R is Natural range 0 .. Count - 1;
      D : Float_List (R) := (others => 0.0);

      function PX (I : Natural) return Float is (Samples (I).X + Samples (I).RX * D (I));
      function PZ (I : Natural) return Float is (Samples (I).Z + Samples (I).RZ * D (I));

      procedure Relax (K : Positive; Iterations : Positive) is
      begin
         for It in 1 .. Iterations loop
            for I in R loop
               declare
                  A : constant Natural := Next (I, -K);
                  B : constant Natural := Next (I, K);
                  MX : constant Float := (PX (A) + PX (B)) * 0.5;
                  MZ : constant Float := (PZ (A) + PZ (B)) * 0.5;
                  S : Sample renames Samples (I);
                  Move : constant Float := (MX - PX (I)) * S.RX + (MZ - PZ (I)) * S.RZ;
               begin
                  D (I) := Clamp (D (I) + 0.5 * Move, -(S.W_L - 1.3), S.W_R - 1.3);
               end;
            end loop;
         end loop;
      end Relax;
   begin
      Relax (60, 120);
      Relax (30, 150);
      Relax (14, 200);
      Circular_Smooth (D, 6, 3);
      for I in R loop
         Samples (I).Line_D := D (I);
      end loop;
      declare
         K : Float_List (R);
      begin
         for I in R loop
            declare
               AX : constant Float := PX (I) - PX (Next (I, -4));
               AZ : constant Float := PZ (I) - PZ (Next (I, -4));
               BX : constant Float := PX (Next (I, 4)) - PX (I);
               BZ : constant Float := PZ (Next (I, 4)) - PZ (I);
               Ang : constant Float := Arctan (AX * BZ - AZ * BX, AX * BX + AZ * BZ);
            begin
               K (I) := Ang / (0.5 * (Sqrt (AX * AX + AZ * AZ) + Sqrt (BX * BX + BZ * BZ)));
            end;
         end loop;
         Circular_Smooth (K, 3, 2);
         for I in R loop
            Samples (I).Line_K := K (I);
         end loop;
      end;
   end Build_Racing_Line;

   procedure Compute_Speeds (Mu, Down_Per_V2, Power_Per_Mass,
                             Drag_Per_V2, Brake_Acc : Float)
   is
      subtype R is Natural range 0 .. Count - 1;
      V : Float_List (R);
   begin
      for I in R loop
         declare
            S : Sample renames Samples (I);
            K : constant Float := abs S.Line_K;
            --  Banking helps: a share of gravity turns the car
            Bank_Help : constant Float :=
              (if S.Line_K > 0.0 then -S.Bank else S.Bank) * 9.81;
            Den : constant Float := K - Mu * Down_Per_V2;
         begin
            V (I) := (if Den <= 0.00005 then 120.0
                      else Float'Min (120.0, Sqrt (Float'Max (2.0, Mu * 9.81 + Bank_Help) / Den)));
         end;
      end loop;
      --  Accelerating and braking limits, twice round so it closes
      for Pass in 1 .. 2 loop
         for I in R loop
            declare
               P : constant Natural := Next (I, -1);
               VP : constant Float := V (P);
               K : constant Float := abs Samples (P).Line_K;
               Lat : constant Float := VP * VP * K;
               Grip : constant Float := Mu * (9.81 + Down_Per_V2 * VP * VP);
               Left : constant Float := Sqrt (Float'Max (0.2, Grip * Grip - Lat * Lat));
               Grade : constant Float := (Samples (I).Y - Samples (P).Y) / Spacing * 9.81;
               A : constant Float := Float'Min
                 (Left, Power_Per_Mass / Float'Max (6.0, VP)) - Drag_Per_V2 * VP * VP - Grade;
            begin
               V (I) := Float'Min (V (I), Sqrt (Float'Max (1.0, VP * VP + 2.0 * Float'Max (A, 0.0) * Spacing)));
            end;
         end loop;
         for I in reverse R loop
            declare
               N : constant Natural := Next (I, 1);
               VN : constant Float := V (N);
               K : constant Float := abs Samples (N).Line_K;
               Lat : constant Float := VN * VN * K;
               Grip : constant Float := Mu * (9.81 + Down_Per_V2 * VN * VN);
               Left : constant Float := Sqrt (Float'Max (0.2, Grip * Grip - Lat * Lat));
               Grade : constant Float := (Samples (N).Y - Samples (I).Y) / Spacing * 9.81;
               A : constant Float := Float'Min (Left, Brake_Acc) + Drag_Per_V2 * VN * VN + Grade;
            begin
               V (I) := Float'Min (V (I), Sqrt (VN * VN + 2.0 * Float'Max (A, 1.0) * Spacing));
            end;
         end loop;
      end loop;
      Circular_Smooth (V, 2, 1);
      for I in R loop
         Samples (I).Line_V := V (I);
      end loop;
   end Compute_Speeds;

   ---------------------------------------------------------------------------
   --  Trees: woods in clumps on a circuit, nearly everywhere on a stage
   ---------------------------------------------------------------------------

   Tree_Cell : constant := 12.0;
   type Int_Array is array (Natural range <>) of Natural;
   type Int_Access is access Int_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Int_Array, Int_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Tree_Array, Tree_Access);
   Cell_Head, Tree_Next : Int_Access;
   Cells_X, Cells_Z : Natural := 0;

   procedure Place_Trees is
      use Ada.Numerics.Float_Random;
      Gen : Generator;
      Stage : constant Boolean := Is_Stage;
      Cell : constant Float := (if Stage then 4.5 else 6.0);
      NX : constant Natural := Natural (Float (Grid_NX) * Grid_Cell / Cell) + 1;
      NZ : constant Natural := Natural (Float (Grid_NZ) * Grid_Cell / Cell) + 1;
      type Bool_Grid is array (Natural range <>) of Boolean;
      type Bool_Access is access Bool_Grid;
      procedure Free_B is new Ada.Unchecked_Deallocation (Bool_Grid, Bool_Access);
      Taken : Bool_Access := new Bool_Grid (0 .. NX * NZ - 1);
      Max_Trees : constant Natural := (if Stage then 16_000 else 7000);
      Found : constant Tree_Access := new Tree_Array (1 .. Max_Trees);
      Placed : Natural := 0;
   begin
      Reset (Gen, 4711);
      Taken.all := (others => False);
      --  Mark the circuit and what stands near it
      for I in 0 .. Count - 1 loop
         declare
            S : Sample renames Samples (I);
            --  Grandstands and pits stand near the start: wider there
            Near_Start : constant Boolean := I < 120 or else I > Count - 120;
            Reach : constant Float :=
              (if Stage then S.W_L + (if Near_Start and then (I < 12 or else I > Count - 12) then 8.0
                                      else 3.0)
               else Float'Max (S.Wall_L, S.Wall_R) + (if Near_Start then 50.0 else 14.0));
            C : constant Integer := Integer (Reach / Cell) + 1;
            CX : constant Integer := Integer ((S.X - Grid_X0) / Cell);
            CZ : constant Integer := Integer ((S.Z - Grid_Z0) / Cell);
         begin
            for IZ in Integer'Max (0, CZ - C) .. Integer'Min (NZ - 1, CZ + C) loop
               for IX in Integer'Max (0, CX - C) .. Integer'Min (NX - 1, CX + C) loop
                  declare
                     PX : constant Float := Grid_X0 + (Float (IX) + 0.5) * Cell - S.X;
                     PZ : constant Float := Grid_Z0 + (Float (IZ) + 0.5) * Cell - S.Z;
                  begin
                     if PX * PX + PZ * PZ < (Reach + (if Stage then Cell * 0.7 else 0.0)) ** 2 then
                        Taken (IZ * NX + IX) := True;
                     end if;
                  end;
               end loop;
            end loop;
         end;
      end loop;

      --  A stage: the trees close in on the road first, then the rest of the wood
      if Stage then
         for I in 0 .. Count - 1 loop
            if I < 8 or else I > Count - 8 then
               null;
            else
               for Side in 0 .. 1 loop
                  declare
                     P : Sample renames Samples (I);
                     --  A few clearings, so that it is not one long green wall
                     Glade : constant Boolean := Fbm (P.S / 240.0, Float (Side) * 31.0, 2) < 0.34;
                     Sgn : constant Float := (if Side = 0 then -1.0 else 1.0);
                     Far : constant Float := P.W_L + 3.2 + 22.0 * Random (Gen) ** 1.3;
                     X : constant Float := P.X + P.RX * Sgn * Far + (Random (Gen) - 0.5) * 1.5;
                     Z : constant Float := P.Z + P.RZ * Sgn * Far + (Random (Gen) - 0.5) * 1.5;
                     IX : constant Integer := Integer (Float'Floor ((X - Grid_X0) / Cell));
                     IZ : constant Integer := Integer (Float'Floor ((Z - Grid_Z0) / Cell));
                     Roll : constant Float := Random (Gen);
                  begin
                     if not Glade and then Roll < 0.55
                       and then IX in 0 .. NX - 1 and then IZ in 0 .. NZ - 1
                       and then not Taken (IZ * NX + IX) and then Placed < Max_Trees
                     then
                        declare
                           H : constant Float := 8.0 + Random (Gen) * 11.0;
                           Tint : constant Float := Random (Gen);
                           Pine : constant Boolean :=
                             Fbm (X / 300.0 + 90.0, Z / 300.0, 2) > 0.34;
                        begin
                           Placed := Placed + 1;
                           Found (Placed) :=
                             (X => X, Y => Terrain_Height (X, Z) - 0.1, Z => Z,
                              H => (if Pine then H * 1.2 else H), Tint => Tint, Pine => Pine);
                           Taken (IZ * NX + IX) := True;
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end loop;
      end if;

      for Try in 1 .. (if Stage then 150_000 else 50_000) loop
         declare
            X : constant Float := Grid_X0 + Random (Gen) * Float (NX - 1) * Cell;
            Z : constant Float := Grid_Z0 + Random (Gen) * Float (NZ - 1) * Cell;
            IX : constant Natural := Natural (Float'Floor ((X - Grid_X0) / Cell));
            IZ : constant Natural := Natural (Float'Floor ((Z - Grid_Z0) / Cell));
            Wood : constant Float := Fbm (X / 180.0, Z / 180.0, 3);
         begin
            if IZ * NX + IX <= Taken'Last and then not Taken (IZ * NX + IX)
              and then Wood > (if Stage then 0.26 else 0.46)
              and then Placed < Max_Trees
            then
               declare
                  H : constant Float := 7.0 + Random (Gen) * 11.0;
                  Tint : constant Float := Random (Gen);
                  Pine : constant Boolean :=
                    Fbm (X / 300.0 + 90.0, Z / 300.0, 2) > (if Stage then 0.34 else 0.5);
               begin
                  Placed := Placed + 1;
                  Found (Placed) :=
                    (X => X, Y => Terrain_Height (X, Z) - 0.1, Z => Z,
                     H => (if Pine then H * 1.2 else H), Tint => Tint, Pine => Pine);
                  if Stage then
                     Taken (IZ * NX + IX) := True;
                  end if;
               end;
            end if;
         end;
      end loop;
      Free_B (Taken);
      if Trees /= null then
         Free (Trees);
      end if;
      Trees := new Tree_Array'(Found (1 .. Placed));

      --  For finding the near ones fast
      Cells_X := Natural (Float (Grid_NX) * Grid_Cell / Tree_Cell) + 1;
      Cells_Z := Natural (Float (Grid_NZ) * Grid_Cell / Tree_Cell) + 1;
      if Cell_Head /= null then
         Free (Cell_Head);
         Free (Tree_Next);
      end if;
      Cell_Head := new Int_Array'(0 .. Cells_X * Cells_Z - 1 => 0);
      Tree_Next := new Int_Array'(1 .. Placed => 0);
      for K in Trees'Range loop
         declare
            CI : constant Natural :=
              Natural (Float'Floor ((Trees (K).Z - Grid_Z0) / Tree_Cell)) * Cells_X
              + Natural (Float'Floor ((Trees (K).X - Grid_X0) / Tree_Cell));
         begin
            if CI <= Cell_Head'Last then
               Tree_Next (K) := Cell_Head (CI);
               Cell_Head (CI) := K;
            end if;
         end;
      end loop;
   end Place_Trees;

   procedure Nearest_Tree (X, Z, Reach : Float; Found : out Boolean; TX, TZ : out Float) is
      CX : constant Integer := Integer (Float'Floor ((X - Grid_X0) / Tree_Cell));
      CZ : constant Integer := Integer (Float'Floor ((Z - Grid_Z0) / Tree_Cell));
      Best : Float := Reach * Reach;
   begin
      Found := False;
      TX := 0.0;
      TZ := 0.0;
      if Trees = null or else Cell_Head = null then
         return;
      end if;
      for IZ in Integer'Max (0, CZ - 1) .. Integer'Min (Cells_Z - 1, CZ + 1) loop
         for IX in Integer'Max (0, CX - 1) .. Integer'Min (Cells_X - 1, CX + 1) loop
            declare
               K : Natural := Cell_Head (IZ * Cells_X + IX);
            begin
               while K /= 0 loop
                  declare
                     D2 : constant Float := (Trees (K).X - X) ** 2 + (Trees (K).Z - Z) ** 2;
                  begin
                     if D2 < Best then
                        Best := D2;
                        Found := True;
                        TX := Trees (K).X;
                        TZ := Trees (K).Z;
                     end if;
                  end;
                  K := Tree_Next (K);
               end loop;
            end;
         end loop;
      end loop;
   end Nearest_Tree;

   ---------------------------------------------------------------------------
   --  Pace notes: read off the road, as a co-driver does on the recce
   ---------------------------------------------------------------------------

   procedure Write_Notes is
      Limit : constant Natural := Natural'Min (Count - 1, Natural (Stage_End / Spacing));
      I : Natural := 0;

      procedure Add_Note (N : Note) is
      begin
         if Note_Count < Notes'Last then
            Note_Count := Note_Count + 1;
            Notes (Note_Count) := N;
         end if;
      end Add_Note;

      function Grade_Of (Radius : Float) return Positive is
        (if Radius < 28.0 then 1
         elsif Radius < 45.0 then 2
         elsif Radius < 70.0 then 3
         elsif Radius < 105.0 then 4
         elsif Radius < 160.0 then 5
         else 6);
   begin
      Note_Count := 0;
      while I < Limit loop
         declare
            K : constant Float := Samples (I).Kappa;
         begin
            if abs K > 1.0 / 220.0 then
               declare
                  Sign : constant Boolean := K > 0.0;
                  J : Natural := I;
                  Peak : Float := 0.0;
               begin
                  while J < Limit
                    and then (Samples (J).Kappa > 0.0) = Sign
                    and then abs Samples (J).Kappa > 1.0 / 300.0
                  loop
                     Peak := Float'Max (Peak, abs Samples (J).Kappa);
                     J := J + 1;
                  end loop;
                  J := Natural'Max (J, I + 1);
                  Add_Note ((Kind => (if Sign then Right else Left),
                             S => Samples (I).S,
                             Grade => Grade_Of (1.0 / Peak),
                             Long => Float (J - I) * Spacing > 95.0));
                  I := J;
               end;
            else
               I := I + 1;
            end if;
         end;
      end loop;
      --  Crests, put in their places among the corners
      declare
         Last_Crest : Float := -100.0;
      begin
         for C in 12 .. Limit loop
            declare
               Y : constant Float := Samples (C).Y;
               Rise : constant Float :=
                 2.0 * Y - Samples (Next (C, -15)).Y - Samples (Next (C, 15)).Y;
            begin
               if Rise > 0.7 and then Y >= Samples (Next (C, -1)).Y
                 and then Y >= Samples (Next (C, 1)).Y
                 and then Samples (C).S > Last_Crest + 60.0
                 and then Note_Count < Notes'Last
               then
                  Last_Crest := Samples (C).S;
                  declare
                     At_I : Positive := Note_Count + 1;
                  begin
                     for N in reverse 1 .. Note_Count loop
                        exit when Notes (N).S <= Last_Crest;
                        At_I := N;
                     end loop;
                     Notes (At_I + 1 .. Note_Count + 1) := Notes (At_I .. Note_Count);
                     Notes (At_I) := (Kind => Crest, S => Last_Crest, Grade => 6, Long => False);
                     Note_Count := Note_Count + 1;
                  end;
               end if;
            end;
         end loop;
      end;
   end Write_Notes;

   function Next_Note (From_S : Float) return Natural is
   begin
      for N in 1 .. Note_Count loop
         if Notes (N).S > From_S then
            return N;
         end if;
      end loop;
      return 0;
   end Next_Note;

   procedure Load (T : Track_Id) is
   begin
      Need_Roads;
      Current := T;
      Build_Line (Roads (T).Points.all);
      Frames;
      Edges;
      Build_Terrain;
      Build_Racing_Line;
      Place_Trees;
      if Is_Stage then
         Stage_End := Samples (Find_Nearest (Roads (T).Finish_X, Roads (T).Finish_Z)).S;
      else
         Stage_End := Length;
      end if;
      Write_Notes;
   end Load;

end Track;
