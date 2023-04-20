# Async

A tree-based thread lifecycle library which sits on top of the Roblox task library.

## 1: Spawning Threads & Cleanup Handlers

```lua
local function Animate(Item, Damping, Frequency, Properties)
    -- ...
end

local TestAnimation = Async.Spawn(function()
    local function InitialState()
        Animate(Workspace.Part1, 1, 5, {
            Position = Vector3.new(0, 10, 0);
        })
        Animate(Workspace.Part2, 1, 100, {
            Position = Vector3.new(0, 10, 0);
        })
    end

    Async.OnFinish(InitialState)
    InitialState()

    local function AnimatePart1()
        for Step = 1, 3 do
            Animate(Workspace.Part1, 1, 5, {
                Position = Vector3.new(0, 10 + 10 * Step, 0);
            })

            task.wait(1)
        end
    end

    local function AnimatePart2()
        for Step = 1, 3 do
            Animate(Workspace.Part2, 1, 100, {
                Position = Vector3.new(0, 10 + 10 * Step, 0);
            })

            task.wait(1)
        end
    end

    task.wait(1) -- 1 sec delay before animation starts

    Async.Spawn(AnimatePart1)
    Async.Spawn(AnimatePart2)
end)

task.wait(2)

-- This will not only cancel the animation thread, but also the sub-threads
-- which the animation thread spawned (AnimatePart1, AnimatePart2). When
-- cancelled, it will call OnFinish, and reset the animation to the initial
-- state (InitialState).
Async.Cancel(TestAnimation)
```

## 2: Waiting for Thread Results

```lua
local Success, Result = Async.Await(Async.Spawn(function()
    local Value = math.random()
    task.wait(2)

    if (Value > 0.5) then
        return false, Value
    end

    return true, Value
end))

print(Success, Result)
```

## 3: Waiting for All Thread Results

```lua
print(Async.AwaitAll({
    Async.Spawn(function()
        task.wait(1)
        return true, "Delayed"
    end);
    Async.Spawn(function()
        return true, "Immediate"
    end);
}))
--> {{true, "Immediate"}, {true, "Delayed"}}
```

## 4: Waiting for First Thread Result

```lua
print(Async.AwaitFirst({
    Async.Spawn(function()
        task.wait(1)
        return true, "Last"
    end);
    Async.Spawn(function()
        return true, "First"
    end);
}))
--> true, "First"
```

## 5: Blockable Timers

```lua
local Characters = {}
local Thread = Async.Timer(1, function()
    table.clear(Characters)

    for _, Player in game.Players:GetChildren() do
        local Char = Player.Character

        if (not Char) then
            return
        end

        table.insert(Characters, Char)
    end
end, "FindPlayers")
-- "FindPlayers" will show up in the Microprofiler, though always ensure the timer does not block if the tag is specified

Async.Delay(5, Async.Cancel, Thread)
```
