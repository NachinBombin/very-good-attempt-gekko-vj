-- ============================================================
-- lua/autorun/server/sv_gekko_bloodpool.lua
-- Server side of the standalone Gekko blood pool system.
--
-- Watches for gekko ragdoll creation, broadcasts a net message
-- so clients can fire the gekko_blood_pool effect.
-- ============================================================

if not SERVER then return end

util.AddNetworkString("GekkoBloodPool")

-- Track the last hit bone per Gekko so the pool spawns at the
-- wound site instead of always at the spine.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    if not physBone then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone then return end

    ent.gekko_pool_lastbone = bone
end)

hook.Add("CreateEntityRagdoll", "GekkoBloodPool_Spawn", function(ent, rag)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    -- Short delay: gives the ragdoll time to fully initialize.
    timer.Simple(0.1, function()
        if not IsValid(rag) then return end

        -- Use the last damaged bone; fall back to spine, then root.
        local bone = ent.gekko_pool_lastbone
        if not bone then
            bone = rag:LookupBone("ValveBiped.Bip01_Spine")
        end
        if not bone then bone = 0 end

        net.Start("GekkoBloodPool")
            net.WriteEntity(rag)
            net.WriteInt(bone, 16)
        net.Broadcast()
    end)
end)
