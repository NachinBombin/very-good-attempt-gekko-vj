-- ============================================================
--  npc_vj_gekko / leg_disable_system.lua
--  Gekko VJ NPC — Leg disabling / grounded state
-- ============================================================

local GROUNDED_HEALTH_FRACTION = 0.30
local GROUNDED_CHANCE          = 0.30

local PELVIS_OFFSET_Z = -125
local L_THIGH_ANG     = Angle(0, 0, -50)
local R_THIGH_ANG     = Angle(100, -80, 0)

-- The spine3 bone sits roughly this many units above the NPC origin
-- when the NPC is upright. When grounded/collapsed the pelvis drops
-- PELVIS_OFFSET_Z, so the effective spine3 floor contact point is
-- approximately (origin + SPINE3_HEIGHT_UPRIGHT + PELVIS_OFFSET_Z).
-- We want THAT point touching the geometry, so we offset the origin
-- UP by this amount when placing the NPC on the floor.
local SPINE3_HEIGHT_UPRIGHT = 96   -- tune if needed

-- ============================================================
--  Init
-- ============================================================
function ENT:GekkoLegs_Init()
    self._gekkoLegsDisabled    = false
    self._gekkoLegsTriggeredT  = 0
    self._gekkoLegsBleedNextT  = 0
    self.GekkoPelvisBone       = self:LookupBone("b_pelvis")   or -1
    self.GekkoLThighBone       = self:LookupBone("b_l_thigh")  or -1
    self.GekkoRThighBone       = self:LookupBone("b_r_thigh")  or -1
end

-- ============================================================
--  Damage hook
-- ============================================================
function ENT:GekkoLegs_OnDamage(dmginfo)
    if self._gekkoLegsDisabled then return end

    local curHP   = self:Health()
    local baseMax = self.StartHealth or self:GetMaxHealth() or curHP
    local thresh  = baseMax * GROUNDED_HEALTH_FRACTION

    if curHP <= thresh then return end
    local newHP = math.max(curHP - dmginfo:GetDamage(), 0)
    if newHP > thresh then return end
    if math.Rand(0, 1) > GROUNDED_CHANCE then return end

    self:GekkoLegs_TriggerGrounded(dmginfo)
end

-- ============================================================
--  Hard locomotion lock (called on trigger + every tick)
-- ============================================================
local function HardLockMovement(ent)
    ent.MoveSpeed    = 0
    ent.RunSpeed     = 0
    ent.WalkSpeed    = 0
    ent.MaxWalkSpeed = 0
    ent.MaxRunSpeed  = 0
    ent:SetAbsVelocity(Vector(0, 0, 0))
    if ent:GetCurrentSchedule() ~= SCHED_IDLE_STAND then
        ent:SetSchedule(SCHED_IDLE_STAND)
    end
    ent:TaskComplete()
    if ent.StopMoving then ent:StopMoving() end
end

-- ============================================================
--  Floor snap
--  Goal: the spine3 bone contact point (body centre when
--  collapsed) must be touching the floor geometry.
--
--  Strategy:
--   1. Trace straight down from well above the NPC to find
--      the floor Z (MASK_SOLID_BRUSHONLY, fallback PLAYERSOLID).
--   2. Place the NPC origin so that spine3 sits on that Z:
--        origin_z = floor_z - (SPINE3_HEIGHT_UPRIGHT + PELVIS_OFFSET_Z)
--      Because the pelvis drops PELVIS_OFFSET_Z when the pose
--      is applied, spine3 ends up at exactly floor_z.
-- ============================================================
local function SnapToFloor(ent)
    local pos = ent:GetPos()

    -- Start the trace well above to avoid starting inside geometry
    local traceStart = Vector(pos.x, pos.y, pos.z + 500)
    local traceEnd   = Vector(pos.x, pos.y, pos.z - 2048)

    local tr = util.TraceLine({
        start  = traceStart,
        endpos = traceEnd,
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })

    if not tr.Hit or tr.StartSolid then
        -- Fallback: include player-solid props
        tr = util.TraceLine({
            start  = traceStart,
            endpos = traceEnd,
            filter = ent,
            mask   = MASK_PLAYERSOLID_BRUSHONLY,
        })
    end

    if tr.Hit and not tr.StartSolid then
        local floorZ     = tr.HitPos.z
        -- spine3 contact offset: upright height + pelvis drop
        local contactOfs = SPINE3_HEIGHT_UPRIGHT + PELVIS_OFFSET_Z
        -- We want: origin_z + contactOfs == floorZ
        -- => origin_z = floorZ - contactOfs
        local newZ = floorZ - contactOfs
        ent:SetPos(Vector(pos.x, pos.y, newZ))
        print(string.format(
            "[GekkoLegs] SnapToFloor | floorZ=%.1f  originZ=%.1f  spine3Z=%.1f (target)",
            floorZ, newZ, newZ + contactOfs
        ))
    else
        print("[GekkoLegs] WARNING: SnapToFloor trace missed entirely")
    end
end

-- ============================================================
--  Grounded trigger
-- ============================================================
function ENT:GekkoLegs_TriggerGrounded(dmginfo)
    if self._gekkoLegsDisabled then return end
    self._gekkoLegsDisabled   = true
    self._gekkoLegsTriggeredT = CurTime()

    -- ---- 1. Fully kill the jump system state -------------------
    -- Set local jump state variable that GekkoJump_Think reads
    self._jumpStateLOCAL = 0   -- JUMP_NONE
    if self.SetGekkoJumpState then self:SetGekkoJumpState(0) end
    if self.SetGekkoJumpTimer  then self:SetGekkoJumpTimer(0) end
    if self.GekkoJump_StopJetFX then self:GekkoJump_StopJetFX() end
    -- Push cooldowns far into the future so _ShouldJump always returns false
    self._jumpCooldown     = CurTime() + 999999
    self._jumpLandCooldown = CurTime() + 999999
    self._jumpRisingStartTime = 0
    self._jumpDidLiftoff   = false

    -- ---- 2. Kill sprint / run ----------------------------------
    self._gekkoRunning      = false
    self._gekkoSprinting    = false
    self._gekkoSprintEndT   = 0
    if self._preSprint_MoveSpeed then
        self.MoveSpeed = self._preSprint_MoveSpeed
        self.RunSpeed  = self._preSprint_RunSpeed
        self.WalkSpeed = self._preSprint_WalkSpeed
        self._preSprint_MoveSpeed = nil
        self._preSprint_RunSpeed  = nil
        self._preSprint_WalkSpeed = nil
    end

    -- ---- 3. Clear crouch / hull --------------------------------
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetNWBool("GekkoIsCrouching", false)
    self._gekkoCrouching    = false
    self.VJ_IsBeingCrouched = false

    -- ---- 4. Make sure we are on MOVETYPE_STEP so SetPos works --
    --        (if mid-jump the type is FLYGRAVITY; reset it first)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetAbsVelocity(Vector(0, 0, 0))

    -- ---- 5. Snap spine3 to the floor --------------------------
    SnapToFloor(self)

    -- ---- 6. Now hard-freeze all locomotion --------------------
    self:SetMoveType(MOVETYPE_NONE)
    HardLockMovement(self)

    -- ---- 7. Apply the bone pose --------------------------------
    self:GekkoLegs_ApplyPose()

    -- ---- 8. Gib burst ------------------------------------------
    local hitPos = dmginfo:GetDamagePosition()
    if (not hitPos) or hitPos == vector_origin then
        hitPos = self:GetPos() + Vector(0, 0, 80)
    end
    local attacker  = dmginfo:GetAttacker()
    local hitNormal = Vector(0, 0, 1)
    if IsValid(attacker) then
        hitNormal = (self:GetPos() - attacker:GetPos()):GetNormalized()
        hitNormal.z = math.Clamp(hitNormal.z, -0.3, 0.3)
        hitNormal:Normalize()
    end
    if self.GekkoGib_BigBurst then
        self:GekkoGib_BigBurst(hitPos, hitNormal)
    else
        self:GekkoGib_OnDamage(self.StartHealth or 900, dmginfo)
    end

    print("[GekkoLegs] Grounded state entered")
end

-- ============================================================
--  Pose application
-- ============================================================
function ENT:GekkoLegs_ApplyPose()
    if not self._gekkoLegsDisabled then return end
    if self.GekkoPelvisBone and self.GekkoPelvisBone >= 0 then
        self:ManipulateBonePosition(self.GekkoPelvisBone, Vector(0, 0, PELVIS_OFFSET_Z))
    end
    if self.GekkoLThighBone and self.GekkoLThighBone >= 0 then
        self:ManipulateBoneAngles(self.GekkoLThighBone, L_THIGH_ANG)
    end
    if self.GekkoRThighBone and self.GekkoRThighBone >= 0 then
        self:ManipulateBoneAngles(self.GekkoRThighBone, R_THIGH_ANG)
    end
end

-- ============================================================
--  Per-tick update while grounded
-- ============================================================
function ENT:GekkoLegs_Think()
    if not self._gekkoLegsDisabled then return end

    -- Keep locomotion dead every tick
    HardLockMovement(self)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetAbsVelocity(Vector(0, 0, 0))

    -- Keep pose
    self:GekkoLegs_ApplyPose()

    -- Passive bleeding
    local now = CurTime()
    if now >= (self._gekkoLegsBleedNextT or 0) then
        self._gekkoLegsBleedNextT = now + math.Rand(0.4, 0.9)
        self._bloodSplatPulse = (self._bloodSplatPulse or 0) + 1
        local variant = math.random(1, 5)
        self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse * 8 + (variant - 1))
    end
end

-- Stub: legacy callers
function ENT:GekkoLegs_GroundToFloor() end
function ENT:GekkoLegs_GroundToFloorOnce() end
