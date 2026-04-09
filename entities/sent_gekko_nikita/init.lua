AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
--  SERVER  -  Gekko Nikita Homing Missile
--
--  Homing method: NWEntity "NikitaTrackEnt" set by FireNikita
--  immediately after Spawn()+Activate(). NetworkVars survive
--  the engine post-Spawn table reset that wiped plain Lua
--  fields (self.TrackEnt = ...) in previous versions.
--
--  MOVETYPE_NOCLIP: SetVelocity fully replaces velocity.
--  MOVETYPE_FLY accumulates velocity (bug: 4700 u/s in 1s).
--
--  SafeAimPos traces ground under target so aim Z is never
--  underground (prevented the nose-dive crash behavior).
-- ============================================================

local SND_EXPLODE = "ambient/explosions/explode_8.wav"

local CRUISE_SPEED     = 380     -- u/s, constant
local MAX_TURN_RATE    = 55      -- degrees per second max turn
local LIFETIME         = 45
local PROXIMITY_RADIUS = 180
local ENGINE_DELAY     = 0.5
local TARGET_Z_OFFSET  = 80

-- Ground trace so aim Z is never underground
local function SafeAimPos( ent )
    local p  = ent:GetPos()
    local tr = util.TraceLine({
        start  = p + Vector( 0, 0, 100 ),
        endpos = p - Vector( 0, 0, 1000 ),
        mask   = MASK_SOLID_BRUSHONLY,
        filter = ent,
    })
    local gz = tr.Hit and tr.HitPos.z or p.z
    return Vector( p.x, p.y, gz + TARGET_Z_OFFSET )
end

function ENT:Initialize()
    self:SetModel( "models/weapons/w_missile_launch.mdl" )
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

    -- Homing target is set via NWEntity by FireNikita right after
    -- Spawn()+Activate(). NWEntity survives the engine table reset.
    -- Plain self.TrackEnt = ... was wiped by Spawn() every time.
    self:SetNWEntity( "NikitaTrackEnt", NULL )

    self:SetVelocity( self:GetForward() * 120 )

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

    -- Read homing target from NWEntity (survives Spawn reset)
    local trackEnt = self:GetNWEntity( "NikitaTrackEnt", NULL )
    local aimPos
    if IsValid( trackEnt ) then
        aimPos = SafeAimPos( trackEnt )
    elseif self.FallbackTarget then
        aimPos = self.FallbackTarget
    end

    if aimPos then
        -- Proximity detonation
        if ( self:GetPos() - aimPos ):LengthSqr() < PROXIMITY_RADIUS * PROXIMITY_RADIUS then
            self:MissileDoExplosion() ; return true
        end

        -- Clamped turn steering
        local wantAngle = ( aimPos - self:GetPos() ):GetNormalized():Angle()
        local curAngle  = self:GetAngles()
        local maxDelta  = MAX_TURN_RATE * FrameTime()

        local function Clamp( cur, want )
            local d = math.NormalizeAngle( want - cur )
            return cur + math.Clamp( d, -maxDelta, maxDelta )
        end

        self:SetAngles( Angle(
            Clamp( curAngle.p, wantAngle.p ),
            Clamp( curAngle.y, wantAngle.y ),
            0
        ))
    end

    self:SetVelocity( self:GetForward() * CRUISE_SPEED )

    -- Manual world/entity collision (SOLID_NONE skips engine Touch)
    local tr = util.TraceLine({
        start  = self:GetPos(),
        endpos = self:GetPos() + self:GetForward() * ( CRUISE_SPEED * FrameTime() + 20 ),
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

    -- Debug every 0.5s
    if CurTime() > self._nextDebug then
        self._nextDebug = CurTime() + 0.5
        print( string.format(
            "[NikitaDBG] homing=%s aimPos=%s ang=%s spd=%.0f",
            tostring( IsValid( trackEnt ) ),
            tostring( aimPos ),
            tostring( self:GetAngles() ),
            self:GetVelocity():Length()
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
