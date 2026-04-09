AddCSLuaFile()

ENT.Type           = "anim"
ENT.Base           = "base_anim"
ENT.PrintName      = "Gekko Nikita Missile"
ENT.Author         = "Gekko NPC"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

function ENT:SetupDataTables()
    self:NetworkVar( "Vector", 0, "TargetPos" )
    self:NetworkVar( "Bool",   0, "EngineStarted" )
end
