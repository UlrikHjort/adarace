--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A rally: every stage in turn, the times added up, against crews whose
--  pace comes from the road and the chosen strength.  Damage goes with the
--  car from stage to stage; the crew mends half of it at each service.

with Track;
with Vehicle;

package Rally is

   Crews : constant := 5;
   subtype Crew_Id is Positive range 1 .. Crews + 1;   --  the last is the player

   type Standing is record
      Crew  : Crew_Id := 1;
      Total : Float := 0.0;
      Stage : Float := 0.0;     --  on the stage just run
   end record;

   type Table is array (1 .. Crews + 1) of Standing;

   Active : Boolean := False;

   procedure Begin_Rally (Skill : Float);

   function Current_Road return Track.Track_Id;
   function Stage_Number return Positive;
   function Stage_Total return Natural;
   function Is_Last return Boolean;

   procedure Finish_Stage (Time : Float; C : Vehicle.Car);
   --  With the player's time: the others' are worked out, the table sorted

   procedure Next_Stage;

   procedure Carry_Over (C : in out Vehicle.Car);
   --  What is left of the damage, on to the fresh car of the next stage

   function Crew_Name (C : Crew_Id) return String;

   Finished_Stage : Boolean := False;   --  the table is showing
   Standings : Table;

   function Position return Positive;

end Rally;
