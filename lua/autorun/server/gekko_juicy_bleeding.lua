-- Code reference: Custom Blood Bleeding 3332958092 Universal SMOD Bleeding Effect 2840303209

include("gekko_juicy_bleeding/extensions.lua")
local active_bloodstreams = {}

local function OFBleeding_CleanUp()
 for i = #active_bloodstreams, 1, -1 do
 if not IsValid(active_bloodstreams[i]) then
 table.remove(active_bloodstreams, i)
 end
 end
end

-- ============================================================
-- CORE: Spawn bleeding particle effect (byte-for-byte identical logic)
-- ============================================================
local function OFBleeding_DO(pos, ang, bone, rag, islarge, type)
 if not rag or not bone then return end

 if GetConVar("gekko_juicy_bleeding_enabled"):GetInt() ~= 1 then return end
 if GetConVar("ai_serverragdolls"):GetInt() ~= 1 then return end
 if not rag.juicy_next_bloodstream then rag.juicy_next_bloodstream = CurTime() end
 if rag.juicy_next_bloodstream > CurTime() then return end
 local cooldown = math.floor(GetConVar("gekko_juicy_bleeding_cooldown"):GetFloat() * 10) / 10
 if type ~= 1 then
 rag.juicy_next_bloodstream = CurTime() + cooldown
 end

 OFBleeding_CleanUp()
 if #active_bloodstreams >= GetConVar("gekko_juicy_bleeding_maxactive"):GetInt() then return end

 local hiddenmodel = ents.Create("prop_dynamic")
 hiddenmodel:SetModel("models/error.mdl")
 hiddenmodel:Spawn()
 hiddenmodel:SetModelScale(0)
 hiddenmodel:SetNotSolid(true)
 hiddenmodel:DrawShadow(false)
 hiddenmodel:SetNW2Bool("gekko_juicy_bleeding_debug", true)
 hiddenmodel:SetNW2String("gekko_juicy_bleeding_debug_bone_name", rag:GetBoneName(bone) or tostring(bone))
 hiddenmodel:SetNW2Int("gekko_juicy_bleeding_debug_type", type or 0)

 SafeRemoveEntityDelayed(hiddenmodel, 2)

 hiddenmodel:FollowBone(rag, bone)

 hiddenmodel:SetLocalAngles(ang)
 hiddenmodel:SetLocalPos(pos)

 local use_darker = GetConVar("gekko_juicy_bleeding_darker") and GetConVar("gekko_juicy_bleeding_darker"):GetBool()
 local effect_name
 if use_darker then
 effect_name = islarge and "gekko_juicy_bleeding_darker_spray" or "gekko_juicy_bleeding_darker_spray_b"
 else
 effect_name = islarge and "gekko_juicy_bleeding_spray" or "gekko_juicy_bleeding_spray_b"
 end

 if type ~= 3 then
 ParticleEffectAttach(effect_name or "gekko_juicy_bleeding_spray_b", PATTACH_ABSORIGIN_FOLLOW, hiddenmodel, 0)
 else
 timer.Simple(0.1, function()
 if IsValid(hiddenmodel) then
 ParticleEffectAttach(effect_name or "gekko_juicy_bleeding_spray_b", PATTACH_ABSORIGIN_FOLLOW, hiddenmodel, 0)
 end
 end)
 end
 table.insert(active_bloodstreams, hiddenmodel)

 rag._active_bloodstream_points = rag._active_bloodstream_points or {}
 table.insert(rag._active_bloodstream_points, {
 time = CurTime(),
 lpos = pos,
 lang = ang,
 bone = bone,
 islarge = islarge,
 })

 local keep = {}
 for _, v in ipairs(rag._active_bloodstream_points) do
 if v.time and v.time > (CurTime() - 2) then
 table.insert(keep, v)
 end
 end
 rag._active_bloodstream_points = keep
end

-- ============================================================
-- PUBLIC API: Call this from the Gekko NPC's OnTakeDamage hook
-- Usage: GekkoTriggerJuicyBleed(self, dmginfo)
-- ============================================================
function GekkoTriggerJuicyBleed(ent, dmginfo)
 if not IsValid(ent) or not ent:IsNPC() then return end
 if GetConVar("gekko_juicy_bleeding_enabled"):GetInt() ~= 1 then return end
 if GetConVar("ai_serverragdolls"):GetInt() ~= 1 then return end

 local dmgpos = dmginfo:GetDamagePosition()
 local dmgdir = dmginfo:GetDamageForce()
 if not isvector(dmgpos) then return end
 if not isvector(dmgdir) or dmgdir:LengthSqr() <= 0 then
 dmgdir = ent:GetForward()
 end

 local bone = dmginfo:GetAnimBone(ent)
 if not bone then return end

 local bone_pos, bone_ang = ent:GetBonePosition(bone)
 if not isvector(bone_pos) then return end
 bone_ang = bone_ang or Angle(0, 0, 0)

 local lpos, lang = WorldToLocal(dmgpos, dmgdir:Angle(), bone_pos, bone_ang)
 local lnum = dmginfo:GetDamage()
 local islarge = lnum and lnum >= 40
 if dmginfo:IsDamageType(DMG_BUCKSHOT) or dmginfo:IsDamageType(DMG_SNIPER) or dmginfo:IsDamageType(DMG_NEVERGIB) then
 islarge = true
 end

 local bleed_type = 0
 if ent:IsRagdoll() then
 bleed_type = 2
 elseif lnum >= ent:Health() then
 bleed_type = 3
 end

 OFBleeding_DO(lpos, lang, bone, ent, islarge, bleed_type)
end

-- ============================================================
-- RAGDOLL HANDOFF: Preserve bleeding when NPC becomes ragdoll
-- ============================================================
hook.Add("CreateEntityRagdoll", "GekkoJuicyBleed_Ragdoll", function(ent, rag)
 if GetConVar("gekko_juicy_bleeding_enabled"):GetInt() ~= 1 then return end
 if GetConVar("ai_serverragdolls"):GetInt() ~= 1 then return end
 rag.allow_gekko_juicy_bleeding = true

 if ent._active_bloodstream_points then
 for _, v in ipairs(ent._active_bloodstream_points) do
 if v and v.lpos and v.lang and v.bone then
 OFBleeding_DO(v.lpos, v.lang, v.bone, rag, v.islarge or false, 1)
 end
 end
 rag._active_bloodstream_points = ent._active_bloodstream_points
 end
end)

-- ============================================================
-- CLEANUP: Remove helper entities on NPC/ragdoll removal
-- ============================================================
hook.Add("EntityRemoved", "GekkoJuicyBleed_Cleanup", function(ent)
 if ent._active_bloodstream_points then
 ent._active_bloodstream_points = nil
 end
end)