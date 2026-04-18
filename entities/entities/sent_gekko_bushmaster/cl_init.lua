-- cl_init.lua  (CLIENT)
-- Visual: bright tracer-dot sprite on the round head + dynamic light.
-- Trail is attached server-side in npc_vj_gekko/init.lua via util.SpriteTrail.
include("shared.lua")

local SPRITE_MAT  = Material("sprites/light_glow02_add")
local SPRITE_SIZE = 4   -- world units, small bright dot
local SPRITE_COL  = Color(255, 240, 180, 255)  -- warm yellow tracer
local LIFETIME    = 12  -- must match server-side LIFETIME constant

-- =========================================================================
-- Initialise
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end

    -- Render bounds must be large enough that the engine never culls Draw()
    -- while the shell is in flight.  At 3900 u/s the projectile outruns an
    -- 8-unit box in a single tick, causing Draw() to be skipped and the
    -- dynamic light's dietime to go stale.
    self:SetRenderBounds(Vector(-64, -64, -64), Vector(64, 64, 64))

    -- Set dietime to full lifetime up front.  We no longer refresh it in
    -- Draw() so the light survives any cull frames automatically.
    -- OnRemove() zeroes dietime so the light dies with the entity.
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.style      = 0
        dlight.r          = 255
        dlight.g          = 210
        dlight.b          = 80
        dlight.brightness = 6
        dlight.size       = 48
        dlight.decay      = 0
        dlight.dietime    = CurTime() + LIFETIME
    end
    self._dynLight = dlight
end

-- =========================================================================
-- Draw
-- =========================================================================
function ENT:Draw()
    -- Do NOT draw the model (0.10 scale = invisible anyway)
    -- Draw a bright additive sprite so the round is visible at any distance
    local pos = self:GetPos()
    render.SetMaterial(SPRITE_MAT)
    render.DrawSprite(pos, SPRITE_SIZE, SPRITE_SIZE, SPRITE_COL)

    -- Only update position; dietime is managed by Initialize/OnRemove
    if self._dynLight then
        self._dynLight.pos = pos
    end
end

-- =========================================================================
-- OnRemove: kill the light immediately so it doesn't ghost after removal
-- =========================================================================
function ENT:OnRemove()
    local dl = DynamicLight(self:EntIndex())
    if dl then dl.dietime = 0 end
end
