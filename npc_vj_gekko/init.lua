-- ============================================================
--  npc_vj_gekko / init.lua
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("crush_system.lua")
include("jump_system.lua")
include("crouch_system.lua")

-- ============================================================
--  Constants
-- ============================================================
local ATT_MACHINEGUN = 3
local ATT_MISSILE_L  = 9
local ATT_MISSILE_R  = 10

local ANIM_WALK_SPEED    = 184
local ANIM_RUN_SPEED     = 20

local RUN_ENGAGE_DIST    = 2000
local RUN_DISENGAGE_DIST = 1600

local MG_ROUNDS_MIN = 9
local MG_ROUNDS_MAX = 36
local MG_INTERVAL   = 0.149
local MG_DAMAGE     = 20
local MG_SPREAD_MIN = 0.2
local MG_SPREAD_MAX = 2.0

local WMODE_MG      = 1
local WMODE_MISSILE = 2

local JUMP_STATE_NAMES = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }

local HEAD_Z_FRACTION = 0.65

-- ============================================================
--  Helpers
-- ============================================================
local function GetActiveEnemy(ent)
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

local function SafeResetSequence(ent, seq)
    if seq and seq ~= -1 then
        ent:ResetSequence(seq)
    end
end

-- ============================================================
--  AnimApply
-- ============================================================
function ENT:AnimApply()
    if CurTime() < (self._gekkoSuppressActivity or 0) then
        return true
    end
    local js = self:GetGekkoJumpState()
    if js == self.JUMP_RISING  or
       js == self.JUMP_FALLING or
       js == self.JUMP_LAND    then
        return true
    end
    return false
end

-- ============================================================
--  Animation translations
-- ============================================================
function ENT:SetAnimationTranslations()
    if not self.AnimationTranslations then
        self.AnimationTranslations = {}
    end

    local walkSeq = self:LookupSequence("walk")
    local runSeq  = self:LookupSequence("run")
    local idleSeq = self:LookupSequence("idle")

    walkSeq = (walkSeq and walkSeq ~= -1) and walkSeq or 0
    runSeq  = (runSeq  and runSeq  ~= -1) and runSeq  or 0
    idleSeq = (idleSeq and idleSeq ~= -1) and idleSeq or 0

    self.AnimationTranslations[ACT_IDLE]                  = idleSeq
    self.AnimationTranslations[ACT_WALK]                  = walkSeq
    self.AnimationTranslations[ACT_RUN]                   = runSeq
    self.AnimationTranslations[ACT_WALK_AIM]              = walkSeq
    self.AnimationTranslations[ACT_RUN_AIM]               = runSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK1]         = idleSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK2]         = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK1] = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK2] = idleSeq
    self.AnimationTranslations[ACT_IDLE_ANGRY]            = idleSeq
    self.AnimationTranslations[ACT_COMBAT_IDLE]           = idleSeq

    self.GekkoSeq_Walk = walkSeq
    self.GekkoSeq_Run  = runSeq
    self.GekkoSeq_Idle = idleSeq
end

-- ============================================================
--  Core animation update
-- ============================================================
function ENT:GekkoUpdateAnimation()
    if self.Flinching then return end

    local now    = CurTime()
    local curPos = self:GetPos()
    local vel    = 0

    if self._gekkoLastPos and self._gekkoLastTime then
        local dt = now - self._gekkoLastTime
        if dt > 0 then
            vel = (curPos - self._gekkoLastPos):Length() / dt
        end
    end
    self._gekkoLastPos  = curPos
    self._gekkoLastTime = now
    self:SetNWFloat("GekkoSpeed", vel)

    if now < (self._gekkoSuppressActivity or 0) then return end
    if self._gekkoSkipAnimTick then
        self._gekkoSkipAnimTick = false
        return
    end

    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING  or
       jumpState == self.JUMP_FALLING or
       jumpState == self.JUMP_LAND    or
       (self._gekkoJustJumped and now < self._gekkoJustJumped) then
        self:SetPoseParameter("move_x", 0)
        self:SetPoseParameter("move_y", 0)
        return
    end

    if self:GeckoCrouch_Update() then return end

    local enemy = GetActiveEnemy(self)
    local dist  = 0
    if IsValid(enemy) then
        dist = self:GetPos():Distance(enemy:GetPos())
        self._gekkoLastEnemyDist = dist
    elseif self._gekkoLastEnemyDist then
        dist = self._gekkoLastEnemyDist
    end

    if dist > RUN_ENGAGE_DIST then
        self._gekkoRunning = true
    elseif dist < RUN_DISENGAGE_DIST then
        self._gekkoRunning = false
    end

    local targetSeq, arate
    if vel > 5 then
        if self._gekkoRunning then
            targetSeq = self.GekkoSeq_Run
            arate     = vel / ANIM_RUN_SPEED
        else
            targetSeq = self.GekkoSeq_Walk
            arate     = vel / ANIM_WALK_SPEED
        end
    elseif self._gekkoRunning then
        targetSeq = self.GekkoSeq_Run
        arate     = 0.5
    else
        targetSeq = self.GekkoSeq_Idle
        arate     = 1.0
    end

    arate = math.Clamp(arate, 0.5, 3.0)

    if targetSeq and targetSeq ~= -1 then
        SafeResetSequence(self, targetSeq)
    end

    if targetSeq == self.GekkoSeq_Run then
        self.Gekko_LastSeqName = "run"
    elseif targetSeq == self.GekkoSeq_Walk then
        self.Gekko_LastSeqName = "walk"
    else
        self.Gekko_LastSeqName = "idle"
    end
    self.Gekko_LastSeqIdx = targetSeq

    self:SetPlaybackRate(arate)
    self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)
end

-- ============================================================
--  SafeInitVJTables
-- ============================================================
local function SafeInitVJTables(ent)
    if not ent.VJ_AddOnDamage    then ent.VJ_AddOnDamage    = {} end
    if not ent.VJ_DamageInfos    then ent.VJ_DamageInfos    = {} end
    if not ent.VJ_DeathSounds    then ent.VJ_DeathSounds    = {} end
    if not ent.VJ_PainSounds     then ent.VJ_PainSounds     = {} end
    if not ent.VJ_IdleSounds     then ent.VJ_IdleSounds     = {} end
    if not ent.VJ_FootstepSounds then ent.VJ_FootstepSounds = {} end
    if not ent.AnimationTranslations then ent.AnimationTranslations = {} end
end

-- ============================================================
--  Init
-- ============================================================
function ENT:Init()
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetSkin(1)

    self.GekkoSpineBone = self:LookupBone("b_spine4")    or -1
    self.GekkoLGunBone  = self:LookupBone("b_l_gunrack") or -1
    self.GekkoRGunBone  = self:LookupBone("b_r_gunrack") or -1

    self.Gekko_NextDebugT    = 0
    self.Gekko_LastSeqName   = ""
    self.Gekko_LastSeqIdx    = -1
    self._missileCount       = 0
    self._mgBurstActive      = false
    self._mgBurstEndT        = 0
    -- _weaponMode always starts on MG; missile is the follow-up, never the opener
    self._weaponMode         = WMODE_MG
    self._gekkoRunning       = false
    self._gekkoLastEnemyDist = nil
    self._gekkoLastPos       = self:GetPos()
    self._gekkoLastTime      = CurTime() - 0.1
    self._gekkoSuppressActivity = 0
    self._gekkoSkipAnimTick  = false
    self._crushHitTimes      = {}

    self:SetNWBool("GekkoMGFiring",  false)
    self:SetNWInt("GekkoJumpDust",   0)
    self:SetNWInt("GekkoLandDust",   0)

    SafeInitVJTables(self)
    self:GekkoJump_Init()
    self:GeckoCrouch_Init()

    local selfRef = self
    timer.Simple(0, function()
        if not IsValid(selfRef) then return end

        selfRef:GekkoJump_Activate()

        selfRef.StartMoveSpeed = selfRef.MoveSpeed or 150
        selfRef.StartRunSpeed  = selfRef.RunSpeed  or 300
        selfRef.StartWalkSpeed = selfRef.WalkSpeed or 150

        local walkSeq = selfRef:LookupSequence("walk")
        local runSeq  = selfRef:LookupSequence("run")
        local idleSeq = selfRef:LookupSequence("idle")
        selfRef.GekkoSeq_Walk = (walkSeq and walkSeq ~= -1) and walkSeq or 0
        selfRef.GekkoSeq_Run  = (runSeq  and runSeq  ~= -1) and runSeq  or 0
        selfRef.GekkoSeq_Idle = (idleSeq and idleSeq ~= -1) and idleSeq or 0

        selfRef:GeckoCrouch_CacheSeqs()
        selfRef:SetAnimationTranslations()

        selfRef.GekkoSpineBone = selfRef:LookupBone("b_spine4")    or -1
        selfRef.GekkoLGunBone  = selfRef:LookupBone("b_l_gunrack") or -1
        selfRef.GekkoRGunBone  = selfRef:LookupBone("b_r_gunrack") or -1

        local mgAtt   = selfRef:GetAttachment(ATT_MACHINEGUN)
        local misLAtt = selfRef:GetAttachment(ATT_MISSILE_L)
        local misRAtt = selfRef:GetAttachment(ATT_MISSILE_R)

        print(string.format(
            "[GekkoNPC] Deferred activate | walk=%d run=%d idle=%d | c_walk=%d cidle=%d | Spine4=%d | MG=%s MissL=%s MissR=%s",
            selfRef.GekkoSeq_Walk, selfRef.GekkoSeq_Run, selfRef.GekkoSeq_Idle,
            selfRef.GekkoSeq_CrouchWalk or -1,
            selfRef.GekkoSeq_CrouchIdle or -1,
            selfRef.GekkoSpineBone,
            mgAtt   and "OK" or "MISSING",
            misLAtt and "OK" or "MISSING",
            misRAtt and "OK" or "MISSING"
        ))
    end)

    print("[GekkoNPC] Init() complete — deferred activate queued")
end

-- ============================================================
--  Activate
-- ============================================================
function ENT:Activate()
    local base = self.BaseClass
    if base and base.Activate and base.Activate ~= ENT.Activate then
        base.Activate(self)
    end
    SafeInitVJTables(self)
end

-- ============================================================
--  Damage override
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    dmginfo:SetDamageForce(Vector(0, 0, 0))

    local hitPos = dmginfo:GetDamagePosition()

    if hitPos == vector_origin then
        local inflictor = dmginfo:GetInflictor()
        if IsValid(inflictor) then
            hitPos = inflictor:GetPos()
        else
            dmginfo:SetDamagePosition(self:GetPos())
            self.BaseClass.OnTakeDamage(self, dmginfo)
            return
        end
    end

    local _, maxs = self:GetCollisionBounds()
    local headZ   = self:GetPos().z + maxs.z * HEAD_Z_FRACTION

    if hitPos.z > headZ then
        dmginfo:ScaleDamage(1 / 3)
    end

    dmginfo:SetDamagePosition(self:GetPos())
    self.BaseClass.OnTakeDamage(self, dmginfo)
end

-- ============================================================
--  Think
-- ============================================================
function ENT:OnThink()
    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end

    self:GekkoJump_Think()
    if self:GekkoJump_ShouldJump() then
        self:GekkoJump_Execute()
    end

    self:GekkoUpdateAnimation()
    self:GeckoCrush_Think()

    if CurTime() > self.Gekko_NextDebugT then
        local enemy = GetActiveEnemy(self)
        local dist, src
        if IsValid(enemy) then
            dist = math.floor(self:GetPos():Distance(enemy:GetPos()))
            src  = IsValid(self.VJ_TheEnemy) and "vj" or "engine"
        elseif self._gekkoLastEnemyDist then
            dist = math.floor(self._gekkoLastEnemyDist)
            src  = "cached"
        else
            dist = -1
            src  = "none"
        end
        print(string.format(
            "[GekkoDBG] vel=%.1f  seq=%s  run=%s  dist=%d  src=%s  spd=%d  jump=%s  crouch=%s  VJ_Crouch=%s  ceil=%s  wmode=%s  mgActive=%s",
            self:GetNWFloat("GekkoSpeed", 0),
            tostring(self.Gekko_LastSeqName),
            tostring(self._gekkoRunning),
            dist, src,
            self.MoveSpeed or 0,
            JUMP_STATE_NAMES[self:GetGekkoJumpState()] or "?",
            tostring(self._gekkoCrouching),
            tostring(self.VJ_IsBeingCrouched),
            tostring(self._gekkoCeilingHit),
            (self._weaponMode == WMODE_MG) and "MG" or "MISSILE",
            tostring(self._mgBurstActive)
        ))
        self.Gekko_NextDebugT = CurTime() + 1
    end
end

-- ============================================================
--  MG burst
--  Called only when _weaponMode == WMODE_MG and no burst is
--  already in flight. Flips mode to MISSILE *after* committing.
-- ============================================================
local function FireMGBurst(ent, enemy)
    -- Guard: never double-fire
    if ent._mgBurstActive then
        print("[GekkoMG] Burst skipped — already active")
        return false
    end

    local aimPos   = enemy:GetPos() + Vector(0, 0, 40)
    local mgRounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local mgSpread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)

    ent._mgBurstActive = true
    ent._mgBurstEndT   = CurTime() + (mgRounds * MG_INTERVAL) + 1.0
    ent:SetNWBool("GekkoMGFiring", true)

    -- Flip mode NOW, after we have committed to firing
    ent._weaponMode = WMODE_MISSILE

    print(string.format("[GekkoMG] Burst | rounds=%d  spread=%.2f", mgRounds, mgSpread))

    for i = 0, mgRounds - 1 do
        timer.Simple(i * MG_INTERVAL, function()
            if not IsValid(ent) then return end

            local curEnemy = GetActiveEnemy(ent)
            local curAim   = IsValid(curEnemy)
                and (curEnemy:GetPos() + Vector(0, 0, 40))
                or  aimPos

            local src
            local mgAtt = ent:GetAttachment(ATT_MACHINEGUN)
            if mgAtt then
                src = mgAtt.Pos
            else
                local boneIdx = ent.GekkoLGunBone
                if boneIdx and boneIdx >= 0 then
                    local m = ent:GetBoneMatrix(boneIdx)
                    if m then src = m:GetTranslation() + m:GetForward() * 28 end
                end
                src = src or (ent:GetPos() + Vector(0, 0, 200))
            end

            local dir = (curAim - src):GetNormalized()

            ent:FireBullets({
                Attacker   = ent,
                Damage     = MG_DAMAGE,
                Dir        = dir,
                Src        = src,
                AmmoType   = "AR2",
                TracerName = "Tracer",
                Num        = 1,
                Spread     = Vector(
                    (math.random() - 0.5) * 2 * mgSpread,
                    (math.random() - 0.5) * 2 * mgSpread,
                    0
                ),
            })

            local eff = EffectData()
            eff:SetOrigin(src)
            eff:SetNormal(dir)
            util.Effect("MuzzleFlash", eff)
            ent:EmitSound("weapons/ar2/fire1.wav", 75, math.random(95, 115))

            -- Last round: clear the burst flag
            if i == mgRounds - 1 then
                ent._mgBurstActive = false
                ent:SetNWBool("GekkoMGFiring", false)
            end
        end)
    end

    return true
end

-- ============================================================
--  Missile
--  Called only when _weaponMode == WMODE_MISSILE.
--  Flips mode back to MG after firing so the cycle continues.
-- ============================================================
local function FireMissile(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)

    ent._missileCount = (ent._missileCount or 0) + 1
    local missileAttIdx = (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R
    local misAtt = ent:GetAttachment(missileAttIdx)
    local src    = misAtt and misAtt.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local dir    = (aimPos - src):GetNormalized()

    local rocket = ents.Create("obj_vj_rocket")
    if IsValid(rocket) then
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(ent)
        rocket:Spawn()
        rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1200) end
    end

    local eff = EffectData()
    eff:SetOrigin(src)
    eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)

    -- Flip back to MG so next call fires bullets again
    ent._weaponMode = WMODE_MG

    return true
end

-- ============================================================
--  Range attack entry point
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end

    if self._weaponMode == WMODE_MG then
        return FireMGBurst(self, enemy)
    else
        return FireMissile(self, enemy)
    end
end

-- ============================================================
--  Death
-- ============================================================
function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end
    local attacker = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos      = self:GetPos()

    self:SetGekkoJumpState(self.JUMP_NONE)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetNWBool("GekkoMGFiring", false)

    timer.Simple(0.8, function()
        if not IsValid(self) then return end
        ParticleEffect("astw2_nightfire_explosion_generic", pos, angle_zero)
        self:EmitSound(VJ.PICK({
            "weapons/mgs3/explosion_01.wav",
            "weapons/mgs3/explosion_02.wav"
        }), 511, 100, 2)
        util.BlastDamage(self, attacker, pos, 512, 256)
    end)
end
