-- cl_init.lua  (CLIENT)
-- Visual: bright tracer-dot sprite on the round head.
-- Trail is attached server-side in npc_vj_gekko/init.lua via util.SpriteTrail.
include("shared.lua")

local SPRITE_MAT  = Material("sprites/light_glow02_add")
local SPRITE_SIZE = 4   -- world units, small bright dot
local SPRITE_COL  = Color(255, 240, 180, 255)  -- warm yellow tracer

-- =========================================================================
-- Initialise
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end
    self:SetRenderBounds(Vector(-8,-8,-8), Vector(8,8,8))

    -- Dynamic light: small, tight, warm
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.style      = 0
        dlight.r          = 255
        dlight.g          = 210
        dlight.b          = 80
        dlight.brightness = 6
        dlight.size       = 48
        dlight.decay      = 0
        dlight.dietime    = CurTime() + 9999
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

    if self._dynLight then
        self._dynLight.pos     = pos
        self._dynLight.dietime = CurTime() + 0.05
    end
end

function ENT:OnRemove()
end
