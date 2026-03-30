-- ============================================================
--  npc_vj_gekko / init.lua
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
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

local MG_ROUNDS   = 24
local MG_INTERVAL = 0.149
local MG_DAMAGE   = 20
local MG_SPREAD   = 0.4

local WMODE_MG      = 1
local WMODE_MISSILE = 2

local JUMP_STATE_NAMES = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }

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
--  Animation translations
-- ============================================================
function ENT:SetAnimationTranslations(wepHoldType)
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
    self.AnimationTranslations[ACT_WALK]                  = runSeq
    self.AnimationTranslations[ACT_RUN]                   = walkSeq
    self.AnimationTranslations[ACT_WALK_AIM]              = runSeq
    self.AnimationTranslations[ACT_RUN_AIM]               = walkSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK1]         = idleSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK2]         = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK1] = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK2] = idleSeq
    self.AnimationTranslations[ACT_IDLE_ANGRY]            = idleSeq
    self.AnimationTranslations[ACT_COMBAT_IDLE]           = idleSeq

    self.GekkoSeq_Walk = runSeq
    self.GekkoSeq_Run  = walkSeq
    self.GekkoSeq_Idle = idleSeq
end

-- ============================================================
--  MaintainIdleAnimation override
--  VJBase registers a global Think hook (funcAnimThink) during
--  Initialize() that calls MaintainIdleAnimation() every tick,
--  bypassing VJ_AnimationThink entirely.  While crouching OR
--  during a jump phase we must block it so our own sequence
--  control is not overwritten.
-- ============================================================
function ENT:MaintainIdleAnimation(force)
    -- Block during crouch
    if self._gekkoCrouching then return end
    -- Block during jump phases (jump_system owns the sequence then)
    local js = self:GetGekkoJumpState()
    if js == self.JUMP_RISING or js == self.JUMP_FALLING or js == self.JUMP_LAND then
        return
    end
    self.BaseClass.MaintainIdleAnimation(self, force)
end

-- ============================================================
--  MaintainActivity override
-- ============================================================
function ENT:MaintainActivity()
    if self._gekkoSuppressActivity and CurTime() < self._gekkoSuppressActivity then
        return
    end
    if self._gekkoCrouching then return end
    local js = self:GetGekkoJumpState()
    if js == self.JUMP_RISING or js == self.JUMP_FALLING or js == self.JUMP_LAND then
        return
    end
    self.BaseClass.MaintainActivity(self)
end

-- ============================================================
--  VJ_AnimationThink override
-- ============================================================
function ENT:VJ_AnimationThink()
    if self._gekkoSuppressActivity and CurTime() < self._gekkoSuppressActivity then
        return
    end
    if self._gekkoCrouching then return end
    local js = self:GetGekkoJumpState()
    if js == self.JUMP_RISING or js == self.JUMP_FALLING or js == self.JUMP_LAND then
        return
    end
    self.BaseClass.VJ_AnimationThink(self)
end

-- ============================================================
--  TranslateActivity
-- ============================================================
function ENT:TranslateActivity(act)
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING  and self._seqJump and self._seqJump ~= -1 then
        return self._seqJump
    end
    if jumpState == self.JUMP_FALLING and self._seqFall and self._seqFall ~= -1 then
        return self._seqFall
    end
    if jumpState == self.JUMP_LAND    and self._seqLand and self._seqLand ~= -1 then
        return self._seqLand
    end

    if self._gekkoCrouching then
        local cidle = self.GekkoSeq_CrouchIdle
        if cidle and cidle ~= -1 then return cidle end
    end

    if act == ACT_WALK or act == ACT_WALK_AIM then
        return self.GekkoSeq_Walk or act
    elseif act == ACT_RUN or act == ACT_RUN_AIM then
        return self.GekkoSeq_Run or act
    elseif act == ACT_IDLE then
        return self.GekkoSeq_Idle or act
    end
    return self.BaseClass.TranslateActivity(self, act)
end

-- ============================================================
--  Core animation update
-- ============================================================
function ENT:GekkoUpdateAnimation()
    if self.Flinching then return end

    local jumpState = self:GetGekkoJumpState()

    if jumpState == self.JUMP_RISING  or
       jumpState == self.JUMP_FALLING or
       jumpState == self.JUMP_LAND    or
       (self._gekkoJustJumped and CurTime() < self._gekkoJustJumped) then
        self:SetPoseParameter("move_x", 0)
        self:SetPoseParameter("move_y", 0)
        return
    end

    -- Run crouch logic first — returns true if crouch owns this tick.
    if self:GeckoCrouch_Update() then return end

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

    if targetSeq ~= self.Gekko_LastSeqIdx then
        SafeResetSequence(self, targetSeq)
        self.Gekko_LastSeqIdx = targetSeq
        if targetSeq == self.GekkoSeq_Run then
            self.Gekko_LastSeqName = "run"
        elseif targetSeq == self.GekkoSeq_Walk then
            self.Gekko_LastSeqName = "walk"
        else
            self.Gekko_LastSeqName = "idle"
        end
    end

    self:SetPlaybackRate(arate)
    self:SetNWFloat("GekkoSpeed", vel)
    self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)
end

-- ============================================================
--  SafeInitVJTables
--  Ensures all VJBase sound/damage tables exist so that
--  VJ_ApplyDamageInfo never errors with "temptable is nil".
--  Called from both Init() and Activate() because VJBase's
--  BaseClass.Activate() may wipe or re-create these tables.
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
    self._weaponMode         = WMODE_MG
    self._gekkoRunning       = false
    self._gekkoLastEnemyDist = nil
    self._gekkoLastPos       = self:GetPos()
    self._gekkoLastTime      = CurTime() - 0.1
    self._gekkoSuppressActivity = 0

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

        selfRef.GekkoSpineBone = selfRef:LookupBone("b_spine4")    or -1
        selfRef.GekkoLGunBone  = selfRef:LookupBone("b_l_gunrack") or -1
        selfRef.GekkoRGunBone  = selfRef:LookupBone("b_r_gunrack") or -1

        local mgAtt   = selfRef:GetAttachment(ATT_MACHINEGUN)
        local misLAtt = selfRef:GetAttachment(ATT_MISSILE_L)
        local misRAtt = selfRef:GetAttachment(ATT_MISSILE_R)

        print(string.format(
            "[GekkoNPC] Deferred activate complete | walk=%d run=%d idle=%d | cidle=%d c_walk=%d | Spine4=%d | MG=%s MissL=%s MissR=%s",
            selfRef.GekkoSeq_Walk, selfRef.GekkoSeq_Run, selfRef.GekkoSeq_Idle,
            selfRef.GekkoSeq_CrouchIdle, selfRef.GekkoSeq_CrouchWalk,
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
    -- Re-guard tables after BaseClass.Activate may have altered them.
    SafeInitVJTables(self)
    print("[GekkoNPC] Activate() called by engine (future VJ path)")
end

-- ============================================================
--  Damage override
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    dmginfo:SetDamageForce(Vector(0, 0, 0))
    dmginfo:SetDamagePosition(self:GetPos())
    self.BaseClass.OnTakeDamage(self, dmginfo)
end

-- ============================================================
--  Think
-- ============================================================
function ENT:OnThink()
    self:GekkoJump_Think()

    if self:GekkoJump_ShouldJump() then
        self:GekkoJump_Execute()
    end

    self:GekkoUpdateAnimation()

    if true and CurTime() > self.Gekko_NextDebugT then
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
            "[GekkoDBG] vel=%.1f  seq=%s  run=%s  dist=%d  src=%s  spd=%d  jump=%s  crouch=%s  VJ_Crouch=%s  ceiling=%s",
            self:GetNWFloat("GekkoSpeed", 0),
            tostring(self.Gekko_LastSeqName),
            tostring(self._gekkoRunning),
            dist, src,
            self.MoveSpeed or 0,
            JUMP_STATE_NAMES[self:GetGekkoJumpState()] or "?",
            tostring(self._gekkoCrouching),
            tostring(self.VJ_IsBeingCrouched),
            tostring(self._gekkoCeilingHit)
        ))
        self.Gekko_NextDebugT = CurTime() + 1
    end
end

-- ============================================================
--  Range attack
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end

    if self:GekkoJump_IsAirborne() then return true end

    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local mode   = self._weaponMode
    self._weaponMode = (mode == WMODE_MG) and WMODE_MISSILE or WMODE_MG

    if mode == WMODE_MG then
        if self._mgBurstActive then return true end
        self._mgBurstActive = true
        local entRef = self

        for i = 0, MG_ROUNDS - 1 do
            timer.Simple(i * MG_INTERVAL, function()
                if not IsValid(entRef) then return end

                local curEnemy = GetActiveEnemy(entRef)
                local curAim   = IsValid(curEnemy)
                    and (curEnemy:GetPos() + Vector(0, 0, 40))
                    or  aimPos

                local src
                local mgAtt = entRef:GetAttachment(ATT_MACHINEGUN)
                if mgAtt then
                    src = mgAtt.Pos
                else
                    local boneIdx = entRef.GekkoLGunBone
                    if boneIdx and boneIdx >= 0 then
                        local m = entRef:GetBoneMatrix(boneIdx)
                        if m then src = m:GetTranslation() + m:GetForward() * 28 end
                    end
                    src = src or (entRef:GetPos() + Vector(0, 0, 200))
                end

                local dir = (curAim - src):GetNormalized()

                entRef:FireBullets({
                    Attacker   = entRef,
                    Damage     = MG_DAMAGE,
                    Dir        = dir,
                    Src        = src,
                    AmmoType   = "AR2",
                    TracerName = "Tracer",
                    Num        = 1,
                    Spread     = Vector(
                        (math.random() - 0.5) * 2 * MG_SPREAD,
                        (math.random() - 0.5) * 2 * MG_SPREAD,
                        0
                    ),
                })

                local eff = EffectData()
                eff:SetOrigin(src)
                eff:SetNormal(dir)
                util.Effect("MuzzleFlash", eff)
                entRef:EmitSound("weapons/ar2/fire1.wav", 75, math.random(95, 115))

                if i == MG_ROUNDS - 1 then
                    entRef._mgBurstActive = false
                end
            end)
        end

        return true
    end

    self._missileCount = (self._missileCount or 0) + 1
    local missileAttIdx = (self._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R
    local misAtt = self:GetAttachment(missileAttIdx)
    local src    = misAtt and misAtt.Pos or (self:GetPos() + Vector(0, 0, 160))
    local dir    = (aimPos - src):GetNormalized()

    local rocket = ents.Create("obj_vj_rocket")
    if IsValid(rocket) then
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(self)
        rocket:Spawn()
        rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1200) end
    end

    local eff = EffectData()
    eff:SetOrigin(src)
    eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)

    return true
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
