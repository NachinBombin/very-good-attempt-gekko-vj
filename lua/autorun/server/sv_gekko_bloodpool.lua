-- ============================================================
-- lua/autorun/server/sv_gekko_bloodpool.lua
-- Server side of the standalone Gekko blood pool system.
--
-- The Gekko spawns its ragdoll via ents.Create("prop_ragdoll")
-- inside GekkoDeath_SpawnRagdoll(), so the engine hook
-- CreateEntityRagdoll never fires.  Instead, death_pose_system.lua
-- calls hook.Run("GekkoRagdollSpawned", npc, rag) after spawning.
-- ============================================================

if not SERVER then return end

util.AddNetworkString("GekkoBloodPool")

-- Track the last hit bone per Gekko so the pool spawns under
-- the wound site rather than always at the spine.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    if not physBone or physBone < 0 then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone or bone < 0 then return end

    ent.gekko_pool_lastbone = bone
end)

-- Fired by death_pose_system.lua right after the prop_ragdoll is spawned.
hook.Add("GekkoRagdollSpawned", "GekkoBloodPool_Spawn", function(npc, rag)
    if not IsValid(rag) then return end

    -- Bone captured here while npc is still valid.
    local bone = (IsValid(npc) and npc.gekko_pool_lastbone)
               or rag:LookupBone("ValveBiped.Bip01_Spine")
               or 0

    -- Short delay lets the ragdoll physics settle from spawn.
    timer.Simple(0.1, function()
        if not IsValid(rag) then return end

        net.Start("GekkoBloodPool")
            net.WriteEntity(rag)
            net.WriteInt(bone, 16)
        net.Broadcast()
    end)
end)
