--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A season: a race at every circuit in turn, points for the places as in
--  the big series, the same rivals all season, a table after every round.

with Session;
with Track;

package Championship is

   Points_For : constant array (1 .. Session.Max_Cars) of Natural :=
     (25, 18, 15, 12, 10, 8, 6, 4);

   function Driver_Name (Car : Session.Car_Index) return String;
   --  The player is car 1; the rivals keep their car numbers all season

   type Entry_Line is record
      Car    : Session.Car_Index := 1;
      Points : Natural := 0;
      Last   : Natural := 0;   --  points in the round just run
      Place  : Natural := 0;   --  in that round
   end record;

   type Table is array (Session.Car_Index range <>) of Entry_Line;

   Active : Boolean := False;
   Finished_Round : Boolean := False;

   procedure Begin_Season (Cars : Positive);
   --  A round at every circuit

   type Road_Array is array (Positive range <>) of Track.Track_Id;

   procedure Begin_Season (Cars : Positive; Only : Road_Array);
   --  A round at each of these (a career's series)
   function Current_Road return Track.Track_Id;
   function Round_Number return Positive;
   function Round_Total return Natural;
   function Is_Last return Boolean;

   procedure Finish_Round;
   --  From Session's finishing order

   procedure Next_Round;

   function Standings return Table;
   --  Best first

   function Leader_Gap return Integer;
   --  The player's points behind the leader (0: leading)

end Championship;
