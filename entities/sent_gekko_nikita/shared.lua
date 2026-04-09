-- ============================================================
--  sent_gekko_nikita / shared.lua
--  NetworkVars shared between server and client.
-- ============================================================
ENT.Type           = "anim"
ENT.Base           = "base_anim"
ENT.PrintName      = "Gekko Nikita Missile"
ENT.Author         = "Gekko NPC"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- ============================================================
--  NetworkVars
--
--  TargetPos  : the fixed world-space aim point set by the Gekko.
--               Sent to clients so cl_init can draw the targeting
--               line toward the missile's actual destination.
--               Never changes after Initialize().
-- ============================================================
function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "TargetPos")
end
