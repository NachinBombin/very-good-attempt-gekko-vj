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
-- VJBase ENT table
-- ============================================================
ENT.Type            = "anim"
ENT.Base            = "base_vj_npc"
ENT.PrintName       = "Gekko"
ENT.Author          = ""
ENT.Category        = "VJ Base"
ENT.SelectWeapon    = false
ENT.VJTag_IsVJBaseNPC = true

-- ============================================================
-- CONSTANTS
-- ============================================================
-- Machine-gun
local MG_DAMAGE       = 16
local MG_FORCE        = 3
local MG_SPREAD       = 0.03
local MG_TRACER       = 1
local MG_COUNT        = 1

-- Missile
local MISS_SPEED      = 900
local MISS_DAMAGE     = 190
local MISS_RADIUS     = 380

-- Grenade
local GREN_SPEED      = 650
local GREN_FUSE       = 2.8

-- Top missile
local TOPM_SPEED      = 700
local TOPM_DAMAGE     = 210
local TOPM_RADIUS     = 400

-- Track missile
local TRACKM_SPEED    = 650
local TRACKM_DAMAGE   = 160
local TRACKM_RADIUS   = 300

-- Orbit RPG
local ORPG_SPEED      = 580
local ORPG_DAMAGE     = 200
local ORPG_RADIUS     = 350

-- Nikita
local NIK_SPEED       = 520
local NIK_DAMAGE      = 240
local NIK_RADIUS      = 420
local NIK_UPWARD      = 220

-- Bushmaster 25mm
local BM_ROUNDS_MIN   = 7
local BM_ROUNDS_MAX   = 13
local BM_INTERVAL     = 0.09
local BM_MUZZLE_Z_OFFSET = 90
local BM_SPARK_SCALE  = 1.2
local BM_SPARK_MAGNITUDE = 2.0
local BM_SPARK_RADIUS = 8
local BM_SMOKE_FORWARD = 18
local BM_SMOKE_UP      = 4
local BM_SMOKE_SCALE   = 0.6
local BM_MUZZLE_SCALE  = 0.9
local BM_TRAIL_MATERIAL  = "effects/blueflare1"
local BM_TRAIL_LIFETIME  = 0.10
local BM_TRAIL_STARTSIZE = 2.5
local BM_TRAIL_ENDSIZE   = 0.4
local BM_SND_SHOOT    = "weapons/ar2/fire1.wav"
local BM_SND_RELOAD   = "weapons/ar2/ar2_reload1.wav"
local BM_SND_LEVEL    = 80

-- Cartridge
local CART_MODEL      = "models/props_junk/PopCan01a.mdl"
local CART_SCALE      = 0.35

-- Weapon selection weights/ranges
local DIST_CLOSE      = 600
local DIST_MID        = 1400
local DIST_LONG       = 2800

-- ============================================================
-- HELPERS
-- ============================================================
local function GetActiveEnemy(ent)
    return IsValid(ent:GetEnemy()) and ent:GetEnemy() or NULL
end

local function SendMuzzleFlash(pos, dir, size)
    net.Start("GekkoMuzzleFlash")
        net.WriteVector(pos)
        net.WriteVector(dir)
        net.WriteUInt(size, 4)
    net.Broadcast()
end

local function SpawnCartridge(pos, ang, scale)
    local c = ents.Create("prop_physics")
    if not IsValid(c) then return end
    c:SetModel(CART_MODEL)
    c:SetPos(pos + Vector(0,0,20))
    c:SetAngles(ang)
    c:SetModelScale(scale or CART_SCALE)
    c:Spawn(); c:Activate()
    local phys = c:GetPhysicsObject()
    if IsValid(phys) then
        phys:ApplyForceCenter(Vector(
            math.Rand(-80, 80),
            math.Rand(-80, 80),
            math.Rand(120, 220)
        ))
    end
    timer.Simple(8, function() if IsValid(c) then c:Remove() end end)
end

-- ============================================================
-- WEAPON SELECTION
-- ============================================================
function ENT:GekkoSelectWeapon(enemy, dist)
    -- Returns a string key for the chosen weapon.
    -- Weights are intentionally loose; no two consecutive same-weapon
    -- calls are guaranteed by VJBase's own cooldown system.

    if dist <= DIST_CLOSE then
        -- Close range: favour MG and grenades
        local r = math.random(1, 10)
        if     r <= 4  then return "MG"
        elseif r <= 6  then return "GRENADE"
        elseif r <= 8  then return "BRUSHMASTER"
        elseif r == 9  then return "ELASTIC"
        else               return "MISSILE_SINGLE"
        end

    elseif dist <= DIST_MID then
        local r = math.random(1, 10)
        if     r <= 3  then return "MG"
        elseif r <= 5  then return "BRUSHMASTER"
        elseif r == 6  then return "GRENADE"
        elseif r == 7  then return "MISSILE_SINGLE"
        elseif r == 8  then return "TOPMISSILE"
        elseif r == 9  then return "ELASTIC"
        else               return "TRACKMISSILE"
        end

    elseif dist <= DIST_LONG then
        local r = math.random(1, 10)
        if     r <= 2  then return "BRUSHMASTER"
        elseif r <= 4  then return "MISSILE_DOUBLE"
        elseif r == 5  then return "TOPMISSILE"
        elseif r == 6  then return "TRACKMISSILE"
        elseif r == 7  then return "ORBITRPG"
        elseif r == 8  then return "NIKITA"
        elseif r == 9  then return "GRENADE"
        else               return "MISSILE_SINGLE"
        end

    else
        -- Very long range
        local r = math.random(1, 6)
        if     r == 1  then return "NIKITA"
        elseif r == 2  then return "ORBITRPG"
        elseif r == 3  then return "TOPMISSILE"
        elseif r == 4  then return "TRACKMISSILE"
        elseif r == 5  then return "MISSILE_DOUBLE"
        else               return "MISSILE_SINGLE"
        end
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
-- MACHINE GUN
-- ============================================================
function ENT:FireMachineGun(enemy)
    local src = self:GetAttachment(ATT_MACHINEGUN)
    if not src then src = {Pos = self:GetPos() + Vector(0,0,60), Ang = self:GetAngles()} end

    local dir = (enemy:GetPos() + Vector(0,0,40) - src.Pos):GetNormalized()

    self:FireBullets({
        Num        = MG_COUNT,
        Src        = src.Pos,
        Dir        = dir,
        Spread     = Vector(MG_SPREAD, MG_SPREAD, 0),
        Tracer     = MG_TRACER,
        Force      = MG_FORCE,
        Damage     = MG_DAMAGE,
        AmmoType   = "AR2",
        Attacker   = self,
    })

    SendMuzzleFlash(src.Pos, dir, 2)
    self:EmitSound("weapons/ar2/fire1.wav", 75, math.random(95,110))
    return true
end

-- ============================================================
-- MISSILE
-- ============================================================
function ENT:FireMissile(enemy, double)
    local function Launch(att)
        local src = self:GetAttachment(att)
        if not src then return end
        local dir = (enemy:GetPos() + Vector(0,0,40) - src.Pos):GetNormalized()
        local m = ents.Create("obj_vj_rocket")
        if not IsValid(m) then return end
        m:SetPos(src.Pos); m:SetAngles(dir:Angle())
        m:SetOwner(self); m:Spawn(); m:Activate()
        m:SetKeyValue("damage", tostring(MISS_DAMAGE))
        m:SetKeyValue("damage_radius", tostring(MISS_RADIUS))
        local phys = m:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * MISS_SPEED) end
    end

    Launch(ATT_MISSILE_L)
    if double then
        timer.Simple(0.15, function()
            if IsValid(self) then Launch(ATT_MISSILE_R) end
        end)
    end
    self:EmitSound("npc/attack_helicopter/aheli_rocket_fire1.wav", 90, 100)
    return true
end

-- ============================================================
-- GRENADE LAUNCHER
-- ============================================================
function ENT:FireGrenadeLauncher(enemy)
    local src = self:GetPos() + Vector(0,0,70)
    local tgt = enemy:GetPos() + Vector(0,0,30)
    local dir = (tgt - src):GetNormalized()

    local count = math.random(2, 4)
    for i = 0, count - 1 do
        timer.Simple(i * 0.22, function()
            if not IsValid(self) then return end
            local g = ents.Create("bombin_gas_grenade")
            if not IsValid(g) then
                g = ents.Create("npc_grenade_frag")
            end
            if not IsValid(g) then return end
            local jitter = Vector(
                math.Rand(-30, 30),
                math.Rand(-30, 30),
                math.Rand(10, 50)
            )
            g:SetPos(src + jitter * 0.1)
            g:SetAngles(dir:Angle())
            g:SetOwner(self)
            g:Spawn(); g:Activate()
            local phys = g:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity((dir + jitter:GetNormalized() * 0.15) * GREN_SPEED)
            end
            timer.Simple(GREN_FUSE, function() if IsValid(g) then g:Remove() end end)
        end)
    end
    self:EmitSound("weapons/grenade_launcher/gl_fire.wav", 85, math.random(95, 110))
    return true
end

-- ============================================================
-- TOP-ATTACK MISSILE
-- ============================================================
function ENT:FireTopMissile(enemy)
    local src = self:GetPos() + Vector(0, 0, 80)
    local m = ents.Create("sent_npc_topmissile")
    if not IsValid(m) then return false end
    m:SetPos(src)
    m:SetAngles(Angle(0,0,0))
    m:SetOwner(self)
    m:Spawn(); m:Activate()
    if m.SetTarget then m:SetTarget(enemy) end
    self:EmitSound("npc/attack_helicopter/aheli_rocket_fire1.wav", 90, 90)
    return true
end

-- ============================================================
-- TRACK MISSILE
-- ============================================================
function ENT:FireTrackMissile(enemy)
    local src = self:GetPos() + Vector(0, 0, 70)
    local dir = (enemy:GetPos() + Vector(0,0,40) - src):GetNormalized()
    local m = ents.Create("sent_npc_trackmissile")
    if not IsValid(m) then return false end
    m:SetPos(src); m:SetAngles(dir:Angle())
    m:SetOwner(self)
    m:Spawn(); m:Activate()
    if m.SetTarget then m:SetTarget(enemy) end
    self:EmitSound("npc/attack_helicopter/aheli_rocket_fire1.wav", 90, 95)
    return true
end

-- ============================================================
-- ORBIT RPG
-- ============================================================
function ENT:FireOrbitRPG(enemy)
    local src = self:GetPos() + Vector(0, 0, 70)
    local dir = (enemy:GetPos() + Vector(0,0,40) - src):GetNormalized()
    local m = ents.Create("sent_orbital_rpg")
    if not IsValid(m) then return false end
    m:SetPos(src); m:SetAngles(dir:Angle())
    m:SetOwner(self)
    m:Spawn(); m:Activate()
    self:EmitSound("npc/attack_helicopter/aheli_rocket_fire1.wav", 90, 110)
    return true
end

-- ============================================================
-- NIKITA
-- ============================================================
function ENT:FireNikita(enemy)
    local src = self:GetPos() + Vector(0, 0, NIK_UPWARD)
    local dir = Vector(0, 0, 1)
    local nikita = ents.Create("npc_vj_gekko_nikita")
    if not IsValid(nikita) then return false end
    nikita:SetPos(src)
    nikita:SetAngles(dir:Angle())
    nikita:SetOwner(self)
    nikita:Spawn(); nikita:Activate()
    if nikita.SetTarget then nikita:SetTarget(enemy) end
    if nikita.SetEnemy  then nikita:SetEnemy(enemy) end
    print(string.format("[GekkoNikita] Launched | dist=%.0f", self:GetPos():Distance(enemy:GetPos())))
    return true
end

-- ============================================================
-- BUSHMASTER VISUAL HELPERS  (must be defined BEFORE FireBushmaster)
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

-- ============================================================
-- BUSHMASTER 25mm CANNON
-- ============================================================
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
        local r = math.random(1, 5)
        if     r == 1 then alt = "GRENADE"
        elseif r == 2 then alt = "MISSILE_SINGLE"
        elseif r == 3 then alt = "MG"
        elseif r == 4 then alt = "BRUSHMASTER"
        else               alt = "TOPMISSILE"
        end
        print(string.format("[GekkoElastic] Re-rolled to: %s", alt))
        if     alt == "GRENADE"       then return ent:FireGrenadeLauncher(enemy)
        elseif alt == "MISSILE_SINGLE" then return ent:FireMissile(enemy, false)
        elseif alt == "MG"            then return ent:FireMachineGun(enemy)
        elseif alt == "BRUSHMASTER"   then return FireBushmaster(ent, enemy)
        elseif alt == "TOPMISSILE"    then return ent:FireTopMissile(enemy)
        end
    end
    return ent:FireElasticTether(enemy)
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/Gekko/Gekko.mdl")
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetBloodColor(DONT_BLEED)
    self:SetMaxHealth(4200)
    self:SetHealth(4200)
    self:SetNWBool("GekkoAlive", true)

    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:CapabilitiesAdd(CAP_TURN_HEAD)
    self:CapabilitiesAdd(CAP_ANIMATEDFACE)

    self.VJ_NPC_Class        = {"CLASS_COMBINE"}
    self.VJ_IsHeavyNPC       = true
    self.VJ_NPC_NextRangeAttackTime = 0.4

    -- Pelvis bone cached for muzzle offset
    self.GekkoPelvisBone = self:LookupBone("b_pelvis") or -1

    -- Crouch system
    if self.CrouchSystem_Init then self:CrouchSystem_Init() end
    -- Jump system
    if self.JumpSystem_Init then self:JumpSystem_Init() end
    -- Targeted jump system
    if self.TargetedJumpSystem_Init then self:TargetedJumpSystem_Init() end
    -- Elastic tether
    if self.ElasticSystem_Init then self:ElasticSystem_Init() end
    -- Leg disable
    if self.LegDisable_Init then self:LegDisable_Init() end

    print("[GekkoInit] Spawned | health=" .. self:GetMaxHealth())
end

-- ============================================================
-- THINK
-- ============================================================
function ENT:Think()
    -- Crouch
    if self.CrouchSystem_Think then self:CrouchSystem_Think() end
    -- Jump
    if self.JumpSystem_Think then self:JumpSystem_Think() end
    -- Targeted jump
    if self.TargetedJumpSystem_Think then self:TargetedJumpSystem_Think() end
    -- Elastic
    if self.ElasticSystem_Think then self:ElasticSystem_Think() end
    -- Leg disable
    if self.LegDisable_Think then self:LegDisable_Think() end
    -- Crush
    if self.CrushSystem_Think then self:CrushSystem_Think() end

    self:NextThink(CurTime())
    return true
end

-- ============================================================
-- ON TAKE DAMAGE  (feeds HitReact NW vars + bleeding)
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    local dmg = dmginfo:GetDamage()
    if dmg <= 0 then return end

    -- Juicy bleeding hook
    if self.GekkoBroadcastHitReact then
        self:GekkoBroadcastHitReact(dmginfo)
    end

    -- Death check
    if self:Health() - dmg <= 0 then
        self:SetNWBool("GekkoAlive", false)
    end
end

-- ============================================================
-- ON KILLED
-- ============================================================
function ENT:OnKilled(dmginfo)
    if self.GibSystem_OnKilled then self:GibSystem_OnKilled(dmginfo) end
    if self.DeathPose_OnKilled  then self:DeathPose_OnKilled(dmginfo) end
    self:SetNWBool("GekkoAlive", false)
    print("[GekkoKilled] Entity removed cleanly.")
end

-- ============================================================
-- UTILITY: attachment position helper
-- ============================================================
function ENT:GetAttachmentPos(attIdx)
    local att = self:GetAttachment(attIdx)
    return att and att.Pos or nil
end
