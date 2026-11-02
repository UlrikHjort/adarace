--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Exceptions;
with Ada.Numerics.Elementary_Functions;
with Ada.Real_Time;
with Ada.Text_IO;

with Gamepad;
with Net;
with Telemetry;
with Track;

package body Sim_Loop is

   use Ada.Real_Time;
   use Ada.Numerics.Elementary_Functions;
   use type Track.Surface_Kind;
   use type Vehicle.Car_Kind;
   use type Session.Mode_Kind;
   use type Net.Role;
   use type Wheel.Button;

   Epoch : constant Time := Clock;

   function Now return Long_Float is
     (Long_Float (To_Duration (Clock - Epoch)));

   function Clamp (V, Lo, Hi : Float) return Float is
     (Float'Max (Lo, Float'Min (Hi, V))) with Inline;

   type Button_Queue is array (1 .. 16) of Wheel.Button;

   protected Shared is
      procedure Put_Keys (K : Keys);
      function Get_Keys return Keys;
      procedure Shift (Up : Boolean);
      procedure Take_Shift (Up, Down : out Boolean);
      procedure Set_Reverse (On : Boolean);
      function Get_Reverse return Boolean;
      procedure Publish (F : Frame);
      procedure Read (Prev, Cur : out Frame);
      procedure Press (B : Wheel.Button);
      procedure Next (B : out Wheel.Button; Got : out Boolean);
      procedure Set_Wheel (Present : Boolean; Steer : Float);
      function Wheel_On return Boolean;
      function Wheel_Pos return Float;
      procedure Set_Pause (On : Boolean);
      function Is_Paused return Boolean;
      procedure Ask (Restart, Reset : Boolean);
      procedure Take (Restart, Reset : out Boolean);
      procedure Set_Gain (G : Float);
      procedure Take_Gain (G : out Float; Changed : out Boolean);
      procedure Set_Load (L : Float);
      function Get_Load return Float;
   private
      K_State : Keys;
      Up_Req, Down_Req : Boolean := False;
      Rev_Req : Boolean := False;
      A, B : Frame;
      Queue : Button_Queue;
      Q_Len : Natural := 0;
      W_On : Boolean := False;
      W_Pos : Float := 0.0;
      Is_Paused_V : Boolean := False;
      Want_Restart, Want_Reset : Boolean := False;
      Gain : Float := 0.7;
      Gain_New : Boolean := False;
      Busy : Float := 0.0;
   end Shared;

   protected body Shared is
      procedure Put_Keys (K : Keys) is
      begin
         K_State := K;
      end Put_Keys;
      function Get_Keys return Keys is (K_State);
      procedure Shift (Up : Boolean) is
      begin
         if Up then
            Up_Req := True;
         else
            Down_Req := True;
         end if;
      end Shift;
      procedure Take_Shift (Up, Down : out Boolean) is
      begin
         Up := Up_Req;
         Down := Down_Req;
         Up_Req := False;
         Down_Req := False;
      end Take_Shift;
      procedure Set_Reverse (On : Boolean) is
      begin
         Rev_Req := On;
      end Set_Reverse;
      function Get_Reverse return Boolean is (Rev_Req);
      procedure Publish (F : Frame) is
      begin
         A := B;
         B := F;
      end Publish;
      procedure Read (Prev, Cur : out Frame) is
      begin
         Prev := A;
         Cur := B;
      end Read;
      procedure Press (B : Wheel.Button) is
      begin
         if Q_Len < Queue'Last then
            Q_Len := Q_Len + 1;
            Queue (Q_Len) := B;
         end if;
      end Press;
      procedure Next (B : out Wheel.Button; Got : out Boolean) is
      begin
         B := Wheel.Cross;
         Got := Q_Len > 0;
         if Got then
            B := Queue (1);
            Queue (1 .. Q_Len - 1) := Queue (2 .. Q_Len);
            Q_Len := Q_Len - 1;
         end if;
      end Next;
      procedure Set_Wheel (Present : Boolean; Steer : Float) is
      begin
         W_On := Present;
         W_Pos := Steer;
      end Set_Wheel;
      function Wheel_On return Boolean is (W_On);
      function Wheel_Pos return Float is (W_Pos);
      procedure Set_Pause (On : Boolean) is
      begin
         Is_Paused_V := On;
      end Set_Pause;
      function Is_Paused return Boolean is (Is_Paused_V);
      procedure Ask (Restart, Reset : Boolean) is
      begin
         Want_Restart := Want_Restart or Restart;
         Want_Reset := Want_Reset or Reset;
      end Ask;
      procedure Take (Restart, Reset : out Boolean) is
      begin
         Restart := Want_Restart;
         Reset := Want_Reset;
         Want_Restart := False;
         Want_Reset := False;
      end Take;
      procedure Set_Gain (G : Float) is
      begin
         Gain := G;
         Gain_New := True;
      end Set_Gain;
      procedure Take_Gain (G : out Float; Changed : out Boolean) is
      begin
         G := Gain;
         Changed := Gain_New;
         Gain_New := False;
      end Take_Gain;
      procedure Set_Load (L : Float) is
      begin
         Busy := L;
      end Set_Load;
      function Get_Load return Float is (Busy);
   end Shared;

   task Runner is
      pragma Storage_Size (16 * 1024 * 1024);
      entry Boot_Up (Use_Wheel : Boolean);
      entry Halt_Now;
      entry Resume_Now;
      entry Stop;
   end Runner;

   ---------------------------------------------------------------------------
   --  Force feedback: what the front tyres do to the steering rack
   ---------------------------------------------------------------------------

   Force_Clock : Float := 0.0;
   Last_Steer  : Float := 0.0;
   Steer_Rate  : Float := 0.0;
   Bump_Smooth : Float := 0.0;
   Jolt        : Float := 0.0;
   Last_Force  : Float := 0.0;

   procedure Force_Feedback (Active : Boolean) is
      Step : constant := 0.008;
      Steer : constant Float := Wheel.State.Steering;
      Rate : constant Float := (Steer - Last_Steer) / Step;
      F : Float;
   begin
      Last_Steer := Steer;
      Steer_Rate := Steer_Rate + (Rate - Steer_Rate) * 0.35;
      Force_Clock := Force_Clock + Step;
      if not Active then
         --  In the menu and paused: a soft centring spring
         Wheel.Set_Force (Clamp (-0.35 * Steer - 0.05 * Steer_Rate, -0.5, 0.5));
         return;
      end if;
      declare
         C : Vehicle.Car renames Session.Cars (1);
         V : constant Float := Vehicle.Speed (C);
         Slow : constant Float := Clamp (1.0 - V / 6.0, 0.0, 1.0);
         Moving : constant Float := Clamp (V / 8.0, 0.0, 1.0);
         Norm : constant Float :=
           (case Session.Config.Kind is
               when Vehicle.Race_GT3 => 420.0,
               when Vehicle.Road_GT => 260.0,
               when Vehicle.Rally_4WD => 230.0,
               when Vehicle.Classic_RWD => 190.0,
               when Vehicle.Hyper_AWD => 400.0,
               when Vehicle.Sport_Bike => 100.0);
      begin
         --  The aligning torque of the tyres: goes light at the limit
         F := C.Rack / Norm;
         --  Tight when parked, heavy in the hands
         F := F - Slow * 0.3 * Steer;
         --  A little of the column's own friction
         F := F - (0.03 + 0.02 * Moving) * Steer_Rate;
         --  Road surface through the rack
         Bump_Smooth := Bump_Smooth + (C.Road_Feel * 90.0 - Bump_Smooth) * 0.5;
         F := F + Clamp (Bump_Smooth, -0.12, 0.12) * Moving;
         --  Kerbs and grass rumble
         declare
            Kerb_On : constant Boolean :=
              C.Wheels (1).Surf = Track.Kerb or else C.Wheels (2).Surf = Track.Kerb;
            Off_On : constant Boolean :=
              C.Wheels (1).Surf in Track.Grass | Track.Gravel
              or else C.Wheels (2).Surf in Track.Grass | Track.Gravel;
         begin
            if C.Wheels (1).Surf = Track.Dirt or else C.Wheels (2).Surf = Track.Dirt then
               --  Stones and washboard through the rack
               F := F + 0.045 * Moving * Sin (Force_Clock * 2.0 * 3.14159 * 24.0 + 3.0 * Sin (Force_Clock * 7.0))
                 + 0.03 * Moving * Sin (Force_Clock * 2.0 * 3.14159 * (V / 2.5));
            end if;
            if Kerb_On then
               F := F + 0.1 * Moving * Sin (Force_Clock * 2.0 * 3.14159 * (V / 1.5));
            elsif Off_On then
               F := F + 0.07 * Moving * Sin (Force_Clock * 2.0 * 3.14159 * 18.0)
                 * Sin (Force_Clock * 13.0);
            end if;
         end;
         --  Hits
         Jolt := Float'Max (Jolt * 0.92, Clamp (C.Impact / 12.0, 0.0, 1.0));
         F := F + Jolt * 0.5 * Sin (Force_Clock * 2.0 * 3.14159 * 22.0);
         F := F + 0.06 * C.Scrape * Sin (Force_Clock * 2.0 * 3.14159 * 31.0);
         --  Soft limit, never a slam
         F := F / (1.0 + 0.3 * abs F);
         Last_Force := Clamp (F, -0.9, 0.9);
         Wheel.Set_Force (Last_Force);
      end;
   end Force_Feedback;

   ---------------------------------------------------------------------------
   --  Inputs: wheel and keyboard together
   ---------------------------------------------------------------------------

   Key_Steer, Key_Throttle, Key_Brake, Key_Clutch : Float := 0.0;

   Key_Steer_2, Key_Throttle_2, Key_Brake_2 : Float := 0.0;

   --  The controller is the second player's when two drive, else the first's
   function Pad_Is_Second return Boolean is
     (Session.Config.Two_Players and then Gamepad.Present);

   --  A stick to the steering: on a motorcycle at speed it asks for a share
   --  of the lean the tyres allow; in a car it is limited, like the keys, to
   --  what the tyres can use, with a little in hand to catch a slide
   function From_Stick (Stick, V : Float) return Float is
      S : Vehicle.Spec renames Session.Spec;
      L : constant Float := S.A + S.B;
   begin
      if Vehicle.Is_Bike (Session.Config.Kind) then
         declare
            Lean : constant Float := Stick * Vehicle.Lean_Limit (S);
            Kappa : constant Float := 9.81 * Tan (Lean) / Float'Max (6.0, V) ** 2;
            At_Speed : constant Float := Arctan (Kappa * L) / (S.Steer_Lock * 0.5);
            W : constant Float := Clamp ((V - 3.0) / 5.0, 0.0, 1.0);
         begin
            return W * At_Speed + (1.0 - W) * Stick;
         end;
      else
         declare
            Lock_At : constant Float :=
              Clamp ((Arctan (0.12) + L * 9.81 * S.Mu * 0.9 / Float'Max (25.0, V * V))
                     / S.Steer_Lock * 1.5, 0.15, 1.0);
         begin
            return Stick * Lock_At;
         end;
      end if;
   end From_Stick;

   --  The second player's hands: the arrow keys when the first has the wheel,
   --  else W A S D
   procedure Gather_Second (Cycle : Float) is
      K : constant Keys := Shared.Get_Keys;
      Arrows : constant Boolean := Wheel.Present;
      L : constant Boolean := (if Arrows then K.Left else K.Left_2);
      R : constant Boolean := (if Arrows then K.Right else K.Right_2);
      T : constant Boolean := (if Arrows then K.Throttle else K.Throttle_2);
      B : constant Boolean := (if Arrows then K.Brake else K.Brake_2);
      V : constant Float := Vehicle.Speed (Session.Cars (2));
      Lock_At : constant Float :=
        Clamp ((Arctan (0.12) + (Session.Spec.A + Session.Spec.B) * 9.81
                * Session.Spec.Mu * 0.9 / Float'Max (25.0, V * V))
               / Session.Spec.Steer_Lock, 0.05, 1.0);
      Target : constant Float := (if L then -Lock_At elsif R then Lock_At else 0.0);
      Rate : constant Float := (if L or R then 2.2 else 3.6);
   begin
      Key_Steer_2 := Key_Steer_2 + Clamp (Target - Key_Steer_2, -Rate * Cycle, Rate * Cycle);
      Key_Throttle_2 := Clamp (Key_Throttle_2 + (if T then 5.0 else -9.0) * Cycle, 0.0, 1.0);
      Key_Brake_2 := Clamp (Key_Brake_2 + (if B then 4.0 else -9.0) * Cycle, 0.0, 1.0);
      Session.Second_Hands :=
        (Steer => Key_Steer_2, Throttle => Key_Throttle_2, Brake => Key_Brake_2, others => <>);
      if Pad_Is_Second then
         declare
            P : constant Gamepad.Input := Gamepad.State;
            H : Vehicle.Inputs renames Session.Second_Hands;
         begin
            H.Steer := Clamp (H.Steer + From_Stick (P.Steer, V), -1.0, 1.0);
            H.Throttle := Float'Max (H.Throttle, P.Throttle);
            H.Brake := Float'Max (H.Brake, P.Brake);
            H.Handbrake := Gamepad.Held (Wheel.Square);
         end;
      end if;
   end Gather_Second;

   function Gather (Cycle : Float) return Vehicle.Inputs is
      I : Vehicle.Inputs;
      K : constant Keys := Shared.Get_Keys;
      W : constant Wheel.Input := Wheel.State;
      On : constant Boolean := Wheel.Present;
      V : constant Float := Vehicle.Speed (Session.Cars (1));
      --  On the keys: only as much lock as the tyres can use at this speed
      Lock_At : constant Float :=
        Clamp ((Arctan (0.12) + (Session.Spec.A + Session.Spec.B) * 9.81
                * Session.Spec.Mu * 0.9 / Float'Max (25.0, V * V))
               / Session.Spec.Steer_Lock, 0.05, 1.0);
      Target : constant Float :=
        (if K.Left then -Lock_At elsif K.Right then Lock_At else 0.0);
      Rate : constant Float := (if K.Left or K.Right then 2.2 else 3.6);
      Up, Down : Boolean;
   begin
      Key_Steer := Key_Steer + Clamp (Target - Key_Steer, -Rate * Cycle, Rate * Cycle);
      Key_Throttle := Clamp (Key_Throttle + (if K.Throttle then 5.0 else -9.0) * Cycle, 0.0, 1.0);
      Key_Brake := Clamp (Key_Brake + (if K.Brake then 4.0 else -9.0) * Cycle, 0.0, 1.0);
      Key_Clutch := Clamp (Key_Clutch + (if K.Clutch then 8.0 else -5.0) * Cycle, 0.0, 1.0);

      --  With two players and a wheel, the arrows belong to the second
      if Session.Config.Two_Players and then On then
         Key_Steer := 0.0;
         Key_Throttle := 0.0;
         Key_Brake := 0.0;
      end if;
      I.Steer := (if On then W.Steering else 0.0) + Key_Steer;
      I.Throttle := Float'Max ((if On then W.Throttle else 0.0), Key_Throttle);
      I.Brake := Float'Max ((if On then W.Brake else 0.0), Key_Brake);
      I.Clutch := Float'Max ((if On then W.Clutch else 0.0), Key_Clutch);
      I.Handbrake := K.Handbrake or else (On and then Wheel.Held (Wheel.L3));
      I.Lever := (if On then Integer (W.Shifter) else 0);
      --  The controller: the stick, the triggers, X for the handbrake (on a
      --  motorcycle the rear brake)
      if Gamepad.Present and then not Pad_Is_Second then
         declare
            P : constant Gamepad.Input := Gamepad.State;
         begin
            I.Steer := Clamp (I.Steer + From_Stick (P.Steer, V), -1.0, 1.0);
            I.Throttle := Float'Max (I.Throttle, P.Throttle);
            I.Brake := Float'Max (I.Brake, P.Brake);
            I.Handbrake := I.Handbrake or else Gamepad.Held (Wheel.Square);
         end;
      end if;
      Shared.Take_Shift (Up, Down);
      I.Shift_Up := Up;
      I.Shift_Down := Down;
      I.Reverse_Req := Shared.Get_Reverse;
      return I;
   end Gather;

   --  Online: what the other machine says, and what to tell it
   procedure Network_Step (Count : Natural) is
      R : Net.Car_State;
      Age : Float;
      Have : Boolean;
   begin
      Net.Latest (R, Age, Have);
      Session.Remote :=
        (X => R.X, Z => R.Z, Y => R.Y, Heading => R.Heading, Pitch => R.Pitch, Roll => R.Roll,
         Vx => R.Vx, Vy => R.Vy, Rate => R.Rate, Steer => R.Steer, Rpm => R.Rpm, Gear => R.Gear,
         Lap => R.Lap, Lap_Time => R.Lap_Time, S => R.S, Last_S => R.Last_S,
         Finish_Time => R.Finish_Time, Finished => R.Finished, On_Grid => R.On_Grid,
         Age => Age, Have => Have);
      --  Both there and driving: the lights may start
      if not Session.Online_Ready and then Have and then Net.Peer_Seen then
         Session.Online_Ready := True;
      end if;
      if Count mod 17 = 0 then
         declare
            C : Vehicle.Car renames Session.Cars (1);
            L : Session.Lap_Info renames Session.Laps (1);
         begin
            Net.Send_State
              ((X => Float (C.X), Z => Float (C.Z), Y => C.Y, Heading => C.Heading,
                Pitch => C.Pitch, Roll => C.Roll, Vx => C.Vx, Vy => C.Vy, Rate => C.Rate,
                Steer => C.Steer, Rpm => C.Rpm, Gear => C.Gear, Lap => L.Lap,
                Lap_Time => L.Lap_Time, S => L.S, Last_S => L.Last_S,
                Finish_Time => L.Finish_Time, Finished => L.Finished, On_Grid => L.On_Grid));
         end;
      end if;
      --  The host keeps giving the race and the start, for a guest still in its menu
      if Net.Current_Role = Net.Host and then Count mod 250 = 0 then
         Net.Send_Go (Track.Loaded, Session.Config.Laps);
      end if;
   end Network_Step;

   function Make_Frame (Tm : Long_Float; I : Vehicle.Inputs) return Frame is
      F : Frame;
   begin
      F.Time := Tm;
      F.Count := Session.Car_Count;
      for K in 1 .. Session.Car_Count loop
         declare
            C : Vehicle.Car renames Session.Cars (K);
            P : Car_Pose renames F.Poses (K);
         begin
            P.X := Float (C.X);
            P.Y := C.Y;
            P.Z := Float (C.Z);
            P.Heading := C.Heading;
            P.Pitch := C.Pitch;
            P.Roll := C.Roll;
            P.Steer := C.Steer;
            P.Speed := Vehicle.Speed (C);
            P.Rpm := C.Rpm;
            P.Gear := C.Gear;
            P.Fallen := C.Fallen_T;
            P.Rider_Gap := C.Rider_Gap;
            for W in Vehicle.Wheel_Id loop
               P.Wheel_Y (W) := C.Wheels (W).Off_Y;
               P.Wheel_Angle (W) := C.Wheels (W).Angle;
               P.Slide (W) := C.Wheels (W).Slide;
            end loop;
         end;
      end loop;
      declare
         C : Vehicle.Car renames Session.Cars (1);
      begin
         F.Poses (1).Brake := I.Brake;
         F.Speed := Vehicle.Speed (C);
         F.Rpm := C.Rpm;
         F.Throttle := I.Throttle;
         F.Brake := I.Brake;
         F.Clutch := I.Clutch;
         F.Steer_In := I.Steer;
         F.Ax := C.Ax;
         F.Ay := C.Ay;
         F.Gear := C.Gear;
         F.Abs_On := C.Abs_Active;
         F.Tc_On := C.Tc_Active;
         F.Grind := C.Grind;
         F.Impact := C.Impact;
         F.Scrape := C.Scrape;
         F.Load := C.Throttle_Eff;
         F.Red_Line := Session.Spec.Red_Line;
         F.School := School.Current;
         F.Tip := School.Tip;
         F.Tip_Len := School.Tip_Len;
         F.Tip_Serial := School.Tip_Serial;
         F.Fuel := C.Fuel;
         F.Uses_Fuel := Session.Config.Assist.Fuel_Use;
         F.Dmg_Aero := C.Dmg_Aero;
         F.Dmg_Engine := C.Dmg_Engine;
         F.Toe := C.Toe;
         F.Service_Left := Session.Service_Left;
         F.Service_Offer := Session.Service_Offer;
         F.Waiting_For_Peer := Session.Config.Online and then not Session.Online_Ready;
         F.In_Pit_Lane := Session.In_Pit_Lane;
         F.VSC_Left := Float'Max (0.0, Session.VSC_Until - Session.Time);
         F.Penalty := Session.Laps (1).Penalty;
         declare
            Here : constant Float := Track.Samples (C.Hint).S;
            Ahead : constant Float :=
              (if Session.Yellow_S >= Here then Session.Yellow_S - Here
               else Session.Yellow_S + Track.Length - Here);
         begin
            F.Yellow_Ahead := Session.Yellow_S >= 0.0 and then Ahead < 400.0;
         end;
         for W in Vehicle.Wheel_Id loop
            F.Temps (W) := C.Wheels (W).Temp;
            F.Slides (W) := C.Wheels (W).Slide;
            F.Wear (W) := C.Wheels (W).Wear;
            F.On_Kerb := F.On_Kerb or else C.Wheels (W).Surf = Track.Kerb;
            F.Off_Road := F.Off_Road or else C.Wheels (W).Surf in Track.Grass | Track.Gravel;
            F.On_Dirt := F.On_Dirt or else C.Wheels (W).Surf = Track.Dirt;
         end loop;
      end;
      F.Laps := Session.Laps;
      F.Lights := Session.Lights;
      F.Lights_Out := Session.Lights_Out;
      F.Race_Over := Session.Race_Over;
      F.New_Best := Session.New_Best;
      if Session.Config.Mode in Session.Hotlap | Session.Stage then
         F.Ghost := Session.Ghost_At (Session.Laps (1).Lap_Time);
      end if;
      return F;
   end Make_Frame;

   --  The controller's motors: the heavy one for knocks, kerbs and a fall,
   --  the light one for a sliding tyre and, on a motorcycle, the engine
   Pad_Jolt : Float := 0.0;

   procedure Pad_Rumble (Live : Boolean) is
      Who : constant Positive := (if Pad_Is_Second then 2 else 1);
   begin
      if not Live or else Who > Session.Car_Count then
         Gamepad.Rumble (0.0, 0.0);
         return;
      end if;
      declare
         C : Vehicle.Car renames Session.Cars (Who);
         Moving : constant Float := Clamp (Vehicle.Speed (C) / 10.0, 0.0, 1.0);
         Slide : Float := 0.0;
         Kerb : Boolean := False;
      begin
         for W in Vehicle.Wheel_Id loop
            Slide := Float'Max (Slide, C.Wheels (W).Slide);
            Kerb := Kerb or else C.Wheels (W).Surf = Track.Kerb;
         end loop;
         Pad_Jolt := Float'Max (Pad_Jolt * 0.85, Clamp (C.Impact / 12.0, 0.0, 1.0));
         Gamepad.Rumble
           (Strong => Float'Max (Pad_Jolt, (if Kerb then 0.35 * Moving else 0.0))
                      + (if C.Fallen_T > 0.0 and then C.Fallen_T < 0.6 then 0.8 else 0.0),
            Weak => 0.55 * Clamp (Slide * 1.5, 0.0, 1.0) * Moving
                    + (if Vehicle.Is_Bike (C.Kind)
                       then 0.10 * C.Throttle_Eff * C.Rpm / Session.Spec.Red_Line
                       else 0.0));
      end;
   end Pad_Rumble;

   task body Runner is
      Cycle : constant Time_Span := Milliseconds (2);
      Next : Time;
      Stepping : Boolean := False;
      Have_Wheel : Boolean := False;
      Count : Natural := 0;
      Spent : Time_Span := Time_Span_Zero;
   begin
      select
         accept Boot_Up (Use_Wheel : Boolean) do
            Have_Wheel := Use_Wheel;
         end Boot_Up;
      or
         terminate;
      end select;
      if Have_Wheel then
         Wheel.Open;
         Gamepad.Open;
      end if;
      Next := Clock;
      loop
         select
            accept Halt_Now do
               Stepping := False;
            end Halt_Now;
         or
            accept Resume_Now do
               Stepping := True;
               Next := Clock;
            end Resume_Now;
         or
            accept Stop;
            exit;
         else
            null;
         end select;

         declare
            T0 : constant Time := Clock;
         begin
            Count := Count + 1;
            if Have_Wheel then
               Wheel.Poll;
               declare
                  B : Wheel.Button;
               begin
                  while Wheel.Next_Press (B) loop
                     case B is
                        when Wheel.Paddle_Right => Shared.Shift (True);
                        when Wheel.Paddle_Left  => Shared.Shift (False);
                        when others => null;
                     end case;
                     Shared.Press (B);
                  end loop;
               end;
               Shared.Set_Wheel (Wheel.Present, Wheel.State.Steering);
               --  The controller's buttons: the same names; the bumpers shift,
               --  unless the second player has it (an automatic gearbox)
               Gamepad.Poll;
               declare
                  B : Wheel.Button;
               begin
                  while Gamepad.Next_Press (B) loop
                     --  X is held for the handbrake while driving, so a click
                     --  of the left stick puts the car back on the track
                     if not Shared.Is_Paused and then B = Wheel.L3 then
                        B := Wheel.Square;
                     elsif not Shared.Is_Paused and then B = Wheel.Square then
                        goto Next_Pad_Button;
                     end if;
                     case B is
                        --  (on the controller the left bumper shifts up)
                        when Wheel.Paddle_Left =>
                           if not Pad_Is_Second then
                              Shared.Shift (True);
                           end if;
                        when Wheel.Paddle_Right =>
                           if not Pad_Is_Second then
                              Shared.Shift (False);
                           end if;
                        when others => null;
                     end case;
                     if not Pad_Is_Second or else B in Wheel.Options | Wheel.PS then
                        Shared.Press (B);
                     end if;
                     <<Next_Pad_Button>>
                  end loop;
               end;
               declare
                  G : Float;
                  Changed : Boolean;
               begin
                  Shared.Take_Gain (G, Changed);
                  if Changed then
                     Wheel.Set_Gain (G);
                  end if;
               end;
            end if;

            if Stepping then
               declare
                  Restart_Req, Reset_Req : Boolean;
               begin
                  Shared.Take (Restart_Req, Reset_Req);
                  if Restart_Req then
                     Session.Restart;
                     School.Begin_Lesson (School.Current.Lesson);
                  end if;
                  if Reset_Req then
                     Session.Reset_Player;
                  end if;
               end;
               if not Shared.Is_Paused then
                  declare
                     I : Vehicle.Inputs := Gather (0.002);
                  begin
                     if Session.Config.Two_Players then
                        Gather_Second (0.002);
                     end if;
                     if Session.Config.Online then
                        Network_Step (Count);
                     end if;
                     Session.Step (I);
                     I.Shift_Up := False;
                     I.Shift_Down := False;
                     School.Step (I);
                     Session.Step (I);
                     School.Step (I);
                     Shared.Publish (Make_Frame (Now, I));
                     if Count mod 5 = 0 and then Session.Config.Mode /= Session.Demo then
                        Telemetry.Sample (I, Last_Force);
                     end if;
                  end;
               else
                  --  Time stands still: the picture keeps its last pose
                  declare
                     I : constant Vehicle.Inputs := (others => <>);
                  begin
                     Shared.Publish (Make_Frame (Now, I));
                  end;
               end if;
            end if;

            if Have_Wheel and then Gamepad.Present and then Count mod 8 = 0 then
               Pad_Rumble (Stepping and then not Shared.Is_Paused
                           and then Session.Config.Mode /= Session.Demo);
            end if;
            if Have_Wheel and then Wheel.Present and then Count mod 4 = 0 then
               Force_Feedback (Stepping and then not Shared.Is_Paused
                               and then Session.Config.Mode /= Session.Demo);
            end if;
            Spent := Spent + (Clock - T0);
            if Count mod 500 = 0 then
               Shared.Set_Load (Float (To_Duration (Spent)) / 1.0);
               Spent := Time_Span_Zero;
            end if;
         end;

         Next := Next + Cycle;
         if Clock - Next > Milliseconds (40) then
            Next := Clock;   --  fell behind: do not try to catch up
         end if;
         delay until Next;
      end loop;
      if Have_Wheel then
         Wheel.Shutdown;
         Gamepad.Rumble (0.0, 0.0);
         Gamepad.Close;
      end if;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Simulation stopped: " & Ada.Exceptions.Exception_Information (E));
         if Have_Wheel then
            Wheel.Shutdown;
         Gamepad.Rumble (0.0, 0.0);
         Gamepad.Close;
         end if;
   end Runner;

   procedure Set_Keys (K : Keys) is
   begin
      Shared.Put_Keys (K);
   end Set_Keys;

   procedure Request_Shift (Up : Boolean) is
   begin
      Shared.Shift (Up);
   end Request_Shift;

   procedure Request_Reverse (On : Boolean) is
   begin
      Shared.Set_Reverse (On);
   end Request_Reverse;

   procedure Boot (Use_Wheel : Boolean) is
   begin
      Runner.Boot_Up (Use_Wheel);
   end Boot;

   procedure Halt is
   begin
      Runner.Halt_Now;
      Telemetry.Write;
   end Halt;

   procedure Resume is
   begin
      Runner.Resume_Now;
   end Resume;

   procedure Pause (On : Boolean) is
   begin
      Shared.Set_Pause (On);
   end Pause;

   function Paused return Boolean is (Shared.Is_Paused);

   procedure Restart is
   begin
      Shared.Ask (True, False);
   end Restart;

   procedure Reset_Car is
   begin
      Shared.Ask (False, True);
   end Reset_Car;

   procedure Set_FFB (Gain : Float) is
   begin
      Shared.Set_Gain (Gain);
   end Set_FFB;

   procedure Shutdown is
   begin
      if Runner'Callable then
         Runner.Stop;
      end if;
      Telemetry.Write;
   end Shutdown;

   procedure Latest (Prev, Cur : out Frame) is
   begin
      Shared.Read (Prev, Cur);
   end Latest;

   function Wheel_Present return Boolean is (Shared.Wheel_On);

   function Next_Button (B : out Wheel.Button) return Boolean is
      Got : Boolean;
   begin
      Shared.Next (B, Got);
      return Got;
   end Next_Button;

   function Pad_Steer return Float is (Shared.Wheel_Pos);

   function Physics_Load return Float is (Shared.Get_Load);

end Sim_Loop;
