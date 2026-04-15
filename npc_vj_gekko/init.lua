-- ============================================================
--  npc_vj_gekko / init.lua
-- ============================================================

if SERVER then
    AddCSLuaFile("cl_init.lua")
    AddCSLuaFile("shared.lua")
end

if CLIENT then include("cl_init.lua") end
include("shared.lua")

include("jump_system.lua")
include("targeted_jump_system.lua")
include("crush_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")
