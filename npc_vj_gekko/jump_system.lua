-- ============================================================
--  npc_vj_gekko / jump_system.lua
-- ============================================================

local JUMP_NONE    = 0
local JUMP_RISING  = 1
local JUMP_FALLING = 2
local JUMP_LAND    = 3

local JUMP_FORCE          = 450
local JUMP_FORWARD_FORCE  = 200
local JUMP_LAND_LOCKOUT   = 2
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
        self:ResetSequence(self._seqJump)
        self:SetPlaybackRate(1.0)
        -- Stamp so GekkoUpdateAnimation won't clobber us with a competing reset
        self.Gekko_LastSeqIdx  = self._seqJump
        self.Gekko_LastSeqName = "jump"
    end

    self:GekkoJump_StartJetFX()
end

-- ============================================================
function ENT:GekkoJump_Think()
    local state    = self:GetGekkoJumpState()
    if state == JUMP_NONE then return end

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
            self:ResetSequence(self._seqFall)
            self:SetPlaybackRate(1.0)
            -- Stamp so GekkoUpdateAnimation won't clobber
            self.Gekko_LastSeqIdx  = self._seqFall
            self.Gekko_LastSeqName = "fall"
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
            self:ResetSequence(self._seqLand)
            self:SetPlaybackRate(1.2)
            -- Stamp so GekkoUpdateAnimation won't clobber
            self.Gekko_LastSeqIdx  = self._seqLand
            self.Gekko_LastSeqName = "land"
        end
        self:GekkoJump_LandImpact()
        return
    end

    if state == JUMP_LAND and CurTime() > self:GetGekkoJumpTimer() then
        self:SetGekkoJumpState(JUMP_NONE)
        self:SetGekkoJumpTimer(0)
        -- Clear stamp so normal walk/idle logic resumes freely
        self.Gekko_LastSeqIdx  = -1
        self.Gekko_LastSeqName = ""
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
    self:EmitSound("MA2_Mech.HardLand", 95, 100)
    local shakePos = self:GetPos()
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetPos():Distance(shakePos) < 600 then
            util.ScreenShake(shakePos, 8, 5, 0.4, 600)
            break
        end
    end
    local eff = EffectData()
    eff:SetOrigin(self:GetPos())
    eff:SetScale(2)
    util.Effect("GekkoLandDust", eff, true, true)
end
