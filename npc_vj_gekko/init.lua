-- ============================================================
--  npc_vj_gekko / init.lua
--  Weapon list:
--  1. Machine-gun burst         (FireBullets)
--  2. Single accurate missile   (obj_vj_rocket)
--  3. Seeker salvo              (obj_vj_seeker)
--  4. Ground-stomp / crush      (util.BlastDamage)
-- ============================================================

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("muzzleflash_system.lua")
AddCSLuaFile("bullet_impact_system.lua")
AddCSLuaFile("crouch_system.lua")
AddCSLuaFile("leg_disable_system.lua")
AddCSLuaFile("gib_system.lua")
AddCSLuaFile("jump_system.lua")
AddCSLuaFile("targeted_jump_system.lua")
AddCSLuaFile("crush_system.lua")

include("shared.lua")
include("leg_disable_system.lua")
include("gib_system.lua")
include("jump_system.lua")
include("targeted_jump_system.lua")
include("crush_system.lua")

-- ============================================================
--  BASE PROPERTIES
-- ============================================================
ENT.Base                     = "base_vj_npc"
ENT.Type                     = "ai"
ENT.PrintName                = "Gekko"
ENT.Author                   = "NachinBombin"
ENT.Contact                  = ""
ENT.Purpose                  = ""
ENT.Instructions             = ""
ENT.AutomaticFrameAdvance    = true

-- ============================================================
--  VJ BASE SETTINGS
-- ============================================================
ENT.VJ_NPC_Class             = { "CLASS_COMBINE" }
ENT.VJ_IsHumanNPC            = false
ENT.StartHealth              = 2500
ENT.VJ_BloodColor            = "Red"
ENT.VJ_BloodType             = 2
ENT.AnimTbl_Walk             = { ACT_WALK }
ENT.AnimTbl_Run              = { ACT_RUN }
ENT.AnimTbl_IdleStand        = { ACT_IDLE }
ENT.Immune_Poison            = true
ENT.Immune_Dissolve          = true
ENT.NoChaseAfterCertainRange = false
ENT.VJ_NPC_MovementType      = VJ_MOVETYPE_GROUND
ENT.FootStepTimeRun          = 0
ENT.FootStepTimeWalk         = 0

-- ============================================================
--  MODEL
-- ============================================================
ENT.Model                    = "models/metal_gear/mgs4/mobs/gekko.mdl"
ENT.ModelScale               = 1

-- ============================================================
--  SOUNDS
-- ============================================================
ENT.VJ_DeathSounds           = {}
ENT.VJ_IdleSounds            = {}
ENT.VJ_AlertSounds           = {}
ENT.VJ_PainSounds            = {}

-- ============================================================
--  LOOT (nothing)
-- ============================================================
ENT.VJ_NPC_LootItems         = {}

-- ============================================================
--  ANIMATION SUPPORT
-- ============================================================
ENT.Gekko_LastSeqName        = ""
ENT.FK360_DURATION           = 0.9

function ENT:SetGekkoJumpState(state)
    self:SetNWInt("GekkoJumpState", state)
end

-- ============================================================
--  INITIALIZE
-- ============================================================
function ENT:Initialize()
    self:SetModel(self.Model)
    self:SetModelScale(self.ModelScale, 0)
    self:SetHullType(HULL_LARGE)
    self:SetHullSizeNormal()

    self:VJ_Initialize()

    self:SetCollisionBounds(Vector(30, 30, 140), Vector(-30, -30, 0))

    -- Initialise NW state before anything reads it
    self:SetGekkoJumpState(self.JUMP_NONE)
    self:SetNWBool("GekkoLegsDisabled",    false)
    self:SetNWBool("GekkoMGFiring",        false)
    self:SetNWBool("GekkoDead",            false)
    self:SetNWInt("GekkoJumpDust",         0)
    self:SetNWInt("GekkoLandDust",         0)
    self:SetNWInt("GekkoFK360LandDust",    0)
    self:SetNWInt("GekkoBloodSplat",       0)

    self:GekkoLegs_Init()
end

-- ============================================================
--  STAGGER ON PAIN / DAMAGE
-- ============================================================
local STAGGER_SOUNDS = {
    "npc/strider/machine_pain1.wav",
    "npc/strider/machine_pain2.wav",
    "npc/strider/machine_pain3.wav",
    "npc/strider/machine_pain4.wav",
}

function ENT:AcceptInput(name, activator, caller, data)
    if name == "StartPatrolling" then
        self:SetSchedule(SCHED_PATROL_WALK)
        return true
    end
end

-- ============================================================
--  BLOOD SPLAT DISPATCH  (server → client via NWInt)
-- ============================================================
local BLOOD_VARIANT_COUNT = 5

function ENT:GekkoDispatchBloodSplat()
    self._bloodSplatPulse = ((self._bloodSplatPulse or 0) % 127) + 1
    local variant = math.random(1, BLOOD_VARIANT_COUNT)
    self:SetNWInt("GekkoBloodSplat", self._bloodSplatPulse*8 + (variant-1))
end

-- ============================================================
--  DAMAGE HANDLER
-- ============================================================
function ENT:OnTakeDamage_Final(dmginfo)
    self:GekkoDispatchBloodSplat()
    self:GekkoLegs_OnDamage(dmginfo)
end

-- ============================================================
--  THINK  (server)
-- ============================================================
local SPEED_SMOOTH = 0.18

function ENT:Think()
    if self._gekkoLegsDisabled then self:GekkoLegs_Think() end

    -- Suppress speed update after death
    if not self:GetNWBool("GekkoDead", false) then
        local vel  = self:GetVelocity():Length2D()
        local prev = self:GetNWFloat("GekkoSpeed", 0)
        self:SetNWFloat("GekkoSpeed", Lerp(SPEED_SMOOTH, prev, vel))
    end

    if not self:Alive() then
        self:SetNWBool("GekkoMGFiring", false)
        return
    end

    self:NextThink(CurTime())
    return true
end

-- ============================================================
--  SEQUENCE HELPER
-- ============================================================
function ENT:GekkoPlaySeq(seqName, rate)
    local seq = self:LookupSequence(seqName)
    if not seq or seq < 0 then return end
    self:ResetSequence(seq)
    self:SetPlaybackRate(rate or 1)
    self.Gekko_LastSeqName = seqName
end

-- ============================================================
--  DEBUG THINK PRINT  (disabled)
-- ============================================================
--[[
function ENT:Think_Debug()
    if (self._dbNextPrint or 0) > CurTime() then return end
    self._dbNextPrint = CurTime() + 2
    print(string.format("[Gekko] hp=%d vel=%.1f seq=%s",
        self:Health(),
        self:GetNWFloat("GekkoSpeed",0), tostring(self.Gekko_LastSeqName),
        self:GetSequenceName(self:GetSequence())))
end
--]]

-- ============================================================
--  MACHINE-GUN  (attack 1)
-- ============================================================
local MG_BULLET_COUNT   = 4
local MG_BULLET_SPREAD  = Vector(0.08, 0.08, 0)
local MG_BULLET_DAMAGE  = 12
local MG_BULLET_RANGE   = 3000
local MG_BURST_COUNT    = 6
local MG_BURST_INTERVAL = 0.11
local MG_ATT_ID         = 3   -- "muzzle" attachment
local MG_SOUND_FIRE     = "weapons/smg1/fire1.wav"
local MG_SOUND_EMPTY    = "weapons/pistol/pistol_empty.wav"

local function GekkoMGFireBullet(ent)
    local attData = ent:GetAttachment(MG_ATT_ID)
    if not attData then return end

    local tr = util.TraceLine({
        start  = attData.Pos,
        endpos  = attData.Pos + attData.Ang:Forward() * MG_BULLET_RANGE,
        filter  = ent,
        mask    = MASK_SHOT,
    })

    ent:FireBullets({
        Num       = MG_BULLET_COUNT,
        Src       = attData.Pos,
        Dir       = attData.Ang:Forward(),
        Spread    = MG_BULLET_SPREAD,
        Tracer    = 2,
        Force     = 3,
        Damage    = MG_BULLET_DAMAGE,
        AmmoType  = "SMG1",
        Attacker  = ent,
    })

    ent:EmitSound(MG_SOUND_FIRE, 85, math.random(95, 105))
end

local function GekkoStartMGBurst(ent)
    if not IsValid(ent) or not ent:Alive() then return end
    ent:SetNWBool("GekkoMGFiring", true)

    local shotsLeft = MG_BURST_COUNT
    local function FireNext()
        if not IsValid(ent) or not ent:Alive() then
            if IsValid(ent) then ent:SetNWBool("GekkoMGFiring", false) end
            return
        end
        GekkoMGFireBullet(ent)
        shotsLeft = shotsLeft - 1
        if shotsLeft > 0 then
            timer.Simple(MG_BURST_INTERVAL, FireNext)
        else
            ent:SetNWBool("GekkoMGFiring", false)
        end
    end
    FireNext()
end

-- ============================================================
--  MISSILE  (attack 2)  — obj_vj_rocket
-- ============================================================
local MISSILE_ATT_ID    = 1
local MISSILE_SPEED     = 950
local MISSILE_DAMAGE    = 80
local MISSILE_SOUND     = "weapons/rpg/rocket1.wav"

local function GekkoFireMissile(ent)
    local attData = ent:GetAttachment(MISSILE_ATT_ID)
    local pos     = attData and attData.Pos or (ent:GetPos() + Vector(0,0,80))
    local enemy   = ent:GetEnemy()
    local target  = IsValid(enemy) and (enemy:GetPos() + Vector(0,0,40))
                    or (pos + ent:GetForward()*1200)

    local missile = ents.Create("obj_vj_rocket")
    if not IsValid(missile) then return end

    missile:SetPos(pos)
    missile:SetAngles((target - pos):Angle())
    missile:Spawn()
    missile:Activate()

    missile:SetOwner(ent)
    missile.Owner     = ent
    missile.Damage    = MISSILE_DAMAGE
    missile.DamageRadius = 220

    local vel = (target - pos):GetNormalized() * MISSILE_SPEED
    missile:GetPhysicsObject():SetVelocity(vel)

    ent:EmitSound(MISSILE_SOUND, 95, 100)
end

-- ============================================================
--  SEEKER SALVO  (attack 3)  — obj_vj_seeker
-- ============================================================
local SEEKER_COUNT    = 3
local SEEKER_INTERVAL = 0.18
local SEEKER_SPEED    = 750
local SEEKER_DAMAGE   = 35
local SEEKER_ATT_ID   = 2

local function GekkoFireSeekerSalvo(ent)
    local fired = 0
    local function FireOne()
        if not IsValid(ent) or not ent:Alive() then return end
        local attData = ent:GetAttachment(SEEKER_ATT_ID)
        local pos     = attData and attData.Pos or (ent:GetPos() + Vector(0,0,80))
        local enemy   = ent:GetEnemy()
        local target  = IsValid(enemy) and (enemy:GetPos() + Vector(0,0,40))
                        or (pos + ent:GetForward()*1200)

        local s = ents.Create("obj_vj_seeker")
        if not IsValid(s) then return end
        s:SetPos(pos)
        s:SetAngles((target - pos):Angle())
        s:Spawn()
        s:Activate()
        s:SetOwner(ent)
        s.Owner       = ent
        s.Damage      = SEEKER_DAMAGE
        s.TargetEnt   = enemy

        local phys = s:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity((target - pos):GetNormalized() * SEEKER_SPEED)
        end

        fired = fired + 1
        if fired < SEEKER_COUNT then
            timer.Simple(SEEKER_INTERVAL, FireOne)
        end
    end
    FireOne()
end

-- ============================================================
--  STOMP / CRUSH  (attack 4)
-- ============================================================
local STOMP_RADIUS  = 220
local STOMP_DAMAGE  = 120
local STOMP_FORCE   = 400

local function GekkoDoStomp(ent)
    local pos = ent:GetPos()
    util.BlastDamage(ent, ent, pos, STOMP_RADIUS, STOMP_DAMAGE)
    local e = EffectData()
    e:SetOrigin(pos)
    e:SetScale(80)
    util.Effect("ThumperDust", e)
    util.Effect("ThumperDust", e)
    ent:EmitSound("physics/metal/metal_box_impact_hard3.wav", 100, 75)
end

-- ============================================================
--  VJ BASE ATTACK CALLBACKS
-- ============================================================
function ENT:VJ_OnThink_AIEnabled()
    if self:GetNWBool("GekkoDead", false) then return end
    self:GekkoJump_Think()
    self:GekkoTargetedJump_Think()
end

function ENT:OnScheduleChange()
end

function ENT:DoCustomMeleeAttack(dmginfo)
    GekkoDoStomp(self)
end

function ENT:VJ_OnShoot(attacktype)
    if attacktype == 1 then
        GekkoStartMGBurst(self)
    elseif attacktype == 2 then
        GekkoFireMissile(self)
    elseif attacktype == 3 then
        GekkoFireSeekerSalvo(self)
    end
end

-- ============================================================
--  PUNCH DISPATCH HELPERS  (server → client via NWInt pulses)
-- ============================================================
local function Pulse(ent, key)
    ent[key] = ((ent[key] or 0) % 127) + 1
    ent:SetNWInt(key, ent[key])
end

function ENT:GekkoKick()            Pulse(self, "GekkoKickPulse")            end
function ENT:GekkoLKick()           Pulse(self, "GekkoLKickPulse")           end
function ENT:GekkoHeadbutt()        Pulse(self, "GekkoHeadbuttPulse")        end
function ENT:GekkoFrontKick360()    Pulse(self, "GekkoFrontKick360Pulse")    end
function ENT:GekkoFrontKick360B()   Pulse(self, "GekkoFrontKick360BPulse")   end
function ENT:GekkoSpinKick()        Pulse(self, "GekkoSpinKickPulse")        end
function ENT:GekkoFootballKick()    Pulse(self, "GekkoFootballKickPulse")    end
function ENT:GekkoRFootballKick()   Pulse(self, "GekkoRFootballKickPulse")   end
function ENT:GekkoDiagonalKick()    Pulse(self, "GekkoDiagonalKickPulse")    end
function ENT:GekkoDiagonalKickR()   Pulse(self, "GekkoDiagonalKickRPulse")   end
function ENT:GekkoBite()            Pulse(self, "GekkoBitePulse")            end
function ENT:GekkoTorqueKick()      Pulse(self, "GekkoTorqueKickPulse")      end
function ENT:GekkoSpinningCapoeira()Pulse(self, "GekkoSpinningCapoeiraPulse")end
function ENT:GekkoHeelHook()        Pulse(self, "GekkoHeelHookPulse")        end
function ENT:GekkoSideHookKick()    Pulse(self, "GekkoSideHookKickPulse")    end
function ENT:GekkoAxeKick()         Pulse(self, "GekkoAxeKickPulse")         end
function ENT:GekkoRAxeKick()        Pulse(self, "GekkoRAxeKickPulse")        end
function ENT:GekkoJumpKick()        Pulse(self, "GekkoJumpKickPulse")        end

-- FK360 spin duration forwarded to client via NWFloat
function ENT:GekkoSetFK360Duration(d)
    self.FK360_DURATION = d
    self:SetNWFloat("GekkoFK360Duration", d)
end

-- ============================================================
--  CRUSH NET MESSAGE
-- ============================================================
util.AddNetworkString("GekkoCrushHit")
util.AddNetworkString("GekkoSonarLock")

function ENT:GekkoNetCrushHit(hitPos)
    net.Start("GekkoCrushHit")
        net.WriteVector(hitPos)
        net.WriteVector(self:GetPos())
    net.Broadcast()
end

function ENT:GekkoNetSonarLock(ply)
    if not IsValid(ply) then return end
    net.Start("GekkoSonarLock")
    net.Send(ply)
end

-- ============================================================
--  FK360 LAND DUST DISPATCH
-- ============================================================
function ENT:GekkoDispatchFK360LandDust()
    self._fk360LandDustPulse = ((self._fk360LandDustPulse or 0) % 127) + 1
    self:SetNWInt("GekkoFK360LandDust", self._fk360LandDustPulse)
end

-- ============================================================
--  Death
-- ============================================================
function ENT:OnDeath(dmginfo, hitgroup, status)
    if status ~= "Finish" then return end
    local attacker = IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker() or self
    local pos      = self:GetPos()
    self:SetGekkoJumpState(self.JUMP_NONE)
    self:SetMoveType(MOVETYPE_STEP)
    self:SetNWBool("GekkoMGFiring", false)
    self:SetNWBool("GekkoDead", true)   -- signal clients: death-settle pass
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
