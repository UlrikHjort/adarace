--  AdaRace: a driving simulator in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;
with Interfaces.C;
with System;
with System.Storage_Elements;

with Car_Model;
with GL;
with Math3D;
with Mesh;
with Scenery;
with Session;
with Shaders;
with Textures;
with Track;
with Vehicle;

package body Renderer is

   use Ada.Numerics.Elementary_Functions;
   use GL;
   use Math3D;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.ptrdiff_t;

   Pi : constant := 3.14159_26535;

   function Clamp (V, Lo, Hi : Float) return Float is
     (Float'Max (Lo, Float'Min (Hi, V)));

   Shadow_Size : constant := 4096;
   Near_Half   : constant := 70.0;
   Far_Half    : constant := 550.0;
   Mirror_W    : constant := 640;
   Mirror_H    : constant := 160;

   --  Programs -----------------------------------------------------------------

   World_P, Shadow_P, Sky_P, Post_P, Fx_P : GLuint := 0;

   U_VP, U_Model, U_Cam, U_Sun, U_Sun_C, U_Sky_C, U_Hor, U_Fog, U_Paint, U_Brake,
   U_Alpha, U_Shad, U_SN, U_SF, U_MN, U_MF : GLint := 0;
   S_LVP, S_Model : GLint := 0;
   K_Inv, K_Cam, K_Sun, K_Sun_C, K_Sky_C, K_Hor, K_Time, K_Clouds : GLint := 0;
   P_Rect, P_Flip, P_Scene, P_Vig, P_Exp : GLint := 0;
   U_Grain, U_Forest, P_Bloom : GLint := -1;
   U_Wet, U_Snow, U_Season, U_Car_V, U_Head_On, U_Head_N, U_Head_Pow : GLint := -1;
   U_Head_Pos, U_Head_Dir : array (1 .. Session.Max_Cars) of GLint := (others => -1);
   K_Mist, P_Rain, P_Time : GLint := -1;
   Guide_On : Boolean := False;
   U_Dirt, U_Dent, U_Dial_Rpm, U_Dial_Speed, U_Dial_Gear : GLint := -1;
   Dirt_Level : Float := 0.0;     --  how filthy the player's car has got
   Dent_Level : Float := 0.0;
   Clock_T : Float := 0.0;
   Car_Speed : Float := 0.0;
   Lights_On : Boolean := False;
   --  What falls from the sky, in a box that goes with the eye
   Fall_Max : constant := 1400;
   Fall_VAO, Fall_VBO : aliased GLuint := 0;
   Fall_Eye : Vec3 := (0.0, 0.0, 0.0);
   Fall_Right : Vec3 := (1.0, 0.0, 0.0);
   F_VP, F_Scale, F_Points : GLint := 0;

   --  Frame buffers -----------------------------------------------------------

   Scene_FB, Resolve_FB, Mirror_FB : aliased GLuint := 0;
   Scene_Color, Scene_Depth, Mirror_Depth : aliased GLuint := 0;
   Resolve_Tex, Mirror_Tex : aliased GLuint := 0;
   Shadow_FB : array (1 .. 2) of aliased GLuint := (0, 0);
   Shadow_Tex : array (1 .. 2) of aliased GLuint := (0, 0);
   FB_W, FB_H : Natural := 0;
   Empty_VAO : aliased GLuint := 0;

   --  Effects: skid marks and smoke -------------------------------------------

   type Fx_Vertex is record
      X, Y, Z : Float;
      R, G, B, A : Float;
      Size : Float;
   end record
     with Convention => C;

   Skid_Max : constant := 60_000;
   Skid_VAO, Skid_VBO : aliased GLuint := 0;
   Skid_Next : Natural := 0;
   Skid_Used : Natural := 0;
   type Skid_Point is record
      Valid : Boolean := False;
      LX, LY, LZ, RX, RY, RZ : Float := 0.0;
   end record;
   Skid_Last : array (Session.Car_Index, Vehicle.Wheel_Id) of Skid_Point;

   Smoke_Max : constant := 700;
   type Particle is record
      X, Y, Z, VX, VY, VZ, Age, Life, Size : Float := 0.0;
   end record;
   Smoke : array (1 .. Smoke_Max) of Particle;
   Smoke_Cursor : Natural := 0;
   Smoke_VAO, Smoke_VBO : aliased GLuint := 0;
   Dice : Ada.Numerics.Float_Random.Generator;

   --  The far shadow map is only redrawn when the car has moved on
   Far_Valid : Boolean := False;
   Far_Matrix : Mat4 := Identity;
   Far_X, Far_Z : Float := 0.0;

   --  Camera ------------------------------------------------------------------

   Chase_Heading : Float := 0.0;
   Head_X, Head_Y, Head_Z : Float := 0.0;  --  the head moves with the g forces
   Last_Lat, Last_Lon : Float := 0.0;

   Paints : constant array (Session.Car_Index) of Vec3 :=
     ((0.0, 0.0, 0.0),
      (0.02, 0.10, 0.45),
      (0.85, 0.42, 0.02),
      (0.02, 0.30, 0.10),
      (0.75, 0.75, 0.72),
      (0.03, 0.03, 0.035),
      (0.50, 0.02, 0.30),
      (0.75, 0.62, 0.03));

   procedure Build_Shadow (I : Positive) is
      Border : aliased constant GLfloat_Array (0 .. 3) := (others => 1.0);
   begin
      glGenFramebuffers (1, Shadow_FB (I)'Address);
      glGenTextures (1, Shadow_Tex (I)'Address);
      glBindTexture (GL_TEXTURE_2D, Shadow_Tex (I));
      glTexImage2D (GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT32F, Shadow_Size, Shadow_Size, 0,
                    GL_DEPTH_COMPONENT, GL_FLOAT, System.Null_Address);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
      glTexParameterfv (GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, Border'Address);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
      glBindFramebuffer (GL_FRAMEBUFFER, Shadow_FB (I));
      glFramebufferTexture2D (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, Shadow_Tex (I), 0);
      glDrawBuffer (GL_NONE);
      glReadBuffer (GL_NONE);
   end Build_Shadow;

   procedure Color_Texture (T : in out GLuint; W, H : Natural) is
   begin
      glBindTexture (GL_TEXTURE_2D, T);
      glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA16F, GLsizei (W), GLsizei (H), 0,
                    GL_RGBA, GL_HALF_FLOAT, System.Null_Address);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
   end Color_Texture;

   procedure Resize (W, H : Natural) is
   begin
      if W = FB_W and then H = FB_H then
         return;
      end if;
      FB_W := W;
      FB_H := H;
      glBindRenderbuffer (GL_RENDERBUFFER, Scene_Color);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, 4, GL_RGBA16F, GLsizei (W), GLsizei (H));
      glBindRenderbuffer (GL_RENDERBUFFER, Scene_Depth);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, 4, GL_DEPTH_COMPONENT32F, GLsizei (W), GLsizei (H));
      Color_Texture (Resolve_Tex, W, H);
   end Resize;

   procedure Attribs_Fx (VAO, VBO : GLuint; Bytes : Natural) is
      use System.Storage_Elements;
      Stride : constant GLsizei := Fx_Vertex'Size / 8;
   begin
      glBindVertexArray (VAO);
      glBindBuffer (GL_ARRAY_BUFFER, VBO);
      glBufferData (GL_ARRAY_BUFFER, GLsizeiptr (Bytes), System.Null_Address, GL_DYNAMIC_DRAW);
      glEnableVertexAttribArray (0);
      glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, Stride, To_Address (0));
      glEnableVertexAttribArray (1);
      glVertexAttribPointer (1, 4, GL_FLOAT, GL_FALSE, Stride, To_Address (12));
      glEnableVertexAttribArray (2);
      glVertexAttribPointer (2, 1, GL_FLOAT, GL_FALSE, Stride, To_Address (28));
      glBindVertexArray (0);
   end Attribs_Fx;

   procedure Create is
      use Shaders;
   begin
      World_P := Load_Program ("shaders/world.vert", "shaders/world.frag");
      Shadow_P := Load_Program ("shaders/shadow.vert", "shaders/shadow.frag");
      Sky_P := Load_Program ("shaders/sky.vert", "shaders/sky.frag");
      Post_P := Load_Program ("shaders/post.vert", "shaders/post.frag");
      Fx_P := Load_Program ("shaders/fx.vert", "shaders/fx.frag");
      U_VP := Location (World_P, "uViewProj");
      U_Model := Location (World_P, "uModel");
      U_Cam := Location (World_P, "uCamPos");
      U_Sun := Location (World_P, "uSunDir");
      U_Sun_C := Location (World_P, "uSunColor");
      U_Sky_C := Location (World_P, "uSkyColor");
      U_Hor := Location (World_P, "uHorizon");
      U_Fog := Location (World_P, "uFog");
      U_Paint := Location (World_P, "uPaint");
      U_Brake := Location (World_P, "uBrake");
      U_Alpha := Location (World_P, "uAlpha");
      U_Shad := Location (World_P, "uShadows");
      U_SN := Location (World_P, "uShadowNear");
      U_SF := Location (World_P, "uShadowFar");
      U_MN := Location (World_P, "uShadowMapNear");
      U_MF := Location (World_P, "uShadowMapFar");
      S_LVP := Location (Shadow_P, "uLightViewProj");
      S_Model := Location (Shadow_P, "uModel");
      K_Inv := Location (Sky_P, "uInvViewProj");
      K_Cam := Location (Sky_P, "uCamPos");
      K_Sun := Location (Sky_P, "uSunDir");
      K_Sun_C := Location (Sky_P, "uSunColor");
      K_Sky_C := Location (Sky_P, "uSkyColor");
      K_Hor := Location (Sky_P, "uHorizon");
      K_Time := Location (Sky_P, "uTime");
      K_Clouds := Location (Sky_P, "uClouds");
      P_Rect := Location (Post_P, "uRect");
      P_Flip := Location (Post_P, "uFlip");
      P_Scene := Location (Post_P, "uScene");
      P_Vig := Location (Post_P, "uVignette");
      P_Exp := Location (Post_P, "uExposure");
      F_VP := Location (Fx_P, "uViewProj");
      F_Scale := Location (Fx_P, "uPointScale");
      F_Points := Location (Fx_P, "uPoints");

      U_Dirt := Location (World_P, "uDirt");
      U_Dent := Location (World_P, "uDent");
      U_Dial_Rpm := Location (World_P, "uDialRpm");
      U_Dial_Speed := Location (World_P, "uDialSpeed");
      U_Dial_Gear := Location (World_P, "uDialGear");
      U_Wet := Location (World_P, "uWet");
      U_Snow := Location (World_P, "uSnow");
      U_Season := Location (World_P, "uSeason");
      U_Car_V := Location (World_P, "uCarV");
      U_Head_On := Location (World_P, "uHeadOn");
      U_Head_N := Location (World_P, "uHeadN");
      U_Head_Pow := Location (World_P, "uHeadPower");
      for I in U_Head_Pos'Range loop
         declare
            N : constant String := Integer'Image (I - 1);
            Idx : constant String := N (N'First + 1 .. N'Last);
         begin
            U_Head_Pos (I) := Location (World_P, "uHeadPos[" & Idx & "]");
            U_Head_Dir (I) := Location (World_P, "uHeadDir[" & Idx & "]");
         end;
      end loop;
      K_Mist := Location (Sky_P, "uMist");
      P_Rain := Location (Post_P, "uRain");
      P_Time := Location (Post_P, "uTime");
      U_Grain := Location (World_P, "uGrain");
      U_Forest := Location (World_P, "uForest");
      P_Bloom := Location (Post_P, "uBloom");
      Textures.Create;
      glUseProgram (World_P);
      Shaders.Set (Location (World_P, "uAsphalt"), Integer'(Textures.Unit_Asphalt));
      Shaders.Set (Location (World_P, "uGrass"), Integer'(Textures.Unit_Grass));
      Shaders.Set (Location (World_P, "uGravel"), Integer'(Textures.Unit_Gravel));
      Shaders.Set (Location (World_P, "uLeaves"), Integer'(Textures.Unit_Leaves));
      Shaders.Set (Location (World_P, "uNeedles"), Integer'(Textures.Unit_Needles));
      glUseProgram (Shadow_P);
      Shaders.Set (Location (Shadow_P, "uLeaves"), Integer'(Textures.Unit_Leaves));
      Shaders.Set (Location (Shadow_P, "uNeedles"), Integer'(Textures.Unit_Needles));
      glUseProgram (0);

      Build_Shadow (1);
      Build_Shadow (2);

      glGenFramebuffers (1, Scene_FB'Address);
      glGenFramebuffers (1, Resolve_FB'Address);
      glGenFramebuffers (1, Mirror_FB'Address);
      glGenRenderbuffers (1, Scene_Color'Address);
      glGenRenderbuffers (1, Scene_Depth'Address);
      glGenRenderbuffers (1, Mirror_Depth'Address);
      glGenTextures (1, Resolve_Tex'Address);
      glGenTextures (1, Mirror_Tex'Address);

      Resize (1280, 720);
      glBindFramebuffer (GL_FRAMEBUFFER, Scene_FB);
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, Scene_Color);
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, Scene_Depth);
      glBindFramebuffer (GL_FRAMEBUFFER, Resolve_FB);
      glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, Resolve_Tex, 0);

      Color_Texture (Mirror_Tex, Mirror_W, Mirror_H);
      glBindRenderbuffer (GL_RENDERBUFFER, Mirror_Depth);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, 0, GL_DEPTH_COMPONENT32F, Mirror_W, Mirror_H);
      glBindFramebuffer (GL_FRAMEBUFFER, Mirror_FB);
      glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, Mirror_Tex, 0);
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, Mirror_Depth);

      glGenVertexArrays (1, Empty_VAO'Address);
      glGenVertexArrays (1, Skid_VAO'Address);
      glGenBuffers (1, Skid_VBO'Address);
      Attribs_Fx (Skid_VAO, Skid_VBO, Skid_Max * (Fx_Vertex'Size / 8));
      glGenVertexArrays (1, Smoke_VAO'Address);
      glGenBuffers (1, Smoke_VBO'Address);
      Attribs_Fx (Smoke_VAO, Smoke_VBO, Smoke_Max * (Fx_Vertex'Size / 8));
      glGenVertexArrays (1, Fall_VAO'Address);
      glGenBuffers (1, Fall_VBO'Address);
      Attribs_Fx (Fall_VAO, Fall_VBO, Fall_Max * 6 * (Fx_Vertex'Size / 8));
      Ada.Numerics.Float_Random.Reset (Dice);
   end Create;

   procedure New_Track is
   begin
      Skid_Next := 0;
      Skid_Used := 0;
      Skid_Last := (others => (others => (others => <>)));
      Smoke := (others => (others => <>));
      Far_Valid := False;
   end New_Track;

   ---------------------------------------------------------------------------

   function Angle_Lerp (A, B, T : Float) return Float is
      D : Float := B - A;
   begin
      if D > Pi then
         D := D - 2.0 * Pi;
      elsif D < -Pi then
         D := D + 2.0 * Pi;
      end if;
      return A + D * T;
   end Angle_Lerp;

   function Pose_Between (A, B : Sim_Loop.Frame; I : Positive; T : Float) return Sim_Loop.Car_Pose is
      P : Sim_Loop.Car_Pose renames A.Poses (I);
      Q : Sim_Loop.Car_Pose renames B.Poses (I);
      R : Sim_Loop.Car_Pose := Q;
      function L (X, Y : Float) return Float is (X + (Y - X) * T);
   begin
      R.X := L (P.X, Q.X);
      R.Y := L (P.Y, Q.Y);
      R.Z := L (P.Z, Q.Z);
      R.Heading := Angle_Lerp (P.Heading, Q.Heading, T);
      R.Pitch := L (P.Pitch, Q.Pitch);
      R.Roll := L (P.Roll, Q.Roll);
      R.Steer := L (P.Steer, Q.Steer);
      for W in Vehicle.Wheel_Id loop
         R.Wheel_Y (W) := L (P.Wheel_Y (W), Q.Wheel_Y (W));
      end loop;
      return R;
   end Pose_Between;

   function Car_Matrix (P : Sim_Loop.Car_Pose) return Mat4 is
     (Translation ((P.X, P.Y, P.Z)) * Rotation_Y (-P.Heading)
      * Rotation_X (P.Pitch) * Rotation_Z (P.Roll)
      * Translation ((0.0, -Session.Spec.H_Cg, 0.0)));

   function Transform (M : Mat4; V : Vec3) return Vec3 is
     ((M (0) * V.X + M (4) * V.Y + M (8) * V.Z + M (12),
       M (1) * V.X + M (5) * V.Y + M (9) * V.Z + M (13),
       M (2) * V.X + M (6) * V.Y + M (10) * V.Z + M (14)));

   function Direction (M : Mat4; V : Vec3) return Vec3 is
     ((M (0) * V.X + M (4) * V.Y + M (8) * V.Z,
       M (1) * V.X + M (5) * V.Y + M (9) * V.Z,
       M (2) * V.X + M (6) * V.Y + M (10) * V.Z));

   --  Reversed depth, far plane at infinity: 1 at the near plane, 0 far away
   function Projection (Fov_Y, Aspect, Near : Float) return Mat4 is
      F : constant Float := 1.0 / Tan (Fov_Y / 2.0);
      M : Mat4 := (others => 0.0);
   begin
      M (0) := F / Aspect;
      M (5) := F;
      M (11) := -1.0;
      M (14) := Near;
      return M;
   end Projection;

   --  With depth from zero to one
   function Ortho_01 (Half, N, F : Float) return Mat4 is
      M : Mat4 := (others => 0.0);
   begin
      M (0) := 1.0 / Half;
      M (5) := 1.0 / Half;
      M (10) := -1.0 / (F - N);
      M (14) := -N / (F - N);
      M (15) := 1.0;
      return M;
   end Ortho_01;

   --  From clip space to shadow map coordinates
   Bias : constant Mat4 :=
     (0.5, 0.0, 0.0, 0.0,
      0.0, 0.5, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.5, 0.5, 0.0, 1.0);

   --  Sun and sky by the hour -----------------------------------------------

   type Sky_Look is record
      Sun_Dir, Sun_C, Sky_C, Hor : Vec3;
      Fog, Clouds, Exposure : Float;
      Mist : Float := 0.0;   --  0 .. 1: how much of the sky is lost in it
   end record;

   function Clear_Look (D : Time_Of_Day) return Sky_Look is
     (case D is
         when Morning =>
           (Normalize ((0.70, 0.42, 0.45)), (2.4, 2.05, 1.6), (0.20, 0.33, 0.60), (0.62, 0.60, 0.60),
            0.00011, 0.30, 0.8, 0.0),
         when Noon =>
           (Normalize ((0.42, 0.72, 0.55)), (2.6, 2.45, 2.2), (0.15, 0.30, 0.65), (0.50, 0.62, 0.78),
            0.00007, 0.42, 0.72, 0.0),
         when Golden_Hour =>
           (Normalize ((-0.78, 0.17, 0.55)), (3.2, 1.8, 0.85), (0.16, 0.24, 0.45), (0.90, 0.56, 0.34),
            0.00014, 0.52, 0.85, 0.0),
         when Overcast =>
           (Normalize ((0.3, 0.8, 0.3)), (0.55, 0.55, 0.57), (0.42, 0.46, 0.50), (0.55, 0.57, 0.60),
            0.00028, 1.0, 0.95, 0.0),
         when Dawn =>
           (Normalize ((0.80, 0.09, -0.55)), (1.9, 1.05, 0.95), (0.10, 0.15, 0.32), (0.72, 0.48, 0.50),
            0.00022, 0.40, 1.05, 0.0),
         when Dusk =>
           (Normalize ((-0.84, 0.05, 0.50)), (1.1, 0.48, 0.32), (0.045, 0.07, 0.18), (0.42, 0.22, 0.24),
            0.00018, 0.45, 1.25, 0.0),
         when Night =>
           (Normalize ((0.35, 0.65, 0.40)), (0.085, 0.10, 0.15), (0.006, 0.009, 0.020), (0.012, 0.016, 0.030),
            0.00015, 0.35, 1.6, 0.0));

   --  The weather over it; darkness stays darkness
   function Look_For (D : Time_Of_Day) return Sky_Look is
      S : Sky_Look := Clear_Look (D);
      Day : constant Float := Float'Min (1.0, Sqrt (S.Sky_C.X ** 2 + S.Sky_C.Y ** 2 + S.Sky_C.Z ** 2) * 1.6);
      use type Session.Weather_Kind;
   begin
      case Session.Config.Weather is
         when Session.Clear => null;
         when Session.Rain =>
            S.Sun_C := 0.28 * S.Sun_C;
            S.Sky_C := Day * Vec3'(0.40, 0.43, 0.47);
            S.Hor := Day * Vec3'(0.50, 0.52, 0.55);
            S.Fog := Float'Max (S.Fog, 0.0012);
            S.Clouds := 1.0;
            S.Mist := 0.25;
         when Session.Fog =>
            S.Sun_C := 0.35 * S.Sun_C;
            S.Sky_C := Day * Vec3'(0.55, 0.57, 0.60);
            S.Hor := Day * Vec3'(0.62, 0.63, 0.65);
            S.Fog := 0.0075;
            S.Clouds := 1.0;
            S.Mist := 1.0;
         when Session.Snowing =>
            S.Sun_C := 0.38 * S.Sun_C;
            S.Sky_C := Day * Vec3'(0.52, 0.55, 0.60);
            S.Hor := Day * Vec3'(0.72, 0.74, 0.78);
            S.Fog := 0.0022;
            S.Clouds := 1.0;
            S.Mist := 0.5;
      end case;
      return S;
   end Look_For;

   ---------------------------------------------------------------------------
   --  Cars
   ---------------------------------------------------------------------------

   procedure Draw_Wheels (P : Sim_Loop.Car_Pose; Model : Mat4; Kind : Vehicle.Car_Kind;
                          Loc : GLint)
   is
      S : Vehicle.Spec renames Session.Spec;
      Xs : constant array (Vehicle.Wheel_Id) of Float :=
        (-S.Track_F / 2.0, S.Track_F / 2.0, -S.Track_R / 2.0, S.Track_R / 2.0);
      Zs : constant array (Vehicle.Wheel_Id) of Float := (-S.A, -S.A, S.B, S.B);
   begin
      for W in Vehicle.Wheel_Id loop
         declare
            Steer : constant Float := (if W <= 2 then P.Steer else 0.0);
            M : constant Mat4 :=
              Model * Translation ((Xs (W), P.Wheel_Y (W), Zs (W)))
              * Rotation_Y (-Steer) * Rotation_X (-P.Wheel_Angle (W));
         begin
            Shaders.Set (Loc, M);
            Mesh.Draw (Car_Model.Meshes (Kind).Wheel);
         end;
      end loop;
   end Draw_Wheels;

   procedure Draw_Car (I : Positive; P : Sim_Loop.Car_Pose; Kind : Vehicle.Car_Kind;
                       Show_Body : Boolean)
   is
      M : constant Mat4 := Car_Matrix (P);
      Paint : constant Vec3 :=
        (if I = 1 then (Session.Spec.Paint_R, Session.Spec.Paint_G, Session.Spec.Paint_B)
         else Paints (I));
   begin
      Shaders.Set (U_Paint, Paint);
      Shaders.Set (U_Brake, P.Brake);
      Shaders.Set (U_Model, M);
      Shaders.Set (U_Dirt, (if I = 1 then Dirt_Level else 0.15 * Dirt_Level));
      Shaders.Set (U_Dent, (if I = 1 then Dent_Level else 0.0));
      if Show_Body then
         glEnable (GL_CULL_FACE);
         glCullFace (GL_BACK);
         Mesh.Draw (Car_Model.Meshes (Kind).Bodywork);
         glDisable (GL_CULL_FACE);
      end if;
      Draw_Wheels (P, M, Kind, U_Model);
   end Draw_Car;

   ---------------------------------------------------------------------------
   --  Skids and smoke
   ---------------------------------------------------------------------------

   procedure Update_Effects (F : Sim_Loop.Frame; Dt : Float) is
      S : Vehicle.Spec renames Session.Spec;
      Xs : constant array (Vehicle.Wheel_Id) of Float :=
        (-S.Track_F / 2.0, S.Track_F / 2.0, -S.Track_R / 2.0, S.Track_R / 2.0);
      Zs : constant array (Vehicle.Wheel_Id) of Float := (-S.A, -S.A, S.B, S.B);
      use Ada.Numerics.Float_Random;
   begin
      for I in 1 .. F.Count loop
         declare
            P : Sim_Loop.Car_Pose renames F.Poses (I);
            M : constant Mat4 := Car_Matrix (P);
         begin
            for W in Vehicle.Wheel_Id loop
               declare
                  Sliding : constant Boolean := P.Slide (W) > 0.08 and then P.Speed > 2.0;
                  Last : Skid_Point renames Skid_Last (I, W);
                  Half : constant Float := 0.12;
                  Y : constant Float := P.Wheel_Y (W) - S.Radius + 0.025;
                  L : constant Vec3 := Transform (M, (Xs (W) - Half, Y, Zs (W)));
                  R : constant Vec3 := Transform (M, (Xs (W) + Half, Y, Zs (W)));
               begin
                  if Sliding then
                     if Last.Valid
                       and then (L.X - Last.LX) ** 2 + (L.Z - Last.LZ) ** 2 > 0.3
                     then
                        declare
                           A : constant Float := Clamp (P.Slide (W) * 1.8, 0.15, 0.75);
                           V : aliased array (1 .. 6) of aliased Fx_Vertex;
                           function Vx (X, Yy, Z : Float) return Fx_Vertex is
                             ((X, Yy, Z, 0.01, 0.01, 0.01, A, 1.0));
                        begin
                           if (L.X - Last.LX) ** 2 + (L.Z - Last.LZ) ** 2 < 25.0 then
                              V (1) := Vx (Last.LX, Last.LY, Last.LZ);
                              V (2) := Vx (Last.RX, Last.RY, Last.RZ);
                              V (3) := Vx (R.X, R.Y, R.Z);
                              V (4) := Vx (Last.LX, Last.LY, Last.LZ);
                              V (5) := Vx (R.X, R.Y, R.Z);
                              V (6) := Vx (L.X, L.Y, L.Z);
                              glBindBuffer (GL_ARRAY_BUFFER, Skid_VBO);
                              glBufferSubData
                                (GL_ARRAY_BUFFER,
                                 GLintptr (Skid_Next) * GLintptr (Fx_Vertex'Size / 8),
                                 GLsizeiptr (6 * (Fx_Vertex'Size / 8)), V'Address);
                              Skid_Next := (Skid_Next + 6) mod (Skid_Max - Skid_Max mod 6);
                              Skid_Used := Natural'Min (Skid_Max - Skid_Max mod 6, Skid_Used + 6);
                           end if;
                           Last := (True, L.X, L.Y, L.Z, R.X, R.Y, R.Z);
                        end;
                     elsif not Last.Valid then
                        Last := (True, L.X, L.Y, L.Z, R.X, R.Y, R.Z);
                     end if;
                  else
                     Last.Valid := False;
                  end if;
                  --  Dust behind every wheel on a dirt road, however it rolls
                  if (Track.Is_Stage or else Track.Wet > 0.5 or else Track.Snow > 0.5)
                    and then P.Speed > (if Track.Is_Stage then 3.0 else 9.0)
                    and then Random (Dice) < (0.12 + 0.012 * P.Speed + 1.2 * P.Slide (W)) * 60.0 * Dt
                  then
                     Smoke_Cursor := Smoke_Cursor mod Smoke_Max + 1;
                     Smoke (Smoke_Cursor) :=
                       (X => L.X, Y => L.Y + 0.15, Z => L.Z,
                        VX => (Random (Dice) - 0.5) * 2.0 + Sin (P.Heading) * P.Speed * 0.3,
                        VY => 0.5 + Random (Dice) * 1.0,
                        VZ => (Random (Dice) - 0.5) * 2.0 - Cos (P.Heading) * P.Speed * 0.3,
                        Age => 0.0, Life => 1.8 + 2.6 * Random (Dice),
                        Size => 0.8 + 0.9 * Random (Dice));
                  --  Smoke from a tyre really going
                  elsif P.Slide (W) > 0.22 and then P.Speed > 2.0
                    and then Random (Dice) < P.Slide (W) * 40.0 * Dt
                  then
                     Smoke_Cursor := Smoke_Cursor mod Smoke_Max + 1;
                     declare
                        Sp : constant Float := Float'Min (P.Speed, 30.0) * 0.25;
                        Fx : constant Float := Sin (P.Heading);
                        Fz : constant Float := -Cos (P.Heading);
                     begin
                        Smoke (Smoke_Cursor) :=
                          (X => L.X, Y => L.Y + 0.2, Z => L.Z,
                           VX => Fx * Sp + (Random (Dice) - 0.5),
                           VY => 0.6 + Random (Dice) * 0.8,
                           VZ => Fz * Sp + (Random (Dice) - 0.5),
                           Age => 0.0, Life => 1.4 + 1.5 * Random (Dice),
                           Size => 0.6 + 0.6 * Random (Dice));
                     end;
                  end if;
               end;
            end loop;
         end;
      end loop;
      for Pt of Smoke loop
         if Pt.Life > 0.0 then
            Pt.Age := Pt.Age + Dt;
            Pt.X := Pt.X + Pt.VX * Dt;
            Pt.Y := Pt.Y + Pt.VY * Dt;
            Pt.Z := Pt.Z + Pt.VZ * Dt;
            Pt.VX := Pt.VX * (1.0 - Dt);
            Pt.VZ := Pt.VZ * (1.0 - Dt);
            if Pt.Age > Pt.Life then
               Pt.Life := 0.0;
            end if;
         end if;
      end loop;
   end Update_Effects;

   type Fall_List is array (1 .. Fall_Max * 6) of aliased Fx_Vertex with Convention => C;
   type Fall_Access is access Fall_List;
   Fall_Data : constant Fall_Access := new Fall_List;

   procedure Draw_Effects (VP : Mat4; Height : Natural; Fov : Float; Sky : Sky_Look) is
   begin
      glUseProgram (Fx_P);
      Shaders.Set (F_VP, VP);
      glEnable (GL_BLEND);
      glBlendFunc (GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
      glDepthMask (GL_FALSE);
      if Skid_Used > 0 then
         Shaders.Set (F_Points, 0.0);
         glBindVertexArray (Skid_VAO);
         glDrawArrays (GL_TRIANGLES, 0, GLsizei (Skid_Used));
      end if;
      declare
         type Point_List is array (1 .. Smoke_Max) of aliased Fx_Vertex with Convention => C;
         Pts : aliased Point_List;
         N : Natural := 0;
         Tone : constant Float := 0.5 * (Sky.Sun_C.X + Sky.Sky_C.X) * 0.5;
      begin
         for P of Smoke loop
            if P.Life > 0.0 then
               N := N + 1;
               declare
                  T : constant Float := P.Age / P.Life;
                  A : constant Float := 0.22 * (1.0 - T);
               begin
                  if Track.Wet > 0.5 or else Track.Snow > 0.5 then
                     --  Spray: pale, and it does not hang about
                     Pts (N) := (P.X, P.Y, P.Z, Tone * 1.5, Tone * 1.5, Tone * 1.55,
                                 A * 0.7, P.Size * (1.0 + 2.5 * T));
                  elsif Track.Is_Stage then
                     Pts (N) := (P.X, P.Y, P.Z, Tone * 0.95, Tone * 0.80, Tone * 0.58,
                                 A * 0.8, P.Size * (1.0 + 4.0 * T));
                  else
                     Pts (N) := (P.X, P.Y, P.Z, Tone, Tone, Tone, A, P.Size * (1.0 + 3.0 * T));
                  end if;
               end;
            end if;
         end loop;
         if N > 0 then
            glBindBuffer (GL_ARRAY_BUFFER, Smoke_VBO);
            glBufferSubData (GL_ARRAY_BUFFER, 0,
                             GLsizeiptr (N * (Fx_Vertex'Size / 8)), Pts'Address);
            Shaders.Set (F_Points, 1.0);
            Shaders.Set (F_Scale, Float (Height) / (2.0 * Tan (Fov / 2.0)));
            glEnable (GL_PROGRAM_POINT_SIZE);
            glBindVertexArray (Smoke_VAO);
            glDrawArrays (GL_POINTS, 0, GLsizei (N));
         end if;
      end;
      --  Rain as streaks, snow as flakes
      declare
         use type Session.Weather_Kind;
         W : constant Session.Weather_Kind := Session.Config.Weather;
         Raining : constant Boolean := W = Session.Rain;
         Snowing : constant Boolean := W = Session.Snowing;
      begin
         if Raining or else Snowing then
            declare
               Vs : constant Fall_Access := Fall_Data;
               N : Natural := 0;
               Tone : constant Float := 0.25 * (Sky.Sky_C.X + Sky.Sun_C.X) + 0.04;
               Box : constant := 26.0;
               Tall : constant := 16.0;
               function Wrap (V, Around : Float) return Float is
                 (Around + (V - Around + Box) - 2.0 * Box * Float'Floor ((V - Around + Box) / (2.0 * Box)) - Box);
            begin
               for K in 1 .. (if Raining then 1100 else 1400) loop
                  declare
                     H1 : constant Float := Float ((K * 7919) mod 1000) / 1000.0;
                     H2 : constant Float := Float ((K * 104_729) mod 1000) / 1000.0;
                     H3 : constant Float := Float ((K * 48_271) mod 1000) / 1000.0;
                     Speed_K : constant Float := (if Raining then 11.0 + 5.0 * H3 else 1.2 + 0.8 * H3);
                     Drift : constant Float :=
                       (if Snowing then 0.5 * Sin (Clock_T * (0.7 + H1) + H2 * 6.0) else 0.0);
                     X : constant Float := Wrap (H1 * 2.0 * Box * 7.0 + Drift, Fall_Eye.X);
                     Z : constant Float := Wrap (H2 * 2.0 * Box * 7.0 + Drift * 0.6, Fall_Eye.Z);
                     Y0 : constant Float := H3 * Tall - Clock_T * Speed_K;
                     Y : constant Float :=
                       Fall_Eye.Y - 4.0 + (Y0 - Tall * Float'Floor (Y0 / Tall));
                     Len : constant Float := (if Raining then 0.55 else 0.0);
                  begin
                     if Raining then
                        declare
                           Wd : constant Vec3 := 0.012 * Fall_Right;
                           Col : constant Float := Tone;
                           function V (P : Vec3) return Fx_Vertex is
                             ((P.X, P.Y, P.Z, Col, Col, Col * 1.08, 0.32, 1.0));
                           A : constant Vec3 := (X, Y, Z);
                           B : constant Vec3 := (X, Y + Len, Z);
                        begin
                           Vs (N + 1) := V (A - Wd);
                           Vs (N + 2) := V (A + Wd);
                           Vs (N + 3) := V (B + Wd);
                           Vs (N + 4) := V (A - Wd);
                           Vs (N + 5) := V (B + Wd);
                           Vs (N + 6) := V (B - Wd);
                           N := N + 6;
                        end;
                     else
                        N := N + 1;
                        Vs (N) := (X, Y, Z, Tone * 2.2, Tone * 2.2, Tone * 2.3, 0.85, 0.055);
                     end if;
                  end;
               end loop;
               glBindBuffer (GL_ARRAY_BUFFER, Fall_VBO);
               glBufferSubData (GL_ARRAY_BUFFER, 0,
                                GLsizeiptr (N * (Fx_Vertex'Size / 8)), Vs.all'Address);
               glBindVertexArray (Fall_VAO);
               if Raining then
                  Shaders.Set (F_Points, 0.0);
                  glDrawArrays (GL_TRIANGLES, 0, GLsizei (N));
               else
                  Shaders.Set (F_Points, 1.0);
                  Shaders.Set (F_Scale, Float (Height) / (2.0 * Tan (Fov / 2.0)));
                  glEnable (GL_PROGRAM_POINT_SIZE);
                  glDrawArrays (GL_POINTS, 0, GLsizei (N));
               end if;
            end;
         end if;
      end;
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);
   end Draw_Effects;

   ---------------------------------------------------------------------------
   --  The scene from one eye
   ---------------------------------------------------------------------------

   procedure Scene
     (Poses : Sim_Loop.Pose_Array; Count : Natural; VP : Mat4; Eye : Vec3;
      Sky : Sky_Look; Clock : Float; Light_N, Light_F : Mat4;
      Hide_Own : Boolean; Cockpit_On : Boolean; Steer_In : Float;
      Ghost : Sim_Loop.Car_Pose; Show_Ghost : Boolean)
   is
      Kind : constant Vehicle.Car_Kind := Session.Config.Kind;
   begin
      --  Sky behind everything
      glDisable (GL_DEPTH_TEST);
      glDepthMask (GL_FALSE);
      glUseProgram (Sky_P);
      Shaders.Set (K_Inv, Inverse (VP));
      Shaders.Set (K_Cam, Eye);
      Shaders.Set (K_Sun, Sky.Sun_Dir);
      Shaders.Set (K_Sun_C, Sky.Sun_C);
      Shaders.Set (K_Sky_C, Sky.Sky_C);
      Shaders.Set (K_Mist, Sky.Mist);
      Shaders.Set (K_Hor, Sky.Hor);
      Shaders.Set (K_Time, Clock);
      Shaders.Set (K_Clouds, Sky.Clouds);
      glBindVertexArray (Empty_VAO);
      glDrawArrays (GL_TRIANGLES, 0, 3);
      glDepthMask (GL_TRUE);
      glEnable (GL_DEPTH_TEST);

      glUseProgram (World_P);
      Shaders.Set (U_VP, VP);
      Shaders.Set (U_Model, Identity);
      Shaders.Set (U_Cam, Eye);
      Shaders.Set (U_Sun, Sky.Sun_Dir);
      Shaders.Set (U_Sun_C, Sky.Sun_C);
      Shaders.Set (U_Sky_C, Sky.Sky_C);
      Shaders.Set (U_Hor, Sky.Hor);
      Shaders.Set (U_Fog, Sky.Fog);
      Shaders.Set (U_Brake, Float'(0.0));
      Shaders.Set (U_Alpha, Float'(1.0));
      Shaders.Set (U_Paint, Vec3'(0.5, 0.5, 0.5));
      Shaders.Set (U_Shad, Float'(1.0));
      Shaders.Set (U_SN, Bias * Light_N);
      Shaders.Set (U_SF, Bias * Light_F);
      Shaders.Set (U_MN, Integer'(1));
      Shaders.Set (U_MF, Integer'(2));
      glActiveTexture (GL_TEXTURE1);
      glBindTexture (GL_TEXTURE_2D, Shadow_Tex (1));
      glActiveTexture (GL_TEXTURE2);
      glBindTexture (GL_TEXTURE_2D, Shadow_Tex (2));
      glActiveTexture (GL_TEXTURE0);

      Shaders.Set (U_Grain, Float'(1.0));
      Shaders.Set (U_Forest, Float'(if Track.Is_Stage then 1.0 else 0.0));
      Shaders.Set (U_Dirt, Float'(0.0));
      Shaders.Set (U_Dent, Float'(0.0));
      Shaders.Set (U_Wet, Track.Wet);
      Shaders.Set (U_Snow, Track.Snow);
      Shaders.Set (U_Season, Float (Session.Season_Kind'Pos (Session.Config.Season)));
      Shaders.Set (U_Car_V, Car_Speed);
      Shaders.Set (U_Head_On, Float'(if Lights_On then 1.0 else 0.0));
      Shaders.Set (U_Head_N, Integer'(Count));
      Shaders.Set (U_Head_Pow, Float'(if Vehicle."=" (Kind, Vehicle.Rally_4WD) then 1.7 else 1.0));
      for I in 1 .. Count loop
         declare
            H : constant Float := Poses (I).Heading;
            Fw : constant Vec3 := (Sin (H), 0.0, -Cos (H));
         begin
            Shaders.Set (U_Head_Pos (I),
                         Vec3'(Poses (I).X, Poses (I).Y + 0.2, Poses (I).Z) + 2.2 * Fw);
            Shaders.Set (U_Head_Dir (I), Normalize (Fw + Vec3'(0.0, -0.045, 0.0)));
         end;
      end loop;
      Mesh.Draw (Scenery.Ground);
      Mesh.Draw (Scenery.Road);
      if Guide_On then
         glEnable (GL_BLEND);
         glBlendFunc (GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
         glDepthMask (GL_FALSE);
         Shaders.Set (U_Alpha, Float'(0.8));
         Mesh.Draw (Scenery.Guide_Line);
         Shaders.Set (U_Alpha, Float'(1.0));
         glDepthMask (GL_TRUE);
         glDisable (GL_BLEND);
      end if;
      Mesh.Draw (Scenery.Static);
      declare
         Inv : constant Mat4 := Inverse (VP);
         Far_Pt : constant Vec3 :=
           (Inv (0) * 0.0 + Inv (8) * 0.5 + Inv (12), 0.0, Inv (2) * 0.0 + Inv (10) * 0.5 + Inv (14));
         W : constant Float := Inv (11) * 0.5 + Inv (15);
         DX : constant Float := Far_Pt.X / W - Eye.X;
         DZ : constant Float := Far_Pt.Z / W - Eye.Z;
         L : constant Float := Float'Max (0.001, Sqrt (DX * DX + DZ * DZ));
      begin
         Scenery.Draw_View (Eye.X, Eye.Z, DX / L, DZ / L);
      end;

      --  The cars move: world-fixed grain would swim over them
      Shaders.Set (U_Grain, Float'(0.0));
      for I in 1 .. Count loop
         if I > 1 or else not Hide_Own then
            Draw_Car (I, Poses (I), Kind, True);
         end if;
      end loop;

      if Cockpit_On then
         declare
            M : constant Mat4 := Car_Matrix (Poses (1));
         begin
            Shaders.Set (U_Paint, Vec3'(Session.Spec.Paint_R, Session.Spec.Paint_G, Session.Spec.Paint_B));
            Shaders.Set (U_Brake, Float'(0.0));
            Shaders.Set (U_Model, M);
            Shaders.Set (U_Dirt, Dirt_Level);
            Shaders.Set (U_Dent, Dent_Level);
            glEnable (GL_CULL_FACE);
            glCullFace (GL_BACK);
            Shaders.Set (U_Grain, Float'(-1.0));
            Mesh.Draw (Car_Model.Meshes (Kind).Bodywork);
            Shaders.Set (U_Grain, Float'(0.0));
            glDisable (GL_CULL_FACE);
            Mesh.Draw (Car_Model.Meshes (Kind).Cockpit);
            Shaders.Set
              (U_Model,
               M * Translation ((Car_Model.Steering_X, Car_Model.Steering_Y, Car_Model.Steering_Z))
               * Rotation_X (-Car_Model.Steering_Tilt)
               * Rotation_Z (-Steer_In * 2.5 * Pi));
            Mesh.Draw (Car_Model.Meshes (Kind).Steering);
         end;
      end if;

      if Show_Ghost then
         glEnable (GL_BLEND);
         glBlendFunc (GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
         glDepthMask (GL_FALSE);
         Shaders.Set (U_Dirt, Float'(0.0));
         Shaders.Set (U_Dent, Float'(0.0));
         Shaders.Set (U_Alpha, Float'(0.28));
         Shaders.Set (U_Paint, Vec3'(0.6, 0.8, 1.0));
         Shaders.Set (U_Brake, Float'(0.0));
         Shaders.Set (U_Model, Car_Matrix (Ghost));
         glEnable (GL_CULL_FACE);
         Mesh.Draw (Car_Model.Meshes (Kind).Bodywork);
         glDisable (GL_CULL_FACE);
         glDepthMask (GL_TRUE);
         glDisable (GL_BLEND);
         Shaders.Set (U_Alpha, Float'(1.0));
      end if;
   end Scene;

   procedure Draw_Shadow (Index : Positive; Light : Mat4; Poses : Sim_Loop.Pose_Array;
                          Count : Natural)
   is
      Kind : constant Vehicle.Car_Kind := Session.Config.Kind;
   begin
      glBindFramebuffer (GL_FRAMEBUFFER, Shadow_FB (Index));
      glViewport (0, 0, Shadow_Size, Shadow_Size);
      glClearDepthf (1.0);
      glClear (GL_DEPTH_BUFFER_BIT);
      glDepthFunc (GL_LESS);
      glEnable (GL_DEPTH_TEST);
      glUseProgram (Shadow_P);
      Shaders.Set (S_LVP, Light);
      Shaders.Set (S_Model, Identity);
      Mesh.Draw (Scenery.Static);
      Scenery.Draw_Near (Poses (1).X, Poses (1).Z, (if Index = 1 then Near_Half * 1.2 else Far_Half * 1.1));
      if Index = 2 then
         return;   --  (the cars are only in the near map)
      end if;
      for I in 1 .. Count loop
         declare
            M : constant Mat4 := Car_Matrix (Poses (I));
         begin
            Shaders.Set (S_Model, M);
            Mesh.Draw (Car_Model.Meshes (Kind).Bodywork);
            Draw_Wheels (Poses (I), M, Kind, S_Model);
         end;
      end loop;
   end Draw_Shadow;

   Listen_Pos : Vec3 := (0.0, 0.0, 0.0);
   Listen_Fwd : Vec3 := (0.0, 0.0, -1.0);

   function Listener_Inside (Options : View_Options) return Boolean is
     (Options.Camera = Cockpit);

   procedure Hearing (Pose : Sim_Loop.Car_Pose; Level, Pan : out Float) is
      DX : constant Float := Pose.X - Listen_Pos.X;
      DZ : constant Float := Pose.Z - Listen_Pos.Z;
      D : constant Float := Sqrt (DX * DX + DZ * DZ) + 0.5;
      RX : constant Float := -Listen_Fwd.Z;
      RZ : constant Float := Listen_Fwd.X;
   begin
      Level := Float'Min (1.0, 14.0 / D);
      Pan := Clamp ((DX * RX + DZ * RZ) / D, -1.0, 1.0);
   end Hearing;

   procedure Draw (A, B : Sim_Loop.Frame; Options : View_Options; Width, Height : Natural) is
      GTK_FB : aliased GLint := 0;
      Now_T : constant Long_Float := Sim_Loop.Now;
      Span : constant Long_Float := B.Time - A.Time;
      T : constant Float :=
        (if Span > 0.0 then Clamp (Float ((Now_T - A.Time) / Span), 0.0, 8.0) else 1.0);
      Poses : Sim_Loop.Pose_Array := B.Poses;
      Dt : constant Float := Options.Dt;
      Sky : constant Sky_Look := Look_For (Options.Day);
      Dim : constant Boolean :=
        Options.Day in Dawn | Dusk | Night
        or else Session.Config.Weather in Session.Rain | Session.Fog | Session.Snowing;
      Fov : constant Float := Options.Fov * Pi / 180.0;
      Aspect : constant Float := Float (Width) / Float (Natural'Max (Height, 1));
   begin
      glGetIntegerv (GL_FRAMEBUFFER_BINDING, GTK_FB'Address);
      Clock_T := Clock_T + Dt;
      Guide_On := Options.Guide;
      --  Dirt gathers on loose ground and washes off in rain; a fresh start is clean
      if B.Laps (1).Lap_Time < 0.05 and then B.Laps (1).Lap = 0 then
         Dirt_Level := 0.0;
      elsif B.On_Dirt or else B.Off_Road then
         Dirt_Level := Float'Min (1.0, Dirt_Level + Dt * Float'Min (B.Speed, 30.0) / 30.0 * 0.018);
      elsif Track.Wet > 0.5 then
         Dirt_Level := Float'Max (0.0, Dirt_Level - Dt * 0.012);
      end if;
      Dent_Level := B.Dmg_Aero;
      glUseProgram (World_P);
      Shaders.Set (U_Dial_Rpm, B.Rpm / Float'Max (1000.0, B.Red_Line + 1800.0));
      Shaders.Set (U_Dial_Speed, B.Speed * 3.6 / 320.0);
      Shaders.Set (U_Dial_Gear, Float (B.Gear));
      Car_Speed := B.Speed;
      Lights_On := Dim;
      for I in 1 .. B.Count loop
         if I <= A.Count then
            Poses (I) := Pose_Between (A, B, I, T);
         end if;
      end loop;
      Resize (Width, Height);

      --  Camera ---------------------------------------------------------------
      declare
         P : Sim_Loop.Car_Pose renames Poses (1);
         M : constant Mat4 := Car_Matrix (P);
         Eye : Vec3;
         Tgt : Vec3;
         Up : Vec3 := (0.0, 1.0, 0.0);
         Cam_Fov : Float := Fov;
         Own_Hidden : Boolean := False;
         In_Cockpit : Boolean := False;
         Fwd_W : constant Vec3 := (Sin (P.Heading), 0.0, -Cos (P.Heading));
         K_Dt : constant Float := Clamp (Dt * 7.0, 0.0, 1.0);
      begin
         case Options.Camera is
            when Cockpit | Hood =>
               In_Cockpit := Options.Camera = Cockpit;
               Own_Hidden := True;
               --  Head pressed by the g forces, with a little lag
               Last_Lat := Last_Lat + (B.Ay - Last_Lat) * K_Dt;
               Last_Lon := Last_Lon + (B.Ax - Last_Lon) * K_Dt;
               Head_X := -Clamp (Last_Lat * 0.0030, -0.04, 0.04);
               Head_Z := Clamp (Last_Lon * 0.0030, -0.035, 0.035);
               Head_Y := Clamp (abs Last_Lon * 0.0006, 0.0, 0.01);
               declare
                  Base : constant Vec3 :=
                    (if Options.Camera = Cockpit
                     then (Car_Model.Eye_X + Head_X, Car_Model.Eye_Y + Head_Y, Car_Model.Eye_Z + Head_Z)
                     else (0.0, 1.03, -0.75));
                  Look_Dir : constant Vec3 :=
                    (Sin (Options.Look), -0.055, -Cos (Options.Look));
                  World_Dir : constant Vec3 := Direction (M, Look_Dir);
               begin
                  Eye := Transform (M, Base);
                  Tgt := Eye + 10.0 * World_Dir;
                  --  Half of the roll and pitch of the car reach the horizon
                  Up := Normalize (Vec3'(0.0, 1.0, 0.0) + Direction (M, (0.0, 1.0, 0.0)));
               end;
            when Chase | Chase_Far =>
               declare
                  Dist : constant Float := (if Options.Camera = Chase then 5.6 else 9.5);
                  High : constant Float := (if Options.Camera = Chase then 1.65 else 2.9);
                  Target_H : constant Float :=
                    (if P.Speed > 1.0 then P.Heading else Chase_Heading);
               begin
                  Chase_Heading := Angle_Lerp (Chase_Heading, Target_H, Clamp (Dt * 5.5, 0.0, 1.0));
                  if Chase_Heading > Pi then
                     Chase_Heading := Chase_Heading - 2.0 * Pi;
                  elsif Chase_Heading < -Pi then
                     Chase_Heading := Chase_Heading + 2.0 * Pi;
                  end if;
                  declare
                     Back : constant Vec3 := (Sin (Chase_Heading), 0.0, -Cos (Chase_Heading));
                     Ground : Float;
                     Hint : Natural := Track.Find_Nearest (P.X, P.Z);
                     Con : Track.Contact;
                     CX : constant Float := P.X - Back.X * Dist;
                     CZ : constant Float := P.Z - Back.Z * Dist;
                  begin
                     Track.Query (CX, CZ, Hint, Con);
                     Ground := Con.Y;
                     Eye := (CX, Float'Max (P.Y + High - 0.3, Ground + 1.0), CZ);
                     Tgt := (P.X, P.Y + 0.55, P.Z) + 2.0 * Fwd_W;
                  end;
                  Cam_Fov := Fov + Clamp (P.Speed / 90.0, 0.0, 1.0) * 0.15;
               end;
            when Trackside =>
               declare
                  Near : constant Natural := Track.Find_Nearest (P.X, P.Z);
                  Stride : constant := 70;
                  Post : constant Natural := Track.Next (0, ((Near + 25) / Stride) * Stride);
                  S : Track.Sample renames Track.Samples (Post);
                  Sign : constant Float := (if Post / Stride mod 2 = 0 then 1.0 else -1.0);
                  D : constant Float := Sign * ((if Sign > 0.0 then S.Wall_R else S.Wall_L) - 0.6);
                  CX : constant Float := S.X + S.RX * D;
                  CZ : constant Float := S.Z + S.RZ * D;
                  Hint : Natural := Post;
                  Con : Track.Contact;
               begin
                  Track.Query (CX, CZ, Hint, Con);
                  Eye := (CX, Con.Y + 2.1, CZ);
                  Tgt := (P.X, P.Y, P.Z);
                  Cam_Fov := Clamp (2.0 * Arctan (6.0 / Float'Max (1.0, Length (Tgt - Eye))), 0.14, 1.1);
               end;
         end case;

         Listen_Pos := Eye;
         Listen_Fwd := Normalize (Tgt - Eye);

         --  Sun shadows, in two ranges round the car -------------------------
         declare
            function Light_Matrix (Half : Float) return Mat4 is
               C : constant Vec3 := (P.X, P.Y, P.Z);
               LV : Mat4 := Look_At (C + 1500.0 * Sky.Sun_Dir, C, (0.0, 1.0, 0.0));
               Texel : constant Float := 2.0 * Half / Float (Shadow_Size);
            begin
               --  Snap to whole texels, or the edges crawl
               LV (12) := Float'Rounding (LV (12) / Texel) * Texel;
               LV (13) := Float'Rounding (LV (13) / Texel) * Texel;
               return Ortho_01 (Half, 100.0, 3000.0) * LV;
            end Light_Matrix;
            LN : constant Mat4 := Light_Matrix (Near_Half);
            Far_Stale : constant Boolean :=
              (P.X - Far_X) ** 2 + (P.Z - Far_Z) ** 2 > 40.0 * 40.0 or else not Far_Valid;
            Ghost : constant Sim_Loop.Car_Pose :=
              (X => B.Ghost.X, Y => B.Ghost.Y, Z => B.Ghost.Z, Heading => B.Ghost.Heading,
               Pitch => B.Ghost.Pitch, Roll => B.Ghost.Roll, others => <>);
            Show_Ghost : constant Boolean :=
              Options.Ghost and then B.Ghost.X /= 0.0 and then B.Ghost.Z /= 0.0;
            Near_Plane : constant Float :=
              (if Options.Camera = Cockpit then 0.06 else 0.3);
            VP : constant Mat4 := Projection (Cam_Fov, Aspect, Near_Plane) * Look_At (Eye, Tgt, Up);
         begin
            glClipControl (GL_LOWER_LEFT, GL_ZERO_TO_ONE);
            glEnable (GL_POLYGON_OFFSET_FILL);
            glPolygonOffset (1.5, 2.0);
            Draw_Shadow (1, LN, Poses, B.Count);
            if Far_Stale then
               Far_Matrix := Light_Matrix (Far_Half);
               Far_X := P.X;
               Far_Z := P.Z;
               Far_Valid := True;
               Draw_Shadow (2, Far_Matrix, Poses, B.Count);
            end if;
            glDisable (GL_POLYGON_OFFSET_FILL);

            Update_Effects (B, Dt);
            Fall_Eye := Eye;
            declare
               Dir : constant Vec3 := Tgt - Eye;
            begin
               Fall_Right := Normalize (Cross (Dir, (0.0, 1.0, 0.0)));
            end;

            --  Reversed depth for the scene
            glDepthFunc (GL_GEQUAL);
            glClearDepthf (0.0);

            --  The virtual mirror --------------------------------------------
            if Options.Mirror and then Options.Camera in Cockpit | Hood then
               declare
                  Base : constant Vec3 := Transform (M, (0.0, 1.13, -0.15));
                  Back : constant Vec3 := Direction (M, (0.0, -0.02, 1.0));
                  MVP : constant Mat4 :=
                    Projection (0.24, Float (Mirror_W) / Float (Mirror_H), 0.5)
                    * Look_At (Base, Base + 10.0 * Back, (0.0, 1.0, 0.0));
               begin
                  glBindFramebuffer (GL_FRAMEBUFFER, Mirror_FB);
                  glViewport (0, 0, Mirror_W, Mirror_H);
                  glClear (GL_DEPTH_BUFFER_BIT);
                  Scene (Poses, B.Count, MVP, Base, Sky, Clock_T, LN, Far_Matrix, True, False, 0.0, Ghost, False);
                  Draw_Effects (MVP, Mirror_H, 0.24, Sky);
               end;
            end if;

            --  The view itself ----------------------------------------------
            glBindFramebuffer (GL_FRAMEBUFFER, Scene_FB);
            glViewport (0, 0, GLsizei (Width), GLsizei (Height));
            glClear (GL_DEPTH_BUFFER_BIT or GL_COLOR_BUFFER_BIT);
            Scene (Poses, B.Count, VP, Eye, Sky, Clock_T, LN, Far_Matrix, Own_Hidden, In_Cockpit,
                   B.Steer_In, Ghost, Show_Ghost);
            Draw_Effects (VP, Height, Cam_Fov, Sky);
         end;
      end;

      --  Resolve, tone map, to the screen ---------------------------------------
      glBindFramebuffer (GL_READ_FRAMEBUFFER, Scene_FB);
      glBindFramebuffer (GL_DRAW_FRAMEBUFFER, Resolve_FB);
      glBlitFramebuffer (0, 0, GLint (Width), GLint (Height), 0, 0, GLint (Width), GLint (Height),
                         GL_COLOR_BUFFER_BIT, GL_NEAREST);
      glBindFramebuffer (GL_FRAMEBUFFER, GLuint (GTK_FB));
      glViewport (0, 0, GLsizei (Width), GLsizei (Height));
      glDisable (GL_DEPTH_TEST);
      glDisable (GL_CULL_FACE);
      glClipControl (GL_LOWER_LEFT, GL_NEGATIVE_ONE_TO_ONE);
      glDepthFunc (GL_LESS);
      glClearDepthf (1.0);
      glUseProgram (Post_P);
      glBindVertexArray (Empty_VAO);
      glActiveTexture (GL_TEXTURE0);
      glBindTexture (GL_TEXTURE_2D, Resolve_Tex);
      --  The mip chain doubles as the blur for the bloom
      glGenerateMipmap (GL_TEXTURE_2D);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
      Shaders.Set (P_Bloom, Float'(1.0));
      Shaders.Set (P_Time, Clock_T);
      Shaders.Set (P_Rain, Float'
        (if Options.Camera = Cockpit
           and then Session.Config.Weather in Session.Rain | Session.Snowing
         then 1.0 else 0.0));
      Shaders.Set (P_Scene, Integer'(0));
      Shaders.Set (P_Exp, Sky.Exposure);
      glBindTexture (GL_TEXTURE_2D, Resolve_Tex);
      glUniform4f (P_Rect, 0.0, 0.0, 1.0, 1.0);
      Shaders.Set (P_Flip, Float'(0.0));
      Shaders.Set (P_Vig, Float'(0.45));
      glDrawArrays (GL_TRIANGLES, 0, 3);
      if Options.Mirror and then Options.Camera in Cockpit | Hood then
         declare
            MW : constant Float := 0.28;
            MH : constant Float := MW * Aspect * Float (Mirror_H) / Float (Mirror_W);
            use Interfaces.C;
         begin
            glBindTexture (GL_TEXTURE_2D, Mirror_Tex);
            glUniform4f (P_Rect, C_float (0.5 - MW / 2.0), C_float (0.975 - MH),
                         C_float (MW), C_float (MH));
            Shaders.Set (P_Flip, Float'(1.0));
            Shaders.Set (P_Bloom, Float'(0.0));
            Shaders.Set (P_Rain, Float'(0.0));
            Shaders.Set (P_Vig, Float'(0.0));
            glEnable (GL_SCISSOR_TEST);
            glScissor (GLint ((0.5 - MW / 2.0) * Float (Width)), GLint ((0.975 - MH) * Float (Height)),
                       GLsizei (MW * Float (Width)), GLsizei (MH * Float (Height)));
            glDrawArrays (GL_TRIANGLES, 0, 3);
            glDisable (GL_SCISSOR_TEST);
         end;
      end if;
      glBindVertexArray (0);
   end Draw;

end Renderer;
