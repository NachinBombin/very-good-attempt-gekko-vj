-- init.lua  (SERVER)
-- npc_vj_gekko

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")
include("death_pose_system.lua")
include("elastic_system.lua")

-- NOTE: extensions.lua is loaded + AddCSLuaFile'd by