with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Session; with Track; with Vehicle; use Vehicle;
procedure Trace is
   package F is new Float_IO (Float);
   procedure P (V : Float) is begin F.Put (V, Fore => 6, Aft => 2, Exp => 0); end P;
   S : Session.Settings;
   N : Vehicle.Inputs;
   T : constant Track.Track_Id := Track.Track_Id'Value (Ada.Command_Line.Argument (1));
   Dur : constant Integer := Integer'Value (Ada.Command_Line.Argument (2));
   Every : constant Integer := Integer'Value (Ada.Command_Line.Argument (3));
begin
   S.Mode := Session.Demo; S.Opponents := 0; S.AI_Skill := 1.0;
   Track.Load (T); Session.Start (S);
   Put_Line ("     t      s      D  lineD     v  lineV    vy   rate  steer  ax ay  impact wall_r wall_l");
   for I in 1 .. Dur loop
      Session.Step (N);
      if I mod Every = 0 then
         declare
            C : Car renames Session.Cars (1);
            Ix : Natural; Tt, D : Float; H : Natural := C.Hint;
         begin
            Track.Locate (Float (C.X), Float (C.Z), H, Ix, Tt, D);
            P (Float (I) / 1000.0); P (Track.Samples (Ix).S); P (D); P (Track.Samples (Ix).Line_D);
            P (C.Vx); P (Track.Samples (Ix).Line_V); P (C.Vy); P (C.Rate); P (C.Steer);
            P (C.Ax); P (C.Ay); P (C.Impact); P (Track.Samples (Ix).Wall_R); P (Track.Samples (Ix).Wall_L); Put (C.Gear'Image);
            P (C.Wheels (1).Slide); P (C.Wheels (3).Slide);
            New_Line;
         end;
      end if;
   end loop;
end Trace;
