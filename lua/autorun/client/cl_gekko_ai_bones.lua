net.Receive("GekkoAI_LogBones", function()
    local ent = net.ReadEntity()

    timer.Simple(0.1, function()
        if not IsValid(ent) then return end

        ent:SetupBones()

        local count = ent:GetBoneCount() or 0
        print("[GekkoAI] ===== BONE LIST =====")
        print("[GekkoAI] Total bones:", count)

        for i = 0, count - 1 do
            local parent = ent:GetBoneParent(i)
            print(string.format("[GekkoAI] [%2d] %-40s parent=%d", i, ent:GetBoneName(i) or "nil", parent or -1))
        end

        print("[GekkoAI] ===== END BONE LIST =====")
    end)
end)
