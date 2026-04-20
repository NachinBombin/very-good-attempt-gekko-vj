-- ============================================================
--  npc_vj_gekko / init.lua
--  Weapon list:
--  1. Machine-gun burst         (FireBullets)
--  2. Single accurate missile   (obj_vj_rocket)
--  3. Double inaccurate salvo   (obj_vj_rocket x2)
--  4. Grenade launcher barrage  (bombin_gas_grenade / stun / flash)
--  5. Top-attack terror missile (sent_npc_topmissile)
--  6. Active-track missile      (sent_npc_trackmissile)
--  7. Orbit RPG                 (sent_orbital_rpg)
--  8. Nikita cruise missile     (npc_vj_gekko_nikita)
--  9. Bushmaster 25mm cannon    (sent_gekko_bushmaster x7-13)
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("muzzleflash_system.lua")
AddCSLuaFile("bullet_impact_system.lua")
AddCSLuaFile("death_pose_system.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")
include("death_pose_system.lua")

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")
util.AddNetworkString("GekkoMuzzleFlash")
util.AddNetworkString("GekkoBulletImpact")

local ATT_MACHINEGUN = 3
local ATT_MISSILE_L  = 9
local ATT_MISSILE_R  = 10

local ANIM_WALK_SPEED    = 184
local ANIM_RUN_SPEED     = 20
local RUN_ENGAGE_DIST    = 2300
local RUN_DISENGAGE_DIST = 1600
local RATE_SMOOTH_SPEED  = 8.0

local MG_ROUNDS_MIN = 11
local MG_ROUNDS_MAX = 36
local MG_INTERVAL   = 0.15
local MG_DAMAGE     = 25
local MG_SPREAD_MIN = 0.06
local MG_SPREAD_MAX = 0.6

local MG_SND_SHOTS       = { "gekko/shot.wav", "gekko/shot2.wav" }
local MG_SND_CHAININSERT = "gekko/chaininsert.wav"
local MG_CHAIN_EVERY     = 6
local MG_SND_LEVEL       = 100
local MG_FLASH_EVERY     = 2

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
local TOPMISSILE_SND_LEVEL =  100

local BM_ROUNDS_MIN   = 7
local BM_ROUNDS_MAX   = 9
local BM_INTERVAL     = 0.38
local BM_SND_SHOOT    = "gekko/brushmaster_25mm/20mm_shoot.wav"
local BM_SND_RELOAD   = "gekko/brushmaster_25mm/20mm_reload.wav"
local BM_SND_LEVEL    = 100
local BM_MUZZLE_SCALE = 9.5
local BM_MUZZLE_Z_OFFSET = 200
local BM_TRAIL_MATERIAL  = "trails/smoke"
local BM_TRAIL_LIFETIME  = 1.55
local BM_TRAIL_STARTSIZE = 7
local BM_TRAIL_ENDSIZE   = 0.5
local BM_TRAIL_COLOR     = Color(235, 235, 235, 90)
local BM_SPARK_SCALE     = 0.32
local BM_SPARK_MAGNITUDE = 2.2
local BM_SPARK_RADIUS    = 6
local BM_SMOKE_SCALE     = 0.9
local BM_SMOKE_FORWARD   = 12
local BM_SMOKE_UP        = 2

local SHELL_MODEL         = "models/props_debris/shellcasing_09.mdl"
local SHELL_LIFETIME      = 5
local MG_SHELL_SCALE      = 0.5
local BM_SHELL_SCALE      = 1.0
local SHELL_RIGHT_OFFSET  = 10
local SHELL_UP_OFFSET     = 4
local SHELL_FWD_OFFSET    = -2
local SHELL_VEL_RIGHT_MIN = 120
local SHELL_VEL_RIGHT_MAX = 220
local SHELL_VEL_UP_MIN    = 40
local SHELL_VEL_UP_MAX    = 90
local SHELL_VEL_FWD_MIN   = -35
local SHELL_VEL_FWD_MAX   = 35
local SHELL_ANGVEL_MIN    = -220
local SHELL_ANGVEL_MAX    = 220
local SHELL_MASS          = 2

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

local WWEIGHT_MG             = 8
local WWEIGHT_MISSILE_SINGLE = 20
local WWEIGHT_MISSILE_DOUBLE = 5
local WWEIGHT_GRENADE        = 10
local WWEIGHT_TOPMISSILE     = 10
local WWEIGHT_TRACKMISSILE   = 2
local WWEIGHT_ORBITRPG       = 10
local WWEIGHT_NIKITA         = 8
local WWEIGHT_BUSHMASTER     = 35

local SALVO_SPREAD_XY = 220
local SALVO_SPREAD_Z  = 80
local SALVO_DELAY     = 0.8

local GL_COUNT_MIN    = 4
local GL_COUNT_MAX    = 8
local GL_INTERVAL     = 0.35
local GL_SPREAD_Y     = 250
local GL_LAUNCH_Z     = 200
local GL_SOUND_FIDGET = "mac_bo2_m32/fidget.wav"
local GL_SOUND_FIRE   = "mac_bo2_m32/fire.wav"
local GL_SOUND_INSERT = "mac_bo2_m32/insert.wav"
local GL_FIDGET_LEAD  = 0.5
local GL_GRENADE_TYPES = { "bombin_gas_grenade", "ent_gas_stun", "ent_flashbang" }
local GL_TYPE_PARAMS = {
    ["bombin_gas_grenade"] = { speed = 2200, loft = 0.28 },
    ["ent_gas_stun"]       = { speed = 2750, loft = 0.35 },
    ["ent_flashbang"]      = { speed = 6500, loft = 0.42 },
}
local GL_TYPE_DEFAULT = { speed = 2650, loft = 0.35 }
local GL_TRAIL_MATERIAL  = "trails/smoke"
local GL_TRAIL_LIFETIME  = 0.6
local GL_TRAIL_STARTSIZE = 22
local GL_TRAIL_ENDSIZE   = 1
local GL_TRAIL_COLOR     = Color(235, 235, 235, 200)
local GL_MUZZLE_FLASH_SCALE = 0.4
local GL_SPARK_ATT_CYCLE = { ATT_MACHINEGUN, ATT_MISSILE_L, ATT_MISSILE_R }
local GL_SPARK_SCALE     = 0.5
local GL_SPARK_MAGNITUDE = 4
local GL_SPARK_RADIUS    = 10
local GL_VAPOR_EFFECT    = "SmokeEffect"
local GL_SMOKE_EFFECT    = "BlackSmoke"
local GL_VAPOR_SCALE     = 0.6
local GL_SMOKE_SCALE     = 0.4
local GL_SMOKE_EVERY     = 2

local KORNET_SND_SHOTS  = {
    "kornet/shot1.wav",
    "kornet/shot2.wav",
    "kornet/shot3.wav",
    "kornet/shot4.wav",
}
local KORNET_SND_LAUNCHES = { "kornet/launch1.wav", "kornet/launch2.wav" }
local KORNET_SND_LEVEL    = 95

local TOPMISSILE_LAUNCH_Z   = 300
local MISSILE_MIN_DIST      = 1200
local NIKITA_MIN_DIST       = 800
local MISSILE_SOUND_WARN    = "buttons/button17.wav"
local MISSILE_SPAWN_FORWARD = 600
local NIKITA_SPAWN_FORWARD  = 100
local NIKITA_SPAWN_Z        = 340

local NIKITA_MUZZLE_SMOKE_COUNT   = 5
local NIKITA_MUZZLE_SMOKE_SCALE   = 1.8
local NIKITA_MUZZLE_SMOKE_STAGGER = 0.06

local JUMP_STATE_NAMES       = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }
local HEAD_Z_FRACTION        = 0.65
local BLOOD_DAMAGE_THRESHOLD = 900
local BLOOD_RANDOM_CHANCE    = 40
local GROUNDED_BLEED_CHANCE  = 0.85

local function GetActiveEnemy(ent)
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

local function RollWeapon()
    local r   = math.random(1, 108)
    local cum = 0
    cum = cum + WWEIGHT_MG;             if r <= cum then return "MG"           end
    cum = cum + WWEIGHT_MISSILE_SINGLE; if r <= cum then return "MISSILE"      end
    cum = cum + WWEIGHT_MISSILE_DOUBLE; if r <= cum then return "SALVO"        end
    cum = cum + WWEIGHT_GRENADE;        if r <= cum then return "GRENADE"      end
    cum = cum + WWEIGHT_TOPMISSILE;     if r <= cum then return "TOPMISSILE"   end
    cum = cum + WWEIGHT_TRACKMISSILE;   if r <= cum then return "TRACKMISSILE" end
    cum = cum + WWEIGHT_ORBITRPG;       if r <= cum then return "ORBITRPG"     end
    cum = cum + WWEIGHT_NIKITA;         if r <= cum then return "NIKITA"       end
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
    local src    = misAtt and misAtt.Pos or (ent:GetPos() + Vector(0,0,160))
    local target = aimPos + (spread or Vector(0,0,0))
    local dir    = (target - src):GetNormalized()
    local rocket = ents.Create("obj_vj_rocket")
    if IsValid(rocket) then
        rocket:SetPos(src) ; rocket:SetAngles(dir:Angle())
        rocket:SetOwner(ent) ; rocket:Spawn() ; rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1200) end
    end
    local eff = EffectData() ; eff:SetOrigin(src) ; eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)
    SendMuzzleFlash(src, dir, 2)
    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(95, 110), 1)
end

local function SalvoSpread()
    return Vector(
        (math.random()-0.5)*2*SALVO_SPREAD_XY,
        (math.random()-0.5)*2*SALVO_SPREAD_XY,
        (math.random()-0.5)*2*SALVO_SPREAD_Z
    )
end

local function GLSparkAtAttachment(ent, shotIndex)
    local attIdx  = GL_SPARK_ATT_CYCLE[((shotIndex-1) % #GL_SPARK_ATT_CYCLE)+1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd = attData.Ang:Forward()
    local e = EffectData()
    e:SetOrigin(attData.Pos+fwd*4) ; e:SetNormal(fwd) ; e:SetEntity(ent)
    e:SetMagnitude(GL_SPARK_MAGNITUDE*GL_SPARK_SCALE) ; e:SetScale(GL_SPARK_SCALE) ; e:SetRadius(GL_SPARK_RADIUS)
    util.Effect("ManhackSparks", e)
end

local function GLVaporAtAttachment(ent, shotIndex)
    local attIdx  = GL_SPARK_ATT_CYCLE[((shotIndex-1) % #GL_SPARK_ATT_CYCLE)+1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local ang = attData.Ang
    local src = attData.Pos + ang:Forward()*14

    local ed1 = EffectData()
    ed1:SetOrigin(src)
    ed1:SetNormal(ang:Forward())
    ed1:SetAngles(ang)
    ed1:SetScale(GL_VAPOR_SCALE)
    util.Effect(GL_VAPOR_EFFECT, ed1, true, true)

    if (shotIndex % GL_SMOKE_EVERY) == 0 then
        local ed2 = EffectData()
        ed2:SetOrigin(src)
        ed2:SetNormal(ang:Forward())
        ed2:SetAngles(ang)
        ed2:SetScale(GL_SMOKE_SCALE)
        util.Effect(GL_SMOKE_EFFECT, ed2, true, true)
    end
end

local function GLMuzzleFlashAtAttachment(ent, shotIndex)
    local attIdx  = GL_SPARK_ATT_CYCLE[((shotIndex-1) % #GL_SPARK_ATT_CYCLE)+1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd = attData.Ang:Forward()
    local ed  = EffectData()
    ed:SetOrigin(attData.Pos+fwd*5) ; ed:SetNormal(fwd) ; ed:SetScale(GL_MUZZLE_FLASH_SCALE)
    util.Effect("MuzzleFlash", ed)
end

local function Spawn40mmGrenade(ent, attIdx, enemy, className)
    if not IsValid(enemy) then return end
    local att = ent:GetAttachment(attIdx)
    local src = att and att.Pos or (ent:GetPos() + Vector(0,0,160))
    local forward = att and att.Ang:Forward() or ent:GetForward()
    local target = enemy:WorldSpaceCenter()
    local toTarget = target - src
    local dist2D = Vector(toTarget.x, toTarget.y, 0):Length()
    local cfg = GL_TYPE_PARAMS[className] or GL_TYPE_DEFAULT
    local speed = cfg.speed
    local loft  = cfg.loft
    local travelTime = math.max(dist2D / speed, 0.2)
    local leadTarget = target
    if enemy.GetVelocity then
        leadTarget = leadTarget + enemy:GetVelocity() * travelTime * 0.45
    end
    local throwPos = leadTarget + Vector(0, 0, dist2D * loft)
    local dir = (throwPos - src):GetNormalized()

    local grenade = ents.Create(className)
    if not IsValid(grenade) then return end
    grenade:SetPos(src)
    grenade:SetAngles(dir:Angle())
    grenade:SetOwner(ent)
    grenade:Spawn()
    grenade:Activate()

    local phys = grenade.GetPhysicsObject and grenade:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetVelocity(dir * speed)
        phys:AddAngleVelocity(VectorRand() * 320)
    elseif grenade.SetVelocity then
        grenade:SetVelocity(dir * speed)
    end

    util.SpriteTrail(
        grenade, 0, GL_TRAIL_COLOR, false,
        GL_TRAIL_STARTSIZE, GL_TRAIL_ENDSIZE,
        GL_TRAIL_LIFETIME, 1/(GL_TRAIL_STARTSIZE+GL_TRAIL_ENDSIZE)*0.5,
        GL_TRAIL_MATERIAL
    )

    ent:EmitSound(GL_SOUND_FIRE, 95, math.random(95,105), 1)
end

local function CreateOrbitingRPG(ent, enemy)
    if not IsValid(enemy) then return nil end

    local m = ents.Create("sent_orbital_rpg")
    if not IsValid(m) then return nil end

    local radius = 500
    local angDeg = math.random(0,359)
    local orbit = Vector(math.cos(math.rad(angDeg))*radius, math.sin(math.rad(angDeg))*radius, 0)
    local startPos = enemy:GetPos() + orbit + Vector(0,0,200)

    m:SetPos(startPos)
    m:SetAngles((enemy:WorldSpaceCenter()-startPos):Angle())
    m:SetOwner(ent)
    m.Target = enemy
    m.LaunchDelay = 5.0
    m.SpawnTime = CurTime()
    m:Spawn()
    m:Activate()

    timer.Simple(0.01, function()
        if IsValid(m) then
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(Vector(0,0,0)) end
        end
    end)

    ent:EmitSound("kornet/launch1.wav", 90, math.random(98,102), 0.9)
    return m
end

local function SpawnNikita(ent, enemy)
    if not IsValid(enemy) then return nil end

    local att = ent:GetAttachment(ATT_MISSILE_L) or ent:GetAttachment(ATT_MISSILE_R)
    local src = att and att.Pos or (ent:GetPos()+Vector(0,0,NIKITA_SPAWN_Z))
    local startPos = src + ent:GetForward()*NIKITA_SPAWN_FORWARD + Vector(0,0,NIKITA_SPAWN_Z-(att and 0 or 0))

    local m = ents.Create("npc_vj_gekko_nikita")
    if not IsValid(m) then return nil end

    m:SetPos(startPos)
    m:SetAngles((enemy:WorldSpaceCenter()-startPos):Angle())
    m:SetOwner(ent)
    m.VJ_NPC_Class = ent.VJ_NPC_Class
    m:SetNWEntity("GekkoNikitaOwner", ent)
    m:Spawn()
    m:Activate()

    if att then
        local fwd = att.Ang:Forward()
        for i = 0, NIKITA_MUZZLE_SMOKE_COUNT - 1 do
            timer.Simple(i * NIKITA_MUZZLE_SMOKE_STAGGER, function()
                if not IsValid(ent) then return end
                local a = ent:GetAttachment(ATT_MISSILE_L) or ent:GetAttachment(ATT_MISSILE_R)
                if not a then return end
                local ed = EffectData()
                ed:SetOrigin(a.Pos + fwd*12)
                ed:SetNormal(fwd)
                ed:SetAngles(a.Ang)
                ed:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
                util.Effect("SmokeEffect", ed, true, true)
            end)
        end
        SendMuzzleFlash(att.Pos, fwd, 4)
    end

    ent:EmitSound(KORNET_SND_LAUNCHES[math.random(#KORNET_SND_LAUNCHES)], KORNET_SND_LEVEL, math.random(95,105), 1)
    return m
end

local function SpawnShell(ent, attData, scale)
    if not attData then return end
    local shell = ents.Create("prop_physics")
    if not IsValid(shell) then return end

    local right = attData.Ang:Right()
    local up    = attData.Ang:Up()
    local fwd   = attData.Ang:Forward()
    local pos   = attData.Pos + right*SHELL_RIGHT_OFFSET + up*SHELL_UP_OFFSET + fwd*SHELL_FWD_OFFSET

    shell:SetModel(SHELL_MODEL)
    shell:SetModelScale(scale or 1, 0)
    shell:SetPos(pos)
    shell:SetAngles(attData.Ang)
    shell:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    shell:Spawn()
    shell:Activate()

    local phys = shell:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(SHELL_MASS)
        local vel = right*math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX)
                  + up   *math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX)
                  + fwd  *math.Rand(SHELL_VEL_FWD_MIN,   SHELL_VEL_FWD_MAX)
        phys:SetVelocity(vel)
        phys:AddAngleVelocity(Vector(
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
            math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX)
        ))
    end

    timer.Simple(SHELL_LIFETIME, function()
        if IsValid(shell) then shell:Remove() end
    end)
end

local function PlayReloadSound(ent)
    ent:EmitSound(RELOAD_SNDS[math.random(#RELOAD_SNDS)], RELOAD_SND_LEVEL, math.random(95, 105), 1)
end

local function SafeInitVJTables(ent)
    if not ent.VJ_DeathAnimationCodeList then ent.VJ_DeathAnimationCodeList = {} end
    if not ent.VJ_DeathAnimationSounds   then ent.VJ_DeathAnimationSounds   = {} end
    if not ent.VJ_DeathAnimationTranslations then ent.VJ_DeathAnimationTranslations = {} end
    if not ent.VJ_DeathSounds        then ent.VJ_DeathSounds        = {} end
    if not ent.VJ_MeleeAttackDamageType then ent.VJ_MeleeAttackDamageType = DMG_CRUSH end
end

ENT.Model = {"models/gekko/gekko_npc.mdl"}
ENT.StartHealth = 3000
ENT.HullType = HULL_LARGE
ENT.MovementType = VJ_MOVETYPE_GROUND
ENT.MeleeAttackDamage = 150
ENT.MeleeAttackDamageDistance = 180
ENT.TimeUntilMeleeAttackDamage = false
ENT.AnimTbl_MeleeAttack = {"idle","walk","run"}
ENT.CanFlinch = 0
ENT.HasDeathAnimation = false
ENT.HasDeathRagdoll = false
ENT.HasGibOnDeath = false
ENT.DeathAnimationTime = 0
ENT.HasMeleeAttack = true
ENT.MeleeAttackDistance = 260
ENT.MeleeAttackAngleRadius = 180
ENT.MeleeAttackAnimationFaceEnemy = false
ENT.HasRangeAttack = true
ENT.RangeAttackEntityToSpawn = nil
ENT.RangeDistance = 0
ENT.RangeToMeleeDistance = 0
ENT.ConstantlyFaceEnemy = false
ENT.DisableFootStepSoundTimer = true
ENT.FootStepTimeRun = 0.35
ENT.FootStepTimeWalk = 0.55
ENT.SoundTbl_FootStep = {
    "player/footsteps/metal1.wav",
    "player/footsteps/metal2.wav",
    "player/footsteps/metal3.wav",
    "player/footsteps/metal4.wav",
}
ENT.SoundTbl_Alert = {"npc/strider/striderx_alert2.wav"}
ENT.SoundTbl_BeforeMeleeAttack = {"npc/strider/strider_skewer1.wav"}
ENT.SoundTbl_Death = {}
ENT.SoundTbl_Pain = {}

ENT.JUMP_NONE    = 0
ENT.JUMP_RISING  = 1
ENT.JUMP_FALLING = 2
ENT.JUMP_LAND    = 3

function ENT:Controller_IntMsg(ply, controlEnt)
    ply:ChatPrint("LMB = MG | RMB = Jump | Reload = Random Heavy Weapon")
end

function ENT:SetGekkoJumpState(st)
    self._jumpStateLOCAL = st or 0
    self:SetNWInt("GekkoJumpState", self._jumpStateLOCAL)
end

function ENT:GetGekkoJumpState()
    return self._jumpStateLOCAL or self:GetNWInt("GekkoJumpState", 0)
end

function ENT:SetGekkoJumpTimer(t)
    self._jumpTimerLOCAL = t or 0
    self:SetNWFloat("GekkoJumpTimer", self._jumpTimerLOCAL)
end

function ENT:GetGekkoJumpTimer()
    return self._jumpTimerLOCAL or self:GetNWFloat("GekkoJumpTimer", 0)
end

function ENT:CustomOnInitialize()
    self._manualControlActive    = false
    self._mgBurstActive          = false
    self._mgBurstEndT            = 0
    self._mgNextShotT            = 0
    self._mgRoundsLeft           = 0
    self._mgLastSoundT           = 0
    self._gekkoDesiredLocoSeq    = -1
    self._gekkoCurrentLocoSeq    = -1
    self._gekkoTargetRate        = 1.0
    self:SetNWBool("GekkoMGFiring",     false)
    self:SetNWInt("GekkoJumpDust",      0)
    self:SetNWInt("GekkoLandDust",      0)
    self:SetNWInt("GekkoFK360LandDust", 0)
    self:SetNWInt("GekkoBloodSplat",    0)
    SafeInitVJTables(self)
    self:GekkoJump_Init()
    self:GekkoTargetJump_Init()
    self:GeckoCrouch_Init()
    self:GekkoLegs_Init()
    self:GekkoDeath_Init()
    local selfRef = self
    timer.Simple(0, function()
        if not IsValid(selfRef) then return end
        selfRef:GekkoJump_Activate()
        selfRef.StartMoveSpeed = selfRef.MoveSpeed or 150
        selfRef.StartRunSpeed  = selfRef.RunSpeed  or 300
        selfRef.StartWalkSpeed = selfRef.WalkSpeed or 150
        local walkSeq = selfRef:LookupSequence("walk")
        local runSeq  = selfRef:LookupSequence("run")
        selfRef._seqWalk = walkSeq
        selfRef._seqRun  = runSeq
        if walkSeq > 0 then selfRef:SetCycle(0) end
    end)
    self.Gekko_NextDebugT = 0
end

function ENT:CustomOnAcceptInput(key, activator, caller, data)
    if key == "step_left" or key == "step_right" then
        self:EmitSound(self.SoundTbl_FootStep[math.random(#self.SoundTbl_FootStep)], 80, math.random(90,110), 0.7)
    end
end

function ENT:CustomOnAlert(argent)
    self:EmitSound(self.SoundTbl_Alert[1], 90, 100)
end

function ENT:GekkoUpdateAnimation()
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end
    local vel2D = self:GetVelocity() ; vel2D.z = 0
    local speed = vel2D:Length()
    local desired = -1
    if self._gekkoCrouching then
        desired = self:LookupSequence("crouch_idle")
        self._gekkoTargetRate = 1
    elseif speed < 10 then
        desired = self:LookupSequence("idle")
        self._gekkoTargetRate = 1
    elseif speed > RUN_ENGAGE_DIST then
        desired = self._seqRun or self:LookupSequence("run")
        self._gekkoTargetRate = math.Clamp(speed / ANIM_RUN_SPEED, 0.8, 2.0)
    else
        desired = self._seqWalk or self:LookupSequence("walk")
        self._gekkoTargetRate = math.Clamp(speed / ANIM_WALK_SPEED, 0.7, 1.4)
    end
    if desired > 0 and desired ~= self._gekkoCurrentLocoSeq then
        self:ResetSequence(desired)
        self:SetCycle(0)
        self._gekkoCurrentLocoSeq = desired
    end
    local cur = self:GetPlaybackRate()
    self:SetPlaybackRate(Lerp(FrameTime() * RATE_SMOOTH_SPEED, cur, self._gekkoTargetRate or 1))
end

function ENT:CustomOnThink_AIEnabled()
    self:GekkoUpdateAnimation()
end

function ENT:CustomOnThink()
    local enemy = GetActiveEnemy(self)
    self._manualControlActive = IsValid(self.VJ_TheController)

    if self._mgBurstActive and CurTime() >= self._mgNextShotT then
        if self._mgRoundsLeft > 0 then
            self:_GekkoFireMG()
            self._mgRoundsLeft = self._mgRoundsLeft - 1
            self._mgNextShotT = CurTime() + MG_INTERVAL
        else
            self._mgBurstActive = false
            self:SetNWBool("GekkoMGFiring", false)
        end
    end

    if self._manualControlActive then return end
    if self:GetGekkoJumpState() ~= self.JUMP_NONE then return end
    if not IsValid(enemy) then return end
    if self._gekkoCrouching then return end

    if not self._nextRangeDecisionT or CurTime() >= self._nextRangeDecisionT then
        self._nextRangeDecisionT = CurTime() + math.Rand(2.5, 5.0)
        local dist = self:GetPos():Distance(enemy:GetPos())
        if dist >= MISSILE_MIN_DIST then
            local choice = RollWeapon()
            if choice == "MG" then self:StartMGBurst()
            elseif choice == "MISSILE" then self:FireSingleMissile(enemy)
            elseif choice == "SALVO" then self:FireDoubleSalvo(enemy)
            elseif choice == "GRENADE" then self:FireGrenadeBarrage(enemy)
            elseif choice == "TOPMISSILE" then self:FireTopMissile(enemy)
            elseif choice == "TRACKMISSILE" then self:FireTrackMissile(enemy)
            elseif choice == "ORBITRPG" then self:SpawnOrbitRPG(enemy)
            elseif choice == "NIKITA" then self:FireNikita(enemy)
            elseif choice == "BRUSHMASTER" then self:StartBushmasterBurst(enemy) end
        else
            if math.random(1,100) <= 55 then self:StartMGBurst() end
        end
    end
end

function ENT:StartMGBurst()
    if self._mgBurstActive then return end
    self._mgBurstActive = true
    self._mgRoundsLeft  = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    self._mgNextShotT   = CurTime()
    self._mgBurstEndT   = CurTime() + self._mgRoundsLeft * MG_INTERVAL + 0.2
    self:SetNWBool("GekkoMGFiring", true)
end

function ENT:_GekkoFireMG()
    local att = self:GetAttachment(ATT_MACHINEGUN)
    local src = att and att.Pos or (self:GetPos()+Vector(0,0,140))
    local dir
    local enemy = GetActiveEnemy(self)
    if IsValid(enemy) then dir = (enemy:WorldSpaceCenter() - src):GetNormalized()
    else dir = self:GetForward() end

    local spread = Vector(MG_SPREAD_MIN, MG_SPREAD_MIN, 0)

    self:FireBullets({
        Attacker = self,
        Damage   = MG_DAMAGE,
        Force    = 5,
        Num      = 1,
        Src      = src,
        Dir      = dir,
        Spread   = spread,
        Tracer   = 1,
        TracerName = "Tracer",
        Callback = function(attacker, trr, dmginfo)
            SendBulletImpact(trr.HitPos, trr.HitNormal, 1)
        end
    })

    if (self._mgRoundsLeft % MG_FLASH_EVERY) == 0 then
        local eff = EffectData() ; eff:SetOrigin(src) ; eff:SetNormal(dir) ; eff:SetScale(0.45)
        util.Effect("MuzzleFlash", eff)
        SendMuzzleFlash(src, dir, 1)
    end
    self:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(97,103), 0.9)
    if (self._mgRoundsLeft % MG_CHAIN_EVERY) == 0 then self:EmitSound(MG_SND_CHAININSERT, 82, 100, 0.55) end
    if att then SpawnShell(self, att, MG_SHELL_SCALE) end
end

function ENT:FireSingleMissile(enemy)
    if not IsValid(enemy) then return end
    local att = (math.random(0,1) == 0) and ATT_MISSILE_L or ATT_MISSILE_R
    SpawnRocket(self, att, enemy:WorldSpaceCenter())
end

function ENT:FireDoubleSalvo(enemy)
    if not IsValid(enemy) then return end
    SpawnRocket(self, ATT_MISSILE_L, enemy:WorldSpaceCenter(), SalvoSpread())
    timer.Simple(SALVO_DELAY, function()
        if IsValid(self) and IsValid(enemy) then
            SpawnRocket(self, ATT_MISSILE_R, enemy:WorldSpaceCenter(), SalvoSpread())
        end
    end)
end

function ENT:FireGrenadeBarrage(enemy)
    if not IsValid(enemy) then return end
    local count = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    self:EmitSound(GL_SOUND_FIDGET, 80, math.random(97,103), 0.9)
    timer.Simple(GL_FIDGET_LEAD, function()
        if not IsValid(self) then return end
        PlayReloadSound(self)
        for i = 1, count do
            timer.Simple((i - 1) * GL_INTERVAL, function()
                if not IsValid(self) or not IsValid(enemy) then return end
                local attIdx = GL_SPARK_ATT_CYCLE[((i-1) % #GL_SPARK_ATT_CYCLE)+1]
                local className = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
                Spawn40mmGrenade(self, attIdx, enemy, className)
                GLMuzzleFlashAtAttachment(self, i)
                GLSparkAtAttachment(self, i)
                GLVaporAtAttachment(self, i)
                local att = self:GetAttachment(attIdx)
                if att then SendMuzzleFlash(att.Pos, att.Ang:Forward(), 2) end
            end)
        end
    end)
end

function ENT:FireTopMissile(enemy)
    if not IsValid(enemy) then return end
    local src = self:GetPos() + self:GetForward()*MISSILE_SPAWN_FORWARD + Vector(0,0,TOPMISSILE_LAUNCH_Z)
    local m = ents.Create("sent_npc_topmissile")
    if not IsValid(m) then return end
    m:SetPos(src)
    m:SetAngles((enemy:WorldSpaceCenter()-src):Angle())
    m:SetOwner(self)
    m:SetNWEntity("TopMissileTarget", enemy)
    m:Spawn()
    m:Activate()
    self:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95,105), 1)
end

function ENT:FireTrackMissile(enemy)
    if not IsValid(enemy) then return end
    local src = self:GetPos() + self:GetForward()*MISSILE_SPAWN_FORWARD + Vector(0,0,TOPMISSILE_LAUNCH_Z)
    local m = ents.Create("sent_npc_trackmissile")
    if not IsValid(m) then return end
    m:SetPos(src)
    m:SetAngles((enemy:WorldSpaceCenter()-src):Angle())
    m:SetOwner(self)
    m:SetNWEntity("TrackMissileTarget", enemy)
    m:Spawn()
    m:Activate()
    self:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95,105), 1)
end

function ENT:SpawnOrbitRPG(enemy)
    CreateOrbitingRPG(self, enemy)
end

function ENT:FireNikita(enemy)
    if not IsValid(enemy) then return end
    local dist = self:GetPos():Distance(enemy:GetPos())
    if dist < NIKITA_MIN_DIST then return end
    SpawnNikita(self, enemy)
end

function ENT:StartBushmasterBurst(enemy)
    if self._bmBurstActive then return end
    self._bmBurstActive = true
    self._bmRoundsLeft  = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)
    self._bmNextShotT   = CurTime()
    self._bmEnemyRef    = enemy
    self:EmitSound(BM_SND_RELOAD, BM_SND_LEVEL, 100, 0.9)
end

function ENT:_GekkoFireBushmaster(enemy)
    local att = self:GetAttachment(ATT_MACHINEGUN)
    local src = att and (att.Pos + Vector(0,0,BM_MUZZLE_Z_OFFSET)) or (self:GetPos()+Vector(0,0,180))
    local dir = IsValid(enemy) and (enemy:WorldSpaceCenter() - src):GetNormalized() or self:GetForward()
    self:FireBullets({
        Attacker = self,
        Damage   = 120,
        Force    = 30,
        Num      = 1,
        Src      = src,
        Dir      = dir,
        Spread   = Vector(0.025, 0.025, 0),
        Tracer   = 1,
        TracerName = "HelicopterTracer",
        Callback = function(attacker, trr, dmginfo)
            SendBulletImpact(trr.HitPos, trr.HitNormal, 2)
        end
    })
    local ed = EffectData() ; ed:SetOrigin(src) ; ed:SetNormal(dir) ; ed:SetScale(BM_MUZZLE_SCALE)
    util.Effect("MuzzleFlash", ed)
    SendMuzzleFlash(src, dir, 3)
    self:EmitSound(BM_SND_SHOOT, BM_SND_LEVEL, math.random(97,103), 1)
    if att then SpawnShell(self, att, BM_SHELL_SCALE) end
end

function ENT:OnInput(key, activator, caller, data)
    if key == "step_left" or key == "step_right" then
        self:EmitSound(self.SoundTbl_FootStep[math.random(#self.SoundTbl_FootStep)], 80, math.random(90,110), 0.7)
    end
end

function ENT:OnTakeDamage(dmginfo)
    local rawDmg = dmginfo:GetDamage()
    local hitPos = dmginfo:GetDamagePosition()
    if hitPos ~= vector_origin then
        local headZ = self:WorldSpaceCenter().z + (self:OBBMaxs().z - self:OBBMins().z) * HEAD_Z_FRACTION
        if hitPos.z >= headZ and math.random(1, 100) <= BLOOD_RANDOM_CHANCE then
            self._bloodSplatPulse = (self._bloodSplatPulse or 0) + 1
            local variant = math.random(1,5)
            self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse*8 + (variant-1))
        end
    end
    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)
    dmginfo:SetDamagePosition(self:GetPos())
    self.BaseClass.OnTakeDamage(self, dmginfo)
end

function ENT:OnThink()
    if self._gekkoLegsDisabled then self:GekkoLegs_Think() end
    self:GekkoDeath_Think()
    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end
    if self._bmBurstActive and CurTime() >= (self._bmNextShotT or 0) then
        if (self._bmRoundsLeft or 0) > 0 then
            self:_GekkoFireBushmaster(self._bmEnemyRef)
            self._bmRoundsLeft = self._bmRoundsLeft - 1
            self._bmNextShotT = CurTime() + BM_INTERVAL
        else
            self._bmBurstActive = false
        end
    end
    self:GekkoJump_Think()
    self:GekkoTargetJump_Think()
    self:GekkoUpdateAnimation()
    self:GeckoCrush_Think()
    if CurTime() > self.Gekko_NextDebugT then
        self.Gekko_NextDebugT = CurTime() + 2
    end
end

function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end
    self:GekkoDeath_Trigger(dmginfo)
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
