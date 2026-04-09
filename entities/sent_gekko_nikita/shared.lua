AddCSLuaFile()

ENT.Type           = "anim"
ENT.Base           = "base_entity"
ENT.PrintName      = "Gekko Nikita Missile"
ENT.Author         = "Gekko NPC"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

function ENT:SetupDataTables()
    self:NetworkVar( "Vector", 0, "TargetPos" )
end
