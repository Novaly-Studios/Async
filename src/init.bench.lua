local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local Root = ReplicatedFirst:WaitForChild("Async")
        local TypeGuard = require(Root.Parent.TypeGuard)
        local Async = require(Root)

local function GenerateBenchmarks(Context: string, AsyncSpawn)
    return {
        [Context .. "Spawn"] = function()
            for _ = 1, 100 do
                AsyncSpawn(function() end)
            end
        end;
    }
end

local CombinedBenchmarks = {}
local OldAsync = Root:FindFirstChild("Old")

if (OldAsync) then
    for Name, Test in GenerateBenchmarks("OldAsync", require(OldAsync).Spawn) do
        CombinedBenchmarks[Name] = Test
    end
end

for Name, Test in GenerateBenchmarks(">NewAsync", Async.Spawn) do
    CombinedBenchmarks[Name] = Test
end

for Name, Test in GenerateBenchmarks("RobloxAsync", task.spawn) do
    CombinedBenchmarks[Name] = Test
end

TypeGuard.SetContextEnabled("Async", false)
TypeGuard.SetContextEnabled("Old", false)

return {
    ParameterGenerator = function()
        return
    end;

    Functions = CombinedBenchmarks;
}