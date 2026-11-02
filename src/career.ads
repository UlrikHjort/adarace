--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A career: a ladder of short championships, each in its own car (or on the
--  motorcycle) at its own circuits.  A place in the top three of a series
--  opens the next; the rivals get a little quicker on the way up.  Kept in
--  ~/.local/share/adarace/career.

with Track;
with Vehicle;

package Career is

   Tier_Count : constant := 6;
   subtype Tier is Positive range 1 .. Tier_Count;

   function Series (T : Tier) return String;
   function Kind (T : Tier) return Vehicle.Car_Kind;
   function Skill (T : Tier) return Float;   --  of the rivals
   Round_Count : constant := 3;
   Race_Laps : constant := 5;

   type Road_List is array (1 .. Round_Count) of Track.Track_Id;

   function Roads (T : Tier) return Road_List;
   --  The circuits of the series (found by their names in tracks/)

   function Reached return Tier;
   --  The series open to drive: the highest one reached
   function Best_Place (T : Tier) return Natural;
   --  Its best finish so far, 0: not yet run

   procedure Load;
   procedure Save;

   procedure Season_Over (T : Tier; Place : Positive; Opened : out Boolean);
   --  The series ended in that place.  Opened: it opened the next one.

   procedure Forget;
   --  Back to the start (for the tests)

end Career;
