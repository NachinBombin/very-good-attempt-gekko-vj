-- ============================================================
--  npc_vj_gekko / ragdoll_system.lua
--
--  Correct approach:
--    VJ Base exposes VJ_CreateRagdoll(npc, dmginfo, options)
--    which internally calls the engine's CreateRagdoll on the
--    live NPC entity -- this is the ONLY way to get a ragdoll
--    that inherits the NPC's current animated bone pose.  Any
--    approach that manually creates a prop_ragdoll from scratch
--    will spawn in the model bind/T-pose regardless.
--
--    After VJ_CreateRagdoll returns the ragdoll entity we:
--      1. Override per-bone mass so the mech feels heavy.
--      2. Apply safe-magnitude impulses for the hit direction,
--         head whip, and hip splay.
--      3. Register a timed alpha-fade for cleanup.
--
--  Impulse safety rule (Source/Havok hard limit):
--    ApplyForceCenter takes kg*units/s^2 (force, not impulse).
--    Anything above ~50 000 on a single bone per tick will
--    cause a physics assertion / CTD.  All values here are
--    deliberately kept under 40 000 per bone.
--
--  API
--    ENT:GekkoRagdoll_OnDeath(dmginfo)   -- call from OnDeath
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Tuning
-- ─────────────────────────────────────────────────────────────
local RAGDOLL_FADE_TIME  = 30   -- seconds until ragdoll is removed
local RAGDOLL_FADE_START = 26   -- seconds until alpha-fade begins

-- Base mass (kg) for bones not in BONE_MASS.
local BASE_MASS = 120

local BONE_MASS = {
    b_pedestal         = 300,
    b_pelvis           = 260,
    b_spine1           = 180,
    b_spine2           = 160,
    b_spine3           = 140,
    b_spine4           = 120,
    b_l_hippiston1     = 200,
    b_r_hippiston1     = 200,
    b_l_thigh          = 160,
    b_r_thigh          = 160,
    b_l_upperleg       = 120,
    b_r_upperleg       = 120,
    b_l_calf           = 90,
    b_r_calf           = 90,
    b_l_foot           = 60,
    b_r_foot           = 60,
    b_l_toe            = 25,
    b_r_toe            = 25,
    b_l_pinky_toe1     = 15,
    b_r_pinky_toe1     = 15,
    b_l_shoulder       = 80,
    b_r_shoulder       = 80,
    b_l_upperarm       = 70,
    b_r_upperarm       = 70,
    b_l_forearm        = 55,
    b_r_forearm        = 55,
    b_l_hand           = 35,
    b_r_hand           = 35,
}

-- Physics feel
local LINEAR_DAMPING   = 0.5
local ANGULAR_DAMPING  = 2.5

-- Whole-body death push (kg*units/s, spread across all bones).
-- Keep per-bone value well under 40 000.
local DEATH_PUSH_TOTAL = 18000  -- divided by physBoneCount at runtime

-- Head-whip: forward + downward kick on b_spine4
local HEAD_BONE          = "b_spine4"
local HEAD_FORCE_FWD     = 12000
local HEAD_FORCE_DOWN    = 8000

-- Hip splay: push each hip outward so legs don't fold inward
local HIP_L_BONE         = "b_l_hippiston1"
local HIP_R_BONE         = "b_r_hippiston1"
local HIP_FORCE_LATERAL  = 6000
local HIP_FORCE_DOWN     = 2500

-- ─────────────────────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────────────────────

local function ConfigurePhysics(ragdoll)
    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if not IsValid(phys) then continue end
        local name = ragdoll:GetBoneName(i) or ""
        phys:SetMass(BONE_MASS[name] or BASE_MASS)
        phys:SetDamping(LINEAR_DAMPING, ANGULAR_DAMPING)
        phys:EnableGravity(true)
        phys:EnableDrag(false)
        phys:Wake()
    end
end

local function FindPhysByBone(ragdoll, boneName)
    local count = ragdoll:GetPhysicsObjectCount()
    for i = 0, count - 1 do
        if (ragdoll:GetBoneName(i) or "") == boneName then
            return ragdoll:GetPhysicsObjectNum(i)
        end
    end
end

local function SafeImpulse(ragdoll, boneName, vec)
    local phys = FindPhysByBone(ragdoll, boneName)
    if IsValid(phys) then
        phys:ApplyForceCenter(vec)
    end
end

local function RegisterFade(ragdoll)
    local key = "GekkoRagdollFade_" .. ragdoll:EntIndex()
    timer.Simple(RAGDOLL_FADE_START, function()
        if not IsValid(ragdoll) then return end
        local fadeLen = RAGDOLL_FADE_TIME - RAGDOLL_FADE_START
        local startT  = CurTime()
        hook.Add("Think", key, function()
            if not IsValid(ragdoll) then hook.Remove("Think", key) return end
            local t = math.Clamp((CurTime() - startT) / fadeLen, 0, 1)
            ragdoll:SetColor(Color(255, 255, 255, math.floor(255 * (1 - t))))
            ragdoll:SetRenderMode(RENDERMODE_TRANSALPHA)
            if t >= 1 then ragdoll:Remove() hook.Remove("Think", key) end
        end)
    end)
    timer.Simple(RAGDOLL_FADE_TIME, function()
        if IsValid(ragdoll) then ragdoll:Remove() end
    end)
end

-- ─────────────────────────────────────────────────────────────
--  ENT:GekkoRagdoll_OnDeath(dmginfo)
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoRagdoll_OnDeath(dmginfo)

    -- Capture orientation before anything mutates state
    local deathAng  = self:GetAngles()
    local fwd       = deathAng:Forward()
    local right     = deathAng:Right()
    local deathVel  = self:GetVelocity()

    local dmgForce  = dmginfo and dmginfo:GetDamageForce() or Vector(0, 0, 0)
    local pushDir   = (dmgForce:LengthSqr() > 1) and dmgForce:GetNormalized()
                      or (fwd * -1)  -- fallback: push backward

    -- ── Use VJ_CreateRagdoll ──────────────────────────────────
    -- This is the VJ Base function that calls the engine's own
    -- CreateRagdoll on the live NPC, transferring the current
    -- animated bone pose into the ragdoll.  It is the only
    -- correct way to avoid the bind-pose / T-pose problem.
    --
    -- Signature (VJ Base source, npc_vj_creature_base/init.lua):
    --   VJ_CreateRagdoll(npc, dmginfo, extraVelocity, dontSetPos)
    --   returns the ragdoll entity
    --
    -- We pass Vector(0,0,0) for extraVelocity and let VJ handle
    -- the initial velocity copy; we'll add our own impulses after.
    local ragdoll = nil
    if VJ_CreateRagdoll then
        ragdoll = VJ_CreateRagdoll(self, dmginfo, Vector(0, 0, 0), false)
    end

    -- Fallback: if VJ_CreateRagdoll is unavailable (shouldn't
    -- happen but defensive) try the engine method directly.
    if not IsValid(ragdoll) then
        ragdoll = self:BecomeRagdollOnClient()
    end

    if not IsValid(ragdoll) then
        print("[GekkoRagdoll] ERROR: could not create ragdoll")
        return
    end

    -- ── Configure physics ─────────────────────────────────────
    ConfigurePhysics(ragdoll)

    local physCount = ragdoll:GetPhysicsObjectCount()
    if physCount < 1 then
        print("[GekkoRagdoll] WARNING: ragdoll has no physics bones")
        RegisterFade(ragdoll)
        return
    end

    -- ── Per-bone death push (safe magnitude) ──────────────────
    -- Divide total desired push across all bones so no single
    -- bone exceeds the Havok safety threshold.
    local perBoneForce = math.min(DEATH_PUSH_TOTAL / physCount, 35000)
    for i = 0, physCount - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            -- Inherit NPC velocity
            phys:SetVelocity(deathVel)
            -- Death direction push
            phys:ApplyForceCenter(pushDir * perBoneForce)
        end
    end

    -- ── Head whip ─────────────────────────────────────────────
    SafeImpulse(ragdoll, HEAD_BONE,
        fwd * HEAD_FORCE_FWD + Vector(0, 0, -HEAD_FORCE_DOWN)
    )

    -- ── Hip splay ─────────────────────────────────────────────
    SafeImpulse(ragdoll, HIP_L_BONE,
         right * HIP_FORCE_LATERAL + Vector(0, 0, -HIP_FORCE_DOWN)
    )
    SafeImpulse(ragdoll, HIP_R_BONE,
        -right * HIP_FORCE_LATERAL + Vector(0, 0, -HIP_FORCE_DOWN)
    )

    -- ── Fade & cleanup ────────────────────────────────────────
    RegisterFade(ragdoll)

    print(string.format(
        "[GekkoRagdoll] Spawned | physBones=%d pushPerBone=%.0f",
        physCount, perBoneForce
    ))
end
