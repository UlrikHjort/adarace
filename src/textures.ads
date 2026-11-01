--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The surfaces, painted by the program at start-up: tiling colour and
--  height (in the alpha) with mipmaps, so that detail stays sharp up close
--  and does not shimmer far away.  No image files to ship.

package Textures is

   --  Texture units, after the shadow maps on 1 and 2
   Unit_Asphalt : constant := 3;
   Unit_Grass   : constant := 4;
   Unit_Gravel  : constant := 5;
   Unit_Leaves  : constant := 6;   --  alpha: the cut-out of a leafy clump
   Unit_Needles : constant := 7;   --  alpha: the cut-out of a pine branch

   procedure Create;
   --  Paints and uploads them all, and binds them to their units
   --  (GL context current; leaves unit 0 active)

end Textures;
