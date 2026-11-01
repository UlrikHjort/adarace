--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The panels over the view: rev bar, gear and speed, times, delta, the
--  tyres and pedals, the map, the order, the start lights.  Painted with
--  cairo and shown through Hud_Layer.

with Sim_Loop;

package Hud is

   procedure Set_Track_Map;
   --  After a new track was loaded

   procedure Draw (F : Sim_Loop.Frame; Width, Height : Natural;
                   Message : String; Fps : Float; Show_Panels : Boolean);
   --  Paints when due (not every frame) and shows the picture

   function Format_Time (T : Float) return String;

   Coach_On : Boolean := False;
   --  The coach's tips on the screen

end Hud;
