--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The co-driver reads the pace notes out in time to act on them.  What to
--  say and when, in words: the sound of them is the mixer's business.

package Codriver is

   type Word is (Left, Right, One, Two, Three, Four, Five, Six, Long, Hairpin,
                 Over, Crest, Into, Finish);

   function File_Name (W : Word) return String;

   procedure Reset;
   --  At the start of a stage

   procedure Update (S, Speed, Stage_Left : Float);
   --  Where the car is (metres along the stage), and how fast

   procedure Next_Word (W : out Word; Got : out Boolean);
   --  The words due, in order

   function Lead_Metres (Speed : Float) return Float;
   --  How long before a corner it is called

end Codriver;
