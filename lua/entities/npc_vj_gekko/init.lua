-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding Effect (Hemo-fluid-stream)
-- NEW BLEEDING TYPE: gekko_juicy_bleeding (NPC-owned only)
-- ============================================================
-- Weapon list:
-- 1. Machine-gun burst (FireBullets)
-- 2. Single accurate missile (obj_vj_rocket)
-- 3. Double inaccurate salvo (obj_vj_rocket x2)
-- 4. Grenade launcher barrage (bombin_gas_grenade / stun / flash)
-- 5. Top-attack terror missile (sent_npc_topmissile)
-- 6. Active-track missile (sent_npc_trackmissile)
-- 7. Orbit RPG (sent_orbital_rpg)
-- 8. Nikita cruise missile (npc_vj_gekko_nikita)
-- 9. Bushmaster 25mm cannon (sent_gekko_bushmaster x7-13)
-- 10. Elastic tether (elastic_system.lua - 0-900 u)
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("muzzleflash_system.lua")
AddCSLuaFile("bullet_impact_system.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")
include("death_pose_system.lua")
include("elastic_system.lua")

-- NOTE: extensions.lua is loaded + AddCSLuaFile'd by
-- lua/autorun/server/gekko_juicy_bleeding.lua which runs first.
-- DO NOT include it again here - that caused a double-load and
-- the relative path from entity scope resolved incorrectly.

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")
util.AddNetworkString("GekkoMuzzleFlash")
util.AddNetworkString("GekkoBulletImpact")
util.AddNetworkString("GekkoBushRecoil")

local ATT_MACHINEGUN = 3
local ATT_MISSILE_L = 9
local ATT_MISSILE_R = 10

local ANIM_WALK_SPEED = 184
local ANIM_RUN_SPEED = 20
local RUN_ENGAGE_DIST = 2300
local RUN_DISENGAGE_DIST = 1600

-- ============================================================
-- CLOSE-RANGE SPRINT BURST SYSTEM
-- ============================================================
local SPRINT_ENGAGE_DIST    = 1500
local SPRINT_DUR_MIN        = 2.0
local SPRINT_DUR_MAX        = 4.0
local SPRINT_COOLDOWN_MIN   = 4.0
local SPRINT_COOLDOWN_MAX   = 9.0
local SPRINT_MOVE_SPEED     = 420
local SPRINT_RUN_SPEED      = 420
local SPRINT_WALK_SPEED     = 420

local MG_ROUNDS_MIN = 11
local MG_ROUNDS_MAX = 36
local MG_INTERVAL = 0.15
local MG_DAMAGE = 25
local MG_SPREAD_MIN = 0.06
local MG_SPREAD_MAX = 0.6

local MG_SND_SHOTS = { "gekko/shot.wav", "gekko/shot2.wav" }
local MG_SND_CHAININSERT = "gekko/chaininsert.wav"
local MG_CHAIN_EVERY = 6
local MG_SND_LEVEL = 100
local MG_FLASH_EVERY = 2

local ROCKET_SND_FIRE = {
    "gekko/wp0040_se_gun_fire_01.wav",
    "gekko/wp0040_se_gun_fire_02.wav",
    "gekko/wp0040_se_gun_fire_03.wav",
}
local ROCKET_SND_LEVEL = 100

local TOPMISSILE_SND_FIRE = {
    "gekko/wp10e0_se_stinger_pass_1.wav",
    "gekko/wp0302_se_missile_fire_1.wav",
    "gekko/wp0302_se_missile_pass_2.wav",
}
local TOPMISSILE_SND_LEVEL = 100

local BM_ROUNDS_MIN = 7
local BM_ROUNDS_MAX = 9
local BM_INTERVAL = 0.38
local BM_SND_SHOOT = "gekko/brushmaster_25mm/20mm_shoot.wav"
local BM_SND_RELOAD = "gekko/brushmaster_25mm/20mm_reload.wav"
local BM_SND_LEVEL = 100
local BM_MUZZLE_SCALE = 9.5
local BM_MUZZLE_Z_OFFSET = 200
local BM_SPARK_SCALE = 0.32
local BM_SPARK_MAGNITUDE = 2.2
local BM_SPARK_RADIUS = 6
local BM_SMOKE_SCALE = 0.9
local BM_SMOKE_FORWARD = 12
local BM_SMOKE_UP = 2

local SHELL_MODEL = "models/props_debris/shellcasing_09.mdl"
local SHELL_LIFETIME = 5
local MG_SHELL_SCALE = 0.5
local BM_SHELL_SCALE = 1.0
local SHELL_RIGHT_OFFSET = 10
local SHELL_UP_OFFSET = 4
local SHELL_FWD_OFFSET = -2
local SHELL_VEL_RIGHT_MIN = 120
local SHELL_VEL_RIGHT_MAX = 220
local SHELL_VEL_UP_MIN = 40
local SHELL_VEL_UP_MAX = 90
local SHELL_VEL_FWD_MIN = -35
local SHELL_VEL_FWD_MAX = 35
local SHELL_ANGVEL_MIN = -220
local SHELL_ANGVEL_MAX = 220
local SHELL_MASS = 2

if SERVER then
    util.PrecacheModel(SHELL_MODEL)
end

local RELOAD_SNDS = {
    "gekko/reload/reloadbig_1.wav",
    "gekko/reload/reloadbig_2.wav",
    "gekko/reload/reloadbig_shell.wav",
    "gekko/reload/reloadbig_2_shell.wav",
    "gekko/reload/reloadmedium_1.wav",
    "gekko/reload/reloadmedium_2.wav",
    "gekko/reload/reloadmedium_shell.wav",
    "gekko/reload/reloadsmall_1.wav",
    "gekko/reload/reloadsmall_2.wav",
    "gekko/reload/reloadsmall_shell.wav",
}
local RELOAD_SND_LEVEL = 105

local WWEIGHT_MG = 8
local WWEIGHT_MISSILE_SINGLE = 20
local WWEIGHT_MISSILE_DOUBLE = 5
local WWEIGHT_GRENADE = 10
local WWEIGHT_TOPMISSILE = 10
local WWEIGHT_TRACKMISSILE = 2
local WWEIGHT_ORBITRPG = 10
local WWEIGHT_NIKITA = 8
local WWEIGHT_BUSHMASTER = 35
local WWEIGHT_ELASTIC = 12

local SALVO_SPREAD_XY = 220
local SALVO_SPREAD_Z = 80
local SALVO_DELAY = 0.8

local GL_COUNT_MIN = 4
local GL_COUNT_MAX = 8
local GL_INTERVAL = 0.35
local GL_SPREAD_Y = 250
local GL_LAUNCH_Z = 200
local GL_SOUND_FIDGET = "mac_bo2_m32/fidget.wav"
local GL_SOUND_FIRE = "mac_bo2_m32/fire.wav"
local GL_SOUND_INSERT = "mac_bo2_m32/insert.wav"
local GL_FIDGET_LEAD = 0.5
local GL_GRENADE_TYPES = { "bombin_gas_grenade", "ent_gas_stun", "ent_flashbang" }
local GL_TYPE_PARAMS = {
    ["bombin_gas_grenade"] = { speed = 2200, loft = 0.28 },
    ["ent_gas_stun"]       = { speed = 2750, loft = 0.35 },
    ["ent_flashbang"]      = { speed = 6500, loft = 0.42 },
}
local GL_TYPE_DEFAULT = { speed = 2650, loft = 0.35 }
local GL_TRAIL_MATERIAL = "trails/smoke"
local GL_TRAIL_LIFETIME = 0.6
local GL_TRAIL_STARTSIZE = 22
local GL_TRAIL_ENDSIZE = 1
local GL_TRAIL_COLOR = Color(235, 235, 235, 200)
local GL_MUZZLE_FLASH_SCALE = 0.4
local GL_SPARK_ATT_CYCLE = { ATT_MACHINEGUN, ATT_MISSILE_L, ATT_MISSILE_R }
local GL_SPARK_SCALE = 0.5
local GL_SPARK_MAGNITUDE = 4
local GL_SPARK_RADIUS = 10
local GL_VAPOR_EFFECT = "SmokeEffect"
local GL_SMOKE_EFFECT = "BlackSmoke"
local GL_VAPOR_SCALE = 0.6
local GL_SMOKE_SCALE = 0.4
local GL_SMOKE_EVERY = 2

local KORNET_SND_SHOTS = {
    "kornet/shot1.wav",
    "kornet/shot2.wav",
    "kornet/shot3.wav",
    "kornet/shot4.wav",
}
local KORNET_SND_LAUNCHES = { "kornet/launch1.wav", "kornet/launch2.wav" }
local KORNET_SND_LEVEL = 95

local TOPMISSILE_LAUNCH_Z = 300
local MISSILE_MIN_DIST = 1200
local NIKITA_MIN_DIST = 800
local MISSILE_SOUND_WARN = "buttons/button17.wav"
local MISSILE_SPAWN_FORWARD = 600
local NIKITA_SPAWN_FORWARD = 100
local NIKITA_SPAWN_Z = 340

local NIKITA_MUZZLE_SMOKE_COUNT = 5
local NIKITA_MUZZLE_SMOKE_SCALE = 1.8
local NIKITA_MUZZLE_SMOKE_STAGGER = 0.06

local JUMP_STATE_NAMES = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }
local HEAD_Z_FRACTION = 0.65
local BLOOD_DAMAGE_THRESHOLD = 20
local BLOOD_RANDOM_CHANCE = 80
local GROUNDED_BLEED_CHANCE = 0.85

-- ============================================================
-- BLOOD SIGNAL (ORIGINAL)
-- ============================================================
local function GekkoSignalBloodHit(ent, hitPos, hitNormal)
    if not IsValid(ent) then return end
    ent._bloodSplatPulse = (ent._bloodSplatPulse or 0) + 1
    local variant = math.random(1, 5)
    ent:SetNWInt("GekkoBloodSplat", ent._bloodSplatPulse * 8 + variant)
    local ed = EffectData()
    ed:SetEntity(ent)
    ed:SetOrigin(hitPos)
    ed:SetNormal(hitNormal)
    ed:SetFlags(0)
    ed:SetScale(1)
    ed:SetMagnitude(1)
    util.Effect("gekko_bloodstream", ed)
end

-- ============================================================
-- VANILLA BLEEDING (ORIGINAL)
-- ============================================================
local function GekkoVanillaBleed(ent, hitPos, hitDir)
    util.Decal("Blood", hitPos - hitDir * 4, hitPos + hitDir * 8, ent)
    local ed = EffectData()
    ed:SetOrigin(hitPos)
    ed:SetNormal(-hitDir)
    ed:SetEntity(ent)
    ed:SetScale(1)
    ed:SetMagnitude(1)
    util.Effect("BloodImpact", ed)
end

-- ============================================================
-- UTILITY FUNCTIONS
-- ============================================================
local function GetActiveEnemy(ent)
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

local function RollWeapon()
    local r = math.random(1, 120)
    local cum = 0
    cum = cum + WWEIGHT_MG;              if r <= cum then return "MG" end
    cum = cum + WWEIGHT_MISSILE_SINGLE;  if r <= cum then return "MISSILE" end
    cum = cum + WWEIGHT_MISSILE_DOUBLE;  if r <= cum then return "SALVO" end
    cum = cum + WWEIGHT_GRENADE;         if r <= cum then return "GRENADE" end
    cum = cum + WWEIGHT_TOPMISSILE;      if r <= cum then return "TOPMISSILE" end
    cum = cum + WWEIGHT_TRACKMISSILE;    if r <= cum then return "TRACKMISSILE" end
    cum = cum + WWEIGHT_ORBITRPG;        if r <= cum then return "ORBITRPG" end
    cum = cum + WWEIGHT_NIKITA;          if r <= cum then return "NIKITA" end
    cum = cum + WWEIGHT_ELASTIC;         if r <= cum then return "ELASTIC" end
    return "BRUSHMASTER"
end

local function SendMuzzleFlash(pos, normal, presetID)
    net.Start("GekkoMuzzleFlash")
    net.WriteVector(pos)
    net.WriteVector(normal)
    net.WriteUInt(presetID, 3)
    net.Broadcast()
end

local function SendBulletImpact(pos, normal, presetID)
    net.Start("GekkoBulletImpact")
    net.WriteVector(pos)
    net.WriteVector(normal)
    net.WriteUInt(presetID, 3)
    net.Broadcast()
end

local function SpawnRocket(ent, attIdx, aimPos, spread)
    local misAtt = ent:GetAttachment(attIdx)
    local src = misAtt and misAtt.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local target = aimPos + (spread or Vector(0, 0, 0))
    local dir = (target - src):GetNormalized()
    local rocket = ents.Create("obj_vj_rocket")
    if IsValid(rocket) then
        rocket:SetPos(src); rocket:SetAngles(dir:Angle())
        rocket:SetOwner(ent); rocket:Spawn(); rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(dir * 2800)
            phys:Wake()
        end
    end
    local eff = EffectData(); eff:SetOrigin(src); eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)
    SendMuzzleFlash(src, dir, 2)
    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(95, 110), 1)
end

local function SalvoSpread()
    return Vector(
        (math.random() - 0.5) * 2 * SALVO_SPREAD_XY,
        (math.random() - 0.5) * 2 * SALVO_SPREAD_XY,
        (math.random() - 0.5) * 2 * SALVO_SPREAD_Z
    )
end

local function GLSparkAtAttachment(ent, shotIndex)
    local attIdx = GL_SPARK_ATT_CYCLE[((shotIndex - 1) % #GL_SPARK_ATT_CYCLE) + 1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd = attData.Ang:Forward()
    local e = EffectData()
    e:SetOrigin(attData.Pos + fwd * 4); e:SetNormal(fwd); e:SetEntity(ent)
    e:SetMagnitude(GL_SPARK_MAGNITUDE * GL_SPARK_SCALE); e:SetScale(GL_SPARK_SCALE); e:SetRadius(GL_SPARK_RADIUS)
    util.Effect("ManhackSparks", e)
end

local function GLVaporAtAttachment(ent, shotIndex)
    local attIdx = GL_SPARK_ATT_CYCLE[((shotIndex - 1) % #GL_SPARK_ATT_CYCLE) + 1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd = attData.Ang:Forward()
    local origin = attData.Pos + fwd * 6
    local ev = EffectData()
    ev:SetOrigin(origin); ev:SetNormal(fwd); ev:SetScale(GL_VAPOR_SCALE); ev:SetMagnitude(1)
    util.Effect(GL_VAPOR_EFFECT, ev)
    if shotIndex % GL_SMOKE_EVERY == 0 then
        local es = EffectData()
        es:SetOrigin(origin + Vector(0, 0, 8)); es:SetNormal(fwd); es:SetScale(GL_SMOKE_SCALE); es:SetMagnitude(1)
        util.Effect(GL_SMOKE_EFFECT, es)
    end
end

local function AttachGrenadeTrail(gren)
    if not IsValid(gren) then return end
    util.SpriteTrail(gren, 0, GL_TRAIL_COLOR, false, GL_TRAIL_STARTSIZE, GL_TRAIL_ENDSIZE,
        GL_TRAIL_LIFETIME, 1 / GL_TRAIL_STARTSIZE, GL_TRAIL_MATERIAL)
end


local function BushmasterSparks(pos, dir, ent)
    local e = EffectData()
    e:SetOrigin(pos + dir * 4); e:SetNormal(dir); e:SetEntity(ent)
    e:SetMagnitude(BM_SPARK_MAGNITUDE); e:SetScale(BM_SPARK_SCALE); e:SetRadius(BM_SPARK_RADIUS)
    util.Effect("ManhackSparks", e)
end

local function BushmasterSmoke(pos, dir)
    local ed = EffectData()
    ed:SetOrigin(pos + dir * BM_SMOKE_FORWARD + Vector(0, 0, BM_SMOKE_UP))
    ed:SetNormal(dir); ed:SetScale(BM_SMOKE_SCALE); ed:SetMagnitude(1)
    util.Effect("SmokeEffect", ed)
end

local function SpawnCartridge(pos, ang, scale)
    if not pos or not ang then return end
    local shell = ents.Create("prop_physics")
    if not IsValid(shell) then return end
    shell:SetModel(SHELL_MODEL)
    shell:SetPos(
        pos
        + ang:Right()   * SHELL_RIGHT_OFFSET
        + ang:Up()      * SHELL_UP_OFFSET
        + ang:Forward() * SHELL_FWD_OFFSET
    )
    shell:SetAngles(ang)
    shell:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    shell:Spawn(); shell:Activate()
    shell:SetModelScale(scale, 0)
    shell:DrawShadow(false)
    local phys = shell:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(SHELL_MASS)
        phys:EnableGravity(true)
        phys:Wake()
        phys:SetVelocity(
            ang:Right()   * math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX)
            + ang:Up()    * math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX)
            + ang:Forward() * math.Rand(SHELL_VEL_FWD_MIN,  SHELL_VEL_FWD_MAX)
        )
        phys:SetAngleVelocity(Vector(
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX)
        ))
    end
    timer.Simple(SHELL_LIFETIME, function()
        if IsValid(shell) then shell:Remove() end
    end)
end

local function RerollNotMissile(exclude)
    local reroll
    repeat reroll = RollWeapon() until reroll ~= exclude
    print("[GekkoMissile] Re-roll -> " .. reroll)
    return reroll
end

local function SendSonarLock(enemy)
    if not IsValid(enemy) then return end
    if not enemy:IsPlayer() then return end
    net.Start("GekkoSonarLock"); net.Send(enemy)
end

-- ============================================================
-- SPRINT SYSTEM
-- ============================================================
local function GekkoSprint_Begin(ent)
    if not IsValid(ent) then return end
    if ent._gekkoDead then return end
    local js = ent:GetGekkoJumpState()
    if js == ent.JUMP_RISING or js == ent.JUMP_FALLING or js == ent.JUMP_LAND then
        ent._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
        return
    end
    if ent._gekkoCrouching then
        ent._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
        return
    end
    ent._gekkoSprinting    = true
    ent._gekkoSprintEndT   = CurTime() + math.Rand(SPRINT_DUR_MIN, SPRINT_DUR_MAX)
    ent._gekkoRunning      = true
    if not ent._preSprint_MoveSpeed then
        ent._preSprint_MoveSpeed = ent.MoveSpeed
        ent._preSprint_RunSpeed  = ent.RunSpeed
        ent._preSprint_WalkSpeed = ent.WalkSpeed
    end
    ent.MoveSpeed = SPRINT_MOVE_SPEED
    ent.RunSpeed  = SPRINT_RUN_SPEED
    ent.WalkSpeed = SPRINT_WALK_SPEED
    print(string.format("[GekkoSprint] BEGIN | dur=%.1fs", ent._gekkoSprintEndT - CurTime()))
end

local function GekkoSprint_End(ent)
    if not IsValid(ent) then return end
    ent._gekkoSprinting = false
    if ent._preSprint_MoveSpeed then
        ent.MoveSpeed = ent._preSprint_MoveSpeed
        ent.RunSpeed  = ent._preSprint_RunSpeed
        ent.WalkSpeed = ent._preSprint_WalkSpeed
        ent._preSprint_MoveSpeed = nil
        ent._preSprint_RunSpeed  = nil
        ent._preSprint_WalkSpeed = nil
    end
    ent._gekkoRunning     = false
    ent._gekkoSprintNextT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
    print("[GekkoSprint] END")
end

local function GekkoSprint_Think(ent)
    if ent._gekkoDead then return end
    local now = CurTime()
    if ent._gekkoSprinting then
        if now >= ent._gekkoSprintEndT then GekkoSprint_End(ent) end
        return
    end
    if now < (ent._gekkoSprintNextT or 0) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    if ent:GetPos():Distance(enemy:GetPos()) > SPRINT_ENGAGE_DIST then return end
    GekkoSprint_Begin(ent)
end

function ENT:AnimApply()
    local js = self:GetGekkoJumpState()
    if js == self.JUMP_RISING or js == self.JUMP_FALLING or js == self.JUMP_LAND then return true end
    return false
end

function ENT:SetAnimationTranslations()
    if not self.AnimationTranslations then self.AnimationTranslations = {} end
    local walkSeq = self:LookupSequence("walk")
    local runSeq  = self:LookupSequence("run")
    local idleSeq = self:LookupSequence("idle")
    walkSeq = (walkSeq and walkSeq ~= -1) and walkSeq or 0
    runSeq  = (runSeq  and runSeq  ~= -1) and runSeq  or 0
    idleSeq = (idleSeq and idleSeq ~= -1) and idleSeq or 0
    self.AnimationTranslations[ACT_IDLE]                    = idleSeq
    self.AnimationTranslations[ACT_WALK]                    = walkSeq
    self.AnimationTranslations[ACT_RUN]                     = runSeq
    self.AnimationTranslations[ACT_WALK_AIM]                = walkSeq
    self.AnimationTranslations[ACT_RUN_AIM]                 = runSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK1]           = idleSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK2]           = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK1]   = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK2]   = idleSeq
    self.AnimationTranslations[ACT_IDLE_ANGRY]              = idleSeq
    self.AnimationTranslations[ACT_COMBAT_IDLE]             = idleSeq
    self.GekkoSeq_Walk = walkSeq
    self.GekkoSeq_Run  = runSeq
    self.GekkoSeq_Idle = idleSeq
end

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
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING or jumpState == self.JUMP_FALLING or jumpState == self.JUMP_LAND
        or (self._gekkoJustJumped and now < self._gekkoJustJumped) then
        self:SetPoseParameter("move_x", 0); self:SetPoseParameter("move_y", 0)
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
    if not self._gekkoSprinting then
        if dist > RUN_ENGAGE_DIST    then self._gekkoRunning = true  end
        if dist < RUN_DISENGAGE_DIST then self._gekkoRunning = false end
    end
    local targetSeq, arate
    if vel > 5 then
        if self._gekkoRunning then
            targetSeq = self.GekkoSeq_Run;  arate = vel / ANIM_RUN_SPEED
        else
            targetSeq = self.GekkoSeq_Walk; arate = vel / ANIM_WALK_SPEED
        end
    elseif self._gekkoRunning then
        targetSeq = self.GekkoSeq_Run; arate = 0.5
    else
        targetSeq = self.GekkoSeq_Idle; arate = 1.0
    end
    arate = math.Clamp(arate, 0.5, 3.0)
    if targetSeq and targetSeq ~= -1 then self:ResetSequence(targetSeq) end
    if     targetSeq == self.GekkoSeq_Run  then self.Gekko_LastSeqName = "run"
    elseif targetSeq == self.GekkoSeq_Walk then self.Gekko_LastSeqName = "walk"
    else                                        self.Gekko_LastSeqName = "idle"
    end
    self:SetPlaybackRate(arate)
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/Metal_Gear_Gekko/metal_gear_gekko_rigged.mdl")
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()
    self.VJ_AddDeaths = true
    self.VJ_NPC_Class = {"CLASS_COMBINE"}
    self.StartHealth = 1200
    self.HasMeleeAttack = false
    self.HasGrenadeAttack = false
    self.HasRangeAttack = true
    self.RangeDistance = 12000
    self.TimeUntilFirstAttack = 1.5
    self.AttackAnimationTime = 0.4
    self.NextAttackTime = 2.0
    self.NoChaseAfterAttack = false
    self.MoveSpeed = 180
    self.WalkSpeed = 180
    self.RunSpeed  = 20
    self.TurnSpeed = 16
    self.AnimationPlaybackRate = 1.0
    self.HasDeathSound = true
    self.DeathSound = {"gekko/death1.wav", "gekko/death2.wav", "gekko/death3.wav"}
    self.HasIdleSound = true
    self.IdleSound = {"gekko/idle1.wav", "gekko/idle2.wav", "gekko/idle3.wav", "gekko/idle4.wav"}
    self.IdleSoundLevel = 75
    self.HasAlertSound = true
    self.AlertSound = {"gekko/alert1.wav", "gekko/alert2.wav"}
    self.AlertSoundLevel = 80
    self.HasPainSound = true
    self.PainSound = {"gekko/pain1.wav", "gekko/pain2.wav", "gekko/pain3.wav"}
    self.HasFootstepSound = false
    self.NoCorpse = true
    self.VJ_BloodColor = "Red"
    self.BloodParticle = "blood_impact_red_01"
    self.CanFlinch = 1
    self.FlinchChance = 12
    self._gekkoDead = false
    self._gekkoSprinting = false
    self._gekkoSprintNextT = 0
    self._gekkoRunning = false
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:CapabilitiesAdd(CAP_TURN_HEAD)
    self:CapabilitiesAdd(CAP_SQUAD)
    self:SetMaxYawSpeed(30)
    self:SetNWInt("GekkoBloodSplat", 0)
    self:SetNWFloat("GekkoSpeed", 0)
    self:GekkoElastic_Init()
    self:SetAnimationTranslations()
end

-- ============================================================
-- FIRE: MACHINE GUN
-- ============================================================
local function FireMachineGun(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local rounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, math.random(95, 105), 1)
    for i = 1, rounds do
        if not IsValid(ent) then break end
        timer.Simple((i - 1) * MG_INTERVAL, function()
            if not IsValid(ent) then return end
            local enemyNow = GetActiveEnemy(ent)
            if not IsValid(enemyNow) then return end
            local attData = ent:GetAttachment(ATT_MACHINEGUN)
            local src     = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, 120))
            local aimPos  = enemyNow:GetPos() + Vector(0, 0, 36)
            local spread  = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
            ent:FireBullets({
                Attacker  = ent,
                Src       = src,
                Dir       = (aimPos - src):GetNormalized(),
                Spread    = Vector(spread, spread, 0),
                Damage    = MG_DAMAGE,
                Num       = 1,
                AmmoType  = "AR2",
                Callback  = function(att, tr, dmg)
                    if tr.HitWorld then
                        SendBulletImpact(tr.HitPos, tr.HitNormal, 1)
                    end
                end,
            })
            if i % MG_FLASH_EVERY == 0 then
                local att2 = ent:GetAttachment(ATT_MACHINEGUN)
                if att2 then SendMuzzleFlash(att2.Pos, att2.Ang:Forward(), 1) end
            end
            if i % MG_CHAIN_EVERY == 0 then
                ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, math.random(95, 105), 1)
            end
            ent:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(95, 115), 1)
            SpawnCartridge(src, ent:GetAngles(), MG_SHELL_SCALE)
        end)
    end
end

-- ============================================================
-- FIRE: GRENADE LAUNCHER
-- ============================================================
local function FireGrenades(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local count    = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    local grenType = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
    local params   = GL_TYPE_PARAMS[grenType] or GL_TYPE_DEFAULT
    local basePos  = enemy:GetPos()
    ent:EmitSound(GL_SOUND_FIDGET, 90, math.random(95, 105), 1)
    for i = 1, count do
        timer.Simple((i - 1) * GL_INTERVAL + GL_FIDGET_LEAD, function()
            if not IsValid(ent) then return end
            local shotIndex = i
            local attIdx    = GL_SPARK_ATT_CYCLE[((shotIndex - 1) % #GL_SPARK_ATT_CYCLE) + 1]
            local attData   = ent:GetAttachment(attIdx)
            local src       = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, GL_LAUNCH_Z))
            local aim       = basePos + Vector(
                (math.random() - 0.5) * 2 * GL_SPREAD_Y,
                (math.random() - 0.5) * 2 * GL_SPREAD_Y,
                0
            )
            local dir = (aim - src):GetNormalized()
            dir.z = dir.z + params.loft
            dir:Normalize()
            local gren = ents.Create(grenType)
            if not IsValid(gren) then return end
            gren:SetPos(src); gren:SetAngles(dir:Angle())
            gren:SetOwner(ent); gren:Spawn(); gren:Activate()
            local phys = gren:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(dir * params.speed); phys:Wake()
            end
            AttachGrenadeTrail(gren)
            GLSparkAtAttachment(ent, shotIndex)
            GLVaporAtAttachment(ent, shotIndex)
            local mf = EffectData()
            mf:SetOrigin(src); mf:SetNormal(dir); mf:SetScale(GL_MUZZLE_FLASH_SCALE)
            util.Effect("MuzzleFlash", mf)
            ent:EmitSound(GL_SOUND_FIRE, 95, math.random(95, 110), 1)
            ent:EmitSound(GL_SOUND_INSERT, 85, math.random(95, 105), 1)
        end)
    end
end

-- ============================================================
-- FIRE: BUSHMASTER 25mm
-- ============================================================
local function FireBushmaster(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local rounds = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)
    ent:EmitSound(BM_SND_RELOAD, BM_SND_LEVEL, math.random(95, 105), 1)
    for i = 1, rounds do
        timer.Simple((i - 1) * BM_INTERVAL, function()
            if not IsValid(ent) then return end
            local enemyNow = GetActiveEnemy(ent)
            if not IsValid(enemyNow) then return end
            local src  = ent:GetPos() + Vector(0, 0, BM_MUZZLE_Z_OFFSET)
            local dir  = (enemyNow:GetPos() + Vector(0, 0, 36) - src):GetNormalized()
            local ejectAng = ent:GetAngles()
            local shell = ents.Create("sent_gekko_bushmaster")
            if IsValid(shell) then
                shell:SetPos(src); shell:SetAngles(dir:Angle())
                shell:SetOwner(ent); shell:Spawn(); shell:Activate()
            end
            SpawnCartridge(src, ejectAng, BM_SHELL_SCALE)
            BushmasterSparks(src, dir, ent)
            BushmasterSmoke(src, dir)
            local mf = EffectData()
            mf:SetOrigin(src + Vector(0, 0, BM_MUZZLE_SCALE))
            mf:SetNormal(dir); mf:SetScale(BM_MUZZLE_SCALE)
            util.Effect("MuzzleFlash", mf)
            SendMuzzleFlash(src, dir, 3)
            ent:EmitSound(BM_SND_SHOOT, BM_SND_LEVEL, math.random(95, 110), 1)
        end)
    end
end

-- ============================================================
-- FIRE: TOPMISSILE
-- ============================================================
local function FireTopMissile(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local src = ent:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local dir = Vector(0, 0, 1)
    local missile = ents.Create("sent_npc_topmissile")
    if IsValid(missile) then
        missile:SetPos(src); missile:SetAngles(dir:Angle())
        missile:SetOwner(ent)
        missile:SetNWEntity("GekkoTopTarget", enemy)
        missile:Spawn(); missile:Activate()
    end
    SendSonarLock(enemy)
    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
end

-- ============================================================
-- FIRE: TRACK MISSILE
-- ============================================================
local function FireTrackMissile(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        ent._gekkoWeapon = RerollNotMissile("TRACKMISSILE")
        return
    end
    local attL = ent:GetAttachment(ATT_MISSILE_L)
    local src  = attL and attL.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local dir  = (enemy:GetPos() + Vector(0, 0, 36) - src):GetNormalized()
    local missile = ents.Create("sent_npc_trackmissile")
    if IsValid(missile) then
        missile:SetPos(src); missile:SetAngles(dir:Angle())
        missile:SetOwner(ent)
        missile:SetNWEntity("GekkoTrackTarget", enemy)
        missile:Spawn(); missile:Activate()
    end
    SendSonarLock(enemy)
    local snd = KORNET_SND_SHOTS[math.random(#KORNET_SND_SHOTS)]
    ent:EmitSound(snd, KORNET_SND_LEVEL, math.random(95, 110), 1)
    timer.Simple(0.15, function()
        if not IsValid(ent) then return end
        ent:EmitSound(KORNET_SND_LAUNCHES[math.random(#KORNET_SND_LAUNCHES)], KORNET_SND_LEVEL, math.random(95, 110), 1)
    end)
end

-- ============================================================
-- FIRE: ORBIT RPG
-- ============================================================
local function FireOrbitRPG(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        ent._gekkoWeapon = RerollNotMissile("ORBITRPG")
        return
    end
    local attL = ent:GetAttachment(ATT_MISSILE_L)
    local src  = attL and attL.Pos or (ent:GetPos() + Vector(0, 0, 200))
    local dir  = (enemy:GetPos() + Vector(0, 0, 36) - src):GetNormalized()
    local rpg = ents.Create("sent_orbital_rpg")
    if IsValid(rpg) then
        rpg:SetPos(src); rpg:SetAngles(dir:Angle())
        rpg:SetOwner(ent)
        rpg:SetNWEntity("GekkoOrbitTarget", enemy)
        rpg:Spawn(); rpg:Activate()
    end
    SendSonarLock(enemy)
    local snd = KORNET_SND_SHOTS[math.random(#KORNET_SND_SHOTS)]
    ent:EmitSound(snd, KORNET_SND_LEVEL, math.random(95, 110), 1)
end

-- ============================================================
-- FIRE: NIKITA CRUISE MISSILE
-- ============================================================
local function FireNikita(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < NIKITA_MIN_DIST then
        ent._gekkoWeapon = RerollNotMissile("NIKITA")
        return
    end
    local src = ent:GetPos() + ent:GetForward() * NIKITA_SPAWN_FORWARD + Vector(0, 0, NIKITA_SPAWN_Z)
    local dir = (enemy:GetPos() + Vector(0, 0, 36) - src):GetNormalized()
    local nikita = ents.Create("npc_vj_gekko_nikita")
    if IsValid(nikita) then
        nikita:SetPos(src); nikita:SetAngles(dir:Angle())
        nikita:SetOwner(ent)
        nikita:SetNWEntity("GekkoNikitaTarget", enemy)
        nikita:Spawn(); nikita:Activate()
    end
    SendSonarLock(enemy)
    for i = 0, NIKITA_MUZZLE_SMOKE_COUNT - 1 do
        local delay  = i * NIKITA_MUZZLE_SMOKE_STAGGER
        local offset = i * 18
        timer.Simple(delay, function()
            if not IsValid(ent) then return end
            local smokePos = src + dir * offset
            local ed = EffectData()
            ed:SetOrigin(smokePos); ed:SetNormal(dir)
            ed:SetScale(NIKITA_MUZZLE_SMOKE_SCALE); ed:SetMagnitude(1)
            util.Effect("SmokeEffect", ed)
        end)
    end
end

-- ============================================================
-- VJ RANGE ATTACK
-- ============================================================
function ENT:CustomRangeAttack(atkType)
    if atkType ~= 1 then return end
    local chosen = self._gekkoWeapon or RollWeapon()
    self._gekkoWeapon = nil
    print("[GekkoWeapon] Firing: " .. chosen)
    if chosen == "MG"           then FireMachineGun(self)
    elseif chosen == "MISSILE"  then SpawnRocket(self, ATT_MISSILE_L, GetActiveEnemy(self) and GetActiveEnemy(self):GetPos() or self:GetPos())
    elseif chosen == "SALVO" then
        local enemy = GetActiveEnemy(self)
        if IsValid(enemy) then
            local aim = enemy:GetPos()
            SpawnRocket(self, ATT_MISSILE_L, aim + SalvoSpread())
            timer.Simple(SALVO_DELAY, function()
                if not IsValid(self) then return end
                SpawnRocket(self, ATT_MISSILE_R, aim + SalvoSpread())
            end)
        end
    elseif chosen == "GRENADE"      then FireGrenades(self)
    elseif chosen == "TOPMISSILE"   then FireTopMissile(self)
    elseif chosen == "TRACKMISSILE" then FireTrackMissile(self)
    elseif chosen == "ORBITRPG"     then FireOrbitRPG(self)
    elseif chosen == "NIKITA"       then FireNikita(self)
    elseif chosen == "ELASTIC"      then self:GekkoElastic_Fire()
    else                                 FireBushmaster(self)
    end
end

-- ============================================================
-- THINK
-- ============================================================
function ENT:Think()
    if not IsValid(self) then return end
    self:GekkoUpdateAnimation()
    GekkoSprint_Think(self)
    self:GekkoElastic_Think()
    self:NextThink(CurTime() + 0.05)
    return true
end

-- ============================================================
-- ON TAKE DAMAGE
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    local dmg = dmginfo:GetDamage()
    if dmg < 1 then return end
    local hitPos    = dmginfo:GetDamagePosition()
    local hitDir    = dmginfo:GetDamageForce():GetNormalized()
    local hitNormal = -hitDir
    GekkoVanillaBleed(self, hitPos, hitDir)
    if dmg >= BLOOD_DAMAGE_THRESHOLD or math.random(100) <= BLOOD_RANDOM_CHANCE then
        GekkoSignalBloodHit(self, hitPos, hitNormal)
    end
    self:VJ_TakeDamageNPC(dmginfo)
end

-- ============================================================
-- ON KILLED
-- ============================================================
function ENT:OnDeath(dmginfo)
    self._gekkoDead = true
    if self._gekkoSprinting then GekkoSprint_End(self) end
    self:GekkoElastic_OnRemove()
    self:GekkoGib_OnDeath(dmginfo)
end

function ENT:OnRemove()
    if self._gekkoSprinting then GekkoSprint_End(self) end
    self:GekkoElastic_OnRemove()
end
