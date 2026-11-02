--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Calendar;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.Sockets;

package body Net is

   use GNAT.Sockets;
   use Ada.Streams;

   Magic : constant String := "ADARACE1";

   --  Lines of words: "ADARACE1 STATE x z ...", "ADARACE1 GO track laps", "ADARACE1 HELLO"

   function Img (F : Float) return String is
      S : constant String := Long_Float'Image (Long_Float (F));
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Img;

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Both));

   function Encode (S : Car_State) return String is
     (Magic & " STATE " & Img (S.X) & " " & Img (S.Z) & " " & Img (S.Y) & " " & Img (S.Heading)
      & " " & Img (S.Pitch) & " " & Img (S.Roll) & " " & Img (S.Vx) & " " & Img (S.Vy)
      & " " & Img (S.Rate) & " " & Img (S.Steer) & " " & Img (S.Rpm) & " " & Img (S.Gear)
      & " " & Img (S.Lap) & " " & Img (S.Lap_Time) & " " & Img (S.S) & " " & Img (S.Last_S)
      & " " & Img (S.Finish_Time) & " " & (if S.Finished then "1" else "0")
      & " " & (if S.On_Grid then "1" else "0"));

   type Word_List is array (1 .. 24) of Natural;

   --  Split on spaces: start and end of each word
   procedure Words (Line : String; Starts, Ends : out Word_List; Count : out Natural) is
      I : Natural := Line'First;
   begin
      Count := 0;
      Starts := (others => 0);
      Ends := (others => 0);
      while I <= Line'Last and then Count < Word_List'Last loop
         if Line (I) = ' ' then
            I := I + 1;
         else
            Count := Count + 1;
            Starts (Count) := I;
            while I <= Line'Last and then Line (I) /= ' ' loop
               I := I + 1;
            end loop;
            Ends (Count) := I - 1;
         end if;
      end loop;
   end Words;

   procedure Decode (Line : String; S : out Car_State; Good : out Boolean) is
      St, En : Word_List;
      N : Natural;
      function W (K : Positive) return String is (Line (St (K) .. En (K)));
      function F (K : Positive) return Float is (Float (Long_Float'Value (W (K))));
   begin
      S := (others => <>);
      Words (Line, St, En, N);
      Good := N = 21 and then W (1) = Magic and then W (2) = "STATE";
      if not Good then
         return;
      end if;
      S := (X => F (3), Z => F (4), Y => F (5), Heading => F (6), Pitch => F (7), Roll => F (8),
            Vx => F (9), Vy => F (10), Rate => F (11), Steer => F (12), Rpm => F (13),
            Gear => Integer'Value (W (14)), Lap => Natural'Value (W (15)),
            Lap_Time => F (16), S => F (17), Last_S => F (18), Finish_Time => F (19),
            Finished => W (20) = "1", On_Grid => W (21) = "1");
   exception
      when others =>
         Good := False;
   end Decode;

   --  What has been heard, between the receiving task and the rest
   protected Heard is
      procedure Put_State (S : Car_State);
      procedure Put_Go (T, L : Natural);
      procedure Seen;
      procedure Get (S : out Car_State; Age : out Float; Have : out Boolean);
      function Recent return Boolean;
      procedure Go (T, L : out Natural; Got : out Boolean);
      function Count return Natural;
      procedure Clear;
   private
      Last : Car_State;
      Have_State : Boolean := False;
      At_Time : Ada.Calendar.Time := Ada.Calendar.Clock;
      Seen_At : Ada.Calendar.Time := Ada.Calendar.Clock;
      Any : Boolean := False;
      Go_T, Go_L : Natural := 0;
      Go_Got : Boolean := False;
      N : Natural := 0;
   end Heard;

   protected body Heard is
      procedure Put_State (S : Car_State) is
      begin
         Last := S;
         Have_State := True;
         At_Time := Ada.Calendar.Clock;
      end Put_State;
      procedure Put_Go (T, L : Natural) is
      begin
         Go_T := T;
         Go_L := L;
         Go_Got := True;
      end Put_Go;
      procedure Seen is
      begin
         Seen_At := Ada.Calendar.Clock;
         Any := True;
         N := N + 1;
      end Seen;
      procedure Get (S : out Car_State; Age : out Float; Have : out Boolean) is
         use type Ada.Calendar.Time;
      begin
         S := Last;
         Have := Have_State;
         Age := Float (Ada.Calendar.Clock - At_Time);
      end Get;
      function Recent return Boolean is
         use type Ada.Calendar.Time;
      begin
         return Any and then Ada.Calendar.Clock - Seen_At < 2.0;
      end Recent;
      procedure Go (T, L : out Natural; Got : out Boolean) is
      begin
         T := Go_T;
         L := Go_L;
         Got := Go_Got;
      end Go;
      function Count return Natural is (N);
      procedure Clear is
      begin
         Have_State := False;
         Any := False;
         Go_Got := False;
         N := 0;
      end Clear;
   end Heard;

   Sock : Socket_Type := No_Socket;
   Peer_Addr : Sock_Addr_Type;
   Know_Peer : Boolean := False with Atomic;
   Me : Role := Off;

   protected Peer_Lock is
      procedure Set (A : Sock_Addr_Type);
      function Get return Sock_Addr_Type;
   private
      Addr : Sock_Addr_Type;
   end Peer_Lock;

   protected body Peer_Lock is
      procedure Set (A : Sock_Addr_Type) is
      begin
         Addr := A;
      end Set;
      function Get return Sock_Addr_Type is (Addr);
   end Peer_Lock;

   task Listener is
      entry Start;
   end Listener;

   task body Listener is
      Buffer : Stream_Element_Array (1 .. 1500);
      Last : Stream_Element_Offset;
      From : Sock_Addr_Type;
   begin
      select
         accept Start;
      or
         terminate;
      end select;
      loop
         exit when Me = Off;
         begin
            Receive_Socket (Sock, Buffer, Last, From);
            declare
               Line : String (1 .. Natural (Last));
               for Line'Address use Buffer'Address;
               St, En : Word_List;
               N : Natural;
            begin
               Words (Line, St, En, N);
               if N >= 2 and then Line (St (1) .. En (1)) = Magic then
                  Heard.Seen;
                  --  The host learns who the guest is from what it sends
                  if Me = Host then
                     Peer_Lock.Set (From);
                     Know_Peer := True;
                  end if;
                  declare
                     Kind : constant String := Line (St (2) .. En (2));
                  begin
                     if Kind = "STATE" then
                        declare
                           S : Car_State;
                           Good : Boolean;
                        begin
                           Decode (Line, S, Good);
                           if Good then
                              Heard.Put_State (S);
                           end if;
                        end;
                     elsif Kind = "GO" and then N = 4 then
                        Heard.Put_Go (Natural'Value (Line (St (3) .. En (3))),
                                      Natural'Value (Line (St (4) .. En (4))));
                     end if;
                  end;
               end if;
            end;
         exception
            when Socket_Error =>
               null;   --  the timeout: look again whether to stop
            when others =>
               null;   --  a bad packet is no reason to stop listening
         end;
      end loop;
   end Listener;

   Started : Boolean := False;

   procedure Open (As : Role; Peer : String := ""; Port : Natural := Default_Port) is
   begin
      Close;
      Heard.Clear;
      Create_Socket (Sock, Family_Inet, Socket_Datagram);
      Set_Socket_Option (Sock, Socket_Level, (Reuse_Address, True));
      Set_Socket_Option (Sock, Socket_Level, (Receive_Timeout, 0.2));
      if As = Host then
         Bind_Socket (Sock, (Family_Inet, Any_Inet_Addr, Port_Type (Port)));
         Know_Peer := False;
      else
         Bind_Socket (Sock, (Family_Inet, Any_Inet_Addr, 0));
         Peer_Lock.Set ((Family_Inet, Addresses (Get_Host_By_Name (Peer)), Port_Type (Port)));
         Know_Peer := True;
      end if;
      Me := As;
      if not Started then
         Started := True;
         Listener.Start;
      end if;
   exception
      when others =>
         Ada.Text_IO.Put_Line ("Network: cannot open " & (if Peer = "" then "the port" else Peer));
         Me := Off;
   end Open;

   procedure Close is
   begin
      if Me /= Off then
         Me := Off;
         Close_Socket (Sock);
      end if;
   exception
      when others => null;
   end Close;

   function Current_Role return Role is (Me);

   procedure Send (Line : String) is
      Data : Stream_Element_Array (1 .. Stream_Element_Offset (Line'Length));
      for Data'Address use Line'Address;
      Last : Stream_Element_Offset;
   begin
      if Me /= Off and then Know_Peer then
         Send_Socket (Sock, Data, Last, Peer_Lock.Get);
      end if;
   exception
      when others => null;   --  a lost packet is the network's business
   end Send;

   procedure Send_State (S : Car_State) is
   begin
      Send (Encode (S));
   end Send_State;

   procedure Send_Go (Track, Laps : Natural) is
   begin
      Send (Magic & " GO " & Img (Track) & " " & Img (Laps));
   end Send_Go;

   procedure Send_Hello is
   begin
      Send (Magic & " HELLO");
   end Send_Hello;

   function Peer_Seen return Boolean is (Heard.Recent);

   function Go_Received (Track, Laps : out Natural) return Boolean is
      Got : Boolean;
   begin
      Heard.Go (Track, Laps, Got);
      return Got;
   end Go_Received;

   procedure Latest (S : out Car_State; Age : out Float; Have : out Boolean) is
   begin
      Heard.Get (S, Age, Have);
   end Latest;

   function Packets return Natural is (Heard.Count);

end Net;
