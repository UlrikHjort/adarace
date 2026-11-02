--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Triangles on their way to the graphics card.

with GL;
with Math3D;

package Mesh is

   --  How the shader paints a surface (see world.frag)
   Plain   : constant := 0.0;
   Terrain : constant := 1.0;   --  Colour.r: share of gravel
   Asphalt : constant := 2.0;   --  Colour: rubber, metres to the edges; UV: along, across
   Kerb    : constant := 3.0;   --  U: along
   Paint   : constant := 5.0;
   Glass   : constant := 6.0;
   Rubber  : constant := 7.0;
   Lamp    : constant := 8.0;   --  lit, brighter with the brake
   Leaves  : constant := 9.0;
   Needles : constant := 10.0;  --  a pine branch card
   Metal   : constant := 11.0;
   Fence   : constant := 12.0;  --  wire mesh: holes
   Crowd   : constant := 13.0;  --  many small dots
   Checker : constant := 14.0;  --  black and white squares, UV in metres
   Glow    : constant := 15.0;  --  lit by itself
   Armco   : constant := 16.0;  --  corrugated steel rail, V across in metres
   Dirt_Road : constant := 18.0; --  Colour: as asphalt; UV: along, across
   Guide   : constant := 19.0;  --  the driving line: Colour.r its speed, U along
   Dial    : constant := 20.0;  --  an instrument: Colour.r which, UV 0 .. 1
   Facade  : constant := 21.0;  --  a building's front: Colour.r its tint; UV metres
   Water   : constant := 22.0;
   Board   : constant := 17.0;  --  an advert: colour; U along, V up in metres

   type Vertex is record
      P, N : Math3D.Vec3;
      R, G, B, Mat, U, V : Float;
   end record
     with Convention => C;

   type Vertex_Array is array (Natural range <>) of aliased Vertex
     with Convention => C;
   type Vertex_Access is access Vertex_Array;

   type Builder is record
      Data : Vertex_Access;
      Used : Natural := 0;
   end record;

   procedure Add (B : in out Builder; V : Vertex);

   type Color is record
      R, G, B : Float;
   end record;

   procedure Tri (B : in out Builder; A, C, D : Math3D.Vec3; Col : Color; Mat : Float := Plain);
   --  Flat shaded, counter-clockwise from the front

   procedure Quad (B : in out Builder; A, C, D, E : Math3D.Vec3; Col : Color; Mat : Float := Plain);
   --  A C D E in order round the face

   procedure Box (B : in out Builder; Lo, Hi : Math3D.Vec3; Col : Color; Mat : Float := Plain);

   procedure Oriented_Box
     (B : in out Builder; Centre, Along, Up : Math3D.Vec3; L, H, W : Float;
      Col : Color; Mat : Float := Plain);
   --  A box lying along a direction: half sizes L, H, W

   type GPU is record
      VAO, VBO : aliased GL.GLuint := 0;
      Count    : GL.GLsizei := 0;
   end record;

   function Upload (B : in out Builder) return GPU;
   --  Sends it and frees the builder

   procedure Draw (M : GPU);
   procedure Delete (M : in out GPU);

end Mesh;
