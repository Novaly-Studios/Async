local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Async = require(ReplicatedFirst:WaitForChild("Async"))

local TaskSpawn = task.spawn
local AsyncSpawn = Async.Spawn

return {
    ParameterGenerator = function()
        return
    end;

    Functions = {
        ["task.spawn / Complete"] = function()
            for _ = 1, 100 do
                TaskSpawn(function() end)
            end
        end;

        ["Async.Spawn / Complete"] = function()
            for _ = 1, 100 do
                AsyncSpawn(function() end)
            end
        end;

        ["task.spawn / Error"] = function()
            TaskSpawn(function() error("") end)
        end;

        ["Async.Spawn / Error"] = function()
            AsyncSpawn(function() error("") end)
        end;
    };
}