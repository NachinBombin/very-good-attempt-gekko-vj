-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding Effect (Hemo-fluid-stream)
-- NEW BLEEDING TYPE: gekko_juicy_bleeding (NPC-owned only)
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

local BM_SND_SHOOT  = "gekko/brushmaster_25mm/20mm_shoot.wav"
local BM_SND_RELOAD = "gekko/brushmaster_25mm/20mm_reload.wav"
local BM_SND_LEVEL  = 100

-- Shell ejection sounds: played 0.19 s after each Bushmaster round fires
local BM_SHELL_DROP_SOUNDS = {
    "gekko/shell/cannon_shell_drop_01.wav",
    "gekko/shell/cannon_shell_drop_02.wav",
    "gekko/shell/cannon_shell_drop_03.wav",
    "gekko/shell/cannon_shell_drop_04.wav",
    "gekko/shell/cannon_shell_drop_05.wav",
    "gekko/shell/cannon_shell_drop_06.wav",
    "gekko/shell/cannon_shell_drop_07.wav",
}
for _, snd in ipairs(BM_SHELL_DROP_SOUNDS) do
    util.PrecacheSound(snd)
end
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
    cum = cum + WWEIGHT_BUSHMASTER;      if r <= cum then return "BRUSHMASTER" end
    return "ELASTIC"
end

-- ============================================================
-- MUZZLE FLASH RELAY
-- ============================================================
local function SendMuzzleFlash(pos, dir, preset)
    net.Start("GekkoMuzzleFlash")
        net.WriteVector(pos)
        net.WriteVector(dir)
        net.WriteUInt(preset, 3)
    net.Broadcast()
end

-- ============================================================
-- SHELL CASINGS
-- ============================================================
local function SpawnCartridge(src, ang, scale)
    if not SERVER then return end
    local shell = ents.Create("prop_physics")
    if not IsValid(shell) then return end
    shell:SetModel(SHELL_MODEL)
    shell:SetModelScale(scale, 0)
    shell:SetPos(src)
    shell:SetAngles(ang)
    shell:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    shell:Spawn(); shell:Activate()
    shell:DrawShadow(false)

    local phys = shell:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(SHELL_MASS)
        local fwd   = ang:Forward()
        local right = ang:Right()
        local up    = ang:Up()
        local vx = right  * math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX)
        local vy = up     * math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX)
        local vz = fwd    * math.Rand(SHELL_VEL_FWD_MIN,   SHELL_VEL_FWD_MAX)
        phys:SetVelocity(vx + vy + vz)
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

-- ============================================================
-- BUSHMASTER VISUAL HELPERS
-- ============================================================
local function BushmasterSparks(pos, dir, ent)
    local ed = EffectData()
    ed:SetOrigin(pos); ed:SetNormal(dir); ed:SetEntity(ent)
    ed:SetScale(BM_SPARK_SCALE); ed:SetMagnitude(BM_SPARK_MAGNITUDE)
    ed:SetRadius(BM_SPARK_RADIUS)
    util.Effect("ElectricSpark", ed)
end

local function BushmasterSmoke(pos, dir)
    local ed = EffectData()
    ed:SetOrigin(pos + dir * BM_SMOKE_FORWARD + Vector(0, 0, BM_SMOKE_UP))
    ed:SetNormal(dir); ed:SetScale(BM_SMOKE_SCALE)
    util.Effect("SmokeEffect", ed)
end

-- ============================================================
-- GRENADE LAUNCHER HELPERS
-- ============================================================
local function GLSparks(pos, dir, ent)
    local ed = EffectData()
    ed:SetOrigin(pos); ed:SetNormal(dir); ed:SetEntity(ent)
    ed:SetScale(GL_SPARK_SCALE); ed:SetMagnitude(GL_SPARK_MAGNITUDE)
    ed:SetRadius(GL_SPARK_RADIUS)
    util.Effect("ElectricSpark", ed)
end

local function GLSmoke(pos, dir)
    local ed = EffectData()
    ed:SetOrigin(pos + dir * 8 + Vector(0, 0, 2))
    ed:SetNormal(dir); ed:SetScale(GL_VAPOR_SCALE)
    util.Effect(GL_VAPOR_EFFECT, ed)
end

-- ============================================================
-- MACHINE-GUN FIRE
-- ============================================================
local function FireMG(ent, enemy)
    if not IsValid(ent) then return end
    local rounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local chain_timer = 0

    for i = 0, rounds - 1 do
        timer.Simple(i * MG_INTERVAL, function()
            if not IsValid(ent) then return end

            local curEnemy = GetActiveEnemy(ent)
            if not IsValid(curEnemy) then return end

            local pelBone = ent.GekkoPelvisBone
            local src
            if pelBone and pelBone >= 0 then
                local m = ent:GetBoneMatrix(pelBone)
                if m then src = m:GetTranslation() end
            end
            src = src or ent:GetPos()

            local dir = (curEnemy:GetPos() + Vector(0, 0, 40) - src):GetNormalized()
            local spread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
            dir = dir + Vector(
                math.Rand(-spread, spread),
                math.Rand(-spread, spread),
                math.Rand(-spread, spread)
            )
            dir:Normalize()

            local dmginfo = DamageInfo()
            dmginfo:SetDamage(MG_DAMAGE)
            dmginfo:SetAttacker(ent)
            dmginfo:SetInflictor(ent)
            dmginfo:SetDamageType(DMG_BULLET)
            dmginfo:SetDamagePosition(src)

            local tr = util.TraceLine({
                start  = src,
                endpos = src + dir * 4000,
                filter = ent,
                mask   = MASK_SHOT,
            })

            if tr.Hit and IsValid(tr.Entity) then
                dmginfo:SetDamageForce(dir * MG_DAMAGE * 80)
                tr.Entity:TakeDamageInfo(dmginfo)
            end

            local snd = MG_SND_SHOTS[math.random(#MG_SND_SHOTS)]
            ent:EmitSound(snd, MG_SND_LEVEL, math.random(95, 110), 1)
            SpawnCartridge(src, ent:GetAngles(), MG_SHELL_SCALE)

            if i % MG_CHAIN_EVERY == 0 then
                ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, 100, 1)
            end

            if i % MG_FLASH_EVERY == 0 then
                local eff = EffectData()
                eff:SetOrigin(src); eff:SetNormal(dir)
                eff:SetScale(1.5); eff:SetMagnitude(1.5)
                util.Effect("MuzzleFlash", eff)
                SendMuzzleFlash(src, dir, 1)
            end
        end)
    end
    return true
end

-- ============================================================
-- MISSILE FIRE
-- ============================================================
local function FireMissile(ent, enemy, count)
    if not IsValid(ent) then return end
    count = count or 1
    for i = 1, count do
        timer.Simple((i - 1) * SALVO_DELAY, function()
            if not IsValid(ent) then return end
            local curEnemy = GetActiveEnemy(ent)
            if not IsValid(curEnemy) then return end

            local src = ent:GetPos() + Vector(0, 0, 80)
            local targetPos = curEnemy:GetPos() + Vector(
                math.Rand(-SALVO_SPREAD_XY, SALVO_SPREAD_XY),
                math.Rand(-SALVO_SPREAD_XY, SALVO_SPREAD_XY),
                math.Rand(-SALVO_SPREAD_Z, SALVO_SPREAD_Z)
            )
            local dir = (targetPos - src):GetNormalized()

            local rocket = ents.Create("obj_gekko_rocket")
            if IsValid(rocket) then
                rocket:SetPos(src)
                rocket:SetAngles(dir:Angle())
                rocket:SetOwner(ent)
                rocket:Spawn()
                rocket:Activate()
            end

            local snd = ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)]
            ent:EmitSound(snd, ROCKET_SND_LEVEL, math.random(95, 110), 1)
        end)
    end
    return true
end

-- ============================================================
-- TOP-ATTACK MISSILE
-- ============================================================
local function FireTopMissile(ent, enemy)
    if not IsValid(ent) then return end
    local src = ent:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local dir = Vector(0, 0, 1)

    local missile = ents.Create("sent_npc_topmissile")
    if IsValid(missile) then
        missile:SetPos(src)
        missile:SetAngles(dir:Angle())
        missile:SetOwner(ent)
        missile:Spawn()
        missile:Activate()
        missile:SetNWEntity("GekkoTopMissileTarget", enemy)
    end

    local snd = TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)]
    ent:EmitSound(snd, TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
    return true
end

-- ============================================================
-- TRACK MISSILE
-- ============================================================
local function FireTrackMissile(ent, enemy)
    if not IsValid(ent) then return end
    local src = ent:GetPos() + Vector(0, 0, 80)
    local dir = (enemy:GetPos() - src):GetNormalized()

    local missile = ents.Create("sent_npc_trackmissile")
    if IsValid(missile) then
        missile:SetPos(src)
        missile:SetAngles(dir:Angle())
        missile:SetOwner(ent)
        missile:Spawn()
        missile:Activate()
        missile:SetNWEntity("GekkoTrackMissileTarget", enemy)
    end

    local snd = ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)]
    ent:EmitSound(snd, ROCKET_SND_LEVEL, math.random(95, 110), 1)
    return true
end

-- ============================================================
-- ORBIT RPG
-- ============================================================
local function FireOrbitRPG(ent, enemy)
    if not IsValid(ent) then return end
    local src = ent:GetPos() + Vector(0, 0, 80)
    local dir = (enemy:GetPos() - src):GetNormalized()

    local missile = ents.Create("sent_orbital_rpg")
    if IsValid(missile) then
        missile:SetPos(src)
        missile:SetAngles(dir:Angle())
        missile:SetOwner(ent)
        missile:Spawn()
        missile:Activate()
        missile:SetNWEntity("GekkoOrbitRPGTarget", enemy)
    end

    local snd = ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)]
    ent:EmitSound(snd, ROCKET_SND_LEVEL, math.random(95, 110), 1)
    return true
end

-- ============================================================
-- NIKITA
-- ============================================================
local function FireNikita(ent, enemy)
    if not IsValid(ent) then return end
    if ent:GetPos():Distance(enemy:GetPos()) < NIKITA_MIN_DIST then return false end

    local src = ent:GetPos() + ent:GetForward() * NIKITA_SPAWN_FORWARD + Vector(0, 0, NIKITA_SPAWN_Z)
    local dir = ent:GetForward()

    local nikita = ents.Create("npc_vj_gekko_nikita")
    if IsValid(nikita) then
        nikita:SetPos(src)
        nikita:SetAngles(dir:Angle())
        nikita:SetOwner(ent)
        nikita:Spawn()
        nikita:Activate()
        nikita:SetNWEntity("GekkoNikitaTarget", enemy)
    end

    local snd = ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)]
    ent:EmitSound(snd, ROCKET_SND_LEVEL, math.random(95, 110), 1)

    for i = 1, NIKITA_MUZZLE_SMOKE_COUNT do
        timer.Simple(i * NIKITA_MUZZLE_SMOKE_STAGGER, function()
            if not IsValid(ent) then return end
            local ed = EffectData()
            ed:SetOrigin(src); ed:SetNormal(dir); ed:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
            util.Effect("SmokeEffect", ed)
        end)
    end

    return true
end

-- ============================================================
-- GRENADE LAUNCHER
-- ============================================================
local function FireGrenadeLauncher(ent, enemy)
    if not IsValid(ent) then return end
    local count = math.random(GL_COUNT_MIN, GL_COUNT_MAX)

    timer.Simple(0, function()
        if IsValid(ent) then
            ent:EmitSound(GL_SOUND_FIDGET, MG_SND_LEVEL, 100, 1)
        end
    end)

    local attCycle = 1
    for i = 0, count - 1 do
        timer.Simple(GL_FIDGET_LEAD + i * GL_INTERVAL, function()
            if not IsValid(ent) then return end

            local curEnemy = GetActiveEnemy(ent)
            if not IsValid(curEnemy) then return end

            local src = ent:GetPos() + Vector(0, 0, GL_LAUNCH_Z)
            local targetPos = curEnemy:GetPos() + Vector(
                math.Rand(-GL_SPREAD_Y, GL_SPREAD_Y), 0, 0
            )
            local dir = (targetPos + Vector(0, 0, 80) - src):GetNormalized()

            local gtype = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
            local params = GL_TYPE_PARAMS[gtype] or GL_TYPE_DEFAULT

            local gren = ents.Create(gtype)
            if IsValid(gren) then
                gren:SetPos(src)
                gren:SetAngles(dir:Angle())
                gren:SetOwner(ent)
                gren:Spawn()
                gren:Activate()
                local phys = gren:GetPhysicsObject()
                if IsValid(phys) then
                    local loftedDir = dir + Vector(0, 0, params.loft)
                    loftedDir:Normalize()
                    phys:SetVelocity(loftedDir * params.speed)
                end
            end

            ent:EmitSound(GL_SOUND_FIRE, MG_SND_LEVEL, math.random(95, 110), 1)

            local att = GL_SPARK_ATT_CYCLE[attCycle]
            local attPos = ent:GetAttachment(att)
            if attPos then
                GLSparks(attPos.Pos, dir, ent)
                GLSmoke(attPos.Pos, dir)
                local eff2 = EffectData()
                eff2:SetOrigin(attPos.Pos); eff2:SetNormal(dir)
                eff2:SetScale(GL_MUZZLE_FLASH_SCALE); eff2:SetMagnitude(GL_MUZZLE_FLASH_SCALE)
                util.Effect("MuzzleFlash", eff2)
            end

            if i % GL_SMOKE_EVERY == 0 then
                local ed2 = EffectData()
                ed2:SetOrigin(src); ed2:SetNormal(dir); ed2:SetScale(GL_SMOKE_SCALE)
                util.Effect(GL_SMOKE_EFFECT, ed2)
            end

            attCycle = (attCycle % #GL_SPARK_ATT_CYCLE) + 1

            if i == count - 1 then
                timer.Simple(0.1, function()
                    if IsValid(ent) then
                        ent:EmitSound(GL_SOUND_INSERT, MG_SND_LEVEL, 100, 1)
                    end
                end)
            end
        end)
    end
    return true
end

-- ============================================================
-- FIRE BUSHMASTER
-- Task 1: +70 u drop compensation + +-17 u vertical jitter
-- Task 2: 55% velocity lead (imperfect aim correction)
-- Task 3: 10% of shots use BM_INTERVAL2 (double delay stutter)
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
            -- ---- Shell ejection sound (0.19 s delay, random 1-7) ----
            local shellSrc = src
            timer.Simple(0.19, function()
                if not IsValid(ent) then return end
                local snd = BM_SHELL_DROP_SOUNDS[math.random(#BM_SHELL_DROP_SOUNDS)]
                ent:EmitSound(snd, 70, math.random(95, 105), 0.8)
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

-- ============================================================
-- ELASTIC TETHER (delegates to elastic_system.lua)
-- ============================================================
local function FireElastic(ent, enemy)
    if ent.Gekko_FireElastic then
        return ent:Gekko_FireElastic(enemy)
    end
    return false
end

-- ============================================================
-- WEAPON COOLDOWN HELPER
-- ============================================================
local WEAPON_COOLDOWN = 2.5
local WEAPON_COOLDOWN_SHORT = 1.2

local function GetWeaponCooldown(wtype)
    if wtype == "MG" then return WEAPON_COOLDOWN_SHORT end
    return WEAPON_COOLDOWN
end

-- ============================================================
-- RELOAD SOUND HELPER
-- ============================================================
local function PlayReload(ent)
    if not IsValid(ent) then return end
    local snd = RELOAD_SNDS[math.random(#RELOAD_SNDS)]
    ent:EmitSound(snd, RELOAD_SND_LEVEL, math.random(95, 105), 1)
end

-- ============================================================
-- MAIN ATTACK DISPATCH
-- (called from VJ_AI_Task_RangeAttack and related hooks)
-- ============================================================
local function DispatchAttack(self, enemy, alt)
    if not IsValid(enemy) then return end

    -- Distance gate for some weapons
    local dist = self:GetPos():Distance(enemy:GetPos())

    if alt then
        -- Alt-fire overrides (used by certain animation events)
        if     alt == "MG"           then return FireMG(self, enemy)
        elseif alt == "MISSILE"      then return FireMissile(self, enemy, 1)
        elseif alt == "SALVO"        then return FireMissile(self, enemy, 2)
        elseif alt == "GRENADE"      then return FireGrenadeLauncher(self, enemy)
        elseif alt == "TOPMISSILE"   then return FireTopMissile(self, enemy)
        elseif alt == "TRACKMISSILE" then return FireTrackMissile(self, enemy)
        elseif alt == "ORBITRPG"     then return FireOrbitRPG(self, enemy)
        elseif alt == "NIKITA"       then return FireNikita(self, enemy)
        elseif alt == "BRUSHMASTER"  then return FireBushmaster(self, enemy)
        elseif alt == "ELASTIC"      then return FireElastic(self, enemy)
        end
        return
    end

    -- Normal weapon roll
    local choice = RollWeapon()
    if     choice == "MG"           then return FireMG(self, enemy)
    elseif choice == "MISSILE"      then return FireMissile(self, enemy, 1)
    elseif choice == "SALVO"        then return FireMissile(self, enemy, 2)
    elseif choice == "GRENADE"      then return FireGrenadeLauncher(self, enemy)
    elseif choice == "TOPMISSILE"   then return FireTopMissile(self, enemy)
    elseif choice == "TRACKMISSILE" then return FireTrackMissile(self, enemy)
    elseif choice == "ORBITRPG"     then return FireOrbitRPG(self, enemy)
    elseif choice == "NIKITA"       then
        if dist >= NIKITA_MIN_DIST then
            return FireNikita(self, enemy)
        end
        return FireMG(self, enemy)
    elseif choice == "BRUSHMASTER"  then return FireBushmaster(self, enemy)
    elseif choice == "ELASTIC"      then return FireElastic(self, enemy)
    end
end

-- ============================================================
-- VJ BASE HOOKS
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/gekko/gekko.mdl")
    self:SetHullType(HULL_HUMAN)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:CapabilitiesAdd(CAP_OPEN_DOORS)
    self:CapabilitiesAdd(CAP_TURN_HEAD)
    self:CapabilitiesAdd(CAP_ANIMATEDFACE)
    self:SetMaxHealth(2200)
    self:SetHealth(2200)
    self:SetBloodColor(BLOOD_COLOR_RED)

    -- Cache pelvis bone for muzzle offset
    self.GekkoPelvisBone = self:LookupBone("Bip01 Pelvis") or -1

    -- Sprint system state
    self._sprintActive    = false
    self._sprintEndTime   = 0
    self._sprintCooldownEndTime = 0

    -- Initialize subsystems
    self:Gekko_InitCrush()
    self:Gekko_InitJump()
    self:Gekko_InitTargetedJump()
    self:Gekko_InitCrouch()
    self:Gekko_InitGib()
    self:Gekko_InitLegDisable()
    self:Gekko_InitDeathPose()
    self:Gekko_InitElastic()
    self:Gekko_InitAPS()
end

function ENT:PostInit()
    -- VJ Base calls this after Initialize
end

-- ============================================================
-- THINK
-- ============================================================
function ENT:Think()
    local now = CurTime()

    -- Sprint system
    local enemy = GetActiveEnemy(self)
    if IsValid(enemy) then
        local dist = self:GetPos():Distance(enemy:GetPos())

        if not self._sprintActive
            and now > self._sprintCooldownEndTime
            and dist < SPRINT_ENGAGE_DIST
        then
            self._sprintActive  = true
            self._sprintEndTime = now + math.Rand(SPRINT_DUR_MIN, SPRINT_DUR_MAX)
        end

        if self._sprintActive and now > self._sprintEndTime then
            self._sprintActive = false
            self._sprintCooldownEndTime = now
                + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
        end
    else
        self._sprintActive = false
    end

    -- Pass to subsystems
    self:Gekko_ThinkCrush()
    self:Gekko_ThinkJump()
    self:Gekko_ThinkTargetedJump()
    self:Gekko_ThinkCrouch()
    self:Gekko_ThinkElastic()
    self:Gekko_ThinkAPS()
    self:NextThink(now)
    return true
end

-- ============================================================
-- MOVEMENT SPEED
-- ============================================================
function ENT:VJ_AI_Move_UpdateSpeed(moveData)
    if self._sprintActive then
        moveData:SetMaxSpeed(SPRINT_MOVE_SPEED)
        moveData:SetMaxClientSpeed(SPRINT_MOVE_SPEED)
        self:SetRunSpeed(SPRINT_RUN_SPEED)
        self:SetWalkSpeed(SPRINT_WALK_SPEED)
        return
    end

    local enemy = GetActiveEnemy(self)
    if IsValid(enemy) then
        local dist = self:GetPos():Distance(enemy:GetPos())
        if dist > RUN_ENGAGE_DIST then
            self:SetRunSpeed(ANIM_RUN_SPEED)
            self:SetWalkSpeed(ANIM_WALK_SPEED)
        elseif dist < RUN_DISENGAGE_DIST then
            self:SetRunSpeed(ANIM_RUN_SPEED)
            self:SetWalkSpeed(ANIM_WALK_SPEED)
        end
    end
end

-- ============================================================
-- RANGED ATTACK
-- ============================================================
function ENT:VJ_AI_Task_RangeAttack()
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    DispatchAttack(self, enemy)
end

-- ============================================================
-- ANIMATION EVENTS (allow animations to trigger specific weapons)
-- ============================================================
function ENT:HandleAnimEvent(ev, options)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end

    if     ev == 1 then DispatchAttack(self, enemy, "MG")
    elseif ev == 2 then DispatchAttack(self, enemy, "MISSILE")
    elseif ev == 3 then DispatchAttack(self, enemy, "SALVO")
    elseif ev == 4 then DispatchAttack(self, enemy, "GRENADE")
    elseif ev == 5 then DispatchAttack(self, enemy, "TOPMISSILE")
    elseif ev == 6 then DispatchAttack(self, enemy, "TRACKMISSILE")
    elseif ev == 7 then DispatchAttack(self, enemy, "ORBITRPG")
    elseif ev == 8 then DispatchAttack(self, enemy, "NIKITA")
    elseif ev == 9 then DispatchAttack(self, enemy, "BRUSHMASTER")
    end
end

-- ============================================================
-- DAMAGE
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    local hitPos    = dmginfo:GetDamagePosition()
    local hitDir    = dmginfo:GetDamageForce():GetNormalized()
    local hitNormal = -hitDir

    -- APS: check if this was an intercepted threat
    if self:Gekko_APSOnDamage(dmginfo) then return end

    -- Flinch
    self:Gekko_FlinchOnDamage(dmginfo)

    -- Leg disable
    self:Gekko_LegDisableOnDamage(dmginfo)

    -- Blood
    local dmgAmt = dmginfo:GetDamage()
    if dmgAmt >= BLOOD_DAMAGE_THRESHOLD or math.random(100) <= BLOOD_RANDOM_CHANCE then
        if math.random() < GROUNDED_BLEED_CHANCE then
            GekkoVanillaBleed(self, hitPos, hitDir)
        end
        GekkoSignalBloodHit(self, hitPos, hitNormal)
    end
end

-- ============================================================
-- DEATH
-- ============================================================
function ENT:OnKilled(dmginfo)
    self:Gekko_DeathPose(dmginfo)
    self:Gekko_GibOnDeath(dmginfo)
    self:Gekko_DisableLegOnDeath()
    self:Gekko_ElasticOnDeath()
end

-- ============================================================
-- SONAR LOCK (net receiver, server)
-- ============================================================
net.Receive("GekkoSonarLock", function(len, ply)
    -- Client pings a lock-on tone: nothing to do server-side, just relay
end)
