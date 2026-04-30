-- ============================================================
-- lua/autorun/client/cl_gekko_bloodpool.lua
-- Client side of the standalone Gekko blood pool system.
--
-- Receives the net message from sv_gekko_bloodpool.lua and
-- fires the gekko_blood_pool effect on the ragdoll.
-- ============================================================

if not CLIENT then return end

net.Receive("GekkoBloodPool", function()
    local rag  = net.ReadEntity()
    local bone = net.ReadInt(16)

    -- Entity might not be valid yet on the client side.
    -- Retry a few times with a short delay if needed.
    local attempts = 0
    local function TrySpawnPool()
        attempts = attempts + 1
        if IsValid(rag) then
            local ed = EffectData()
            ed:SetEntity(rag)
            ed:SetAttachment(bone)
            ed:SetColor(BLOOD_COLOR_RED)
            ed:SetFlags(0)
            util.Effect("gekko_blood_pool", ed, true, true)
        elseif attempts < 10 then
            timer.Simple(0.1, TrySpawnPool)
        end
    end

    TrySpawnPool()
end)
