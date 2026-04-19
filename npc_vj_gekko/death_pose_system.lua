-- ============================================================
--  npc_vj_gekko / death_pose_system.lua
--  Server-side death pose trigger state.
--  The actual bone animation runs clientside from cl_init.lua,
--  mirroring the leg disable system approach.
-- ============================================================

function ENT:GekkoDeath_Init()
    self._gDeathTriggered = false
    self:SetNWBool("GekkoDeathActive", false)
    self:SetNWFloat("GekkoDeathStartT", 0)
end

function ENT:GekkoDeath_Trigger(dmginfo)
    if self._gDeathTriggered then return end

    self._gDeathTriggered = true
    self:SetNWBool("GekkoDeathActive", true)
    self:SetNWFloat("GekkoDeathStartT", CurTime())
end

function ENT:GekkoDeath_Think()
end
