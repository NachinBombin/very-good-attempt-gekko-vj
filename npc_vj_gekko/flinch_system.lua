-- ============================================================
--  npc_vj_gekko / flinch_system.lua
--  Procedural, damage-scaled flinch system.
--
--  DESIGN PRINCIPLES:
--    - Zero model sequences used. Pure ManipulateBoneAngles / ManipulateBonePosition.
--    - Damage magnitude drives: duration, peak angle scale, number of bones involved,
--      and whether a secondary "stagger" wave fires after the primary.
--    - Every trigger produces a unique pose: all keyframe angles are re-randomised
--      per hit using a wide jitter envelope.
--    - Hitgroup steers the primary bone and lean direction but adds noise so the
--      result never looks scripted.
--    - Respects the hip-mutex (ClaimHips/ReleaseHips) so flinch cannot fight
--      active attack drivers.
--    - Server side: wired into OnTakeDamage via SetNWInt pulse pattern.
--    - Client side: GekkoFlinch_Think() called from the main Think hook.
-- ============================================================

-- ============================================================
--  SHARED CONSTANTS  (loaded on both realms via shared.lua include)
-- ============================================================
GEKKO_FLINCH_NET = "GekkoFlinchPulse"

-- ============================================================
--  SERVER
-- ============================================================
if SERVER then

-- Minimum seconds between flinch triggers (per NPC).
local FLINCH_COOLDOWN_MIN  = 0.08
-- At this damage value the flinch is considered "heavy".
local FLINCH_HEAVY_DMG     = 60
-- At this damage value the flinch is considered "critical" (adds stagger wave).
local FLINCH_CRIT_DMG      = 150
-- Damage types that should NOT trigger flinch.
local FLINCH_BANNED_DTYPE  = {
    [DMG_BURN]         = true,
    [DMG_SLOWBURN]     = true,
    [DMG_FALL]         = true,
    [DMG_RADIATION]    = true,
    [DMG_PARALYZE]     = true,
    [DMG_POISON]       = true,
    [DMG_DROWN]        = true,
    [DMG_DROWNRECOVER] = true,
    [DMG_NERVEGAS]     = true,
}

-- Encode hitgroup + damage tier + pulse into one NWInt.
-- Bits:  [0..3] hitgroup  [4..5] tier(0-2)  [6..23] pulse counter
local function EncodeFlinch(pulse, hitgroup, tier)
    return (pulse * 64) + (tier * 16) + math.Clamp(hitgroup, 0, 15)
end

function GekkoFlinch_OnDamage(ent, dmginfo)
    if not IsValid(ent) then return end
    -- Cooldown gate
    local now = CurTime()
    if now < (ent._flinchNextT or 0) then return end
    -- Damage type filter
    if FLINCH_BANNED_DTYPE[dmginfo:GetDamageType()] then return end
    local dmg     = dmginfo:GetDamage()
    if dmg <= 0 then return end
    -- Tier
    local tier
    if     dmg >= FLINCH_CRIT_DMG  then tier = 2
    elseif dmg >= FLINCH_HEAVY_DMG then tier = 1
    else                                 tier = 0 end
    -- Cooldown scales with tier (light hits can stack faster)
    local cd = FLINCH_COOLDOWN_MIN * (1 + tier * 0.6)
    ent._flinchNextT = now + cd
    -- Pulse counter (wraps at a large prime to avoid zero-reset ambiguity)
    ent._flinchPulse = ((ent._flinchPulse or 0) + 1) % 32749
    if ent._flinchPulse == 0 then ent._flinchPulse = 1 end
    local hitgroup = dmginfo:GetHitGroup and dmginfo:GetHitGroup() or HITGROUP_GENERIC
    ent:SetNWInt(GEKKO_FLINCH_NET, EncodeFlinch(ent._flinchPulse, hitgroup, tier))
end

end -- SERVER

-- ============================================================
--  CLIENT
-- ============================================================
if CLIENT then

-- ------------------------------------------------------------
--  Bone names on the Gekko model
-- ------------------------------------------------------------
local BONE_PELVIS   = "b_pelvis"
local BONE_PEDESTAL = "b_pedestal"
local BONE_SPINE    = "b_spine3"
local BONE_LHIP     = "b_l_hippiston1"
local BONE_RHIP     = "b_r_hippiston1"
local BONE_LULEG    = "b_l_upperleg"
local BONE_RULEG    = "b_r_upperleg"

-- ------------------------------------------------------------
--  Decode helpers
-- ------------------------------------------------------------
local function DecodeHitgroup(packed)  return packed % 16          end
local function DecodeTier(packed)      return math.floor(packed / 16) % 4 end
local function DecodePulse(packed)     return math.floor(packed / 64) end

-- ------------------------------------------------------------
--  Random helpers
-- ------------------------------------------------------------
local function RandS(mag)   return (math.random() - 0.5) * 2 * mag end
local function RandU(a, b)  return a + math.random() * (b - a)     end
local function RandSAngle(p, y, r)
    return Angle(RandS(p), RandS(y), RandS(r))
end

-- Heavy jitter: every angle axis gets an independent random multiplier
-- so no two flinches ever look the same.
local function JitterAngle(base, jMag)
    return Angle(
        base.p * RandU(0.55, 1.45) + RandS(jMag),
        base.y * RandU(0.55, 1.45) + RandS(jMag),
        base.r * RandU(0.55, 1.45) + RandS(jMag)
    )
end

local function LerpAngle(a, b, t)
    return Angle(
        Lerp(t, a.p, b.p),
        Lerp(t, a.y, b.y),
        Lerp(t, a.r, b.r)
    )
end

local function Smoothstep(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function Smoothstep2(t)  -- double-smoothstep for snappier return
    return Smoothstep(Smoothstep(t))
end

-- ------------------------------------------------------------
--  Per-tier configuration tables
--  All angles are BASE values; jitter is applied at trigger time.
-- ------------------------------------------------------------

-- Hitgroup → primary lean direction (Angle: pitch = fwd/back, yaw = twist, roll = side)
local HitgroupLean = {
    [HITGROUP_HEAD]     = Angle(-28,  0,   0),   -- head snaps forward
    [HITGROUP_CHEST]    = Angle( 18,  0,   0),   -- chest pushed back
    [HITGROUP_STOMACH]  = Angle( 22,  0,   0),   -- gut recoil back
    [HITGROUP_LEFTARM]  = Angle(  8,  0,  22),   -- left side lean
    [HITGROUP_RIGHTARM] = Angle(  8,  0, -22),   -- right side lean
    [HITGROUP_LEFTLEG]  = Angle( 12,  8,  15),   -- left weight shift
    [HITGROUP_RIGHTLEG] = Angle( 12, -8, -15),   -- right weight shift
    [HITGROUP_GENERIC]  = Angle( 15,  0,   0),   -- generic back-push
}

local TierCfg = {
    -- tier 0: light hit
    [0] = {
        durationBase  = 0.28,
        durationJit   = 0.12,   -- random subtracted from base
        spineLeanMul  = 0.70,   -- scale applied to lean angle
        spineJitMag   = 14,     -- ± degrees random noise per axis on spine
        pelvisJitMag  = 8,
        hipJitMag     = 10,
        pedJitMag     = 6,
        ulegJitMag    = 8,
        pelvisBobZ    = 0,      -- vertical pelvis bob (units)
        hipPitchMin   = 8,
        hipPitchMax   = 22,
        stagger       = false,  -- no secondary stagger wave
        bonesInvolved = 2,      -- spine + 1 hip only
    },
    -- tier 1: heavy hit
    [1] = {
        durationBase  = 0.48,
        durationJit   = 0.18,
        spineLeanMul  = 1.20,
        spineJitMag   = 22,
        pelvisJitMag  = 14,
        hipJitMag     = 18,
        pedJitMag     = 12,
        ulegJitMag    = 14,
        pelvisBobZ    = RandU(8, 22),
        hipPitchMin   = 18,
        hipPitchMax   = 42,
        stagger       = false,
        bonesInvolved = 4,      -- spine, pelvis, both hips
    },
    -- tier 2: critical hit
    [2] = {
        durationBase  = 0.72,
        durationJit   = 0.22,
        spineLeanMul  = 1.85,
        spineJitMag   = 34,
        pelvisJitMag  = 22,
        hipJitMag     = 28,
        pedJitMag     = 18,
        ulegJitMag    = 22,
        pelvisBobZ    = RandU(18, 48),
        hipPitchMin   = 30,
        hipPitchMax   = 68,
        stagger       = true,   -- secondary stagger wave fires after primary
        bonesInvolved = 6,      -- all bones including upperlegs + pedestal
    },
}

-- ------------------------------------------------------------
--  Build a randomised flinch keyframe set from tier + hitgroup
-- ------------------------------------------------------------
local function BuildFlinchKeys(tier, hitgroup)
    local cfg  = TierCfg[tier] or TierCfg[0]
    local lean = HitgroupLean[hitgroup] or HitgroupLean[HITGROUP_GENERIC]

    -- Duration with random trim
    local dur = cfg.durationBase - math.random() * cfg.durationJit

    -- Spine peak: lean direction scaled by tier multiplier + full-axis jitter
    local spineBase = Angle(
        lean.p * cfg.spineLeanMul,
        lean.y * cfg.spineLeanMul * RandU(0.4, 1.6),
        lean.r * cfg.spineLeanMul * RandU(0.4, 1.6)
    )
    local spinePeak = JitterAngle(spineBase, cfg.spineJitMag)

    -- Pelvis: small random offset, driven by tier
    local pelvisPeak = RandSAngle(cfg.pelvisJitMag, cfg.pelvisJitMag * 0.5, cfg.pelvisJitMag * 0.3)
    local pelvisBobZ = cfg.pelvisBobZ * RandU(0.6, 1.4) * ((math.random() > 0.5) and 1 or -1)

    -- Pedestal: mild compensatory twist
    local pedPeak = RandSAngle(cfg.pedJitMag * 0.4, cfg.pedJitMag, cfg.pedJitMag * 0.6)

    -- Hip pistons: which side reacts more depends on hitgroup
    local lhipSign = (hitgroup == HITGROUP_RIGHTARM or hitgroup == HITGROUP_RIGHTLEG) and 0.35 or 1.0
    local rhipSign = (hitgroup == HITGROUP_LEFTARM  or hitgroup == HITGROUP_LEFTLEG)  and 0.35 or 1.0
    local hipPitch = RandU(cfg.hipPitchMin, cfg.hipPitchMax)
    local lhipPeak = Angle(
        hipPitch * lhipSign * RandU(0.7, 1.3),
        RandS(cfg.hipJitMag * 0.5),
        RandS(cfg.hipJitMag * 0.4)
    )
    local rhipPeak = Angle(
        -hipPitch * rhipSign * RandU(0.7, 1.3),
        RandS(cfg.hipJitMag * 0.5),
        RandS(cfg.hipJitMag * 0.4)
    )

    -- Upper legs: small sympathetic kick
    local lulegPeak = RandSAngle(cfg.ulegJitMag * 0.5, cfg.ulegJitMag * 0.3, cfg.ulegJitMag * 0.2)
    local rulegPeak = RandSAngle(cfg.ulegJitMag * 0.5, cfg.ulegJitMag * 0.3, cfg.ulegJitMag * 0.2)

    -- Phase envelope fractions (normalised 0-1)
    -- impact: 0 → peakFrac  (fast snap in)
    -- decay:  peakFrac → 1  (smooth settle)
    local peakFrac = RandU(0.18, 0.38)   -- how quickly the peak is reached

    return {
        dur       = dur,
        peakFrac  = peakFrac,
        spine     = spinePeak,
        pelvis    = pelvisPeak,
        pelvisBobZ = pelvisBobZ,
        pedestal  = pedPeak,
        lhip      = lhipPeak,
        rhip      = rhipPeak,
        luleg     = lulegPeak,
        ruleg     = rulegPeak,
        bones     = cfg.bonesInvolved,
        stagger   = cfg.stagger,
    }
end

-- ------------------------------------------------------------
--  Build a secondary stagger keyframe (critical hits only)
--  Intentionally counter-directional to the primary.
-- ------------------------------------------------------------
local function BuildStaggerKeys(primary)
    local dur = RandU(0.20, 0.38)
    -- Stagger opposes the primary spine lean
    local spineStagger = Angle(
        -primary.spine.p * RandU(0.3, 0.6) + RandS(18),
        -primary.spine.y * RandU(0.2, 0.5) + RandS(12),
        -primary.spine.r * RandU(0.2, 0.5) + RandS(10)
    )
    local pelStagger = RandSAngle(10, 6, 4)
    local peakFrac   = RandU(0.20, 0.42)
    return {
        dur      = dur,
        peakFrac = peakFrac,
        spine    = spineStagger,
        pelvis   = pelStagger,
        pelvisBobZ = primary.pelvisBobZ * RandU(-0.4, 0.4),
        pedestal = RandSAngle(6, 8, 4),
        lhip     = RandSAngle(12, 6, 4),
        rhip     = RandSAngle(12, 6, 4),
        luleg    = RandSAngle(6, 3, 2),
        ruleg    = RandSAngle(6, 3, 2),
        bones    = math.max(primary.bones - 1, 2),
        stagger  = false,
    }
end

-- ------------------------------------------------------------
--  Apply one keyframe set at envelope value env (0→1→0)
-- ------------------------------------------------------------
local ZERO_ANG = Angle(0,0,0)
local ZERO_VEC = Vector(0,0,0)

local function ApplyKeys(ent, keys, env, state)
    local spine  = state.spineIdx
    local pelvis = state.pelvisIdx
    local ped    = state.pedestalIdx
    local lhip   = state.lhipIdx
    local rhip   = state.rhipIdx
    local luleg  = state.lulegIdx
    local ruleg  = state.rulegIdx

    local bones = keys.bones

    -- Spine (always)
    if spine >= 0 then
        ent:ManipulateBoneAngles(spine, LerpAngle(ZERO_ANG, keys.spine, env), false)
    end

    if bones >= 2 then
        -- One hip side (primary)
        if lhip >= 0 then
            ent:ManipulateBoneAngles(lhip, LerpAngle(ZERO_ANG, keys.lhip, env), false)
        end
    end

    if bones >= 3 then
        if rhip >= 0 then
            ent:ManipulateBoneAngles(rhip, LerpAngle(ZERO_ANG, keys.rhip, env), false)
        end
    end

    if bones >= 4 then
        if pelvis >= 0 then
            ent:ManipulateBoneAngles(pelvis,   LerpAngle(ZERO_ANG, keys.pelvis, env), false)
            ent:ManipulateBonePosition(pelvis, Vector(0, 0, keys.pelvisBobZ * env), false)
        end
    end

    if bones >= 5 then
        if ped >= 0 then
            ent:ManipulateBoneAngles(ped, LerpAngle(ZERO_ANG, keys.pedestal, env), false)
        end
    end

    if bones >= 6 then
        if luleg >= 0 then
            ent:ManipulateBoneAngles(luleg, LerpAngle(ZERO_ANG, keys.luleg, env), false)
        end
        if ruleg >= 0 then
            ent:ManipulateBoneAngles(ruleg, LerpAngle(ZERO_ANG, keys.ruleg, env), false)
        end
    end
end

local function ResetBones(ent, state)
    local spine  = state.spineIdx
    local pelvis = state.pelvisIdx
    local ped    = state.pedestalIdx
    local lhip   = state.lhipIdx
    local rhip   = state.rhipIdx
    local luleg  = state.lulegIdx
    local ruleg  = state.rulegIdx

    if spine  >= 0 then ent:ManipulateBoneAngles(spine,   ZERO_ANG, false) end
    if pelvis >= 0 then
        ent:ManipulateBoneAngles(pelvis,   ZERO_ANG, false)
        ent:ManipulateBonePosition(pelvis, ZERO_VEC, false)
    end
    if ped    >= 0 then ent:ManipulateBoneAngles(ped,     ZERO_ANG, false) end
    if lhip   >= 0 then ent:ManipulateBoneAngles(lhip,   ZERO_ANG, false) end
    if rhip   >= 0 then ent:ManipulateBoneAngles(rhip,   ZERO_ANG, false) end
    if luleg  >= 0 then ent:ManipulateBoneAngles(luleg,  ZERO_ANG, false) end
    if ruleg  >= 0 then ent:ManipulateBoneAngles(ruleg,  ZERO_ANG, false) end
end

-- ------------------------------------------------------------
--  Main per-entity Think driver
--  Call from the cl_init.lua Think hook for every valid Gekko.
-- ------------------------------------------------------------
function GekkoFlinch_Think(ent)
    -- One-time init
    if not ent._flinchInited then
        ent._flinchInited   = true
        ent._flinchState    = {
            spineIdx    = ent:LookupBone(BONE_SPINE)    or -1,
            pelvisIdx   = ent:LookupBone(BONE_PELVIS)   or -1,
            pedestalIdx = ent:LookupBone(BONE_PEDESTAL) or -1,
            lhipIdx     = ent:LookupBone(BONE_LHIP)     or -1,
            rhipIdx     = ent:LookupBone(BONE_RHIP)     or -1,
            lulegIdx    = ent:LookupBone(BONE_LULEG)    or -1,
            rulegIdx    = ent:LookupBone(BONE_RULEG)    or -1,
        }
        ent._flinchPulseLast   = 0
        ent._flinchActive      = false
        ent._flinchPhase       = "NONE"   -- "PRIMARY" | "STAGGER" | "NONE"
        ent._flinchKeys        = nil
        ent._flinchStaggerKeys = nil
        ent._flinchStart       = 0
    end

    local state = ent._flinchState
    local packed = ent:GetNWInt(GEKKO_FLINCH_NET, 0)

    -- Edge-trigger: new pulse detected
    local pulse = DecodePulse(packed)
    if pulse ~= ent._flinchPulseLast and pulse ~= 0 then
        ent._flinchPulseLast = pulse
        local hitgroup = DecodeHitgroup(packed)
        local tier     = DecodeTier(packed)

        -- Build randomised keyframes for this hit
        local keys = BuildFlinchKeys(tier, hitgroup)

        ent._flinchKeys        = keys
        ent._flinchStaggerKeys = keys.stagger and BuildStaggerKeys(keys) or nil
        ent._flinchStart       = CurTime()
        ent._flinchPhase       = "PRIMARY"
        ent._flinchActive      = true

        -- Try to claim hips; if another driver owns them we still animate
        -- spine + pelvis (the mutex only blocks hip piston writes)
        ent._flinchHipsClaimed = ClaimHips and ClaimHips(ent, "FLINCH") or true
    end

    if not ent._flinchActive then return end

    local now     = CurTime()
    local elapsed = now - ent._flinchStart
    local phase   = ent._flinchPhase

    -- --------------------------------------------------------
    --  PRIMARY phase
    -- --------------------------------------------------------
    if phase == "PRIMARY" then
        local keys = ent._flinchKeys
        local dur  = keys.dur
        if elapsed >= dur then
            -- Transition: stagger or done
            ResetBones(ent, state)
            if ent._flinchStaggerKeys then
                ent._flinchPhase = "STAGGER"
                ent._flinchStart = now
            else
                ent._flinchPhase  = "NONE"
                ent._flinchActive = false
                if ReleaseHips then ReleaseHips(ent, "FLINCH") end
            end
            return
        end

        local t   = elapsed / dur
        local pf  = keys.peakFrac
        local env
        if t < pf then
            -- Fast snap in: Smoothstep2 for extra sharpness
            env = Smoothstep2(t / pf)
        else
            -- Slower settle out: Smoothstep
            env = Smoothstep(1 - (t - pf) / (1 - pf))
        end

        -- Only write hip bones if we claimed them
        local writeKeys = keys
        if not ent._flinchHipsClaimed then
            writeKeys = table.Copy(keys)
            writeKeys.bones = math.min(writeKeys.bones, 1)
        end
        ApplyKeys(ent, writeKeys, env, state)
        return
    end

    -- --------------------------------------------------------
    --  STAGGER phase  (critical hits only)
    -- --------------------------------------------------------
    if phase == "STAGGER" then
        local keys = ent._flinchStaggerKeys
        local dur  = keys.dur
        if elapsed >= dur then
            ResetBones(ent, state)
            ent._flinchPhase  = "NONE"
            ent._flinchActive = false
            if ReleaseHips then ReleaseHips(ent, "FLINCH") end
            return
        end

        local t   = elapsed / dur
        local pf  = keys.peakFrac
        local env
        if t < pf then
            env = Smoothstep2(t / pf)
        else
            env = Smoothstep(1 - (t - pf) / (1 - pf))
        end
        ApplyKeys(ent, keys, env, state)
    end
end

end -- CLIENT
