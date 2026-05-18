-- ============================================================
-- lua/autorun/server/sv_gekko_bloodpool.lua
-- Sends GekkoBloodPoolSpawn net message to all clients after
-- the Gekko ragdoll is spawned.
--
-- Delayed 0.3 s so the prop_ragdoll entity has time to
-- replicate to clients before the effect tries to reference it.
-- util.Effect must NOT be called server-side for this effect --
-- the engine would serialize the NPC entity index, not the
-- ragdoll, and clients would receive the wrong entity.
-- ============================================================
if not SERVER then return end

util.AddNetworkString("GekkoBloodPoolSpawn")

hook.Add("GekkoRagdollSpawned", "GekkoBloodPool_Send", function(npc, rag)
    if not IsValid(rag) then return end

    local bone = (IsValid(npc) and npc.gekko_pool_lastbone) or 0
    local ragIndex = rag:EntIndex()

    timer.Simple(0.3, function()
        -- Re-validate: ragdoll might have been removed in 0.3 s
        local r = Entity(ragIndex)
        if not IsValid(r) then return end

        net.Start("GekkoBloodPoolSpawn")
            net.WriteUInt(ragIndex, 13)
            net.WriteUInt(bone,     7)
        net.Broadcast()
    end)
end)

-- Track the most-recently-hit bone on the living NPC so the
-- pool appears at the right location after death.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    if not physBone or physBone < 0 then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone or bone < 0 then return end

    ent.gekko_pool_lastbone = bone
end)
