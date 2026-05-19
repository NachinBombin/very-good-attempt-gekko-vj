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
local BM_TRAIL_MATERIAL = "trails/smoke"
local BM_TRAIL_LIFETIME = 1.55
local BM_TRAIL_STARTSIZE = 7
local BM_TRAIL_ENDSIZE = 0.5
local BM_TRAIL_COLOR = Color(235, 235, 235, 90)
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
    util.Effect("GekkoBloodHit", ed, true, true)
end

-- ============================================================
-- PHYSICS / IMPULSE HELPER
-- ============================================================
local IMPULSE_SCALE = 1.8
local IMPULSE_CAP   = 12000

local function GekkoApplyHitImpulse(ent, hitDir, rawDmg)
    local mag = math.min(rawDmg * IMPULSE_SCALE, IMPULSE_CAP)
    local force = hitDir * mag
    ent:SetVelocity(force)
end

-- ============================================================
-- VANILLA BLEED (decals)
-- ============================================================
local function GekkoVanillaBleed(ent, hitPos, hitDir)
    local tr = util.TraceLine({
        start  = hitPos - hitDir * 4,
        endpos = hitPos + hitDir * 32,
        filter = ent,
    })
    if tr.Hit then
        local decalName = "Blood"
        util.Decal(decalName, tr.HitPos - hitDir * 4, tr.HitPos + hitDir * 4)
    end
end

-- ============================================================
-- MUZZLE FLASH NET (sent to all clients)
-- ============================================================
local function SendMuzzleFlash(pos, dir, attachIdx)
    net.Start("GekkoMuzzleFlash")
        net.WriteVector(pos)
        net.WriteVector(dir)
        net.WriteUInt(attachIdx, 4)
    net.Broadcast()
end

-- ============================================================
-- BULLET IMPACT NET
-- ============================================================
local function SendBulletImpact(hitPos, hitNormal, hitEnt)
    net.Start("GekkoBulletImpact")
        net.WriteVector(hitPos)
        net.WriteVector(hitNormal)
        net.WriteEntity(hitEnt)
    net.Broadcast()
end

-- ============================================================
-- SHELL CASING SPAWN
-- ============================================================
local function SpawnCartridge(src, ang, scale)
    if not SERVER then return end
    local right   = ang:Right()
    local up      = ang:Up()
    local forward = ang:Forward()
    local spawnPos = src
        + right   * SHELL_RIGHT_OFFSET
        + up      * SHELL_UP_OFFSET
        + forward * SHELL_FWD_OFFSET
    local shell = ents.Create("prop_physics")
    if not IsValid(shell) then return end
    shell:SetModel(SHELL_MODEL)
    shell:SetPos(spawnPos)
    shell:SetAngles(ang)
    shell:SetModelScale(scale)
    shell:Spawn()
    shell:Activate()
    local phys = shell:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(SHELL_MASS)
        local vel =
            right   * math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX)
          + up      * math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX)
          + forward * math.Rand(SHELL_VEL_FWD_MIN,   SHELL_VEL_FWD_MAX)
        phys:SetVelocity(vel)
        local av = Angle(
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX)
        )
        phys:SetAngleVelocity(av)
    end
    timer.Simple(SHELL_LIFETIME, function()
        if IsValid(shell) then shell:Remove() end
    end)
end

-- ============================================================
-- SAFE GetActiveEnemy (no VJ dependency crash)
-- ============================================================
local function GetActiveEnemy(ent)
    if not IsValid(ent) then return NULL end
    if IsValid(ent.VJ_TheEnemy) then return ent.VJ_TheEnemy end
    local enemy = ent:GetEnemy()
    return IsValid(enemy) and enemy or NULL
end

-- ============================================================
-- SPRINT SYSTEM
-- ============================================================
local function GekkoSprint_Think(ent)
    if not ent._gekkoSprinting then return end
    if CurTime() > ent._gekkoSprintEndT then
        ent._gekkoSprinting = false
        ent.MoveSpeed  = ent._preSprint_MoveSpeed  or ent.MoveSpeed
        ent.RunSpeed   = ent._preSprint_RunSpeed   or ent.RunSpeed
        ent.WalkSpeed  = ent._preSprint_WalkSpeed  or ent.WalkSpeed
    end
end

local function GekkoMaybeSprint(ent, enemy)
    if not IsValid(enemy) then return end
    if ent._gekkoSprinting then return end
    if CurTime() < ent._gekkoSprintNextT then return end
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist > SPRINT_ENGAGE_DIST then return end
    ent._preSprint_MoveSpeed = ent.MoveSpeed
    ent._preSprint_RunSpeed  = ent.RunSpeed
    ent._preSprint_WalkSpeed = ent.WalkSpeed
    ent.MoveSpeed  = SPRINT_MOVE_SPEED
    ent.RunSpeed   = SPRINT_RUN_SPEED
    ent.WalkSpeed  = SPRINT_WALK_SPEED
    ent._gekkoSprinting   = true
    ent._gekkoSprintEndT  = CurTime() + math.Rand(SPRINT_DUR_MIN, SPRINT_DUR_MAX)
    ent._gekkoSprintNextT = ent._gekkoSprintEndT
        + math.Rand(SPRINT_COOLDOWN_MIN, SPRINT_COOLDOWN_MAX)
end

-- ============================================================
-- ANIMATION SYSTEM
-- ============================================================
local SEQ_IDLE = "idle"
local SEQ_WALK = "walk_all"
local SEQ_RUN  = "run_all"

local function GekkoUpdateAnimation(self)
    local vel  = self:GetVelocity():Length()
    self:SetNWFloat("GekkoSpeed", vel)
    local enemy = GetActiveEnemy(self)
    if IsValid(enemy) then
        local dist = self:GetPos():Distance(enemy:GetPos())
        self._gekkoLastEnemyDist = dist
        if dist > RUN_ENGAGE_DIST and not self._gekkoRunning then
            self._gekkoRunning = true
        elseif dist < RUN_DISENGAGE_DIST and self._gekkoRunning then
            self._gekkoRunning = false
        end
        GekkoMaybeSprint(self, enemy)
    end
    if vel < 5 then
        if self.Gekko_LastSeqName ~= SEQ_IDLE then
            self:ResetSequence(SEQ_IDLE)
            self:SetPlaybackRate(1)
            self.Gekko_LastSeqName = SEQ_IDLE
        end
        return
    end
    local targetSeq, targetSpeed
    if self._gekkoRunning or self._gekkoSprinting then
        targetSeq   = SEQ_RUN
        targetSpeed = ANIM_RUN_SPEED
    else
        targetSeq   = SEQ_WALK
        targetSpeed = ANIM_WALK_SPEED
    end
    local arate = math.Clamp(vel / targetSpeed, 0.4, 3.0)
    if self.Gekko_LastSeqName ~= targetSeq then
        self:ResetSequence(targetSeq)
        self.Gekko_LastSeqName = targetSeq
    end
    self:SetPlaybackRate(arate)
end

-- Expose for external access
ENT.GekkoUpdateAnimation = GekkoUpdateAnimation

-- ============================================================
-- HIT REACT POSITION RESOLVER
-- ============================================================
local function GekkoResolveHitPos(self, dmginfo)
    local dmgPos   = dmginfo:GetDamagePosition()
    local attacker = dmginfo:GetAttacker()
    local inflictor = dmginfo:GetInflictor()
    local bodyCenter = self:GetPos() + Vector(0, 0, 60)

    if dmgPos:LengthSqr() > 0 then
        local _, maxs = self:GetCollisionBounds()
        local ht = maxs.z
        local z  = dmgPos.z - self:GetPos().z
        if z >= 0 and z <= ht * 1.1 then
            return dmgPos, "dmgpos"
        end
    end

    if IsValid(inflictor) and inflictor ~= self and inflictor ~= attacker then
        local inflPos = inflictor:GetPos()
        local _, maxs = self:GetCollisionBounds()
        local z = inflPos.z - self:GetPos().z
        if z >= 0 and z <= maxs.z * 1.1 then
            return inflPos, "inflictor_pos"
        end
    end

    if IsValid(attacker) then
        local atkPos   = attacker:GetPos()
        local atkDir   = (self:GetPos() - atkPos):GetNormalized()
        local tr = util.TraceLine({
            start  = atkPos,
            endpos = self:GetPos() + atkDir * 200,
            filter = attacker,
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            return tr.HitPos, "trace_inflictor"
        end
        return bodyCenter, "bodycenter_inflictor"
    end

    return bodyCenter, "bodycenter_fallback"
end

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
    GekkoSprint_Think(self)
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
            tostring(self._gekkoCrouching or false),
            tostring(self._mgBurstActive or false),
            tostring(self._lastWeaponChoice or "none"),
            tostring(self._gekkoDead)
        ))
        self.Gekko_NextDebugT = CurTime() + 3
    end
end

-- ============================================================
-- RANGE ATTACK OVERRIDE  (VJBase calls this)
-- ============================================================
function ENT:CustomRangeAttack(data)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return false end

    local dist = self:GetPos():Distance(enemy:GetPos())
    self._gekkoLastEnemyDist = dist

    local choice = self:GekkoSelectWeapon(enemy, dist)
    self._lastWeaponChoice = choice
    print(string.format("[GekkoWpn] Selected: %s | dist=%.0f", choice, dist))

    if     choice == "MG"          then return self:FireMachineGun(enemy)
    elseif choice == "MISSILE_SINGLE" then return self:FireMissile(enemy, false)
    elseif choice == "MISSILE_DOUBLE" then return self:FireMissile(enemy, true)
    elseif choice == "GRENADE"     then return self:FireGrenadeLauncher(enemy)
    elseif choice == "TOPMISSILE"  then return self:FireTopMissile(enemy)
    elseif choice == "TRACKMISSILE" then return self:FireTrackMissile(enemy)
    elseif choice == "ORBITRPG"    then return self:FireOrbitRPG(enemy)
    elseif choice == "NIKITA"      then return self:FireNikita(enemy)
    elseif choice == "BRUSHMASTER" then return FireBushmaster(self, enemy)
    elseif choice == "ELASTIC"     then return self:FireElastic(enemy)
    end
    return false
end

-- ============================================================
-- WEAPON SELECTION
-- ============================================================
function ENT:GekkoSelectWeapon(enemy, dist)
    -- Elastic: short range only
    if dist <= 900 then
        local r = math.random(1, 3)
        if r == 1 then return "ELASTIC" end
    end

    -- Build weighted table
    local weights = {
        { choice = "MG",              w = WWEIGHT_MG },
        { choice = "MISSILE_SINGLE",  w = WWEIGHT_MISSILE_SINGLE },
        { choice = "MISSILE_DOUBLE",  w = WWEIGHT_MISSILE_DOUBLE },
        { choice = "GRENADE",         w = WWEIGHT_GRENADE },
        { choice = "TOPMISSILE",      w = WWEIGHT_TOPMISSILE },
        { choice = "TRACKMISSILE",    w = WWEIGHT_TRACKMISSILE },
        { choice = "ORBITRPG",        w = WWEIGHT_ORBITRPG },
        { choice = "NIKITA",          w = WWEIGHT_NIKITA },
        { choice = "BRUSHMASTER",     w = WWEIGHT_BUSHMASTER },
        { choice = "ELASTIC",         w = 0 },  -- handled above
    }

    -- Exclude weapons that need min distance
    if dist < MISSILE_MIN_DIST then
        for _, e in ipairs(weights) do
            if e.choice == "TOPMISSILE" or e.choice == "TRACKMISSILE"
            or e.choice == "NIKITA" or e.choice == "MISSILE_SINGLE"
            or e.choice == "MISSILE_DOUBLE" then
                e.w = 0
            end
        end
    end

    local total = 0
    for _, e in ipairs(weights) do total = total + e.w end
    local roll  = math.random() * total
    local accum = 0
    for _, e in ipairs(weights) do
        accum = accum + e.w
        if roll <= accum then return e.choice end
    end
    return "MG"
end

-- ============================================================
-- MACHINE GUN
-- ============================================================
function ENT:FireMachineGun(enemy)
    local rounds   = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local spread   = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
    local shotCount = 0
    self._mgBurstActive = true
    self._mgBurstEndT   = CurTime() + rounds * MG_INTERVAL + 0.2
    self:SetNWBool("GekkoMGFiring", true)
    for i = 0, rounds - 1 do
        local shot = i
        timer.Simple(shot * MG_INTERVAL, function()
            if not IsValid(self) then return end
            local curEnemy = GetActiveEnemy(self)
            if not IsValid(curEnemy) then return end
            local src = self:GetAttachmentPos(ATT_MACHINEGUN)
                or (self:GetPos() + Vector(0, 0, 60))
            local aimPos = curEnemy:GetPos() + Vector(0, 0, 40)
            local dir    = (aimPos - src):GetNormalized()
            local bdata = {}
            bdata.Src       = src
            bdata.Dir       = dir
            bdata.Spread    = Vector(spread, spread, 0)
            bdata.Damage    = MG_DAMAGE
            bdata.Force     = 2
            bdata.AmmoType  = "Pistol"
            bdata.AttackerID = self:EntIndex()
            self:FireBullets(bdata)
            shotCount = shotCount + 1
            if shotCount % MG_FLASH_EVERY == 0 then
                local eff = EffectData()
                eff:SetOrigin(src); eff:SetNormal(dir)
                util.Effect("MuzzleFlash", eff)
                SendMuzzleFlash(src, dir, ATT_MACHINEGUN)
            end
            if shotCount % MG_CHAIN_EVERY == 0 then
                self:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, 100, 1)
            end
            self:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)],
                MG_SND_LEVEL, math.random(95, 110), 1)
            SpawnCartridge(src, self:GetAngles(), MG_SHELL_SCALE)
        end)
    end
    print(string.format("[GekkoMG] Burst | rounds=%d spread=%.2f", rounds, spread))
    return true
end

-- ============================================================
-- MISSILES
-- ============================================================
function ENT:FireMissile(enemy, double)
    local aimPos  = enemy:GetPos() + Vector(0, 0, 40)
    local attIdx  = double and {ATT_MISSILE_L, ATT_MISSILE_R} or {ATT_MISSILE_L}
    local function LaunchOne(att)
        local src = self:GetAttachmentPos(att) or (self:GetPos() + Vector(0, 0, 80))
        local dir = (aimPos - src):GetNormalized()
        local rocket = ents.Create("obj_vj_rocket")
        if not IsValid(rocket) then return end
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(self)
        rocket:Spawn()
        rocket:Activate()
        self:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)],
            ROCKET_SND_LEVEL, math.random(95, 110), 1)
        local eff = EffectData()
        eff:SetOrigin(src); eff:SetNormal(dir)
        util.Effect("MuzzleFlash", eff)
        SendMuzzleFlash(src, dir, att)
    end
    if double then
        LaunchOne(ATT_MISSILE_L)
        timer.Simple(SALVO_DELAY, function()
            if not IsValid(self) then return end
            LaunchOne(ATT_MISSILE_R)
        end)
        print("[GekkoMissile] Double salvo")
    else
        LaunchOne(ATT_MISSILE_L)
        print("[GekkoMissile] Single")
    end
    return true
end

-- ============================================================
-- GRENADE LAUNCHER
-- ============================================================
function ENT:FireGrenadeLauncher(enemy)
    local count   = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    local aimBase = enemy:GetPos()
    self:EmitSound(GL_SOUND_FIDGET, 95, 100, 1)
    timer.Simple(GL_FIDGET_LEAD, function()
        if not IsValid(self) then return end
        self:EmitSound(GL_SOUND_INSERT, 90, 100, 1)
    end)
    for i = 0, count - 1 do
        local shot = i
        timer.Simple(GL_FIDGET_LEAD + shot * GL_INTERVAL, function()
            if not IsValid(self) then return end
            local attIdx = GL_SPARK_ATT_CYCLE[(shot % #GL_SPARK_ATT_CYCLE) + 1]
            local src = self:GetAttachmentPos(attIdx)
                or (self:GetPos() + Vector(0, 0, GL_LAUNCH_Z))
            local spread = Vector(
                math.Rand(-GL_SPREAD_Y, GL_SPREAD_Y),
                math.Rand(-GL_SPREAD_Y, GL_SPREAD_Y),
                0
            )
            local aim = aimBase + spread
            local grenadeName = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
            local params = GL_TYPE_PARAMS[grenadeName] or GL_TYPE_DEFAULT
            local flat = (aim - src); flat.z = 0
            local hDist = flat:Length()
            local loft  = hDist * params.loft
            local dir = (aim + Vector(0, 0, loft) - src):GetNormalized()
            local gren = ents.Create(grenadeName)
            if not IsValid(gren) then
                gren = ents.Create("bombin_gas_grenade")
            end
            if not IsValid(gren) then return end
            gren:SetPos(src)
            gren:SetAngles(dir:Angle())
            gren:SetOwner(self)
            gren:Spawn()
            gren:Activate()
            gren:SetVelocity(dir * params.speed)
            -- Trail
            local trail = ents.Create("env_spritetrail")
            if IsValid(trail) then
                trail:SetPos(src)
                trail:SetParent(gren)
                trail:SetKeyValue("spritename", GL_TRAIL_MATERIAL)
                trail:SetKeyValue("lifetime",   tostring(GL_TRAIL_LIFETIME))
                trail:SetKeyValue("startwidth", tostring(GL_TRAIL_STARTSIZE))
                trail:SetKeyValue("endwidth",   tostring(GL_TRAIL_ENDSIZE))
                trail:SetKeyValue("colorr", "235")
                trail:SetKeyValue("colorg", "235")
                trail:SetKeyValue("colorb", "235")
                trail:SetKeyValue("alpha",  "200")
                trail:Spawn()
                trail:Activate()
            end
            self:EmitSound(GL_SOUND_FIRE, 95, math.random(95, 110), 1)
            -- Smoke / vapor FX
            local efd = EffectData()
            efd:SetOrigin(src); efd:SetNormal(dir)
            efd:SetScale(GL_VAPOR_SCALE)
            util.Effect(GL_VAPOR_EFFECT, efd)
            if shot % GL_SMOKE_EVERY == 0 then
                local efd2 = EffectData()
                efd2:SetOrigin(src + dir * 30)
                efd2:SetScale(GL_SMOKE_SCALE)
                util.Effect(GL_SMOKE_EFFECT, efd2)
            end
            -- Spark
            local efd3 = EffectData()
            efd3:SetOrigin(src); efd3:SetNormal(dir)
            efd3:SetScale(GL_SPARK_SCALE)
            efd3:SetMagnitude(GL_SPARK_MAGNITUDE)
            efd3:SetRadius(GL_SPARK_RADIUS)
            util.Effect("MetalSpark", efd3)
        end)
    end
    print(string.format("[GekkoGL] Barrage | count=%d", count))
    return true
end

-- ============================================================
-- TOP-ATTACK MISSILE
-- ============================================================
function ENT:FireTopMissile(enemy)
    local src = self:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local missile = ents.Create("sent_npc_topmissile")
    if not IsValid(missile) then
        print("[GekkoTopMissile] FAILED: sent_npc_topmissile not found")
        return false
    end
    missile:SetPos(src)
    missile:SetAngles(Angle(0, self:GetAngles().y, 0))
    missile:SetOwner(self)
    missile:Spawn()
    missile:Activate()
    if missile.SetTarget then missile:SetTarget(enemy) end
    self:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)],
        TOPMISSILE_SND_LEVEL, 100, 1)
    self:EmitSound(MISSILE_SOUND_WARN, 90, 100, 1)
    print(string.format("[GekkoTopMissile] Launched"))
    return true
end

-- ============================================================
-- TRACK MISSILE
-- ============================================================
function ENT:FireTrackMissile(enemy)
    local src = self:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local missile = ents.Create("sent_npc_trackmissile")
    if not IsValid(missile) then
        print("[GekkoTrackMissile] FAILED: sent_npc_trackmissile not found")
        return false
    end
    missile:SetPos(src)
    missile:SetAngles(Angle(0, self:GetAngles().y, 0))
    missile:SetOwner(self)
    missile:Spawn()
    missile:Activate()
    if missile.SetTarget then missile:SetTarget(enemy) end
    self:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)],
        TOPMISSILE_SND_LEVEL, 100, 1)
    print(string.format("[GekkoTrackMissile] Launched"))
    return true
end

-- ============================================================
-- ORBIT RPG
-- ============================================================
function ENT:FireOrbitRPG(enemy)
    local src  = self:GetPos() + Vector(0, 0, 100)
    local aim  = enemy:GetPos() + Vector(0, 0, 40)
    local dir  = (aim - src):GetNormalized()
    local rpg  = ents.Create("sent_orbital_rpg")
    if not IsValid(rpg) then
        print("[GekkoOrbitRPG] FAILED: sent_orbital_rpg not found")
        return false
    end
    rpg:SetPos(src)
    rpg:SetAngles(dir:Angle())
    rpg:SetOwner(self)
    rpg:Spawn()
    rpg:Activate()
    self:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)],
        ROCKET_SND_LEVEL, math.random(95, 110), 1)
    print("[GekkoOrbitRPG] Fired")
    return true
end

-- ============================================================
-- NIKITA CRUISE MISSILE
-- ============================================================
function ENT:FireNikita(enemy)
    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist < NIKITA_MIN_DIST then
        print(string.format("[GekkoNikita] Aborted (dist=%.0f < %d)", dist, NIKITA_MIN_DIST))
        return false
    end
    local fwd = self:GetForward()
    local src = self:GetPos()
        + fwd   * NIKITA_SPAWN_FORWARD
        + Vector(0, 0, NIKITA_SPAWN_Z)
    local dir = (enemy:GetPos() - src):GetNormalized()
    -- Muzzle smoke burst
    for i = 1, NIKITA_MUZZLE_SMOKE_COUNT do
        timer.Simple((i-1) * NIKITA_MUZZLE_SMOKE_STAGGER, function()
            if not IsValid(self) then return end
            local efd = EffectData()
            efd:SetOrigin(src + dir * (i * 15))
            efd:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
            util.Effect("SmokeEffect", efd)
        end)
    end
    local nikita = ents.Create("npc_vj_gekko_nikita")
    if not IsValid(nikita) then
        print("[GekkoNikita] FAILED: npc_vj_gekko_nikita not found")
        return false
    end
    nikita:SetPos(src)
    nikita:SetAngles(dir:Angle())
    nikita:SetOwner(self)
    nikita:Spawn()
    nikita:Activate()
    if nikita.SetEnemy then
        nikita:SetEnemy(enemy)
    end
    print(string.format("[GekkoNikita] Launched | dist=%.0f", dist))
    return true
end

local function FireBushmaster(ent, enemy)
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local rounds = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)
    for i = 0, rounds - 1 do
        local shot = i
        timer.Simple(shot * BM_INTERVAL, function()
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
            local curAim   = IsValid(curEnemy) and (curEnemy:GetPos() + Vector(0, 0, 40)) or aimPos
            local dir      = (curAim - src):GetNormalized()
            local shell = ents.Create("sent_gekko_bushmaster")
            if IsValid(shell) then
                shell:SetPos(src); shell:SetAngles(dir:Angle())
                shell:SetOwner(ent); shell:Spawn(); shell:Activate()
                AttachBushmasterTrail(shell)
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
    print(string.format("[GekkoBM] Salvo | rounds=%d interval=%.2fs", rounds, BM_INTERVAL))
    return true
end

local function FireElastic(ent, enemy)
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if dist > 900 then
        print(string.format("[GekkoElastic] Re-rolling (dist=%.0f > 900)", dist))
        local alt
        local triesLeft = 8
        repeat
            alt = ent:GekkoSelectWeapon(enemy, dist)
            triesLeft = triesLeft - 1
        until alt ~= "ELASTIC" or triesLeft <= 0
        if alt and alt ~= "ELASTIC" then
            ent._lastWeaponChoice = alt
            if     alt == "MG"               then return ent:FireMachineGun(enemy)
            elseif alt == "MISSILE_SINGLE"   then return ent:FireMissile(enemy, false)
            elseif alt == "MISSILE_DOUBLE"   then return ent:FireMissile(enemy, true)
            elseif alt == "GRENADE"          then return ent:FireGrenadeLauncher(enemy)
            elseif alt == "TOPMISSILE"       then return ent:FireTopMissile(enemy)
            elseif alt == "TRACKMISSILE"     then return ent:FireTrackMissile(enemy)
            elseif alt == "ORBITRPG"         then return ent:FireOrbitRPG(enemy)
            elseif alt == "NIKITA"           then return ent:FireNikita(enemy)
            elseif alt == "BRUSHMASTER"      then return FireBushmaster(ent, enemy)
            end
        end
        return false
    end
    return ent:GekkoElastic_Fire(enemy)
end

-- ============================================================
-- VJBase RANGE ATTACK (hook)
-- ============================================================
function ENT:VJ_OnShoot()
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    local dist   = self:GetPos():Distance(enemy:GetPos())
    local choice = self:GekkoSelectWeapon(enemy, dist)
    self._lastWeaponChoice = choice
    print(string.format("[GekkoWpn-VJ] Selected: %s | dist=%.0f", choice, dist))
    if     choice == "MG"               then self:FireMachineGun(enemy)
    elseif choice == "MISSILE_SINGLE"   then self:FireMissile(enemy, false)
    elseif choice == "MISSILE_DOUBLE"   then self:FireMissile(enemy, true)
    elseif choice == "GRENADE"          then self:FireGrenadeLauncher(enemy)
    elseif choice == "TOPMISSILE"       then self:FireTopMissile(enemy)
    elseif choice == "TRACKMISSILE"     then self:FireTrackMissile(enemy)
    elseif choice == "ORBITRPG"         then self:FireOrbitRPG(enemy)
    elseif choice == "NIKITA"           then self:FireNikita(enemy)
    elseif alt == "BRUSHMASTER"         then FireBushmaster(self, enemy)
    elseif choice == "ELASTIC"          then FireElastic(self, enemy)
    end
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:Initialize()
    self:SetModel(self.Model[1])
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_IDLE)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(CAP_MOVE_GROUND | CAP_TURN_HEAD | CAP_OPEN_DOORS
        | CAP_WEAPON_RANGE_ATTACK1)
    self:SetMaxHealth(self.StartHealth)
    self:SetHealth(self.StartHealth)
    self:SetBloodColor(BLOOD_COLOR_RED)
    self:SetUseType(SIMPLE_USE)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)

    self:SetKeyValue("gag", "1")

    self._bloodSplatPulse         = 0
    self._hitReactPulse           = 0
    self._gibCooldownT            = 0
    self._lastWeaponChoice        = ""
    self._glSparkCounter          = 0
    self._gekkoDead               = false
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

    -- Cache bone indices
    self.GekkoPelvisBone = self:LookupBone("b_pelvis")     or -1
    self.GekkoSpineBone  = self:LookupBone("b_spine4")    or -1

    self:GekkoLegs_Init()
    self:GekkoJump_Init()
    self:GekkoTargetJump_Init()
    self:GeckoCrush_Init()
    self:GekkoGib_Init()

    self.Gekko_LastSeqName  = ""
    self.Gekko_NextDebugT   = CurTime() + 3

    -- Re-cache bones after a brief delay (model may not be fully loaded)
    timer.Simple(0.1, function()
        if not IsValid(self) then return end
        local selfRef = self
        selfRef.GekkoPelvisBone = selfRef:LookupBone("b_pelvis")  or -1
        selfRef.GekkoSpineBone  = selfRef:LookupBone("b_spine4")    or -1
        print(string.format(
            "[GekkoInit] PelvisBone=%d SpineBone=%d",
            selfRef.GekkoPelvisBone, selfRef.GekkoSpineBone
        ))
    end)

    print("[GekkoInit] Spawned ent #" .. self:EntIndex())
end

-- ============================================================
-- DEATH
-- ============================================================
function ENT:OnDeath(dmginfo)
    self._gekkoDead = true
    self:SetNWBool("GekkoMGFiring", false)
    self:GekkoDeathPose_Apply()
end

-- ============================================================
-- SAFE TABLE INIT (avoids VJBase nil crash on
-- AnimationTranslations / SoundTbl_* not being tables)
-- ============================================================
function SafeInitVJTables(ent)
    if type(ent.AnimationTranslations) ~= "table" then
        ent.AnimationTranslations = {}
    end
    local soundTbls = {
        "SoundTbl_Death", "SoundTbl_Alert", "SoundTbl_Pain",
        "SoundTbl_Idle",  "SoundTbl_LostEnemy"
    }
    for _, name in ipairs(soundTbls) do
        if type(ent[name]) ~= "table" then ent[name] = {} end
    end
end

-- ============================================================
-- ATTACHMENT HELPER
-- ============================================================
function ENT:GetAttachmentPos(attIdx)
    local att = self:GetAttachment(attIdx)
    return att and att.Pos or nil
end

-- ============================================================
-- BUSHMASTER VISUAL HELPERS  (called inside FireBushmaster)
-- ============================================================
local function AttachBushmasterTrail(shell)
    local trail = ents.Create("env_spritetrail")
    if not IsValid(trail) then return end
    trail:SetParent(shell)
    trail:SetKeyValue("spritename",  BM_TRAIL_MATERIAL)
    trail:SetKeyValue("lifetime",    tostring(BM_TRAIL_LIFETIME))
    trail:SetKeyValue("startwidth",  tostring(BM_TRAIL_STARTSIZE))
    trail:SetKeyValue("endwidth",    tostring(BM_TRAIL_ENDSIZE))
    trail:SetKeyValue("colorr", "235")
    trail:SetKeyValue("colorg", "235")
    trail:SetKeyValue("colorb", "235")
    trail:SetKeyValue("alpha",  "90")
    trail:Spawn()
    trail:Activate()
end

local function BushmasterSparks(pos, dir, ent)
    local efd = EffectData()
    efd:SetOrigin(pos); efd:SetNormal(dir)
    efd:SetScale(BM_SPARK_SCALE)
    efd:SetMagnitude(BM_SPARK_MAGNITUDE)
    efd:SetRadius(BM_SPARK_RADIUS)
    util.Effect("MetalSpark", efd)
end

local function BushmasterSmoke(pos, dir)
    local efd = EffectData()
    efd:SetOrigin(pos + dir * BM_SMOKE_FORWARD + Vector(0, 0, BM_SMOKE_UP))
    efd:SetScale(BM_SMOKE_SCALE)
    util.Effect("SmokeEffect", efd)
end
