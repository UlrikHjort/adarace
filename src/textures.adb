--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Ada.Unchecked_Deallocation;
with Interfaces;

with GL;

package body Textures is

   use Ada.Numerics.Elementary_Functions;
   use Ada.Numerics.Float_Random;

   Pi : constant := 3.14159_26535;

   type Pixel is record
      R, G, B, A : Interfaces.Unsigned_8;
   end record
     with Convention => C, Size => 32;

   type Image is array (Natural range <>) of aliased Pixel
     with Convention => C;
   type Image_Access is access Image;
   procedure Free is new Ada.Unchecked_Deallocation (Image, Image_Access);

   function Clamp01 (V : Float) return Float is
     (Float'Max (0.0, Float'Min (1.0, V))) with Inline;

   function To_Byte (V : Float) return Interfaces.Unsigned_8 is
     (Interfaces.Unsigned_8 (Clamp01 (V) * 255.0)) with Inline;

   --  Linear light to the sRGB the texture is stored in
   function Encode (V : Float) return Interfaces.Unsigned_8 is
     (To_Byte (Clamp01 (V) ** 0.4545)) with Inline;

   function Hash (X, Y, Salt : Integer) return Float is
      use Interfaces;
      H : Unsigned_32 :=
        Unsigned_32'Mod (X) * 374_761_393 + Unsigned_32'Mod (Y) * 668_265_263
        + Unsigned_32'Mod (Salt) * 2_147_483_647;
   begin
      H := (H xor Shift_Right (H, 13)) * 1_274_126_177;
      H := H xor Shift_Right (H, 16);
      return Float (H and 16#FFFFFF#) / 16_777_216.0;
   end Hash;

   --  Value noise repeating every Period cells
   function Noise (X, Y : Float; Period, Salt : Integer) return Float is
      FX : constant Float := Float'Floor (X);
      FY : constant Float := Float'Floor (Y);
      IX : constant Integer := Integer (FX) mod Period;
      IY : constant Integer := Integer (FY) mod Period;
      JX : constant Integer := (IX + 1) mod Period;
      JY : constant Integer := (IY + 1) mod Period;
      TX0 : constant Float := X - FX;
      TY0 : constant Float := Y - FY;
      TX : constant Float := TX0 * TX0 * (3.0 - 2.0 * TX0);
      TY : constant Float := TY0 * TY0 * (3.0 - 2.0 * TY0);
      A : constant Float := Hash (IX, IY, Salt) + (Hash (JX, IY, Salt) - Hash (IX, IY, Salt)) * TX;
      B : constant Float := Hash (IX, JY, Salt) + (Hash (JX, JY, Salt) - Hash (IX, JY, Salt)) * TX;
   begin
      return A + (B - A) * TY;
   end Noise;

   --  U, V in 0 .. 1; tiles
   function Fbm (U, V : Float; Cells, Octaves, Salt : Integer) return Float is
      Sum : Float := 0.0;
      Amp : Float := 0.5;
      P : Integer := Cells;
   begin
      for O in 1 .. Octaves loop
         Sum := Sum + Amp * Noise (U * Float (P), V * Float (P), P, Salt + O);
         Amp := Amp * 0.5;
         P := P * 2;
      end loop;
      return Sum / (1.0 - Amp * 2.0 * 0.5);
   end Fbm;

   --  Round stones in a grid of Cells: distance to the nearest (0 at its
   --  heart, about 1 in the gaps), which stone it is
   procedure Stones (U, V : Float; Cells, Salt : Integer; D, Which : out Float) is
      X : constant Float := U * Float (Cells);
      Y : constant Float := V * Float (Cells);
      CX : constant Integer := Integer (Float'Floor (X));
      CY : constant Integer := Integer (Float'Floor (Y));
      Best : Float := 9.0;
   begin
      Which := 0.0;
      for DY in -1 .. 1 loop
         for DX in -1 .. 1 loop
            declare
               GX : constant Integer := (CX + DX) mod Cells;
               GY : constant Integer := (CY + DY) mod Cells;
               PX : constant Float := Float (CX + DX) + Hash (GX, GY, Salt) - X;
               PY : constant Float := Float (CY + DY) + Hash (GX, GY, Salt + 1) - Y;
               L : constant Float := PX * PX + PY * PY;
            begin
               if L < Best then
                  Best := L;
                  Which := Hash (GX, GY, Salt + 2);
               end if;
            end;
         end loop;
      end loop;
      D := Sqrt (Best);
   end Stones;

   procedure Upload (Unit : Natural; Img : Image; Size : Positive) is
      use GL;
      Tex : aliased GLuint := 0;
   begin
      glGenTextures (1, Tex'Address);
      glActiveTexture (GLenum (GL_TEXTURE0 + Unit));
      glBindTexture (GL_TEXTURE_2D, Tex);
      glTexImage2D (GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, GLsizei (Size), GLsizei (Size), 0,
                    GL_RGBA, GL_UNSIGNED_BYTE, Img (Img'First)'Address);
      glGenerateMipmap (GL_TEXTURE_2D);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY, 16);
   end Upload;

   ---------------------------------------------------------------------------

   procedure Paint_Asphalt is
      Size : constant := 1024;
      Img : Image_Access := new Image (0 .. Size * Size - 1);
   begin
      for Y in 0 .. Size - 1 loop
         for X in 0 .. Size - 1 loop
            declare
               U : constant Float := Float (X) / Float (Size);
               V : constant Float := Float (Y) / Float (Size);
               D, W : Float;
               Blotch : constant Float := Fbm (U, V, 8, 4, 11);
            begin
               Stones (U, V, 170, 21, D, W);
               declare
                  Stone : constant Float := Clamp01 (1.0 - D * 1.25);
                  Tone : constant Float :=
                    0.032 + 0.050 * W * W + (if W > 0.97 then 0.035 else 0.0);
                  Grey : constant Float :=
                    (0.018 + (Tone - 0.018) * Stone) * (0.75 + 0.5 * Blotch);
               begin
                  Img (Y * Size + X) :=
                    (Encode (Grey * 1.02), Encode (Grey), Encode (Grey * 0.97),
                     To_Byte (0.15 + 0.8 * Stone));
               end;
            end;
         end loop;
      end loop;
      Upload (Unit_Asphalt, Img.all, Size);
      Free (Img);
   end Paint_Asphalt;

   procedure Paint_Gravel is
      Size : constant := 1024;
      Img : Image_Access := new Image (0 .. Size * Size - 1);
   begin
      for Y in 0 .. Size - 1 loop
         for X in 0 .. Size - 1 loop
            declare
               U : constant Float := Float (X) / Float (Size);
               V : constant Float := Float (Y) / Float (Size);
               D, W, D2, W2 : Float;
               Earth : constant Float := Fbm (U, V, 6, 5, 31);
            begin
               Stones (U, V, 46, 41, D, W);
               Stones (U, V, 130, 51, D2, W2);
               declare
                  Big : constant Float := Clamp01 (1.1 - D * 1.5);
                  Small : constant Float := Clamp01 (1.0 - D2 * 1.4);
                  Height : constant Float :=
                    Float'Max (Big * (0.6 + 0.4 * W), Small * 0.55) + 0.1 * Earth;
                  Tone : constant Float :=
                    (0.10 + 0.32 * (if Big > 0.15 then W else W2)) * (0.45 + 0.75 * Height);
               begin
                  Img (Y * Size + X) :=
                    (Encode (Tone * 1.10), Encode (Tone * 0.93), Encode (Tone * 0.72),
                     To_Byte (Height));
               end;
            end;
         end loop;
      end loop;
      Upload (Unit_Gravel, Img.all, Size);
      Free (Img);
   end Paint_Gravel;

   --  Painted in floats so strokes can layer, then encoded
   type Layer is array (Natural range <>) of Float;
   type Layer_Access is access Layer;
   procedure Free is new Ada.Unchecked_Deallocation (Layer, Layer_Access);

   procedure Paint_Grass is
      Size : constant := 1024;
      Gen : Generator;
      Img : Image_Access := new Image (0 .. Size * Size - 1);
      R : Layer_Access := new Layer (0 .. Size * Size - 1);
      G : Layer_Access := new Layer (0 .. Size * Size - 1);
      B : Layer_Access := new Layer (0 .. Size * Size - 1);
      H : Layer_Access := new Layer (0 .. Size * Size - 1);
   begin
      Reset (Gen, 90);
      for Y in 0 .. Size - 1 loop
         for X in 0 .. Size - 1 loop
            declare
               E : constant Float :=
                 Fbm (Float (X) / Float (Size), Float (Y) / Float (Size), 12, 4, 61);
               I : constant Natural := Y * Size + X;
            begin
               R (I) := 0.028 + 0.02 * E;
               G (I) := 0.040 + 0.025 * E;
               B (I) := 0.012;
               H (I) := 0.05;
            end;
         end loop;
      end loop;
      --  Blades, lowest first: the upper ones are lighter and in front
      for N in 1 .. 95_000 loop
         declare
            Depth : constant Float := Float (N) / 95_000.0;
            X0 : constant Float := Random (Gen) * Float (Size);
            Y0 : constant Float := Random (Gen) * Float (Size);
            Dir : constant Float := Random (Gen) * 2.0 * Pi;
            Bend : constant Float := (Random (Gen) - 0.5) * 0.06;
            Len : constant Natural := 12 + Natural (Random (Gen) * 22.0);
            Hue : constant Float := Random (Gen);
            Bright : constant Float := (0.35 + 0.65 * Depth) * (0.65 + 0.7 * Random (Gen));
            CR : constant Float := (0.055 + 0.075 * Hue) * Bright;
            CG : constant Float := (0.115 + 0.055 * Hue) * Bright;
            CB : constant Float := (0.022 + 0.012 * Hue) * Bright;
            A : Float := Dir;
            PX : Float := X0;
            PY : Float := Y0;
         begin
            for T in 0 .. Len loop
               declare
                  I : constant Natural :=
                    (Integer (Float'Floor (PY)) mod Size) * Size
                    + Integer (Float'Floor (PX)) mod Size;
                  Alpha : constant Float := 0.9 - 0.5 * Float (T) / Float (Len);
               begin
                  R (I) := R (I) + (CR - R (I)) * Alpha;
                  G (I) := G (I) + (CG - G (I)) * Alpha;
                  B (I) := B (I) + (CB - B (I)) * Alpha;
                  H (I) := Float'Max (H (I), 0.2 + 0.8 * Depth * (1.0 - 0.4 * Float (T) / Float (Len)));
               end;
               PX := PX + Cos (A);
               PY := PY + Sin (A);
               A := A + Bend;
            end loop;
         end;
      end loop;
      for I in Img'Range loop
         Img (I) := (Encode (R (I)), Encode (G (I)), Encode (B (I)), To_Byte (H (I)));
      end loop;
      Upload (Unit_Grass, Img.all, Size);
      Free (Img);
      Free (R);
      Free (G);
      Free (B);
      Free (H);
   end Paint_Grass;

   --  Clear to a mid tone with no alpha: the mipmaps must not fringe dark
   procedure Clear_Card (Img : in out Image; Tone : Float) is
   begin
      Img := (others => (Encode (Tone), Encode (Tone), Encode (Tone), 0));
   end Clear_Card;

   --  A filled ellipse of one grey, with a brighter upper edge
   procedure Leaf (Img : in out Image; Size : Positive; CX, CY, Along, Across, Angle, Tone : Float) is
      C : constant Float := Cos (Angle);
      S : constant Float := Sin (Angle);
      Reach : constant Integer := Integer (Along) + 2;
   begin
      for DY in -Reach .. Reach loop
         for DX in -Reach .. Reach loop
            declare
               A : constant Float := (Float (DX) * C + Float (DY) * S) / Along;
               B : constant Float := (-Float (DX) * S + Float (DY) * C) / Across;
               PX : constant Integer := Integer (CX) + DX;
               PY : constant Integer := Integer (CY) + DY;
            begin
               if A * A + B * B <= 1.0 and then PX in 0 .. Size - 1 and then PY in 0 .. Size - 1 then
                  declare
                     V : constant Interfaces.Unsigned_8 := Encode (Tone * (0.8 + 0.35 * (B + 1.0) * 0.5));
                  begin
                     Img (PY * Size + PX) := (V, V, V, 255);
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Leaf;

   procedure Paint_Leaves is
      Size : constant := 512;
      Gen : Generator;
      Img : Image_Access := new Image (0 .. Size * Size - 1);
   begin
      Reset (Gen, 12);
      Clear_Card (Img.all, 0.32);
      for N in 1 .. 2600 loop
         declare
            Depth : constant Float := Float (N) / 2600.0;
            Ang : constant Float := Random (Gen) * 2.0 * Pi;
            Rad : constant Float := Sqrt (Random (Gen)) * 235.0;
            Edge : constant Float := Rad / 235.0;
         begin
            --  Thinner to the rim, so the clump's edge is single leaves
            if Random (Gen) > Edge ** 3 * 0.7 then
               Leaf (Img.all, Size,
                     256.0 + Rad * Cos (Ang), 256.0 + Rad * Sin (Ang),
                     7.0 + Random (Gen) * 5.0, 3.0 + Random (Gen) * 2.5,
                     Random (Gen) * Pi,
                     (0.12 + 0.55 * Depth) * (0.7 + 0.6 * Random (Gen)));
            end if;
         end;
      end loop;
      Upload (Unit_Leaves, Img.all, Size);
      Free (Img);
   end Paint_Leaves;

   --  A pine branch: the stem down the middle of the card from the bottom
   --  (V = 0, at the trunk) to the tip, with needles sprays either side
   procedure Paint_Needles is
      Size : constant := 512;
      Gen : Generator;
      Img : Image_Access := new Image (0 .. Size * Size - 1);
   begin
      Reset (Gen, 34);
      Clear_Card (Img.all, 0.25);
      for N in 1 .. 7000 loop
         declare
            Depth : constant Float := Float (N) / 7000.0;
            Along : constant Float := Random (Gen);      --  from the trunk
            Width : constant Float := 210.0 * (1.0 - Along) ** 0.8;
            Side : constant Float := (Random (Gen) * 2.0 - 1.0);
            Ang : constant Float := Pi / 2.0 + Side * 0.95 + (Random (Gen) - 0.5) * 0.3;
         begin
            Leaf (Img.all, Size,
                  256.0 + Side * Width * Random (Gen), 8.0 + Along * 490.0,
                  8.0 + Random (Gen) * 8.0, 1.2 + Random (Gen) * 0.8,
                  Ang,
                  (0.14 + 0.5 * Depth) * (0.7 + 0.6 * Random (Gen)));
         end;
      end loop;
      Upload (Unit_Needles, Img.all, Size);
      Free (Img);
   end Paint_Needles;

   procedure Create is
   begin
      Paint_Asphalt;
      Paint_Gravel;
      Paint_Grass;
      Paint_Leaves;
      Paint_Needles;
      GL.glActiveTexture (GL.GL_TEXTURE0);
   end Create;

end Textures;
