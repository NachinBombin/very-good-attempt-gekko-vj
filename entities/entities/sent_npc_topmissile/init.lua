-- ============================================================
--  sent_npc_topmissile / init.lua  (SERVER)
--
--  Top-attack guided missile for npc_vj_gekko.
--
--  Required fields set by the NPC BEFORE Spawn():
--    missile.Owner   = <npc entity>
--    missile.Target  = <Vector>   (target position snapshot)
--
--  Guidance lifecycle:
--    1. Spawn: gravity OFF, initial kick upward / forward.
--    2. After LAUNCH_DELAY: engine fires, gravity ON, guidance begins.
--    3. PhysicsUpdate: 3-phase top-attack arc steered via LerpAngle.
--         Phase A (> 90% initial dist): fly toward target + 512 Z
--         Phase B (40-90%):             fly toward target + large climb
--         Phase C (< 40%):              dive directly onto target
--    4. Detonation: PhysicsCollide (speed + deltatime guard) OR
--       proximity check in Think when within RADIUS * 0.65.
-- ============================================================
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ---- Tuning -----------------------------------------------
local LAUNCH_DELAY    = 0.6      -- seconds before engine ignites
local LAUNCH_KICK     = 90000   -- initial upward velocity (Hammer units/s)
local SPEED_MAX       = 2200    -- terminal guidance speed
local SPEED_ACCEL     = 300     -- force added per PhysicsUpdate tick
local MASS            = 500
local STEER_FAR       = 0.01    -- LerpAngle weight when far
local STEER_NEAR      = 0.12    -- LerpAngle weight when within 1000 u
local COLLIDE_SPEED   = 450     -- min speed for PhysicsCollide detonation
local COLLIDE_DT      = 0.2     -- min deltatime for PhysicsCollide detonation
local DAMAGE          = 2800
local RADIUS          = 820
local HEALTH          = 50
local PROX_FRACTION   = 0.65    -- detonate when dist < RADIUS * this
local ENGINE_SOUND    = "BF4/Rockets/PODS_Rocket_Engine_Wave 2 0 0_2ch.wav"
local EXPLODE_SOUND   = "WT/misc/bomb_explosion_1.wav"
local MODEL           = "models/weapons/w_missile_closed.mdl"
-- -----------------------------------------------------------

function ENT:Initialize()
    self:SetModel(MODEL)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(MASS)
        phys:EnableDrag(true)
        phys:EnableGravity(false)   -- gravity OFF until engine fires
    end

    self._speed     = 0
    self._started   = false
    self._destroyed = false
    self._healthVal = HEALTH

    -- Snapshot target in case it wasn't set
    if not self.Target then
        self.Target = self:GetPos() + self:GetForward() * 3000
    end

    -- Initial kick
    local phys2 = self:GetPhysicsObject()
    if IsValid(phys2) then
        phys2:SetVelocityInstantaneous(self:GetForward() * LAUNCH_KICK)
    end

    local eff = EffectData()
    eff:SetOrigin(self:GetPos())
    eff:SetNormal(self:GetForward())
    util.Effect("MuzzleFlash", eff)

    -- Safety kill after 25 seconds
    self:Fire("kill", "", 25)

    local selfRef = self
    timer.Simple(LAUNCH_DELAY, function()
        if not IsValid(selfRef) then return end
        selfRef:_IgniteEngine()
    end)
end

function ENT:_IgniteEngine()
    self._started = true
    self:SetNWBool("TMStarted", true)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(true)
    end

    self._engineSound = CreateSound(self, ENGINE_SOUND)
    self._engineSound:PlayEx(511, 100)

    -- Smoke trail prop (invisible, parented)
    local trail = ents.Create("prop_physics")
    if IsValid(trail) then
        trail:SetPos(self:LocalToWorld(Vector(-15, 0, 0)))
        trail:SetAngles(self:GetAngles())
        trail:SetParent(self)
        trail:SetModel("models/items/ar2_grenade.mdl")
        trail:Spawn()
        trail:SetRenderMode(RENDERMODE_TRANSALPHA)
        trail:SetColor(Color(0, 0, 0, 0))
        ParticleEffectAttach("scud_trail", PATTACH_ABSORIGIN_FOLLOW, trail, 0)
    end

    ParticleEffect("tank_muzzleflash", self:GetPos(), self:GetAngles(), nil)
end

function ENT:PhysicsUpdate()
    if not self._started  then return end
    if not self.Target    then return end

    if self:GetVelocity():Length() < SPEED_MAX then
        self._speed = self._speed + SPEED_ACCEL
    end

    -- 3-phase top-attack arc
    local mp     = self:GetPos()
    local dist2d = (Vector(mp.x, mp.y, 0) - Vector(self.Target.x, self.Target.y, 0)):Length()

    if not self._initDist then
        self._initDist = dist2d
    end

    local halfway   = self._initDist * 0.9
    local twoThirds = self._initDist * 0.4
    local aimPos

    if not self._tracking then
        if dist2d > halfway then
            -- Phase A: climb
            aimPos = self.Target + Vector(0, 0, 512)
        elseif dist2d > twoThirds then
            -- Phase B: peak
            aimPos = self.Target + Vector(0, 0, math.Clamp(self._initDist * 0.85, 0, 14500))
        else
            -- Phase C: dive
            aimPos = self.Target
            self._tracking = true
        end
    else
        aimPos = self.Target
    end

    local lerpVal = (dist2d < 1000) and STEER_NEAR or STEER_FAR
    self:SetAngles(LerpAngle(lerpVal, self:GetAngles(), (aimPos - self:GetPos()):GetNormalized():Angle()))
    self:GetPhysicsObject():ApplyForceCenter(self:GetForward() * self._speed)
end

function ENT:Think()
    -- Proximity detonation in Phase C
    if self._tracking and self.Target then
        if (self:GetPos() - self.Target):Length() < RADIUS * PROX_FRACTION then
            self:_Detonate()
        end
    end
    self:NextThink(CurTime())
    return true
end

function ENT:PhysicsCollide(data)
    if self._destroyed then return end
    if self._started
    and data.Speed     > COLLIDE_SPEED
    and data.DeltaTime > COLLIDE_DT then
        self:_Detonate()
    end
end

function ENT:_Detonate()
    if self._destroyed then return end
    self._destroyed = true

    if self._engineSound then
        self._engineSound:Stop()
    end

    self:EmitSound(EXPLODE_SOUND, 511, 100)
    ParticleEffect("explosion_medium", self:GetPos(), self:GetAngles(), nil)

    -- Physics shockwave
    local pe = ents.Create("env_physexplosion")
    if IsValid(pe) then
        pe:SetPos(self:GetPos())
        pe:SetKeyValue("Magnitude", tostring(5 * DAMAGE))
        pe:SetKeyValue("radius",    tostring(RADIUS))
        pe:SetKeyValue("spawnflags", "19")
        pe:Spawn()
        pe:Activate()
        pe:Fire("Explode", "", 0)
        pe:Fire("Kill",    "", 0.5)
    end

    local own = IsValid(self.Owner) and self.Owner or self
    util.BlastDamage(self, own, self:GetPos() + Vector(0, 0, 50), RADIUS, DAMAGE)
    self:Remove()
end

function ENT:OnTakeDamage(dmginfo)
    if self._destroyed then return end
    self._healthVal = self._healthVal - dmginfo:GetDamage()
    if self._healthVal <= 0 then
        self:_Detonate()
    end
end

function ENT:OnRemove()
    if self._engineSound then
        self._engineSound:Stop()
    end
end
