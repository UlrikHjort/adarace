--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
package body Rally is

   Roads : array (1 .. Track.Max_Tracks) of Track.Track_Id;
   Road_Count : Natural := 0;
   At_Stage : Positive := 1;
   Pace : Float := 0.93;

   --  How each crew goes against the line's speed: a little over or under
   Crew_Factor : constant array (1 .. Crews) of Float := (0.97, 1.00, 1.03, 1.07, 1.12);

   Totals : array (Crew_Id) of Float := (others => 0.0);
   Dmg_Aero, Dmg_Engine, Toe : Float := 0.0;

   function Crew_Name (C : Crew_Id) return String is
     (case C is
         when 1 => "A. Holm",
         when 2 => "K. Virta",
         when 3 => "S. Moreau",
         when 4 => "J. Silva",
         when 5 => "R. Nagy",
         when others => "YOU");

   procedure Begin_Rally (Skill : Float) is
   begin
      Road_Count := 0;
      for T in 1 .. Track.Track_Count loop
         if Track.Stage_Road (T) then
            Road_Count := Road_Count + 1;
            Roads (Road_Count) := T;
         end if;
      end loop;
      At_Stage := 1;
      Pace := Skill;
      Totals := (others => 0.0);
      Dmg_Aero := 0.0;
      Dmg_Engine := 0.0;
      Toe := 0.0;
      Finished_Stage := False;
      Active := True;
   end Begin_Rally;

   function Current_Road return Track.Track_Id is (Roads (At_Stage));
   function Stage_Number return Positive is (At_Stage);
   function Stage_Total return Natural is (Road_Count);
   function Is_Last return Boolean is (At_Stage >= Road_Count);

   --  A crew's time on the road just loaded, from the speed the line allows
   function Crew_Time (K : Positive) return Float is
      Line : Float := 0.0;
   begin
      for I in 0 .. Track.Count - 1 loop
         exit when Track.Samples (I).S > Track.Stage_End;
         Line := Line + Track.Spacing / Float'Max (5.0, Track.Samples (I).Line_V);
      end loop;
      --  Spread by stage, so the order is not the same every time
      declare
         Luck : constant Float :=
           0.012 * Float ((K * 7 + At_Stage * 13) mod 5 - 2);
      begin
         --  (real crews lose a tenth or so on the theoretical line)
         return 1.10 * Line / Pace * Crew_Factor (K) * (1.0 + Luck);
      end;
   end Crew_Time;

   procedure Finish_Stage (Time : Float; C : Vehicle.Car) is
   begin
      if Finished_Stage then
         return;
      end if;
      Finished_Stage := True;
      Dmg_Aero := C.Dmg_Aero;
      Dmg_Engine := C.Dmg_Engine;
      Toe := C.Toe;
      for K in Standings'Range loop
         declare
            T : constant Float := (if K = Crew_Id'Last then Time else Crew_Time (K));
         begin
            Totals (K) := Totals (K) + T;
            Standings (K) := (Crew => K, Total => Totals (K), Stage => T);
         end;
      end loop;
      --  Best first
      for I in 2 .. Standings'Last loop
         declare
            Key : constant Standing := Standings (I);
            J : Natural := I - 1;
         begin
            while J >= 1 and then Standings (J).Total > Key.Total loop
               Standings (J + 1) := Standings (J);
               J := J - 1;
            end loop;
            Standings (J + 1) := Key;
         end;
      end loop;
   end Finish_Stage;

   procedure Next_Stage is
   begin
      if not Is_Last then
         At_Stage := At_Stage + 1;
      end if;
      Finished_Stage := False;
      --  Service: half of what is bent gets straightened
      Dmg_Aero := Dmg_Aero * 0.5;
      Dmg_Engine := Dmg_Engine * 0.5;
      Toe := Toe * 0.5;
   end Next_Stage;

   procedure Carry_Over (C : in out Vehicle.Car) is
   begin
      C.Dmg_Aero := Dmg_Aero;
      C.Dmg_Engine := Dmg_Engine;
      C.Toe := Toe;
   end Carry_Over;

   function Position return Positive is
   begin
      for I in Standings'Range loop
         if Standings (I).Crew = Crew_Id'Last then
            return I;
         end if;
      end loop;
      return Standings'Last;
   end Position;

end Rally;
