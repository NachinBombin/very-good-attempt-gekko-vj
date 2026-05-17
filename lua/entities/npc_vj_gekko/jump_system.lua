-- ============================================================
--  npc_vj_gekko / jump_system.lua
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

local JUMP_FORCE_MIN      = 500
local JUMP_FORCE_MAX      = 1200
local JUMP_FORWARD_FORCE  = 400
local JUMP_LAND_LOCKOUT   = 1.4
local JUMP_COOLDOWN_MIN   = 11.0
local JUMP_COOLDOWN_MAX   = 35.0
local JUMP_GROUND_DIST    = 24
local JUMP_MIN_ENEMY_DIST = 600
local JUMP_MAX_ENEMY_DIST = 99400

local JUMP_RISING_TIMEOUT    = 1.5
local JUMP_LAND_SUPPRESS_PAD = 1.1
local JUMP_POST_LAND_COOLDOWN = 3.0

-- ── Stuck-Z recovery ───────────────────────────────────────────────────
local JUMP_STUCK_Z_THRESHOLD  = 8.0
local JUMP_STUCK_Z_WINDOW     = 0.6
local JUMP_UNSTUCK_NUDGE      = 28
local JUMP_STUCK_MAX_ATTEMPTS = 2

-- ── Jet FX / Land impact tuning ──────────────────────────────────────────
local JET_PARTICLE      = "astw2_nightfire_thruster_small"
local LAND_PARTICLE     = "astw2_nightfire_explosion_ground"
local LAND_BLAST_RADIUS = 220
local LAND_BLAST_DAMAGE = 55
local LAND_SND = {
    "gekko/land1.wav",
    "gekko/land2.wav",
}
local LAND_SND_LEVEL = 100

-- ============================================================
--  Internal helpers
-- ============================================================

local function GetLocalState(ent)
    return ent._jumpStateLOCAL or JUMP_NONE
end

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

local function GekkoJump_FindNudgeDir(ent)
    local pos  = ent:GetPos()
    local dirs = {
        Vector( 1,  0, 0), Vector(-1,  0, 0),
        Vector( 0,  1, 0), Vector( 0, -1, 0),
        Vector( 1,  1, 0):GetNormalized(), Vector(-1, -1, 0):GetNormalized(),
        Vector( 1, -1, 0):GetNormalized(), Vector(-1,  1, 0):GetNormalized(),
    }
    local bestDir  = nil
    local bestDist = math.huge
    for _, d in ipairs(dirs) do
        local tr = util.TraceLine({
            start  = pos,
            endpos = pos + d * JUMP_UNSTUCK_NUDGE,
            filter = ent,
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit and tr.Fraction < bestDist then
            bestDist = tr.Fraction
            bestDir  = -tr.HitNormal
        end
    end
    return bestDir
end

-- ============================================================
function ENT:GekkoJump_Init()
    self._jumpStateLOCAL      = JUMP_NONE
    self:SetGekkoJumpState(JUMP_NONE)
    self:SetGekkoJumpTimer(0)
    self._jumpCooldown        = 0
    self._gekkoJustJumped     = 0
    self._jetAttachments      = {}
    self._jetsRunning         = false
    self._seqJump             = -1
    self._seqFall             = -1
    self._seqLand             = -1
    self._jumpRisingStartTime = 0
    self._jumpDidLiftoff      = false
    self._jumpLandCooldown    = CurTime() + JUMP_POST_LAND_COOLDOWN
    self._jumpLastState       = JUMP_NONE
    self._jumpStuckZLastVelZ  = 0
    self._jumpStuckZSince     = 0
    self._jumpStuckAttempts   = 0
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
    self:GekkoJump_ScanAttachments()
    print(string.format(
        "[GekkoJump] Activate | jump=%d  fall=%d  land=%d  jets=%d",
        self._seqJump, self._seqFall, self._seqLand,
        #self._jetAttachments
    ))
end

-- ============================================================
--  GekkoJump_ScanAttachments
--
--  Correct GMod API for iterating model attachments:
--    Entity:GetAttachmentInfo(index) -> table { name=string, id=number }
--                                    -> nil when index is out of range
--
--  There is NO GetNumAttachments() or GetAttachmentName() in GMod Lua.
-- ============================================================
function ENT:GekkoJump_ScanAttachments()
    self._jetAttachments = {}
    local i = 1
    while true do
        local info = self:GetAttachmentInfo(i)
        if not info then break end             -- nil = past last attachment
        if string.find(info.name, "MainJet", 1, true) then
            self._jetAttachments[#self._jetAttachments + 1] = i
        end
        i = i + 1
    end
end

-- ============================================================
--  GekkoJump_StartJetFX
-- ============================================================
function ENT:GekkoJump_StartJetFX()
    if not self._jetAttachments then return end
    self:GekkoJump_StopJetFX()
    for _, attIdx in ipairs(self._jetAttachments) do
        ParticleEffectAttach(JET_PARTICLE, PATTACH_POINT_FOLLOW, self, attIdx)
    end
    self._jetsRunning = true
    print("[GekkoJump] StartJetFX | attachments=" .. #self._jetAttachments)
end

-- ============================================================
--  GekkoJump_StopJetFX
-- ============================================================
function ENT:GekkoJump_StopJetFX()
    if not self._jetsRunning then return end
    self:StopParticles()
    self._jetsRunning = false
    print("[GekkoJump] StopJetFX")
end

-- ============================================================
--  GekkoJump_LandImpact
-- ============================================================
function ENT:GekkoJump_LandImpact()
    local pos = self:GetPos()
    if LAND_SND and #LAND_SND > 0 then
        self:EmitSound(
            LAND_SND[math.random(#LAND_SND)],
            LAND_SND_LEVEL,
            math.random(95, 110),
            1
        )
    end
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, 1))
    ed:SetScale(1.2)
    ed:SetMagnitude(1)
    util.Effect(LAND_PARTICLE, ed)
    self:SetNWInt("GekkoLandDust", (self:GetNWInt("GekkoLandDust", 0) + 1) % 255)
    util.BlastDamage(self, self, pos, LAND_BLAST_RADIUS, LAND_BLAST_DAMAGE)
    print(string.format(
        "[GekkoJump] LandImpact | pos=(%.0f,%.0f,%.0f)",
        pos.x, pos.y, pos.z
    ))
end

-- ============================================================
function ENT:GekkoJump_ShouldJump()
    if self._jumpCooldown     > CurTime() then return false end
    if self._jumpLandCooldown > CurTime() then return false end
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
    ent.Gekko_LastSeqIdx       = seq
    ent.Gekko_LastSeqName      = seqLabel or "jump_phase"
    ent._gekkoSuppressActivity = CurTime() + suppressDur
    ent.VJ_IsMoving            = false
    ent.VJ_CanMoveThink        = false
end

-- ============================================================
function ENT:GekkoJump_Execute()
    if GetLocalState(self) ~= JUMP_NONE then return end

    local jumpForce    = math.Rand(JUMP_FORCE_MIN, JUMP_FORCE_MAX)
    local jumpCooldown = math.Rand(JUMP_COOLDOWN_MIN, JUMP_COOLDOWN_MAX)

    local enemy = self:GetEnemy()
    local fwd   = IsValid(enemy)
                  and (enemy:GetPos() - self:GetPos()):GetNormalized()
                  or  self:GetForward()
    fwd.z = 0
    fwd:Normalize()

    self:SetAngles(Angle(0, fwd:Angle().y, 0))
    self:SetMoveType(MOVETYPE_FLYGRAVITY)

    local vel = self:GetVelocity()
    vel.z     = jumpForce
    vel       = vel + fwd * JUMP_FORWARD_FORCE
    self:SetVelocity(vel)

    self:SetSchedule(SCHED_NONE)

    SetLocalState(self, JUMP_RISING)
    self._jumpLastState       = JUMP_RISING
    self._jumpCooldown        = CurTime() + jumpCooldown
    self._gekkoJustJumped     = CurTime() + 0.3
    self._jumpRisingStartTime = CurTime()
    self._jumpDidLiftoff      = false
    self._jumpLandCooldown    = 0
    self._jumpStuckZLastVelZ  = vel.z
    self._jumpStuckZSince     = CurTime()
    self._jumpStuckAttempts   = 0

    if self._seqJump ~= -1 then
        ForceSeq(self, self._seqJump, 1.0, 0.5, "jump")
    end

    self:GeckoCrush_LaunchBlast()
    self:SetNWInt("GekkoJumpDust", (self:GetNWInt("GekkoJumpDust", 0) + 1) % 255)
    self:GekkoJump_StartJetFX()
end

-- ============================================================
function ENT:GekkoJump_CheckStuckZ(velZ, now)
    if math.abs(velZ - self._jumpStuckZLastVelZ) > JUMP_STUCK_Z_THRESHOLD then
        self._jumpStuckZLastVelZ = velZ
        self._jumpStuckZSince    = now
        return false
    end
    if (now - self._jumpStuckZSince) < JUMP_STUCK_Z_WINDOW then
        return false
    end
    print(string.format(
        "[GekkoJump] STUCK-Z detected | velZ=%.1f  attempts=%d",
        velZ, self._jumpStuckAttempts
    ))
    if self._jumpStuckAttempts >= JUMP_STUCK_MAX_ATTEMPTS then
        print("[GekkoJump] STUCK-Z: giving up, aborting jump")
        SetLocalState(self, JUMP_NONE)
        self._jumpLastState         = JUMP_NONE
        self:SetGekkoJumpTimer(0)
        self:SetMoveType(MOVETYPE_STEP)
        self:SetVelocity(Vector(0, 0, 0))
        self.Gekko_LastSeqIdx       = -1
        self.Gekko_LastSeqName      = ""
        self._gekkoSuppressActivity = now + 0.15
        self.VJ_CanMoveThink        = true
        self._jumpCooldown          = now + JUMP_COOLDOWN_MAX * 2
        self._jumpLandCooldown      = now + JUMP_POST_LAND_COOLDOWN
        self:GekkoJump_StopJetFX()
        if self._gekkoCrouching then self._gekkoCrouchJustEntered = true end
        return true
    end
    self._jumpStuckAttempts = self._jumpStuckAttempts + 1
    local nudgeDir = GekkoJump_FindNudgeDir(self)
    if nudgeDir then
        nudgeDir.z = 0
        self:SetPos(self:GetPos() + nudgeDir * JUMP_UNSTUCK_NUDGE)
        print(string.format(
            "[GekkoJump] STUCK-Z: nudged %.0f units  dir=(%.2f,%.2f)",
            JUMP_UNSTUCK_NUDGE, nudgeDir.x, nudgeDir.y
        ))
    else
        print("[GekkoJump] STUCK-Z: no wall found, applying vertical kick")
    end
    local enemy = self:GetEnemy()
    local fwd   = IsValid(enemy)
                  and (enemy:GetPos() - self:GetPos()):GetNormalized()
                  or  self:GetForward()
    fwd.z = 0
    fwd:Normalize()
    local newVel = fwd * JUMP_FORWARD_FORCE
    newVel.z     = math.Rand(JUMP_FORCE_MIN, JUMP_FORCE_MAX)
    self:SetVelocity(newVel)
    self:SetMoveType(MOVETYPE_FLYGRAVITY)
    self._jumpStuckZLastVelZ = newVel.z
    self._jumpStuckZSince    = now
    SetLocalState(self, JUMP_RISING)
    self._jumpLastState = JUMP_RISING
    return true
end

-- ============================================================
function ENT:GekkoJump_Think()
    local state = GetLocalState(self)
    if state == JUMP_NONE then
        self._jumpLastState = JUMP_NONE
        return
    end

    local vel      = self:GetVelocity()
    local grounded = GekkoIsGrounded(self)
    local now      = CurTime()

    if state ~= self._jumpLastState then
        if state == JUMP_RISING or state == JUMP_FALLING then
            self.VJ_IsMoving     = false
            self.VJ_CanMoveThink = false
        end
        self._jumpLastState = state
    end

    if state == JUMP_LAND then
        local cv = self:GetVelocity()
        if math.abs(cv.x) > 0.5 or math.abs(cv.y) > 0.5 then
            self:SetVelocity(Vector(0, 0, cv.z))
        end
        self.VJ_IsMoving            = false
        self.VJ_CanMoveThink        = false
        self._gekkoSuppressActivity = now + 0.2
    end

    if state == JUMP_RISING or state == JUMP_FALLING then
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

    -- ── RISING ───────────────────────────────────────────────
    if state == JUMP_RISING then
        if vel.z > 50 then self._jumpDidLiftoff = true end

        if not self._jumpDidLiftoff and
           (now - self._jumpRisingStartTime) > JUMP_RISING_TIMEOUT then
            SetLocalState(self, JUMP_NONE)
            self._jumpLastState         = JUMP_NONE
            self:SetGekkoJumpTimer(0)
            self:SetMoveType(MOVETYPE_STEP)
            self:SetVelocity(Vector(0, 0, 0))
            self.Gekko_LastSeqIdx       = -1
            self.Gekko_LastSeqName      = ""
            self._gekkoSuppressActivity = now + 0.15
            self.VJ_CanMoveThink        = true
            self._jumpCooldown          = now + JUMP_COOLDOWN_MAX * 2
            self._jumpLandCooldown      = now + JUMP_POST_LAND_COOLDOWN
            self:GekkoJump_StopJetFX()
            if self._gekkoCrouching then self._gekkoCrouchJustEntered = true end
            return
        end

        if self._jumpDidLiftoff then
            if self:GekkoJump_CheckStuckZ(vel.z, now) then return end
        end

        if self._seqJump ~= -1 then
            if self:GetSequence() ~= self._seqJump then
                self:ResetSequence(self._seqJump)
                self:SetPlaybackRate(0.8)
            end
            if self:GetCycle() > 0.90 then self:SetCycle(0.5) end
        end

        if vel.z < 0 then
            SetLocalState(self, JUMP_FALLING)
            self._jumpLastState = JUMP_FALLING
            self:GekkoJump_StopJetFX()
            if self._seqFall ~= -1 then
                ForceSeq(self, self._seqFall, 1.0, 0.5, "fall")
            end
            return
        end
    end

    -- ── FALLING ──────────────────────────────────────────────
    if state == JUMP_FALLING then
        if self:GekkoJump_CheckStuckZ(vel.z, now) then return end
        if self._seqFall ~= -1 then
            if self:GetSequence() ~= self._seqFall then
                self:ResetSequence(self._seqFall)
                self:SetPlaybackRate(0.8)
            end
            if self:GetCycle() > 0.90 then self:SetCycle(0.5) end
        end
    end

    -- ── FALLING → LAND ───────────────────────────────────────
    if state == JUMP_FALLING and grounded then
        SetLocalState(self, JUMP_LAND)
        self._jumpLastState = JUMP_LAND
        self:SetGekkoJumpTimer(now + JUMP_LAND_LOCKOUT)
        self:SetMoveType(MOVETYPE_STEP)
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
        self._jumpLandCooldown = now + JUMP_LAND_LOCKOUT + JUMP_POST_LAND_COOLDOWN
        self:GekkoJump_LandImpact()
        return
    end

    -- ── LAND → NONE ─────────────────────────────────────────
    if state == JUMP_LAND and now > self:GetGekkoJumpTimer() then
        SetLocalState(self, JUMP_NONE)
        self._jumpLastState         = JUMP_NONE
        self:SetGekkoJumpTimer(0)
        self.Gekko_LastSeqIdx       = -1
        self.Gekko_LastSeqName      = ""
        self._gekkoSuppressActivity = now + 0.08
        self._gekkoSkipAnimTick     = true
        if self.GekkoSeq_Idle and self.GekkoSeq_Idle ~= -1 then
            self:ResetSequence(self.GekkoSeq_Idle)
            self:SetPlaybackRate(1.0)
            self.Gekko_LastSeqIdx  = self.GekkoSeq_Idle
            self.Gekko_LastSeqName = "idle"
        end
        self.VJ_CanMoveThink = true
        if self._gekkoCrouching then self._gekkoCrouchJustEntered = true end
    end
end

-- ============================================================
function ENT:GekkoJump_IsAirborne()
    local s = GetLocalState(self)
    return s == JUMP_RISING or s == JUMP_FALLING
end
