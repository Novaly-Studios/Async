# Async

A tree-based thread lifecycle library which sits on top of the Roblox task library.

## Concepts

### Thread Result

### Thread Termination

## Usage Examples

### 1: Spawning Threads

```lua
local function Animate(Item, Damping, Frequency, Properties)
    -- ...
end

local TestAnimation = Async.Spawn(function(OnFinish)
    local function InitialState()
        Animate(Workspace.Part1, 1, 5, {
            Position = Vector3.new(0, 10, 0);
        })
        Animate(Workspace.Part2, 1, 100, {
            Position = Vector3.new(0, 10, 0);
        })
    end

    OnFinish(InitialState)
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

### 2: Waiting for Thread Results

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
