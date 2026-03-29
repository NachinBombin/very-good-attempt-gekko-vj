-- ============================================================
--  npc_vj_gekko / jump_system.lua
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

local JUMP_FORCE          = 450
local JUMP_FORWARD_FORCE  = 200
local JUMP_LAND_LOCKOUT   = 1.4   -- matches land anim duration
local JUMP_COOLDOWN       = 6.0
local JUMP_GROUND_DIST    = 24
local JUMP_MIN_ENEMY_DIST = 600
local JUMP_MAX_ENEMY_DIST = 4400

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
    self._jumpCooldown    = 0
    self._gekkoJustJumped = 0
    self._jetAttachments  = {}
    self._seqJump = -1
    self._seqFall = -1
    self._seqLand = -1

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

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist < JUMP_MIN_ENEMY_DIST or dist > JUMP_MAX_ENEMY_DIST then return false end
    if (enemy:GetPos().z - self:GetPos().z) < -200 then return false end

    return true
end

-- ============================================================
--  GekkoJump_ForceSequence
--  Single authoritative place to slam a jump-phase sequence.
--  Locks out GekkoUpdateAnimation AND MaintainActivity so
--  nothing underneath can clobber the anim this tick.
-- ============================================================
local function ForceSeq(ent, seq, rate)
    ent:ResetSequence(seq)
    ent:SetCycle(0)
    ent:SetPlaybackRate(rate)
    ent.Gekko_LastSeqIdx  = seq
    ent.Gekko_LastSeqName = "jump_phase"
    -- Suppress VJ MaintainActivity for this tick
    ent._gekkoSuppressActivity = CurTime() + 0.5
end

-- ============================================================
function ENT:GekkoJump_Execute()
    if self:GetGekkoJumpState() ~= JUMP_NONE then return end

    local enemy = self:GetEnemy()
    local fwd   = IsValid(enemy)
                  and (enemy:GetPos() - self:GetPos()):GetNormalized()
                  or  self:GetForward()
    fwd.z = 0
    fwd:Normalize()

    local vel = self:GetVelocity()
    vel.z     = JUMP_FORCE
    vel       = vel + fwd * JUMP_FORWARD_FORCE
    self:SetVelocity(vel)
    self:SetMoveType(MOVETYPE_FLYGRAVITY)

    self:SetGekkoJumpState(JUMP_RISING)
    self._jumpCooldown    = CurTime() + JUMP_COOLDOWN
    self._gekkoJustJumped = CurTime() + 0.3

    print("[GekkoJump] EXECUTE → RISING  seqJump=" .. self._seqJump)

    if self._seqJump ~= -1 then
        ForceSeq(self, self._seqJump, 1.0)
    end

    self:GekkoJump_StartJetFX()
end

-- ============================================================
function ENT:GekkoJump_Think()
    local state    = self:GetGekkoJumpState()
    if state == JUMP_NONE then return end

    -- Keep suppression alive every think tick while airborne
    if state == JUMP_RISING or state == JUMP_FALLING then
        self._gekkoSuppressActivity = CurTime() + 0.5
    end

    local vel      = self:GetVelocity()
    local grounded = GekkoIsGrounded(self)

    if not self._jumpThinkPrint or CurTime() > self._jumpThinkPrint then
        print(string.format(
            "[GekkoJump] Think | state=%d  velZ=%.1f  grounded=%s",
            state, vel.z, tostring(grounded)
        ))
        self._jumpThinkPrint = CurTime() + 0.2
    end

    if state == JUMP_RISING and vel.z < 0 then
        self:SetGekkoJumpState(JUMP_FALLING)
        self:GekkoJump_StopJetFX()
        print("[GekkoJump] → FALLING  seqFall=" .. self._seqFall)
        if self._seqFall ~= -1 then
            ForceSeq(self, self._seqFall, 1.0)
        end
        return
    end

    if state == JUMP_FALLING and grounded then
        self:SetGekkoJumpState(JUMP_LAND)
        self:SetGekkoJumpTimer(CurTime() + JUMP_LAND_LOCKOUT)
        self:SetMoveType(MOVETYPE_STEP)
        self:SetVelocity(Vector(0, 0, 0))
        print("[GekkoJump] → LAND  seqLand=" .. self._seqLand)
        if self._seqLand ~= -1 then
            -- Play land anim at natural speed (1.0).
            -- Lockout duration should match the anim length — tune JUMP_LAND_LOCKOUT if needed.
            ForceSeq(self, self._seqLand, 1.0)
        end
        self:GekkoJump_LandImpact()
        return
    end

    if state == JUMP_LAND and CurTime() > self:GetGekkoJumpTimer() then
        self:SetGekkoJumpState(JUMP_NONE)
        self:SetGekkoJumpTimer(0)
        self.Gekko_LastSeqIdx  = -1
        self.Gekko_LastSeqName = ""
        self._gekkoSuppressActivity = 0
        print("[GekkoJump] → NONE (lockout done)")
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

    -- Camera shake — works serverside, broadcasts to nearby players
    util.ScreenShake(shakePos, 12, 8, 0.6, 700)

    -- Land sound
    self:EmitSound("physics/metal/metal_box_impact_hard3.wav", 100, 80)

    -- Dust: use a real built-in particle that definitely exists
    local eff = EffectData()
    eff:SetOrigin(shakePos)
    eff:SetNormal(Vector(0, 0, 1))
    eff:SetScale(3)
    eff:SetMagnitude(3)
    eff:SetRadius(128)
    util.Effect("dust", eff)

    -- Supplemental dirt puff via particle system
    ParticleEffect("impact_dirt_cheap", shakePos, Angle(0, 0, 0))
end
