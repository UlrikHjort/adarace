--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The circuits: a centre line with elevation, banking and width sampled
--  every two metres, kerbs, run-off and barriers derived from its shape,
--  the terrain around it, and a racing line with a speed for every metre.
--  No graphics here: the physics and the headless tests use this as well.
--
--  World axes: X east, Y up, Z south.  Lateral distance D is positive to
--  the right of the driving direction.

package Track is

   type Surface_Kind is (Asphalt, Kerb, Grass, Gravel, Dirt);

   type Sample is record
      X, Y, Z  : Float := 0.0;
      TX, TZ   : Float := 0.0;    --  unit tangent
      RX, RZ   : Float := 0.0;    --  unit vector to the right
      W_L, W_R : Float := 6.0;    --  road edge, from the centre
      Bank     : Float := 0.0;    --  rise per metre to the right
      Kappa    : Float := 0.0;    --  curvature, + turns right
      Kerb_L, Kerb_R : Float := 0.0;   --  kerb width, 0 none
      Gravel_L, Gravel_R : Boolean := False;
      Wall_L, Wall_R : Float := 20.0;  --  barrier, from the centre
      S        : Float := 0.0;    --  metres from the start line
      Line_D   : Float := 0.0;    --  racing line, lateral
      Line_K   : Float := 0.0;    --  its curvature
      Line_V   : Float := 50.0;   --  its speed, m/s
   end record;

   type Sample_Array is array (Natural range <>) of Sample;
   type Sample_Access is access Sample_Array;

   Samples : Sample_Access;       --  0 .. Count - 1, closed loop
   Count   : Natural := 0;
   Length  : Float := 0.0;
   Spacing : Float := 2.0;

   --  The roads are files in tracks/, in the order of their names
   Max_Tracks : constant := 32;
   subtype Track_Id is Positive range 1 .. Max_Tracks;

   function Track_Count return Natural;
   function Name (T : Track_Id) return String;
   function Stage_Road (T : Track_Id) return Boolean;

   Bad_Track : exception;

   procedure Check_File (File : String; Good : out Boolean; Why : out Positive);
   --  Whether a file is a road that can be driven; Why: the line it fails on

   procedure Catalogue (Folder : String);
   --  Read the roads from another folder (normally done by itself)

   procedure Load (T : Track_Id);
   --  Build the circuit (a second or so).  Not while the simulation runs.

   function Loaded return Track_Id;

   function Is_City return Boolean;
   --  A street circuit: walls at the kerb, buildings behind them, maybe water

   --  Water (a harbour basin), if the road has one
   Has_Water : Boolean := False;
   Water_X, Water_Z, Water_R, Water_Y : Float := 0.0;

   --  The buildings of a street circuit, each a block standing along the road
   type Building is record
      X, Y, Z : Float := 0.0;     --  centre of the footprint, on the ground
      TX, TZ : Float := 1.0;      --  along the front
      Len, Depth, Height : Float := 10.0;
      Tint : Float := 0.0;
   end record;
   type Building_Array is array (Positive range <>) of Building;
   type Building_Access is access Building_Array;
   Buildings : Building_Access;

   function Is_Stage return Boolean;
   --  A rally stage: loose road, no barriers, trees that are really there.
   --  It runs from S = 0 to Stage_End; the road goes on from there back to
   --  the start, so that all that works on a closed loop works here too.

   Stage_End : Float := 0.0;

   --  The state of the ground, 0 .. 1 (set with the session's weather)
   Wet, Snow : Float := 0.0;

   --  Trees, for the picture and on a stage to hit
   type Tree is record
      X, Y, Z, H, Tint : Float := 0.0;
      Pine : Boolean := False;
   end record;
   type Tree_Array is array (Positive range <>) of Tree;
   type Tree_Access is access Tree_Array;
   Trees : Tree_Access;
   Tree_Radius : constant := 0.35;

   procedure Nearest_Tree (X, Z, Reach : Float; Found : out Boolean; TX, TZ : out Float);
   --  The nearest trunk within Reach of a point

   --  The co-driver's notes
   type Note_Kind is (Left, Right, Crest);
   type Note is record
      Kind  : Note_Kind := Crest;
      S     : Float := 0.0;           --  where it starts
      Grade : Positive range 1 .. 6 := 6;  --  1 a hairpin .. 6 nearly flat
      Long  : Boolean := False;
   end record;
   type Note_Array is array (1 .. 400) of Note;
   Notes : Note_Array;
   Note_Count : Natural := 0;

   function Next_Note (From_S : Float) return Natural;
   --  The first note still ahead; 0 when there are none

   type Contact is record
      Index : Natural := 0;   --  sample before the point
      T     : Float := 0.0;   --  0 .. 1 towards the next sample
      D     : Float := 0.0;   --  lateral distance from the centre line
      Y     : Float := 0.0;   --  ground height, bumps included
      Surf  : Surface_Kind := Asphalt;
   end record;

   procedure Query (X, Z : Float; Hint : in out Natural; C : out Contact);
   --  What is under this point.  Hint: the sample found last time (the
   --  search walks from there, so it is cheap and stays on the right part
   --  of the circuit where two parts run close together).

   procedure Locate (X, Z : Float; Hint : in out Natural; Index : out Natural;
                     T, D : out Float);
   --  Only where along the track: no height

   function Find_Nearest (X, Z : Float) return Natural;
   --  Search the whole loop

   function Next (I : Natural; N : Integer := 1) return Natural
     with Inline;

   function Road_Height (I : Natural; D : Float) return Float;
   --  Smooth road plane at a sample (no bumps); the road edge continues
   --  outwards through the shoulder into the terrain

   function Terrain_Height (X, Z : Float) return Float;
   --  The ground without the road, smooth

   --  The pit box: an apron off the left of the road, just past the line
   Pit_From : constant := 20.0;    --  metres after the line
   Pit_To   : constant := 70.0;
   Pit_Wide : constant := 5.5;     --  metres out from the road's edge

   function In_Pit_Box (Index : Natural; D : Float) return Boolean;
   --  Index along the circuit, D across it

   Shoulder : constant := 12.0;   --  metres between road edge and open terrain

   function Line_Point (I : Natural; Extra_D : Float := 0.0;
                        X, Z : out Float) return Boolean;
   --  Where the racing line is at a sample (always True; a function for
   --  use in expressions of the AI)

   procedure Compute_Speeds (Mu, Down_Per_V2, Power_Per_Mass,
                             Drag_Per_V2, Brake_Acc : Float);
   --  The speed along the racing line for a car: its grip, downforce
   --  (m/s^2 per (m/s)^2), power, drag and brakes

   --  Terrain grid (read by the scenery to build its mesh)
   Grid_Cell : constant := 5.0;
   Grid_NX, Grid_NZ : Natural := 0;
   Grid_X0, Grid_Z0 : Float := 0.0;
   type Float_Grid is array (Natural range <>) of Float;
   type Float_Grid_Access is access Float_Grid;
   Grid : Float_Grid_Access;      --  (IZ * Grid_NX + IX)

   function Noise (X, Y : Float) return Float;
   --  Smooth value noise, 0 .. 1
   function Fbm (X, Y : Float; Octaves : Positive := 4) return Float;
   --  Fractal noise, about 0 .. 1

end Track;
