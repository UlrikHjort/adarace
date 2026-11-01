--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Everything at the circuit that stands still: the road surface, kerbs,
--  run-off, barriers, grandstands, the pit building, the trees, the hills.

with Mesh;

package Scenery is

   Ground  : Mesh.GPU;   --  terrain, far hills, shoulders: receive shadows only
   Road    : Mesh.GPU;
   Static  : Mesh.GPU;   --  start line furniture, always drawn; casts shadows

   Guide_Line : Mesh.GPU;   --  the racing line, painted by speed

   procedure Build_Guide;
   --  From the speeds of the session just started (GL context current)

   procedure Draw_Near (X, Z, Radius : Float);
   --  Barriers and trees in tiles round a point

   procedure Draw_View (X, Z, Dir_X, Dir_Z : Float);
   --  Those a camera can see looking that way

   procedure Build;
   --  For the loaded track (GL context current; replaces the old meshes)

end Scenery;
