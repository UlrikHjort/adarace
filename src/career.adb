--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Career is

   use Vehicle;

   type Plan is record
      Name  : access constant String;
      Car   : Car_Kind;
      Roads : access constant String;   --  road names, by "|"
   end record;

   S1 : aliased constant String := "Classic Cup";
   S2 : aliased constant String := "Road GT Series";
   S3 : aliased constant String := "Superbike Trophy";
   S4 : aliased constant String := "GT3 Championship";
   S5 : aliased constant String := "Island TT Masters";
   S6 : aliased constant String := "Hypercar Finale";
   R1 : aliased constant String := "Sondersoe Ring|Monte Ferro|Havnebyen";
   R2 : aliased constant String := "Fjordringen|Boulevard Royal|Kalvoe Speedway";
   R3 : aliased constant String := "Sondersoe Ring|Fjordringen|Havnebyen";
   R4 : aliased constant String := "Monte Ferro|Boulevard Royal|Sondersoe Ring";
   R5 : aliased constant String := "Storoe TT|Monte Ferro|Fjordringen";
   R6 : aliased constant String := "Kalvoe Speedway|Fjordringen|Boulevard Royal";

   Plans : constant array (Tier) of Plan :=
     ((S1'Access, Classic_RWD, R1'Access),
      (S2'Access, Road_GT, R2'Access),
      (S3'Access, Sport_Bike, R3'Access),
      (S4'Access, Race_GT3, R4'Access),
      (S5'Access, Sport_Bike, R5'Access),
      (S6'Access, Hyper_AWD, R6'Access));

   At_Tier : Tier := 1;
   Places : array (Tier) of Natural := (others => 0);

   function Series (T : Tier) return String is (Plans (T).Name.all);
   function Kind (T : Tier) return Car_Kind is (Plans (T).Car);
   function Skill (T : Tier) return Float is (0.88 + 0.02 * Float (T - 1));
   function Reached return Tier is (At_Tier);
   function Best_Place (T : Tier) return Natural is (Places (T));

   --  A road by the start of its name ("Havnebyen" finds "Havnebyen (street circuit)")
   function Road_Named (N : String) return Track.Track_Id is
   begin
      for T in 1 .. Track.Track_Count loop
         declare
            Full : constant String := Track.Name (T);
         begin
            if Full'Length >= N'Length
              and then Full (Full'First .. Full'First + N'Length - 1) = N
            then
               return T;
            end if;
         end;
      end loop;
      return Track.Track_Id'First;   --  a road gone missing: the first one
   end Road_Named;

   function Roads (T : Tier) return Road_List is
      L : Road_List;
      Text : constant String := Plans (T).Roads.all;
      From : Positive := Text'First;
      K : Positive := 1;
   begin
      for I in Text'First .. Text'Last + 1 loop
         if I > Text'Last or else Text (I) = '|' then
            L (K) := Road_Named (Text (From .. I - 1));
            K := K + 1;
            From := I + 1;
         end if;
      end loop;
      return L;
   end Roads;

   function File return String is
     ((if Ada.Environment_Variables.Exists ("HOME")
       then Ada.Environment_Variables.Value ("HOME") else ".")
      & "/.local/share/adarace/career");

   procedure Load is
      use Ada.Text_IO;
      F : File_Type;
   begin
      At_Tier := 1;
      Places := (others => 0);
      if not Ada.Directories.Exists (File) then
         return;
      end if;
      Open (F, In_File, File);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
            Sp : constant Natural := Ada.Strings.Fixed.Index (L, " ");
         begin
            if Sp > 0 then
               declare
                  Key : constant String := L (L'First .. Sp - 1);
                  V : constant Natural := Natural'Value (L (Sp + 1 .. L'Last));
               begin
                  if Key = "reached" and then V in Tier then
                     At_Tier := V;
                  elsif Key'Length = 5 and then Key (Key'First .. Key'First + 3) = "best"
                    and then Character'Pos (Key (Key'Last)) - Character'Pos ('0') in Tier
                  then
                     Places (Character'Pos (Key (Key'Last)) - Character'Pos ('0')) := V;
                  end if;
               end;
            end if;
         exception
            when Constraint_Error => null;   --  a line it cannot read
         end;
      end loop;
      Close (F);
   end Load;

   procedure Save is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Ada.Directories.Create_Path (Ada.Directories.Containing_Directory (File));
      Create (F, Out_File, File);
      Put_Line (F, "reached" & At_Tier'Image);
      for T in Tier loop
         Put_Line (F, "best" & Character'Val (Character'Pos ('0') + T) & Places (T)'Image);
      end loop;
      Close (F);
   exception
      when others =>
         Put_Line ("Career not saved");
   end Save;

   procedure Season_Over (T : Tier; Place : Positive; Opened : out Boolean) is
   begin
      Opened := False;
      if Places (T) = 0 or else Place < Places (T) then
         Places (T) := Place;
      end if;
      if Place <= 3 and then T = At_Tier and then T < Tier_Count then
         At_Tier := T + 1;
         Opened := True;
      end if;
      Save;
   end Season_Over;

   procedure Forget is
   begin
      At_Tier := 1;
      Places := (others => 0);
   end Forget;

end Career;
