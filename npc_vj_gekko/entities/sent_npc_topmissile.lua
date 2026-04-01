-- ============================================================
--  sent_npc_topmissile
--  Top-attack guided missile for npc_vj_gekko.
--
--  Guidance lifecycle (mirrors sent_neuro_javelin exactly):
--    1. On spawn: zero speed, gravity OFF, kick velocity applied
--       so it coasts upward.
--    2. After LAUNCH_DELAY seconds: engine fires (Started = true),
--       gravity ON, ApplyForceCenter begins in PhysicsUpdate.
--    3. PhysicsUpdate steers via LerpAngle toward a 3-phase arc:
--         a. Far   (> 90% initial dist): fly to target + 512 Z
--         b. Mid   (40%–90%):            fly to target + climb arc
--         c. Close (< 40%):              track TargetEntity directly
--    4. Detonation: PhysicsCollide (speed+deltatime guard) OR
--       proximity check in Think when within Radius * 0.65.
--
--  Required fields set by the NPC BEFORE Spawn():
--    missile.Owner         = <npc entity>
--    missile.Target        = <Vector>   (target position snapshot)
--    missile.TargetEntity  = <entity>   (optional live tracking)
-- ============================================================
AddCSLuaFile()

ENT.PrintName   = "NPC Top-Attack Missile"
ENT.Author      = "GekkoNPC"
ENT.Category    = "NPC Projectiles"
ENT.Type        = "anim"
ENT.Spawnable   = false
ENT.AdminOnly   = false

-- ── Tuning ───────────────────────────────────────────────────
local LAUNCH_DELAY   = 0.6    -- seconds before engine ignites
local LAUNCH_KICK    = 90000  -- initial velocity (Hammer units/s) — gets it away from the NPC body
local SPEED_MAX      = 2200   -- terminal guidance speed (units/frame threshold)
local SPEED_ACCEL    = 300    -- force added per PhysicsUpdate tick
local MASS           = 500
local STEER_FAR      = 0.01   -- LerpAngle weight when far
local STEER_NEAR     = 0.12   -- LerpAngle weight when within 1000 u
local STEER_MOVING   = 0.125  -- LerpAngle weight for moving-target mode
local COLLIDE_SPEED  = 450    -- min speed for PhysicsCollide detonation
local COLLIDE_DT     = 0.2    -- min delta-time  for PhysicsCollide detonation
local DAMAGE         = 2800
local RADIUS         = 820
local HEALTH         = 50
local PROX_FRACTION  = 0.65   -- detonate when dist < RADIUS * this

local ENGINE_SOUND   = "BF4/Rockets/PODS_Rocket_Engine_Wave 2 0 0_2ch.wav"
local EXPLODE_SOUND  = "WT/misc/bomb_explosion_1.wav"
local MODEL          = "models/weapons/w_missile_closed.mdl"  -- fallback GMod stock model
local VEFFECT        = "explosion_medium"                      -- particle on detonation

-- ── Shared ───────────────────────────────────────────────────
function ENT:Initialize()
    if SERVER then
        self:SetModel(MODEL)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)

        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:SetMass(MASS)
            phys:EnableDrag(true)
            phys:EnableGravity(false)  -- gravity OFF until engine fires
        end

        self._speed      = 0
        self._started    = false
        self._destroyed  = false
        self._healthVal  = HEALTH

        self._engineSound = CreateSound(self, ENGINE_SOUND)

        -- Snapshot target at init time in case .Target wasn't set
        if not self.Target then
            self.Target = self:GetPos() + self:GetForward() * 3000
        end

        -- Initial kick — gets missile clear of the NPC before gravity/guidance
        local phys2 = self:GetPhysicsObject()
        if IsValid(phys2) then
            phys2:SetVelocityInstantaneous(self:GetForward() * LAUNCH_KICK)
        end

        -- Muzzle flash at launch point
        local eff = EffectData()
        eff:SetOrigin(self:GetPos())
        eff:SetNormal(self:GetForward())
        util.Effect("MuzzleFlash", eff)

        -- Delayed engine ignition
        local selfRef = self
        timer.Simple(LAUNCH_DELAY, function()
            if not IsValid(selfRef) then return end
            selfRef:_IgniteEngine()
        end)

        -- Safety kill — remove after 25 seconds regardless
        self:Fire("kill", "", 25)
    end
end

-- ── Engine ignition ──────────────────────────────────────────
function ENT:_IgniteEngine()
    self._started = true
    self:SetNWBool("TMStarted", true)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(true)  -- now subject to gravity; engine must overcome it
    end

    self._engineSound:PlayEx(511, 100)

    -- Smoke trail prop (invisible, parented, drives particle attach)
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

-- ── Guidance + propulsion ────────────────────────────────────
function ENT:PhysicsUpdate()
    if not SERVER then return end
    if not self._started then return end
    if not self.Target then return end

    -- Speed cap — keep accumulating force up to terminal velocity
    if self:GetVelocity():Length() < SPEED_MAX then
        self._speed = self._speed + SPEED_ACCEL
    end

    -- Moving-target mode: once missile is below target and target moves fast,
    -- switch to direct live-tracking with height offset based on distance.
    if IsValid(self.TargetEntity) and not self._movingTargetMode then
        local tpos = self.TargetEntity:GetPos()
        local mpos = self:GetPos()
        if (mpos.z - tpos.z) < -200 and self.TargetEntity:GetVelocity():Length() > 200 then
            self._movingTargetMode = true
        end
    end

    local aimPos
    if self._movingTargetMode and IsValid(self.TargetEntity) then
        -- Live-track with dynamic height offset
        local dist  = (self.TargetEntity:GetPos() - self:GetPos()):Length()
        aimPos = self.TargetEntity:GetPos() + Vector(0, 0, math.Clamp(dist / 5, 0, 2500))
        self:SetAngles(LerpAngle(STEER_MOVING, self:GetAngles(), (aimPos - self:GetPos()):GetNormalized():Angle()))
    else
        -- 3-phase top-attack arc
        local mp         = self:GetPos()
        local dist2d     = (Vector(mp.x, mp.y, 0) - Vector(self.Target.x, self.Target.y, 0)):Length()

        if not self._initDist then
            self._initDist = dist2d
        end

        local halfway   = self._initDist * 0.9
        local twoThirds = self._initDist * 0.4

        if not self._tracking then
            if dist2d > halfway then
                -- Phase A: arc up
                aimPos = self.Target + Vector(0, 0, 512)
            elseif dist2d > twoThirds then
                -- Phase B: peak of arc
                aimPos = self.Target + Vector(0, 0, math.Clamp(self._initDist * 0.85, 0, 14500))
            else
                -- Phase C: dive onto target / lock entity
                if IsValid(self.TargetEntity) then
                    aimPos = self.TargetEntity:GetPos()
                    self._tracking = true
                else
                    aimPos = self.Target
                end
            end
        else
            aimPos = IsValid(self.TargetEntity) and self.TargetEntity:GetPos() or self.Target
        end

        local lerpVal = (dist2d < 1000) and STEER_NEAR or STEER_FAR
        self:SetAngles(LerpAngle(lerpVal, self:GetAngles(), (aimPos - self:GetPos()):GetNormalized():Angle()))
    end

    self:GetPhysicsObject():ApplyForceCenter(self:GetForward() * self._speed)
end

-- ── Proximity detonation ─────────────────────────────────────
function ENT:Think()
    if not SERVER then return end

    -- Moving-target proximity detonation
    if self._movingTargetMode and IsValid(self.TargetEntity) then
        if (self:GetPos() - self.TargetEntity:GetPos()):Length() < RADIUS * PROX_FRACTION then
            self:_Detonate()
        end
    end

    self:NextThink(CurTime())
    return true
end

-- ── Impact detonation ────────────────────────────────────────
function ENT:PhysicsCollide(data)
    if not SERVER then return end
    if self._destroyed then return end

    -- Guard: only detonate if engine is running, speed is high, and
    -- enough time has passed since last collision — prevents ground-stuck loops.
    if self._started
    and data.Speed    > COLLIDE_SPEED
    and data.DeltaTime > COLLIDE_DT then
        self:_Detonate()
    end
end

-- ── Detonation ───────────────────────────────────────────────
function ENT:_Detonate()
    if self._destroyed then return end
    self._destroyed = true

    if self._engineSound then
        self._engineSound:Stop()
    end

    self:EmitSound(EXPLODE_SOUND, 511, 100)

    ParticleEffect(VEFFECT, self:GetPos(), self:GetAngles(), nil)

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

-- ── Damage (can be shot down) ────────────────────────────────
function ENT:OnTakeDamage(dmginfo)
    if self._destroyed then return end
    self._healthVal = self._healthVal - dmginfo:GetDamage()
    if self._healthVal <= 0 then
        self:_Detonate()
    end
end

-- ── Cleanup ──────────────────────────────────────────────────
function ENT:OnRemove()
    if self._engineSound then
        self._engineSound:Stop()
    end
end

-- ── Client: exhaust particles ────────────────────────────────
if CLIENT then
    function ENT:Draw()
        self:DrawModel()

        if not self:GetNWBool("TMStarted") then return end

        if not self._emitter then
            self._emitter = ParticleEmitter(self:GetPos(), false)
        end
        if not self._emitter then return end

        local pos  = self:GetPos() + self:GetForward() * -15
        local vel  = self:GetForward() * -10

        -- Fire core
        local p = self._emitter:Add("effects/smoke_a", pos)
        if p then
            p:SetVelocity(vel)
            p:SetDieTime(math.Rand(0.05, 0.1))
            p:SetStartAlpha(math.Rand(222, 255))
            p:SetEndAlpha(0)
            p:SetStartSize(math.random(4, 6))
            p:SetEndSize(math.random(20, 34))
            p:SetAirResistance(150)
            p:SetRoll(math.Rand(180, 480))
            p:SetRollDelta(math.Rand(-3, 3))
            p:SetColor(255, 100, 0)
        end

        -- Dynamic light
        local dl = DynamicLight(self:EntIndex())
        if dl then
            dl.Pos        = self:GetPos()
            dl.r          = 250 + math.random(-5, 5)
            dl.g          = 170 + math.random(-5, 5)
            dl.b          = 0
            dl.Brightness = 1
            dl.Decay      = 0.1
            dl.Size       = 2048
            dl.DieTime    = CurTime() + 0.15
        end
    end
end
