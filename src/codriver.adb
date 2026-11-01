--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Characters.Handling;

with Track;

package body Codriver is

   use type Track.Note_Kind;

   Into_Gap : constant := 45.0;   --  a next corner this close is said as one

   Queue : array (1 .. 32) of Word;
   Used  : Natural := 0;
   Called : Natural := 0;         --  the last note read out
   Finish_Said : Boolean := False;
   Last_S : Float := 0.0;

   function File_Name (W : Word) return String is
     ("sounds/codriver/" & Ada.Characters.Handling.To_Lower (W'Image) & ".pcm");

   function Lead_Metres (Speed : Float) return Float is
     (Float'Max (55.0, Speed * 4.0));

   procedure Say (W : Word) is
   begin
      if Used < Queue'Last then
         Used := Used + 1;
         Queue (Used) := W;
      end if;
   end Say;

   procedure Reset is
   begin
      Used := 0;
      Called := 0;
      Last_S := 0.0;
      Finish_Said := False;
   end Reset;

   procedure Read_Out (N : Positive) is
      Nt : Track.Note renames Track.Notes (N);
   begin
      case Nt.Kind is
         when Track.Crest =>
            Say (Over);
            Say (Crest);
         when Track.Left | Track.Right =>
            if Nt.Grade = 1 then
               Say (Hairpin);
            end if;
            Say (if Nt.Kind = Track.Left then Left else Right);
            if Nt.Grade > 1 then
               Say (case Nt.Grade is
                       when 2 => Two, when 3 => Three, when 4 => Four,
                       when 5 => Five, when others => Six);
            end if;
            if Nt.Long then
               Say (Long);
            end if;
      end case;
   end Read_Out;

   procedure Update (S, Speed, Stage_Left : Float) is
      Lead : constant Float := Lead_Metres (Speed);
      Ahead : constant Natural := Track.Next_Note (S);
   begin
      --  Put back along the road, or a corner gone past unsaid: go on from here
      if Ahead > 0 and then (S < Last_S - 30.0 or else Called + 1 < Ahead) then
         Called := Ahead - 1;
      end if;
      Last_S := S;
      if Ahead > 0 and then Called < Ahead
        and then Track.Notes (Ahead).S - S < Lead
      then
         Read_Out (Ahead);
         Called := Ahead;
         --  A pair of corners close together go as one call
         if Ahead < Track.Note_Count
           and then Track.Notes (Ahead + 1).S - Track.Notes (Ahead).S < Into_Gap
         then
            Say (Into);
            Read_Out (Ahead + 1);
            Called := Ahead + 1;
         end if;
      end if;
      if not Finish_Said and then Stage_Left < Float'Max (60.0, Speed * 3.0) then
         Say (Finish);
         Finish_Said := True;
      end if;
   end Update;

   procedure Next_Word (W : out Word; Got : out Boolean) is
   begin
      Got := Used > 0;
      W := Finish;
      if Got then
         W := Queue (1);
         Queue (1 .. Used - 1) := Queue (2 .. Used);
         Used := Used - 1;
      end if;
   end Next_Word;

end Codriver;
