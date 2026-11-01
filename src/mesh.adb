--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Unchecked_Deallocation;
with Interfaces.C;
with System.Storage_Elements;

package body Mesh is

   use GL;
   use Math3D;
   use type Interfaces.C.int;
   use type Interfaces.C.ptrdiff_t;

   procedure Free is new Ada.Unchecked_Deallocation (Vertex_Array, Vertex_Access);

   procedure Add (B : in out Builder; V : Vertex) is
   begin
      if B.Data = null then
         B.Data := new Vertex_Array (0 .. 65_535);
      elsif B.Used > B.Data'Last then
         declare
            N : constant Vertex_Access := new Vertex_Array (0 .. 2 * B.Data'Length - 1);
         begin
            N (0 .. B.Used - 1) := B.Data (0 .. B.Used - 1);
            Free (B.Data);
            B.Data := N;
         end;
      end if;
      B.Data (B.Used) := V;
      B.Used := B.Used + 1;
   end Add;

   procedure Tri (B : in out Builder; A, C, D : Vec3; Col : Color; Mat : Float := Plain) is
      N : constant Vec3 := Normalize (Cross (C - A, D - A));
   begin
      Add (B, (A, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
      Add (B, (C, N, Col.R, Col.G, Col.B, Mat, 1.0, 0.0));
      Add (B, (D, N, Col.R, Col.G, Col.B, Mat, 1.0, 1.0));
   end Tri;

   procedure Quad (B : in out Builder; A, C, D, E : Vec3; Col : Color; Mat : Float := Plain) is
      N : constant Vec3 := Normalize (Cross (C - A, D - A));
      Lu : constant Float := Length (C - A);
      Lv : constant Float := Length (E - A);
   begin
      Add (B, (A, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
      Add (B, (C, N, Col.R, Col.G, Col.B, Mat, Lu, 0.0));
      Add (B, (D, N, Col.R, Col.G, Col.B, Mat, Lu, Lv));
      Add (B, (A, N, Col.R, Col.G, Col.B, Mat, 0.0, 0.0));
      Add (B, (D, N, Col.R, Col.G, Col.B, Mat, Lu, Lv));
      Add (B, (E, N, Col.R, Col.G, Col.B, Mat, 0.0, Lv));
   end Quad;

   procedure Box (B : in out Builder; Lo, Hi : Vec3; Col : Color; Mat : Float := Plain) is
      P000 : constant Vec3 := (Lo.X, Lo.Y, Lo.Z);
      P100 : constant Vec3 := (Hi.X, Lo.Y, Lo.Z);
      P010 : constant Vec3 := (Lo.X, Hi.Y, Lo.Z);
      P110 : constant Vec3 := (Hi.X, Hi.Y, Lo.Z);
      P001 : constant Vec3 := (Lo.X, Lo.Y, Hi.Z);
      P101 : constant Vec3 := (Hi.X, Lo.Y, Hi.Z);
      P011 : constant Vec3 := (Lo.X, Hi.Y, Hi.Z);
      P111 : constant Vec3 := (Hi.X, Hi.Y, Hi.Z);
   begin
      Quad (B, P001, P101, P111, P011, Col, Mat);   --  +Z
      Quad (B, P100, P000, P010, P110, Col, Mat);   --  -Z
      Quad (B, P101, P100, P110, P111, Col, Mat);   --  +X
      Quad (B, P000, P001, P011, P010, Col, Mat);   --  -X
      Quad (B, P011, P111, P110, P010, Col, Mat);   --  +Y
      Quad (B, P000, P100, P101, P001, Col, Mat);   --  -Y
   end Box;

   procedure Oriented_Box
     (B : in out Builder; Centre, Along, Up : Vec3; L, H, W : Float;
      Col : Color; Mat : Float := Plain)
   is
      X : constant Vec3 := Normalize (Along);
      Z : constant Vec3 := Normalize (Cross (X, Up));
      Y : constant Vec3 := Normalize (Cross (Z, X));
      function P (SX, SY, SZ : Float) return Vec3 is
        (Centre + (SX * L) * X + (SY * H) * Y + (SZ * W) * Z);
   begin
      Quad (B, P (-1.0, -1.0, 1.0), P (1.0, -1.0, 1.0), P (1.0, 1.0, 1.0), P (-1.0, 1.0, 1.0), Col, Mat);
      Quad (B, P (1.0, -1.0, -1.0), P (-1.0, -1.0, -1.0), P (-1.0, 1.0, -1.0), P (1.0, 1.0, -1.0), Col, Mat);
      Quad (B, P (1.0, -1.0, 1.0), P (1.0, -1.0, -1.0), P (1.0, 1.0, -1.0), P (1.0, 1.0, 1.0), Col, Mat);
      Quad (B, P (-1.0, -1.0, -1.0), P (-1.0, -1.0, 1.0), P (-1.0, 1.0, 1.0), P (-1.0, 1.0, -1.0), Col, Mat);
      Quad (B, P (-1.0, 1.0, 1.0), P (1.0, 1.0, 1.0), P (1.0, 1.0, -1.0), P (-1.0, 1.0, -1.0), Col, Mat);
      Quad (B, P (-1.0, -1.0, -1.0), P (1.0, -1.0, -1.0), P (1.0, -1.0, 1.0), P (-1.0, -1.0, 1.0), Col, Mat);
   end Oriented_Box;

   function Upload (B : in out Builder) return GPU is
      use System.Storage_Elements;
      M : GPU;
      Size : constant GLsizei := Vertex'Size / 8;
   begin
      glGenVertexArrays (1, M.VAO'Address);
      glGenBuffers (1, M.VBO'Address);
      glBindVertexArray (M.VAO);
      glBindBuffer (GL_ARRAY_BUFFER, M.VBO);
      if B.Used > 0 then
         glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (B.Used) * GLsizeiptr (Size),
                       B.Data (0)'Address, GL_STATIC_DRAW);
      end if;
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, Size, To_Address (0));
      glEnableVertexAttribArray (1);
      glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, Size, To_Address (12));
      glEnableVertexAttribArray (2);
      glVertexAttribPointer (2, 3, GL_FLOAT, GL_FALSE, Size, To_Address (24));
      glEnableVertexAttribArray (3);
      glVertexAttribPointer (3, 3, GL_FLOAT, GL_FALSE, Size, To_Address (36));
      glBindVertexArray (0);
      M.Count := GLsizei (B.Used);
      if B.Data /= null then
         Free (B.Data);
      end if;
      B.Used := 0;
      return M;
   end Upload;

   procedure Draw (M : GPU) is
   begin
      if M.Count > 0 then
         glBindVertexArray (M.VAO);
         glDrawArrays (GL_TRIANGLES, 0, M.Count);
      end if;
   end Draw;

   procedure Delete (M : in out GPU) is
      use type Interfaces.C.unsigned;
   begin
      if M.VAO /= 0 then
         glDeleteBuffers (1, M.VBO'Address);
         glDeleteVertexArrays (1, M.VAO'Address);
      end if;
      M.VAO := 0;
      M.VBO := 0;
      M.Count := 0;
   end Delete;

end Mesh;
