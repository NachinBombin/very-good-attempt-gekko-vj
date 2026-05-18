-- ============================================================
-- lua/autorun/server/sv_gekko_bloodpool.lua
-- Gekko blood pool - server side.
--
-- FIX (2026): CreateBloodPoolForRagdoll / PCF path removed.
-- The original addon is not guaranteed to be loaded, and the
-- prop_ragdoll entity is not yet replicated to clients at the
-- moment GekkoRagdollSpawned fires (causing EFFECT:Init to
-- receive an invalid entity).
--
-- New path:
--   Server sends a net message (GekkoBloodPoolSpawn) with the
--   ragdoll EntIndex + bone ID 0.15 s after spawn.
--   Client receives it, polls Entity(idx) until valid (up to
--   2 s), then fires the local gekko_blood_pool effect.
-- ============================================================

if not SERVER then return end

util.AddNetworkString("GekkoBloodPoolSpawn")

local ZERO_ANG = Angle(0, 0, 0)

-- Track last hit bone per Gekko NPC while it is still alive.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    if not physBone or physBone < 0 then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone or bone < 0 then return end

    ent.gekko_pool_lastbone = bone
    local bonePos, boneAng = ent:GetBonePosition(bone)
    if isvector(bonePos) then
        ent.gekko_pool_lastlpos = WorldToLocal(
            dmginfo:GetDamagePosition(), ZERO_ANG, bonePos, boneAng or ZERO_ANG
        )
    end
end)

-- Fired by death_pose_system.lua after the prop_ragdoll is spawned.
hook.Add("GekkoRagdollSpawned", "GekkoBloodPool_Spawn", function(npc, rag)
    if not IsValid(rag) then return end

    local bone = (IsValid(npc) and npc.gekko_pool_lastbone) or 0

    -- Wait 0.15 s so the ragdoll entity has time to replicate to
    -- all connected clients before we tell them to use it.
    timer.Simple(0.15, function()
        if not IsValid(rag) then return end
        net.Start("GekkoBloodPoolSpawn")
            net.WriteUInt(rag:EntIndex(), 13)  -- 13 bits = 0-8191
            net.WriteUInt(bone,           7)   --  7 bits = 0-127
        net.Broadcast()
    end)
end)
