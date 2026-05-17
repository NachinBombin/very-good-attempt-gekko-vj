-- ============================================================
-- FILE: lua/autorun/server/sv_gekko_bloodpool.lua
-- PURPOSE: Blood pool spawning for Gekko ragdolls.
-- SCOPE: Server autorun
-- NOTE: GetHitPhysBone is on the DMGINFO metatable, loaded by
--       gekko_juicy_bleeding.lua via extensions.lua (same file).
--       Both server autorun files load at the same time; hook
--       fires later, so the metatable extension is always ready.
-- ============================================================
if not SERVER then return end

-- Track the last-hit physics bone + local hit offset per Gekko NPC,
-- mirroring bloodpool_lastdmgbone / bloodpool_lastdmglpos in the
-- original addon.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    -- GetHitPhysBone defined by extensions.lua
    local mt = FindMetaTable("CTakeDamageInfo")
    if not mt or not mt.GetHitPhysBone then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    if not physBone or physBone < 0 then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone or bone < 0 then return end

    ent.gekko_pool_lastbone = bone

    local bonePos = ent:GetBonePosition(bone)
    if bonePos then
        -- FIX: angle_zero is a VJ Base global and is not guaranteed to exist
        -- in vanilla GMod. Use Angle(0,0,0) which is always available.
        ent.gekko_pool_lastlpos = WorldToLocal(
            dmginfo:GetDamagePosition(), Angle(0, 0, 0), bonePos, Angle(0, 0, 0)
        )
    end
end)

-- Called by death_pose_system.lua after prop_ragdoll is spawned
-- via the GekkoRagdollSpawned hook.
hook.Add("GekkoRagdollSpawned", "GekkoBloodPool_Spawn", function(npc, rag)
    if not IsValid(rag) then return end

    local bone = (IsValid(npc) and npc.gekko_pool_lastbone) or 0
    local lpos = (IsValid(npc) and npc.gekko_pool_lastlpos) or Vector(0, 0, 0)

    if CreateBloodPoolForRagdoll then
        -- Original addon present: use its PCF blood pool directly.
        timer.Simple(0.05, function()
            if not IsValid(rag) then return end
            CreateBloodPoolForRagdoll(rag, bone, lpos, BLOOD_COLOR_RED, 0)
        end)
    else
        -- Fallback: poll until ragdoll settles, then fire a PCF pool.
        local tname    = "gekko_bpool_" .. rag:EntIndex()
        local physBone = rag:TranslateBoneToPhysBone(bone)
        local phys     = rag:GetPhysicsObjectNum(physBone or 0)

        timer.Create(tname, 0.5, 0, function()
            if not IsValid(rag) or not IsValid(phys) then
                timer.Remove(tname)
                return
            end
            if phys:GetVelocity():LengthSqr() > 10 then return end
            timer.Remove(tname)
            ParticleEffect("blood_pool_MysterAC_v2",
                phys:LocalToWorld(lpos), Angle(0, 0, 0))
        end)
    end
end)
