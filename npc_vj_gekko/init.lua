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
-- 10. Elastic tether            (elastic_system.lua — 0-900 u)
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

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")
util.AddNetworkString("GekkoMuzzleFlash")
util.AddNetworkString("GekkoBulletImpact")
util.AddNetworkString("GekkoBloodHit")

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
local TOPMISSILE_SND_LEVEL = 100

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
local WWEIGHT_ELASTIC        = 12

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
local BLOOD_DAMAGE_THRESHOLD = 20
local BLOOD_RANDOM_CHANCE    = 80
local GROUNDED_BLEED_CHANCE  = 0.85

-- ============================================================
--  BLOOD SIGNAL
--  On bullet damage, broadcasts a net message to all clients.
--  A random variant (0-5) is selected here on the server.
--  lua/autorun/client/gekko_blood.lua receives and dispatches.
--  Variant map:
--    0=HemoStream  1=Geyser  2=RadialRing
--    3=BurstCloud  4=ArcShower  5=GroundPool
-- ============================================================
local function GekkoSignalBloodHit(ent)
    if not IsValid(ent) then return end
    net.Start("GekkoBloodHit")
        net.WriteEntity(ent)
        net.WriteUInt(math.random(0, 5), 3)
    net.Broadcast()
end

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

local function GetActiveEnemy(ent)
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

local function RollWeapon()
    local r   = math.random(1, 120)
    local cum = 0
    cum = cum + WWEIGHT_MG;             if r <= cum then return "MG"           end
    cum = cum + WWEIGHT_MISSILE_SINGLE; if r <= cum then return "MISSILE"      end
    cum = cum + WWEIGHT_MISSILE_DOUBLE; if r <= cum then return "SALVO"        end
    cum = cum + WWEIGHT_GRENADE;        if r <= cum then return "GRENADE"      end
    cum = cum + WWEIGHT_TOPMISSILE;     if r <= cum then return "TOPMISSILE"   end
    cum = cum + WWEIGHT_TRACKMISSILE;   if r <= cum then return "TRACKMISSILE" end
    cum = cum + WWEIGHT_ORBITRPG;       if r <= cum then return "ORBITRPG"     end
    cum = cum + WWEIGHT_NIKITA;         if r <= cum then return "NIKITA"       end
    cum = cum + WWEIGHT_ELASTIC;        if r <= cum then return "ELASTIC"      end
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

local function FireMG(self, attacker)
    self:GekkoGib_OnShoot()
    local att  = self:GetAttachment(ATT_MACHINEGUN)
    local src  = att and att.Pos or self:GetPos() + Vector(0,0,160)
    local fwd  = att and att.Ang:Forward() or self:GetForward()

    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    local aimPos = enemy:WorldSpaceCenter()

    local dist     = src:Distance(aimPos)
    local tSpread  = math.Clamp(MG_SPREAD_MIN + (dist / 4000) * (MG_SPREAD_MAX - MG_SPREAD_MIN),
                                MG_SPREAD_MIN, MG_SPREAD_MAX)
    local spread   = Vector(tSpread, tSpread, 0)

    local bdata = {}
    bdata.Attacker  = self
    bdata.Tracer    = 1
    bdata.Src       = src
    bdata.Dir       = (aimPos - src):GetNormalized()
    bdata.Spread    = spread
    bdata.Damage    = MG_DAMAGE
    bdata.AmmoType  = "AR2"
    bdata.Callback  = function(att2, tr, dmginfo)
        if tr.Hit then
            SendBulletImpact(tr.HitPos, tr.HitNormal, 1)
        end
    end
    self:FireBullets(bdata)

    if self._mgShotCount % MG_CHAIN_EVERY == 0 then
        self:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, math.random(95, 105), 1)
    end
    self:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(95, 110), 1)

    if self._mgShotCount % MG_FLASH_EVERY == 0 then
        local attd = self:GetAttachment(ATT_MACHINEGUN)
        if attd then
            SendMuzzleFlash(attd.Pos, attd.Ang:Forward(), 1)
        end
    end

    self._mgShotCount = (self._mgShotCount or 0) + 1
end

local function FireMissile(self, salvo)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    local aimPos = enemy:WorldSpaceCenter()

    if salvo then
        SpawnRocket(self, ATT_MISSILE_L, aimPos, SalvoSpread())
        timer.Simple(SALVO_DELAY, function()
            if IsValid(self) then SpawnRocket(self, ATT_MISSILE_R, aimPos, SalvoSpread()) end
        end)
    else
        SpawnRocket(self, ATT_MISSILE_L, aimPos)
    end
end

local function FireTopMissile(self)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    local aimPos = enemy:WorldSpaceCenter()

    local src = self:GetPos() + Vector(0, 0, TOPMISSILE_LAUNCH_Z)
    local dir = (aimPos - src):GetNormalized()
    local rocket = ents.Create("sent_npc_topmissile")
    if IsValid(rocket) then
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(self)
        rocket:Spawn()
        rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1200) end
    end
    self:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
end

local function FireTrackMissile(self)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    local aimPos = enemy:WorldSpaceCenter()

    local src = self:GetPos() + Vector(0, 0, 160)
    local dir = (aimPos - src):GetNormalized()
    local rocket = ents.Create("sent_npc_trackmissile")
    if IsValid(rocket) then
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(self)
        rocket:Spawn()
        rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 900) end
    end
    self:EmitSound(KORNET_SND_SHOTS[math.random(#KORNET_SND_SHOTS)], KORNET_SND_LEVEL, math.random(95, 110), 1)
    self:EmitSound(KORNET_SND_LAUNCHES[math.random(#KORNET_SND_LAUNCHES)], KORNET_SND_LEVEL, math.random(95, 110), 1)
end

local function FireOrbitRPG(self)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end

    local src = self:GetPos() + Vector(0, 0, 160)
    local dir = (enemy:WorldSpaceCenter() - src):GetNormalized()
    local rocket = ents.Create("sent_orbital_rpg")
    if IsValid(rocket) then
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(self)
        rocket:Spawn()
        rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1100) end
    end
end

local function FireNikita(self)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    if self:GetPos():Distance(enemy:GetPos()) < NIKITA_MIN_DIST then return end

    local src = self:GetPos() + self:GetForward() * NIKITA_SPAWN_FORWARD + Vector(0, 0, NIKITA_SPAWN_Z)
    local dir = self:GetForward()
    local nikita = ents.Create("npc_vj_gekko_nikita")
    if IsValid(nikita) then
        nikita:SetPos(src)
        nikita:SetAngles(dir:Angle())
        nikita:SetOwner(self)
        nikita.GekkoMaster = self
        nikita:Spawn()
        nikita:Activate()
        local phys = nikita:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 600) end
    end

    for i = 1, NIKITA_MUZZLE_SMOKE_COUNT do
        timer.Simple(i * NIKITA_MUZZLE_SMOKE_STAGGER, function()
            if not IsValid(self) then return end
            local att = self:GetAttachment(ATT_MISSILE_L)
            if att then
                local eff = EffectData()
                eff:SetOrigin(att.Pos)
                eff:SetNormal(att.Ang:Forward())
                eff:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
                util.Effect("SmokeEffect", eff)
            end
        end)
    end
end

local function FireBushmaster(self)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end

    local rounds = math.random(BM_ROUNDS_MIN, BM_ROUNDS_MAX)
    self:EmitSound(BM_SND_RELOAD, BM_SND_LEVEL, math.random(95, 110), 1)

    for i = 1, rounds do
        timer.Simple((i-1) * BM_INTERVAL, function()
            if not IsValid(self) then return end

            local att = self:GetAttachment(ATT_MACHINEGUN)
            local src = att and att.Pos or (self:GetPos() + Vector(0, 0, BM_MUZZLE_Z_OFFSET))
            local dir = att and att.Ang:Forward() or self:GetForward()

            local ent = ents.Create("sent_gekko_bushmaster")
            if IsValid(ent) then
                ent:SetPos(src)
                ent:SetAngles(dir:Angle())
                ent:SetOwner(self)
                ent:Spawn()
                ent:Activate()
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then phys:SetVelocity(dir * 2200) end
            end

            local trailEnt = ents.Create("env_spritetrail")
            if IsValid(trailEnt) then
                trailEnt:SetPos(src)
                trailEnt:SetParent(ent)
                trailEnt:SetKeyValue("spritename", BM_TRAIL_MATERIAL)
                trailEnt:SetKeyValue("lifetime", tostring(BM_TRAIL_LIFETIME))
                trailEnt:SetKeyValue("startwidth", tostring(BM_TRAIL_STARTSIZE))
                trailEnt:SetKeyValue("endwidth",   tostring(BM_TRAIL_ENDSIZE))
                trailEnt:Spawn()
                trailEnt:Activate()
            end

            self:EmitSound(BM_SND_SHOOT, BM_SND_LEVEL, math.random(95, 110), 1)

            local sparkEff = EffectData()
            sparkEff:SetOrigin(src)
            sparkEff:SetNormal(dir)
            sparkEff:SetScale(BM_SPARK_SCALE * BM_MUZZLE_SCALE)
            sparkEff:SetMagnitude(BM_SPARK_MAGNITUDE)
            sparkEff:SetRadius(BM_SPARK_RADIUS)
            util.Effect("MuzzleEffect", sparkEff)

            local smokeEff = EffectData()
            smokeEff:SetOrigin(src + dir * BM_SMOKE_FORWARD + Vector(0, 0, BM_SMOKE_UP))
            smokeEff:SetNormal(dir)
            smokeEff:SetScale(BM_SMOKE_SCALE)
            util.Effect("SmokeEffect", smokeEff)

            SendMuzzleFlash(src, dir, 2)

            local shell = ents.Create("prop_physics_override")
            if IsValid(shell) then
                shell:SetModel(SHELL_MODEL)
                shell:SetModelScale(BM_SHELL_SCALE)
                local right = att and att.Ang:Right() or self:GetRight()
                local up    = att and att.Ang:Up()    or Vector(0,0,1)
                shell:SetPos(src + right * SHELL_RIGHT_OFFSET + up * SHELL_UP_OFFSET + dir * SHELL_FWD_OFFSET)
                shell:SetAngles(Angle(math.random(0,360), math.random(0,360), math.random(0,360)))
                shell:Spawn()
                shell:Activate()
                local phys2 = shell:GetPhysicsObject()
                if IsValid(phys2) then
                    phys2:SetMass(SHELL_MASS)
                    phys2:SetVelocity(
                        right * math.Rand(SHELL_VEL_RIGHT_MIN, SHELL_VEL_RIGHT_MAX) +
                        up    * math.Rand(SHELL_VEL_UP_MIN,    SHELL_VEL_UP_MAX) +
                        dir   * math.Rand(SHELL_VEL_FWD_MIN,   SHELL_VEL_FWD_MAX)
                    )
                    phys2:SetAngleVelocity(Vector(
                        math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
                        math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX),
                        math.Rand(SHELL_ANGVEL_MIN, SHELL_ANGVEL_MAX)
                    ))
                end
                SafeRemoveEntityDelayed(shell, SHELL_LIFETIME)
            end
        end)
    end
end

local function FireGrenadeLauncher(self)
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end
    local aimPos = enemy:GetPos()

    local count = math.random(GL_COUNT_MIN, GL_COUNT_MAX)

    self:EmitSound(GL_SOUND_FIDGET, RELOAD_SND_LEVEL, math.random(95, 110), 1)

    timer.Simple(GL_FIDGET_LEAD, function()
        if not IsValid(self) then return end
        self:EmitSound(GL_SOUND_INSERT, RELOAD_SND_LEVEL, math.random(95, 110), 1)
    end)

    for i = 1, count do
        timer.Simple(GL_FIDGET_LEAD + (i - 1) * GL_INTERVAL, function()
            if not IsValid(self) then return end

            local att = self:GetAttachment(ATT_MACHINEGUN)
            local src = att and att.Pos or (self:GetPos() + Vector(0, 0, GL_LAUNCH_Z))
            local dir = att and att.Ang:Forward() or self:GetForward()

            local gtype  = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
            local params = GL_TYPE_PARAMS[gtype] or GL_TYPE_DEFAULT

            local targetVariance = Vector(
                (math.random()-0.5) * 2 * GL_SPREAD_Y,
                (math.random()-0.5) * 2 * GL_SPREAD_Y,
                0
            )
            local finalAim  = aimPos + targetVariance
            local launchDir = (finalAim - src):GetNormalized()
            local loftedDir = (launchDir + Vector(0, 0, params.loft)):GetNormalized()

            local gren = ents.Create(gtype)
            if IsValid(gren) then
                gren:SetPos(src)
                gren:SetAngles(loftedDir:Angle())
                gren:SetOwner(self)
                gren:Spawn()
                gren:Activate()
                local phys = gren:GetPhysicsObject()
                if IsValid(phys) then phys:SetVelocity(loftedDir * params.speed) end
            end

            local trailEnt = ents.Create("env_spritetrail")
            if IsValid(trailEnt) then
                trailEnt:SetPos(src)
                trailEnt:SetParent(gren)
                trailEnt:SetKeyValue("spritename", GL_TRAIL_MATERIAL)
                trailEnt:SetKeyValue("lifetime",   tostring(GL_TRAIL_LIFETIME))
                trailEnt:SetKeyValue("startwidth",  tostring(GL_TRAIL_STARTSIZE))
                trailEnt:SetKeyValue("endwidth",    tostring(GL_TRAIL_ENDSIZE))
                trailEnt:Spawn()
                trailEnt:Activate()
            end

            self:EmitSound(GL_SOUND_FIRE, RELOAD_SND_LEVEL, math.random(95, 110), 1)

            local attIdx = GL_SPARK_ATT_CYCLE[(i % #GL_SPARK_ATT_CYCLE) + 1]
            local sAtt = self:GetAttachment(attIdx)
            if sAtt then
                local se = EffectData()
                se:SetOrigin(sAtt.Pos)
                se:SetNormal(dir)
                se:SetScale(GL_SPARK_SCALE * GL_MUZZLE_FLASH_SCALE)
                se:SetMagnitude(GL_SPARK_MAGNITUDE)
                se:SetRadius(GL_SPARK_RADIUS)
                util.Effect("MuzzleEffect", se)
            end

            if i % GL_SMOKE_EVERY == 0 then
                local veff = EffectData()
                veff:SetOrigin(src)
                veff:SetNormal(dir)
                veff:SetScale(GL_VAPOR_SCALE)
                util.Effect(GL_VAPOR_EFFECT, veff)

                local seff = EffectData()
                seff:SetOrigin(src + dir * 12)
                seff:SetNormal(dir)
                seff:SetScale(GL_SMOKE_SCALE)
                util.Effect(GL_SMOKE_EFFECT, seff)
            end
        end)
    end
end

local function FireElastic(self)
    if self.GekkoElastic_Fire then
        self:GekkoElastic_Fire()
    end
end

-- ============================================================
--  RELOAD SOUND
-- ============================================================
local function PlayReload(self)
    self:EmitSound(RELOAD_SNDS[math.random(#RELOAD_SNDS)], RELOAD_SND_LEVEL, math.random(95, 105), 1)
end

-- ============================================================
--  VJ BASE OVERRIDES
-- ============================================================
ENT.Type            = "nextbot"
ENT.Base            = "base_vj_npc_friendly"
ENT.PrintName       = "Gekko"
ENT.Author          = "NachinBombin"
ENT.Category        = "VJ Base"
ENT.AutomaticFrameAdvance = true

function ENT:SetupDataTables()
    self:NetworkVar("Bool",   0, "GekkoMGFiring")
    self:NetworkVar("Bool",   1, "GekkoLegsDisabled")
    self:NetworkVar("Int",    0, "GekkoJumpDust")
    self:NetworkVar("Int",    1, "GekkoLandDust")
    self:NetworkVar("Int",    2, "GekkoFK360LandDust")
    self:NetworkVar("Int",    3, "GekkoBloodSplat")
end

local BLOOD_COLOR_RED = BLOOD_COLOR_RED or 0

function ENT:Initialize()
    self:SetModel("models/gekko/gekko.mdl")
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetBloodColor(BLOOD_COLOR_RED)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:CapabilitiesAdd(CAP_MOVE_JUMP)
    self:CapabilitiesAdd(CAP_TURN_HEAD)
    self:CapabilitiesAdd(CAP_SQUAD)
    self:SetMaxHealth(3500)
    self:SetHealth(3500)
    self:SetArrivalSpeed(ANIM_RUN_SPEED)

    self.VJ_NPC_Class           = { "CLASS_COMBINE" }
    self.VJ_IsHumanNPC          = false
    self.VJ_AddEntityToList     = false
    self.VJ_HasDeathAnimation   = true
    self.VJ_UseGibOnDeath       = false

    self._mgBurstActive         = false
    self._mgBurstEndT           = 0
    self._mgShotCount           = 0
    self._weaponState           = "IDLE"
    self._nextAttack            = CurTime() + 3
    self._lastAttackType        = ""
    self._bloodSplatPulse        = 0

    self:SetNWBool("GekkoMGFiring",      false)
    self:SetNWBool("GekkoLegsDisabled",  false)
    self:SetNWInt("GekkoJumpDust",      0)
    self:SetNWInt("GekkoLandDust",      0)
    self:SetNWInt("GekkoFK360LandDust", 0)
    self:SetNWInt("GekkoBloodSplat",    0)

    self:GekkoLegs_Init()
    self:GekkoJump_Init()
    self:GekkoTargetJump_Init()
    self:GekkoCrouch_Init()
    self:GekkoGib_Init()
    self:GekkoDeathPose_Init()
    self:GekkoElastic_Init()
end

function ENT:OnTakeDamage(dmginfo)
    local dmgtype  = dmginfo:GetDamageType()
    local savedForce = dmginfo:GetDamageForce()

    local hitPos
    if dmginfo:IsBulletDamage() then
        local tr = dmginfo:GetDamagePosition and dmginfo:GetDamagePosition()
        hitPos   = tr or self:WorldSpaceCenter()
    else
        local inflictor = dmginfo:GetInflictor()
        if IsValid(inflictor) then
            hitPos = inflictor:GetPos()
        else
            dmginfo:SetDamageForce(savedForce)
            self.BaseClass.OnTakeDamage(self, dmginfo)
            return
        end
    end

    local _, maxs = self:GetCollisionBounds()
    local headZ   = self:GetPos().z + maxs.z * HEAD_Z_FRACTION
    if hitPos.z > headZ then dmginfo:ScaleDamage(1/3) end

    local rawDmg = dmginfo:GetDamage()

    local attacker = dmginfo:GetAttacker()
    local hitDir   = IsValid(attacker)
        and (hitPos - attacker:GetPos()):GetNormalized()
        or  self:GetForward()
    GekkoVanillaBleed(self, hitPos, hitDir)

    -- Signal cl_init to fire blood stream effect
    if dmginfo:IsBulletDamage() then
        GekkoSignalBloodHit(self)
    end

    self:GekkoLegs_OnDamage(dmginfo)
    self:GekkoGib_OnDamage(rawDmg, dmginfo)

    dmginfo:SetDamageForce(savedForce)
    self.BaseClass.OnTakeDamage(self, dmginfo)
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
    self:GekkoUpdateAnimation()
    self:GeckoCrush_Think()
    if CurTime() > self.Gekko_NextDebugT do
        local enemy = GetActiveEnemy(self)
        local dist, src
        if IsValid(enemy) then
            dist = math.floor(self:GetPos():Distance(enemy:GetPos()))
            src  = IsValid(self.VJ_TheEnemy) and "vj" or "engine"
        elseif self._gekkoLastEnemyDist then
        end
    end
end

function ENT:OnRemove()
end
