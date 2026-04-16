-- shared.lua
-- Defines the entity type, networked vars, and basic properties shared
-- between server and client.
-- Copied exactly from sent_orbital_rpg/shared.lua structure.

ENT.Type           = "anim"
ENT.Base           = "base_entity"
ENT.PrintName      = "Gekko 25mm Bushmaster Round"
ENT.Author         = "NachinBombin"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- Network variables -------------------------------------------------------
function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "SpawnPos")
    self:NetworkVar("Vector", 1, "SpawnDir")
    self:NetworkVar("Float",  0, "BirthTime")
end
