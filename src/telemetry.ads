--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  What the player's car did, 100 times a second, kept in memory while
--  driving (no disk in the real-time loop) and written as CSV when the drive
--  ends, to ~/.local/share/adarace/telemetry.  The newest files are kept.

with Vehicle;

package Telemetry is

   procedure Sample (I : Vehicle.Inputs; Force : Float);
   --  From the simulation task, 100 times a second, of the player's car

   procedure Write;
   --  The simulation must not be stepping.  Writes what was gathered, unless
   --  it is under ten seconds, and starts afresh.

   function Last_File return String;
   --  The file written last ("" if none)

end Telemetry;
