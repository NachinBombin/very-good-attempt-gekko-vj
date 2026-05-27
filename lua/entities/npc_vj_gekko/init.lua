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
    cum = cum + WWEIGHT_BUSHMASTER;      if r <= cum then return "BUSHMASTER" end
    return "ELASTIC"
end

local function ShouldJuicyBleed(dmginfo)
    if dmginfo:GetDamage() < BLOOD_DAMAGE_THRESHOLD then return false end
    if math.random(1, 100) > BLOOD_RANDOM_CHANCE then return false end
    return true
end

local function FindFloorBelow(ent)
    local pos = ent:GetPos()
    local tr = util.TraceLine({
        start  = pos,
        endpos = pos + Vector(0, 0, -180),
        filter = ent,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then return tr.HitPos end
    return nil
end

-- ============================================================
-- HIT-IMPULSE SYSTEM
-- ============================================================
local HIT_IMPULSE_HORIZ = 6.5
local HIT_IMPULSE_VERT  = 1.8
local HIT_IMPULSE_CAP   = 480

local function GekkoApplyHitImpulse(ent, hitDir, dmg)
    local horiz = Vector(hitDir.x, hitDir.y, 0)
    horiz:Normalize()
    local impulse = horiz * (dmg * HIT_IMPULSE_HORIZ)
                  + Vector(0, 0, dmg * HIT_IMPULSE_VERT)
    local mag = impulse:Length()
    if mag > HIT_IMPULSE_CAP then
        impulse = impulse * (HIT_IMPULSE_CAP / mag)
    end
    ent:SetVelocity(impulse)
end

-- ============================================================
-- HIT POSITION RESOLVER
-- ============================================================
local HEAD_Z_FRACTION = 0.88

local function GekkoResolveHitPos(ent, dmginfo)
    local p = dmginfo:GetDamagePosition()
    if p ~= Vector(0,0,0) then return p, "dmgpos" end

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) then
        local tr = util.TraceLine({
            start  = attacker:EyePos(),
            endpos = ent:WorldSpaceCenter(),
            filter = attacker,
            mask   = MASK_SHOT,
        })
        if tr.Hit then return tr.HitPos, "trace" end
    end

    return ent:WorldSpaceCenter(), "center"
end

-- ============================================================
-- SHELL EJECTION
-- ============================================================
local function EjectShell(ent, scale)
    local ang = ent:GetAngles()
    local fwd = ent:GetForward()
    local rgt = ent:GetRight()
    local up  = ent:GetUp()

    local pos = ent:GetPos()
               + rgt * SHELL_RIGHT_OFFSET
               + up  * SHELL_UP_OFFSET
               + fwd * SHELL_FWD_OFFSET

    local shell = ents.Create("prop_physics_override")
    if not IsValid(shell) then return end
    shell:SetModel(SHELL_MODEL)
    shell:SetPos(pos)
    shell:SetAngles(ang)
    shell:SetModelScale(scale or MG_SHELL_SCALE)
    shell:Spawn()
    shell:Activate()
    shell:PhysicsInit(SOLID_VPHYSICS)

    local phys = shell:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(SHELL_MASS)
        local velRight = math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX)
        local velUp    = math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX)
        local velFwd   = math.Rand(SHELL_VEL_FWD_MIN,   SHELL_VEL_FWD_MAX)
        local vel = rgt * velRight + up * velUp + fwd * velFwd
        phys:SetVelocity(vel)
        local angVel = Vector(
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX)
        )
        phys:SetAngleVelocity(angVel)
    end

    timer.Simple(SHELL_LIFETIME, function()
        if IsValid(shell) then shell:Remove() end
    end)
end

-- ============================================================
-- MUZZLE FLASH NETWORK SENDER (server side)
-- ============================================================
local function SendMuzzleFlash(ent, attachID, presetID)
    net.Start("GekkoMuzzleFlash")
        net.WriteEntity(ent)
        net.WriteUInt(attachID, 8)
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

-- ============================================================
-- GEKKO NPC ENTITY
-- ============================================================
ENT.Type           = "nextbot"
ENT.Base           = "base_ai"
ENT.PrintName      = "Gekko"
ENT.Author         = "NachinBombin"
ENT.Category       = "VJ Base"
ENT.Spawnable      = true
ENT.AdminSpawnable = true
ENT.VJ_NPC_CLASS   = { "CLASS_COMBINE" }

if CLIENT then return end

local WEPSELECT_DELAY_MIN = 0.4
local WEPSELECT_DELAY_MAX = 1.6
local WEPSELECT_COMBAT_ONLY = false

local ATTACK_DIST_MIN = 900
local ATTACK_DIST_MAX = 5500

local NIKITA_ACTIVE_MAX = 2

-- ============================================================
-- NPC SEQUENCE CACHE (server)
-- ============================================================
local function GekkoUpdateAnimation(self)
    -- see ENT:GekkoUpdateAnimation() defined below
end

function ENT:CacheSeqs()
    local walkSeq = self:LookupSequence("walk")
    local runSeq  = self:LookupSequence("run")
    local idleSeq = self:LookupSequence("idle_alert")

    self.GekkoSeq_Walk = (walkSeq and walkSeq ~= -1) and walkSeq or -1
    self.GekkoSeq_Run  = (runSeq  and runSeq  ~= -1) and runSeq  or -1
    self.GekkoSeq_Idle = (idleSeq and idleSeq ~= -1) and idleSeq or -1

    self.GekkoSeq_Walk = self.GekkoSeq_Walk
    self.GekkoSeq_Run  = self.GekkoSeq_Run
    self.GekkoSeq_Idle = self.GekkoSeq_Idle
end

function ENT:GekkoUpdateSeqCache()
    self.GekkoSeq_Walk = self:LookupSequence("walk")
    self.GekkoSeq_Run  = self:LookupSequence("run")
    self.GekkoSeq_Idle = self:LookupSequence("idle_alert")

    local walkSeq = self.GekkoSeq_Walk
    local runSeq  = self.GekkoSeq_Run
    local idleSeq = self.GekkoSeq_Idle

    self.GekkoSeq_Walk = walkSeq
    self.GekkoSeq_Run  = runSeq
    self.GekkoSeq_Idle = idleSeq
end

local SPRINT_ANIM_SPEED = SPRINT_RUN_SPEED

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
    if now < (self._gekkoSuppressActivity or 0) then
        -- During a dodge slide the suppress guard is active, but we still
        -- need GeckoCrouch_Update to enforce the duck animation each tick.
        if self:GeckoCrouch_Update() then return end
        return
    end
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
        elseif self._gekkoSprinting then
            targetSeq = self.GekkoSeq_Run;  arate = vel / SPRINT_ANIM_SPEED
        else
            targetSeq = self.GekkoSeq_Walk; arate = vel / ANIM_WALK_SPEED
        end
    else
        targetSeq = self.GekkoSeq_Idle; arate = 1
    end
    if targetSeq and targetSeq ~= -1 then
        self:ResetSequence(targetSeq)
        self:SetPlaybackRate(arate)
    end
end

-- ============================================================
-- WEAPON FIRING FUNCTIONS
-- ============================================================
local function FireMG(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local origin = ent:GetAttachment(ATT_MACHINEGUN)
    if not origin then return end

    local rounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    ent._mgRoundsLeft = rounds
    ent._mgBurstActive = true
    ent._mgBurstEndT   = CurTime() + rounds * MG_INTERVAL + 0.3
    ent:SetNWBool("GekkoMGFiring", true)

    local function FireOne()
        if not IsValid(ent) or not ent._mgBurstActive then return end
        if ent._mgRoundsLeft <= 0 then
            ent._mgBurstActive = false
            ent:SetNWBool("GekkoMGFiring", false)
            return
        end
        ent._mgRoundsLeft = ent._mgRoundsLeft - 1

        local att = ent:GetAttachment(ATT_MACHINEGUN)
        if not att then return end

        local en = GetActiveEnemy(ent)
        if not IsValid(en) then
            ent._mgBurstActive = false
            ent:SetNWBool("GekkoMGFiring", false)
            return
        end

        local spread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
        local aimPos = en:WorldSpaceCenter()
        local dir = (aimPos - att.Pos):GetNormalized()
        dir.x = dir.x + math.Rand(-spread, spread)
        dir.y = dir.y + math.Rand(-spread, spread)
        dir.z = dir.z + math.Rand(-spread * 0.5, spread * 0.5)
        dir:Normalize()

        local tr = util.TraceLine({
            start  = att.Pos,
            endpos = att.Pos + dir * 8000,
            filter = ent,
            mask   = MASK_SHOT,
        })

        if tr.Hit and IsValid(tr.Entity) then
            local dmginfo = DamageInfo()
            dmginfo:SetDamage(MG_DAMAGE)
            dmginfo:SetAttacker(ent)
            dmginfo:SetInflictor(ent)
            dmginfo:SetDamageType(DMG_BULLET)
            dmginfo:SetDamagePosition(tr.HitPos)
            dmginfo:SetDamageForce(dir * MG_DAMAGE * 50)
            tr.Entity:TakeDamageInfo(dmginfo)
        end

        ent:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(95, 110))

        local roundNum = rounds - ent._mgRoundsLeft
        if roundNum % MG_CHAIN_EVERY == 0 then
            ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL - 10, math.random(95, 105))
        end

        if roundNum % MG_FLASH_EVERY == 0 then
            SendMuzzleFlash(ent, ATT_MACHINEGUN, 1)
        end

        if tr.Hit then
            SendBulletImpact(tr.HitPos, tr.HitNormal, 1)
        end

        if ent._mgRoundsLeft > 0 then
            timer.Simple(MG_INTERVAL, FireOne)
        else
            ent._mgBurstActive = false
            ent:SetNWBool("GekkoMGFiring", false)
        end
    end

    FireOne()
end

local function FireMissile(ent, side)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local attID = (side == "L") and ATT_MISSILE_L or ATT_MISSILE_R
    local att = ent:GetAttachment(attID)
    if not att then return end

    local rocket = ents.Create("obj_gekko_rocket")
    if not IsValid(rocket) then return end
    rocket:SetPos(att.Pos)
    rocket:SetAngles(att.Ang)
    rocket:SetOwner(ent)
    rocket:Spawn()
    rocket:Activate()

    local dir = (enemy:WorldSpaceCenter() - att.Pos):GetNormalized()
    rocket:SetVelocity(dir * 1200)

    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(92, 108))
end

local function FireSalvo(ent)
    FireMissile(ent, "L")
    timer.Simple(SALVO_DELAY, function()
        if IsValid(ent) then FireMissile(ent, "R") end
    end)
end

local function FireTopMissile(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local att = ent:GetAttachment(ATT_MISSILE_L)
    if not att then return end

    local missile = ents.Create("sent_npc_topmissile")
    if not IsValid(missile) then return end
    missile:SetPos(att.Pos)
    missile:SetAngles(att.Ang)
    missile:SetOwner(ent)
    missile:Spawn()
    missile:Activate()

    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(90, 110))
end

local function FireTrackMissile(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local att = ent:GetAttachment(ATT_MISSILE_R)
    if not att then return end

    local missile = ents.Create("sent_npc_trackmissile")
    if not IsValid(missile) then return end
    missile:SetPos(att.Pos)
    missile:SetAngles(att.Ang)
    missile:SetOwner(ent)
    missile:Spawn()
    missile:Activate()

    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(90, 110))
end

local function FireOrbitRPG(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local att = ent:GetAttachment(ATT_MISSILE_L)
    if not att then return end

    local rpg = ents.Create("sent_orbital_rpg")
    if not IsValid(rpg) then return end
    rpg:SetPos(att.Pos)
    rpg:SetAngles(att.Ang)
    rpg:SetOwner(ent)
    rpg:Spawn()
    rpg:Activate()

    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(90, 110))
end

local function FireNikita(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local count = 0
    for _, e in ipairs(ents.FindByClass("npc_vj_gekko_nikita")) do
        if IsValid(e) and e:GetOwner() == ent then count = count + 1 end
    end
    if count >= NIKITA_ACTIVE_MAX then return end

    local att = ent:GetAttachment(ATT_MISSILE_L)
    if not att then return end

    local nikita = ents.Create("npc_vj_gekko_nikita")
    if not IsValid(nikita) then return end
    nikita:SetPos(att.Pos)
    nikita:SetAngles(att.Ang)
    nikita:SetOwner(ent)
    nikita:Spawn()
    nikita:Activate()

    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(90, 110))
end

local function FireGrenadeLauncher(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local grenadeClass = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
    local params = GL_TYPE_PARAMS[grenadeClass] or GL_TYPE_DEFAULT
    local count  = math.random(GL_COUNT_MIN, GL_COUNT_MAX)

    ent:EmitSound(GL_SOUND_FIDGET, 95, math.random(95, 105))

    timer.Simple(GL_FIDGET_LEAD, function()
        if not IsValid(ent) then return end
        ent:EmitSound(GL_SOUND_INSERT, 90, math.random(95, 105))
    end)

    for i = 1, count do
        timer.Simple((i - 1) * GL_INTERVAL + GL_FIDGET_LEAD, function()
            if not IsValid(ent) then return end

            local att = ent:GetAttachment(ATT_MISSILE_L)
            if not att then return end

            local en = GetActiveEnemy(ent)
            if not IsValid(en) then return end

            local aimPos = en:WorldSpaceCenter()
            local spreadY = math.Rand(-GL_SPREAD_Y, GL_SPREAD_Y)
            aimPos.y = aimPos.y + spreadY

            local startPos = att.Pos + Vector(0, 0, GL_LAUNCH_Z)
            local dir = (aimPos - startPos):GetNormalized()
            dir.z = dir.z + params.loft
            dir:Normalize()

            local gren = ents.Create(grenadeClass)
            if not IsValid(gren) then return end
            gren:SetPos(startPos)
            gren:SetAngles(dir:Angle())
            gren:SetOwner(ent)
            gren:Spawn()
            gren:Activate()

            local phys = gren:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(dir * params.speed)
            end

            ent:EmitSound(GL_SOUND_FIRE, 100, math.random(93, 107))

            -- Smoke trail
            local trail = ents.Create("env_smoketrail")
            if IsValid(trail) then
                trail:SetPos(startPos)
                trail:SetParent(gren)
                trail:Spawn()
                trail:Activate()
            end
        end)
    end
end

local function FireBushmaster(ent)
    if not IsValid(ent) then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end

    local rounds = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)
    local bushmasterEnt = ents.Create("sent_gekko_bushmaster")
    if not IsValid(bushmasterEnt) then return end

    bushmasterEnt:SetOwner(ent)
    bushmasterEnt:SetPos(ent:GetPos())
    bushmasterEnt:SetAngles(ent:GetAngles())
    bushmasterEnt:Spawn()
    bushmasterEnt:Activate()

    ent._bushmasterActive = true
    ent._bushmasterEndT   = CurTime() + rounds * BM_INTERVAL + 0.5
end

local function FireElastic(ent)
    if not IsValid(ent) then return end
    ent:GekkoElastic_Fire()
end

-- ============================================================
-- WEPSELECT TIMER
-- ============================================================
local function ScheduleNextAttack(ent)
    local delay = math.Rand(WEPSELECT_DELAY_MIN, WEPSELECT_DELAY_MAX)
    timer.Simple(delay, function()
        if not IsValid(ent) or ent._gekkoDead then return end
        local enemy = GetActiveEnemy(ent)
        if not IsValid(enemy) then
            ScheduleNextAttack(ent)
            return
        end
        local dist = ent:GetPos():Distance(enemy:GetPos())
        if dist < ATTACK_DIST_MIN or dist > ATTACK_DIST_MAX then
            ScheduleNextAttack(ent)
            return
        end
        local wep = RollWeapon()
        ent._lastWeapon = wep
        if     wep == "MG"          then FireMG(ent)
        elseif wep == "MISSILE"     then FireMissile(ent, math.random(2) == 1 and "L" or "R")
        elseif wep == "SALVO"       then FireSalvo(ent)
        elseif wep == "GRENADE"     then FireGrenadeLauncher(ent)
        elseif wep == "TOPMISSILE" then FireTopMissile(ent)
        elseif wep == "TRACKMISSILE" then FireTrackMissile(ent)
        elseif wep == "ORBITRPG"   then FireOrbitRPG(ent)
        elseif wep == "NIKITA"     then FireNikita(ent)
        elseif wep == "BUSHMASTER" then FireBushmaster(ent)
        elseif wep == "ELASTIC"    then FireElastic(ent)
        end
        ScheduleNextAttack(ent)
    end)
end

-- ============================================================
-- SPRINT SYSTEM
-- ============================================================
local function GekkoSprint_Think(ent)
    local now = CurTime()
    if ent._gekkoDead then return end
    if ent._gekkoSprinting then
        if now > ent._gekkoSprintEndT then
            GekkoSprint_End(ent)
        end
        return
    end
    if now < ent._gekkoSprintCooldownT then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then return end
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist > SPRINT_ENGAGE_DIST then return end
    ent._gekkoSprinting   = true
    ent._gekkoSprintEndT  = now + math.Rand(SPRINT_DUR_MIN, SPRINT_DUR_MAX)
    ent:SetNWBool("GekkoSprinting", true)
    ent.MoveType = MOVETYPE_WALK
    ent:SetMaxSpeed(SPRINT_MOVE_SPEED)
    ent:SetRunSpeed(SPRINT_RUN_SPEED)
    ent:SetWalkSpeed(SPRINT_WALK_SPEED)
end

function GekkoSprint_End(ent)
    if not IsValid(ent) then return end
    ent._gekkoSprinting       = false
    ent._gekkoSprintCooldownT = CurTime() + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
    ent:SetNWBool("GekkoSprinting", false)
    ent:SetMaxSpeed(ent.VJ_NPC_MoveSpeed or 200)
    ent:SetRunSpeed(ent.VJ_NPC_MoveSpeed or 200)
    ent:SetWalkSpeed(ent.VJ_NPC_MoveSpeed or 200)
end

-- ============================================================
-- RELOAD SOUND
-- ============================================================
local RELOAD_INTERVAL_MIN = 8
local RELOAD_INTERVAL_MAX = 20

local function ScheduleReload(ent)
    timer.Simple(math.Rand(RELOAD_INTERVAL_MIN, RELOAD_INTERVAL_MAX), function()
        if not IsValid(ent) or ent._gekkoDead then return end
        ent:EmitSound(RELOAD_SNDS[math.random(#RELOAD_SNDS)], RELOAD_SND_LEVEL, math.random(93, 107))
        ScheduleReload(ent)
    end)
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/gekko.mdl")
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_COMBAT)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)

    self.VJ_NPC_CLASS      = { "CLASS_COMBINE" }
    self.VJ_NPC_MoveSpeed  = 200
    self.VJ_IsBeingCrouched = false

    self.BloodColor = BLOOD_COLOR_RED
    self:SetupBloodColor(self.BloodColor)

    self:SetHealth(3500)
    self:SetMaxHealth(3500)
    self:SetCollisionBounds(
        Vector(-64, -64, 0),
        Vector( 64,  64, 200)
    )

    self._gekkoDead               = false
    self._gekkoLastPos             = self:GetPos()
    self._gekkoLastTime            = CurTime()
    self._mgBurstActive            = false
    self._mgBurstEndT              = 0
    self._mgRoundsLeft             = 0
    self._bushmasterActive         = false
    self._bushmasterEndT           = 0
    self._lastWeapon               = ""
    self._gekkoRunning             = false
    self._gekkoSprinting           = false
    self._gekkoSprintEndT          = 0
    self._gekkoSprintCooldownT     = 0
    self._gekkoSuppressActivity   = 0
    self._gekkoLastEnemyDist       = 0
    self._bloodSplatPulse         = 0

    self:SetNWBool("GekkoMGFiring",   false)
    self:SetNWBool("GekkoSprinting",  false)
    self:SetNWBool("GekkoIsCrouching", false)

    self:GeckoCrouch_Init()
    self:GekkoGib_Init()
    self:GekkoLegs_Init()
    self:GekkoDeathPose_Init()
    self:GekkoElastic_Init()
    self:GekkoAPS_Init()

    -- ── Pedestal dodge / random strafe initialisation ────────────────
    self:PedestalDodge_Init()

    timer.Simple(0, function()
        if not IsValid(self) then return end
        local selfRef = self
        selfRef:GekkoUpdateSeqCache()
        selfRef:GeckoCrouch_CacheSeqs()
        selfRef:GekkoJump_CacheSeqs()
        selfRef:GekkoTargetedJump_CacheSeqs()
        net.Start("GekkoFK360LandDust")
            net.WriteEntity(selfRef)
            net.WriteInt(selfRef.GekkoSeq_Walk or -1, 16)
            net.WriteInt(selfRef.GekkoSeq_Run or -1,  16)
            net.WriteInt(selfRef.GekkoSeq_Idle or -1, 16)
            net.WriteInt(selfRef.GekkoSeq_CrouchWalk or -1, 16)
            net.WriteInt(selfRef.GekkoSeq_CrouchIdle or -1, 16)
        net.Broadcast()
    end)

    ScheduleNextAttack(self)
    ScheduleReload(self)
end

-- ============================================================
-- OnTakeDamage: INTEGRATED WITH JUICY BLEEDING + HIT REACT
--               + PEDESTAL DODGE (reactive sideways slide)
-- ============================================================

local FLINCH_DAMAGE_THRESHOLD = 35
local FLINCH_DAMAGE_CAP = 250
local FLINCH_CHANCE = 0.40
local FLINCH_FORCE_BASE = 30
local FLINCH_FORCE_PER_DMG = 0.22
local HEAD_SHOT_MULTIPLIER = 0.33

function ENT:OnTakeDamage(dmginfo)
    if self._gekkoDead then
        dmginfo:SetDamage(0)
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

    GekkoApplyHitImpulse(self, hitDir, rawDmg)

    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)

    -- ── Reactive pedestal dodge (nullifies damage on successful dodge) ──
    -- Blood, explosion decals and JuicyBleed are intentionally placed AFTER
    -- this check so that a successful dodge suppresses ALL visual hit feedback.
    if self:PedestalDodge_OnHit(dmginfo) then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        return  -- ← early-out: no blood, no decal, no juicy bleed
    end
    -- ───────────────────────────────────────────────────────────────────

    -- Blood and impact effects only reach here when the dodge did NOT fire.
    GekkoVanillaBleed(self, hitPos, hitDir)
    if dmginfo:IsBulletDamage() then
        GekkoSignalBloodHit(self, hitPos, hitDir)
    end

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

    GekkoSprint_Think(self)
    self:GekkoAPS_Think()

    -- ── Pedestal dodge: random strafe tick + slide advancement ──────
    self:PedestalDodge_ThinkStrafe()

    self:GekkoUpdateAnimation()

    if GetConVar("developer") and GetConVar("developer"):GetInt() >= 1 then
        local now = CurTime()
        if not self._dbgNextT or now > self._dbgNextT then
            self._dbgNextT = now + 1
            local vel    = self:GetVelocity():Length2D()
            local seq    = self:GetSequence()
            local seqName = self:GetSequenceName(seq) or "?"
            local run    = tostring(self._gekkoRunning)
            local sprint = tostring(self._gekkoSprinting)
            local dist   = self._gekkoLastEnemyDist or 0
            local distS  = dist < 1000 and "CLOSE" or dist < 2000 and "MED" or "FAR"
            local speed  = self:GetNWFloat("GekkoSpeed", 0)
            local jump   = self:GetNWInt("GekkoJumpState", 0)
            local dead   = tostring(self._gekkoDead)
            print(string.format(
                "[GekkoDBG] vel=%.1f seq=%s run=%s sprint=%s dist=%d(%s) spd=%d jump=%s crouch=%s mgActive=%s lastWpn=%s dead=%s",
                vel, seqName, run, sprint, dist, distS, speed, jump,
                tostring(self._gekkoCrouching), tostring(self._mgBurstActive),
                tostring(self._lastWeapon), dead
            ))
        end
    end
end

-- ============================================================
-- DEATH
-- ============================================================
function ENT:OnDeath(dmginfo)
    self._gekkoDead = true
    if self._gekkoSprinting then GekkoSprint_End(self) end
    self:SetNWBool("GekkoMGFiring", false)
    self:SetNWBool("GekkoSprinting", false)
    self:SetNWBool("GekkoIsCrouching", false)
    self:GekkoDeathPose_OnDeath()
    self:GekkoElastic_OnDeath()
end

function ENT:OnRemove()
    if self._gekkoSprinting then GekkoSprint_End(self) end
    self:GekkoElastic_OnRemove()
end
