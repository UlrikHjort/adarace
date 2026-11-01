--  Reads the wheel for some seconds and prints what it says.  No force is
--  ever applied: safe to run with nobody holding the wheel.
with Ada.Text_IO; use Ada.Text_IO;
with Wheel;
procedure Wheelprobe is
   use type Wheel.Gear_Position;
   Min_S, Max_S : Float := 0.0;
begin
   Wheel.Open;
   Put_Line ("present: " & Wheel.Present'Image & "  force effect accepted: " & Wheel.Force_Ready'Image);
   for I in 1 .. 300 loop
      Wheel.Poll;
      Min_S := Float'Min (Min_S, Wheel.State.Steering);
      Max_S := Float'Max (Max_S, Wheel.State.Steering);
      if I mod 100 = 1 then
         Put_Line ("steer" & Wheel.State.Steering'Image & " throttle" & Wheel.State.Throttle'Image
                   & " brake" & Wheel.State.Brake'Image & " clutch" & Wheel.State.Clutch'Image
                   & " lever" & Wheel.State.Shifter'Image);
      end if;
      delay 0.01;
   end loop;
   Wheel.Shutdown;
   Put_Line ("closed, autocentre restored");
end Wheelprobe;
