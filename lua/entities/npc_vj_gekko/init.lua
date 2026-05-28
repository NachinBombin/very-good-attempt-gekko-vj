-- ============================================================
-- npc_vj_gekko / init.lua
-- INTEGRATED WITH: Juicy Bleeding Effect (Hemo-fluid-stream)
-- NEW BLEEDING TYPE: gekko_juicy_bleeding (NPC-specific viscous stream)
-- SERVER-SIDE LOGIC ONLY
-- ============================================================
if CLIENT then return end

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("elastic_cl.lua")
AddCSLuaFile("hit_react_cl.lua")
AddCSLuaFile("cl_aps.lua")
AddCSLuaFile("bullet_impact_system.lua")

include("shared.lua")
include("crouch_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("flinch_system.lua")
include("gib_system.lua")
include("elastic_system.lua")
include("leg_disable_system.lua")
include("mg_shell_system.lua")
include("muzzleflash_system.lua")
include("aps_system.lua")
include("crush_system.lua")
include("pedestal_dodge_system.lua")
include("death_pose_system.lua")

-- ============================================================
-- JUICY BLEEDING INTEGRATION
-- ============================================================
local GekkoTriggerJuicyBleed = nil
local function SafeInitVJTables(ent)
    if not ent.VJ_AddSoundFile then
        ent.VJ_SoundFiles = ent.VJ_SoundFiles or {}
    end
end

-- ============================================================
-- Attempt to load the juicy bleeding module
-- ============================================================
local function TryLoadJuicyBleed()
    local modPath = "gekko_juicy_bleeding/gekko_bleeding_module.lua"
    if file.Exists("lua/" .. modPath, "GAME") then
        local ok, mod = pcall(include, modPath)
        if ok and type(mod) == "table" and mod.TriggerBleed then
            GekkoTriggerJuicyBleed = mod.TriggerBleed
            print("[GekkoNPC] Juicy bleed module loaded OK")
        else
            print("[GekkoNPC] Juicy bleed module load failed: " .. tostring(mod))
        end
    else
        print("[GekkoNPC] Juicy bleed module not found at: lua/" .. modPath)
    end
end
TryLoadJuicyBleed()

-- ============================================================
-- CONSTANTS
-- ============================================================
local HEAD_Z_FRACTION       = 0.82
local HIT_IMPULSE_SCALE     = 0.15
local HIT_IMPULSE_MAX       = 120
local ATT_MACHINEGUN        = "muzzle_mg"
local ATT_MISSILE_L         = "muzzle_missile_l"
local ATT_MISSILE_R         = "muzzle_missile_r"
local MG_INTERVAL           = 0.09
local MG_ROUNDS_MIN         = 6
local MG_ROUNDS_MAX         = 14
local MG_SPREAD_MIN         = 0.04
local MG_SPREAD_MAX         = 0.10
local MG_DAMAGE             = 12
local BUSHMASTER_DAMAGE      = 55
local BUSHMASTER_INTERVAL    = 0.55
local BUSHMASTER_SPREAD      = 0.02
local RUN_ENGAGE_DIST        = 900
local RUN_DISENGAGE_DIST     = 600
local ANIM_RUN_SPEED         = 300
local ANIM_WALK_SPEED        = 150
local SPRINT_ENGAGE_DIST     = 1400
local SPRINT_DISENGAGE_DIST  = 900
local SPRINT_ANIM_SPEED      = 450
local SPRINT_MOVE_SPEED      = 320
local ROCKET_ENGAGE_DIST_MIN = 600
local ROCKET_ENGAGE_DIST_MAX = 3000
local ROCKET_INTERVAL        = 5.0
local ROCKET_SPEED           = 1100
local ROCKET_DAMAGE          = 110
local GL_VAPOR_EFFECT        = "SmokeEffect"
local GL_SMOKE_EFFECT        = "smokesprites_0001"

local BLOOD_DAMAGE_THRESHOLD = 20
local BLOOD_RANDOM_CHANCE = 80

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

local function ShouldJuicyBleed(dmginfo)
    if not dmginfo:IsBulletDamage() then return false end
    local dmg = dmginfo:GetDamage()
    if dmg < BLOOD_DAMAGE_THRESHOLD then
        return math.random(1, 100) <= BLOOD_RANDOM_CHANCE
    end
    return true
end

-- ============================================================
-- SPRINT
-- ============================================================
local function GekkoSprint_Think(ent)
    if ent._gekkoSprintCooldown and CurTime() < ent._gekkoSprintCooldown then return end
    local enemy = GetActiveEnemy(ent)
    if not IsValid(enemy) then
        ent._gekkoSprinting = false
        ent.MoveSpeed = ent.StartMoveSpeed or 150
        return
    end
    local dist = ent:GetPos():Distance(enemy:GetPos())
    if not ent._gekkoSprinting then
        if dist > SPRINT_ENGAGE_DIST then
            ent._gekkoSprinting = true
            ent.MoveSpeed = SPRINT_MOVE_SPEED
        end
    else
        if dist < SPRINT_DISENGAGE_DIST then
            ent._gekkoSprinting = false
            ent.MoveSpeed = ent.StartMoveSpeed or 150
            ent._gekkoSprintCooldown = CurTime() + 3.0
        end
    end
end

-- ============================================================
-- HIT IMPULSE
-- ============================================================
local function GekkoApplyHitImpulse(ent, hitDir, damage)
    local force = math.min(damage * HIT_IMPULSE_SCALE, HIT_IMPULSE_MAX)
    local vel   = ent:GetVelocity()
    vel = vel + hitDir * force
    ent:SetVelocity(vel)
end

-- ============================================================
-- MUZZLE FLASH (MG)
-- ============================================================
local function FireMGMuzzle(ent)
    local att = ent:GetAttachment(ent:LookupAttachment(ATT_MACHINEGUN))
    if not att then return end
    local src = att.Pos
    local dir = att.Ang:Forward()
    local eff = EffectData(); eff:SetOrigin(src); eff:SetNormal(dir)
    util.Effect("MuzzleFlash", eff)
    ent:GekkoMG_SendImpactLight(src, dir, 1)
end

-- ============================================================
-- SNAP ANGLES
-- ============================================================
local function SnapToEnemy(ent, enemy)
    if not IsValid(enemy) then return end
    local dir = (enemy:GetPos() - ent:GetPos()):GetNormalized()
    dir.z = 0
    local ang = dir:Angle()
    ent:SetAngles(ang)
end

-- ============================================================
-- BUSHMASTER CANNON
-- ============================================================
local function FireBushmasterRound(ent, enemy)
    local att = ent:GetAttachment(ent:LookupAttachment(ATT_MACHINEGUN))
    if not att then return end
    SnapToEnemy(ent, enemy)
    local src    = att.Pos
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local dir    = (aimPos - src):GetNormalized()
    local spread = Vector(
        math.Rand(-BUSHMASTER_SPREAD, BUSHMASTER_SPREAD),
        math.Rand(-BUSHMASTER_SPREAD, BUSHMASTER_SPREAD),
        0
    )
    dir = (dir + spread):GetNormalized()
    local tr = util.TraceLine({
        start  = src,
        endpos = src + dir * 4000,
        filter = ent,
        mask   = MASK_SHOT,
    })
    local mf = EffectData()
    mf:SetOrigin(src)
    mf:SetNormal(dir)
    util.Effect("MuzzleFlash", mf)
    ent:GekkoMG_SendImpactLight(src, dir, 2)
    if tr.Hit and IsValid(tr.Entity) and tr.Entity:IsNPC() == false then
        tr.Entity:TakeDamage(BUSHMASTER_DAMAGE, ent, ent)
    elseif tr.Hit and IsValid(tr.Entity) then
        tr.Entity:TakeDamage(BUSHMASTER_DAMAGE, ent, ent)
    end
    local eff = EffectData()
    eff:SetOrigin(tr.HitPos)
    eff:SetNormal(tr.HitNormal)
    eff:SetScale(0.6); eff:SetMagnitude(1)
    util.Effect("SmokeEffect", eff)
end

-- ============================================================
-- ROCKET ATTACK
-- ============================================================
local function FireRocket(ent, enemy)
    if not IsValid(enemy) then return end
    SnapToEnemy(ent, enemy)
    local function LaunchFromAtt(attName)
        local attIdx = ent:LookupAttachment(attName)
        if not attIdx or attIdx == 0 then return end
        local att = ent:GetAttachment(attIdx)
        if not att then return end
        local rocket = ents.Create("obj_gekko_rocket")
        if not IsValid(rocket) then return end
        local src    = att.Pos
        local aimPos = enemy:GetPos() + Vector(0, 0, 40)
        local dir    = (aimPos - src):GetNormalized()
        rocket:SetPos(src)
        rocket:SetAngles(dir:Angle())
        rocket:Spawn()
        rocket:SetOwner(ent)
        rocket:GetPhysicsObject():SetVelocity(dir * ROCKET_SPEED)
        local eff = EffectData()
        eff:SetOrigin(src); eff:SetNormal(dir)
        eff:SetScale(1.5); eff:SetMagnitude(2)
        util.Effect("MuzzleFlash", eff)
        local smoke = EffectData()
        smoke:SetOrigin(src); smoke:SetNormal(dir)
        smoke:SetScale(1); smoke:SetMagnitude(1)
        util.Effect("SmokeEffect", smoke)
    end
    LaunchFromAtt(ATT_MISSILE_L)
    LaunchFromAtt(ATT_MISSILE_R)
end

-- ============================================================
-- GRENADE LAUNCHER
-- ============================================================
local function FireGL(ent, enemy)
    if not IsValid(enemy) then return end
    SnapToEnemy(ent, enemy)
    local attIdx = ent:LookupAttachment(ATT_MACHINEGUN)
    local att    = attIdx and ent:GetAttachment(attIdx)
    local src    = att and att.Pos or (ent:GetPos() + Vector(0,0,60))
    local aimPos = enemy:GetPos() + Vector(0, 0, 40)
    local dir    = (aimPos - src):GetNormalized()
    local grenade = ents.Create("npc_grenade_frag")
    if IsValid(grenade) then
        grenade:SetPos(src)
        grenade:SetAngles(dir:Angle())
        grenade:Spawn()
        grenade:SetOwner(ent)
        local phys = grenade:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(dir * 600 + Vector(0,0,200))
            phys:ApplyForceCenter(dir * 500)
        end
        timer.Simple(3.0, function()
            if IsValid(grenade) then grenade:Remove() end
        end)
    end
    local ev = EffectData()
    ev:SetOrigin(src); ev:SetNormal(dir)
    util.Effect(GL_VAPOR_EFFECT, ev)
    if att then
        local es = EffectData()
        es:SetOrigin(src); es:SetNormal(dir)
        util.Effect(GL_SMOKE_EFFECT, es)
    end
end

-- ============================================================
-- TAUNT BARK
-- ============================================================
local TAUNT_SOUNDS = {
    "npc/strider/strider_alert1.wav",
    "npc/strider/strider_alert2.wav",
    "npc/strider/anger1.wav",
}
local function DoTaunt(ent)
    ent:EmitSound(TAUNT_SOUNDS[math.random(#TAUNT_SOUNDS)], 80, math.random(90,110))
end

-- ============================================================
-- WEAPON CHOICE AI
-- ============================================================
local WEAPON_MG         = "mg"
local WEAPON_BUSHMASTER = "bushmaster"
local WEAPON_ROCKET     = "rocket"
local WEAPON_GL         = "gl"

local function ChooseWeapon(ent, dist)
    if dist > ROCKET_ENGAGE_DIST_MIN and dist < ROCKET_ENGAGE_DIST_MAX then
        if math.random() < 0.35 then return WEAPON_ROCKET end
    end
    if dist > 400 and dist < 1800 and math.random() < 0.25 then
        return WEAPON_BUSHMASTER
    end
    if dist > 500 and dist < 2200 and math.random() < 0.15 then
        return WEAPON_GL
    end
    return WEAPON_MG
end

-- ============================================================
-- HIT POSITION RESOLVER
-- ============================================================
local function GekkoResolveHitPos(ent, dmginfo)
    local bodyCenter = ent:GetPos() + Vector(0, 0, 80)
    local dmgPos     = dmginfo:GetDamagePosition()

    if dmgPos and dmgPos ~= vector_origin then
        local _, entMaxs = ent:GetCollisionBounds()
        local entTop  = ent:GetPos().z + (entMaxs and entMaxs.z or 200)
        local entBase = ent:GetPos().z
        if dmgPos.z >= entBase and dmgPos.z <= entTop + 10 then
            return dmgPos, "dmgpos"
        end
    end

    local attacker   = dmginfo:GetAttacker()
    local inflictor  = dmginfo:GetInflictor()

    if IsValid(inflictor) and inflictor ~= attacker then
        local inflPos = inflictor:GetPos()
        local tr = util.TraceLine({
            start  = inflPos,
            endpos = bodyCenter,
            filter = { inflictor, ent },
            mask   = MASK_SHOT,
        })
        if tr.Hit and tr.Entity == ent then
            return tr.HitPos, "trace_inflictor_entity"
        end
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

    -- ── Reactive pedestal dodge: MUST run before any visual calls ──
    -- A successful dodge suppresses all hit effects (blood, decals,
    -- juicy bleed, BaseClass splatter) and returns immediately.
    -- Previously this ran AFTER GekkoVanillaBleed/GekkoSignalBloodHit,
    -- so blood and decals spawned even on a successful dodge.
    if self:PedestalDodge_OnHit(dmginfo) then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        dmginfo:SetDamageForce(Vector(0, 0, 0))
        return  -- no blood, no decal, no BaseClass splatter
    end
    -- ───────────────────────────────────────────────────────────────

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
    for i = 1, mgRounds do
        timer.Simple((i - 1) * MG_INTERVAL, function()
            if not IsValid(ent) or not IsValid(enemy) then return end
            SnapToEnemy(ent, enemy)
            local attIdx = ent:LookupAttachment(ATT_MACHINEGUN)
            local att    = attIdx and ent:GetAttachment(attIdx)
            if not att then return end
            local src    = att.Pos
            local spread = Vector(
                math.Rand(-mgSpread, mgSpread),
                math.Rand(-mgSpread, mgSpread), 0
            )
            local dir = ((aimPos - src):GetNormalized() + spread):GetNormalized()
            local tr  = util.TraceLine({
                start  = src,
                endpos = src + dir * 3000,
                filter = ent,
                mask   = MASK_SHOT,
            })
            FireMGMuzzle(ent)
            ent:GekkoMG_SpawnShell()
            if IsValid(tr.Entity) then
                tr.Entity:TakeDamage(MG_DAMAGE, ent, ent)
            end
            ent:GekkoMG_SendImpactLight(src, dir, 1)
        end)
    end
    return true
end

local function FireBushmasterBurst(ent, enemy)
    if ent._mgBurstActive then return false end
    local rounds = math.random(2, 4)
    ent._mgBurstActive = true
    ent._mgBurstEndT   = CurTime() + (rounds * BUSHMASTER_INTERVAL) + 0.5
    for i = 1, rounds do
        timer.Simple((i - 1) * BUSHMASTER_INTERVAL, function()
            if not IsValid(ent) or not IsValid(enemy) then return end
            FireBushmasterRound(ent, enemy)
        end)
    end
    return true
end

-- ============================================================
-- COMBAT AI
-- ============================================================
function ENT:CombatThink()
    local enemy = GetActiveEnemy(self)
    if not IsValid(enemy) then return end

    local dist = self:GetPos():Distance(enemy:GetPos())
    self._gekkoLastEnemyDist = dist

    local now = CurTime()
    if not self._nextAttackT then self._nextAttackT = now end
    if now < self._nextAttackT then return end

    if self._mgBurstActive then return end

    local weapon = ChooseWeapon(self, dist)
    self._lastWeaponChoice = weapon

    if weapon == WEAPON_MG then
        if FireMGBurst(self, enemy) then
            self._nextAttackT = now + math.Rand(0.8, 1.6)
        end
    elseif weapon == WEAPON_BUSHMASTER then
        if FireBushmasterBurst(self, enemy) then
            self._nextAttackT = now + math.Rand(2.0, 3.5)
        end
    elseif weapon == WEAPON_ROCKET then
        if not self._nextRocketT or now >= self._nextRocketT then
            FireRocket(self, enemy)
            self._nextRocketT = now + ROCKET_INTERVAL
            self._nextAttackT = now + math.Rand(1.5, 2.5)
        end
    elseif weapon == WEAPON_GL then
        FireGL(self, enemy)
        self._nextAttackT = now + math.Rand(3.0, 5.0)
    end

    if math.random() < 0.05 then
        DoTaunt(self)
    end
end

-- ============================================================
-- ANIMATION
-- ============================================================
local JUMP_STATE_NAMES = { [0]="NONE", [1]="RISING", [2]="FALLING", [3]="LAND" }

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

    -- ── Crouch animation ──────────────────────────────────────────────────────
    -- Always run GeckoCrouch_Update when a dodge-crouch is active.
    -- The pedestal dodge uses MOVETYPE_FLYGRAVITY with SLIDE_HOP_Z=80, which
    -- causes a small ballistic arc that can briefly set JUMP_RISING. Without
    -- this bypass, the jump-state guard would skip GeckoCrouch_Update for the
    -- entire hop duration, making the crouch animation never play during a dodge.
    local jumpState = self:GetGekkoJumpState()
    local dodgeCrouchActive = self._gekkoDodgeCrouch and now < (self._gekkoDodgeCrouchUntil or 0)
    local jumpBlocking = (jumpState == self.JUMP_RISING  or
                          jumpState == self.JUMP_FALLING  or
                          jumpState == self.JUMP_LAND     or
                          (self._gekkoJustJumped and now < self._gekkoJustJumped))

    if dodgeCrouchActive or not jumpBlocking then
        if self:GeckoCrouch_Update() then return end
    end
    -- ──────────────────────────────────────────────────────────────────────────

    if now < (self._gekkoSuppressActivity or 0) then return end

    if jumpBlocking then
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
        if self._gekkoSprinting then
            targetSeq = self.GekkoSeq_Run;  arate = vel / SPRINT_ANIM_SPEED
        elseif self._gekkoRunning then
            targetSeq = self.GekkoSeq_Run;  arate = vel / ANIM_RUN_SPEED
        else
            targetSeq = self.GekkoSeq_Walk; arate = vel / ANIM_WALK_SPEED
        end
    else
        targetSeq = self.GekkoSeq_Idle; arate = 1
    end
    if not targetSeq or targetSeq == -1 then
        targetSeq = self.GekkoSeq_Idle or 0
    end
    if targetSeq ~= self._gekkoLastSeqSet then
        self:ResetSequence(targetSeq)
        self._gekkoLastSeqSet = targetSeq
    else
        self:ResetSequence(targetSeq)
    end
    self:SetPlaybackRate(arate or 1)
    self:SetPoseParameter("move_x", 0)
    self:SetPoseParameter("move_y", 0)
    self.Gekko_LastSeqName = targetSeq
end

-- ============================================================
-- ANIMATION TRANSLATIONS
-- ============================================================
function ENT:SetAnimationTranslations()
    -- VJ Base override: prevent VJ from overriding our sequences
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:Initialize()
    self:SetModel("models/combine_strider.mdl")
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(CAP_MOVE_GROUND)
    self:SetMaxHealth(8000)
    self:SetHealth(8000)
    self:SetCollisionBounds(
        Vector(-64, -64, 0),
        Vector( 64,  64, 200)
    )
    self.BloodColor = BLOOD_COLOR_RED
    self:SetupBloodColor(self.BloodColor)
    self.VJ_IsBeingCrouched  = false
    self.VJ_TheEnemy         = NULL
    self._mgBurstActive      = false
    self._mgBurstEndT        = 0
    self._nextRocketT        = 0
    self._gekkoRunning       = false
    self._gekkoSprinting     = false
    self._gekkoLastSeqSet    = -1
    self._gekkoSuppressActivity   = 0
    self._gekkoLastPos       = nil
    self._gekkoLastTime      = nil
    self._gekkoLastEnemyDist = nil
    self._bloodSplatPulse         = 0
    self._gekkoDead          = false
    self.Gekko_NextDebugT    = 0
    self.Gekko_LastSeqName   = "none"

    self:GeckoCrouch_Init()
    self:GekkoLegs_Init()
    self:GekkoGib_Init()
    self:GekkoElastic_Init()
    self:GekkoAPS_Init()
    self:PedestalDodge_Init()
    self:GeckoCrush_Init()
    self:GekkoDeathPose_Init()

    SafeInitVJTables(self)
    self:SetNWBool("GekkoIsCrouching", false)
    self:SetNWBool("GekkoMGFiring",    false)
    self:SetNWInt("GekkoBloodSplat",   0)

    timer.Simple(0.1, function()
        if not IsValid(self) then return end
        local selfRef = self
        selfRef:GekkoJump_Activate()
        selfRef:GekkoTargetJump_Activate()
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
-- AI SCHEDULE / THINK
-- ============================================================
function ENT:RunAI()
    if self._gekkoDead then return end
    self:CombatThink()
end

-- ============================================================
-- DEATH
-- ============================================================
function ENT:OnRemove()
    self._gekkoDead = true
end

local DEATH_SOUNDS = {
    "npc/strider/strider_death1.wav",
    "npc/strider/strider_death2.wav",
}
function ENT:Event_Death(dmginfo, hitgroup)
    self._gekkoDead = true
    self:EmitSound(DEATH_SOUNDS[math.random(#DEATH_SOUNDS)], 90, math.random(90, 110))
    self:SetCollisionBounds(Vector(-64,-64,0), Vector(64,64,200))
    self:GekkoDeathPose_Apply()

    local pos = self:GetPos()
    local ang = Angle(0,0,0)
    ParticleEffect("astw2_nightfire_explosion_generic", pos, ang)
    timer.Simple(0.3, function()
        if IsValid(self) then
            ParticleEffect("astw2_nightfire_explosion_generic", pos + Vector(math.Rand(-60,60), math.Rand(-60,60), 60), ang)
        end
    end)
end
