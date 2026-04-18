-- cl_init.lua  (CLIENT)
-- Visual: model + tracer sprite + nozzle dynamic light + flame exhaust.
-- Trail is attached server-side in npc_vj_gekko/init.lua via util.SpriteTrail.
include("shared.lua")

local SPRITE_MAT  = Material("sprites/light_glow02_add")
local SPRITE_SIZE = 4
local SPRITE_COL  = Color(255, 240, 180, 255)

-- =========================================================================
-- Initialize
-- =========================================================================
function ENT:Initialize()
    if not IsValid(self) then return end
    -- Large render bounds so Draw() is never culled at 2900 u/s
    self:SetRenderBounds(Vector(-64, -64, -64), Vector(64, 64, 64))
    self.Emitter = ParticleEmitter(self:GetPos(), false)
end

-- =========================================================================
-- Think  (runs on client timeline, immune to Draw cull)
-- =========================================================================
function ENT:Think()
    local pos     = self:GetRenderOrigin()
    local backDir = -self:GetForward()
    local exhaustPos = pos + backDir * 14

    -- --------------------------------------------------------
    --  Dynamic light: bright warm nozzle glow
    --  DieTime refreshed every Think so it stays alive regardless
    --  of draw culling (same pattern as Nikita).
    --  size=380: large enough to cast on nearby geometry in open space
    -- --------------------------------------------------------
    local dlight = DynamicLight(self:EntIndex())
    if dlight then
        dlight.pos        = exhaustPos
        dlight.r          = 255
        dlight.g          = 210
        dlight.b          = 80
        dlight.brightness = 6
        dlight.Decay      = 1200
        dlight.Size       = 380
        dlight.DieTime    = CurTime() + 0.05
    end

    if not IsValid(self.Emitter) then return end
    self.Emitter:SetPos(pos)

    -- --------------------------------------------------------
    --  Orange flame core
    -- --------------------------------------------------------
    for i = 1, 4 do
        local part = self.Emitter:Add(
            "particles/flamelet" .. math.random(1, 5),
            exhaustPos + VectorRand() * 6
        )
        if part then
            part:SetVelocity(backDir * math.Rand(80, 200) + VectorRand() * 18)
            part:SetDieTime(math.Rand(0.08, 0.18))
            part:SetStartAlpha(220)
            part:SetEndAlpha(0)
            part:SetStartSize(math.Rand(18, 32))
            part:SetEndSize(math.Rand(4, 10))
            part:SetColor(255, math.random(100, 180), 0)
            part:SetRoll(math.Rand(0, 360))
            part:SetRollDelta(math.Rand(-2, 2))
            part:SetGravity(Vector(0, 0, 12))
            part:SetCollide(false)
        end
    end

    -- --------------------------------------------------------
    --  Sparks
    -- --------------------------------------------------------
    for i = 1, 3 do
        local part = self.Emitter:Add(
            "effects/spark",
            exhaustPos + VectorRand() * 4
        )
        if part then
            part:SetVelocity(backDir * math.Rand(300, 700) + VectorRand() * 35)
            part:SetDieTime(math.Rand(0.10, 0.25))
            part:SetStartAlpha(255)
            part:SetEndAlpha(0)
            part:SetStartSize(math.Rand(1, 3))
            part:SetEndSize(0)
            part:SetColor(255, 230, 160)
            part:SetGravity(Vector(0, 0, -320))
            part:SetCollide(true)
            part:SetBounce(0.2)
        end
    end
end

-- =========================================================================
-- Draw
-- =========================================================================
function ENT:Draw()
    self:DrawModel()
    local pos = self:GetRenderOrigin()
    render.SetMaterial(SPRITE_MAT)
    render.DrawSprite(pos, SPRITE_SIZE, SPRITE_SIZE, SPRITE_COL)
end

-- =========================================================================
-- OnRemove
-- =========================================================================
function ENT:OnRemove()
    if IsValid(self.Emitter) then self.Emitter:Finish() end
    local dl = DynamicLight(self:EntIndex())
    if dl then dl.DieTime = 0 end
end
