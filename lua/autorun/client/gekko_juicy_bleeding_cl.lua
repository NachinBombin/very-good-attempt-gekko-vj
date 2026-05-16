-- Code reference: Custom Blood Bleeding 3332958092 Universal SMOD Bleeding Effect 2840303209

hook.Add("PopulateToolMenu", "GekkoJuicyBleed_PopulateMenu", function()
 spawnmenu.AddToolMenuOption("Utilities", "Admin", "GekkoJuicyBleedSettings", "Gekko Juicy Bleeding", "", "", function(panel)
 panel:ClearControls()

 panel:CheckBox("Enable Bleeding Effect", "gekko_juicy_bleeding_enabled")
 panel:CheckBox("Enable Bleeding for Players", "gekko_juicy_bleeding_player"):SetTooltip("Allow players to show blood effects when damaged")
 panel:NumSlider("Maximum Active Blood Effects", "gekko_juicy_bleeding_maxactive", 10, 500, 0)
 panel:NumSlider("Bleeding Cooldown Time", "gekko_juicy_bleeding_cooldown", 0, 1, 1)
 panel:CheckBox("Debug Mode", "gekko_juicy_bleeding_debug")
 panel:CheckBox("Use Darker Blood Color", "gekko_juicy_bleeding_darker")

 local keepcorpseslabel = language.GetPhrase and language.GetPhrase("#menubar.npcs.keepcorpses") or "Keep corpses"

 panel:Help("Make sure that '" .. keepcorpseslabel .. "' is CHECKED.\nOtherwise, bleeding effects will not work.")

 panel:CheckBox(keepcorpseslabel .. " (Must be Enabled)", "ai_serverragdolls")

 panel:Help("Note: Blood effects for zombies are disabled due to bugs.\n\nAlso, some mod may cause the direction of NPC ragdoll bleeding effects to be inaccurate.")
 end)
end)

hook.Add("PostDrawTranslucentRenderables", "GekkoJuicyBleed_DebugHiddenModel", function(depth, skybox, skybox3d)
 if skybox or skybox3d then return end

 local cvar = GetConVar("gekko_juicy_bleeding_debug")
 if not cvar or not cvar:GetBool() then return end

 for _, ent in ipairs(ents.GetAll()) do
 if not IsValid(ent) then continue end
 if not ent:GetNW2Bool("gekko_juicy_bleeding_debug", false) then continue end

 local pos = ent:GetPos()
 local ang = ent:GetAngles()

 -- 根据type选择球的颜色
 local debug_type = ent:GetNW2Int("gekko_juicy_bleeding_debug_type", 0)
 local sphereColor = Color(255, 255, 0) --活人
 if debug_type == 1 then --过渡
 sphereColor = Color(0, 128, 255)
 elseif debug_type == 2 then --布娃娃
 sphereColor = Color(0, 255, 0)
 elseif debug_type == 3 then --致命一击
 sphereColor = Color(255, 0, 0)
 end

 -- 绘制球
 render.SetColorMaterial()
 render.DrawWireframeSphere(pos, 4, 12, 12, sphereColor, true)

 local arrowLength = 16
 local arrowRadius = 2
 local back = ang:Forward() * -1 -- 向后
 local startPos = pos
 local endPos = pos + back * arrowLength

 -- 主轴线（正后方）
 render.DrawLine(startPos, endPos, Color(255, 0, 0), false)

 -- 箭头两侧
 local tip = endPos
 local base = endPos - back * 6
 local left = ang:Right() * arrowRadius
 local up = ang:Up() * arrowRadius

 render.DrawLine(tip, base + left, Color(255, 0, 0), false)
 render.DrawLine(tip, base - left, Color(255, 0, 0), false)
 render.DrawLine(tip, base + up, Color(255, 0, 0), false)
 render.DrawLine(tip, base - up, Color(255, 0, 0), false)

 -- 显示骨骼名字
 local bone_name = ent:GetNW2String("gekko_juicy_bleeding_debug_bone_name", "unknown")
 local text_ang = Angle(0, EyeAngles().y - 90, 90)
 cam.Start3D2D(pos + Vector(0, 0, 6), text_ang, 0.08)
 draw.SimpleTextOutlined(
 bone_name,
 "DermaDefaultBold",
 0,
 0,
 Color(255, 0, 0),
 TEXT_ALIGN_CENTER,
 TEXT_ALIGN_CENTER,
 1,
 Color(0, 0, 0, 200)
 )
 cam.End3D2D()
 end
end)