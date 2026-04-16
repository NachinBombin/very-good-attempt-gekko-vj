-- cl_init.lua  (CLIENT)
-- Render-only: model + scaled sprite trail + engine dynamic light.
-- rockettrail particle replaced with util.SpriteTrail at 0.35x size
-- so the Bushmaster round has a visually smaller tail than standard missiles.
include("shared.lua")

-- Rockettrail reference sizes (full):  startWidth~22, endWidth~1, lifetime~0.6
-- 0.35x scale:
local TRAIL_START  = 7.7   -- 22 * 0.35
local TRAIL_END    = 0.35  --  1 * 0.35
local TRAIL_TIME   = 0.21  --  0.6 * 0.35
local TRAIL_MAT    = "trails/smoke"
local TRAIL_COLOR  = Color(210, 210, 200, 180)

-- =========================================================================
-- Initialise
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end

    self:SetRenderBounds(
        Vector(-24, -24, -24),
        Vector( 24,  24,  24)
    )

    -- Scaled sprite trail instead of the full rockettrail particle system
    util.SpriteTrail(
        self, 0,
        TRAIL_COLOR,
        false,
        TRAIL_START, TRAIL_END,
        TRAIL_TIME,
        1 / TRAIL_START,
        TRAIL_MAT
    )

    -- Acid-lime tracer light: r=180 g=255 b=40
    -- Distinct from orbital RPG (orange/amber) and standard rockets (white/yellow)
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.style      = 0
        dlight.r          = 180
        dlight.g          = 255
        dlight.b          = 40
        dlight.brightness = 9.5
        dlight.size       = 30
        dlight.decay      = 0
        dlight.dietime    = CurTime() + 9999
    end
    self._dynLight = dlight
end

-- =========================================================================
-- Draw
-- =========================================================================
function ENT:Draw()
    self:DrawModel()

    -- Keep the dynamic light anchored to current position each frame
    if self._dynLight then
        self._dynLight.pos     = self:GetPos()
        self._dynLight.dietime = CurTime() + 0.05
    end
end

-- =========================================================================
-- Cleanup
-- =========================================================================
function ENT:OnRemove()
    -- SpriteTrail cleans itself up automatically; nothing extra needed
end
