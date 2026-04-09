AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Homing Cruise Missile
--
--  ROOT CAUSE OF ACCELERATION BUG:
--    MOVETYPE_NOCLIP does NOT zero velocity between ticks.
--    SetVelocity() ADDS to the current velocity.
--    Every Think() was stacking +CRUISE_SPEED on top of the
--    previous value, causing exponential acceleration.
--
--  FIX: Use SetAbsVelocity() which REPLACES velocity outright.
--    This is the only safe way to drive constant-speed motion
--    on MOVETYPE_NOCLIP entities in GMod.
--
--  Steering: LerpVector on 3D direction vector, framerate-independent.
--  Collision: util.TraceHull each tick (more reliable than line trace).
--  Homing: NWEntity "NikitaTrackEnt" set post-Spawn by FireNikita.
--
--  IMPORTANT: Do NOT set NikitaTrackEnt = NULL inside Initialize().
--    Initialize() is called internally by Spawn(), which means it
--    fires BEFORE FireNikita's post-Activate SetNWEntity call.
--    Setting it to NULL here would permanently overwrite the real
--    target, making the missile fly straight every time.
-- ============================================================

local SND_EXPLODE   = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED  = 400    -- true u/s, no accumulation
local TURN_SPEED    = 4.5    -- LerpVector t per second
local LIFETIME      = 45
local PROX_RADIUS   = 180
local ENGINE_DELAY  = 0.5
local TARGET_Z_OFFS = 80

local HULL_MINS = Vector( -8, -8, -8 )
local HULL_MAXS = Vector(  8,  8,  8 )

local function SafeAimPos( ent )
    local p  = ent:GetPos()
    local tr = util.TraceLine({
        start  = p + Vector( 0, 0, 100 ),
        endpos = p - Vector( 0, 0, 1000 ),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = ent,
    })
    local gz = tr.Hit and tr.HitPos.z or p.z
    return Vector( p.x, p.y, gz + TARGET_Z_OFFS )
end

function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
    self:SetModelScale( 7, 0 )
    self:SetMoveType( MOVETYPE_NOCLIP )
    self:SetSolid( SOLID_NONE )
    self:SetCollisionGroup( COLLISION_GROUP_PROJECTILE )

    self.Destroyed    = false
    self.EngineActive = false
    self.SpawnTime    = CurTime()
    self.HealthVal    = 50
    self.Damage       = 0
    self.Radius       = 0
    self._nextDebug   = 0

    -- NOTE: Do NOT set NikitaTrackEnt here.
    -- FireNikita sets it after Spawn()+Activate(). Setting it
    -- to NULL inside Initialize() (which runs during Spawn())
    -- would overwrite the real target and break homing entirely.

    -- Launch nudge: SetAbsVelocity replaces velocity, does not accumulate
    self:SetAbsVelocity( self:GetForward() * 80 )

    local selfRef = self
    timer.Simple( ENGINE_DELAY, function()
        if not IsValid( selfRef ) or selfRef.Destroyed then return end
        selfRef.Damage = math.random( 2500, 4500 )
        selfRef.Radius = math.random( 700,  1024 )
        selfRef.EngineActive = true
        local trackEnt = selfRef:GetNWEntity( "NikitaTrackEnt", NULL )
        print( "[NikitaDBG] Engine ACTIVE | homing=" .. tostring( IsValid( trackEnt ) )
            .. " target=" .. tostring( trackEnt ) )
    end )

    self:NextThink( CurTime() )
end

function ENT:Think()
    self:NextThink( CurTime() )
    if self.Destroyed then return true end

    if CurTime() - self.SpawnTime > LIFETIME then
        self:MissileDoExplosion() ; return true
    end

    if not self.EngineActive then return true end

    -- Resolve homing target
    local trackEnt = self:GetNWEntity( "NikitaTrackEnt", NULL )
    local aimPos
    if IsValid( trackEnt ) then
        aimPos = SafeAimPos( trackEnt )
    elseif self.FallbackTarget then
        aimPos = self.FallbackTarget
    end

    -- Compute steering direction
    local currentDir = self:GetForward()
    local moveDir

    if aimPos then
        -- Proximity detonation
        if ( self:GetPos() - aimPos ):LengthSqr() < PROX_RADIUS * PROX_RADIUS then
            self:MissileDoExplosion() ; return true
        end

        local desiredDir = ( aimPos - self:GetPos() ):GetNormalized()
        moveDir = LerpVector( FrameTime() * TURN_SPEED, currentDir, desiredDir ):GetNormalized()
    else
        moveDir = currentDir
    end

    self:SetAngles( moveDir:Angle() )

    -- SetAbsVelocity REPLACES velocity -- no accumulation, true constant speed
    self:SetAbsVelocity( moveDir * CRUISE_SPEED )

    -- Hull collision sweep ahead
    local stepDist = CRUISE_SPEED * FrameTime() + 16
    local tr = util.TraceHull({
        start  = self:GetPos(),
        endpos = self:GetPos() + moveDir * stepDist,
        mins   = HULL_MINS,
        maxs   = HULL_MAXS,
        mask   = MASK_SHOT,
        filter = { self, IsValid( self.NikitaOwner ) and self.NikitaOwner or self },
    })
    if tr.Hit then
        if tr.HitWorld then
            self:MissileDoExplosion() ; return true
        end
        if IsValid( tr.Entity ) and tr.Entity ~= self.NikitaOwner then
            self:MissileDoExplosion() ; return true
        end
    end

    -- Debug ticker
    if CurTime() > self._nextDebug then
        self._nextDebug = CurTime() + 0.5
        print( string.format(
            "[NikitaDBG] homing=%s spd=%.0f ang=%s",
            tostring( IsValid( trackEnt ) ),
            self:GetAbsVelocity():Length(),
            tostring( self:GetAngles() )
        ))
    end

    return true
end

function ENT:Touch( ent )
    if self.Destroyed then return end
    if CurTime() - self.SpawnTime < 0.3 then return end
    if ent == self.NikitaOwner then return end
    self:MissileDoExplosion()
end

function ENT:OnTakeDamage( dmginfo )
    if self.Destroyed then return end
    self.HealthVal = self.HealthVal - dmginfo:GetDamage()
    if self.HealthVal <= 0 then self:MissileDoExplosion() end
end

function ENT:MissileDoExplosion()
    if self.Destroyed then return end
    self.Destroyed = true
    self:StopParticles()
    local pos   = self:GetPos()
    local dmg   = self.Damage > 0 and self.Damage or 1200
    local rad   = self.Radius > 0 and self.Radius or 700
    local owner = IsValid( self.NikitaOwner ) and self.NikitaOwner or self
    sound.Play( SND_EXPLODE, pos, 100, 100 )
    util.ScreenShake( pos, 16, 200, 1, 3000 )
    local ed = EffectData() ; ed:SetOrigin( pos ) ; util.Effect( "Explosion", ed )
    local pe = ents.Create( "env_physexplosion" )
    if IsValid( pe ) then
        pe:SetPos( pos )
        pe:SetKeyValue( "Magnitude",  tostring( math.floor( dmg * 5 ) ) )
        pe:SetKeyValue( "radius",     tostring( rad ) )
        pe:SetKeyValue( "spawnflags", "19" )
        pe:Spawn() ; pe:Activate()
        pe:Fire( "Explode", "", 0 ) ; pe:Fire( "Kill", "", 0.5 )
    end
    util.BlastDamage( self, owner, pos + Vector( 0, 0, 50 ), rad, dmg )
    self:Remove()
end

function ENT:OnRemove()
    self.Destroyed = true
    self:StopParticles()
end
