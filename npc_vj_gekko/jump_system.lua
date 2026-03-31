-- ============================================================
--  npc_vj_gekko / jump_system.lua
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

local JUMP_FORCE_MIN      = 200
local JUMP_FORCE_MAX      = 1300
local JUMP_FORWARD_FORCE  = 300
local JUMP_LAND_LOCKOUT   = 1.4
local JUMP_COOLDOWN_MIN   = 8.0
local JUMP_COOLDOWN_MAX   = 30.0
local JUMP_GROUND_DIST    = 24
local JUMP_MIN_ENEMY_DIST = 600
local JUMP_MAX_ENEMY_DIST = 19400

local JUMP_RISING_TIMEOUT = 1.5

-- Land suppress: long enough to cover the full lockout + a generous pad
-- so VJ Base / GekkoUpdateAnimation cannot sneak a reset in.
local JUMP_LAND_SUPPRESS_PAD = 1.1   -- was 0.3 — now total = 1.4 + 1.1 = 2.5s

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

    if self._seqJump == -1 then print("[GekkoJump] WARNING: 'jump' not found") end
    if self._seqFall == -1 then print("[GekkoJump] WARNING: 'fall' not found") end
    if self._seqLand == -1 then print("[GekkoJump] WARNING: 'land' not found") end
end

-- ============================================================
function ENT:GekkoJump_ScanAttachments()
    self._jetAttachments = {}

    local numAtt = self:GetNumAttachments()
    if not numAtt then
        print("[GekkoJump] ScanAttachments: GetNumAttachments returned nil, skipping")
        return
    end

    for i = 1, numAtt do
        local name = self:GetAttachmentName(i)
        if name and string.find(name, "MainJet") then
            self._jetAttachments[#self._jetAttachments + 1] = i
            print("[GekkoJump] Found jet attachment: " .. i .. " = " .. name)
        end
    end

    print("[GekkoJump] Attachment scan complete — " .. #self._jetAttachments .. " jet(s) found")
end

-- ============================================================
function ENT:GekkoJump_ShouldJump()
    if self._jumpCooldown > CurTime()        then return false end
    if self:GetGekkoJumpState() ~= JUMP_NONE then return false end
    if not self:IsOnGround()                 then return false end
    if self._mgBurstActive                   then return false end

    local enemy = self:GetEnemy()
    if not IsValid(enemy)                    then return false end

    local dist = self:GetPos():Distance2D(enemy:GetPos())
    if dist < JUMP_MIN_ENEMY_DIST or dist > JUMP_MAX_ENEMY_DIST then return false end

    return true
end

-- ============================================================
-- Force a sequence and lock out VJ + GekkoUpdateAnimation.
--   suppressDur: seconds to hold the lock.
--   seqLabel:    debug name.
local function ForceSeq(ent, seq, rate, suppressDur, seqLabel)
    ent:ResetSequence(seq)
    ent:SetCycle(0)
    ent:SetPlaybackRate(rate)
    ent.Gekko_LastSeqIdx   = seq
    ent.Gekko_LastSeqName  = seqLabel or "jump_phase"
    ent._gekkoSuppressActivity = CurTime() + suppressDur
    ent.VJ_IsMoving        = false
    ent.VJ_CanMoveThink    = false
    print(string.format(
        "[GekkoJump] ForceSeq seq=%d  label=%s  suppress=%.2fs",
        seq, seqLabel or "jump_phase", suppressDur
    ))
end

-- ============================================================
function ENT:GekkoJump_Execute()
    if self:GetGekkoJumpState() ~= JUMP_NONE then return end

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

    self:SetGekkoJumpState(JUMP_RISING)
    self._jumpCooldown        = CurTime() + jumpCooldown
    self._gekkoJustJumped     = CurTime() + 0.3
    self._jumpRisingStartTime = CurTime()
    self._jumpDidLiftoff      = false

    print(string.format(
        "[GekkoJump] EXECUTE → RISING  seqJump=%d  force=%.0f  cooldown=%.1fs",
        self._seqJump, jumpForce, jumpCooldown
    ))

    if self._seqJump ~= -1 then
        ForceSeq(self, self._seqJump, 1.0, 0.5, "jump")
    end

    self:GekkoJump_StartJetFX()
end

-- ============================================================
function ENT:GekkoJump_Think()
    local state    = self:GetGekkoJumpState()
    if state == JUMP_NONE then return end

    local vel      = self:GetVelocity()
    local grounded = GekkoIsGrounded(self)
    local now      = CurTime()

    -- While airborne, keep rolling the suppression window so it never
    -- lapses mid-flight.
    if state == JUMP_RISING or state == JUMP_FALLING then
        self._gekkoSuppressActivity = now + 1.0
        self.VJ_IsMoving     = false
        self.VJ_CanMoveThink = false

        local a = self:GetAngles()
        if math.abs(a.p) > 0.5 or math.abs(a.r) > 0.5 then
            self:SetAngles(Angle(0, a.y, 0))
        end
    end

    if not self._jumpThinkPrint or now > self._jumpThinkPrint then
        print(string.format(
            "[GekkoJump] Think | state=%d  velZ=%.1f  grounded=%s",
            state, vel.z, tostring(grounded)
        ))
        self._jumpThinkPrint = now + 0.2
    end

    if state == JUMP_RISING then
        if vel.z > 50 then
            self._jumpDidLiftoff = true
        end

        if not self._jumpDidLiftoff and
           (now - self._jumpRisingStartTime) > JUMP_RISING_TIMEOUT then
            print(string.format(
                "[GekkoJump] RISING TIMEOUT (%.1fs, velZ=%.1f) — aborting jump",
                now - self._jumpRisingStartTime, vel.z
            ))
            self:SetGekkoJumpState(JUMP_NONE)
            self:SetGekkoJumpTimer(0)
            self:SetMoveType(MOVETYPE_STEP)
            self:SetVelocity(Vector(0, 0, 0))
            self.Gekko_LastSeqIdx  = -1
            self.Gekko_LastSeqName = ""
            self._gekkoSuppressActivity = now + 0.15
            self.VJ_CanMoveThink = true
            self._jumpCooldown = now + JUMP_COOLDOWN_MAX * 2
            self:GekkoJump_StopJetFX()
            if self._gekkoCrouching then
                self._gekkoCrouchJustEntered = true
            end
            return
        end

        if vel.z < 0 then
            self:SetGekkoJumpState(JUMP_FALLING)
            self:GekkoJump_StopJetFX()
            print("[GekkoJump] → FALLING  seqFall=" .. self._seqFall)
            if self._seqFall ~= -1 then
                ForceSeq(self, self._seqFall, 1.0, 0.5, "fall")
            end
            return
        end
    end

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

    if state == JUMP_FALLING and grounded then
        self:SetGekkoJumpState(JUMP_LAND)
        self:SetGekkoJumpTimer(now + JUMP_LAND_LOCKOUT)
        self:SetMoveType(MOVETYPE_STEP)
        self:SetVelocity(Vector(0, 0, 0))
        local a = self:GetAngles()
        self:SetAngles(Angle(0, a.y, 0))
        print("[GekkoJump] → LAND  seqLand=" .. self._seqLand)
        if self._seqLand ~= -1 then
            -- Full lockout + generous pad — animation must finish before
            -- AnimApply or GekkoUpdateAnimation can touch the sequence.
            ForceSeq(self, self._seqLand, 1.0,
                JUMP_LAND_LOCKOUT + JUMP_LAND_SUPPRESS_PAD, "land")
        end
        self:GekkoJump_LandImpact()
        return
    end

    if state == JUMP_LAND and now > self:GetGekkoJumpTimer() then
        self:SetGekkoJumpState(JUMP_NONE)
        self:SetGekkoJumpTimer(0)
        self.Gekko_LastSeqIdx  = -1
        self.Gekko_LastSeqName = ""
        -- Short suppress so AnimApply stays blocked one extra tick,
        -- and flag GekkoUpdateAnimation to also skip this exact tick.
        self._gekkoSuppressActivity = now + 0.08
        self._gekkoSkipAnimTick     = true
        if self.GekkoSeq_Idle and self.GekkoSeq_Idle ~= -1 then
            self:ResetSequence(self.GekkoSeq_Idle)
            self:SetPlaybackRate(1.0)
            self.Gekko_LastSeqIdx  = self.GekkoSeq_Idle
            self.Gekko_LastSeqName = "idle"
        end
        self.VJ_CanMoveThink = true
        print("[GekkoJump] → NONE (lockout done)")

        if self._gekkoCrouching then
            self._gekkoCrouchJustEntered = true
            print("[GekkoJump] → crouch active after landing — signalling AnimApply")
        end
    end
end

-- ============================================================
function ENT:GekkoJump_IsAirborne()
    local s = self:GetGekkoJumpState()
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
end
