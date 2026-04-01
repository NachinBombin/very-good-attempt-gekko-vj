-- ============================================================
--  npc_vj_gekko / jump_system.lua
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

local JUMP_FORCE_MIN      = 200
local JUMP_FORCE_MAX      = 1000
local JUMP_FORWARD_FORCE  = 300
local JUMP_LAND_LOCKOUT   = 1.4
local JUMP_COOLDOWN_MIN   = 8.0
local JUMP_COOLDOWN_MAX   = 30.0
local JUMP_GROUND_DIST    = 24
local JUMP_MIN_ENEMY_DIST = 600
local JUMP_MAX_ENEMY_DIST = 19400

local JUMP_RISING_TIMEOUT    = 1.5
local JUMP_LAND_SUPPRESS_PAD = 1.1

-- Extra cooldown applied ON LANDING on top of JUMP_LAND_LOCKOUT.
-- Prevents ShouldJump from firing the instant the land anim finishes.
local JUMP_POST_LAND_COOLDOWN = 3.0

-- ============================================================
--  Internal helpers
-- ============================================================

-- Read the authoritative LOCAL state (never touches the NW var for logic).
local function GetLocalState(ent)
    return ent._jumpStateLOCAL or JUMP_NONE
end

-- Write both the local field AND the NW var (for clientside rendering only).
local function SetLocalState(ent, state)
    ent._jumpStateLOCAL = state
    ent:SetGekkoJumpState(state)
end

local function GekkoIsGrounded(ent)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local tr = util.TraceHull({
        start  = ent:GetPos(),
        endpos = ent:GetPos() + Vector(0, 0, -JUMP_GROUND_DIST),
        mins   = Vector(mins.x * 0.5, mins.y * 0.5, 0),
        maxs   = Vector(maxs.x * 0.5, maxs.y * 0.5, 4),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    return tr.Hit
end

-- ============================================================
function ENT:GekkoJump_Init()
    -- _jumpStateLOCAL is the ONLY field used by ShouldJump / Think for logic.
    -- GetGekkoJumpState() (NW var) is used by cl_init.lua for rendering only.
    self._jumpStateLOCAL      = JUMP_NONE
    self:SetGekkoJumpState(JUMP_NONE)
    self:SetGekkoJumpTimer(0)
    self._jumpCooldown        = 0
    self._gekkoJustJumped     = 0
    self._jetAttachments      = {}
    self._seqJump             = -1
    self._seqFall             = -1
    self._seqLand             = -1
    self._jumpRisingStartTime = 0
    self._jumpDidLiftoff      = false
    -- Armed immediately so even a first-frame ground-check can't fire.
    -- Will be overwritten to a real future time whenever landing occurs.
    self._jumpLandCooldown    = CurTime() + JUMP_POST_LAND_COOLDOWN

    self.JUMP_NONE    = JUMP_NONE
    self.JUMP_RISING  = JUMP_RISING
    self.JUMP_FALLING = JUMP_FALLING
    self.JUMP_LAND    = JUMP_LAND

    print("[GekkoJump] Init() called")
end

-- ============================================================
function ENT:GekkoJump_Activate()
    self._seqJump = self:LookupSequence("jump")
    self._seqFall = self:LookupSequence("fall")
    self._seqLand = self:LookupSequence("land")

    print(string.format(
        "[GekkoJump] Activate | jump=%d  fall=%d  land=%d",
        self._seqJump, self._seqFall, self._seqLand
    ))
end

-- ============================================================
function ENT:GekkoJump_ScanAttachments()
    self._jetAttachments = {}

    local numAtt = self:GetNumAttachments()
    if not numAtt then return end

    for i = 1, numAtt do
        local name = self:GetAttachmentName(i)
        if name and string.find(name, "MainJet") then
            self._jetAttachments[#self._jetAttachments + 1] = i
        end
    end
end

-- ============================================================
--  ShouldJump
--  Uses _jumpStateLOCAL (plain Lua field, set synchronously on
--  the same tick as any state change) instead of GetGekkoJumpState()
--  (NW var). This eliminates the one-tick window where the NW var
--  already reads NONE but the land cooldown hasn't been evaluated yet.
-- ============================================================
function ENT:GekkoJump_ShouldJump()
    if self._jumpCooldown     > CurTime() then return false end
    if self._jumpLandCooldown > CurTime() then return false end
    -- Use the LOCAL field, not the NW var.
    if GetLocalState(self) ~= JUMP_NONE   then return false end
    if not self:IsOnGround()              then return false end
    if self._mgBurstActive                then return false end

    local enemy = self:GetEnemy()
    if not IsValid(enemy)                 then return false end

    local dist = self:GetPos():Distance2D(enemy:GetPos())
    if dist < JUMP_MIN_ENEMY_DIST or dist > JUMP_MAX_ENEMY_DIST then return false end

    return true
end

-- ============================================================
local function ForceSeq(ent, seq, rate, suppressDur, seqLabel)
    ent:ResetSequence(seq)
    ent:SetCycle(0)
    ent:SetPlaybackRate(rate)
    ent.Gekko_LastSeqIdx   = seq
    ent.Gekko_LastSeqName  = seqLabel or "jump_phase"
    ent._gekkoSuppressActivity = CurTime() + suppressDur
    ent.VJ_IsMoving        = false
    ent.VJ_CanMoveThink    = false
end

-- ============================================================
function ENT:GekkoJump_Execute()
    -- Guard against double-fire: check LOCAL state, not NW var.
    if GetLocalState(self) ~= JUMP_NONE then return end

    local jumpForce    = math.Rand(JUMP_FORCE_MIN, JUMP_FORCE_MAX)
    local jumpCooldown = math.Rand(JUMP_COOLDOWN_MIN, JUMP_COOLDOWN_MAX)

    local enemy = self:GetEnemy()
    local fwd   = IsValid(enemy)
                  and (enemy:GetPos() - self:GetPos()):GetNormalized()
                  or  self:GetForward()
    fwd.z = 0
    fwd:Normalize()

    local launchYaw = fwd:Angle().y
    self:SetAngles(Angle(0, launchYaw, 0))

    self:SetMoveType(MOVETYPE_FLYGRAVITY)

    local vel = self:GetVelocity()
    vel.z     = jumpForce
    vel       = vel + fwd * JUMP_FORWARD_FORCE
    self:SetVelocity(vel)

    self:SetSchedule(SCHED_NONE)

    SetLocalState(self, JUMP_RISING)
    self._jumpCooldown        = CurTime() + jumpCooldown
    self._gekkoJustJumped     = CurTime() + 0.3
    self._jumpRisingStartTime = CurTime()
    self._jumpDidLiftoff      = false
    -- Clear land cooldown when a new jump begins.
    self._jumpLandCooldown    = 0

    if self._seqJump ~= -1 then
        ForceSeq(self, self._seqJump, 1.0, 0.5, "jump")
    end

    self:GeckoCrush_LaunchBlast()
    self:SetNWInt("GekkoJumpDust", (self:GetNWInt("GekkoJumpDust", 0) + 1) % 255)
    self:GekkoJump_StartJetFX()
end

-- ============================================================
function ENT:GekkoJump_Think()
    local state    = GetLocalState(self)
    if state == JUMP_NONE then return end

    local vel      = self:GetVelocity()
    local grounded = GekkoIsGrounded(self)
    local now      = CurTime()

    if state == JUMP_RISING or state == JUMP_FALLING then
        self._gekkoSuppressActivity = now + 1.0
        self.VJ_IsMoving     = false
        self.VJ_CanMoveThink = false

        local a = self:GetAngles()
        if math.abs(a.p) > 0.5 or math.abs(a.r) > 0.5 then
            self:SetAngles(Angle(0, a.y, 0))
        end
    end

    if state == JUMP_LAND then
        local cv = self:GetVelocity()
        if math.abs(cv.x) > 0.5 or math.abs(cv.y) > 0.5 then
            self:SetVelocity(Vector(0, 0, cv.z))
        end
        self.VJ_IsMoving     = false
        self.VJ_CanMoveThink = false
        self._gekkoSuppressActivity = now + 0.2
    end

    if not self._jumpThinkPrint or now > self._jumpThinkPrint then
        print(string.format(
            "[GekkoJump] Think | state=%d  velZ=%.1f  grounded=%s",
            state, vel.z, tostring(grounded)
        ))
        self._jumpThinkPrint = now + 0.2
    end

    -- ── RISING ────────────────────────────────────────────────
    if state == JUMP_RISING then
        if vel.z > 50 then
            self._jumpDidLiftoff = true
        end

        -- Abort: never got airborne within timeout.
        if not self._jumpDidLiftoff and
           (now - self._jumpRisingStartTime) > JUMP_RISING_TIMEOUT then
            SetLocalState(self, JUMP_NONE)
            self:SetGekkoJumpTimer(0)
            self:SetMoveType(MOVETYPE_STEP)
            self:SetVelocity(Vector(0, 0, 0))
            self.Gekko_LastSeqIdx  = -1
            self.Gekko_LastSeqName = ""
            self._gekkoSuppressActivity = now + 0.15
            self.VJ_CanMoveThink = true
            self._jumpCooldown     = now + JUMP_COOLDOWN_MAX * 2
            -- Arm land cooldown on the abort path too.
            self._jumpLandCooldown = now + JUMP_POST_LAND_COOLDOWN
            self:GekkoJump_StopJetFX()
            if self._gekkoCrouching then
                self._gekkoCrouchJustEntered = true
            end
            return
        end

        if self._seqJump ~= -1 then
            if self:GetSequence() ~= self._seqJump then
                self:ResetSequence(self._seqJump)
                self:SetPlaybackRate(0.8)
            end
            if self:GetCycle() > 0.90 then
                self:SetCycle(0.5)
            end
        end

        if vel.z < 0 then
            SetLocalState(self, JUMP_FALLING)
            self:GekkoJump_StopJetFX()
            if self._seqFall ~= -1 then
                ForceSeq(self, self._seqFall, 1.0, 0.5, "fall")
            end
            return
        end
    end

    -- ── FALLING ───────────────────────────────────────────────
    if state == JUMP_FALLING then
        if self._seqFall ~= -1 then
            if self:GetSequence() ~= self._seqFall then
                self:ResetSequence(self._seqFall)
                self:SetPlaybackRate(0.8)
            end
            if self:GetCycle() > 0.90 then
                self:SetCycle(0.5)
            end
        end
    end

    -- ── FALLING → LAND ────────────────────────────────────────
    if state == JUMP_FALLING and grounded then
        SetLocalState(self, JUMP_LAND)
        self:SetGekkoJumpTimer(now + JUMP_LAND_LOCKOUT)
        self:SetMoveType(MOVETYPE_STEP)

        -- Zero velocity immediately and one tick later to absorb any
        -- residual momentum from the movetype-switch frame.
        self:SetVelocity(Vector(0, 0, 0))
        local selfRef = self
        timer.Simple(0, function()
            if IsValid(selfRef) and GetLocalState(selfRef) == JUMP_LAND then
                selfRef:SetVelocity(Vector(0, 0, 0))
            end
        end)

        local a = self:GetAngles()
        self:SetAngles(Angle(0, a.y, 0))
        if self._seqLand ~= -1 then
            ForceSeq(self, self._seqLand, 1.0,
                JUMP_LAND_LOCKOUT + JUMP_LAND_SUPPRESS_PAD, "land")
        end

        -- Arm the post-land cooldown NOW (before state ever reaches NONE)
        -- so ShouldJump is blocked for the full JUMP_POST_LAND_COOLDOWN
        -- seconds after the land animation finishes.
        self._jumpLandCooldown = now + JUMP_LAND_LOCKOUT + JUMP_POST_LAND_COOLDOWN

        self:GekkoJump_LandImpact()
        return
    end

    -- ── LAND → NONE ───────────────────────────────────────────
    if state == JUMP_LAND and now > self:GetGekkoJumpTimer() then
        SetLocalState(self, JUMP_NONE)
        self:SetGekkoJumpTimer(0)
        self.Gekko_LastSeqIdx  = -1
        self.Gekko_LastSeqName = ""
        self._gekkoSuppressActivity = now + 0.08
        self._gekkoSkipAnimTick     = true
        if self.GekkoSeq_Idle and self.GekkoSeq_Idle ~= -1 then
            self:ResetSequence(self.GekkoSeq_Idle)
            self:SetPlaybackRate(1.0)
            self.Gekko_LastSeqIdx  = self.GekkoSeq_Idle
            self.Gekko_LastSeqName = "idle"
        end
        self.VJ_CanMoveThink = true

        if self._gekkoCrouching then
            self._gekkoCrouchJustEntered = true
        end
        -- _jumpLandCooldown keeps blocking ShouldJump for JUMP_POST_LAND_COOLDOWN
        -- seconds from this point. No change needed here.
    end
end

-- ============================================================
function ENT:GekkoJump_IsAirborne()
    local s = GetLocalState(self)
    return s == JUMP_RISING or s == JUMP_FALLING
end

-- ============================================================
function ENT:GekkoJump_StartJetFX()
    if not self._jetAttachments or #self._jetAttachments == 0 then return end
    for _, attIdx in ipairs(self._jetAttachments) do
        local attData = self:GetAttachment(attIdx)
        if attData then
            local eff = EffectData()
            eff:SetOrigin(attData.Pos)
            eff:SetAngles(attData.Ang)
            eff:SetEntity(self)
            eff:SetScale(1)
            util.Effect("GekkoJetStart", eff, true, true)
        end
    end
    self:EmitSound("MA2_Mech.JJLoop", 85, 100)
end

function ENT:GekkoJump_StopJetFX()
    self:StopSound("MA2_Mech.JJLoop")
    self:EmitSound("MA2_Mech.JJEnd", 85, 100)
end

-- ============================================================
function ENT:GekkoJump_LandImpact()
    local shakePos = self:GetPos()

    util.ScreenShake(shakePos, 12, 8, 0.6, 700)
    self:EmitSound("physics/metal/metal_box_impact_hard3.wav", 100, 80)

    local eff = EffectData()
    eff:SetOrigin(shakePos)
    eff:SetNormal(Vector(0, 0, 1))
    eff:SetScale(3)
    eff:SetMagnitude(3)
    eff:SetRadius(128)
    util.Effect("dust", eff)

    ParticleEffect("impact_dirt_cheap", shakePos, Angle(0, 0, 0))
    self:SetNWInt("GekkoLandDust", (self:GetNWInt("GekkoLandDust", 0) + 1) % 255)
    self:GeckoCrush_LandBlast()
end
