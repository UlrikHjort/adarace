--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Session;
with Track;

package body Telemetry is

   use Ada.Strings.Unbounded;

   Keep_Files : constant := 20;
   Capacity   : constant := 100 * 60 * 60;   --  an hour; then it stops gathering

   type Quad is array (Vehicle.Wheel_Id) of Float;

   type Row is record
      Lap : Natural;
      Lap_Time, S, X, Z, Speed, Vx, Vy, Rate : Float;
      Steer, Throttle, Brake, Clutch : Float;
      Gear : Integer;
      Rpm, Ax, Ay, Rack, Force : Float;
      Slide, Fz, Temp, Wear : Quad;
      Fuel, Dmg_Aero, Dmg_Engine, Toe : Float;
      Tc, Abs_On, Off_Road : Boolean;
   end record;

   type Rows is array (1 .. Capacity) of Row;
   type Rows_Access is access Rows;

   Data : Rows_Access;
   Used : Natural := 0;
   Written : Unbounded_String;

   procedure Sample (I : Vehicle.Inputs; Force : Float) is
      C : Vehicle.Car renames Session.Cars (1);
      L : Session.Lap_Info renames Session.Laps (1);
      Off : Boolean := False;
      R : Row;
   begin
      if Data = null then
         Data := new Rows;
      end if;
      if Used = Capacity then
         return;
      end if;
      for W in Vehicle.Wheel_Id loop
         R.Slide (W) := C.Wheels (W).Slide;
         R.Fz (W) := C.Wheels (W).Fz;
         R.Temp (W) := C.Wheels (W).Temp;
         R.Wear (W) := C.Wheels (W).Wear;
         Off := Off or else C.Wheels (W).Surf in Track.Grass | Track.Gravel;
      end loop;
      R.Lap := L.Lap;
      R.Lap_Time := L.Lap_Time;
      R.S := L.S;
      R.X := Float (C.X);
      R.Z := Float (C.Z);
      R.Speed := Vehicle.Speed (C);
      R.Vx := C.Vx;
      R.Vy := C.Vy;
      R.Rate := C.Rate;
      R.Steer := I.Steer;
      R.Throttle := I.Throttle;
      R.Brake := I.Brake;
      R.Clutch := I.Clutch;
      R.Gear := C.Gear;
      R.Rpm := C.Rpm;
      R.Ax := C.Ax;
      R.Ay := C.Ay;
      R.Rack := C.Rack;
      R.Force := Force;
      R.Fuel := C.Fuel;
      R.Dmg_Aero := C.Dmg_Aero;
      R.Dmg_Engine := C.Dmg_Engine;
      R.Toe := C.Toe;
      R.Tc := C.Tc_Active;
      R.Abs_On := C.Abs_Active;
      R.Off_Road := Off;
      Used := Used + 1;
      Data (Used) := R;
   end Sample;

   function Dir return String is
     ((if Ada.Environment_Variables.Exists ("HOME")
       then Ada.Environment_Variables.Value ("HOME") else ".")
      & "/.local/share/adarace/telemetry");

   function Stamp return String is
      use Ada.Calendar;
      T : constant String := Formatting.Image
        (Clock, Time_Zone => Time_Zones.UTC_Time_Offset);
      --  YYYY-MM-DD HH:MM:SS
   begin
      return T (1 .. 4) & T (6 .. 7) & T (9 .. 10) & "-"
        & T (12 .. 13) & T (15 .. 16) & T (18 .. 19);
   end Stamp;

   procedure Prune is
      use Ada.Directories;
      package Names is new Ada.Containers.Indefinite_Ordered_Sets (String);
      All_Files : Names.Set;
      Search_It : Search_Type;
      E : Directory_Entry_Type;
   begin
      Start_Search (Search_It, Dir, "*.csv", (Ordinary_File => True, others => False));
      while More_Entries (Search_It) loop
         Get_Next_Entry (Search_It, E);
         All_Files.Include (Simple_Name (E));
      end loop;
      End_Search (Search_It);
      --  The name starts with the time, so the first is the oldest
      while Natural (All_Files.Length) > Keep_Files loop
         Delete_File (Dir & "/" & All_Files.First_Element);
         All_Files.Delete_First;
      end loop;
   end Prune;

   procedure Write is
      use Ada.Text_IO;
      F : File_Type;

      function N (V : Float) return String is
         Scaled : constant Long_Long_Integer := Long_Long_Integer (V * 1000.0);
         A : constant Long_Long_Integer := abs Scaled;
         Whole : constant String := Long_Long_Integer'Image (A / 1000);
         Frac : constant String := Long_Long_Integer'Image (1000 + A mod 1000);
      begin
         return (if Scaled < 0 then "-" else "")
           & Whole (Whole'First + 1 .. Whole'Last) & "."
           & Frac (Frac'First + 2 .. Frac'Last);
      end N;

      function B (V : Boolean) return String is (if V then "1" else "0");
   begin
      if Used < 1000 then
         Used := 0;
         return;
      end if;
      Ada.Directories.Create_Path (Dir);
      declare
         Tr : constant String := Track.Loaded'Image;
         Name : constant String := Dir & "/" & Stamp & "_"
           & Tr (Tr'First + 1 .. Tr'Last) & "_"
           & Vehicle.Car_Kind'Image (Session.Config.Kind) & ".csv";
      begin
         Create (F, Out_File, Name);
         Put_Line (F, "t,lap,lap_time,s,x,z,speed,vx,vy,rate,steer,throttle,brake,clutch,gear,"
                   & "rpm,ax,ay,rack,force,slide_fl,slide_fr,slide_rl,slide_rr,"
                   & "fz_fl,fz_fr,fz_rl,fz_rr,temp_fl,temp_fr,temp_rl,temp_rr,wear_fl,wear_fr,wear_rl,wear_rr,fuel,dmg_aero,dmg_engine,toe,tc,abs,off_road");
         for K in 1 .. Used loop
            declare
               R : Row renames Data (K);
            begin
               Put (F, N (Float (K) * 0.01) & "," & R.Lap'Image & "," & N (R.Lap_Time)
                    & "," & N (R.S) & "," & N (R.X) & "," & N (R.Z) & "," & N (R.Speed)
                    & "," & N (R.Vx) & "," & N (R.Vy) & "," & N (R.Rate) & "," & N (R.Steer)
                    & "," & N (R.Throttle) & "," & N (R.Brake) & "," & N (R.Clutch)
                    & "," & R.Gear'Image & "," & N (R.Rpm) & "," & N (R.Ax) & "," & N (R.Ay)
                    & "," & N (R.Rack) & "," & N (R.Force));
               for W in Vehicle.Wheel_Id loop
                  Put (F, "," & N (R.Slide (W)));
               end loop;
               for W in Vehicle.Wheel_Id loop
                  Put (F, "," & N (R.Fz (W)));
               end loop;
               for W in Vehicle.Wheel_Id loop
                  Put (F, "," & N (R.Temp (W)));
               end loop;
               for W in Vehicle.Wheel_Id loop
                  Put (F, "," & N (R.Wear (W)));
               end loop;
               Put (F, "," & N (R.Fuel) & "," & N (R.Dmg_Aero) & "," & N (R.Dmg_Engine)
                    & "," & N (R.Toe));
               Put_Line (F, "," & B (R.Tc) & "," & B (R.Abs_On) & "," & B (R.Off_Road));
            end;
         end loop;
         Close (F);
         Written := To_Unbounded_String (Name);
      end;
      Used := 0;
      Prune;
   exception
      when E : others =>
         Used := 0;
         --  No telemetry is no reason to stop the game
         Put_Line ("Telemetry not saved: " & Ada.Exceptions.Exception_Message (E));
   end Write;

   function Last_File return String is (To_String (Written));

end Telemetry;
