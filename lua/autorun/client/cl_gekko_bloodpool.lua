-- ============================================================
-- lua/autorun/client/cl_gekko_bloodpool.lua
-- Client-side receiver for GekkoBloodPoolSpawn net message.
--
-- Polls Entity(entIndex) until the ragdoll is valid, then
-- fires the gekko_blood_pool EFFECT so EFFECT:Init always
-- receives a properly replicated entity.
-- ============================================================

if SERVER then return end

local POLL_INTERVAL = 0.05   -- seconds between validity checks
local POLL_TIMEOUT  = 2.0    -- give up after this many seconds

net.Receive("GekkoBloodPoolSpawn", function()
    local entIndex = net.ReadUInt(13)
    local bone     = net.ReadUInt(7)

    local elapsed = 0
    timer.Create("GekkoBloodPool_Wait_" .. entIndex .. "_" .. CurTime(), POLL_INTERVAL, 0, function()
        elapsed = elapsed + POLL_INTERVAL

        local rag = Entity(entIndex)
        local valid = IsValid(rag) and rag:GetModel() ~= nil and rag:GetModel() ~= ""

        if valid then
            timer.Remove("GekkoBloodPool_Wait_" .. entIndex .. "_" .. tostring(math.floor((CurTime() - elapsed) * 100) / 100))
            -- Fire the effect now that the entity is real on this client.
            local ed = EffectData()
            ed:SetEntity(rag)
            ed:SetAttachment(bone)
            ed:SetFlags(0)
            util.Effect("gekko_blood_pool", ed, true, true)
        elseif elapsed >= POLL_TIMEOUT then
            timer.Remove("GekkoBloodPool_Wait_" .. entIndex .. "_" .. tostring(math.floor((CurTime() - elapsed) * 100) / 100))
        end
    end)
end)
