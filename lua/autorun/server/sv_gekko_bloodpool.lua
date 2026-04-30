-- ============================================================
-- lua/autorun/server/sv_gekko_bloodpool.lua
-- Server side of the standalone Gekko blood pool system.
-- ============================================================

if not SERVER then return end

util.AddNetworkString("GekkoBloodPool")

-- Track the last hit bone per Gekko so the pool spawns under
-- the wound site rather than always at the spine.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    -- GetHitPhysBone returns -1 when no phys-bone data is available.
    if not physBone or physBone < 0 then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone or bone < 0 then return end

    ent.gekko_pool_lastbone = bone
end)

hook.Add("CreateEntityRagdoll", "GekkoBloodPool_Spawn", function(ent, rag)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    -- Capture bone NOW — ent may be invalid inside the timer closure.
    local bone = ent.gekko_pool_lastbone
    if not bone then
        -- Fall back to spine bone on the ragdoll (same model, same indices).
        bone = rag:LookupBone("ValveBiped.Bip01_Spine") or 0
    end

    -- Short delay gives the ragdoll physics time to fully initialize.
    timer.Simple(0.1, function()
        if not IsValid(rag) then return end

        net.Start("GekkoBloodPool")
            net.WriteEntity(rag)
            net.WriteInt(bone, 16)
        net.Broadcast()
    end)
end)
