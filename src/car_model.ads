--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The car as a picture.  Model space: origin on the ground under the
--  centre of gravity, X to the right, Y up, forward is -Z.

with Math3D;
with Mesh;
with Vehicle;

package Car_Model is

   type Car_Meshes is record
      Bodywork : Mesh.GPU;
      Wheel    : Mesh.GPU;   --  a wheel on its axle, along X
      Cockpit  : Mesh.GPU;   --  dash, pillars, roof, door tops
      Steering : Mesh.GPU;   --  round its own column, centred at the origin
      Rider    : Mesh.GPU;   --  on a motorcycle; nothing in a car
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

   --  On a motorcycle: the rider's eyes inside the helmet, and the bars
   Bike_Eye_Y : constant := 1.21;
   Bike_Eye_Z : constant := -0.30;
   Bars_Y : constant := 0.96;
   Bars_Z : constant := -0.50;
   Seat : constant Math3D.Vec3 := (0.0, 0.86, 0.12);   --  the rider moves about it

   function Eye (K : Vehicle.Car_Kind) return Math3D.Vec3 is
     (if Vehicle.Is_Bike (K) then (0.0, Bike_Eye_Y, Bike_Eye_Z) else (Eye_X, Eye_Y, Eye_Z));

end Car_Model;
