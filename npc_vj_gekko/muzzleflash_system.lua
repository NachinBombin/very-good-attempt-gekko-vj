-- ============================================================
--  npc_vj_gekko / muzzleflash_system.lua
--  Client-side projected-texture muzzle flash for the Gekko.
--
--  Ported logic from l4d_mf_client.lua (L4D Muzzleflash addon).
--
--  Fires on:
--    GekkoMGFiring  (bool NW)    -- machine-gun burst, per-bullet
--    GekkoMFFire    (int NW)     -- single pulse for every other weapon
--                                   EXCEPT the grenade launcher
--
--  Size is randomised each flash within designer-tuned limits:
--    FOV    : 110 – 160  (controls spread / "size" of the cone)
--    FarZ   : 380 – 560  (how far the light reaches, ~4 m guaranteed)
--    Brightness: 1.5 – 3.0
-- ============================================================
if SERVER then return end

-- ============================================================
--  Constants
-- ============================================================
local MF_TEXTURE    = "effects/muzzleflash_light"
local MF_NEARZ      = 4
local MF_LIFETIME   = 0.055

local MF_FOV_MIN    = 110
local MF_FOV_MAX    = 160
local MF_FARZ_MIN   = 380     -- guarantees ~4 m illumination at minimum
local MF_FARZ_MAX   = 560
local MF_BRIGHT_MIN = 1.5
local MF_BRIGHT_MAX = 3.0

local MF_COLOR_R    = 255
local MF_COLOR_G    = 180
local MF_COLOR_B    = 80

-- MG: fire a flash once every N bullets so the table stays small
local MG_FLASH_EVERY = 2

-- Attachment candidates, in priority order
local ATTACH_NAMES = { "muzzle", "muzzle_flash", "muzzleflash", "attach_muzzle", "muzzle1" }
local ATTACH_SEARCH_MAX = 32

-- Fallback muzzle offset in entity-local space (matches l4d_mf_client.lua)
local FALLBACK_OFFSET = Vector(14, 0, -2)

-- ============================================================
--  Attachment cache (model -> best attachment index)
-- ============================================================
local _attachCache = {}

local function FindBestAttachment(ent)
    if not IsValid(ent) then return nil end
    local mdl = ent:GetModel() or ""
    if _attachCache[mdl] ~= nil then return _attachCache[mdl] end

    -- try named candidates first
    for _, name in ipairs(ATTACH_NAMES) do
        local idx = ent:LookupAttachment(name)
        if tonumber(idx) and idx > 0 then
            _attachCache[mdl] = idx
            return idx
        end
    end

    -- fall back to the most-forward attachment
    local best, bestDot = nil, -1e9
    local entPos = ent:GetPos()
    local entFwd = ent:GetForward()
    for i = 1, ATTACH_SEARCH_MAX do
        local att = ent:GetAttachment(i)
        if att and att.Pos then
            local dir = att.Pos - entPos
            local len = dir:Length()
            if len > 0 then
                local dot = entFwd:Dot(dir / len)
                if dot > bestDot then bestDot = dot ; best = i end
            end
        end
    end

    _attachCache[mdl] = best
    return best
end

-- ============================================================
--  Muzzle transform: returns pos, ang or nil
-- ============================================================
local function GetMuzzleTransform(ent)
    if not IsValid(ent) then return nil end

    -- try attachment index 3 first (ATT_MACHINEGUN, always present)
    local att3 = ent:GetAttachment(3)
    if att3 then return att3.Pos, att3.Ang end

    -- generic forward-most attachment
    local idx = FindBestAttachment(ent)
    if idx then
        local att = ent:GetAttachment(idx)
        if att then return att.Pos, att.Ang end
    end

    -- absolute fallback
    return ent:LocalToWorld(FALLBACK_OFFSET), ent:GetAngles()
end

-- ============================================================
--  Active flash table  { proj, dieTime }
-- ============================================================
local _flashes = {}

-- ============================================================
--  Create one projected-texture flash
-- ============================================================
local function SpawnFlash(pos, ang)
    local proj = ProjectedTexture()
    if not proj then return end

    proj:SetTexture(MF_TEXTURE)
    proj:SetNearZ(MF_NEARZ)
    proj:SetFOV(math.Rand(MF_FOV_MIN,    MF_FOV_MAX))
    proj:SetFarZ(math.Rand(MF_FARZ_MIN,  MF_FARZ_MAX))
    proj:SetBrightness(math.Rand(MF_BRIGHT_MIN, MF_BRIGHT_MAX))
    proj:SetColor(Color(MF_COLOR_R, MF_COLOR_G, MF_COLOR_B))
    if proj.SetEnableShadows then proj:SetEnableShadows(true) end
    proj:SetPos(pos)
    proj:SetAngles(ang)
    proj:Update()

    table.insert(_flashes, {
        proj    = proj,
        dieTime = CurTime() + MF_LIFETIME,
    })
end

local function TryFlash(ent)
    if not IsValid(ent) then return end
    local pos, ang = GetMuzzleTransform(ent)
    if pos and ang then SpawnFlash(pos, ang) end
end

-- ============================================================
--  Lifetime ticker
-- ============================================================
hook.Add("Think", "GekkoMF_Lifetime", function()
    local now = CurTime()
    for i = #_flashes, 1, -1 do
        local d = _flashes[i]
        if not IsValid(d.proj) or now > d.dieTime then
            if IsValid(d.proj) then d.proj:Remove() end
            table.remove(_flashes, i)
        end
    end
end)

-- ============================================================
--  Per-entity think driver
--  Call this from the Gekko's ENT:Think / ENT:Draw tick
--  (wired in via EntityThink hook below).
-- ============================================================
local _mgBulletCounter = {}

local function GekkoMF_Think(ent)
    if not IsValid(ent) then return end

    -- --------------------------------------------------------
    --  MG burst: fires a flash every MG_FLASH_EVERY bullets
    -- --------------------------------------------------------
    local mgFiring = ent:GetNWBool("GekkoMGFiring", false)
    if mgFiring then
        _mgBulletCounter[ent] = (_mgBulletCounter[ent] or 0) + 1
        if _mgBulletCounter[ent] >= MG_FLASH_EVERY then
            _mgBulletCounter[ent] = 0
            TryFlash(ent)
        end
    else
        _mgBulletCounter[ent] = 0
    end

    -- --------------------------------------------------------
    --  Single-shot pulse: every other weapon except GRENADE
    -- --------------------------------------------------------
    local pulse = ent:GetNWInt("GekkoMFFire", 0)
    if pulse ~= (ent._mfLastPulse or 0) then
        ent._mfLastPulse = pulse
        TryFlash(ent)
    end
end

-- ============================================================
--  EntityThink hook – runs GekkoMF_Think for every Gekko
-- ============================================================
hook.Add("EntityThink", "GekkoMF_EntityThink", function(ent)
    if not IsValid(ent) then return end
    if ent:GetClass() ~= "npc_vj_gekko" then return end
    GekkoMF_Think(ent)
end)

-- ============================================================
--  USAGE NOTE (server side, init.lua)
--  In every weapon fire function EXCEPT FireGrenadeLauncher,
--  add one line after the shot to pulse GekkoMFFire:
--
--    ent._mfFirePulse = (ent._mfFirePulse or 0) + 1
--    ent:SetNWInt("GekkoMFFire", ent._mfFirePulse)
--
--  GekkoMGFiring is already set by FireMGBurst, so the MG
--  is handled automatically by the Think loop above.
-- ============================================================
