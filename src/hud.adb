--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Cairo;
with Cairo.Image_Surface;
with Cairo.Surface;
with Glib;
with System;

with Hud_Layer;
with School;
with Session;
with Track;
with Vehicle;

package body Hud is

   use Cairo;
   use Glib;
   use type Session.Mode_Kind;
   use type School.Phase_Kind;

   Tip_Seen : Natural := 0;
   Tip_Until : Long_Float := 0.0;
   use type Track.Note_Kind;

   Surface : Cairo_Surface := Null_Surface;
   Cr      : Cairo_Context := Null_Context;
   Surf_W, Surf_H : Natural := 0;
   Frame_No : Natural := 0;

   function GD (V : Float) return Gdouble is (Gdouble (V));

   function Sin_Of (A : Float) return Float renames Ada.Numerics.Elementary_Functions.Sin;
   function Cos_Of (A : Float) return Float renames Ada.Numerics.Elementary_Functions.Cos;

   procedure Color (R, G, B : Float; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, GD (R), GD (G), GD (B), GD (A));
   end Color;

   procedure Rect (X, Y, W, H : Float) is
   begin
      Rectangle (Cr, GD (X), GD (Y), GD (W), GD (H));
      Fill (Cr);
   end Rect;

   Mono_Ratio : constant := 0.602;

   procedure Text (S : String; X, Y, Size : Float; Align : Float := 0.0) is
      --  Align: 0 left, 0.5 centre, 1 right
      W : constant Float := Float (S'Length) * Size * Mono_Ratio;
   begin
      Set_Font_Size (Cr, GD (Size));
      Move_To (Cr, GD (X - W * Align), GD (Y));
      Show_Text (Cr, S);
   end Text;

   function Trim (S : String) return String is
     (if S'Length > 0 and then S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);

   function Format_Time (T : Float) return String is
      Ms : constant Natural := Natural (Float'Max (0.0, T) * 1000.0);
      M  : constant Natural := Ms / 60_000;
      S  : constant Natural := (Ms / 1000) mod 60;
      F  : constant Natural := Ms mod 1000;
      SS : constant String := Trim (Natural'Image (S));
      FS : constant String := Trim (Natural'Image (F));
   begin
      return Trim (Natural'Image (M)) & ":"
        & (if S < 10 then "0" else "") & SS & "."
        & (if F < 100 then "0" else "") & (if F < 10 then "0" else "") & FS;
   end Format_Time;

   function Signed (V : Float) return String is
      A : constant Natural := Natural (abs V * 1000.0);
      Whole : constant String := Trim (Natural'Image (A / 1000));
      Rest : constant Natural := A mod 1000;
      RS : constant String := Trim (Natural'Image (Rest));
   begin
      return (if V < 0.0 then "-" else "+") & Whole & "."
        & (if Rest < 100 then "0" else "") & (if Rest < 10 then "0" else "") & RS;
   end Signed;

   --  A rounded dark panel
   procedure Panel (X, Y, W, H : Float; A : Float := 0.55) is
      R : constant Float := 6.0;
      Pi : constant := Ada.Numerics.Pi;
   begin
      Color (0.03, 0.035, 0.045, A);
      New_Path (Cr);
      Arc (Cr, GD (X + W - R), GD (Y + R), GD (R), GD (-Pi / 2.0), 0.0);
      Arc (Cr, GD (X + W - R), GD (Y + H - R), GD (R), 0.0, GD (Pi / 2.0));
      Arc (Cr, GD (X + R), GD (Y + H - R), GD (R), GD (Pi / 2.0), GD (Pi));
      Arc (Cr, GD (X + R), GD (Y + R), GD (R), GD (Pi), GD (3.0 * Pi / 2.0));
      Close_Path (Cr);
      Fill (Cr);
   end Panel;

   --  The circuit as a thin line
   Map_N : constant := 300;
   Map_X, Map_Y : array (0 .. Map_N - 1) of Float := (others => 0.0);
   Map_MinX, Map_MinZ, Map_Scale : Float := 0.0;

   procedure Set_Track_Map is
      MaxX, MaxZ : Float := Float'First;
      MinX, MinZ : Float := Float'Last;
   begin
      for I in Track.Samples'Range loop
         MinX := Float'Min (MinX, Track.Samples (I).X);
         MaxX := Float'Max (MaxX, Track.Samples (I).X);
         MinZ := Float'Min (MinZ, Track.Samples (I).Z);
         MaxZ := Float'Max (MaxZ, Track.Samples (I).Z);
      end loop;
      Map_MinX := MinX;
      Map_MinZ := MinZ;
      Map_Scale := 1.0 / Float'Max (MaxX - MinX, MaxZ - MinZ);
      for I in Map_X'Range loop
         declare
            S : Track.Sample renames Track.Samples (I * Track.Count / Map_N);
         begin
            Map_X (I) := (S.X - MinX) * Map_Scale;
            Map_Y (I) := (S.Z - MinZ) * Map_Scale;
         end;
      end loop;
   end Set_Track_Map;

   procedure Draw_Map (F : Sim_Loop.Frame; X, Y, Size : Float) is
   begin
      Panel (X - 10.0, Y - 10.0, Size + 20.0, Size + 20.0, 0.35);
      Set_Line_Width (Cr, 3.0);
      Color (0.9, 0.9, 0.9, 0.85);
      Move_To (Cr, GD (X + Map_X (0) * Size), GD (Y + Map_Y (0) * Size));
      for I in 1 .. Map_N - 1 loop
         Line_To (Cr, GD (X + Map_X (I) * Size), GD (Y + Map_Y (I) * Size));
      end loop;
      Close_Path (Cr);
      Stroke (Cr);
      for I in reverse 1 .. F.Count loop
         declare
            P : Sim_Loop.Car_Pose renames F.Poses (I);
            PX : constant Float := X + (P.X - Map_MinX) * Map_Scale * Size;
            PY : constant Float := Y + (P.Z - Map_MinZ) * Map_Scale * Size;
         begin
            if I = 1 then
               Color (1.0, 0.25, 0.1);
            else
               Color (0.3, 0.7, 1.0);
            end if;
            Arc (Cr, GD (PX), GD (PY), (if I = 1 then 6.0 else 4.0), 0.0, 6.2832);
            Fill (Cr);
         end;
      end loop;
   end Draw_Map;

   procedure Paint (F : Sim_Loop.Frame; W, H : Float; Message : String; Fps : Float;
                    Panels : Boolean) is
      S : constant Float := H / 1080.0;  --  all sizes for a 1080 line screen
      L : Session.Lap_Info renames F.Laps (1);
      Cx : constant Float := W / 2.0;
      Racing : constant Boolean := Session.Config.Mode = Session.Race;
      On_Stage : constant Boolean := Session.Config.Mode = Session.Stage;
   begin
      Set_Operator (Cr, Cairo_Operator_Clear);
      Cairo.Paint (Cr);
      Set_Operator (Cr, Cairo_Operator_Over);
      Select_Font_Face (Cr, "DejaVu Sans Mono", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);

      if Panels then
         --  Bottom centre: rev bar, gear, speed ------------------------------
         declare
            PW : constant Float := 460.0 * S;
            PH : constant Float := 118.0 * S;
            PX : constant Float := Cx - PW / 2.0;
            PY : constant Float := H - PH - 22.0 * S;
            Rev : constant Float := Float'Min (1.0, F.Rpm / (F.Red_Line + 300.0));
            Bars : constant := 40;
            Red_At : constant Float := F.Red_Line / (F.Red_Line + 300.0);
            Shift_Now : constant Boolean := F.Rpm > F.Red_Line * 0.96;
         begin
            --  (from the cockpit the real instruments tell all this)
            if not In_Cockpit then
            Panel (PX, PY, PW, PH, 0.62);
            for I in 0 .. Bars - 1 loop
               declare
                  Part : constant Float := Float (I) / Float (Bars);
                  BX : constant Float := PX + 12.0 * S + Part * (PW - 24.0 * S);
                  On : constant Boolean := Part < Rev;
                  BW : constant Float := (PW - 24.0 * S) / Float (Bars) - 2.0 * S;
               begin
                  if On then
                     if Part > Red_At - 0.04 then
                        Color (1.0, 0.12, 0.08);
                     elsif Part > Red_At - 0.2 then
                        Color (1.0, 0.72, 0.1);
                     else
                        Color (0.35, 0.95, 0.5);
                     end if;
                  else
                     Color (0.3, 0.3, 0.32, 0.5);
                  end if;
                  Rect (BX, PY + 10.0 * S, BW, 16.0 * S);
               end;
            end loop;
            if Shift_Now then
               Color (1.0, 0.15, 0.1);
            else
               Color (1.0, 1.0, 1.0);
            end if;
            Text ((if F.Gear = -1 then "R" elsif F.Gear = 0 then "N" else Trim (F.Gear'Image)),
                  Cx, PY + 96.0 * S, 72.0 * S, 0.5);
            Color (1.0, 1.0, 1.0);
            Text (Trim (Natural'Image (Natural (F.Speed * 3.6))), PX + 175.0 * S, PY + 80.0 * S, 44.0 * S, 1.0);
            Color (0.7, 0.7, 0.72);
            Text ("km/h", PX + 175.0 * S, PY + 102.0 * S, 15.0 * S, 1.0);
            Text (Trim (Natural'Image (Natural (F.Rpm))), PX + PW - 22.0 * S, PY + 64.0 * S, 20.0 * S, 1.0);
            Text ("rpm", PX + PW - 22.0 * S, PY + 84.0 * S, 13.0 * S, 1.0);
            end if;
            if F.Abs_On then
               Color (1.0, 0.8, 0.1);
               Text ("ABS", PX + 12.0 * S, PY + 58.0 * S, 15.0 * S);
            end if;
            if F.Tc_On then
               Color (0.2, 0.8, 1.0);
               Text ("TC", PX + 12.0 * S, PY + 78.0 * S, 15.0 * S);
            end if;
            if F.Grind then
               Color (1.0, 0.2, 0.1);
               Text ("CLUTCH!", PX + PW - 22.0 * S, PY + 106.0 * S, 15.0 * S, 1.0);
            end if;
         end;

         --  Pedals and tyres, right of it ------------------------------------
         declare
            PX : constant Float := Cx + 245.0 * S;
            PH : constant Float := 118.0 * S;
            PY : constant Float := H - PH - 22.0 * S;

            procedure Pedal (Index : Natural; V : Float; R, G, B : Float) is
               BX : constant Float := PX + 12.0 * S + Float (Index) * 16.0 * S;
               Full : constant Float := PH - 24.0 * S;
            begin
               Color (0.3, 0.3, 0.32, 0.55);
               Rect (BX, PY + 12.0 * S, 11.0 * S, Full);
               Color (R, G, B);
               Rect (BX, PY + 12.0 * S + Full * (1.0 - V), 11.0 * S, Full * V);
            end Pedal;

            procedure Tyre (X, Y : Float; Temp, Slide, Wear : Float) is
               T : constant Float := (Temp - 45.0) / 70.0;
               R : constant Float := Float'Min (1.0, Float'Max (0.0, T * 2.0 - 0.6));
               G : constant Float := Float'Min (1.0, Float'Max (0.15, 1.5 - abs (T - 0.55) * 2.6));
               B : constant Float := Float'Min (1.0, Float'Max (0.0, 1.0 - T * 2.2));
            begin
               Color (R, G, B, 0.95);
               Rect (X, Y, 20.0 * S, 34.0 * S);
               if Slide > 0.05 then
                  Color (1.0, 1.0, 1.0, Float'Min (0.9, Slide * 1.6));
                  Rect (X, Y, 20.0 * S, 34.0 * S);
               end if;
               --  Dark from the top as the rubber goes
               if Wear > 0.01 then
                  Color (0.0, 0.0, 0.0, 0.72);
                  Rect (X, Y, 20.0 * S, 34.0 * S * Wear);
               end if;
            end Tyre;
            TX : constant Float := PX + 74.0 * S;
         begin
            Panel (PX, PY, 138.0 * S, PH, 0.55);
            Pedal (0, F.Clutch, 0.3, 0.6, 1.0);
            Pedal (1, F.Brake, 1.0, 0.18, 0.12);
            Pedal (2, F.Throttle, 0.3, 0.95, 0.4);
            Tyre (TX, PY + 12.0 * S, F.Temps (1), F.Slides (1), F.Wear (1));
            Tyre (TX + 28.0 * S, PY + 12.0 * S, F.Temps (2), F.Slides (2), F.Wear (2));
            Tyre (TX, PY + 64.0 * S, F.Temps (3), F.Slides (3), F.Wear (3));
            Tyre (TX + 28.0 * S, PY + 64.0 * S, F.Temps (4), F.Slides (4), F.Wear (4));
         end;

         --  Fuel and what is broken, over the tyres ---------------------------
         declare
            Broken : constant Boolean :=
              F.Dmg_Aero > 0.01 or else F.Dmg_Engine > 0.01 or else abs F.Toe > 0.002;
            PX : constant Float := Cx + 245.0 * S;
            Rows : constant Float := (if F.Uses_Fuel then 1.0 else 0.0) + (if Broken then 2.0 else 0.0);
         begin
            if Rows > 0.0 then
               declare
                  PH : constant Float := Rows * 19.0 * S + 10.0 * S;
                  PY : Float := H - 118.0 * S - 22.0 * S - PH - 6.0 * S;
               begin
                  Panel (PX, PY, 196.0 * S, PH, 0.55);
                  PY := PY + 18.0 * S;
                  if F.Uses_Fuel then
                     declare
                        Laps_Left : constant Float :=
                          F.Fuel / Float'Max (0.01, Track.Length / 1000.0
                                              * Vehicle.Fuel_Per_Km (Session.Config.Kind));
                     begin
                        if Laps_Left < 1.0 then
                           Color (1.0, 0.3, 0.15);
                        else
                           Color (0.9, 0.9, 0.92);
                        end if;
                        Text ("FUEL " & Trim (Natural'Image (Natural (F.Fuel))) & " kg, "
                              & Trim (Natural'Image (Natural (Float'Floor (Laps_Left)))) & " laps",
                              PX + 10.0 * S, PY, 14.0 * S);
                        PY := PY + 19.0 * S;
                     end;
                  end if;
                  if Broken then
                     Color (1.0, 0.65, 0.15);
                     Text ("AERO" & Natural'Image (Natural (F.Dmg_Aero * 100.0)) & " % ENGINE"
                           & Natural'Image (Natural (F.Dmg_Engine * 100.0)) & " %",
                           PX + 10.0 * S, PY, 14.0 * S);
                     PY := PY + 19.0 * S;
                     Text ((if abs F.Toe <= 0.002 then "STEERING OK"
                            else (if F.Toe > 0.0 then "STEERING PULLS RIGHT" else "STEERING PULLS LEFT")),
                           PX + 10.0 * S, PY, 14.0 * S);
                  end if;
               end;
            end if;
         end;

         --  G meter, left of it -----------------------------------------------
         declare
            R : constant Float := 54.0 * S;
            GX : constant Float := Cx - 245.0 * S - 59.0 * S;
            GY : constant Float := H - 22.0 * S - 59.0 * S;
         begin
            Panel (GX - 59.0 * S, GY - 59.0 * S, 118.0 * S, 118.0 * S, 0.55);
            Set_Line_Width (Cr, GD (1.0 * S));
            Color (0.7, 0.7, 0.75, 0.6);
            Arc (Cr, GD (GX), GD (GY), GD (R), 0.0, 6.2832);
            Stroke (Cr);
            Arc (Cr, GD (GX), GD (GY), GD (R * 0.5), 0.0, 6.2832);
            Stroke (Cr);
            Color (1.0, 0.85, 0.25);
            Arc (Cr, GD (GX + Float'Max (-1.0, Float'Min (1.0, F.Ay / 19.62)) * R),
                 GD (GY - Float'Max (-1.0, Float'Min (1.0, F.Ax / 19.62)) * R),
                 GD (5.0 * S), 0.0, 6.2832);
            Fill (Cr);
         end;

         --  Times, top left --------------------------------------------------
         declare
            X : constant Float := 22.0 * S;
            Y : Float := 22.0 * S;
         begin
            Panel (X, Y, 300.0 * S, 136.0 * S);
            Y := Y + 30.0 * S;
            Color (0.75, 0.75, 0.78);
            if On_Stage then
               Text ("STAGE", X + 14.0 * S, Y, 18.0 * S);
               Color (1.0, 1.0, 1.0);
               declare
                  Left : constant Float :=
                    Float'Max (0.0, Track.Stage_End - L.Progress) / 100.0;
                  Tenths : constant Natural := Natural (Float'Ceiling (Left));
               begin
                  Text (Trim (Natural'Image (Tenths / 10)) & "."
                        & Trim (Natural'Image (Tenths mod 10)) & " km to go",
                        X + 90.0 * S, Y, 18.0 * S);
               end;
            else
               Text ("LAP", X + 14.0 * S, Y, 18.0 * S);
               Color (1.0, 1.0, 1.0);
               Text (Trim (Natural'Image (L.Lap + 1))
                     & (if Racing then " /" & Session.Config.Laps'Image else ""),
                     X + 70.0 * S, Y, 18.0 * S);
            end if;
            if L.Invalid then
               Color (1.0, 0.25, 0.15);
               Text ("INVALID", X + 288.0 * S, Y, 16.0 * S, 1.0);
            end if;
            Y := Y + 40.0 * S;
            Color (1.0, 1.0, 1.0);
            Text (Format_Time (L.Lap_Time), X + 14.0 * S, Y, 34.0 * S);
            Y := Y + 28.0 * S;
            Color (0.75, 0.75, 0.78);
            Text ("LAST " & (if L.Last_Time > 0.0 then Format_Time (L.Last_Time) else "-"),
                  X + 14.0 * S, Y, 16.0 * S);
            Y := Y + 22.0 * S;
            Color (0.75, 0.55, 1.0);
            Text ("BEST " & (if L.Best_Time > 0.0 then Format_Time (L.Best_Time) else "-"),
                  X + 14.0 * S, Y, 16.0 * S);
         end;

         --  Delta, top centre ------------------------------------------------
         if L.Has_Delta and then not Racing then
            declare
               BW : constant Float := 360.0 * S;
               BX : constant Float := Cx - BW / 2.0;
               BY : constant Float := 22.0 * S;
               Part : constant Float := Float'Max (-1.0, Float'Min (1.0, L.Delta_T / 2.0));
            begin
               Panel (BX, BY, BW, 52.0 * S);
               if Part < 0.0 then
                  Color (0.2, 0.95, 0.35);
               else
                  Color (1.0, 0.25, 0.15);
               end if;
               if Part >= 0.0 then
                  Rect (Cx - Part * (BW / 2.0 - 6.0 * S), BY + 40.0 * S, Part * (BW / 2.0 - 6.0 * S), 6.0 * S);
               else
                  Rect (Cx, BY + 40.0 * S, -Part * (BW / 2.0 - 6.0 * S), 6.0 * S);
               end if;
               Text (Signed (L.Delta_T), Cx, BY + 31.0 * S, 26.0 * S, 0.5);
            end;
         end if;

         --  Race order, below the times --------------------------------------
         if F.Count > 1 then
            declare
               X : constant Float := 22.0 * S;
               Y0 : constant Float := 172.0 * S;
            begin
               Panel (X, Y0, 200.0 * S, 30.0 * S + 24.0 * S * Float (F.Count));
               Color (1.0, 1.0, 1.0);
               Text ("P" & Trim (L.Position'Image) & " /" & F.Count'Image, X + 12.0 * S, Y0 + 24.0 * S, 18.0 * S);
               for P in 1 .. F.Count loop
                  for I in 1 .. F.Count loop
                     if F.Laps (I).Position = P then
                        if I = 1 then
                           Color (1.0, 0.8, 0.2);
                        else
                           Color (0.85, 0.85, 0.88);
                        end if;
                        Text (Trim (P'Image) & "  "
                              & (if I = 1 then "YOU" else "AI" & Trim (Natural'Image (I - 1)))
                              & "  L" & Trim (Natural'Image (F.Laps (I).Lap + 1)),
                              X + 12.0 * S, Y0 + 24.0 * S + 24.0 * S * Float (P), 15.0 * S);
                     end if;
                  end loop;
               end loop;
            end;
         end if;

         Draw_Map (F, W - 232.0 * S, 32.0 * S, 200.0 * S);

         if Fps > 0.0 then
            Color (0.8, 0.8, 0.8, 0.7);
            Text (Trim (Natural'Image (Natural (Fps))) & " fps", W - 20.0 * S, H - 14.0 * S, 13.0 * S, 1.0);
         end if;
      end if;

      --  Start lights -----------------------------------------------------------
      if not F.Lights_Out then
         declare
            Size : constant Float := 34.0 * S;
            X0 : constant Float := Cx - 2.5 * (Size * 2.2);
            Y : constant Float := 130.0 * S;
         begin
            Panel (X0 - 14.0 * S, Y - Size - 14.0 * S, 5.0 * Size * 2.2 + 8.0 * S, 2.0 * Size + 28.0 * S, 0.85);
            for I in 1 .. 5 loop
               if I <= F.Lights then
                  Color (1.0, 0.08, 0.05);
               else
                  Color (0.18, 0.04, 0.04);
               end if;
               Arc (Cr, GD (X0 + (Float (I) - 0.5) * Size * 2.2 - 6.0 * S), GD (Y), GD (Size), 0.0, 6.2832);
               Fill (Cr);
            end loop;
         end;
      end if;

      --  The co-driver: what comes next, and what comes straight after it ----
      if On_Stage and then not F.Laps (1).Finished then
         declare
            Here : constant Float := F.Laps (1).S;
            Ready : constant Boolean := not F.Laps (1).On_Grid;
            First : constant Natural := (if Ready then Track.Next_Note (Here) else Track.Next_Note (0.0));
            Lead : constant Float := Float'Max (110.0, F.Speed * 6.5);
            Y0 : constant Float := 146.0 * S;   --  clear of the mirror
            Box_W : constant Float := 132.0 * S;
            Box_H : constant Float := 118.0 * S;

            procedure Show (N : Positive; X : Float; Big : Boolean) is
               Nt : Track.Note renames Track.Notes (N);
               Dist : constant Float :=
                 Float'Max (0.0, Nt.S - (if Ready then Here else 0.0));
               CX : constant Float := X + Box_W / 2.0;
               Base : constant Float := Y0 + 78.0 * S;
               Lift : constant Float := 56.0 * S;
               --  The tighter the corner, the more the arrow turns
               Turn : constant Float :=
                 (case Nt.Grade is
                     when 1 => 2.6, when 2 => 2.0, when 3 => 1.5,
                     when 4 => 1.05, when 5 => 0.7, when 6 => 0.4);
               Sign : constant Float := (if Nt.Kind = Track.Right then 1.0 else -1.0);
               PX : Float := CX;
               PY : Float := Base;
               Angle : Float := 0.0;
               Step_L : constant Float := Lift / 14.0;
            begin
               Panel (X, Y0, Box_W, Box_H, (if Big then 0.72 else 0.5));
               if Nt.Grade <= 2 then
                  Color (1.0, 0.3, 0.15);
               elsif Nt.Grade <= 4 then
                  Color (1.0, 0.82, 0.25);
               else
                  Color (0.92, 0.95, 0.98);
               end if;
               Set_Line_Width (Cr, GD (6.0 * S));
               if Nt.Kind = Track.Crest then
                  Move_To (Cr, GD (CX - 42.0 * S), GD (Base));
                  Curve_To (Cr, GD (CX - 14.0 * S), GD (Base - 46.0 * S),
                            GD (CX + 14.0 * S), GD (Base - 46.0 * S),
                            GD (CX + 42.0 * S), GD (Base));
                  Stroke (Cr);
                  Text ("CREST", CX, Y0 + 100.0 * S, 15.0 * S, 0.5);
               else
                  Move_To (Cr, GD (PX), GD (PY));
                  for K in 1 .. 14 loop
                     Angle := Angle + Sign * Turn / 14.0;
                     PX := PX + Sin_Of (Angle) * Step_L;
                     PY := PY - Cos_Of (Angle) * Step_L;
                     Line_To (Cr, GD (PX), GD (PY));
                  end loop;
                  Stroke (Cr);
                  --  Its head
                  declare
                     HL : constant Float := 15.0 * S;
                  begin
                     Move_To (Cr, GD (PX + Sin_Of (Angle) * HL), GD (PY - Cos_Of (Angle) * HL));
                     Line_To (Cr, GD (PX + Cos_Of (Angle) * HL * 0.7), GD (PY + Sin_Of (Angle) * HL * 0.7));
                     Line_To (Cr, GD (PX - Cos_Of (Angle) * HL * 0.7), GD (PY - Sin_Of (Angle) * HL * 0.7));
                     Close_Path (Cr);
                     Fill (Cr);
                  end;
                  Text ((if Nt.Kind = Track.Right then "R" else "L")
                        & Trim (Natural'Image (Nt.Grade))
                        & (if Nt.Long then " LONG" else ""),
                        CX, Y0 + 100.0 * S, 17.0 * S, 0.5);
               end if;
               Color (0.85, 0.85, 0.88);
               Text (Trim (Natural'Image (Natural (Float'Floor (Dist / 10.0)) * 10)) & " m",
                     CX, Y0 + 19.0 * S, 14.0 * S, 0.5);
            end Show;
         begin
            if First > 0 and then Track.Notes (First).S - (if Ready then Here else 0.0) < Lead then
               Show (First, Cx - Box_W - 4.0 * S, True);
               if First < Track.Note_Count
                 and then Track.Notes (First + 1).S - (if Ready then Here else 0.0) < Lead * 1.6
               then
                  Show (First + 1, Cx + 4.0 * S, False);
               end if;
            end if;
         end;
      end if;

      --  The driving school --------------------------------------------------
      if F.School.Phase /= School.Off then
         declare
            St : School.Status renames F.School;
            Less : constant School.Lesson_Id := St.Lesson;
            PW : constant Float := 760.0 * S;
            PX : constant Float := Cx - PW / 2.0;
            PY : constant Float := H - 118.0 * S - 22.0 * S - 92.0 * S;
         begin
            if St.Phase = School.Running then
               Panel (PX, PY, PW, 80.0 * S, 0.6);
               Color (1.0, 0.85, 0.25);
               Text (School.Title (Less), PX + 14.0 * S, PY + 22.0 * S, 16.0 * S);
               Color (0.92, 0.92, 0.94);
               if St.Time < 15.0 then
                  Text (School.Goal (Less), PX + 14.0 * S, PY + 44.0 * S, 12.0 * S);
               else
                  Text ("On the line" & Natural'Image (Natural (St.On_Line * 100.0))
                        & " %  too fast" & St.Too_Fast'Image & "  slides" & St.Slides'Image
                        & "  off" & St.Offs'Image & "  time" & Natural'Image (Natural (St.Time))
                        & " / par" & Natural'Image (Natural (St.Par)) & " s",
                        PX + 14.0 * S, PY + 44.0 * S, 14.0 * S);
               end if;
               Color (0.3, 0.3, 0.33, 0.8);
               Rect (PX + 14.0 * S, PY + 58.0 * S, PW - 28.0 * S, 8.0 * S);
               Color (0.3, 0.85, 0.4);
               Rect (PX + 14.0 * S, PY + 58.0 * S, (PW - 28.0 * S) * St.Done, 8.0 * S);
            else
               declare
                  RY : constant Float := H * 0.22;
                  Good : constant Boolean := St.Phase = School.Passed;
               begin
                  Panel (PX, RY, PW, 150.0 * S, 0.82);
                  if Good then
                     Color (0.3, 0.95, 0.45);
                  else
                     Color (1.0, 0.4, 0.2);
                  end if;
                  Text ((if Good then "PASSED" else "NOT YET"), Cx, RY + 42.0 * S, 32.0 * S, 0.5);
                  Color (1.0, 1.0, 1.0);
                  Text (School.Title (Less), Cx, RY + 72.0 * S, 17.0 * S, 0.5);
                  Text (School.Result_Line, Cx, RY + 98.0 * S, 15.0 * S, 0.5);
                  Color (0.8, 0.8, 0.84);
                  Text ("F5 / Square-in-pause: again.  Esc: the menu.", Cx, RY + 128.0 * S, 14.0 * S, 0.5);
               end;
            end if;
         end;
      end if;

      --  The coach's word after a lap --------------------------------------
      if Coach_On and then F.Tip_Len > 0 then
         if F.Tip_Serial /= Tip_Seen then
            Tip_Seen := F.Tip_Serial;
            Tip_Until := F.Time + 9.0;
         end if;
         if F.Time < Tip_Until then
            declare
               Line : String renames F.Tip (1 .. F.Tip_Len);
               Sz : constant Float := 16.0 * S;
               MW : constant Float := Float (Line'Length) * Sz * Mono_Ratio + 40.0 * S;
               TY : constant Float := H * 0.70;
            begin
               Panel (Cx - MW / 2.0, TY, MW, 34.0 * S, 0.72);
               Color (0.6, 0.9, 1.0);
               Text (Line, Cx, TY + 23.0 * S, Sz, 0.5);
            end;
         end if;
      end if;

      --  Stage over ----------------------------------------------------------
      if On_Stage and then F.Laps (1).Finished and then F.School.Phase = School.Off then
         declare
            L1 : Session.Lap_Info renames F.Laps (1);
            PW : constant Float := 440.0 * S;
            PX : constant Float := Cx - PW / 2.0;
            PY : constant Float := H * 0.24;
         begin
            Panel (PX, PY, PW, 150.0 * S, 0.8);
            Color (1.0, 1.0, 1.0);
            Text ("STAGE COMPLETE", Cx, PY + 36.0 * S, 24.0 * S, 0.5);
            Text (Format_Time (L1.Finish_Time), Cx, PY + 84.0 * S, 38.0 * S, 0.5);
            Color (0.75, 0.55, 1.0);
            Text ((if F.New_Best then "NEW BEST TIME" else "BEST " & Format_Time (L1.Best_Time)),
                  Cx, PY + 112.0 * S, 17.0 * S, 0.5);
            Color (0.8, 0.8, 0.84);
            Text ("Resets" & Natural'Image (L1.Resets) & "   Esc for the menu",
                  Cx, PY + 136.0 * S, 14.0 * S, 0.5);
         end;
      end if;

      if F.Service_Left > 0.0 or else F.Service_Offer
        or else (F.Uses_Fuel and then F.Fuel <= 0.0)
      then
         declare
            Line : constant String :=
              (if F.Service_Left > 0.0
               then "SERVICE " & Trim (Natural'Image (Natural (Float'Ceiling (F.Service_Left)))) & " s"
               elsif F.Service_Offer then "PIT BOX: STOP HERE FOR SERVICE"
               else "OUT OF FUEL");
            Sz : constant Float := 24.0 * S;
            MW : constant Float := Float (Line'Length) * Sz * Mono_Ratio + 40.0 * S;
         begin
            Panel (Cx - MW / 2.0, H * 0.32, MW, 44.0 * S, 0.7);
            Color (1.0, 0.85, 0.25);
            Text (Line, Cx, H * 0.32 + 31.0 * S, Sz, 0.5);
         end;
      end if;

      if Message'Length > 0 then
         declare
            Sz : constant Float := 30.0 * S;
            MW : constant Float := Float (Message'Length) * Sz * Mono_Ratio + 40.0 * S;
         begin
            Panel (Cx - MW / 2.0, H * 0.22, MW, 56.0 * S, 0.7);
            Color (1.0, 1.0, 1.0);
            Text (Message, Cx, H * 0.22 + 39.0 * S, Sz, 0.5);
         end;
      end if;
   end Paint;

   procedure Draw (F : Sim_Loop.Frame; Width, Height : Natural;
                   Message : String; Fps : Float; Show_Panels : Boolean) is
      Fresh : Boolean := False;
   begin
      if Width /= Surf_W or else Height /= Surf_H then
         if Cr /= Null_Context then
            Destroy (Cr);
            Cairo.Surface.Destroy (Surface);
         end if;
         Surface := Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32, Gint (Width), Gint (Height));
         Cr := Create (Surface);
         Surf_W := Width;
         Surf_H := Height;
         Fresh := True;
      end if;
      Frame_No := Frame_No + 1;
      if Fresh or else Frame_No mod 2 = 0 then
         Paint (F, Float (Width), Float (Height), Message, Fps, Show_Panels);
         Cairo.Surface.Flush (Surface);
         Fresh := True;
      end if;
      declare
         Data : constant System.Address := Cairo.Image_Surface.Get_Data_Generic (Surface);
         Stride : constant Natural := Natural (Cairo.Image_Surface.Get_Stride (Surface));
      begin
         if Fresh then
            Hud_Layer.Draw (Data, Width, Height, Stride, 0, 0, Width, Height);
         else
            Hud_Layer.Draw (Data, Width, Height, Stride, 0, 0, 0, 0);
         end if;
      end;
   end Draw;

end Hud;
