--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
package body Championship is

   Roads : array (1 .. Track.Max_Tracks) of Track.Track_Id;
   Road_Count : Natural := 0;
   At_Round : Positive := 1;
   Field : Positive := 1;
   Lines : Table (1 .. Session.Max_Cars);

   function Driver_Name (Car : Session.Car_Index) return String is
     (case Car is
         when 1 => "YOU",
         when 2 => "Holm",
         when 3 => "Virta",
         when 4 => "Moreau",
         when 5 => "Silva",
         when 6 => "Nagy",
         when 7 => "Berg",
         when 8 => "Okafor");

   procedure Begin_Season (Cars : Positive) is
   begin
      Road_Count := 0;
      for T in 1 .. Track.Track_Count loop
         if not Track.Stage_Road (T) then
            Road_Count := Road_Count + 1;
            Roads (Road_Count) := T;
         end if;
      end loop;
      At_Round := 1;
      Field := Positive'Min (Cars, Session.Max_Cars);
      for C in Lines'Range loop
         Lines (C) := (Car => C, others => 0);
      end loop;
      Finished_Round := False;
      Active := True;
   end Begin_Season;

   procedure Begin_Season (Cars : Positive; Only : Road_Array) is
   begin
      Begin_Season (Cars);
      Road_Count := 0;
      for T of Only loop
         Road_Count := Road_Count + 1;
         Roads (Road_Count) := T;
      end loop;
   end Begin_Season;

   function Current_Road return Track.Track_Id is (Roads (At_Round));
   function Round_Number return Positive is (At_Round);
   function Round_Total return Natural is (Road_Count);
   function Is_Last return Boolean is (At_Round >= Road_Count);

   procedure Finish_Round is
   begin
      if Finished_Round then
         return;
      end if;
      Finished_Round := True;
      for C in 1 .. Session.Car_Count loop
         declare
            P : constant Positive := Session.Laps (C).Position;
         begin
            Lines (C).Place := P;
            Lines (C).Last := Points_For (P);
            Lines (C).Points := Lines (C).Points + Points_For (P);
         end;
      end loop;
   end Finish_Round;

   procedure Next_Round is
   begin
      if not Is_Last then
         At_Round := At_Round + 1;
      end if;
      Finished_Round := False;
   end Next_Round;

   function Standings return Table is
      T : Table := Lines (1 .. Field);
   begin
      for I in T'First + 1 .. T'Last loop
         declare
            Key : constant Entry_Line := T (I);
            J : Natural := I - 1;
         begin
            while J >= T'First
              and then (T (J).Points < Key.Points
                        or else (T (J).Points = Key.Points and then T (J).Place > Key.Place))
            loop
               T (J + 1) := T (J);
               J := J - 1;
            end loop;
            T (J + 1) := Key;
         end;
      end loop;
      return T;
   end Standings;

   function Leader_Gap return Integer is
      T : constant Table := Standings;
   begin
      return T (T'First).Points - Lines (1).Points;
   end Leader_Gap;

end Championship;
