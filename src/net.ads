--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Racing another machine on the home network: each drives its own car and
--  sends where it is, thirty times a second, over UDP; the other car is drawn
--  where its last word says, carried on by its speed.  The host chooses the
--  circuit and the laps and gives the start.

package Net is

   Default_Port : constant := 41_000;

   type Role is (Off, Host, Guest);

   type Car_State is record
      X, Z, Y, Heading, Pitch, Roll : Float := 0.0;
      Vx, Vy, Rate, Steer, Rpm : Float := 0.0;
      Gear : Integer := 0;
      Lap : Natural := 0;
      Lap_Time, S, Last_S, Finish_Time : Float := 0.0;
      Finished, On_Grid : Boolean := False;
   end record;

   procedure Open (As : Role; Peer : String := ""; Port : Natural := Default_Port);
   --  Host: listen on Port.  Guest: Peer is the host's address
   procedure Close;

   function Current_Role return Role;

   procedure Send_State (S : Car_State);
   procedure Send_Go (Track, Laps : Natural);
   procedure Send_Hello;
   --  Guest: here I am (until the host gives the start)
   --  Host: the race, and the word to start (sent until the guest drives)

   function Peer_Seen return Boolean;
   --  Something heard from the other machine in the last two seconds

   function Go_Received (Track, Laps : out Natural) return Boolean;
   --  Guest: the host has said which race, and to start

   procedure Latest (S : out Car_State; Age : out Float; Have : out Boolean);
   --  The other car as last heard, and how many seconds ago

   function Packets return Natural;
   --  Heard so far (for the checks)

   --  The wire format, for the tests
   function Encode (S : Car_State) return String;
   procedure Decode (Line : String; S : out Car_State; Good : out Boolean);

end Net;
