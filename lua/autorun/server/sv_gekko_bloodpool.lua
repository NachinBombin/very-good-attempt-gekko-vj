-- ============================================================
-- lua/autorun/server/sv_gekko_bloodpool.lua
-- Gekko blood pool - server side.
--
-- The original addon's blood pools come from PCF particle
-- effects ("blood_pool_MysterAC_v2" etc.) fired via
-- ParticleEffect() inside CreateBloodPoolForRagdoll().
-- The blood_pool.lua EFFECT file is a secondary fallback system.
--
-- We call CreateBloodPoolForRagdoll() directly so the Gekko
-- gets the exact same PCF pool visuals as any other NPC.
-- ============================================================

if not SERVER then return end

-- Track last hit bone + local hit position per Gekko,
-- mirroring the original addon's bloodpool_lastdmgbone /
-- bloodpool_lastdmglpos approach.
hook.Add("EntityTakeDamage", "GekkoBloodPool_TrackBone", function(ent, dmginfo)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end

    local physBone = dmginfo:GetHitPhysBone(ent)
    if not physBone or physBone < 0 then return end

    local bone = ent:TranslatePhysBoneToBone(physBone)
    if not bone or bone < 0 then return end

    ent.gekko_pool_lastbone = bone
    -- Local-space offset of hit position relative to the bone
    -- (same as bloodpool_lastdmglpos in the original addon)
    local bonePos = ent:GetBonePosition(bone)
    if bonePos then
        ent.gekko_pool_lastlpos = WorldToLocal(
            dmginfo:GetDamagePosition(), angle_zero, bonePos, angle_zero
        )
    end
end)

-- Fired by death_pose_system.lua after the prop_ragdoll is spawned.
hook.Add("GekkoRagdollSpawned", "GekkoBloodPool_Spawn", function(npc, rag)
    if not IsValid(rag) then return end

    -- Bone + local hit pos captured while npc may still be valid.
    local bone = (IsValid(npc) and npc.gekko_pool_lastbone) or 0
    local lpos = (IsValid(npc) and npc.gekko_pool_lastlpos) or Vector(0, 0, 0)

    -- Call the original addon's function directly so the pool uses
    -- the exact same PCF particles (blood_pool_MysterAC_v2 etc.)
    -- and settling logic as every other NPC in the game.
    if CreateBloodPoolForRagdoll then
        timer.Simple(0.05, function()
            if not IsValid(rag) then return end
            CreateBloodPoolForRagdoll(rag, bone, lpos, BLOOD_COLOR_RED, 0)
        end)
    else
        -- Fallback if original addon is not loaded: wait for ragdoll
        -- to settle then fire the first available PCF pool effect.
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
                phys:LocalToWorld(lpos), angle_zero)
        end)
    end
end)
