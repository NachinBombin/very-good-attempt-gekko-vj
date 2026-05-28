-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding Effect (Hemo-fluid-stream)
-- NEW BLEEDING TYPE: gekko_juicy_bleeding (NPC-owned only)
-- INTEGRATED WITH: pedestal_dodge_system.lua (random strafe + reactive dodge)
-- ============================================================
-- Weapon list:
-- 1. Machine-gun burst (FireBullets)
-- 2. Single accurate missile (obj_gekko_rocket)
-- 3. Double inaccurate salvo (obj_gekko_rocket x2)
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
include("aps_system.lua")
AddCSLuaFile("cl_aps.lua")
include("pedestal_dodge_system.lua")   -- random strafe + reactive dodge

-- NOTE: extensions.lua is loaded + AddCSLuaFile'd by
-- lua/autorun/server/gekko_juicy_bleeding.lua which runs first.
-- DO NOT include it again here - that caused a double-load and
-- the relative path from entity scope resolved incorrectly.

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")
util.AddNetworkString("GekkoMuzzleFlash")
util.AddNetworkString("GekkoBulletImpact")
util.AddNetworkString("GekkoBushRecoil")
util.AddNetworkString("GekkoAPSIntercept")
util.AddNetworkString("GekkoAPSLaser")

local ATT_MACHINEGUN = 3
local ATT_MISSILE_L = 9
local ATT_MISSILE_R = 10

local ANIM_WALK_SPEED = 184
local ANIM_RUN_SPEED = 20
local RUN_ENGAGE_DIST = 2200
local RUN_DISENGAGE_DIST = 1600

-- ============================================================
-- CLOSE-RANGE SPRINT BURST SYSTEM
-- ============================================================
local SPRINT_ENGAGE_DIST    = 1500
local SPRINT_DUR_MIN        = 2.0
local SPRINT_DUR_MAX        = 6.0
local SPRINT_COOLDOWN_MIN   = 4.0
local SPRINT_COOLDOWN_MAX   = 9.0
local SPRINT_MOVE_SPEED     = 420
local SPRINT_RUN_SPEED      = 420
local SPRINT_WALK_SPEED     = 420

local MG_ROUNDS_MIN = 11
local MG_ROUNDS_MAX = 42
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

local BM_ROUNDS_MIN = 3
local BM_ROUNDS_MAX = 16
local BM_INTERVAL  = 0.36   -- normal interval between shots
local BM_INTERVAL2 = 0.72   -- stutter interval (task 3): used for 10% of shots
local BM_STUTTER_CHANCE = 10 -- % of shots that get the doubled delay

-- Task 1: bullet drop compensation
local BM_DROP_COMP_Z   = 30     -- constant upward aim offset (units)
local BM_DROP_JITTER_Z = 17     -- +/- vertical jitter on top of the compensation

-- Task 2: imperfect velocity lead
-- Projectile speed from sent_gekko_bushmaster (SPEED = 3950 u/s)
local BM_PROJ_SPEED  = 3950
local BM_LEAD_FACTOR = 0.55     -- 55% of perfect lead -> plausible but not perfect

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

-- ============================================================
-- BUSHMASTER SHELL EJECTION SOUNDS
-- Played 0.19 s after each shot via timer.Simple.
-- Seven variants are picked at random each ejection.
-- ============================================================
local BM_SHELL_DROP_SOUNDS = {
    "gekko/shell/cannon_shell_drop_01.wav",
    "gekko/shell/cannon_shell_drop_02.wav",
    "gekko/shell/cannon_shell_drop_03.wav",
    "gekko/shell/cannon_shell_drop_04.wav",
    "gekko/shell/cannon_shell_drop_05.wav",
    "gekko/shell/cannon_shell_drop_06.wav",
    "gekko/shell/cannon_shell_drop_07.wav",
}
local BM_SHELL_DROP_DELAY  = 0.19
local BM_SHELL_DROP_LEVEL  = 75   -- quieter than the cannon blast
local BM_SHELL_DROP_PITCH_MIN = 95
local BM_SHELL_DROP_PITCH_MAX = 105

if SERVER then
    for _, snd in ipairs(BM_SHELL_DROP_SOUNDS) do
        util.PrecacheSound(snd)
    end
end
-- ============================================================

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

local WWEIGHT_MG = 9
local WWEIGHT_MISSILE_SINGLE = 20
local WWEIGHT_MISSILE_DOUBLE = 5
local WWEIGHT_GRENADE = 10
local WWEIGHT_TOPMISSILE = 10
local WWEIGHT_TRACKMISSILE = 1
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

local NIKITA_MUZZLE_SMOKE_COUNT = 3
local NIKITA_MUZZLE_SMOKE_SCALE = 0.9
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
    local rocket = ents.Create("obj_gekko_rocket")
    if IsValid(rocket) then
        rocket:SetPos(src); rocket:SetAngles(dir:Angle())
        rocket:SetOwner(ent); rocket:Spawn(); rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1200) end
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

-- ============================================================
-- TranslateActivity
-- Called by VJ Base (and the engine) every time it wants to
-- resolve an ACT_* constant to a sequence index. By intercepting
-- here we guarantee the crouch sequence wins BEFORE VJ ever
-- gets to call ResetSequence with a walk/idle sequence.
-- This is the deepest interception point available without
-- patching VJ Base itself.
-- ============================================================
function ENT:TranslateActivity(act)
    if self._gekkoCrouching then
        local speed = self:GetNWFloat("GekkoSpeed", 0)
        if speed > 5 then
            local seq = self.GekkoSeq_CrouchWalk
            if seq and seq ~= -1 then return seq end
        else
            local seq = (self.GekkoSeq_CrouchIdle ~= -1)
                        and self.GekkoSeq_CrouchIdle
                        or  self.GekkoSeq_CrouchWalk
            if seq and seq ~= -1 then return seq end
        end
    end
    -- Fall through to AnimationTranslations table (VJ custom move anim path)
    if self.AnimationTranslations and self.AnimationTranslations[act] then
        return self.AnimationTranslations[act]
    end
    return self.BaseClass.TranslateActivity(self, act)
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

    -- ── FIX #2: Crouch runs even during a dodge hop.
    -- The dodge slide uses MOVETYPE_FLYGRAVITY + small Z kick which briefly
    -- flips jumpState to JUMP_RISING and caused the old guard to skip
    -- GeckoCrouch_Update for the entire dodge duration. We now bypass that
    -- gate when the NPC is explicitly crouching (_gekkoCrouching == true).
    local jumpState = self:GetGekkoJumpState()
    local isJumpBlocking = (jumpState == self.JUMP_RISING or
                            jumpState == self.JUMP_FALLING or
                            jumpState == self.JUMP_LAND or
                            (self._gekkoJustJumped and now < self._gekkoJustJumped))

    if not isJumpBlocking or self._gekkoCrouching then
        -- FIX #3: lazy sequence re-cache.
        -- If the model finished loading AFTER the deferred timer in Init fired,
        -- LookupSequence("c_walk") returned -1 and was never retried. Re-attempt
        -- here so the very first dodge-crouch actually finds the right sequence.
        if self.GekkoSeq_CrouchWalk == nil or self.GekkoSeq_CrouchWalk == -1 then
            self:GeckoCrouch_CacheSeqs()
            if self.GekkoSeq_CrouchWalk == nil or self.GekkoSeq_CrouchWalk == -1 then
                -- model has no c_walk at all: fall back to idle to at least hold a pose
                self.GekkoSeq_CrouchWalk = self.GekkoSeq_Idle or 0
            end
        end
        if self:GeckoCrouch_Update() then return end
    end

    if now < (self._gekkoSuppressActivity or 0) then return end

    if isJumpBlocking then
        self:SetPoseParameter("move_x", 0); self:SetPoseParameter("move_y", 0)
        return
    end

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
    else                                        self.Gekko_LastSeqName = "idle" end
    self.Gekko_LastSeqIdx = targetSeq
    self:SetPlaybackRate(arate)
    self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)
end

local function SafeInitVJTables(ent)
    if not ent.VJ_AddOnDamage    then ent.VJ_AddOnDamage    = {} end
    if not ent.VJ_DamageInfos    then ent.VJ_DamageInfos    = {} end
    if not ent.VJ_DeathSounds    then ent.VJ_DeathSounds    = {} end
    if not ent.VJ_PainSounds     then ent.VJ_PainSounds     = {} end
    if not ent.VJ_IdleSounds     then ent.VJ_IdleSounds     = {} end
    if not ent.VJ_FootstepSounds then ent.VJ_FootstepSounds = {} end
    if not ent.AnimationTranslations then ent.AnimationTranslations = {} end
end

function ENT:Init()
    self.BloodColor = BLOOD_COLOR_RED
    self:SetupBloodColor(self.BloodColor)
    self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 200))
    self:SetSkin(1)
    self.GekkoSpineBone  = self:LookupBone("b_spine4")    or -1
    self.GekkoLGunBone   = self:LookupBone("b_l_gunrack") or -1
    self.GekkoRGunBone   = self:LookupBone("b_r_gunrack") or -1
    self.GekkoPelvisBone = self:LookupBone("b_pelvis1")   or -1
    self.Gekko_NextDebugT         = 0
    self.Gekko_LastSeqName        = ""
    self.Gekko_LastSeqIdx         = -1
    self._missileCount            = 0
    self._mgBurstActive           = false
    self._mgBurstEndT             = 0
    self._gekkoRunning            = false
    self._gekkoLastEnemyDist      = nil
    self._gekkoLastPos            = self:GetPos()
    self._gekkoLastTime           = CurTime() - 0.1
    self._gekkoSuppressActivity   = 0
    self._crushHitTimes           = {}
    self._bloodSplatPulse         = 0
    self._hitReactPulse           = 0
    self._gibCooldownT            = 0
    self._lastWeaponChoice        = ""
    self._glSparkCounter          = 0
    self._gekkoDead               = false
    self._gekkoInvulnUntil        = 0  -- invulnerability window during dodge (set by pedestal_dodge_system)
    self._gekkoSprinting          = false
    self._gekkoSprintEndT         = 0
    self._gekkoSprintNextT        = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
    self._preSprint_MoveSpeed     = nil
    self._preSprint_RunSpeed      = nil
    self._preSprint_WalkSpeed     = nil
    self:SetNWBool("GekkoMGFiring",      false)
    self:SetNWInt("GekkoJumpDust",       0)
    self:SetNWInt("GekkoLandDust",       0)
    self:SetNWInt("GekkoFK360LandDust",  0)
    self:SetNWInt("GekkoBloodSplat",     0)
    -- Hit-react pulse signal initialised to 0 so client baseline matches.
    self:SetNWInt("GekkoHitReactPulse",  0)
    self:SetNW2Vector("GekkoHitPos",     Vector(0, 0, 0))
    self:SetNW2Vector("GekkoHitDir",     Vector(0, 1, 0))
    self:SetNW2Bool("GekkoHitLarge",     false)
    SafeInitVJTables(self)
    self:GekkoJump_Init()
    self:GekkoTargetJump_Init()
    self:GeckoCrouch_Init()
    self:GekkoLegs_Init()
    self:GekkoDeath_Init()
    self:GekkoElastic_Init()
	self:GekkoAPS_Init()
    -- ── Pedestal dodge / random strafe initialisation ────────────────
    self:PedestalDodge_Init()
    -- ─────────────────────────────────────────────────────────────────
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
        selfRef.GekkoSpineBone  = selfRef:LookupBone("b_spine4")    or -1
        selfRef.GekkoLGunBone   = selfRef:LookupBone("b_l_gunrack") or -1
        selfRef.GekkoRGunBone   = selfRef:LookupBone("b_r_gunrack") or -1
        selfRef.GekkoPelvisBone = selfRef:LookupBone("b_pelvis1")   or -1
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
end

function ENT:Activate()
    local base = self.BaseClass
    if base and base.Activate and base.Activate ~= ENT.Activate then base.Activate(self) end
    SafeInitVJTables(self)
end

-- ============================================================
-- OnTakeDamage: INTEGRATED WITH JUICY BLEEDING + HIT REACT
--               + PEDESTAL DODGE (reactive sideways slide)
-- ============================================================
local BLEED_DMG_TYPES = {
    DMG_BULLET,
    DMG_BUCKSHOT,
    DMG_SLASH,
    DMG_CLUB,
    DMG_BURN,
    DMG_PLASMA,
    DMG_ENERGYBEAM,
    DMG_SNIPER,
    DMG_NEVERGIB,
}

local function ShouldJuicyBleed(dmginfo)
    if dmginfo:IsBulletDamage() then return true end
    for _, dtype in ipairs(BLEED_DMG_TYPES) do
        if dmginfo:IsDamageType(dtype) then return true end
    end
    return false
end

local IMPULSE_SCALE   = 18
local IMPULSE_MAX     = 220
local IMPULSE_MIN_DMG = 8

local function GekkoApplyHitImpulse(ent, hitDir, damage)
    if damage < IMPULSE_MIN_DMG then return end
    local mag = math.Clamp(damage * IMPULSE_SCALE, 0, IMPULSE_MAX)
    local cur = ent:GetAbsVelocity()
    ent:SetAbsVelocity(cur + hitDir * mag)
end

-- ============================================================
-- RECONSTRUCT HIT POSITION
-- ============================================================
local function GekkoResolveHitPos(self, dmginfo)
    local hitPos = dmginfo:GetDamagePosition()
    if hitPos ~= vector_origin then
        return hitPos, "dmgpos"
    end

    local _, maxs = self:GetCollisionBounds()
    local bodyCenter = self:GetPos() + Vector(0, 0, maxs.z * 0.5)

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) then
        local src = attacker.EyePos and attacker:EyePos() or attacker:GetPos()
        local tr = util.TraceLine({
            start  = src,
            endpos = bodyCenter,
            filter = { attacker, self },
            mask   = MASK_SHOT,
        })
        if tr.Hit then
            return tr.HitPos, "trace_attacker"
        end
        return bodyCenter, "bodycenter_attacker"
    end

    local inflictor = dmginfo:GetInflictor()
    if IsValid(inflictor) then
        local src = inflictor:GetPos()
        local tr = util.TraceLine({
            start  = src,
            endpos = bodyCenter,
            filter = { inflictor, self },
            mask   = MASK_SHOT,
        })
        if tr.Hit then
            return tr.HitPos, "trace_inflictor"
        end
        return bodyCenter, "bodycenter_inflictor"
    end

    return bodyCenter, "bodycenter_fallback"
end


-- ============================================================
-- TraceAttack override
-- Suppresses engine-side blood decals and impact effects
-- (ImpactEffect, BloodImpact, surface decals) that the engine
-- fires through the C++ TraceAttack path BEFORE OnTakeDamage
-- is ever called. Without this override those effects always
-- fire even when OnTakeDamage zeroes and discards the damage.
-- During the invulnerability window we zero the damage in the
-- dmginfo and return without calling BaseClass so the engine
-- skips every visual associated with the hit.
-- ============================================================
function ENT:TraceAttack(dmginfo, dir, trace)
    if self._gekkoDead then
        dmginfo:SetDamage(0)
        return
    end
    -- Invulnerability window set by PedestalDodge_OnHit
    if CurTime() < (self._gekkoInvulnUntil or 0) then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        -- Returning without BaseClass call suppresses engine blood/impact effects.
        return
    end
    self.BaseClass.TraceAttack(self, dmginfo, dir, trace)
end

function ENT:OnTakeDamage(dmginfo)
    if self._gekkoDead then
        dmginfo:SetDamage(0)
        return
    end

    -- Early invulnerability window check (set by PedestalDodge_OnHit).
    -- TraceAttack already blocks engine effects; this guard blocks anything
    -- that reaches OnTakeDamage through a non-TraceAttack path (blast, etc.)
    if CurTime() < (self._gekkoInvulnUntil or 0) then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        return
    end

    local savedForce = dmginfo:GetDamageForce()
    dmginfo:SetDamageForce(Vector(0, 0, 0))

    local hitPos, hitPosSource = GekkoResolveHitPos(self, dmginfo)

    local _, maxs = self:GetCollisionBounds()
    local headZ = self:GetPos().z + maxs.z * HEAD_Z_FRACTION
    if hitPos.z > headZ then dmginfo:ScaleDamage(1 / 3) end

    local rawDmg   = dmginfo:GetDamage()
    local attacker = dmginfo:GetAttacker()

    local hitDir = IsValid(attacker)
        and (hitPos - attacker:GetPos()):GetNormalized()
        or self:GetForward()

    -- ── Reactive pedestal dodge runs FIRST, before ANY visual effect.
    -- PedestalDodge_OnHit sets _gekkoInvulnUntil on the entity so that
    -- TraceAttack (engine blood/impact effects) and any follow-up blast
    -- damage are also blocked for the full dodge+tail window.
    -- On a successful dodge we zero damage and return immediately.
    if self:PedestalDodge_OnHit(dmginfo) then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        -- Suppress VJ Base flinch from this tick onward (it runs after us).
        self.Flinching = false
        return
    end
    -- ───────────────────────────────────────────────────────────────────────

    -- Only reaches here when the dodge did NOT trigger.
    GekkoApplyHitImpulse(self, hitDir, rawDmg)
    GekkoVanillaBleed(self, hitPos, hitDir)
    if dmginfo:IsBulletDamage() then
        GekkoSignalBloodHit(self, hitPos, hitDir)
    end

    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)

    if hitPosSource ~= "dmgpos" then
        print(string.format("[GekkoHitReact] hitPos reconstructed via '%s'", hitPosSource))
    end

    dmginfo:SetDamageForce(savedForce)
    self.BaseClass.OnTakeDamage(self, dmginfo)

    if ShouldJuicyBleed(dmginfo) and GekkoTriggerJuicyBleed then
        GekkoTriggerJuicyBleed(self, dmginfo, hitDir, self:GetLastDamageHitGroup())
    end
end

function ENT:OnThink()
    if self._gekkoLegsDisabled then self:GekkoLegs_Think() end
    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end
    self:GekkoJump_Think()
    self:GekkoTargetJump_Think()
    self:GekkoElastic_Think()
	self:GekkoAPS_Think()
    GekkoSprint_Think(self)
    -- ── Pedestal dodge: random strafe tick + slide advancement ──────
    self:PedestalDodge_ThinkStrafe()
    -- ────────────────────────────────────────────────────────────────
    self:GekkoUpdateAnimation()
    self:GeckoCrush_Think()
    if CurTime() > self.Gekko_NextDebugT then
        local enemy = GetActiveEnemy(self)
        local dist, src
        if IsValid(enemy) then
            dist = math.floor(self:GetPos():Distance(enemy:GetPos()))
            src  = IsValid(self.VJ_TheEnemy) and "vj" or "engine"
        elseif self._gekkoLastEnemyDist then
            dist = math.floor(self._gekkoLastEnemyDist); src = "cached"
        else
            dist = -1; src = "none"
        end
        print(string.format(
            "[GekkoDBG] vel=%.1f seq=%s run=%s sprint=%s dist=%d(%s) spd=%d jump=%s crouch=%s mgActive=%s lastWpn=%s dead=%s",
            self:GetNWFloat("GekkoSpeed", 0), tostring(self.Gekko_LastSeqName),
            tostring(self._gekkoRunning), tostring(self._gekkoSprinting),
            dist, src, self.MoveSpeed or 0,
            JUMP_STATE_NAMES[self:GetGekkoJumpState()] or "?",
            tostring(self._gekkoCrouching), tostring(self._mgBurstActive),
            tostring(self._lastWeaponChoice), tostring(self._gekkoDead)
        ))
        self.Gekko_NextDebugT = CurTime() + 1
    end
end

local function FireMGBurst(ent, enemy)
    if ent._mgBurstActive then return false end
    local aimPos   = enemy:GetPos() + Vector(0, 0, 40)
    local mgRounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local mgSpread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
    ent._mgBurstActive = true
    ent._mgBurstEndT   = CurTime() + (mgRounds * MG_INTERVAL) + 1.0
    ent:SetNWBool("GekkoMGFiring", true)
    for i = 0, mgRounds - 1 do
        local round = i
        timer.Simple(round * MG_INTERVAL, function()
            if not IsValid(ent) then return end
            local curEnemy = GetActiveEnemy(ent)
            local curAim   = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0, 0, 40)) or aimPos
            local src, ejectAng
            local mgAtt = ent:GetAttachment(ATT_MACHINEGUN)
            if mgAtt then
                src      = mgAtt.Pos
                ejectAng = mgAtt.Ang
            else
                local boneIdx = ent.GekkoLGunBone
                if boneIdx and boneIdx >= 0 then
                    local m = ent:GetBoneMatrix(boneIdx)
                    if m then
                        src      = m:GetTranslation() + m:GetForward() * 28
                        ejectAng = m:GetAngles()
                    end
                end
                src      = src      or (ent:GetPos() + Vector(0, 0, 200))
                ejectAng = ejectAng or ent:GetAngles()
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
                Spread     = Vector(mgSpread, mgSpread, mgSpread),
                Callback   = function(_, tr, _)
                    if tr.Hit and tr.HitNormal then
                        SendBulletImpact(tr.HitPos, tr.HitNormal, 1)
                    end
                end,
            })
            SpawnCartridge(src, ejectAng, MG_SHELL_SCALE)
            local eff = EffectData(); eff:SetOrigin(src); eff:SetNormal(dir)
            util.Effect("MuzzleFlash", eff)
            if (round % MG_FLASH_EVERY) == 0 then SendMuzzleFlash(src, dir, 1) end
            ent:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(95, 115), 1)
            if (round + 1) % MG_CHAIN_EVERY == 0 then
                ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, 100, 1)
            end
            if round == mgRounds - 1 then
                ent._mgBurstActive = false
                ent:SetNWBool("GekkoMGFiring", false)
            end
        end)
    end
    return true
end

local function FireMissile(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    ent._missileCount = (ent._missileCount or 0) + 1
    SpawnRocket(ent, (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R, aimPos, nil)
    return true
end

local function FireDoubleSalvo(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    ent._missileCount = (ent._missileCount or 0) + 1
    SpawnRocket(ent, (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R, aimPos, SalvoSpread())
    timer.Simple(SALVO_DELAY, function()
        if not IsValid(ent) then return end
        local curEnemy = GetActiveEnemy(ent)
        local curAim   = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0, 0, 40)) or aimPos
        ent._missileCount = (ent._missileCount or 0) + 1
        SpawnRocket(ent, (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R, curAim, SalvoSpread())
    end)
    return true
end

local function FireGrenadeLauncher(ent, enemy)
    local count       = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    local grenadeType = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
    local typeParams  = GL_TYPE_PARAMS[grenadeType] or GL_TYPE_DEFAULT
    ent._glSparkCounter = 0
    ent:EmitSound(GL_SOUND_FIDGET, 80, 100, 1)
    timer.Simple(GL_FIDGET_LEAD + (count - 1) * GL_INTERVAL + 0.1, function()
        if not IsValid(ent) then return end
        ent:EmitSound(GL_SOUND_INSERT, 80, 100, 1)
    end)
    for i = 0, count - 1 do
        local shotNumber = i + 1
        timer.Simple(GL_FIDGET_LEAD + i * GL_INTERVAL, function()
            if not IsValid(ent) then return end
            local forward = ent:GetForward()
            local right   = ent:GetRight()
            local origin  = ent:GetPos() + Vector(0, 0, GL_LAUNCH_Z)
            ent:EmitSound(GL_SOUND_FIRE, 80, math.random(95, 105), 1)
            GLSparkAtAttachment(ent, shotNumber)
            GLVaporAtAttachment(ent, shotNumber)
            local scatter   = forward * math.Rand(300, 700) + right * ((math.random() - 0.5) * 2 * GL_SPREAD_Y)
            local spawnPos  = origin + scatter * 0.05
            local launchDir = scatter:GetNormalized()
            launchDir.z = launchDir.z + typeParams.loft
            launchDir:Normalize()
            local mf = EffectData()
            mf:SetOrigin(spawnPos); mf:SetNormal(launchDir); mf:SetScale(GL_MUZZLE_FLASH_SCALE)
            util.Effect("MuzzleFlash", mf)
            local gren = ents.Create(grenadeType)
            if IsValid(gren) then
                gren:SetPos(spawnPos); gren:SetAngles(launchDir:Angle())
                gren:SetOwner(ent); gren:Spawn(); gren:Activate()
                local phys = gren:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(launchDir * typeParams.speed)
                    phys:SetAngleVelocity(Vector(math.Rand(-200, 200), math.Rand(-200, 200), math.Rand(-200, 200)))
                end
                AttachGrenadeTrail(gren)
            end
        end)
    end
    return true
end

local function FireOrbitRpg(ent, enemy)
    ent._missileCount = (ent._missileCount or 0) + 1
    local attIdx  = (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R
    local attData = ent:GetAttachment(attIdx)
    local src     = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local aimPos  = enemy:GetPos() + Vector(0, 0, 40)
    local dir     = (aimPos - src):GetNormalized()
    local eff = EffectData(); eff:SetOrigin(src); eff:SetNormal(dir); eff:SetScale(0.6); eff:SetMagnitude(1)
    util.Effect("SmokeEffect", eff)
    SendMuzzleFlash(src, dir, 2)
    ent:EmitSound(KORNET_SND_SHOTS[math.random(#KORNET_SND_SHOTS)],   KORNET_SND_LEVEL, math.random(95, 105), 1)
    ent:EmitSound(KORNET_SND_LAUNCHES[math.random(#KORNET_SND_LAUNCHES)], KORNET_SND_LEVEL, 100, 1)
    local rpg = ents.Create("sent_orbital_rpg")
    if not IsValid(rpg) then
        print("[GekkoORBIT] ERROR: sent_orbital_rpg create failed -- falling back")
        return FireMissile(ent, enemy)
    end
    rpg:SetPos(src); rpg:SetAngles(dir:Angle()); rpg:SetOwner(ent)
    rpg:Spawn(); rpg:Activate()
    print(string.format("[GekkoORBIT] Launched | att=%d dist=%.0f", attIdx, ent:GetPos():Distance(enemy:GetPos())))
    return true
end

local function FireTopMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        print(string.format("[GekkoTM] Too close (%.0f) -- re-rolling", dist))
        local alt = RerollNotMissile("TOPMISSILE")
        if alt == "MG" then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE" then return FireMissile(ent, enemy)
        elseif alt == "SALVO"   then return FireDoubleSalvo(ent, enemy)
        elseif alt == "ORBITRPG" then return FireOrbitRpg(ent, enemy)
        else return FireGrenadeLauncher(ent, enemy) end
    end
    sound.Play(MISSILE_SOUND_WARN, ent:GetPos(), 511, 60)
    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
    local toTarget2D = (enemy:GetPos() - ent:GetPos()); toTarget2D.z = 0; toTarget2D:Normalize()
    local launchPos  = ent:GetPos() + toTarget2D * MISSILE_SPAWN_FORWARD + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local faceAng    = (enemy:GetPos() - launchPos):GetNormalized():Angle(); faceAng.p = 0
    local missile = ents.Create("sent_npc_topmissile")
    if not IsValid(missile) then print("[GekkoTM] ERROR: create failed") return FireGrenadeLauncher(ent, enemy) end
    missile.Owner  = ent
    missile.Target = enemy:GetPos() + Vector(0, 0, 40)
    missile:SetPos(launchPos); missile:SetAngles(faceAng); missile:Spawn(); missile:Activate()
    SendMuzzleFlash(launchPos, (enemy:GetPos() - launchPos):GetNormalized(), 2)
    print(string.format("[GekkoTM] Launched | dist=%.0f", dist))
    return true
end

local function FireTrackMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        print(string.format("[GekkoTRK] Too close (%.0f) -- re-rolling", dist))
        local alt = RerollNotMissile("TRACKMISSILE")
        if alt == "MG"        then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE"    then return FireMissile(ent, enemy)
        elseif alt == "SALVO"      then return FireDoubleSalvo(ent, enemy)
        elseif alt == "TOPMISSILE" then return FireTopMissile(ent, enemy)
        elseif alt == "ORBITRPG"   then return FireOrbitRpg(ent, enemy)
        else return FireGrenadeLauncher(ent, enemy) end
    end
    SendSonarLock(enemy)
    sound.Play(MISSILE_SOUND_WARN, ent:GetPos(), 511, 60)
    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
    local toTarget2D = (enemy:GetPos() - ent:GetPos()); toTarget2D.z = 0; toTarget2D:Normalize()
    local launchPos  = ent:GetPos() + toTarget2D * MISSILE_SPAWN_FORWARD + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local faceAng    = (enemy:GetPos() - launchPos):GetNormalized():Angle(); faceAng.p = 0
    local missile = ents.Create("sent_npc_trackmissile")
    if not IsValid(missile) then print("[GekkoTRK] ERROR: create failed") return FireGrenadeLauncher(ent, enemy) end
    missile.Owner    = ent
    missile.Target   = enemy:GetPos() + Vector(0, 0, 40)
    missile.TrackEnt = enemy
    missile:SetPos(launchPos); missile:SetAngles(faceAng); missile:Spawn(); missile:Activate()
    SendMuzzleFlash(launchPos, (enemy:GetPos() - launchPos):GetNormalized(), 2)
    print(string.format("[GekkoTRK] Launched | dist=%.0f", dist))
    return true
end

local function NikitaMuzzleSmoke(ent)
    ent._missileCount = (ent._missileCount or 0) + 1
    local attIdx  = (ent._missileCount % 2 == 1) and ATT_MISSILE_L or ATT_MISSILE_R
    local attData = ent:GetAttachment(attIdx)
    local nozzle  = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local nozzDir = attData and attData.Ang:Forward() or ent:GetForward()
    for i = 0, NIKITA_MUZZLE_SMOKE_COUNT - 1 do
        local delay  = i * NIKITA_MUZZLE_SMOKE_STAGGER
        local pos    = nozzle
        local normal = nozzDir
        timer.Simple(delay, function()
            if not IsValid(ent) then return end
            local ed = EffectData()
            ed:SetOrigin(pos + normal * (i * 4))
            ed:SetNormal(normal)
            ed:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
            ed:SetMagnitude(1)
            util.Effect("SmokeEffect", ed)
        end)
    end
    SendMuzzleFlash(nozzle, nozzDir, 4)
end

local function FireNikita(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < NIKITA_MIN_DIST then
        print(string.format("[GekkoNikita] Too close (%.0f) -- re-rolling", dist))
        return FireMGBurst(ent, enemy)
    end
    NikitaMuzzleSmoke(ent)
    local toTarget2D = (enemy:GetPos() - ent:GetPos())
    toTarget2D.z = 0
    if toTarget2D:Length() > 0 then toTarget2D:Normalize() end
    local spawnPos  = ent:GetPos() + toTarget2D * NIKITA_SPAWN_FORWARD + Vector(0, 0, NIKITA_SPAWN_Z)
    local aimPos    = enemy:GetPos() + Vector(0, 0, 40)
    local launchDir = (aimPos - spawnPos):GetNormalized()
    local nikita    = ents.Create("npc_vj_gekko_nikita")
    if not IsValid(nikita) then
        print("[GekkoNikita] ERROR: create failed")
        return FireMissile(ent, enemy)
    end
    nikita:SetPos(spawnPos)
    nikita:SetAngles(launchDir:Angle())
    nikita:SetOwner(ent)
    nikita.NikitaOwner     = ent
    nikita.NikitaTargetEnt = enemy
    nikita:Spawn(); nikita:Activate()
    if IsValid(enemy) then
        if nikita.VJ_DoSetEnemy then
            nikita:VJ_DoSetEnemy(enemy, true, true)
        else
            nikita:SetEnemy(enemy)
        end
    end
    print(string.format("[GekkoNikita] Launched | dist=%.0f", dist))
    return true
end

-- ============================================================
-- FIRE BUSHMASTER
-- Task 1: +70 u drop compensation + +-17 u vertical jitter
-- Task 2: 55% velocity lead (imperfect aim correction)
-- Task 3: 10% of shots use BM_INTERVAL2 (double delay stutter)
-- Shell ejection sound: random pick from BM_SHELL_DROP_SOUNDS,
--   played BM_SHELL_DROP_DELAY (0.19 s) after each shot fires.
-- ============================================================
local function FireBushmaster(ent, enemy)
    -- Snapshot the fallback aim position at burst start
    local aimPosBase = enemy:GetPos() + Vector(0, 0, 40)

    -- Task 2: snapshot enemy velocity at burst start for lead calculation.
    -- We re-sample per shot so the lead tracks the target if it changes direction.
    -- Using GetAbsVelocity() - works on players and NPCs alike.
    local rounds = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)

    -- Task 3: pre-build the per-shot fire times with stutter accumulation.
    -- Each shot decides independently whether to add BM_INTERVAL2 or BM_INTERVAL
    -- to the running clock. This means a stutter on shot N shifts ALL subsequent shots.
    local shotTimes = {}
    local accumTime = 0
    for i = 0, rounds - 1 do
        shotTimes[i] = accumTime
        -- Roll stutter for the NEXT gap (no gap after the last shot, doesn't matter)
        local gap = (math.random(100) <= BM_STUTTER_CHANCE) and BM_INTERVAL2 or BM_INTERVAL
        accumTime = accumTime + gap
    end

    for i = 0, rounds - 1 do
        local shot = i
        timer.Simple(shotTimes[shot], function()
            if not IsValid(ent) then return end

            -- Resolve muzzle source
            local src, ejectAng
            ejectAng = ent:GetAngles()
            local pelBone = ent.GekkoPelvisBone
            if pelBone and pelBone >= 0 then
                local m = ent:GetBoneMatrix(pelBone)
                if m then
                    src      = m:GetTranslation() + Vector(0, 0, BM_MUZZLE_Z_OFFSET)
                    ejectAng = m:GetAngles()
                end
            end
            src = src or (ent:GetPos() + Vector(0, 0, BM_MUZZLE_Z_OFFSET))

            -- Resolve current enemy
            local curEnemy = GetActiveEnemy(ent)
            local basePos  = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0, 0, 40)) or aimPosBase

            -- Task 2: imperfect velocity lead.
            -- tof = straight-line distance / projectile speed (rough estimate, ignores orbit path)
            -- lead = velocity * tof * BM_LEAD_FACTOR  (55% -> plausible but not perfect)
            local leadOffset = Vector(0, 0, 0)
            if IsValid(curEnemy) then
                local enemyVel = curEnemy:GetAbsVelocity()
                -- Only lead if the target is actually moving (avoids jitter on standing targets)
                if enemyVel:LengthSqr() > 100 then
                    local dist = src:Distance(basePos)
                    local tof  = dist / BM_PROJ_SPEED
                    leadOffset = enemyVel * (tof * BM_LEAD_FACTOR)
                end
            end

            -- Task 1: drop compensation + vertical jitter
            local dropCompZ = BM_DROP_COMP_Z + math.Rand(-BM_DROP_JITTER_Z, BM_DROP_JITTER_Z)

            -- Final aim point: base + velocity lead + drop compensation (Z only)
            local curAim = basePos + leadOffset + Vector(0, 0, dropCompZ)

            local dir = (curAim - src):GetNormalized()

            local shell = ents.Create("sent_gekko_bushmaster")
            if IsValid(shell) then
                shell:SetPos(src); shell:SetAngles(dir:Angle())
                shell:SetOwner(ent); shell:Spawn(); shell:Activate()
            end
            SpawnCartridge(src, ejectAng, BM_SHELL_SCALE)
            BushmasterSparks(src, dir, ent)
            BushmasterSmoke(src, dir)
            local eff = EffectData()
            eff:SetOrigin(src); eff:SetNormal(dir)
            eff:SetScale(BM_MUZZLE_SCALE); eff:SetMagnitude(BM_MUZZLE_SCALE)
            util.Effect("MuzzleFlash", eff)
            SendMuzzleFlash(src, dir, 3)
            ent:EmitSound(BM_SND_SHOOT, BM_SND_LEVEL, math.random(95, 110), 1)

            -- Shell ejection sound: played 0.19 s after the shot,
            -- random variant from BM_SHELL_DROP_SOUNDS (01-07).
            local shellSnd = BM_SHELL_DROP_SOUNDS[math.random(#BM_SHELL_DROP_SOUNDS)]
            timer.Simple(BM_SHELL_DROP_DELAY, function()
                if not IsValid(ent) then return end
                ent:EmitSound(shellSnd, BM_SHELL_DROP_LEVEL,
                    math.random(BM_SHELL_DROP_PITCH_MIN, BM_SHELL_DROP_PITCH_MAX), 0.8)
            end)

            -- ---- Bushmaster fire-recoil signal (server -> client) ----
            net.Start("GekkoBushRecoil")
                net.WriteEntity(ent)
                net.WriteVector(src)
                net.WriteVector(-dir)   -- recoil direction = opposite of shot
            net.Broadcast()
            -- -----------------------------------------------------------
            if shot == rounds - 1 then
                timer.Simple(0.12, function()
                    if not IsValid(ent) then return end
                    ent:EmitSound(BM_SND_RELOAD, BM_SND_LEVEL, 100, 1)
                end)
            end
        end)
    end
    print(string.format("[GekkoBM] Salvo | rounds=%d interval=%.2fs/%.2fs stutter=%d%%",
        rounds, BM_INTERVAL, BM_INTERVAL2, BM_STUTTER_CHANCE))
    return true
end

local function FireElastic(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist > 900 then
        print(string.format("[GekkoElastic] Re-rolling (dist=%.0f > 900)", dist))
        local alt
        repeat alt = RollWeapon() until alt ~= "ELASTIC"
        if     alt == "MG"           then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE"      then return FireMissile(ent, enemy)
        elseif alt == "SALVO"        then return FireDoubleSalvo(ent, enemy)
        elseif alt == "TOPMISSILE"   then return FireTopMissile(ent, enemy)
        elseif alt == "TRACKMISSILE" then return FireTrackMissile(ent, enemy)
        elseif alt == "ORBITRPG"     then return FireOrbitRpg(ent, enemy)
        elseif alt == "NIKITA"       then return FireNikita(ent, enemy)
        elseif alt == "BRUSHMASTER"  then return FireBushmaster(ent, enemy)
        else return FireGrenadeLauncher(ent, enemy) end
    end
    if CurTime() < (ent._elasticNextShotT or 0) then
        print("[GekkoElastic] On cooldown, re-rolling")
        local alt
        repeat alt = RollWeapon() until alt ~= "ELASTIC"
        if     alt == "MG"           then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE"      then return FireMissile(ent, enemy)
        elseif alt == "SALVO"        then return FireDoubleSalvo(ent, enemy)
        elseif alt == "TOPMISSILE"   then return FireTopMissile(ent, enemy)
        elseif alt == "TRACKMISSILE" then return FireTrackMissile(ent, enemy)
        elseif alt == "ORBITRPG"     then return FireOrbitRpg(ent, enemy)
        elseif alt == "NIKITA"       then return FireNikita(ent, enemy)
        elseif alt == "BRUSHMASTER"  then return FireBushmaster(ent, enemy)
        else return FireGrenadeLauncher(ent, enemy) end
    end
    return ent:GekkoElastic_Fire(enemy)
end

function ENT:OnRangeAttackExecute(status, enemy, projectile)
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end
    local choice = RollWeapon()
    self._lastWeaponChoice = choice
    self:EmitSound(RELOAD_SNDS[math.random(#RELOAD_SNDS)], RELOAD_SND_LEVEL, 100, 1)
    print("[GekkoWpn] Roll -> " .. choice)
    if     choice == "MG"           then return FireMGBurst(self, enemy)
    elseif choice == "MISSILE"      then return FireMissile(self, enemy)
    elseif choice == "SALVO"        then return FireDoubleSalvo(self, enemy)
    elseif choice == "TOPMISSILE"   then return FireTopMissile(self, enemy)
    elseif choice == "TRACKMISSILE" then return FireTrackMissile(self, enemy)
    elseif choice == "ORBITRPG"     then return FireOrbitRpg(self, enemy)
    elseif choice == "NIKITA"       then return FireNikita(self, enemy)
    elseif choice == "ELASTIC"      then return FireElastic(self, enemy)
    elseif choice == "BRUSHMASTER"  then return FireBushmaster(self, enemy)
    else return FireGrenadeLauncher(self, enemy)
    end
end

function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end
    if self._gekkoDead then return end
    self._gekkoDead = true
    if self._gekkoSprinting then GekkoSprint_End(self) end
    local attacker  = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos       = self:GetPos()
    self:SetGekkoJumpState(self.JUMP_NONE)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetNWBool("GekkoMGFiring", false)
    self:SetNotSolid(true)
    self:GekkoElastic_OnRemove()
    self:GekkoDeath_SpawnRagdoll()
    timer.Simple(0.8, function()
        if not IsValid(self) then return end
        ParticleEffect("astw2_nightfire_explosion_generic", pos, angle_zero)
        self:EmitSound(VJ.PICK({
            "weapons/mgs3/explosion_01.wav",
            "weapons/mgs3/explosion_02.wav",
        }), 511, 100, 2)
        util.BlastDamage(self, attacker, pos, 512, 256)
    end)
end

function ENT:OnRemove()
    if self._gekkoSprinting then GekkoSprint_End(self) end
    self:GekkoElastic_OnRemove()
end