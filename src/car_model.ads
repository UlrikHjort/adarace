--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The car as a picture.  Model space: origin on the ground under the
--  centre of gravity, X to the right, Y up, forward is -Z.

with Mesh;
with Vehicle;

package Car_Model is

   type Car_Meshes is record
      Bodywork : Mesh.GPU;
      Wheel    : Mesh.GPU;   --  a wheel on its axle, along X
      Cockpit  : Mesh.GPU;   --  dash, pillars, roof, door tops
      Steering : Mesh.GPU;   --  round its own column, centred at the origin
   end record;

   Meshes : array (Vehicle.Car_Kind) of Car_Meshes;

   procedure Build;
   --  (GL context current)

   --  Where things are, in model space
   Eye_X : constant := -0.37;
   Eye_Y : constant := 1.09;
   Eye_Z : constant := 0.03;
   Steering_X : constant := -0.37;
   Steering_Y : constant := 0.80;
   Steering_Z : constant := -0.42;
   Steering_Tilt : constant := 0.38;

end Car_Model;
