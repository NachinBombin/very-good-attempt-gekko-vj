-- ============================================================
--  npc_vj_gekko / init.lua
-- ============================================================
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("crush_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crouch_system.lua")
include("gib_system.lua")
include("leg_disable_system.lua")

util.AddNetworkString("GekkoSonarLock")
util.AddNetworkString("GekkoFK360LandDust")

local ATT_MACHINEGUN  = 3
local ATT_MISSILE_L   = 9
local ATT_MISSILE_R   = 10

local ANIM_WALK_SPEED    = 184
local ANIM_RUN_SPEED     = 20
local RUN_ENGAGE_DIST    = 2300
local RUN_DISENGAGE_DIST = 1600
local RATE_SMOOTH_SPEED  = 8.0

local MG_ROUNDS_MIN = 11
local MG_ROUNDS_MAX = 36
local MG_INTERVAL   = 0.15
local MG_DAMAGE     = 25
local MG_SPREAD_MIN = 0.08
local MG_SPREAD_MAX = 0.8

local MG_SND_SHOTS       = { "gekko/shot.wav", "gekko/shot2.wav" }
local MG_SND_CHAININSERT = "gekko/chaininsert.wav"
local MG_CHAIN_EVERY     = 6
local MG_SND_LEVEL       = 95

local ROCKET_SND_FIRE = {
    "gekko/wp0040_se_gun_fire_01.wav",
    "gekko/wp0040_se_gun_fire_02.wav",
    "gekko/wp0040_se_gun_fire_03.wav",
}
local ROCKET_SND_LEVEL = 95

local TOPMISSILE_SND_FIRE = {
    "gekko/wp10e0_se_stinger_pass_1.wav",
    "gekko/wp0302_se_missile_fire_1.wav",
    "gekko/wp0302_se_missile_pass_2.wav",
}
local TOPMISSILE_SND_LEVEL = 95

local WWEIGHT_MG             = 35
local WWEIGHT_MISSILE_SINGLE = 20
local WWEIGHT_MISSILE_DOUBLE = 5
local WWEIGHT_GRENADE        = 10
local WWEIGHT_TOPMISSILE     = 10
local WWEIGHT_TRACKMISSILE   = 2
local WWEIGHT_ORBITRPG       = 10
local WWEIGHT_NIKITA         = 8

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

-- FIX 1: Threshold lowered from 450 to 200.
-- The old value created a 0-449 unit dead zone where aerial mode never
-- engaged, leaving the Gekko on the broken ground-combat path while the
-- player stood on any roof or ledge. 200 units (roughly one floor of
-- architecture) is the correct trigger height.
local AERIAL_Z_THRESHOLD     = 200
local AERIAL_CHASE_INTERVAL  = 0.3
-- Interval between aerial weapon fires (VJ Base's own NextRangeAttackTime
-- governs ground cadence; this governs aerial-only intercept cadence).
local AERIAL_ATTACK_INTERVAL = 6.0
-- FIX 1b: Hysteresis reduced proportionally (was 300, ratio kept at ~60%).
local AERIAL_EXIT_HYSTERESIS = 120

-- Watchdog polls this often; only un-sticks IsAbleToRangeAttack,
-- never zeros any timer (zeroing timers re-triggers VJ Base instantly).
local WATCHDOG_INTERVAL      = 0.5
-- FIX 3: Grace cut from 2.0s to 0.3s.
-- 2.0s meant every stuck-attack cycle produced 2 full seconds of weapon
-- silence. 0.3s is long enough to never false-fire on a running MG burst,
-- but short enough to be imperceptible to the player.
local WATCHDOG_GRACE         = 0.3

-- ============================================================
--  Helpers
-- ============================================================
local function GekkoEffectiveDist( posA, posB )
    local dx = posA.x - posB.x
    local dy = posA.y - posB.y
    local dz = (posA.z - posB.z) * 0.4
    return math.sqrt( dx*dx + dy*dy + dz*dz )
end

local function Dist2D( posA, posB )
    local dx = posA.x - posB.x
    local dy = posA.y - posB.y
    return math.sqrt( dx*dx + dy*dy )
end

local function GetActiveEnemy( ent )
    local e = ent.VJ_TheEnemy
    if IsValid(e) then return e end
    e = ent:GetEnemy()
    if IsValid(e) then return e end
    return nil
end

local function RollWeapon()
    local r   = math.random(1, 100)
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

local function SpawnRocket( ent, attIdx, aimPos, spread )
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
    ent:EmitSound(ROCKET_SND_FIRE[math.random(#ROCKET_SND_FIRE)], ROCKET_SND_LEVEL, math.random(95, 110), 1)
end

local function SalvoSpread()
    return Vector(
        (math.random()-0.5)*2*SALVO_SPREAD_XY,
        (math.random()-0.5)*2*SALVO_SPREAD_XY,
        (math.random()-0.5)*2*SALVO_SPREAD_Z
    )
end

local function GLSparkAtAttachment( ent, shotIndex )
    local attIdx  = GL_SPARK_ATT_CYCLE[((shotIndex-1) % #GL_SPARK_ATT_CYCLE)+1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd = attData.Ang:Forward()
    local e = EffectData()
    e:SetOrigin(attData.Pos + fwd*4) ; e:SetNormal(fwd) ; e:SetEntity(ent)
    e:SetMagnitude(GL_SPARK_MAGNITUDE*GL_SPARK_SCALE) ; e:SetScale(GL_SPARK_SCALE) ; e:SetRadius(GL_SPARK_RADIUS)
    util.Effect("ManhackSparks", e)
end

local function GLVaporAtAttachment( ent, shotIndex )
    local attIdx  = GL_SPARK_ATT_CYCLE[((shotIndex-1) % #GL_SPARK_ATT_CYCLE)+1]
    local attData = ent:GetAttachment(attIdx)
    if not attData then return end
    local fwd    = attData.Ang:Forward()
    local origin = attData.Pos + fwd*6
    local ev = EffectData()
    ev:SetOrigin(origin) ; ev:SetNormal(fwd) ; ev:SetScale(GL_VAPOR_SCALE) ; ev:SetMagnitude(1)
    util.Effect(GL_VAPOR_EFFECT, ev)
    if (shotIndex % GL_SMOKE_EVERY) == 0 then
        local es = EffectData()
        es:SetOrigin(origin+Vector(0,0,8)) ; es:SetNormal(fwd) ; es:SetScale(GL_SMOKE_SCALE) ; es:SetMagnitude(1)
        util.Effect(GL_SMOKE_EFFECT, es)
    end
end

local function AttachGrenadeTrail( gren )
    if not IsValid(gren) then return end
    util.SpriteTrail(gren,0,GL_TRAIL_COLOR,false,GL_TRAIL_STARTSIZE,GL_TRAIL_ENDSIZE,
        GL_TRAIL_LIFETIME,1/GL_TRAIL_STARTSIZE,GL_TRAIL_MATERIAL)
end

local function RerollNotMissile( exclude )
    local reroll
    repeat reroll = RollWeapon() until reroll ~= exclude
    print("GekkoMissile Re-roll -> " .. reroll)
    return reroll
end

local function SendSonarLock( enemy )
    if not IsValid(enemy) then return end
    if not enemy:IsPlayer() then return end
    net.Start("GekkoSonarLock")
    net.Send(enemy)
end

-- ============================================================
--  Weapons
-- ============================================================
local function FireMGBurst( ent, enemy )
    if ent._mgBurstActive then return false end
    local aimPos   = enemy:GetPos() + Vector(0,0,40)
    local mgRounds = math.random(MG_ROUNDS_MIN, MG_ROUNDS_MAX)
    local mgSpread = math.Rand(MG_SPREAD_MIN, MG_SPREAD_MAX)
    ent._mgBurstActive = true
    ent._mgBurstEndT   = CurTime() + mgRounds * MG_INTERVAL + 1.0
    ent:SetNWBool("GekkoMGFiring", true)
    for i = 0, mgRounds-1 do
        local round = i
        timer.Simple(round * MG_INTERVAL, function()
            if not IsValid(ent) then return end
            local curEnemy = GetActiveEnemy(ent)
            local curAim   = IsValid(curEnemy) and (curEnemy:GetPos()+Vector(0,0,40)) or aimPos
            local src
            local mgAtt = ent:GetAttachment(ATT_MACHINEGUN)
            if mgAtt then
                src = mgAtt.Pos
            else
                local boneIdx = ent._GekkoLGunBone
                if boneIdx and boneIdx >= 0 then
                    local m = ent:GetBoneMatrix(boneIdx)
                    if m then src = m:GetTranslation() + m:GetForward()*28 end
                end
                src = src or (ent:GetPos()+Vector(0,0,200))
            end
            local dir = (curAim - src):GetNormalized()
            ent:FireBullets({
                Attacker = ent, Damage = MG_DAMAGE,
                Dir = dir, Src = src, AmmoType = "AR2",
                TracerName = "Tracer", Num = 1,
                Spread = Vector(mgSpread,mgSpread,mgSpread)
            })
            local eff = EffectData() ; eff:SetOrigin(src) ; eff:SetNormal(dir)
            util.Effect("MuzzleFlash", eff)
            ent:EmitSound(MG_SND_SHOTS[math.random(#MG_SND_SHOTS)], MG_SND_LEVEL, math.random(95, 115), 1)
            if (round + 1) % MG_CHAIN_EVERY == 0 then
                ent:EmitSound(MG_SND_CHAININSERT, MG_SND_LEVEL, 100, 1)
            end
            if round >= mgRounds-1 then
                ent._mgBurstActive = false
                ent:SetNWBool("GekkoMGFiring", false)
            end
        end)
    end
    return true
end

local function FireMissile( ent, enemy )
    local aimPos = enemy:GetPos() + Vector(0,0,40)
    ent._missileCount = (ent._missileCount or 0) + 1
    SpawnRocket(ent, (ent._missileCount%2==1) and ATT_MISSILE_L or ATT_MISSILE_R, aimPos, nil)
    return true
end

local function FireDoubleSalvo( ent, enemy )
    local aimPos = enemy:GetPos() + Vector(0,0,40)
    ent._missileCount = (ent._missileCount or 0) + 1
    SpawnRocket(ent, (ent._missileCount%2==1) and ATT_MISSILE_L or ATT_MISSILE_R, aimPos, SalvoSpread())
    timer.Simple(SALVO_DELAY, function()
        if not IsValid(ent) then return end
        local curEnemy = GetActiveEnemy(ent)
        local curAim   = IsValid(curEnemy) and (curEnemy:GetPos()+Vector(0,0,40)) or aimPos
        ent._missileCount = (ent._missileCount or 0) + 1
        SpawnRocket(ent, (ent._missileCount%2==1) and ATT_MISSILE_L or ATT_MISSILE_R, curAim, SalvoSpread())
    end)
    return true
end

local function FireGrenadeLauncher( ent, enemy )
    local count       = math.random(GL_COUNT_MIN, GL_COUNT_MAX)
    local grenadeType = GL_GRENADE_TYPES[math.random(#GL_GRENADE_TYPES)]
    local typeParams  = GL_TYPE_PARAMS[grenadeType] or GL_TYPE_DEFAULT
    ent._glSparkCounter = 0
    ent:EmitSound(GL_SOUND_FIDGET, 80, 100, 1)
    timer.Simple(GL_FIDGET_LEAD + (count-1)*GL_INTERVAL + 0.1, function()
        if not IsValid(ent) then return end
        ent:EmitSound(GL_SOUND_INSERT, 80, 100, 1)
    end)
    for i = 0, count-1 do
        local shotNumber = i+1
        timer.Simple(GL_FIDGET_LEAD + i*GL_INTERVAL, function()
            if not IsValid(ent) then return end
            local forward = ent:GetForward()
            local right   = ent:GetRight()
            local origin  = ent:GetPos() + Vector(0,0,GL_LAUNCH_Z)
            ent:EmitSound(GL_SOUND_FIRE, 80, math.random(95, 105), 1)
            GLSparkAtAttachment(ent, shotNumber)
            GLVaporAtAttachment(ent, shotNumber)
            local scatter    = forward * math.Rand(300,700) + right * math.random(-0.5,2*GL_SPREAD_Y)
            local spawnPos   = origin + scatter*0.05
            local launchDir  = scatter:GetNormalized()
            launchDir.z = launchDir.z + typeParams.loft
            launchDir:Normalize()
            local mf = EffectData()
            mf:SetOrigin(spawnPos) ; mf:SetNormal(launchDir) ; mf:SetScale(GL_MUZZLE_FLASH_SCALE)
            util.Effect("MuzzleFlash", mf)
            local gren = ents.Create(grenadeType)
            if IsValid(gren) then
                gren:SetPos(spawnPos) ; gren:SetAngles(launchDir:Angle())
                gren:SetOwner(ent) ; gren:Spawn() ; gren:Activate()
                local phys = gren:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(launchDir * typeParams.speed)
                    phys:SetAngleVelocity(Vector(math.Rand(-200,200),math.Rand(-200,200),math.Rand(-200,200)))
                end
                AttachGrenadeTrail(gren)
            end
        end)
    end
    return true
end

local function FireOrbitRpg( ent, enemy )
    ent._missileCount = (ent._missileCount or 0) + 1
    local attIdx  = (ent._missileCount%2==1) and ATT_MISSILE_L or ATT_MISSILE_R
    local attData = ent:GetAttachment(attIdx)
    local src     = attData and attData.Pos or (ent:GetPos()+Vector(0,0,160))
    local aimPos  = enemy:GetPos() + Vector(0,0,40)
    local dir     = (aimPos - src):GetNormalized()
    local eff = EffectData()
    eff:SetOrigin(src) ; eff:SetNormal(dir) ; eff:SetScale(0.6) ; eff:SetMagnitude(1)
    util.Effect("SmokeEffect", eff)
    ent:EmitSound(KORNET_SND_SHOTS[math.random(#KORNET_SND_SHOTS)],   KORNET_SND_LEVEL, math.random(95, 105), 1)
    ent:EmitSound(KORNET_SND_LAUNCHES[math.random(#KORNET_SND_LAUNCHES)], KORNET_SND_LEVEL, 100, 1)
    local rpg = ents.Create("sent_orbital_rpg")
    if not IsValid(rpg) then
        print("GekkoORBIT ERROR: sent_orbital_rpg create failed -- falling back")
        return FireMissile(ent, enemy)
    end
    rpg:SetPos(src) ; rpg:SetAngles(dir:Angle()) ; rpg:SetOwner(ent)
    rpg:Spawn() ; rpg:Activate()
    print(string.format("[GekkoORBIT] Launched | att=%d dist=%.0f", attIdx, ent:GetPos():Distance(enemy:GetPos())))
    return true
end

local function FireTopMissile( ent, enemy )
    local dist = GekkoEffectiveDist(ent:GetPos(), enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        local alt = RerollNotMissile("TOPMISSILE")
        if     alt == "MG"          then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE"     then return FireMissile(ent, enemy)
        elseif alt == "SALVO"       then return FireDoubleSalvo(ent, enemy)
        elseif alt == "ORBITRPG"    then return FireOrbitRpg(ent, enemy)
        else                             return FireGrenadeLauncher(ent, enemy) end
    end
    sound.Play(MISSILE_SOUND_WARN, ent:GetPos(), 511, 60)
    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
    local toTarget2D = enemy:GetPos()-ent:GetPos() ; toTarget2D.z=0 ; toTarget2D:Normalize()
    local launchPos  = ent:GetPos() + toTarget2D*MISSILE_SPAWN_FORWARD + Vector(0,0,TOPMISSILE_LAUNCH_Z)
    local faceAng    = (enemy:GetPos()-launchPos):GetNormalized():Angle() ; faceAng.p=0
    local missile = ents.Create("sent_npc_topmissile")
    if not IsValid(missile) then return FireGrenadeLauncher(ent,enemy) end
    missile.Owner  = ent
    missile.Target = enemy:GetPos() + Vector(0,0,40)
    missile:SetPos(launchPos) ; missile:SetAngles(faceAng)
    missile:Spawn() ; missile:Activate()
    return true
end

local function FireTrackMissile( ent, enemy )
    local dist = GekkoEffectiveDist(ent:GetPos(), enemy:GetPos())
    if dist < MISSILE_MIN_DIST then
        local alt = RerollNotMissile("TRACKMISSILE")
        if     alt == "MG"          then return FireMGBurst(ent, enemy)
        elseif alt == "MISSILE"     then return FireMissile(ent, enemy)
        elseif alt == "SALVO"       then return FireDoubleSalvo(ent, enemy)
        elseif alt == "TOPMISSILE"  then return FireTopMissile(ent, enemy)
        elseif alt == "ORBITRPG"    then return FireOrbitRpg(ent, enemy)
        else                             return FireGrenadeLauncher(ent, enemy) end
    end
    SendSonarLock(enemy)
    sound.Play(MISSILE_SOUND_WARN, ent:GetPos(), 511, 60)
    ent:EmitSound(TOPMISSILE_SND_FIRE[math.random(#TOPMISSILE_SND_FIRE)], TOPMISSILE_SND_LEVEL, math.random(95, 110), 1)
    local toTarget2D = enemy:GetPos()-ent:GetPos() ; toTarget2D.z=0 ; toTarget2D:Normalize()
    local launchPos  = ent:GetPos() + toTarget2D*MISSILE_SPAWN_FORWARD + Vector(0,0,TOPMISSILE_LAUNCH_Z)
    local faceAng    = (enemy:GetPos()-launchPos):GetNormalized():Angle() ; faceAng.p=0
    local missile = ents.Create("sent_npc_trackmissile")
    if not IsValid(missile) then return FireGrenadeLauncher(ent,enemy) end
    missile.Owner    = ent
    missile.Target   = enemy:GetPos() + Vector(0,0,40)
    missile.TrackEnt = enemy
    missile:SetPos(launchPos) ; missile:SetAngles(faceAng)
    missile:Spawn() ; missile:Activate()
    return true
end

local function NikitaMuzzleSmoke( ent )
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
            ed:SetOrigin(pos + normal * i * 4)
            ed:SetNormal(normal)
            ed:SetScale(NIKITA_MUZZLE_SMOKE_SCALE)
            ed:SetMagnitude(1)
            util.Effect("SmokeEffect", ed)
        end)
    end
end

local function FireNikita( ent, enemy )
    local dist = GekkoEffectiveDist(ent:GetPos(), enemy:GetPos())
    if dist < NIKITA_MIN_DIST then return FireMGBurst(ent, enemy) end
    NikitaMuzzleSmoke(ent)
    local toTarget2D = enemy:GetPos() - ent:GetPos()
    toTarget2D.z = 0
    if toTarget2D:Length() > 0 then toTarget2D:Normalize() end
    local spawnPos  = ent:GetPos() + toTarget2D * NIKITA_SPAWN_FORWARD + Vector(0, 0, NIKITA_SPAWN_Z)
    local aimPos    = enemy:GetPos() + Vector(0, 0, 40)
    local launchDir = (aimPos - spawnPos):GetNormalized()
    local nikita    = ents.Create("npc_vj_gekko_nikita")
    if not IsValid(nikita) then return FireMissile(ent, enemy) end
    nikita:SetPos(spawnPos)
    nikita:SetAngles(launchDir:Angle())
    nikita:SetOwner(ent)
    nikita._NikitaOwner    = ent
    nikita._NikitaTargetEnt = enemy
    nikita:Spawn()
    nikita:Activate()
    if IsValid(enemy) then
        if nikita.VJDoSetEnemy then
            nikita:VJDoSetEnemy(enemy, true, true)
        else
            nikita:SetEnemy(enemy)
        end
    end
    return true
end

-- ============================================================
--  Dispatch helper used by both ground Execute and aerial
--  PreInit intercept paths.
-- ============================================================
local function GekkoFireWeapon( ent, enemy )
    local choice = RollWeapon()
    ent._lastWeaponChoice = choice
    print("GekkoFire: " .. choice)
    if     choice == "MG"          then return FireMGBurst(ent, enemy)
    elseif choice == "MISSILE"     then return FireMissile(ent, enemy)
    elseif choice == "SALVO"       then return FireDoubleSalvo(ent, enemy)
    elseif choice == "TOPMISSILE"  then return FireTopMissile(ent, enemy)
    elseif choice == "TRACKMISSILE"then return FireTrackMissile(ent, enemy)
    elseif choice == "ORBITRPG"    then return FireOrbitRpg(ent, enemy)
    elseif choice == "NIKITA"      then return FireNikita(ent, enemy)
    else                                return FireGrenadeLauncher(ent, enemy) end
end

-- ============================================================
--  Attack readiness reset.  Only un-sticks the boolean gate
--  and clears AttackType.
--  NEVER zeros NextRangeAttackTime or NextAnyAttackTime_Range
--  -- doing so would re-trigger VJ Base's fire cycle instantly.
-- ============================================================
function ENT:GekkoResetAttackReadiness()
    local sd = self:GetTable()
    if not sd then return end
    sd.IsAbleToRangeAttack = true
    sd.AttackType          = 0
    -- If the attack deadline has already passed, give VJ Base a short
    -- window (0.5s) so it reschedules normally without firing instantly.
    local now = CurTime()
    if (sd.NextRangeAttackTime or 0) < now then
        sd.NextRangeAttackTime = now + 0.5
    end
    print("GekkoReset: IsAbleToRangeAttack un-stuck")
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

function ENT:SetAnimationTranslations()
    if not self.AnimationTranslations then self.AnimationTranslations = {} end
    local walkSeq = self:LookupSequence("walk")
    local runSeq  = self:LookupSequence("run")
    local idleSeq = self:LookupSequence("idle")
    walkSeq = (walkSeq and walkSeq >= -1) and walkSeq or 0
    runSeq  = (runSeq  and runSeq  >= -1) and runSeq  or 0
    idleSeq = (idleSeq and idleSeq >= -1) and idleSeq or 0
    self.AnimationTranslations[ACT_IDLE]               = idleSeq
    self.AnimationTranslations[ACT_WALK]               = walkSeq
    self.AnimationTranslations[ACT_RUN]                = runSeq
    self.AnimationTranslations[ACT_WALK_AIM]           = walkSeq
    self.AnimationTranslations[ACT_RUN_AIM]            = runSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK1]      = idleSeq
    self.AnimationTranslations[ACT_RANGE_ATTACK2]      = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK1] = idleSeq
    self.AnimationTranslations[ACT_GESTURE_RANGE_ATTACK2] = idleSeq
    self.AnimationTranslations[ACT_IDLE_ANGRY]         = idleSeq
    self.AnimationTranslations[ACT_COMBAT_IDLE]        = idleSeq
    self._GekkoSeqWalk  = walkSeq
    self._GekkoSeqRun   = runSeq
    self._GekkoSeqIdle  = idleSeq
end

function ENT:GekkoUpdateAnimation()
    if self._Flinching then return end
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
    if self._gekkoSkipAnimTick then self._gekkoSkipAnimTick = false ; return end
    local jumpState = self:GetGekkoJumpState()
    if jumpState == self.JUMP_RISING or jumpState == self.JUMP_FALLING or jumpState == self.JUMP_LAND
       or (self._gekkoJustJumped and now < self._gekkoJustJumped) then
        self:SetPoseParameter("movex", 0)
        self:SetPoseParameter("movey", 0)
        return
    end
    if self:GeckoCrouchUpdate() then return end
    local enemy = GetActiveEnemy(self)
    local dist  = 0
    if IsValid(enemy) then
        dist = self:GetPos():Distance(enemy:GetPos())
        self._gekkoLastEnemyDist = dist
    elseif self._gekkoLastEnemyDist then
        dist = self._gekkoLastEnemyDist
    end
    if dist > RUN_ENGAGE_DIST    then self._gekkoRunning = true  end
    if dist < RUN_DISENGAGE_DIST then self._gekkoRunning = false end
    local targetSeq, arate
    if vel > 5 then
        if self._gekkoRunning then
            targetSeq = self._GekkoSeqRun  ; arate = vel / ANIM_RUN_SPEED
        else
            targetSeq = self._GekkoSeqWalk ; arate = vel / ANIM_WALK_SPEED
        end
    elseif self._gekkoRunning then
        targetSeq = self._GekkoSeqRun  ; arate = 0.5
    else
        targetSeq = self._GekkoSeqIdle ; arate = 1.0
    end
    arate = math.Clamp(arate, 0.5, 3.0)
    if targetSeq and targetSeq ~= -1 then
        if self._gekkoCurrentLocoSeq ~= targetSeq then
            self._gekkoCurrentLocoSeq = targetSeq
            self:ResetSequence(targetSeq)
        end
    end
    if     targetSeq == self._GekkoSeqRun  then self._GekkoLastSeqName = "run"
    elseif targetSeq == self._GekkoSeqWalk then self._GekkoLastSeqName = "walk"
    else                                         self._GekkoLastSeqName = "idle" end
    self._GekkoLastSeqIdx  = targetSeq
    self._gekkoTargetRate  = arate
    local smoothed = Lerp(FrameTime() * RATE_SMOOTH_SPEED, self:GetPlaybackRate(), self._gekkoTargetRate)
    self:SetPlaybackRate(smoothed)
    self:SetNWEntity("GekkoEnemy", IsValid(enemy) and enemy or NULL)
end

local function SafeInitVJTables( ent )
    if not ent.VJAddOnDamage   then ent.VJAddOnDamage   = {} end
    if not ent.VJDamageInfos   then ent.VJDamageInfos   = {} end
    if not ent.VJDeathSounds   then ent.VJDeathSounds   = {} end
    if not ent.VJPainSounds    then ent.VJPainSounds    = {} end
    if not ent.VJIdleSounds    then ent.VJIdleSounds    = {} end
    if not ent.VJFootstepSounds then ent.VJFootstepSounds = {} end
    if not ent.AnimationTranslations then ent.AnimationTranslations = {} end
end

function ENT:Initialize()
    self:SetCollisionBounds(Vector(-64,-64,0), Vector(64,64,200))
    self:SetSkin(1)
    self._GekkoSpineBone    = self:LookupBone("bip_spine_4") or -1
    self._GekkoLGunBone     = self:LookupBone("b_lgunrack")  or -1
    self._GekkoRGunBone     = self:LookupBone("b_rgunrack")  or -1
    self._GekkoNextDebugT   = 0
    self._GekkoLastSeqName  = ""
    self._GekkoLastSeqIdx   = -1
    self._missileCount      = 0
    self._mgBurstActive     = false
    self._mgBurstEndT       = 0
    self._gekkoRunning      = false
    self._gekkoLastEnemyDist = nil
    self._gekkoLastPos      = self:GetPos()
    self._gekkoLastTime     = CurTime() - 0.1
    self._gekkoSuppressActivity = 0
    self._gekkoSkipAnimTick = false
    self._crushHitTimes     = {}
    self._bloodSplatPulse   = 0
    self._gibCooldownT      = 0
    self._lastWeaponChoice  = ""
    self._glSparkCounter    = 0
    self._gekkoCurrentLocoSeq = -1
    self._gekkoTargetRate   = 1.0
    self.GekkoLastVisibleTime   = 0
    -- FIX: All aerial-mode fields use the underscore prefix consistently.
    -- Initialising them here ensures a clean state on every spawn/re-activate
    -- and prevents stale values carrying over across entity re-use.
    self._gekkoAerialMode        = false
    self._gekkoNextChaseOverride = 0
    self._gekkoNextAerialAtk     = 0
    self._gekkoNextWatchdog      = 0
    self:SetNWBool("GekkoMGFiring",     false)
    self:SetNWInt("GekkoJumpDust",      0)
    self:SetNWInt("GekkoLandDust",      0)
    self:SetNWInt("GekkoFK360LandDust", 0)
    self:SetNWInt("GekkoBloodSplat",    0)
    SafeInitVJTables(self)
    self:GekkoJumpInit()
    self:GekkoTargetJumpInit()
    self:GeckoCrouchInit()
    self:GekkoLegsInit()
    self:SetViewOffset(Vector(0, 0, 180))
    local selfRef = self
    timer.Simple(0, function()
        if not IsValid(selfRef) then return end
        selfRef._StartMoveSpeed  = selfRef.MoveSpeed  or 150
        selfRef._StartRunSpeed   = selfRef.RunSpeed   or 300
        selfRef._StartWalkSpeed  = selfRef.WalkSpeed  or 150
        local walkSeq = selfRef:LookupSequence("walk")
        local runSeq  = selfRef:LookupSequence("run")
        local idleSeq = selfRef:LookupSequence("idle")
        selfRef._GekkoSeqWalk = (walkSeq and walkSeq >= -1) and walkSeq or 0
        selfRef._GekkoSeqRun  = (runSeq  and runSeq  >= -1) and runSeq  or 0
        selfRef._GekkoSeqIdle = (idleSeq and idleSeq >= -1) and idleSeq or 0
        selfRef._gekkoCurrentLocoSeq = -1
        selfRef:GeckoCrouchCacheSeqs()
        selfRef:SetAnimationTranslations()
        selfRef._GekkoSpineBone = selfRef:LookupBone("bip_spine_4") or -1
        selfRef._GekkoLGunBone  = selfRef:LookupBone("b_lgunrack")  or -1
        selfRef._GekkoRGunBone  = selfRef:LookupBone("b_rgunrack")  or -1
        selfRef:GekkoJumpActivate()
        print("GekkoNPC Activated | walk="..selfRef._GekkoSeqWalk.." run="..selfRef._GekkoSeqRun.." idle="..selfRef._GekkoSeqIdle)
    end)
    -- Guarantee OnThink runs even if VJ Base stops calling it
    timer.Create("GekkoThink_" .. self:EntIndex(), 0.1, 0, function()
        if not IsValid(self) then timer.Remove("GekkoThink_" .. self:EntIndex()) ; return end
        self:OnThink()
    end)
end

function ENT:Activate()
    local base = self.BaseClass
    if base and base.Activate and base.Activate ~= ENT.Activate then
        base.Activate(self)
    end
    SafeInitVJTables(self)
end

function ENT:GetShootPos()
    return self:GetPos() + Vector(0, 0, 180)
end

function ENT:OnTakeDamage( dmginfo )
    dmginfo:SetDamageForce(Vector(0,0,0))
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
    if hitPos.z > headZ then
        dmginfo:ScaleDamage(1/3)
    end
    local rawDmg = dmginfo:GetDamage()
    local doSplat
    if self._gekkoLegsDisabled then
        doSplat = math.Rand(0,1) < GROUNDED_BLEED_CHANCE
    else
        doSplat = math.random(1,BLOOD_RANDOM_CHANCE) == 1 or rawDmg > BLOOD_DAMAGE_THRESHOLD
    end
    if doSplat then
        self._bloodSplatPulse = (self._bloodSplatPulse or 0) + 1
        local variant = math.random(1,5)
        self:SetNWInt("GekkoBloodSplat", (self._bloodSplatPulse % 8) * 5 + (variant-1))
    end
    self:GekkoLegsOnDamage(dmginfo)
    self:GekkoGibOnDamage(rawDmg, dmginfo)
    dmginfo:SetDamagePosition(self:GetPos())
    self.BaseClass.OnTakeDamage(self, dmginfo)
end

-- ============================================================
--  LOS grace used by OnThinkAttack
-- ============================================================
function ENT:OnThinkAttack( isAttacking, enemy )
    if IsValid(enemy) and self:Visible(enemy) then
        self.GekkoLastVisibleTime = CurTime()
    end
end

-- ============================================================
--  OnRangeAttack
--
--  This is the SINGLE chokepoint that decides whether VJ Base
--  fires or we fire ourselves.
--
--  AERIAL mode (player is AERIAL_Z_THRESHOLD units above):
--    We own the cadence via _gekkoNextAerialAtk.
--    Fire ourselves then return TRUE to fully suppress VJ Base.
--    If the aerial cooldown hasn't expired, still return TRUE
--    so VJ Base stays blocked until we're ready.
--
--  GROUND mode:
--    Return FALSE unconditionally so VJ Base's state machine
--    continues normally to OnRangeAttackExecute.
--    Do NOT fire here -- OnRangeAttackExecute does it.
-- ============================================================
function ENT:OnRangeAttack( status, enemy )
    if status ~= "PreInit" then return end
    if not IsValid(enemy) then return true end  -- no target: suppress

    if self._gekkoAerialMode then
        local now = CurTime()
        if now >= self._gekkoNextAerialAtk then
            local fired = GekkoFireWeapon(self, enemy)
            self._gekkoNextAerialAtk = now + (fired and AERIAL_ATTACK_INTERVAL or 2.0)
            print(string.format("[GekkoAerial] Fired | next=%.1f", self._gekkoNextAerialAtk))
        else
            print(string.format("[GekkoAerial] Blocked (cooldown %.1fs left)",
                self._gekkoNextAerialAtk - now))
        end
        return true  -- always suppress VJ Base in aerial mode
    end

    -- Ground: let VJ Base run through to OnRangeAttackExecute
    return false
end

-- ============================================================
--  AERIAL CHASE SYSTEM
--  Keeps the Gekko pathing toward the ground projection of an
--  elevated enemy, and manages the aerial mode flag.
-- ============================================================
function ENT:GekkoAerialChase_Think( enemy )
    local myPos  = self:GetPos()
    local enePos = enemy:GetPos()
    local dz     = enePos.z - myPos.z

    local enterThresh = AERIAL_Z_THRESHOLD
    local exitThresh  = AERIAL_Z_THRESHOLD - AERIAL_EXIT_HYSTERESIS

    if self._gekkoAerialMode then
        if dz < exitThresh then
            self._gekkoAerialMode = false
            self:GekkoResetAttackReadiness()
            print("[GekkoAerial] EXIT | dz=" .. math.floor(dz))
            return false
        end
    else
        if dz < enterThresh then return false end
        self._gekkoAerialMode        = true
        self._gekkoNextChaseOverride = 0
        self._gekkoNextAerialAtk     = CurTime() + 1.0
        print("[GekkoAerial] ENTER | dz=" .. math.floor(dz))
    end

    local groundWaypoint = Vector(enePos.x, enePos.y, myPos.z)
    if (groundWaypoint - myPos):Length() < 32 then
        groundWaypoint = myPos + self:GetForward() * 128
    end
    -- Nav uses the ground projection so the Gekko walks under the player.
    self:UpdateEnemyMemory(enemy, groundWaypoint)

    local selfData = self:GetTable()
    if selfData and selfData.EnemyData then
        selfData.EnemyData.VisibleTime = CurTime()
        selfData.EnemyData.Visible     = true
        -- FIX 2: Use Z-weighted effective distance, not flat 2D.
        -- Dist2D was causing VJ Base's scheduler to treat a directly
        -- overhead enemy as "very close", misfiring its distance guards.
        selfData.EnemyData.Distance    = GekkoEffectiveDist(myPos, enePos)
        -- FIX 2b: VisiblePos must point at the REAL enemy position, not
        -- the ground projection. Weapon systems read VisiblePos for aim;
        -- writing the floor coord here was sending rockets into the ground
        -- and confusing VJ Base's secondary dot-product checks.
        selfData.EnemyData.VisiblePos  = enePos
    end

    local now = CurTime()
    if now >= self._gekkoNextChaseOverride then
        self._gekkoNextChaseOverride = now + AERIAL_CHASE_INTERVAL
        self:MaintainAlertBehavior(true)
    end

    return true
end

-- ============================================================
--  Watchdog
--  Polls every WATCHDOG_INTERVAL seconds.
--  ONLY un-sticks IsAbleToRangeAttack if it has been false
--  for longer than WATCHDOG_GRACE seconds past its deadline.
--  Never touches NextRangeAttackTime or any other timer.
-- ============================================================
function ENT:GekkoWatchdogThink( enemy )
    local now = CurTime()
    if now < self._gekkoNextWatchdog then return end
    self._gekkoNextWatchdog = now + WATCHDOG_INTERVAL

    if not IsValid(enemy) then return end
    if self._mgBurstActive  then return end

    local sd = self:GetTable()
    if not sd then return end

    if sd.IsAbleToRangeAttack == false then
        local deadline = sd.NextRangeAttackTime or 0
        if now > deadline + WATCHDOG_GRACE then
            print(string.format(
                "[GekkoWatchdog] Stuck false for %.1fs past deadline -- un-sticking",
                now - deadline))
            self:GekkoResetAttackReadiness()
        end
    end
end

-- ============================================================
--  OnThink
-- ============================================================
function ENT:OnThink()
    if self._gekkoLegsDisabled then self:GekkoLegsThink() end

    if self._mgBurstActive and CurTime() > self._mgBurstEndT then
        self._mgBurstActive = false
        self:SetNWBool("GekkoMGFiring", false)
    end

    local enemy = GetActiveEnemy(self)
    if IsValid(enemy) then
        self:GekkoAerialChase_Think(enemy)
        self:GekkoWatchdogThink(enemy)
    elseif self._gekkoAerialMode then
        -- FIX: aerial mode MUST be cleared when there is no valid enemy.
        -- Without this, losing the target while airborne would leave
        -- _gekkoAerialMode=true forever, permanently suppressing VJ Base.
        self._gekkoAerialMode = false
        self:GekkoResetAttackReadiness()
    end

    self:GekkoJumpThink()
    if not self._gekkoAerialMode then
        self:GekkoTargetJumpThink()
    end

    self:GekkoUpdateAnimation()
    self:GeckoCrushThink()

    if CurTime() > self._GekkoNextDebugT then
        local dist, src
        if IsValid(enemy) then
            dist = math.floor(self:GetPos():Distance(enemy:GetPos()))
            src  = IsValid(self.VJ_TheEnemy) and "vj" or "engine"
        elseif self._gekkoLastEnemyDist then
            dist = math.floor(self._gekkoLastEnemyDist) ; src = "cached"
        else
            dist = -1 ; src = "none"
        end
        local sd   = self:GetTable()
        local able = sd and tostring(sd.IsAbleToRangeAttack) or "?"
        local nrat = sd and string.format("%.1f", sd.NextRangeAttackTime or 0) or "?"
        print(string.format(
            "[GekkoDBG] seq=%s run=%s dist=%d(%s) jump=%s mgActive=%s lastWpn=%s aerial=%s ableRng=%s nrat=%s",
            tostring(self._GekkoLastSeqName), tostring(self._gekkoRunning), dist, src,
            JUMP_STATE_NAMES[self:GetGekkoJumpState()] or "?",
            tostring(self._mgBurstActive), tostring(self._lastWeaponChoice),
            tostring(self._gekkoAerialMode), able, nrat))
        self._GekkoNextDebugT = CurTime() + 1
    end
end

-- ============================================================
--  OnRangeAttackExecute  (ground mode only)
--  VJ Base calls this after PreInit returns false.
--  This is the one and only ground fire path.
-- ============================================================
function ENT:OnRangeAttackExecute( status, enemy, projectile )
    if status ~= "Init" then return end
    if not IsValid(enemy) then return true end
    return GekkoFireWeapon(self, enemy)
end

-- ============================================================
--  Death
-- ============================================================
function ENT:OnDeath( dmginfo, hitgroup, status )
    if status ~= "Finish" then return end
    timer.Remove("GekkoThink_" .. self:EntIndex())
    local attacker = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos      = self:GetPos()
    self:SetGekkoJumpState(self.JUMP_NONE)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetNWBool("GekkoMGFiring", false)
    -- FIX: clear the aerial-mode flag on death using the correct underscore field.
    -- Without this, a Gekko that dies while _gekkoAerialMode=true would re-animate
    -- from a dirty state if the entity slot is reused.
    self._gekkoAerialMode = false
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
