-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding Effect (Hemo-fluid-stream)
-- NEW BLEEDING TYPE: gekko_juicy_bleeding (NPC bleeding on hit)
-- INTEGRATED WITH: Active Protection System (aps_system.lua)
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
include("sprint_system.lua")  -- GekkoSprint_Init / Think / End
include("aps_system.lua")     -- Active Protection System

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
local RUN_ENGAGE_DIST = 2200
local RUN_DISENGAGE_DIST = 1600

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

local BM_ROUNDS_MIN = 3
local BM_ROUNDS_MAX = 11
local BM_INTERVAL = 0.36
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
end

-- ============================================================
-- SONAR LOCK FUNCTIONS
-- ============================================================
local function GekkoSendSonarLock(ent, target)
    if not IsValid(ent) or not IsValid(target) then return end
    net.Start("GekkoSonarLock")
        net.WriteEntity(ent)
        net.WriteEntity(target)
    net.Broadcast()
end

-- ============================================================
-- FK360 LAND DUST
-- ============================================================
local function GekkoSendFK360LandDust(ent, pos)
    if not IsValid(ent) then return end
    net.Start("GekkoFK360LandDust")
        net.WriteEntity(ent)
        net.WriteVector(pos)
    net.Broadcast()
end

-- ============================================================
-- ACTIVE ENEMY HELPER
-- ============================================================
local function GetActiveEnemy(ent)
    if not IsValid(ent) then return nil end
    local e = ent:GetEnemy()
    if IsValid(e) and e:Health() > 0 then return e end
    return nil
end

-- ============================================================
-- NET HELPERS
-- ============================================================
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
    local e = EffectData()
    e:SetOrigin(attData.Pos); e:SetNormal(fwd)
    e:SetScale(GL_VAPOR_SCALE)
    util.Effect(GL_VAPOR_EFFECT, e)
end

local function GLSmokeAtPos(pos, dir, shotIndex)
    if shotIndex % GL_SMOKE_EVERY ~= 0 then return end
    local e = EffectData()
    e:SetOrigin(pos); e:SetNormal(dir)
    e:SetScale(GL_SMOKE_SCALE)
    util.Effect(GL_SMOKE_EFFECT, e)
end

local function SpawnCartridge(src, ejectAng, scale)
    local shell = ents.Create("prop_physics")
    if not IsValid(shell) then return end
    shell:SetModel(SHELL_MODEL)
    shell:SetModelScale(scale, 0)
    local right = ejectAng:Right()
    local up    = ejectAng:Up()
    local fwd   = ejectAng:Forward()
    local spawnPos = src
        + right * SHELL_RIGHT_OFFSET
        + up    * SHELL_UP_OFFSET
        + fwd   * SHELL_FWD_OFFSET
    shell:SetPos(spawnPos)
    shell:SetAngles(ejectAng)
    shell:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    shell:Spawn()
    shell:Activate()
    shell:DrawShadow(false)
    local phys = shell:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(SHELL_MASS)
        local vel = right  * math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX)
                  + up     * math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX)
                  + fwd    * math.Rand(SHELL_VEL_FWD_MIN,   SHELL_VEL_FWD_MAX)
        phys:SetVelocity(vel)
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
-- WEAPON ROLL
-- ============================================================
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

local function BushmasterSparks(pos, dir, ent)
    local e = EffectData()
    e:SetOrigin(pos); e:SetNormal(dir); e:SetEntity(ent)
    e:SetMagnitude(BM_SPARK_MAGNITUDE); e:SetScale(BM_SPARK_SCALE); e:SetRadius(BM_SPARK_RADIUS)
    util.Effect("ManhackSparks", e)
end

local function BushmasterSmoke(pos, dir)
    local ed = EffectData()
    ed:SetOrigin(pos + dir * BM_SMOKE_FORWARD + Vector(0, 0, BM_SMOKE_UP))
    ed:SetNormal(dir); ed:SetScale(BM_SMOKE_SCALE); ed:SetMagnitude(1)
    util.Effect("SmokeEffect", ed)
end

-- ============================================================
-- FIRE FUNCTIONS
-- ============================================================
local function FireMGBurst(ent, enemy)
    local rounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local chainCount = 0
    for i = 0, rounds - 1 do
        timer.Simple(i * MG_INTERVAL, function()
            if not IsValid(ent) then return end
            local attData = ent:GetAttachment(ATT_MACHINEGUN)
            local src = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, 60))
            local fwd = attData and attData.Ang:Forward() or ent:GetForward()
            chainCount = chainCount + 1
            if chainCount % MG_CHAIN_EVERY == 0 then
                ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, math.random(95, 110), 1)
            end
            local curEnemy = GetActiveEnemy(ent)
            if not IsValid(curEnemy) then return end
            local spread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
            local dmginfo = DamageInfo()
            dmginfo:SetDamage(MG_DAMAGE)
            dmginfo:SetAttacker(ent)
            dmginfo:SetInflictor(ent)
            dmginfo:SetDamageType(DMG_BULLET)
            local tr = util.TraceLine({
                start  = src,
                endpos = curEnemy:GetPos() + Vector(0, 0, 40)
                        + Vector(math.Rand(-spread, spread) * 100,
                                 math.Rand(-spread, spread) * 100,
                                 math.Rand(-spread, spread) * 100),
                filter = ent,
                mask   = MASK_SHOT,
            })
            if tr.Hit and IsValid(tr.Entity) then
                dmginfo:SetDamagePosition(tr.HitPos)
                dmginfo:SetDamageForce(fwd * MG_DAMAGE * 50)
                tr.Entity:TakeDamageInfo(dmginfo)
                GekkoSignalBloodHit(tr.Entity, tr.HitPos, tr.HitNormal)
            end
            if i % MG_FLASH_EVERY == 0 then
                local eff = EffectData()
                eff:SetOrigin(src); eff:SetNormal(fwd)
                util.Effect("MuzzleFlash", eff)
                SendMuzzleFlash(src, fwd, 1)
                SendBulletImpact(tr.HitPos, tr.HitNormal, 1)
            end
            ent:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(95, 110), 1)
            SpawnCartridge(src, ent:GetAngles(), MG_SHELL_SCALE)
        end)
    end
    return true
end

local function FireMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        return FireMGBurst(ent, enemy)
    end
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    SpawnRocket(ent, ATT_MISSILE_L, aimPos)
    ent:EmitSound(MISSILE_SOUND_WARN, 80, 100, 1)
    return true
end

local function FireSalvo(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        return FireMGBurst(ent, enemy)
    end
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    SpawnRocket(ent, ATT_MISSILE_L, aimPos, SalvoSpread())
    timer.Simple(SALVO_DELAY, function()
        if not IsValid(ent) then return end
        local curEnemy = GetActiveEnemy(ent)
        local curAim   = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0, 0, 40)) or aimPos
        SpawnRocket(ent, ATT_MISSILE_R, curAim, SalvoSpread())
    end)
    ent:EmitSound(MISSILE_SOUND_WARN, 80, 100, 1)
    return true
end

local function FireGrenadeLauncher(ent, enemy)
    local count = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    local aimPos = enemy:GetPos()
    ent:EmitSound(GL_SOUND_FIDGET, MG_SND_LEVEL, 100, 1)
    for i = 1, count do
        timer.Simple((i - 1) * GL_INTERVAL + GL_FIDGET_LEAD, function()
            if not IsValid(ent) then return end
            local curEnemy = GetActiveEnemy(ent)
            local tgt = IsValid(curEnemy) and curEnemy:GetPos() or aimPos
            local attIdx = GL_SPARK_ATT_CYCLE[((i - 1) % #GL_SPARK_ATT_CYCLE) + 1]
            local attData = ent:GetAttachment(attIdx)
            local src = attData and attData.Pos or (ent:GetPos() + Vector(0, 0, GL_LAUNCH_Z))
            local gType = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
            local params = GL_TYPE_PARAMS[gType] or GL_TYPE_DEFAULT
            local loft = Vector(0, 0, params.speed * params.loft)
            local spread = Vector(
                (math.random() - 0.5) * 2 * GL_SPREAD_Y,
                (math.random() - 0.5) * 2 * GL_SPREAD_Y,
                0
            )
            local dir = ((tgt + spread + loft) - src):GetNormalized()
            local gren = ents.Create(gType)
            if IsValid(gren) then
                gren:SetPos(src); gren:SetAngles(dir:Angle())
                gren:SetOwner(ent); gren:Spawn(); gren:Activate()
                local phys = gren:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(dir * params.speed)
                end
                local trail = ents.Create("env_spritetail")
                if IsValid(trail) then
                    trail:SetPos(src)
                    trail:SetParent(gren)
                    trail:SetKeyValue("lifetime", tostring(GL_TRAIL_LIFETIME))
                    trail:SetKeyValue("startwidth", tostring(GL_TRAIL_STARTSIZE))
                    trail:SetKeyValue("endwidth", tostring(GL_TRAIL_ENDSIZE))
                    trail:SetKeyValue("spritename", GL_TRAIL_MATERIAL)
                    trail:SetKeyValue("rendercolor", GL_TRAIL_COLOR.r .. " " .. GL_TRAIL_COLOR.g .. " " .. GL_TRAIL_COLOR.b)
                    trail:SetKeyValue("renderamt", tostring(GL_TRAIL_COLOR.a))
                    trail:Spawn(); trail:Activate()
                    timer.Simple(3, function() if IsValid(trail) then trail:Remove() end end)
                end
            end
            GLSparkAtAttachment(ent, i)
            GLVaporAtAttachment(ent, i)
            GLSmokeAtPos(src, dir, i)
            local muzzleEff = EffectData()
            muzzleEff:SetOrigin(src); muzzleEff:SetNormal(dir)
            muzzleEff:SetScale(GL_MUZZLE_FLASH_SCALE)
            util.Effect("MuzzleFlash", muzzleEff)
            ent:EmitSound(GL_SOUND_FIRE, MG_SND_LEVEL, math.random(90, 110), 1)
            if i % 3 == 0 then
                ent:EmitSound(GL_SOUND_INSERT, MG_SND_LEVEL, 100, 1)
            end
        end)
    end
    return true
end

local function FireTopMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        return FireMGBurst(ent, enemy)
    end
    local aimPos = enemy:GetPos()
    local src = ent:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local missile = ents.Create("sent_npc_topmissile")
    if IsValid(missile) then
        missile:SetPos(src)
        missile:SetAngles(Angle(0, ent:GetAngles().y, 0))
        missile:SetOwner(ent)
        if missile.SetTargetPos then missile:SetTargetPos(aimPos) end
        missile:Spawn(); missile:Activate()
    end
    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
    ent:EmitSound(MISSILE_SOUND_WARN, 80, 100, 1)
    return true
end

local function FireTrackMissile(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        return FireMGBurst(ent, enemy)
    end
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local src = ent:GetPos() + ent:GetForward() * MISSILE_SPAWN_FORWARD + Vector(0, 0, 40)
    local dir = (aimPos - src):GetNormalized()
    local missile = ents.Create("sent_npc_trackmissile")
    if IsValid(missile) then
        missile:SetPos(src); missile:SetAngles(dir:Angle())
        missile:SetOwner(ent); missile:Spawn(); missile:Activate()
    end
    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(95, 110), 1)
    ent:EmitSound(MISSILE_SOUND_WARN, 80, 100, 1)
    GekkoSendSonarLock(ent, enemy)
    return true
end

local function FireOrbitRPG(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        return FireMGBurst(ent, enemy)
    end
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local misAtt = ent:GetAttachment(ATT_MISSILE_L)
    local src = misAtt and misAtt.Pos or (ent:GetPos() + Vector(0, 0, 160))
    local dir = (aimPos - src):GetNormalized()
    local rpg = ents.Create("sent_orbital_rpg")
    if IsValid(rpg) then
        rpg:SetPos(src); rpg:SetAngles(dir:Angle())
        rpg:SetOwner(ent); rpg:Spawn(); rpg:Activate()
    end
    local eff = EffectData(); eff:SetOrigin(src); eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)
    SendMuzzleFlash(src, dir, 2)
    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(95, 110), 1)
    ent:EmitSound(MISSILE_SOUND_WARN, 80, 100, 1)
    return true
end

local function FireNikita(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist < NIKITA_MIN_DIST then
        return FireMGBurst(ent, enemy)
    end
    local src = ent:GetPos() + ent:GetForward() * NIKITA_SPAWN_FORWARD + Vector(0, 0, NIKITA_SPAWN_Z)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local dir = (aimPos - src):GetNormalized()
    local nikita = ents.Create("npc_vj_gekko_nikita")
    if IsValid(nikita) then
        nikita:SetPos(src); nikita:SetAngles(dir:Angle())
        nikita:SetOwner(ent); nikita:Spawn(); nikita:Activate()
        if nikita.SetTarget then
            nikita:SetTarget(enemy)
        elseif nikita.VJ_DoSetEnemy then
            nikita:VJ_DoSetEnemy(enemy, true, true)
        else
            nikita:SetEnemy(enemy)
        end
    end
    for k = 1, NIKITA_MUZZLE_SMOKE_COUNT do
        timer.Simple((k - 1) * NIKITA_MUZZLE_SMOKE_STAGGER, function()
            if not IsValid(ent) then return end
            local smokeEff = EffectData()
            smokeEff:SetOrigin(src); smokeEff:SetNormal(dir)
            smokeEff:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
            util.Effect("SmokeEffect", smokeEff)
        end)
    end
    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(95, 110), 1)
    print(string.format("[GekkoNikita] Launched | dist=%.0f", dist))
    return true
end

local BM_INTERVAL2        = 0.72
local BM_DROP_COMP        = 70
local BM_DROP_JITTER      = 17
local BM_VEL_LEAD_FRAC    = 0.55

local BM_SHELL_SPEED = 3950
local function BM_PredictAimPos(src, targetEnt, baseAimPos)
    if not IsValid(targetEnt) then return baseAimPos end
    local vel = targetEnt:GetVelocity()
    if vel:LengthSqr() < 4 then return baseAimPos end
    local dist = src:Distance(baseAimPos)
    local travelTime = dist / BM_SHELL_SPEED
    return baseAimPos + vel * (travelTime * BM_VEL_LEAD_FRAC)
end

local function FireBushmaster(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local rounds = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)

    local fireTimes = {}
    local t = 0
    for i = 0, rounds - 1 do
        fireTimes[i] = t
        local interval = (math.random(100) <= 10) and BM_INTERVAL2 or BM_INTERVAL
        t = t + interval
    end

    for i = 0, rounds - 1 do
        local shot      = i
        local fireDelay = fireTimes[i]
        timer.Simple(fireDelay, function()
            if not IsValid(ent) then return end
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
            local curEnemy = GetActiveEnemy(ent)

            local baseAim
            if IsValid(curEnemy) then
                baseAim = curEnemy:GetPos() + Vector(0, 0, 40)
            else
                baseAim = aimPos
            end
            local leadAim = BM_PredictAimPos(src, curEnemy, baseAim)
            local jitter  = math.Rand(-BM_DROP_JITTER, BM_DROP_JITTER)
            local curAim  = leadAim + Vector(0, 0, BM_DROP_COMP + jitter)

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
            net.Start("GekkoBushRecoil")
                net.WriteEntity(ent)
                net.WriteVector(src)
                net.WriteVector(-dir)
            net.Broadcast()
            if shot == rounds - 1 then
                timer.Simple(0.12, function()
                    if not IsValid(ent) then return end
                    ent:EmitSound(BM_SND_RELOAD, BM_SND_LEVEL, 100, 1)
                end)
            end
        end)
    end
    print(string.format("[GekkoBM] Salvo | rounds=%d base_interval=%.2fs", rounds, BM_INTERVAL))
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
        elseif alt == "SALVO"        then return FireSalvo(ent, enemy)
        elseif alt == "GRENADE"      then return FireGrenadeLauncher(ent, enemy)
        elseif alt == "TOPMISSILE"   then return FireTopMissile(ent, enemy)
        elseif alt == "TRACKMISSILE" then return FireTrackMissile(ent, enemy)
        elseif alt == "ORBITRPG"     then return FireOrbitRPG(ent, enemy)
        elseif alt == "NIKITA"       then return FireNikita(ent, enemy)
        else                              return FireBushmaster(ent, enemy)
        end
    end
    ent:GekkoElastic_Fire(enemy)
    return true
end

-- ============================================================
-- RELOAD SOUND HELPER
-- ============================================================
local function PlayReloadSound(ent)
    ent:EmitSound(RELOAD_SNDS[math.random(#RELOAD_SNDS)], RELOAD_SND_LEVEL, math.random(95, 105), 1)
end

-- ============================================================
-- VJ BASE OVERRIDES
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/gekko/gekko.mdl")
    self:SetHullType(HULL_HUMAN)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_NONE)
    self:SetSolid(SOLID_BBOX)

    self:SetMaxHealth(2500)
    self:SetHealth(2500)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:CapabilitiesAdd(CAP_OPEN_DOORS)
    self:CapabilitiesAdd(CAP_AUTO_DOORS)
    self:CapabilitiesAdd(CAP_TURN_HEAD)

    self:SetNavType(NAV_GROUND)
    self:SetMoveType(MOVETYPE_STEP)

    self.GekkoPelvisBone = self:LookupBone("ValveBiped.Bip01_Pelvis")

    self._weaponCooldown    = 0
    self._lastWeapon        = ""
    self._gekkoDead         = false
    self._bloodSplatPulse   = 0
    self._lastReload        = 0

    GekkoSprint_Init(self)
    GekkoJump_Init(self)
    GekkoTargetedJump_Init(self)
    GekkoCrouch_Init(self)
    GekkoGib_Init(self)
    GekkoLegDisable_Init(self)
    GekkoDeathPose_Init(self)
    self:GekkoElastic_Init()

    -- ---- Active Protection System ----
    GekkoAPS_Init(self)

    self:SetSchedule(SCHED_IDLE_WANDER)
    self:SetNPCState(NPC_STATE_IDLE)
end

function ENT:PostInit()
end

-- ============================================================
-- THINK (weapon selection)
-- ============================================================
local WEAPON_COOLDOWN_MIN = 3.5
local WEAPON_COOLDOWN_MAX = 6.5

function ENT:RunTask(task)
end

function ENT:Think()
    local now = CurTime()

    -- ---- Active Protection System (always-on) ----
    GekkoAPS_Think(self, now)

    GekkoSprint_Think(self, now)
    GekkoJump_Think(self, now)
    GekkoTargetedJump_Think(self, now)
    GekkoCrouch_Think(self, now)
    self:GekkoElastic_Think(now)

    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then
        self:NextThink(now + 0.1)
        return true
    end

    if now < self._weaponCooldown then
        self:NextThink(now + 0.05)
        return true
    end

    local choice = RollWeapon()
    self._lastWeapon = choice

    local fired = false
    if     choice == "MG"           then fired = FireMGBurst(self, enemy)
    elseif choice == "MISSILE"      then fired = FireMissile(self, enemy)
    elseif choice == "SALVO"        then fired = FireSalvo(self, enemy)
    elseif choice == "GRENADE"      then fired = FireGrenadeLauncher(self, enemy)
    elseif choice == "TOPMISSILE"   then fired = FireTopMissile(self, enemy)
    elseif choice == "TRACKMISSILE" then fired = FireTrackMissile(self, enemy)
    elseif choice == "ORBITRPG"     then fired = FireOrbitRPG(self, enemy)
    elseif choice == "NIKITA"       then fired = FireNikita(self, enemy)
    elseif choice == "ELASTIC"      then fired = FireElastic(self, enemy)
    elseif choice == "BRUSHMASTER"  then fired = FireBushmaster(self, enemy)
    end

    if fired then
        PlayReloadSound(self)
        self._weaponCooldown = now + math.Rand(WEAPON_COOLDOWN_MIN, WEAPON_COOLDOWN_MAX)
    end

    self:NextThink(now + 0.05)
    return true
end

-- ============================================================
-- SCHEDULED WEAPON THINK (alternate path some VJ bases use)
-- ============================================================
function ENT:VJ_OnThink()
    local now = CurTime()
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    if now < self._weaponCooldown then return end

    local choice = RollWeapon()
    self._lastWeapon = choice

    local fired = false
    if     choice == "MG"           then fired = FireMGBurst(self, enemy)
    elseif choice == "MISSILE"      then fired = FireMissile(self, enemy)
    elseif choice == "SALVO"        then fired = FireSalvo(self, enemy)
    elseif choice == "GRENADE"      then fired = FireGrenadeLauncher(self, enemy)
    elseif choice == "TOPMISSILE"   then fired = FireTopMissile(self, enemy)
    elseif choice == "TRACKMISSILE" then fired = FireTrackMissile(self, enemy)
    elseif choice == "ORBITRPG"     then fired = FireOrbitRPG(self, enemy)
    elseif choice == "NIKITA"       then fired = FireNikita(self, enemy)
    elseif choice == "ELASTIC"      then fired = FireElastic(self, enemy)
    elseif choice == "BRUSHMASTER"  then fired = FireBushmaster(self, enemy)
    end

    if fired then
        PlayReloadSound(self)
        self._weaponCooldown = now + math.Rand(WEAPON_COOLDOWN_MIN, WEAPON_COOLDOWN_MAX)
    end
end

-- ============================================================
-- DAMAGE / BLOOD
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    local dmg     = dmginfo:GetDamage()
    local hitPos  = dmginfo:GetDamagePosition()
    local hitNorm = (hitPos - self:GetPos()):GetNormalized()

    if dmg >= BLOOD_DAMAGE_THRESHOLD then
        if math.random(100) <= BLOOD_RANDOM_CHANCE then
            GekkoSignalBloodHit(self, hitPos, hitNorm)
        end
    end

    GekkoLegDisable_OnDamage(self, dmginfo)
end

-- ============================================================
-- DEATH
-- ============================================================
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
