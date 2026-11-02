--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces.C;
with System;

with Gdk.Event;
with Gdk;
with Gdk.Frame_Clock;
with Gdk.Types;
with Gdk.Types.Keysyms;
with Glib;
with Glib.Main;
with Gtk.Adjustment;
with Gtk.Box;
with Gtk.Button;
with Gtk.Combo_Box;
with Gtk.Combo_Box_Text;
with Gtk.Css_Provider;
with Gtk.Enums;
with Gtk.GEntry;
with Gtk.Grid;
with Gtk.Label;
with Gtk.Main;
with Gtk.Overlay;
with Gtk.Scale;
with Gtk.Style_Context;
with Gtk.Style_Provider;
with Gtk.Widget;
with Gtk.Window;
with Gdk.Screen;

with Audio;
with Codriver;
with Car_Model;
with GL;
with GL_Area;
with Hud;
with Hud_Layer;
with Championship;
with Rally;
with Net;
with Recorder;
with Replay;
with Renderer;
with School;
with Scenery;
with Session;
with Sim_Loop;
with Telemetry;
with Track;
with Vehicle;
with Wheel;

package body App is

   use Glib;
   use Ada.Strings.Unbounded;
   use type Gdk.Types.Gdk_Key_Type;
   use type Renderer.Camera_Kind;
   use type Session.Mode_Kind;
   use type Session.Weather_Kind;
   use type Net.Role;

   Window : Gtk.Window.Gtk_Window;
   Area   : GL_Area.Gtk_GL_Area;
   Menu   : Gtk.Box.Gtk_Box;
   Pause_Box : Gtk.Box.Gtk_Box;
   Status : Gtk.Label.Gtk_Label;

   Combo_Track, Combo_Car, Combo_Mode, Combo_Opp, Combo_Laps, Combo_Gear,
   Combo_Abs, Combo_Tc, Combo_Time, Combo_Skill,
   Combo_Wear, Combo_Damage, Combo_Lesson, Combo_Aid, Combo_Weather, Combo_Season :
     Gtk.Combo_Box_Text.Gtk_Combo_Box_Text;
   FFB_Scale, Fov_Scale : Gtk.Scale.Gtk_Scale;
   Start_Button : Gtk.Button.Gtk_Button;

   --  The car's setup, in percent: one set of values for each car, kept
   --  while the other is shown in the sliders
   Setup_Box : Gtk.Box.Gtk_Box;
   subtype Knob is Positive range 1 .. 8;
   type Knob_Values is array (Knob) of Integer;
   Knob_Default : constant Knob_Values := (100, 100, 100, 100, 0, 100, 100, 100);
   Tunes : array (Vehicle.Car_Kind) of Knob_Values := (others => Knob_Default);
   Knobs : array (Knob) of Gtk.Scale.Gtk_Scale;
   Setup_Car : Vehicle.Car_Kind := Vehicle.Road_GT;
   Setup_Live : Boolean := False;

   Options : Renderer.View_Options;
   Keys    : Sim_Loop.Keys;

   In_Menu : Boolean := True;
   Ready   : Boolean := False;   --  GL is up
   Shown_Track : Natural := 0;   --  the track behind the menu
   Pending_Track : Natural := 0;
   Is_Fullscreen : Boolean := False;
   Show_Panels : Boolean := True;
   Last_Frame_T : Long_Float := 0.0;
   procedure Set_Frame_Sync (W : Gdk.Gdk_Window; On : Gboolean)
     with Import, Convention => C, External_Name => "gdk_x11_window_set_frame_sync_enabled";

   Voice_On : Boolean := True;
   Rally_Auto : Boolean := False;
   Replay_From : Natural := 0;
   Shot_At_Table : Boolean := False;
   Rally_Wait : Natural := 0;
   Want_Record : Boolean := False;   --  F9: done where the picture is ready
   Record_At, Record_For : Float := 0.0;  --  automated: from when, how long

   Fps_Smooth : Float := 60.0;
   Late_20, Late_34 : Natural := 0;   --  frames over 20 ms, over 34 ms
   Worst_Frame : Float := 0.0;
   Volume : Float := 0.8;

   Message : Unbounded_String;
   Message_Until : Long_Float := 0.0;

   Last_Gear : Integer := 0;
   Last_Lights : Natural := 0;
   Was_Out : Boolean := True;
   Last_Impact : Float := 0.0;

   --  Automated check: start at once, write a picture after some frames and quit
   Shot_File : Unbounded_String;
   Shot_Frame : Natural := 0;
   Frame_Count : Natural := 0;
   Time_Scene, Time_All : Long_Float := 0.0;
   Profile : Boolean := False;
   Wheel_Shown : Boolean := False;
   Started_At : Long_Float := 0.0;

   function Env (N : String) return String is
     (if Ada.Environment_Variables.Exists (N) then Ada.Environment_Variables.Value (N) else "");

   procedure Say (S : String; Seconds : Long_Float := 3.0) is
   begin
      Message := To_Unbounded_String (S);
      Message_Until := Sim_Loop.Now + Seconds;
   end Say;

   --  "This felt wrong": numbered in the telemetry, for telling about it later
   procedure Mark_Moment is
      N : constant Positive := Telemetry.Mark;
      Img : constant String := N'Image;
   begin
      Say ("Mark" & Img & " noted", 2.0);
   end Mark_Moment;

   ---------------------------------------------------------------------------
   --  Remembered choices, in ~/.adaracerc
   ---------------------------------------------------------------------------

   function Rc_File return String is (Env ("HOME") & "/.adaracerc");

   procedure Save_Choices is
      use Ada.Text_IO;
      F : File_Type;
      procedure Item (Name : String; V : Integer) is
      begin
         Put_Line (F, Name & " " & Integer'Image (V));
      end Item;
   begin
      Create (F, Out_File, Rc_File);
      Item ("track", Integer (Combo_Track.Get_Active));
      Item ("car", Integer (Combo_Car.Get_Active));
      Item ("mode", Integer (Combo_Mode.Get_Active));
      Item ("opponents", Integer (Combo_Opp.Get_Active));
      Item ("laps", Integer (Combo_Laps.Get_Active));
      Item ("gearbox", Integer (Combo_Gear.Get_Active));
      Item ("abs", Integer (Combo_Abs.Get_Active));
      Item ("tc", Integer (Combo_Tc.Get_Active));
      Item ("time", Integer (Combo_Time.Get_Active));
      Item ("skill", Integer (Combo_Skill.Get_Active));
      Item ("ffb", Integer (FFB_Scale.Get_Value));
      Item ("fov", Integer (Fov_Scale.Get_Value));
      Item ("camera", Renderer.Camera_Kind'Pos (Options.Camera));
      Item ("lesson", Integer (Combo_Lesson.Get_Active));
      Item ("aid", Integer (Combo_Aid.Get_Active));
      Item ("weather", Integer (Combo_Weather.Get_Active));
      Item ("season", Integer (Combo_Season.Get_Active));
      Item ("voice", (if Voice_On then 1 else 0));
      Item ("wear", Integer (Combo_Wear.Get_Active));
      Item ("damage", Integer (Combo_Damage.Get_Active));
      for C in Vehicle.Car_Kind loop
         for K in Knob loop
            Item ("su" & Character'Val (48 + Vehicle.Car_Kind'Pos (C)) & Character'Val (48 + K),
                  Tunes (C) (K));
         end loop;
      end loop;
      Close (F);
   exception
      when others => null;
   end Save_Choices;

   procedure Load_Choices is
      use Ada.Text_IO;
      F : File_Type;
   begin
      if not Ada.Directories.Exists (Rc_File) then
         return;
      end if;
      Open (F, In_File, Rc_File);
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            Gap : Natural := 0;
         begin
            for I in Line'Range loop
               if Line (I) = ' ' then
                  Gap := I;
                  exit;
               end if;
            end loop;
            if Gap > 0 then
               declare
                  N : constant String := Line (Line'First .. Gap - 1);
                  V : constant Integer := Integer'Value (Line (Gap + 1 .. Line'Last));
                  G : constant Gint := Gint (V);
               begin
                  if N = "track" then Combo_Track.Set_Active (G);
                  elsif N = "car" then Combo_Car.Set_Active (G);
                  elsif N = "mode" then Combo_Mode.Set_Active (G);
                  elsif N = "opponents" then Combo_Opp.Set_Active (G);
                  elsif N = "laps" then Combo_Laps.Set_Active (G);
                  elsif N = "gearbox" then Combo_Gear.Set_Active (G);
                  elsif N = "abs" then Combo_Abs.Set_Active (G);
                  elsif N = "tc" then Combo_Tc.Set_Active (G);
                  elsif N = "time" then Combo_Time.Set_Active (G);
                  elsif N = "skill" then Combo_Skill.Set_Active (G);
                  elsif N = "ffb" then FFB_Scale.Set_Value (Gdouble (V));
                  elsif N = "fov" then Fov_Scale.Set_Value (Gdouble (V));
                  elsif N = "camera" then Options.Camera := Renderer.Camera_Kind'Val (V);
                  elsif N = "lesson" then Combo_Lesson.Set_Active (G);
                  elsif N = "aid" then Combo_Aid.Set_Active (G);
                  elsif N = "weather" then Combo_Weather.Set_Active (G);
                  elsif N = "season" then Combo_Season.Set_Active (G);
                  elsif N = "voice" then Voice_On := V /= 0;
                  elsif N = "wear" then Combo_Wear.Set_Active (G);
                  elsif N = "damage" then Combo_Damage.Set_Active (G);
                  elsif N'Length = 4 and then N (N'First .. N'First + 1) = "su" then
                     Tunes (Vehicle.Car_Kind'Val (Integer'Value (N (N'First + 2 .. N'First + 2))))
                       (Integer'Value (N (N'First + 3 .. N'First + 3))) := V;
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others => null;
   end Load_Choices;

   ---------------------------------------------------------------------------
   --  Sessions
   ---------------------------------------------------------------------------

   function Chosen_Track return Track.Track_Id is
     (Track.Track_Id (Integer (Combo_Track.Get_Active) + 1));

   function Chosen_Car return Vehicle.Car_Kind is
     (Vehicle.Car_Kind'Val (Integer (Combo_Car.Get_Active)));

   procedure Store_Knobs is
   begin
      for K in Knob loop
         Tunes (Setup_Car) (K) := Integer (Knobs (K).Get_Value);
      end loop;
   end Store_Knobs;

   procedure Show_Knobs (C : Vehicle.Car_Kind) is
      use type Vehicle.Car_Kind;
   begin
      Setup_Car := C;
      for K in Knob loop
         Knobs (K).Set_Value (Gdouble (Tunes (C) (K)));
      end loop;
      --  (the road car has no wing to set)
      Knobs (7).Set_Sensitive (C in Vehicle.Race_GT3 | Vehicle.Hyper_AWD);
   end Show_Knobs;

   function Chosen_Setup return Vehicle.Setup is
      V : Knob_Values renames Tunes (Chosen_Car);
      function P (K : Knob) return Float is (Float (V (K)) / 100.0);
   begin
      return (Spring_F => P (1), Spring_R => P (2), Bar_F => P (3), Bar_R => P (4),
              Brake_Shift => P (5), Final_Drive => P (6), Wing => P (7), Diff => P (8));
   end Chosen_Setup;

   procedure Apply_Time is
   begin
      Options.Day := Renderer.Time_Of_Day'Val (Integer (Combo_Time.Get_Active));
   end Apply_Time;

   --  Everything for a track: the data, the meshes, the map
   procedure Show_Track (T : Track.Track_Id) is
   begin
      Area.Make_Current;
      Track.Load (T);
      Scenery.Build;
      Renderer.New_Track;
      Hud.Set_Track_Map;
      Shown_Track := T;
   end Show_Track;

   procedure Start_Demo is
      S : Session.Settings;
   begin
      Sim_Loop.Halt;
      if Shown_Track /= Chosen_Track then
         Show_Track (Chosen_Track);
      end if;
      S.Mode := Session.Demo;
      S.Kind := Chosen_Car;
      S.Weather := Session.Weather_Kind'Val (Integer (Combo_Weather.Get_Active));
      S.Season := Session.Season_Kind'Val (Integer (Combo_Season.Get_Active));
      S.Opponents := 3;
      S.AI_Skill := 0.93;
      Session.Start (S);
      Sim_Loop.Pause (False);
      Sim_Loop.Resume;
      Options.Ghost := False;
   end Start_Demo;

   function In_School return Boolean is (Combo_Mode.Get_Active = 2);

   function In_Rally return Boolean is (Combo_Mode.Get_Active = 3);

   function In_Season return Boolean is (Combo_Mode.Get_Active = 4);

   function Two_Players return Boolean is (Combo_Mode.Get_Active = 5);

   function Hosting return Boolean is (Combo_Mode.Get_Active = 6);
   function Joining_Mode return Boolean is (Combo_Mode.Get_Active = 7);

   --  Joining: looking for the host from the menu until it gives the race
   Host_Entry : Gtk.GEntry.Gtk_Entry;
   Joining : Boolean := False;
   Join_Wait : Natural := 0;
   Join_Track, Join_Laps : Natural := 0;

   function Lesson_Chosen return School.Lesson_Id is
     (School.Lesson_Id (Integer (Combo_Lesson.Get_Active) + 1));

   function Drive_Track return Track.Track_Id is
     (if Joining_Mode and then Join_Track > 0 then Track.Track_Id (Join_Track)
      elsif In_School then School.Circuit (Lesson_Chosen)
      elsif In_Rally then Rally.Current_Road
      elsif In_Season then Championship.Current_Road
      else Chosen_Track);

   procedure Begin_Drive;

   --  Online, from the menu: the host opens and drives; the guest first finds the host
   procedure Begin_Online is
   begin
      if Hosting then
         Net.Open (Net.Host);
      elsif Joining_Mode and then Join_Track = 0 then
         Net.Open (Net.Guest, Host_Entry.Get_Text);
         if Net.Current_Role = Net.Off then
            Status.Set_Text ("Cannot reach " & Host_Entry.Get_Text);
         else
            Joining := True;
            Status.Set_Text ("Looking for the host at " & Host_Entry.Get_Text & " ...");
         end if;
      end if;
   end Begin_Online;

   procedure Begin_From_Menu;

   procedure Begin_Drive is
      S : Session.Settings;
      Skill : constant Float :=
        (case Integer (Combo_Skill.Get_Active) is
            when 0 => 0.80, when 1 => 0.87, when 2 => 0.93, when others => 0.98);
   begin
      --  A new rally from the menu; from one stage to the next it goes on
      if In_Rally and then In_Menu then
         Rally.Begin_Rally (Skill);
      elsif not In_Rally then
         Rally.Active := False;
      end if;
      if In_Season and then In_Menu then
         Championship.Begin_Season (Natural (Combo_Opp.Get_Active) + 2);
      elsif not In_Season then
         Championship.Active := False;
      end if;
      Store_Knobs;
      Save_Choices;
      Replay.Clear;
      Sim_Loop.Halt;
      if Shown_Track /= Drive_Track then
         Show_Track (Drive_Track);
      end if;
      S.Mode := (if Track.Is_Stage then Session.Stage
                 elsif Combo_Mode.Get_Active = 0 then Session.Hotlap else Session.Race);
      if In_Season then
         S.Mode := Session.Race;
      end if;
      S.Two_Players := Two_Players and then not Track.Is_Stage;
      S.Online := (Hosting or else Joining_Mode) and then not Track.Is_Stage;
      if S.Online then
         S.Mode := Session.Race;
         S.Opponents := 1;
         if Joining_Mode and then Join_Laps > 0 then
            S.Laps := Join_Laps;
         end if;
         Session.Online_Ready := False;
      end if;
      if S.Two_Players then
         S.Mode := Session.Race;
         --  (the second player counts as one of the cars)
         S.Opponents := Natural'Max (1, S.Opponents);
      end if;
      S.Kind := Chosen_Car;
      S.Opponents := Natural (Combo_Opp.Get_Active) + 1;
      S.Laps := (case Integer (Combo_Laps.Get_Active) is
                    when 0 => 3, when 1 => 5, when 2 => 10, when others => 20);
      S.Assist.Mode := Vehicle.Gearbox_Mode'Val (Integer (Combo_Gear.Get_Active));
      --  An H-shifter needs the wheel's lever, and a motorcycle's box is
      --  sequential: otherwise it would sit in neutral
      if S.Assist.Mode in Vehicle.H_Auto_Clutch | Vehicle.H_Clutch
        and then (Vehicle.Is_Bike (S.Kind) or else not Sim_Loop.Wheel_Present)
      then
         S.Assist.Mode := Vehicle.Paddles;
      end if;
      S.Assist.Abs_On := Combo_Abs.Get_Active = 0;
      S.Assist.Tc_On := Combo_Tc.Get_Active = 0;
      S.Assist.Wear_Rate := (case Integer (Combo_Wear.Get_Active) is
                                when 0 => 0.0, when 1 => 1.0, when others => 3.0);
      S.Assist.Fuel_Use := Combo_Wear.Get_Active > 0;
      S.Assist.Damage := (case Integer (Combo_Damage.Get_Active) is
                             when 0 => 0.0, when 1 => 0.5, when others => 1.0);
      S.Tune := Chosen_Setup;
      S.Weather := Session.Weather_Kind'Val (Integer (Combo_Weather.Get_Active));
      S.Season := Session.Season_Kind'Val (Integer (Combo_Season.Get_Active));
      S.AI_Skill := (case Integer (Combo_Skill.Get_Active) is
                        when 0 => 0.80, when 1 => 0.87, when 2 => 0.93, when others => 0.98);
      if In_School then
         S := School.Prepare (Lesson_Chosen, S);
      end if;
      if Env ("ADARACE_LAPS") /= "" then
         S.Laps := Positive'Value (Env ("ADARACE_LAPS"));
      end if;
      Session.Start (S);
      if In_Rally then
         Rally.Carry_Over (Session.Cars (1));
      end if;
      School.Begin_Lesson (if In_School then Lesson_Chosen else 0);
      Codriver.Reset;
      Area.Make_Current;
      Scenery.Build_Guide;
      Options.Guide := In_School or else Combo_Aid.Get_Active > 0;
      Hud.Coach_On := In_School or else Combo_Aid.Get_Active = 2;
      Options.Ghost := not In_School;
      Apply_Time;
      Options.Fov := Float (Fov_Scale.Get_Value);
      Options.Look := 0.0;
      Sim_Loop.Set_FFB (Float (FFB_Scale.Get_Value) / 100.0);
      Sim_Loop.Pause (False);
      Sim_Loop.Resume;
      In_Menu := False;
      Menu.Hide;
      Setup_Box.Hide;
      Pause_Box.Hide;
      Last_Lights := 0;
      Was_Out := Session.Lights_Out;
      Window.Grab_Focus;
      Area.Grab_Focus;
      Say (Track.Name (Chosen_Track) & "  -  " & Vehicle.Name (S.Kind), 3.0);
   end Begin_Drive;

   --  DRIVE in the menu: an online race goes by way of the network
   procedure Begin_From_Menu is
   begin
      if Hosting then
         Begin_Online;
         Begin_Drive;
      elsif Joining_Mode then
         Join_Track := 0;
         Begin_Online;
      else
         Net.Close;
         Begin_Drive;
      end if;
   end Begin_From_Menu;

   procedure To_Menu is
   begin
      Net.Close;
      Joining := False;
      Join_Track := 0;
      In_Menu := True;
      Pause_Box.Hide;
      Menu.Show;
      Setup_Box.Show;
      Start_Demo;
      Start_Button.Grab_Focus;
   end To_Menu;

   --  Watching it again: the race stands still meanwhile
   Camera_Before : Renderer.Camera_Kind := Renderer.Cockpit;
   Paused_Before : Boolean := False;

   procedure Toggle_Replay is
   begin
      if In_Menu then
         return;
      end if;
      if Replay.Active then
         Replay.Stop;
         Options.Camera := Camera_Before;
         if not Paused_Before then
            Sim_Loop.Pause (False);
         end if;
      elsif Replay.Length > 1.0 then
         Paused_Before := Sim_Loop.Paused;
         Sim_Loop.Pause (True);
         Pause_Box.Hide;
         Camera_Before := Options.Camera;
         Options.Camera := Renderer.Trackside;
         Replay.Start;
      end if;
   end Toggle_Replay;

   procedure Toggle_Pause is
   begin
      if In_Menu then
         return;
      end if;
      if Sim_Loop.Paused then
         Sim_Loop.Pause (False);
         Pause_Box.Hide;
      else
         Sim_Loop.Pause (True);
         Pause_Box.Show;
      end if;
   end Toggle_Pause;

   --  The button stays latched, so a second press must bring the view back
   procedure Toggle_Look_Back is
   begin
      if Options.Look = 0.0 then
         Options.Look := Ada.Numerics.Pi * 0.97;
         Say ("Looking back: same button for the front", 2.0);
      else
         Options.Look := 0.0;
      end if;
   end Toggle_Look_Back;

   --  At the end of a stage of a rally: on to the next, or home after the last
   procedure Advance_Rally is
   begin
      if Championship.Active and then Championship.Finished_Round then
         if Championship.Is_Last then
            Championship.Active := False;
            To_Menu;
         else
            Championship.Next_Round;
            Begin_Drive;
         end if;
      elsif Rally.Active and then Rally.Finished_Stage then
         if Rally.Is_Last then
            Rally.Active := False;
            To_Menu;
         else
            Rally.Next_Stage;
            Begin_Drive;
         end if;
      end if;
   end Advance_Rally;

   procedure Next_Camera is
      use Renderer;
   begin
      Options.Look := 0.0;
      Options.Camera :=
        (if Options.Camera = Camera_Kind'Last then Camera_Kind'First
         else Camera_Kind'Succ (Options.Camera));
      Say ((case Options.Camera is
               when Cockpit => "Cockpit",
               when Hood => "Hood",
               when Chase => "Chase",
               when Chase_Far => "Chase, far",
               when Trackside => "Trackside"), 1.0);
   end Next_Camera;

   procedure Change_FFB (By : Float) is
   begin
      FFB_Scale.Set_Value (FFB_Scale.Get_Value + Gdouble (By));
      Sim_Loop.Set_FFB (Float (FFB_Scale.Get_Value) / 100.0);
      Say ("Force feedback" & Integer'Image (Integer (FFB_Scale.Get_Value)) & " %", 1.0);
   end Change_FFB;

   ---------------------------------------------------------------------------
   --  Keys
   ---------------------------------------------------------------------------

   function Key_Press (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
   begin
      if K = GDK_F11 then
         Is_Fullscreen := not Is_Fullscreen;
         if Is_Fullscreen then
            Window.Fullscreen;
         else
            Window.Unfullscreen;
         end if;
         return True;
      end if;
      if In_Menu then
         if K = GDK_Return or else K = GDK_KP_Enter then
            Begin_From_Menu;
            return True;
         elsif K = GDK_Escape then
            Gtk.Main.Main_Quit;
            return True;
         end if;
         return False;
      end if;
      --  The replay's own keys while it runs
      if Replay.Active then
         if K = GDK_F2 or else K = GDK_Escape then Toggle_Replay;
         elsif K = GDK_Left then Replay.Seek (-5.0);
         elsif K = GDK_Right then Replay.Seek (5.0);
         elsif K = GDK_Up then Replay.Speed := Float'Min (4.0, (if Replay.Speed = 0.0 then 0.25 else Replay.Speed * 2.0));
         elsif K = GDK_Down then Replay.Speed := (if Replay.Speed <= 0.25 then 0.0 else Replay.Speed / 2.0);
         elsif K = GDK_space then Replay.Speed := (if Replay.Speed = 0.0 then 1.0 else 0.0);
         elsif K = GDK_LC_c then Next_Camera;
         end if;
         return True;
      end if;
      if K = GDK_F2 then
         Toggle_Replay;
         return True;
      end if;
      --  Two players without a wheel: the second drives on W A S D
      if Session.Config.Two_Players and then not Sim_Loop.Wheel_Present
        and then (K = GDK_LC_w or else K = GDK_LC_a or else K = GDK_LC_s or else K = GDK_LC_d)
      then
         if K = GDK_LC_w then Keys.Throttle_2 := True;
         elsif K = GDK_LC_s then Keys.Brake_2 := True;
         elsif K = GDK_LC_a then Keys.Left_2 := True;
         else Keys.Right_2 := True;
         end if;
         Sim_Loop.Set_Keys (Keys);
         return True;
      end if;
      if K = GDK_Left then Keys.Left := True;
      elsif K = GDK_Right then Keys.Right := True;
      elsif K = GDK_Up then Keys.Throttle := True;
      elsif K = GDK_Down then Keys.Brake := True;
      elsif K = GDK_space then Keys.Handbrake := True;
      elsif K = GDK_LC_a then Sim_Loop.Request_Shift (True);
      elsif K = GDK_LC_z then Sim_Loop.Request_Shift (False);
      elsif K = GDK_LC_x then Sim_Loop.Request_Reverse (True);
      elsif K = GDK_Return then
         Advance_Rally;
      elsif K = GDK_LC_b then
         Voice_On := not Voice_On;
         Say ((if Voice_On then "Co-driver speaks" else "Co-driver silent"), 1.5);
      elsif K = GDK_F9 then
         Want_Record := True;
      elsif K = GDK_LC_c then Next_Camera;
      elsif K = GDK_LC_m then Mark_Moment;
      elsif K = GDK_LC_l then
         Options.Guide := not Options.Guide;
         Say ((if Options.Guide then "Driving line on" else "Driving line off"), 1.5);
      elsif K = GDK_LC_v then Options.Mirror := not Options.Mirror;
      elsif K = GDK_LC_g then Options.Ghost := not Options.Ghost;
      elsif K = GDK_LC_h then Show_Panels := not Show_Panels;
      elsif K = GDK_LC_r then Sim_Loop.Reset_Car;
      elsif K = GDK_LC_q then Options.Look := -1.2;
      elsif K = GDK_LC_e then Options.Look := 1.2;
      elsif K = GDK_LC_w then Options.Look := Ada.Numerics.Pi * 0.97;
      elsif K = GDK_plus or else K = GDK_KP_Add then Change_FFB (5.0);
      elsif K = GDK_minus or else K = GDK_KP_Subtract then Change_FFB (-5.0);
      elsif K = GDK_bracketright then Options.Fov := Float'Min (90.0, Options.Fov + 2.0);
      elsif K = GDK_bracketleft then Options.Fov := Float'Max (30.0, Options.Fov - 2.0);
      elsif K = GDK_Escape or else K = GDK_LC_p then Toggle_Pause;
      elsif K = GDK_F5 and then Sim_Loop.Paused then
         Sim_Loop.Restart;
         Toggle_Pause;
      elsif K = GDK_F10 and then Sim_Loop.Paused then
         To_Menu;
      else
         return False;
      end if;
      Sim_Loop.Set_Keys (Keys);
      return True;
   end Key_Press;

   function Key_Release (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                         Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
   begin
      if K = GDK_LC_w then Keys.Throttle_2 := False;
      elsif K = GDK_LC_s then Keys.Brake_2 := False;
      elsif K = GDK_LC_a then Keys.Left_2 := False;
      elsif K = GDK_LC_d then Keys.Right_2 := False;
      end if;
      if K = GDK_Left then Keys.Left := False;
      elsif K = GDK_Right then Keys.Right := False;
      elsif K = GDK_Up then Keys.Throttle := False;
      elsif K = GDK_Down then Keys.Brake := False;
      elsif K = GDK_space then Keys.Handbrake := False;
      elsif K = GDK_LC_x then Sim_Loop.Request_Reverse (False);
      elsif K = GDK_LC_q or else K = GDK_LC_e or else K = GDK_LC_w then Options.Look := 0.0;
      else
         return False;
      end if;
      Sim_Loop.Set_Keys (Keys);
      return True;
   end Key_Release;

   --  Wheel buttons -----------------------------------------------------------

   Menu_Row : Natural := 0;
   Menu_Rows : constant := 16;

   function Row_Combo (R : Natural) return Gtk.Combo_Box_Text.Gtk_Combo_Box_Text is
     (case R is
         when 0 => Combo_Track,
         when 1 => Combo_Car,
         when 2 => Combo_Mode,
         when 3 => Combo_Opp,
         when 4 => Combo_Laps,
         when 5 => Combo_Skill,
         when 6 => Combo_Gear,
         when 7 => Combo_Abs,
         when 8 => Combo_Tc,
         when 9 => Combo_Wear,
         when 10 => Combo_Damage,
         when 11 => Combo_Time,
         when 12 => Combo_Weather,
         when 13 => Combo_Season,
         when 14 => Combo_Lesson,
         when others => Combo_Aid);

   procedure Wheel_Buttons is
      use Wheel;
      B : Button;
   begin
      while Sim_Loop.Next_Button (B) loop
         if In_Menu then
            case B is
               when Pad_Up =>
                  Menu_Row := (Menu_Row + Menu_Rows - 1) mod Menu_Rows;
                  Row_Combo (Menu_Row).Grab_Focus;
               when Pad_Down =>
                  Menu_Row := (Menu_Row + 1) mod Menu_Rows;
                  Row_Combo (Menu_Row).Grab_Focus;
               when Pad_Left | Pad_Right =>
                  declare
                     C : constant Gtk.Combo_Box_Text.Gtk_Combo_Box_Text := Row_Combo (Menu_Row);
                     Old : constant Gint := C.Get_Active;
                  begin
                     C.Set_Active (Old + (if B = Pad_Left then -1 else 1));
                     if C.Get_Active < 0 then
                        C.Set_Active (Old);
                     end if;
                  end;
               when Cross | Enter =>
                  Begin_From_Menu;
               when others => null;
            end case;
         elsif Replay.Active then
            case B is
               when Wheel.Options | Cross | Circle => Toggle_Replay;
               when Pad_Left => Replay.Seek (-5.0);
               when Pad_Right => Replay.Seek (5.0);
               when Triangle => Next_Camera;
               when others => null;
            end case;
         elsif Sim_Loop.Paused then
            case B is
               when Triangle => Toggle_Replay;
               when Wheel.Options | Cross => Toggle_Pause;
               when Square =>
                  Sim_Loop.Restart;
                  Toggle_Pause;
               when Circle => To_Menu;
               when others => null;
            end case;
         else
            case B is
               when Cross | Enter =>
                  Advance_Rally;
               when Triangle => Next_Camera;
               when Square => Sim_Loop.Reset_Car;
               when Wheel.Options => Toggle_Pause;
               when Share => App.Options.Mirror := not App.Options.Mirror;
               when Plus | Dial_Right => Change_FFB (5.0);
               when Minus | Dial_Left => Change_FFB (-5.0);
               when R3 => Toggle_Look_Back;
               when Pad_Down => Mark_Moment;
               when others => null;
            end case;
         end if;
      end loop;
   end Wheel_Buttons;

   ---------------------------------------------------------------------------
   --  Rendering
   ---------------------------------------------------------------------------

   procedure Realize (Widget, Data : System.Address) with Convention => C;
   procedure Realize (Widget, Data : System.Address) is
      pragma Unreferenced (Widget, Data);
   begin
      Area.Make_Current;
      if Area.Error_Message /= "" then
         Ada.Text_IO.Put_Line ("OpenGL 4.5 is needed: " & Area.Error_Message);
         return;
      end if;
      Renderer.Create;
      Hud_Layer.Create;
      Car_Model.Build;
      Ready := True;
      Sim_Loop.Boot (Env ("ADARACE_NOWHEEL") = "");
      Start_Demo;
      Audio.Start;
      if Env ("ADARACE_AUTOSTART") /= "" then
         Begin_From_Menu;
         if Env ("ADARACE_AUTOPILOT") /= "" then
            --  (for the automated checks) the AI drives, under the player's rules
            Sim_Loop.Halt;
            Session.Force_AI := True;
            Session.Stunt_Riders := Env ("ADARACE_STUNT") /= "";
            Sim_Loop.Resume;
         end if;
         if Env ("ADARACE_DEMO_CAM") /= "" then
            --  (for the automated checks) the AI drives the car in the picture
            Sim_Loop.Halt;
            Session.Config.Mode := Session.Demo;
            Sim_Loop.Resume;
         end if;
      end if;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Start failed: " & Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
   end Realize;

   procedure Update_Sound (F : Sim_Loop.Frame) is
      P : Audio.Params;
      Sq : Float := 0.0;
   begin
      for W in Vehicle.Wheel_Id loop
         Sq := Float'Max (Sq, F.Slides (W));
      end loop;
      P.Rpm := F.Rpm;
      P.Load := F.Load;
      P.Speed := F.Speed;
      P.Squeal := Float'Min (1.0, Sq * 1.6);
      P.Rumble := (if F.On_Kerb then Float'Min (1.0, F.Speed / 10.0) else 0.0);
      P.Dirt := (if F.Off_Road then 1.0
                 elsif F.On_Dirt then Float'Min (0.7, F.Speed / 25.0) else 0.0);
      P.Scrape := F.Scrape;
      P.Inside := Renderer.Listener_Inside (Options);
      P.Engine := (case Session.Config.Kind is
                      when Vehicle.Road_GT => Audio.V8,
                      when Vehicle.Race_GT3 => Audio.V10,
                      when Vehicle.Rally_4WD => Audio.Turbo_Four,
                      when Vehicle.Classic_RWD => Audio.Old_Four,
                      when Vehicle.Hyper_AWD => Audio.V10,
                      when Vehicle.Sport_Bike => Audio.Bike_Four);
      P.Rain := Track.Wet * (if Session.Config.Weather = Session.Rain then 1.0 else 0.0);
      P.Snowy := Track.Snow > 0.5;
      P.Wipers := Session.Config.Weather in Session.Rain | Session.Snowing;
      P.Master := (if In_Menu or else Sim_Loop.Paused then Volume * 0.15 else Volume);
      --  The nearest others
      for I in 2 .. Natural'Min (F.Count, 5) loop
         declare
            L, Pan : Float;
         begin
            Renderer.Hearing (F.Poses (I), L, Pan);
            P.Others_V (I - 1) := (Rpm => F.Poses (I).Rpm, Level => L, Pan => Pan);
         end;
      end loop;
      Audio.Set (P);

      --  The co-driver reads the road ahead (not again in a replay)
      if Session.Config.Mode = Session.Stage and then Voice_On and then not Replay.Active then
         if not F.Laps (1).On_Grid and then not F.Laps (1).Finished then
            Codriver.Update (F.Laps (1).S, F.Speed, Track.Stage_End - F.Laps (1).Progress);
            declare
               W : Codriver.Word;
               Got : Boolean;
            begin
               loop
                  Codriver.Next_Word (W, Got);
                  exit when not Got;
                  Audio.Speak (W);
               end loop;
            end;
         end if;
      end if;

      if F.Gear /= Last_Gear then
         Audio.Clunk;
         Last_Gear := F.Gear;
      end if;
      if F.Impact > 2.0 and then F.Impact > Last_Impact + 0.5 then
         Audio.Thud (Float'Min (1.0, F.Impact / 14.0));
      end if;
      Last_Impact := F.Impact;
      if F.Lights /= Last_Lights and then F.Lights > Last_Lights then
         Audio.Beep (False);
      end if;
      Last_Lights := F.Lights;
      if F.Lights_Out and then not Was_Out then
         Audio.Beep (True);
      end if;
      Was_Out := F.Lights_Out;
   end Update_Sound;

   procedure Write_Picture (W, H : Natural) is
      use Ada.Text_IO;
      use Interfaces.C;
      type Bytes is array (Natural range <>) of aliased unsigned_char;
      type Bytes_Access is access Bytes;
      Data : constant Bytes_Access := new Bytes (0 .. W * H * 4 - 1);
      Name : constant String := To_String (Shot_File);
   begin
      GL.glReadPixels (0, 0, GL.GLsizei (W), GL.GLsizei (H), GL.GL_RGBA, GL.GL_UNSIGNED_BYTE,
                       Data (0)'Address);
      declare
         F : File_Type;
      begin
         Create (F, Out_File, Name);
         Put (F, "P6" & W'Image & H'Image & " 255" & ASCII.LF);
         for Row in reverse 0 .. H - 1 loop
            declare
               Line : String (1 .. W * 3);
            begin
               for X in 0 .. W - 1 loop
                  for C in 0 .. 2 loop
                     Line (X * 3 + C + 1) :=
                       Character'Val (Integer (Data (Row * W * 4 + X * 4 + C)));
                  end loop;
               end loop;
               Put (F, Line);
            end;
         end loop;
         Close (F);
      end;
   end Write_Picture;

   function Render (A, Context, Data : System.Address) return Gboolean
     with Convention => C;
   function Render (A, Context, Data : System.Address) return Gboolean is
      pragma Unreferenced (A, Context, Data);
      Prev, Cur : Sim_Loop.Frame;
      Viewport : aliased GL.GLint_Array (0 .. 3) := (others => 0);
      Now_T : constant Long_Float := Sim_Loop.Now;
      Dt : constant Float := Float'Min (0.1, Float (Now_T - Last_Frame_T));
   begin
      if not Ready or else Shown_Track = 0 then
         return 1;
      end if;
      Last_Frame_T := Now_T;
      if Dt > 0.0 then
         Fps_Smooth := Fps_Smooth + (1.0 / Dt - Fps_Smooth) * 0.05;
         if Frame_Count >= 60 then
            Late_20 := Late_20 + (if Dt > 0.020 then 1 else 0);
            Late_34 := Late_34 + (if Dt > 0.034 then 1 else 0);
            Worst_Frame := Float'Max (Worst_Frame, Dt);
         end if;
      end if;
      Sim_Loop.Latest (Prev, Cur);
      if Replay.Active then
         Replay.Advance (Dt);
         Replay.Pair (Now_T, Prev, Cur);
      elsif not In_Menu and then not Sim_Loop.Paused then
         Replay.Keep (Cur);
      end if;
      GL.glGetIntegerv (GL.GL_VIEWPORT, Viewport (0)'Address);
      declare
         W : constant Natural := Natural (Viewport (2));
         H : constant Natural := Natural (Viewport (3));
         Opt : Renderer.View_Options := Options;
         Msg : constant String :=
           (if Replay.Active
            then "REPLAY" & (if Replay.Speed = 0.0 then "  stopped"
                             elsif Replay.Speed = 1.0 then ""
                             else " " & Natural'Image (Natural (Replay.Speed * 100.0)) & " %")
                 & "   <- -> 5 s   up/down speed   space stop   C camera   F2 back"
            elsif Now_T < Message_Until then To_String (Message) else "");
      begin
         Opt.Dt := Dt;
         if In_Menu then
            Opt.Camera := Renderer.Trackside;
            Opt.Mirror := False;
            Opt.Guide := False;
            Opt.Day := Renderer.Time_Of_Day'Val (Integer (Combo_Time.Get_Active));
         end if;
         declare
            T0 : constant Long_Float := Sim_Loop.Now;
            Halves : constant Boolean :=
              not In_Menu and then Session.Config.Two_Players and then Cur.Count >= 2;
         begin
            Hud.Split := Halves;
            if Halves then
               --  Player one above, player two below
               Renderer.Draw (Prev, Cur, Opt, W, H / 2, Focus => 1, Y0 => H - H / 2);
               Renderer.Draw (Prev, Cur, Opt, W, H / 2, Focus => 2, Y0 => 0);
               --  (back to the whole window, which the next frame reads its size from)
               GL.glViewport (0, 0, GL.GLsizei (W), GL.GLsizei (H));
            else
               Renderer.Draw (Prev, Cur, Opt, W, H);
            end if;
            Time_Scene := Time_Scene + (Sim_Loop.Now - T0);
         end;
         Hud.In_Cockpit := Options.Camera = Renderer.Cockpit;
         if not In_Menu then
            Hud.Draw (Cur, W, H, Msg, (if Env ("ADARACE_FPS") /= "" then Fps_Smooth else 0.0), Show_Panels);
         end if;
         if Profile then
            GL.glFinish.all;
         end if;
         Time_All := Time_All + (Sim_Loop.Now - Now_T);
         if Want_Record then
            Want_Record := False;
            if Recorder.Active then
               Recorder.Stop;
            else
               Recorder.Start (W, H);
            end if;
            Say (Recorder.Message, 4.0);
         end if;
         --  ADARACE_RECORD: start some way into the drive, then leave
         if Record_For > 0.0 then
            if not Recorder.Active and then Float (Now_T) >= Record_At then
               Recorder.Start (W, H);
            elsif Recorder.Active and then Float (Recorder.Seconds) >= Record_For then
               Recorder.Stop;
               Record_For := 0.0;
               Gtk.Main.Main_Quit;
            end if;
         end if;
         --  (for the automated checks) a replay started by itself
         if Replay_From > 0 and then Frame_Count = Replay_From then
            Toggle_Replay;
         end if;
         Recorder.Frame (W, H);
         Update_Sound (Cur);
         Frame_Count := Frame_Count + 1;
         if Frame_Count = 60 then
            Started_At := Now_T;
         end if;
         if Shot_Frame > 0 and then Frame_Count = Shot_Frame then
            Write_Picture (W, H);
            Ada.Text_IO.Put_Line ("average fps"
                                  & Integer'Image (Integer (Long_Float (Frame_Count - 60) / (Now_T - Started_At)))
                                  & "  fps" & Integer'Image (Integer (Fps_Smooth))
                                  & "  over20ms" & Late_20'Image & "  over34ms" & Late_34'Image
                                  & "  worst ms" & Integer'Image (Integer (Worst_Frame * 1000.0))
                                  & "  physics load"
                                  & Integer'Image (Integer (Sim_Loop.Physics_Load * 100.0)) & " %"
                                  & "  scene ms" & Integer'Image (Integer (Time_Scene / Long_Float (Frame_Count) * 1000.0))
                                  & "  sound peak" & Audio.Peak'Image
                                  & "  frame ms" & Integer'Image (Integer (Time_All / Long_Float (Frame_Count) * 1000.0)));
            Gtk.Main.Main_Quit;
         end if;
      end;
      return 1;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Frame failed: " & Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
         return 1;
   end Render;

   --  ADARACE_SELFTEST: through the screens by itself, as a person would
   Self_Test : Boolean := False;
   Test_Tick : Natural := 0;

   procedure Test_Step is
   begin
      Test_Tick := Test_Tick + 1;
      case Test_Tick is
         when 120 => Toggle_Pause;
         when 200 => Toggle_Pause;
         when 260 =>
            Toggle_Pause;
            Sim_Loop.Restart;
         when 300 => Toggle_Pause;
         when 360 =>
            Toggle_Pause;
            To_Menu;
         when 480 => Combo_Track.Set_Active ((Combo_Track.Get_Active + 1) mod Gint (Track.Track_Count));
         when 600 => Combo_Car.Set_Active ((Combo_Car.Get_Active + 1) mod 2);
         when 640 => Combo_Weather.Set_Active (1);
         when 680 => Combo_Season.Set_Active (2);
         when 720 => Begin_Drive;
         when 780 =>
            Toggle_Look_Back;
            if Options.Look = 0.0 then
               Ada.Text_IO.Put_Line ("SELF TEST FAILED: the look back button did nothing");
            end if;
         when 800 =>
            Toggle_Look_Back;
            if Options.Look /= 0.0 then
               Ada.Text_IO.Put_Line ("SELF TEST FAILED: the look back button is stuck");
            end if;
         when 820 => Toggle_Look_Back;
         when 850 =>
            Toggle_Replay;
            if not Replay.Active then
               Ada.Text_IO.Put_Line ("SELF TEST FAILED: no replay to watch");
            end if;
         when 880 =>
            if Replay.Position <= 0.0 then
               Ada.Text_IO.Put_Line ("SELF TEST FAILED: the replay did not move");
            end if;
            Toggle_Replay;
            if Replay.Active or else Sim_Loop.Paused then
               Ada.Text_IO.Put_Line ("SELF TEST FAILED: the replay did not end cleanly");
            end if;
         when 840 =>
            Next_Camera;
            if Options.Look /= 0.0 then
               Ada.Text_IO.Put_Line ("SELF TEST FAILED: a new camera still looks back");
            end if;
         when 900 => Sim_Loop.Reset_Car;
         when 1000 =>
            Ada.Text_IO.Put_Line ("self test done on " & Track.Name (Track.Loaded));
            Gtk.Main.Main_Quit;
         when others => null;
      end case;
   end Test_Step;

   function Tick (Widget : not null access Gtk.Widget.Gtk_Widget_Record'Class;
                  Frame_Clock : not null access Gdk.Frame_Clock.Gdk_Frame_Clock_Record'Class)
                  return Boolean
   is
      pragma Unreferenced (Widget, Frame_Clock);
   begin
      Wheel_Buttons;
      --  Joining: say hello until the host gives the race, then drive it
      if Joining then
         Join_Wait := Join_Wait + 1;
         if Join_Wait mod 30 = 0 then
            Net.Send_Hello;
         end if;
         declare
            T, L : Natural;
         begin
            if Net.Go_Received (T, L) and then T in 1 .. Track.Track_Count then
               Joining := False;
               Join_Track := T;
               Join_Laps := L;
               Begin_Drive;
            end if;
         end;
      end if;
      --  A stage of a rally finished: its times go on the table
      if Rally.Active and then not In_Menu and then not Rally.Finished_Stage then
         declare
            Prev, Cur : Sim_Loop.Frame;
         begin
            Sim_Loop.Latest (Prev, Cur);
            if Cur.Laps (1).Finished then
               Rally.Finish_Stage (Cur.Laps (1).Finish_Time, Session.Cars (1));
            end if;
         end;
      end if;
      --  A round of the season run: its points go on the table
      if Championship.Active and then not In_Menu and then not Championship.Finished_Round then
         declare
            Prev, Cur : Sim_Loop.Frame;
         begin
            Sim_Loop.Latest (Prev, Cur);
            if Cur.Race_Over then
               Championship.Finish_Round;
            end if;
         end;
      end if;
      --  (for the automated checks) a picture of the table when it comes up
      if Shot_At_Table and then Shot_Frame = 0
        and then ((Rally.Active and then Rally.Finished_Stage)
                  or else (Championship.Active and then Championship.Finished_Round))
      then
         Shot_Frame := Frame_Count + 40;
      end if;
      --  (for the automated checks) on to the next stage or round by itself
      if Rally_Auto
        and then ((Rally.Active and then Rally.Finished_Stage)
                  or else (Championship.Active and then Championship.Finished_Round))
      then
         Rally_Wait := Rally_Wait + 1;
         if Rally_Wait = 240 then
            Rally_Wait := 0;
            if Championship.Active and then Championship.Is_Last then
               Ada.Text_IO.Put_Line ("season done, behind the leader by"
                                     & Championship.Leader_Gap'Image & " points");
               Gtk.Main.Main_Quit;
            elsif Rally.Active and then Rally.Is_Last then
               Ada.Text_IO.Put_Line ("rally done, position" & Rally.Position'Image);
               Gtk.Main.Main_Quit;
            else
               Advance_Rally;
            end if;
         end if;
      end if;
      if Self_Test then
         Test_Step;
      end if;
      if In_Menu and then Sim_Loop.Wheel_Present /= Wheel_Shown then
         Wheel_Shown := Sim_Loop.Wheel_Present;
         Status.Set_Text ((if Wheel_Shown then "Racing wheel found"
                           else "No racing wheel: arrow keys"));
      end if;
      --  In the menu a new track or car shows behind it
      if In_Menu and then Ready then
         if Pending_Track /= 0 then
            Pending_Track := 0;
            Start_Demo;
         end if;
      end if;
      Area.Queue_Render;
      return True;
   end Tick;

   ---------------------------------------------------------------------------
   --  Building the window
   ---------------------------------------------------------------------------

   Css : constant String :=
     "#menu { background: rgba(10,12,16,0.86); border-radius: 12px; padding: 26px; "
     & "         color: #e8e8ea; min-width: 430px; }"
     & "#title { font-size: 40px; font-weight: 800; color: #ffffff; letter-spacing: 2px; }"
     & "#sub { font-size: 14px; color: #ff5a3c; font-weight: 700; letter-spacing: 3px; }"
     & "#hint { font-size: 12px; color: #9a9ca3; }"
     & "#wheel { font-size: 12px; color: #66dd88; }"
     & "#start { background: #d8322a; background-image: none; color: white; font-size: 18px; "
     & "         font-weight: 800; padding: 12px; border: none; }"
     & "#start:hover, #start:focus { background: #f04338; background-image: none; }"
     & "#pause { background: rgba(10,12,16,0.88); border-radius: 12px; padding: 30px; color: white; }"
     & "#pause label { color: white; font-size: 16px; }"
     & "#pausetitle { font-size: 34px; font-weight: 800; }"
     & "#menu label { color: #d8d8dc; }"
     & "#menu button label { color: #202024; }"
     & "#menu #start label { color: white; }";

   procedure Changed_Choice (Self : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class) is
      pragma Unreferenced (Self);
   begin
      if Ready and then In_Menu then
         Pending_Track := 1;
      end if;
   end Changed_Choice;

   procedure Start_Clicked (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Begin_From_Menu;
   end Start_Clicked;

   procedure On_Destroy (Self : access Gtk.Widget.Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Gtk.Main.Main_Quit;
   end On_Destroy;

   procedure Build_Menu is
      use Gtk.Combo_Box_Text;
      Grid : Gtk.Grid.Gtk_Grid;
      Row : Gint := 0;
      Title, Sub, Hint : Gtk.Label.Gtk_Label;

      procedure Add_Row (Text : String; W : access Gtk.Widget.Gtk_Widget_Record'Class) is
         L : Gtk.Label.Gtk_Label;
      begin
         Gtk.Label.Gtk_New (L, Text);
         L.Set_Halign (Gtk.Widget.Align_End);
         Grid.Attach (L, 0, Row);
         W.Set_Hexpand (True);
         Grid.Attach (W, 1, Row);
         Row := Row + 1;
      end Add_Row;

      procedure Make (C : out Gtk_Combo_Box_Text; Text : String; Items : String) is
         First : Natural := Items'First;
      begin
         Gtk_New (C);
         for I in Items'Range loop
            if Items (I) = '|' then
               C.Append_Text (Items (First .. I - 1));
               First := I + 1;
            end if;
         end loop;
         C.Append_Text (Items (First .. Items'Last));
         C.Set_Active (0);
         Add_Row (Text, C);
      end Make;
   begin
      Gtk.Box.Gtk_New_Vbox (Menu, False, 10);
      Menu.Set_Name ("menu");
      Menu.Set_Halign (Gtk.Widget.Align_Start);
      Menu.Set_Valign (Gtk.Widget.Align_Center);
      Menu.Set_Margin_Start (50);

      Gtk.Label.Gtk_New (Title, "ADARACE");
      Title.Set_Name ("title");
      Title.Set_Halign (Gtk.Widget.Align_Start);
      Menu.Pack_Start (Title, False, False);
      Gtk.Label.Gtk_New (Sub, "DRIVING SIMULATOR");
      Sub.Set_Name ("sub");
      Sub.Set_Halign (Gtk.Widget.Align_Start);
      Menu.Pack_Start (Sub, False, False);

      Gtk.Grid.Gtk_New (Grid);
      Grid.Set_Row_Spacing (2);
      Grid.Set_Column_Spacing (14);
      Grid.Set_Margin_Top (6);
      Menu.Pack_Start (Grid, False, False);

      Gtk_New (Combo_Track);
      for T in 1 .. Track.Track_Count loop
         Combo_Track.Append_Text (Track.Name (T));
      end loop;
      Combo_Track.Set_Active (0);
      Add_Row ("Circuit", Combo_Track);

      Gtk_New (Combo_Car);
      for K in Vehicle.Car_Kind loop
         Combo_Car.Append_Text (Vehicle.Name (K));
      end loop;
      Combo_Car.Set_Active (0);
      Add_Row ("Car", Combo_Car);

      Make (Combo_Mode, "Mode", "Hot laps, against your ghost|Race against the AI|Driving school|Rally: every stage in turn|Championship: a race at every circuit|Two players: split screen|Online: host a race|Online: join a race");
      Gtk_New (Combo_Lesson);
      for L in School.Lesson_Id loop
         Combo_Lesson.Append_Text (School.Title (L));
      end loop;
      Combo_Lesson.Set_Active (0);
      Add_Row ("Lesson", Combo_Lesson);
      Make (Combo_Aid, "Driving aids", "None|Coloured driving line|Line and coach's tips");
      Make (Combo_Opp, "Opponents", "1|2|3|4|5|6|7");
      Combo_Opp.Set_Active (4);
      Make (Combo_Laps, "Race laps", "3|5|10|20");
      Make (Combo_Skill, "AI strength", "Easy|Medium|Hard|Alien");
      Combo_Skill.Set_Active (2);
      Make (Combo_Gear, "Gearbox",
            "Paddles, automatic clutch|H-shifter, automatic clutch|H-shifter with clutch pedal|Automatic");
      Make (Combo_Abs, "ABS", "On|Off");
      Make (Combo_Tc, "Traction control", "On|Off");
      Make (Combo_Wear, "Tyres and fuel (races)", "Fresh all race|Wear as in life|Wear three times as fast");
      Combo_Wear.Set_Active (1);
      Make (Combo_Damage, "Damage", "Off|Light|Full");
      Combo_Damage.Set_Active (1);
      Make (Combo_Time, "Light", "Morning|Noon|Golden hour|Overcast|Dawn|Dusk|Night");
      Combo_Time.Set_Active (1);
      Make (Combo_Weather, "Weather", "Clear|Rain|Fog|Snow");
      Make (Combo_Season, "Season", "Summer|Autumn|Winter|Spring");
      Combo_Weather.On_Changed (Changed_Choice'Access);
      Combo_Season.On_Changed (Changed_Choice'Access);

      Gtk.GEntry.Gtk_New (Host_Entry);
      Host_Entry.Set_Text ("localhost");
      Add_Row ("Host to join", Host_Entry);
      Gtk.Scale.Gtk_New_With_Range (FFB_Scale, Gtk.Enums.Orientation_Horizontal, 0.0, 100.0, 5.0);
      FFB_Scale.Set_Value (70.0);
      Add_Row ("Force feedback", FFB_Scale);
      Gtk.Scale.Gtk_New_With_Range (Fov_Scale, Gtk.Enums.Orientation_Horizontal, 30.0, 90.0, 1.0);
      Fov_Scale.Set_Value (55.0);
      Add_Row ("Field of view", Fov_Scale);

      Combo_Track.On_Changed (Changed_Choice'Access);
      Combo_Car.On_Changed (Changed_Choice'Access);

      Gtk.Button.Gtk_New (Start_Button, "DRIVE");
      Start_Button.Set_Name ("start");
      Start_Button.On_Clicked (Start_Clicked'Access);
      Menu.Pack_Start (Start_Button, False, False, 8);

      Gtk.Label.Gtk_New (Status, "");
      Status.Set_Name ("wheel");
      Status.Set_Halign (Gtk.Widget.Align_Start);
      Menu.Pack_Start (Status, False, False);

      Gtk.Label.Gtk_New
        (Hint,
         "Wheel: d-pad and X choose, start.  Keys: arrows, A/Z shift, C camera, R back on track," & ASCII.LF
         & "L line, B co-driver's voice, F9 record, Esc pause, F11 fullscreen.  Rally: choose Skovvej.  Pit box: yellow lines past the start.");
      Hint.Set_Name ("hint");
      Hint.Set_Halign (Gtk.Widget.Align_Start);
      Menu.Pack_Start (Hint, False, False);
   end Build_Menu;

   procedure Car_Changed (Self : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class) is
      pragma Unreferenced (Self);
   begin
      if Setup_Live then
         Store_Knobs;
         Show_Knobs (Chosen_Car);
      end if;
   end Car_Changed;

   procedure Setup_Reset (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Tunes (Setup_Car) := Knob_Default;
      Show_Knobs (Setup_Car);
   end Setup_Reset;

   procedure Build_Setup is
      Title, Hint : Gtk.Label.Gtk_Label;
      Grid : Gtk.Grid.Gtk_Grid;
      Reset : Gtk.Button.Gtk_Button;

      procedure Row (K : Knob; Text : String; Lo, Hi : Float) is
         L : Gtk.Label.Gtk_Label;
      begin
         Gtk.Label.Gtk_New (L, Text);
         L.Set_Halign (Gtk.Widget.Align_End);
         Grid.Attach (L, 0, Gint (K));
         Gtk.Scale.Gtk_New_With_Range
           (Knobs (K), Gtk.Enums.Orientation_Horizontal, Gdouble (Lo), Gdouble (Hi), 1.0);
         Knobs (K).Set_Value (Gdouble (Knob_Default (K)));
         Knobs (K).Set_Hexpand (True);
         Grid.Attach (Knobs (K), 1, Gint (K));
      end Row;
   begin
      Gtk.Box.Gtk_New_Vbox (Setup_Box, False, 8);
      Setup_Box.Set_Name ("menu");
      Setup_Box.Set_Halign (Gtk.Widget.Align_End);
      Setup_Box.Set_Valign (Gtk.Widget.Align_Center);
      Setup_Box.Set_Margin_End (50);
      Gtk.Label.Gtk_New (Title, "CAR SETUP");
      Title.Set_Name ("sub");
      Title.Set_Halign (Gtk.Widget.Align_Start);
      Setup_Box.Pack_Start (Title, False, False);
      Gtk.Grid.Gtk_New (Grid);
      Grid.Set_Row_Spacing (4);
      Grid.Set_Column_Spacing (14);
      Setup_Box.Pack_Start (Grid, False, False);
      Row (1, "Front springs %", 70.0, 130.0);
      Row (2, "Rear springs %", 70.0, 130.0);
      Row (3, "Front anti-roll bar %", 50.0, 150.0);
      Row (4, "Rear anti-roll bar %", 50.0, 150.0);
      Row (5, "Brakes to the front", -8.0, 8.0);
      Row (6, "Final drive %", 85.0, 115.0);
      Row (7, "Wing %", 50.0, 150.0);
      Row (8, "Differential lock %", 50.0, 150.0);
      Gtk.Button.Gtk_New (Reset, "Factory settings");
      Reset.On_Clicked (Setup_Reset'Access);
      Setup_Box.Pack_Start (Reset, False, False);
      Gtk.Label.Gtk_New
        (Hint,
         "Understeers: softer front, or stiffer rear." & ASCII.LF
         & "Oversteers: stiffer front, or softer rear." & ASCII.LF
         & "Rear locks under braking: more brakes to the front." & ASCII.LF
         & "Final drive up: quicker pull, lower top speed." & ASCII.LF
         & "Wing up: more grip in fast corners, slower on straights." & ASCII.LF
         & "Diff up: more traction out, less turn in.");
      Hint.Set_Name ("hint");
      Hint.Set_Halign (Gtk.Widget.Align_Start);
      Setup_Box.Pack_Start (Hint, False, False);
   end Build_Setup;

   procedure Build_Pause is
      T, L : Gtk.Label.Gtk_Label;
   begin
      Gtk.Box.Gtk_New_Vbox (Pause_Box, False, 12);
      Pause_Box.Set_Name ("pause");
      Pause_Box.Set_Halign (Gtk.Widget.Align_Center);
      Pause_Box.Set_Valign (Gtk.Widget.Align_Center);
      Gtk.Label.Gtk_New (T, "PAUSED");
      T.Set_Name ("pausetitle");
      Pause_Box.Pack_Start (T, False, False);
      Gtk.Label.Gtk_New
        (L, "Esc / Options: go on" & ASCII.LF
         & "F5 / Square: restart" & ASCII.LF
         & "F10 / Circle: back to the menu");
      Pause_Box.Pack_Start (L, False, False);
   end Build_Pause;

   procedure Find_Home is
      --  Shaders are found relative to the project
      Cmd : constant String := Ada.Command_Line.Command_Name;
   begin
      if not Ada.Directories.Exists ("shaders/world.vert") then
         for I in reverse Cmd'Range loop
            if Cmd (I) = '/' then
               Ada.Directories.Set_Directory (Cmd (Cmd'First .. I) & "..");
               exit;
            end if;
         end loop;
      end if;
   end Find_Home;

   procedure Run is
      Over : Gtk.Overlay.Gtk_Overlay;
      Id : Guint;
      Provider : Gtk.Css_Provider.Gtk_Css_Provider;
      Dummy : Boolean;
   begin
      Find_Home;
      Gtk.Main.Init;

      Gtk.Css_Provider.Gtk_New (Provider);
      Dummy := Provider.Load_From_Data (Css, null);
      Gtk.Style_Context.Add_Provider_For_Screen
        (Gdk.Screen.Get_Default, Gtk.Css_Provider."+" (Provider),
         Gtk.Style_Provider.Priority_Application);

      Gtk.Window.Gtk_New (Window);
      Window.Set_Title ("AdaRace");
      Window.Set_Default_Size (1600, 900);
      Window.On_Destroy (On_Destroy'Access);
      Window.On_Key_Press_Event (Key_Press'Access, False);
      Window.On_Key_Release_Event (Key_Release'Access, False);

      GL_Area.Gtk_New (Area);
      Area.Set_Required_Version (4, 5);
      Area.Set_Has_Depth_Buffer (False);
      Area.On_Realize (Realize'Access);
      Area.On_Render (Render'Access);
      Area.Set_Can_Focus (True);

      Gtk.Overlay.Gtk_New (Over);
      Build_Menu;
      Build_Setup;
      Build_Pause;
      Over.Add (Area);
      Over.Add_Overlay (Menu);
      Over.Add_Overlay (Setup_Box);
      Over.Add_Overlay (Pause_Box);
      Window.Add (Over);

      Load_Choices;
      if Env ("ADARACE_VOLUME") /= "" then
         Volume := Float'Value (Env ("ADARACE_VOLUME"));
      end if;
      Profile := Env ("ADARACE_PROFILE") /= "";
      Self_Test := Env ("ADARACE_SELFTEST") /= "";
      Shot_File := To_Unbounded_String (Env ("ADARACE_SHOT"));
      if Env ("ADARACE_SHOT_FRAME") /= "" then
         Shot_Frame := Natural'Value (Env ("ADARACE_SHOT_FRAME"));
      end if;
      if Env ("ADARACE_TRACK") /= "" then
         Combo_Track.Set_Active (Gint'Value (Env ("ADARACE_TRACK")) - 1);
      end if;
      if Env ("ADARACE_CAR") /= "" then
         Combo_Car.Set_Active (Gint'Value (Env ("ADARACE_CAR")));
      end if;
      if Env ("ADARACE_MODE") /= "" then
         Combo_Mode.Set_Active (Gint'Value (Env ("ADARACE_MODE")));
      end if;
      if Env ("ADARACE_TIME") /= "" then
         Combo_Time.Set_Active (Gint'Value (Env ("ADARACE_TIME")));
      end if;
      if Env ("ADARACE_RECORD_FOR") /= "" then
         Record_For := Float'Value (Env ("ADARACE_RECORD_FOR"));
         if Env ("ADARACE_RECORD_AT") /= "" then
            Record_At := Float'Value (Env ("ADARACE_RECORD_AT"));
         end if;
      end if;
      Rally_Auto := Env ("ADARACE_RALLY_AUTO") /= "";
      Shot_At_Table := Env ("ADARACE_SHOT_TABLE") /= "";
      if Env ("ADARACE_REPLAY_AT") /= "" then
         Replay_From := Natural'Value (Env ("ADARACE_REPLAY_AT"));
      end if;
      if Env ("ADARACE_JOIN") /= "" then
         Host_Entry.Set_Text (Env ("ADARACE_JOIN"));
      end if;
      if Env ("ADARACE_WEATHER") /= "" then
         Combo_Weather.Set_Active (Gint'Value (Env ("ADARACE_WEATHER")));
      end if;
      if Env ("ADARACE_SEASON") /= "" then
         Combo_Season.Set_Active (Gint'Value (Env ("ADARACE_SEASON")));
      end if;
      if Env ("ADARACE_AID") /= "" then
         Combo_Aid.Set_Active (Gint'Value (Env ("ADARACE_AID")));
      end if;
      if Env ("ADARACE_LESSON") /= "" then
         Combo_Lesson.Set_Active (Gint'Value (Env ("ADARACE_LESSON")));
      end if;
      if Env ("ADARACE_ORBIT") /= "" then
         Options.Orbit := Float'Value (Env ("ADARACE_ORBIT")) * Ada.Numerics.Pi / 180.0;
      end if;
      if Env ("ADARACE_CAMERA") /= "" then
         Options.Camera := Renderer.Camera_Kind'Value (Env ("ADARACE_CAMERA"));
      end if;

      Show_Knobs (Chosen_Car);
      Combo_Car.On_Changed (Car_Changed'Access);
      Setup_Live := True;

      Window.Show_All;
      --  GTK's handshake with the compositor settles into every other
      --  refresh here (40 fps); without it the frame clock keeps the display's
      if Env ("ADARACE_FRAME_SYNC") = "" then
         Set_Frame_Sync (Window.Get_Window, 0);
      end if;
      if Env ("ADARACE_FULLSCREEN") /= "" then
         Window.Fullscreen;
         Is_Fullscreen := True;
      end if;
      Pause_Box.Hide;
      Start_Button.Grab_Focus;
      Id := Area.Add_Tick_Callback (Tick'Access);
      pragma Unreferenced (Id);
      Gtk.Main.Main;

      Recorder.Stop;
      Sim_Loop.Shutdown;
      Audio.Stop;
   end Run;

end App;
