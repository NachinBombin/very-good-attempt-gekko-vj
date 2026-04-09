-- ============================================================
--  npc_vj_gekko / init.lua
--  + 5th weapon : Top-Attack Terror Missile   (sent_npc_topmissile)
--  + 6th weapon : Active-Track Ballistic Missile (sent_npc_trackmissile)
--  + 7th weapon : Orbit RPG (sent_orbital_rpg)
--  + 8th weapon : Nikita Missile (sent_nikita)
--  + Sonar Lock : net message to targeted player on TRACKMISSILE fire
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("crush_system.lua")
include("jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")

-- ============================================================
--  Net message pool
-- ============================================================
util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")  -- ThumperDust on FK360 landing kick

-- ============================================================
--  Constants
-- ============================================================
local ATT_MACHINEGUN = 3
local ATT_MISSILE_L  = 9
local ATT_MISSILE_R  = 10

local ANIM_WALK_SPEED    = 184
local ANIM_RUN_SPEED     = 20

local RUN_ENGAGE_DIST    = 2300
local RUN_DISENGAGE_DIST = 1600

-- Playback rate lerp speed (higher = snappier, lower = smoother)
local RATE_SMOOTH_SPEED  = 8.0

local MG_ROUNDS_MIN = 9
local MG_ROUNDS_MAX = 36
local MG_INTERVAL   = 0.15
local MG_DAMAGE     = 20
local MG_SPREAD_MIN = 0.2
local MG_SPREAD_MAX = 2.0

-- Weapon selection weights (must sum to 100)
local WWEIGHT_MG             = 35
local WWEIGHT_MISSILE_SINGLE = 20
local WWEIGHT_MISSILE_DOUBLE = 5
local WWEIGHT_GRENADE        = 10
local WWEIGHT_TOPMISSILE     = 10
local WWEIGHT_TRACKMISSILE   = 5
local WWEIGHT_ORBITRPG       = 10
local WWEIGHT_NIKITA         = 5

-- Double-salvo inaccuracy
local SALVO_SPREAD_XY = 220
local SALVO_SPREAD_Z  = 80
local SALVO_DELAY     = 0.8

-- Grenade launcher
local GL_COUNT_MIN    = 4
local GL_COUNT_MAX    = 8
local GL_INTERVAL     = 0.35
local GL_SPREAD_Y     = 250
local GL_LAUNCH_Z     = 180
local GL_SOUND_FIDGET = "mac_bo2_m32/fidget.wav"
local GL_SOUND_FIRE   = "mac_bo2_m32/fire.wav"
local GL_SOUND_INSERT = "mac_bo2_m32/insert.wav"
local GL_FIDGET_LEAD  = 0.5
local GL_GRENADE_TYPES = {
    "bombin_gas_grenade",
    "ent_gas_stun",
    "ent_flashbang",
}
local GL_TYPE_PARAMS = {
    ["bombin_gas_grenade"] = { speed = 2200, loft = 0.28 },
    ["ent_gas_stun"]       = { speed = 2750, loft = 0.35 },
    ["ent_flashbang"]      = { speed = 6500, loft = 0.42 },
}
local GL_TYPE_DEFAULT = { speed = 2650, loft = 0.35 }

-- ============================================================
--  Grenade sprite trail constants
-- ============================================================
local GL_TRAIL_MATERIAL  = "trails/smoke"
local GL_TRAIL_LIFETIME  = 1.8
local GL_TRAIL_STARTSIZE = 8
local GL_TRAIL_ENDSIZE   = 1
local GL_TRAIL_COLOR     = Color(235, 235, 235, 200)

local GL_SPARK_ATT_CYCLE = { ATT_MACHINEGUN, ATT_MISSILE_L, ATT_MISSILE_R }
local GL_SPARK_SCALE     = 0.5
local GL_SPARK_MAGNITUDE = 4
local GL_SPARK_RADIUS    = 10
local GL_VAPOR_EFFECT    = "SmokeEffect"
local GL_SMOKE_EFFECT    = "BlackSmoke"
local GL_VAPOR_SCALE     = 0.6
local GL_SMOKE_SCALE     = 0.4
local GL_SMOKE_EVERY     = 2

-- Shared missile constants
local TOPMISSILE_LAUNCH_Z  = 300
local MISSILE_MIN_DIST     = 1200
local MISSILE_SOUND_WARN   = "buttons/button17.wav"

local JUMP_STATE_NAMES = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }
local HEAD_Z_FRACTION  = 0.65
local BLOOD_DAMAGE_THRESHOLD = 900
local BLOOD_RANDOM_CHANCE    = 40
local GROUNDED_BLEED_CHANCE  = 0.85

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

-- Weapon roll
local function RollWeapon()
    local r = math.random(1, 100)
    local cum = 0
    cum = cum + WWEIGHT_MG;             if r <= cum then return "MG"           end
    cum = cum + WWEIGHT_MISSILE_SINGLE; if r <= cum then return "MISSILE"      end
    cum = cum + WWEIGHT_MISSILE_DOUBLE; if r <= cum then return "SALVO"        end
    cum = cum + WWEIGHT_GRENADE;        if r <= cum then return "GRENADE"      end
    cum = cum + WWEIGHT_TOPMISSILE;     if r <= cum then return "TOPMISSILE"   end
    cum = cum + WWEIGHT_TRACKMISSILE;   if r <= cum then return "TRACKMISSILE" end
    cum = cum + WWEIGHT_ORBITRPG;       if r <= cum then return "ORBITRPG"     end
    return "NIKITA"
end

local function SpawnRocket(ent, attIdx, aimPos, spread)
    local misAtt = ent:GetAttachment(attIdx)
    local src    = misAtt and misAtt.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local target = aimPos + (spread or Vector(0, 0, 0))
    local dir    = (target - src):GetNormalized()
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
end

local function SalvoSpread()
    return Vector(
        (math.random() - 0.5) * 2 * SALVO_SPREAD_XY,
        (math.random() - 0.5) * 2 * SALVO_SPREAD_XY,
        (math.random() - 0.5) * 2 * SALVO_SPREAD_Z
    )
end

local function GLSparkAtAttachment(ent, shotIndex)
    local cycle   = GL_SPARK_ATT_CYCLE
    local attIdx  = cycle[((shotIndex - 1) % #cycle) + 1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd = attData.Ang:Forward()
    local e   = EffectData()
    e:SetOrigin(attData.Pos + fwd * 4)
    e:SetNormal(fwd)
    e:SetEntity(ent)
    e:SetMagnitude(GL_SPARK_MAGNITUDE * GL_SPARK_SCALE)
    e:SetScale(GL_SPARK_SCALE)
    e:SetRadius(GL_SPARK_RADIUS)
    util.Effect("ManhackSparks", e)
end

local function GLVaporAtAttachment(ent, shotIndex)
    local cycle   = GL_SPARK_ATT_CYCLE
    local attIdx  = cycle[((shotIndex - 1) % #cycle) + 1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd    = attData.Ang:Forward()
    local origin = attData.Pos + fwd * 6
    local ev = EffectData()
    ev:SetOrigin(origin)
    ev:SetNormal(fwd)
    ev:SetScale(GL_VAPOR_SCALE)
    ev:SetMagnitude(1)
    util.Effect(GL_VAPOR_EFFECT, ev)
    if shotIndex % GL_SMOKE_EVERY == 0 then
        local es = EffectData()
        es:SetOrigin(origin + Vector(0, 0, 8))
        es:SetNormal(fwd)
        es:SetScale(GL_SMOKE_SCALE)
        es:SetMagnitude(1)
        util.Effect(GL_SMOKE_EFFECT, es)
    end
end

local function AttachGrenadeTrail(gren)
    if not IsValid(gren) then return end
    util.SpriteTrail(
        gren,
        0,
        GL_TRAIL_COLOR,
        false,
        GL_TRAIL_STARTSIZE,
        GL_TRAIL_ENDSIZE,
        GL_TRAIL_LIFETIME,
        1 / GL_TRAIL_STARTSIZE,
        GL_TRAIL_MATERIAL
    )
end

local function RerollNotMissile(ent, enemy, exclude)
    local reroll
    repeat reroll = RollWeapon() until reroll ~= exclude
    print("[GekkoMissile] Re-roll -> " .. reroll)
    if reroll == "MG" then return "MG"
    elseif reroll == "MISSILE" then return "MISSILE"
    elseif reroll == "SALVO" then return "SALVO"
    elseif reroll == "TOPMISSILE" then return "TOPMISSILE"
    elseif reroll == "TRACKMISSILE" then return "TRACKMISSILE"
    elseif reroll == "ORBITRPG" then return "ORBITRPG"
    elseif reroll == "NIKITA" then return "NIKITA"
    else return "GRENADE" end
end

-- ============================================================
--  Sonar Lock notification
-- ============================================================
local function SendSonarLock(enemy)
    if not IsValid(enemy) then return end
    if not enemy:IsPlayer() then return end
    net.Start("GekkoSonarLock")
    net.Send(enemy)
end

-- ============================================================
--  AnimApply
-- ============================================================
function ENT:AnimApply()
    if CurTime() < (self._gekkoSuppressActivity or 0) then return true end
    local js = self:GetGekkoJumpState()
    if js == self.JUMP_RISING or js == self.JUMP_FALLING or js == self.JUMP_LAND then
        return true
    end
    return false
end

-- ============================================================
--  Animation translations
-- ============================================================
function ENT:SetAnimationTranslations()
    if not self.AnimationTranslations then self.AnimationTranslations = {} end
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
        if dt > 0 then vel = (curPos - self._gekkoLastPos):Length() / dt end
    end
    self._gekkoLastPos  = curPos
    self._gekkoLastTime = now
    self:SetNWFloat("GekkoSpeed", vel)
    if now < (self._gekkoSuppressActivity or 0) then return end
    if self._gekkoSkipAnimTick then self._gekkoSkipAnimTick = false return end
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING or jumpState == self.JUMP_FALLING or jumpState == self.JUMP_LAND
    or (self._gekkoJustJumped and now < self._gekkoJustJumped) then
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

    -- Sequence change guard: only ResetSequence on actual change
    if targetSeq and targetSeq ~= -1 then
        if self._gekkoCurrentLocoSeq ~= targetSeq then
            self._gekkoCurrentLocoSeq = targetSeq
            self:ResetSequence(targetSeq)
        end
    end

    if targetSeq == self.GekkoSeq_Run then
        self.Gekko_LastSeqName = "run"
    elseif targetSeq == self.GekkoSeq_Walk then
        self.Gekko_LastSeqName = "walk"
    else
        self.Gekko_LastSeqName = "idle"
    end
    self.Gekko_LastSeqIdx = targetSeq

    -- Playback rate smoother: lerp instead of snap
    self._gekkoTargetRate = arate
    local smoothed = Lerp(FrameTime() * RATE_SMOOTH_SPEED, self:GetPlaybackRate(), self._gekkoTargetRate)
    self:SetPlaybackRate(smoothed)

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
    self._gekkoRunning       = false
    self._gekkoLastEnemyDist = nil
    self._gekkoLastPos       = self:GetPos()
    self._gekkoLastTime      = CurTime() - 0.1
    self._gekkoSuppressActivity = 0
    self._gekkoSkipAnimTick  = false
    self._crushHitTimes      = {}
    self._bloodSplatPulse    = 0
    self._gibCooldownT       = 0
    self._lastWeaponChoice   = ""
    self._glSparkCounter     = 0
    -- Sequence guard + rate smoother state
    self._gekkoCurrentLocoSeq = -1
    self._gekkoTargetRate     = 1.0
    self:SetNWBool("GekkoMGFiring",     false)
    self:SetNWInt("GekkoJumpDust",      0)
    self:SetNWInt("GekkoLandDust",      0)
    self:SetNWInt("GekkoFK360LandDust", 0)
    self:SetNWInt("GekkoBloodSplat",    0)
    SafeInitVJTables(self)
    self:GekkoJump_Init()
    self:GeckoCrouch_Init()
    self:GekkoLegs_Init()
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
        selfRef._gekkoCurrentLocoSeq = -1
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
            selfRef.GekkoSeq_CrouchWalk or -1, selfRef.GekkoSeq_CrouchIdle or -1,
            selfRef.GekkoSpineBone,
            mgAtt   and "OK" or "MISSING",
            misLAtt and "OK" or "MISSING",
            misRAtt and "OK" or "MISSING"
        ))
    end)
    print("[GekkoNPC] Init() complete -- deferred activate queued")
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
    if hitPos.z > headZ then dmginfo:ScaleDamage(1 / 3) end
    local rawDmg  = dmginfo:GetDamage()

    local doSplat
    if self._gekkoLegsDisabled then
        doSplat = (math.Rand(0, 1) < GROUNDED_BLEED_CHANCE)
    else
        doSplat = (math.random(1, BLOOD_RANDOM_CHANCE) == 1) or (rawDmg >= BLOOD_DAMAGE_THRESHOLD)
    end

    if doSplat then
        self._bloodSplatPulse = (self._bloodSplatPulse or 0) + 1
        local variant = math.random(1, 5)
        self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse * 8 + (variant - 1))
    end

    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)
    dmginfo:SetDamagePosition(self:GetPos())
    self.BaseClass.OnTakeDamage(self, dmginfo)
end

-- ============================================================
--  Think
-- ============================================================
function ENT:OnThink()
    if self._gekkoLegsDisabled then
        self:GekkoLegs_Think()
    end
    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end
    self:GekkoJump_Think()
    if self:GekkoJump_ShouldJump() then self:GekkoJump_Execute() end
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
            dist = -1 src = "none"
        end
        print(string.format(
            "[GekkoDBG] vel=%.1f seq=%s run=%s dist=%d(%s) spd=%d jump=%s crouch=%s mgActive=%s lastWpn=%s",
            self:GetNWFloat("GekkoSpeed", 0), tostring(self.Gekko_LastSeqName),
            tostring(self._gekkoRunning), dist, src, self.MoveSpeed or 0,
            JUMP_STATE_NAMES[self:GetGekkoJumpState()] or "?",
            tostring(self._gekkoCrouching), tostring(self._mgBurstActive),
            tostring(self._lastWeaponChoice)
        ))
        self.Gekko_NextDebugT = CurTime() + 1
    end
end

-- ============================================================
--  Weapon: MG burst
-- ============================================================
local function FireMGBurst(ent, enemy)
    if ent._mgBurstActive then return false end
    local aimPos   = enemy:GetPos() + Vector(0, 0, 40)
    local mgRounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local mgSpread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
    ent._mgBurstActive = true
    ent._mgBurstEndT   = CurTime() + (mgRounds * MG_INTERVAL) + 1.0
    ent:SetNWBool("GekkoMGFiring", true)
    for i = 0, mgRounds - 1 do
        timer.Simple(i * MG_INTERVAL, function()
            if not IsValid(ent) then return end
            local curEnemy = GetActiveEnemy(ent)
            local curAim   = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0,0,40)) or aimPos
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
                Attacker=ent, Damage=MG_DAMAGE, Dir=dir, Src=src,
                AmmoType="AR2", TracerName="Tracer", Num=1,
                Spread=Vector(mgSpread, mgSpread, mgSpread),
            })
            local eff = EffectData()
            eff:SetOrigin(src) eff:SetNormal(dir)
            util.Effect("MuzzleFlash", eff)
            ent:EmitSound("weapons/ar2/fire1.wav", 75, math.random(95, 115))
            if i == mgRounds - 1 then
                ent._mgBurstActive = false
                ent:SetNWBool("GekkoMGFiring", false)
            end
        end)
    end
    return true
end

-- ============================================================
--  Weapon: single accurate missile
-- ============================================================
local function FireMissile(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    ent._missileCount = (ent._missileCount or 0) + 1
    SpawnRocket(ent, (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R, aimPos, nil)
    return true
end

-- ============================================================
--  Weapon: double inaccurate salvo
-- ============================================================
local function FireDoubleSalvo(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    ent._missileCount = (ent._missileCount or 0) + 1
    SpawnRocket(ent, (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R, aimPos, SalvoSpread())
    timer.Simple(SALVO_DELAY, function()
        if not IsValid(ent) then return end
        local curEnemy = GetActiveEnemy(ent)
        local curAim   = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0,0,40)) or aimPos
        ent._missileCount = (ent._missileCount or 0) + 1
        SpawnRocket(ent, (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R, curAim, SalvoSpread())
    end)
    return true
end

-- ============================================================
--  Weapon: grenade launcher
-- ============================================================
local function FireGrenadeLauncher(ent, enemy)
    local count       = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    local grenadeType = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
    local typeParams  = GL_TYPE_PARAMS[grenadeType] or GL_TYPE_DEFAULT
    local forward = ent:GetForward()
    local right   = ent:GetRight()
    local origin  = ent:GetPos() + Vector(0, 0, GL_LAUNCH_Z)
    ent._glSparkCounter = 0
    ent:EmitSound(GL_SOUND_FIDGET, 80, 100, 1)
    timer.Simple(GL_FIDGET_LEAD, function()
        if not IsValid(ent) then return end
        ent:EmitSound(GL_SOUND_FIRE, 80, 100, 1)
    end)
    timer.Simple(GL_FIDGET_LEAD + (count - 1) * GL_INTERVAL + 0.1, function()
        if not IsValid(ent) then return end
        ent:EmitSound(GL_SOUND_INSERT, 80, 100, 1)
    end)
    for i = 0, count - 1 do
        local shotNumber = i + 1
        timer.Simple(GL_FIDGET_LEAD + i * GL_INTERVAL, function()
            if not IsValid(ent) then return end
            GLSparkAtAttachment(ent, shotNumber)
            GLVaporAtAttachment(ent, shotNumber)
            local scatter   = forward * math.Rand(300, 700)
                            + right   * ((math.random() - 0.5) * 2 * GL_SPREAD_Y)
            local spawnPos  = origin + scatter * 0.05
            local launchDir = scatter:GetNormalized()
            launchDir.z     = launchDir.z + typeParams.loft
            launchDir:Normalize()
            local gren = ents.Create(grenadeType)
            if IsValid(gren) then
                gren:SetPos(spawnPos)
                gren:SetAngles(launchDir:Angle())
                gren:SetOwner(ent)
                gren:Spawn()
                gren:Activate()
                local phys = gren:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(launchDir * typeParams.speed)
                    phys:SetAngleVelocity(Vector(
                        math.Rand(-200,200), math.Rand(-200,200), math.Rand(-200,200)
                    ))
                end
                AttachGrenadeTrail(gren)
            end
        end)
    end
    return true
end

-- ============================================================
--  Weapon: top-attack terror missile  (5th)
-- ============================================================
local function FireTopMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        print(string.format("[GekkoTM] Too close (%.0f) -- re-rolling", dist))
        local alt = RerollNotMissile(ent, enemy, "TOPMISSILE")
        if alt == "MG" then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE" then return FireMissile(ent, enemy)
        elseif alt == "SALVO" then return FireDoubleSalvo(ent, enemy)
        elseif alt == "ORBITRPG" then return FireOrbitRpg(ent, enemy)
        else return FireGrenadeLauncher(ent, enemy) end
    end
    sound.Play(MISSILE_SOUND_WARN, ent:GetPos(), 511, 60)
    local launchPos = ent:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local missile = ents.Create("sent_npc_topmissile")
    if not IsValid(missile) then
        print("[GekkoTM] ERROR: create failed")
        return FireGrenadeLauncher(ent, enemy)
    end
    missile.Owner  = ent
    missile.Target = enemy:GetPos() + Vector(0, 0, 40)
    missile:SetPos(launchPos)
    missile:SetAngles(Angle(-90, ent:GetAngles().y, 0))
    missile:Spawn()
    missile:Activate()
    print(string.format("[GekkoTM] Launched | dist=%.0f", dist))
    return true
end

-- ============================================================
--  Weapon: active-track then ballistic missile  (6th)
-- ============================================================
local function FireTrackMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        print(string.format("[GekkoTRK] Too close (%.0f) -- re-rolling", dist))
        local alt = RerollNotMissile(ent, enemy, "TRACKMISSILE")
        if alt == "MG" then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE" then return FireMissile(ent, enemy)
        elseif alt == "SALVO" then return FireDoubleSalvo(ent, enemy)
        elseif alt == "TOPMISSILE" then return FireTopMissile(ent, enemy)
        elseif alt == "ORBITRPG" then return FireOrbitRpg(ent, enemy)
        else return FireGrenadeLauncher(ent, enemy) end
    end
    SendSonarLock(enemy)
    sound.Play(MISSILE_SOUND_WARN, ent:GetPos(), 511, 60)
    local launchPos = ent:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local missile = ents.Create("sent_npc_trackmissile")
    if not IsValid(missile) then
        print("[GekkoTRK] ERROR: create failed")
        return FireGrenadeLauncher(ent, enemy)
    end
    missile.Owner    = ent
    missile.Target   = enemy:GetPos() + Vector(0, 0, 40)
    missile.TrackEnt = enemy
    missile:SetPos(launchPos)
    missile:SetAngles(Angle(-90, ent:GetAngles().y, 0))
    missile:Spawn()
    missile:Activate()
    print(string.format("[GekkoTRK] Launched | dist=%.0f  tracking=%s", dist, tostring(enemy)))
    return true
end

-- ============================================================
--  Weapon: Orbit RPG (7th)
--  Fires sent_orbital_rpg from the rocket launcher attachment.
--  Direction = attachment-to-enemy aim angle at launch time.
--  The missile flies straight in that direction; orbital wobble
--  is handled entirely inside sent_orbital_rpg.
-- ============================================================
local function FireOrbitRpg(ent, enemy)
    ent._missileCount = (ent._missileCount or 0) + 1
    local attIdx  = (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R
    local attData = ent:GetAttachment(attIdx)
    local src     = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local aimPos  = enemy:GetPos() + Vector(0, 0, 40)
    local dir     = (aimPos - src):GetNormalized()

    -- Grey smoke muzzle puff
    local eff = EffectData()
    eff:SetOrigin(src)
    eff:SetNormal(dir)
    eff:SetScale(0.6)
    eff:SetMagnitude(1)
    util.Effect("SmokeEffect", eff)

    local rpg = ents.Create("sent_orbital_rpg")
    if not IsValid(rpg) then
        print("[GekkoORBIT] ERROR: sent_orbital_rpg create failed -- falling back")
        return FireMissile(ent, enemy)
    end
    rpg:SetPos(src)
    rpg:SetAngles(dir:Angle())  -- direction baked into angles; missile reads GetForward() on Initialize
    rpg:SetOwner(ent)
    rpg:Spawn()
    rpg:Activate()

    print(string.format("[GekkoORBIT] Launched | att=%d dist=%.0f",
        attIdx, ent:GetPos():Distance(enemy:GetPos())))
    return true
end

-- ============================================================
--  Weapon: Nikita homing missile  (8th)
--  Slow, self-homing, destructible (10 HP).
--  Target is auto-acquired in sent_nikita:Initialize() by scanning
--  nearby entities -- we only need to set position, angle, and owner.
-- ============================================================
local function FireNikita(ent, enemy)
    ent._missileCount = (ent._missileCount or 0) + 1
    local attIdx  = (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R
    local attData = ent:GetAttachment(attIdx)
    local src     = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local aimPos  = enemy:GetPos() + Vector(0, 0, 40)
    local dir     = (aimPos - src):GetNormalized()

    -- Small smoke puff at launch point
    local eff = EffectData()
    eff:SetOrigin(src)
    eff:SetNormal(dir)
    eff:SetScale(0.5)
    eff:SetMagnitude(1)
    util.Effect("SmokeEffect", eff)

    local nikita = ents.Create("sent_nikita")
    if not IsValid(nikita) then
        print("[GekkoNikita] ERROR: sent_nikita create failed -- falling back to missile")
        return FireMissile(ent, enemy)
    end
    nikita:SetPos(src)
    nikita:SetAngles(dir:Angle())  -- initial facing; auto-target acquired in Initialize()
    nikita:SetOwner(ent)           -- owner excluded from FindClosestTarget scan
    nikita:Spawn()
    nikita:Activate()

    print(string.format("[GekkoNikita] Launched | att=%d dist=%.0f",
        attIdx, ent:GetPos():Distance(enemy:GetPos())))
    return true
end

-- ============================================================
--  Range attack entry point
-- ============================================================
function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end
    local choice = RollWeapon()
    self._lastWeaponChoice = choice
    print("[GekkoWpn] Roll -> " .. choice)
    if     choice == "MG"           then return FireMGBurst(self, enemy)
    elseif choice == "MISSILE"      then return FireMissile(self, enemy)
    elseif choice == "SALVO"        then return FireDoubleSalvo(self, enemy)
    elseif choice == "TOPMISSILE"   then return FireTopMissile(self, enemy)
    elseif choice == "TRACKMISSILE" then return FireTrackMissile(self, enemy)
    elseif choice == "ORBITRPG"     then return FireOrbitRpg(self, enemy)
    elseif choice == "NIKITA"       then return FireNikita(self, enemy)
    else                                 return FireGrenadeLauncher(self, enemy)
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
