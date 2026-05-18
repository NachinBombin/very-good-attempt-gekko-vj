-- ============================================================
-- lua/autorun/client/cl_gekko_bloodpool.lua
-- Receives GekkoBloodPoolSpawn net message and fires the
-- gekko_blood_pool effect ONCE on the correct ragdoll entity.
--
-- NO polling loops. NO timers. The server already delays the
-- net message 0.3 s to allow replication to complete.
-- gekko_blood_pool EFFECT:Init handles IsValid(ent) itself.
-- ============================================================
if SERVER then return end

net.Receive("GekkoBloodPoolSpawn", function()
    local entIndex = net.ReadUInt(13)
    local bone     = net.ReadUInt(7)

    local rag = Entity(entIndex)
    if not IsValid(rag) then return end

    local ed = EffectData()
    ed:SetEntity(rag)
    ed:SetAttachment(bone)
    ed:SetFlags(0)
    util.Effect("gekko_blood_pool", ed, true, true)
end)
