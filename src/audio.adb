--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Exceptions;
with Ada.Numerics.Elementary_Functions;
with Ada.Text_IO;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Audio is

   use Ada.Numerics.Elementary_Functions;
   use Interfaces;
   use type C.int;
   use type System.Address;

   Two_Pi : constant := 6.28318_53072;
   Rate   : constant := 44_100;
   Frames : constant := 441;      --  ten milliseconds a block

   type Sample_Spec is record
      Format   : C.int;
      Sample_Rate : Unsigned_32;
      Channels : Unsigned_8;
   end record
     with Convention => C;

   type Buffer_Attr is record
      Max_Length, T_Length, Pre_Buf, Min_Req, Frag_Size : Unsigned_32;
   end record
     with Convention => C;

   function PA_New
     (Server : C.Strings.chars_ptr; Name : C.Strings.chars_ptr; Dir : C.int;
      Dev : C.Strings.chars_ptr; Stream_Name : C.Strings.chars_ptr;
      Spec : access Sample_Spec; Map : System.Address; Attr : access Buffer_Attr;
      Error : access C.int) return System.Address
     with Import, Convention => C, External_Name => "pa_simple_new";

   function PA_Write (S : System.Address; Data : System.Address; Bytes : C.size_t;
                      Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "pa_simple_write";

   procedure PA_Free (S : System.Address)
     with Import, Convention => C, External_Name => "pa_simple_free";

   protected Shared is
      procedure Put (P : Params);
      function Get return Params;
      procedure Hit (S : Float);
      procedure Gear;
      procedure Tone (High : Boolean);
      procedure Take (Hit_S : out Float; Gear_On : out Boolean; Beep_On : out Integer);
      procedure Quit;
      function Stopping return Boolean;
      procedure Set_Peak (V : Float);
      function Get_Peak return Float;
   private
      Peak_V : Float := 0.0;
      Cur : Params;
      Pending_Hit : Float := 0.0;
      Pending_Gear : Boolean := False;
      Pending_Beep : Integer := 0;
      Done : Boolean := False;
   end Shared;

   protected body Shared is
      procedure Put (P : Params) is
      begin
         Cur := P;
      end Put;
      function Get return Params is (Cur);
      procedure Hit (S : Float) is
      begin
         Pending_Hit := Float'Max (Pending_Hit, S);
      end Hit;
      procedure Gear is
      begin
         Pending_Gear := True;
      end Gear;
      procedure Tone (High : Boolean) is
      begin
         Pending_Beep := (if High then 2 else 1);
      end Tone;
      procedure Take (Hit_S : out Float; Gear_On : out Boolean; Beep_On : out Integer) is
      begin
         Hit_S := Pending_Hit;
         Gear_On := Pending_Gear;
         Beep_On := Pending_Beep;
         Pending_Hit := 0.0;
         Pending_Gear := False;
         Pending_Beep := 0;
      end Take;
      procedure Quit is
      begin
         Done := True;
      end Quit;
      function Stopping return Boolean is (Done);
      procedure Set_Peak (V : Float) is
      begin
         Peak_V := V;
      end Set_Peak;
      function Get_Peak return Float is (Peak_V);
   end Shared;

   Noise_State : Unsigned_32 := 2463534242;

   function White return Float is
   begin
      Noise_State := Noise_State xor Shift_Left (Noise_State, 13);
      Noise_State := Noise_State xor Shift_Right (Noise_State, 17);
      Noise_State := Noise_State xor Shift_Left (Noise_State, 5);
      return Float (Noise_State and 16#FFFF#) / 32768.0 - 1.0;
   end White;

   --  A resonant band filter (state variable)
   type Filter is record
      Low, Band : Float := 0.0;
   end record;

   function Run (F : in out Filter; Input, Fc, Q : Float) return Float is
      G : constant Float := 2.0 * Sin (3.14159 * Float'Min (Fc, 9000.0) / Float (Rate));
      High : constant Float := Input - F.Low - Q * F.Band;
   begin
      F.Band := F.Band + G * High;
      F.Low := F.Low + G * F.Band;
      return F.Band;
   end Run;

   --  One pole low-pass
   procedure Smooth (S : in out Float; Target, K : Float) is
   begin
      S := S + (Target - S) * K;
   end Smooth;

   task Mixer is
      entry Go;
   end Mixer;

   task body Mixer is
      Spec : aliased Sample_Spec := (3, Rate, 2);   --  16 bit little endian
      Attr : aliased Buffer_Attr :=
        (Max_Length => Unsigned_32'Last,
         T_Length   => Frames * 4 * 4,              --  about 40 ms
         Pre_Buf    => Unsigned_32'Last,
         Min_Req    => Unsigned_32'Last,
         Frag_Size  => Unsigned_32'Last);
      Err : aliased C.int := 0;
      Stream : System.Address := System.Null_Address;
      type Sample_Array is array (0 .. 2 * Frames - 1) of Integer_16 with Convention => C;
      Buffer : aliased Sample_Array;

      Crank : Float := 0.0;        --  phase of the crankshaft
      Whine : Float := 0.0;
      Rpm_S, Load_S, Speed_S, Squeal_S, Rumble_S, Dirt_S, Scrape_S : Float := 0.0;
      Exh1, Exh2, Tyre_F, Wind_F, Road_F, Thud_F, Scrape_F : Filter;
      Low_In : Float := 0.0;
      Thud_E : Float := 0.0;
      Clunk_E : Float := 0.0;
      Beep_E : Float := 0.0;
      Beep_P : Float := 0.0;
      Beep_F : Float := 800.0;
      Rumble_P : Float := 0.0;
      Block_Peak : Float := 0.0;
      type Phase_Array is array (Voice_List'Range) of Float;
      V_Phase : Phase_Array := (others => 0.0);
      V_Rpm, V_Lev, V_Pan : Phase_Array := (others => 0.0);
      Name : C.Strings.chars_ptr := C.Strings.New_String ("AdaRace");
      SName : C.Strings.chars_ptr := C.Strings.New_String ("car");
   begin
      select
         accept Go;
      or
         terminate;
      end select;
      Stream := PA_New (C.Strings.Null_Ptr, Name, 1, C.Strings.Null_Ptr, SName,
                        Spec'Access, System.Null_Address, Attr'Access, Err'Access);
      C.Strings.Free (Name);
      C.Strings.Free (SName);
      while Stream /= System.Null_Address and then not Shared.Stopping loop
         declare
            P : constant Params := Shared.Get;
            Hit_S : Float;
            Gear_On : Boolean;
            Beep_On : Integer;
            K : constant := 0.002;
         begin
            Shared.Take (Hit_S, Gear_On, Beep_On);
            Thud_E := Float'Max (Thud_E, Hit_S);
            if Gear_On then
               Clunk_E := 1.0;
            end if;
            if Beep_On /= 0 then
               Beep_E := 1.0;
               Beep_F := (if Beep_On = 2 then 1320.0 else 660.0);
            end if;
            for V in Voice_List'Range loop
               V_Rpm (V) := P.Others_V (V).Rpm;
               V_Lev (V) := V_Lev (V) + (P.Others_V (V).Level - V_Lev (V)) * 0.1;
               V_Pan (V) := P.Others_V (V).Pan;
            end loop;
            for I in 0 .. Frames - 1 loop
               Smooth (Rpm_S, P.Rpm, 0.004);
               Smooth (Load_S, P.Load, K);
               Smooth (Speed_S, P.Speed, K);
               Smooth (Squeal_S, P.Squeal, K);
               Smooth (Rumble_S, P.Rumble, K * 2.0);
               Smooth (Dirt_S, P.Dirt, K);
               Smooth (Scrape_S, P.Scrape, K);
               declare
                  Crank_F : constant Float := Rpm_S / 60.0;
                  --  A V8: four firings per turn, unevenly loud between banks
                  Phase_Firing : constant Float := Crank * 4.0;
                  Pulse : constant Float :=
                    Sin (Two_Pi * Phase_Firing)
                    + 0.55 * Sin (Two_Pi * Phase_Firing * 2.0 + 0.7)
                    + 0.30 * Sin (Two_Pi * Phase_Firing * 3.0 + 1.9)
                    + 0.18 * Sin (Two_Pi * Phase_Firing * 5.0)
                    + 0.35 * Sin (Two_Pi * Crank * 2.0 + 0.3)
                    + 0.22 * Sin (Two_Pi * Crank);
                  Lump : constant Float :=
                    1.0 + 0.3 * Sin (Two_Pi * Crank) * (1.0 - Load_S * 0.6);
                  Rough : constant Float := White * (0.08 + 0.3 * Load_S);
                  Raw : constant Float := (Pulse * Lump + Rough * 1.2) * (0.25 + 0.75 * Load_S);
                  --  The exhaust resonates; the note hardens with the revs
                  Res1 : constant Float := Run (Exh1, Raw, 180.0 + Rpm_S * 0.05, 0.55);
                  Res2 : constant Float := Run (Exh2, Raw, 700.0 + Rpm_S * 0.18, 0.75);
                  Clip : constant Float :=
                    (Res1 * 0.55 + Res2 * (0.15 + 0.3 * Load_S)) * 0.8;
                  Eng : constant Float := Clip / (1.0 + abs Clip * 0.6);
                  Whine_S : constant Float :=
                    0.03 * Sin (Two_Pi * Whine) * Float'Min (1.0, Rpm_S / 6000.0);

                  W1 : constant Float := White;
                  Tyre : constant Float :=
                    Run (Tyre_F, W1, 850.0 + 250.0 * Squeal_S + 100.0 * Sin (Two_Pi * Crank * 0.03), 0.09)
                    * 0.28 * Squeal_S;
                  Wind : constant Float :=
                    Run (Wind_F, White, 300.0 + Speed_S * 9.0, 1.0)
                    * Float'Min (0.5, (Speed_S / 90.0) ** 2) * (if P.Inside then 0.22 else 0.55);
                  Road : constant Float :=
                    Run (Road_F, White, 70.0 + Speed_S * 1.6, 0.8) * Float'Min (0.35, Speed_S / 120.0);
                  Rib : constant Float :=
                    (if Rumble_P < 0.5 then 1.0 else -1.0) * 0.28 * Rumble_S;
                  Gravel : constant Float :=
                    White * 0.22 * Dirt_S * Float'Min (1.0, Speed_S / 15.0);
                  Scr : constant Float :=
                    Run (Scrape_F, White, 2300.0, 0.25) * 0.3 * Scrape_S;
                  Bang : constant Float :=
                    Run (Thud_F, White * 2.0, 120.0, 0.4) * Thud_E;
                  Clk : constant Float := White * 0.3 * Clunk_E * Clunk_E;
                  Bp : constant Float := Sin (Two_Pi * Beep_P) * 0.22 * Beep_E;
                  Eng_Gain : constant Float := (if P.Inside then 0.75 else 0.6);
                  Mono0 : constant Float :=
                    Eng * Eng_Gain + Whine_S + Tyre + Wind + Road + Rib + Gravel + Scr + Bang + Clk + Bp;
                  Left, Right : Float;
               begin
                  --  From inside the cockpit the top end is duller
                  Low_In := Low_In + (Mono0 - Low_In) * (if P.Inside then 0.5 else 0.85);
                  Left := Low_In;
                  Right := Low_In;

                  --  The others
                  for V in Voice_List'Range loop
                     if V_Lev (V) > 0.002 then
                        declare
                           Wave : constant Float :=
                             Sin (Two_Pi * V_Phase (V)) + 0.5 * Sin (Two_Pi * V_Phase (V) * 2.0)
                             + 0.25 * Sin (Two_Pi * V_Phase (V) * 3.0);
                           S : constant Float := Wave * 0.16 * V_Lev (V);
                        begin
                           Left := Left + S * (1.0 - V_Pan (V)) * 0.5;
                           Right := Right + S * (1.0 + V_Pan (V)) * 0.5;
                           V_Phase (V) := V_Phase (V) + (V_Rpm (V) / 60.0 * 4.0) / Float (Rate);
                           if V_Phase (V) > 1.0 then
                              V_Phase (V) := V_Phase (V) - 1.0;
                           end if;
                        end;
                     end if;
                  end loop;

                  Crank := Crank + Crank_F / Float (Rate);
                  if Crank > 100.0 then
                     Crank := Crank - 100.0;
                  end if;
                  Whine := Whine + Crank_F * 11.0 / Float (Rate);
                  if Whine > 1.0 then
                     Whine := Whine - 1.0;
                  end if;
                  Rumble_P := Rumble_P + Float'Max (20.0, Speed_S / 1.5) / Float (Rate);
                  if Rumble_P > 1.0 then
                     Rumble_P := Rumble_P - 1.0;
                  end if;
                  Beep_P := Beep_P + Beep_F / Float (Rate);
                  if Beep_P > 1.0 then
                     Beep_P := Beep_P - 1.0;
                  end if;
                  Thud_E := Thud_E * 0.9994;
                  Clunk_E := Clunk_E * 0.997;
                  Beep_E := Beep_E * 0.99985;

                  Block_Peak := Float'Max (Block_Peak, Float'Max (abs Left, abs Right));
                  Left := Left * P.Master;
                  Right := Right * P.Master;
                  Buffer (2 * I) := Integer_16 (Float'Max (-1.0, Float'Min (1.0, Left)) * 32000.0);
                  Buffer (2 * I + 1) := Integer_16 (Float'Max (-1.0, Float'Min (1.0, Right)) * 32000.0);
               end;
            end loop;
         end;
         Shared.Set_Peak (Block_Peak);
         Block_Peak := 0.0;
         if PA_Write (Stream, Buffer'Address, C.size_t (Frames * 4), Err'Access) < 0 then
            exit;
         end if;
      end loop;
      if Stream /= System.Null_Address then
         PA_Free (Stream);
      end if;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Sound stopped: " & Ada.Exceptions.Exception_Information (E));
   end Mixer;

   Started : Boolean := False;

   procedure Start is
   begin
      if not Started then
         Started := True;
         Mixer.Go;
      end if;
   end Start;

   procedure Stop is
   begin
      Shared.Quit;
   end Stop;

   procedure Set (P : Params) is
   begin
      Shared.Put (P);
   end Set;

   procedure Thud (Strength : Float) is
   begin
      Shared.Hit (Strength);
   end Thud;

   procedure Clunk is
   begin
      Shared.Gear;
   end Clunk;

   procedure Beep (High : Boolean) is
   begin
      Shared.Tone (High);
   end Beep;

   function Peak return Float is (Shared.Get_Peak);

end Audio;
