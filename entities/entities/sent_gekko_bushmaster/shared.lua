-- shared.lua
-- Defines entity type, networked vars, and basic properties shared
-- between server and client.  Matches sent_orbital_rpg exactly.

ENT.Type           = "anim"
ENT.Base           = "base_entity"   -- base_entity provides SetOwner/GetOwner/damage methods
ENT.PrintName      = "Gekko 25mm Round"
ENT.Author         = "NachinBombin"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- Network variables -------------------------------------------------------
function ENT:SetupDataTables()
    -- Store the initial spawn position and forward vector so both realms
    -- can reconstruct the centre-line of the trajectory.
    self:NetworkVar("Vector", 0, "SpawnPos")
    self:NetworkVar("Vector", 1, "SpawnDir")
    -- Birth timestamp (CurTime) used to drive the orbital phase.
    self:NetworkVar("Float",  0, "BirthTime")
end