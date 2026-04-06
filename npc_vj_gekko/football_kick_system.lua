-- ============================================================
--  football_kick_system.lua
--  Gekko VJ NPC — Melee Attack #5: Football Kick
--
--  A powerful forward-cone stomp kick with 4 phases:
--    Phase 1  (0.00-0.25)  Preparation  — left leg winds back
--    Phase 2  (0.25-0.45)  Hold         — balance / force accumulation
--    Phase 3  (0.45-0.65)  Extension    — leg shoots forward, DAMAGE fires
--    Phase 4  (0.65-1.00)  Recovery     — leg returns to rest
--
--  Server sets GekkoFootballKickPulse (NW Int) to trigger.
--  cl_init.lua reads the same pulse and drives the bone animation.
--
--  Damage fires once at the start of Phase 3.
--  Attack shape: forward cone (dot >= 0.4) within FK_DAMAGE_RADIUS.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  Timing
-- ─────────────────────────────────────────────────────────────
local FK_DURATION         = 1.2    -- total animation seconds
local FK_PHASE1_END       = 0.25   -- normalised t: end of preparation
local FK_PHASE2_END       = 0.45   -- normalised t: end of hold
local FK_PHASE3_END       = 0.65   -- normalised t: end of extension (damage window)
-- Phase 4 is the remainder to 1.0

-- Damage fires when t crosses FK_PHASE3_START
local FK_DAMAGE_T         = FK_PHASE2_END   -- t at which damage fires

-- ─────────────────────────────────────────────────────────────
--  Damage
-- ─────────────────────────────────────────────────────────────
local FK_DAMAGE_RADIUS    = 280     -- Hammer units, leg-reach of the Gekko
local FK_DAMAGE_AMOUNT    = 85
local FK_CONE_DOT         = 0.4    -- forward cone half-angle (cos); ~66 deg half-angle
local FK_FORCE_SCALE      = 65000  -- knockback impulse

-- ─────────────────────────────────────────────────────────────
--  Cooldown / trigger
-- ─────────────────────────────────────────────────────────────
local FK_COOLDOWN         = 4.0    -- seconds before another Football Kick can fire
local FK_TRIGGER_DIST_MAX = 320    -- only trigger if enemy is within this range

-- NW string identifier
local FK_NW_PULSE         = "GekkoFootballKickPulse"

-- ─────────────────────────────────────────────────────────────
--  Net string (declared here, init.lua includes this file)
-- ─────────────────────────────────────────────────────────────
util.AddNetworkString(FK_NW_PULSE .. "Net")  -- optional future net use

-- ─────────────────────────────────────────────────────────────
--  Helper: GetActiveEnemy  (mirrors init.lua local)
-- ─────────────────────────────────────────────────────────────
local function GetActiveEnemy(ent)
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

-- ─────────────────────────────────────────────────────────────
--  GekkoFK_Init
--  Called from ENT:Init() (via init.lua)
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoFK_Init()
    self._fkActive       = false
    self._fkStartTime    = -9999
    self._fkPulseCount   = 0
    self._fkDamageFired  = false
    self._fkNextT        = 0
    self:SetNWInt(FK_NW_PULSE, 0)
    print("[GekkoFK] Football Kick system initialised")
end

-- ─────────────────────────────────────────────────────────────
--  GekkoFK_CanTrigger
--  Returns true if conditions allow a Football Kick right now.
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoFK_CanTrigger()
    if self._fkActive then return false end
    if CurTime() < (self._fkNextT or 0) then return false end

    -- Jump / crouch guards
    local js = self:GetGekkoJumpState()
    if js ~= self.JUMP_NONE then return false end
    if self._gekkoCrouching then return false end

    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return false end

    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist > FK_TRIGGER_DIST_MAX then return false end

    -- Must be facing the enemy (same cone as damage)
    local toEnemy = (enemy:GetPos() - self:GetPos()):GetNormalized()
    local dot     = self:GetForward():Dot(toEnemy)
    if dot < FK_CONE_DOT then return false end

    return true
end

-- ─────────────────────────────────────────────────────────────
--  GekkoFK_Execute
--  Starts the Football Kick sequence.
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoFK_Execute()
    if self._fkActive then return end

    self._fkActive      = true
    self._fkStartTime   = CurTime()
    self._fkDamageFired = false
    self._fkNextT       = CurTime() + FK_COOLDOWN

    -- Suppress VJ animation override for the full duration
    self._gekkoSuppressActivity = CurTime() + FK_DURATION + 0.1

    -- Freeze locomotion during the kick
    self.VJ_CanMoveThink = false

    -- Pulse the NW int to trigger client bone driver
    self._fkPulseCount = (self._fkPulseCount or 0) + 1
    self:SetNWInt(FK_NW_PULSE, self._fkPulseCount)

    print(string.format("[GekkoFK] EXECUTE  pulse=%d  dur=%.2f", self._fkPulseCount, FK_DURATION))
end

-- ─────────────────────────────────────────────────────────────
--  GekkoFK_ApplyDamage
--  Forward-cone area damage at the moment the leg extends.
-- ─────────────────────────────────────────────────────────────
local function FK_ApplyDamage(ent)
    local origin  = ent:GetPos() + Vector(0, 0, 60)  -- approx leg impact height
    local forward = ent:GetForward()

    local dmgInfo = DamageInfo()
    dmgInfo:SetAttacker(ent)
    dmgInfo:SetInflictor(ent)
    dmgInfo:SetDamageType(DMG_CLUB)
    dmgInfo:SetDamage(FK_DAMAGE_AMOUNT)

    local hit = false

    for _, ent2 in ipairs(ents.FindInSphere(origin, FK_DAMAGE_RADIUS)) do
        if not IsValid(ent2) then continue end
        if ent2 == ent then continue end
        if not ent2:IsNPC() and not ent2:IsPlayer() then continue end
        if ent:IsEnemy(ent2) == false then continue end  -- don't hurt allies

        local toTarget = (ent2:GetPos() - ent:GetPos()):GetNormalized()
        local dot      = forward:Dot(toTarget)
        if dot < FK_CONE_DOT then continue end

        -- Direction of force: mix of forward push and slight upward
        local forceDir = (forward * 0.85 + Vector(0, 0, 0.15)):GetNormalized()
        dmgInfo:SetDamageForce(forceDir * FK_FORCE_SCALE)
        dmgInfo:SetDamagePosition(ent2:GetPos())

        ent2:TakeDamageInfo(dmgInfo)
        hit = true

        print(string.format("[GekkoFK] HIT  target=%s  dist=%.0f  dot=%.2f",
            tostring(ent2), ent:GetPos():Distance(ent2:GetPos()), dot))
    end

    -- Impact effects regardless of hit
    local e = EffectData()
    e:SetOrigin(origin + forward * FK_DAMAGE_RADIUS * 0.5)
    e:SetNormal(forward)
    e:SetMagnitude(8)
    e:SetScale(2)
    e:SetRadius(40)
    util.Effect("ManhackSparks", e)

    util.ScreenShake(origin, hit and 20 or 10, 18, 0.25, 600)

    ent:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 6) .. ".wav", 95, 75)
end

-- ─────────────────────────────────────────────────────────────
--  GekkoFK_Think
--  Called every server tick from ENT:OnThink()
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoFK_Think()
    if not self._fkActive then return end

    local now     = CurTime()
    local elapsed = now - self._fkStartTime
    local t       = elapsed / FK_DURATION

    -- Damage fires once as t crosses into Phase 3
    if not self._fkDamageFired and t >= FK_DAMAGE_T then
        self._fkDamageFired = true
        FK_ApplyDamage(self)
    end

    -- Animation finished
    if t >= 1.0 then
        self._fkActive       = false
        self.VJ_CanMoveThink = true
        print("[GekkoFK] COMPLETE  elapsed=" .. string.format("%.2f", elapsed))
    end
end

-- ─────────────────────────────────────────────────────────────
--  GekkoFK_ShouldTrigger
--  External check used by OnThink (not OnRangeAttackExecute).
--  Melee 5 fires independently of the range attack roll.
-- ─────────────────────────────────────────────────────────────
function ENT:GekkoFK_ShouldTrigger()
    return self:GekkoFK_CanTrigger()
end
