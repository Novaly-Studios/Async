--!optimize 2
--!native
--!strict

-- Allows easy command bar paste.
if (not script and Instance) then
    script = game:GetService("ReplicatedFirst").Async.Task
end

local Async = require(script.Parent.Async)
    local AwaitDescendants = Async.AwaitDescendants
    local ResolveRoot = Async.ResolveRoot
    local SpawnTimed = Async.SpawnTimed
    local AwaitFirst = Async.AwaitFirst
    local CancelRoot = Async.CancelRoot
    local FireSignal = Async.FireSignal
    local AwaitAll = Async.AwaitAll
    local Results = Async.Results
    local Resolve = Async.Resolve
    local Retries = Async.Retries
    local Cancel = Async.Cancel
    local Delay = Async.Delay
    local Defer = Async.Defer
    local Spawn = Async.Spawn
    local Await = Async.Await

--- The Task class extends the base functionality of Async with better typing support at the expense of performance.
local Task = {}
Task.__index = Task

type TaskCallback<Result> = ((...any) -> (Result))

export type Task<Result> = {
    DidComplete: ((self: Task<Result>) -> boolean);
    DidSucceed: ((self: Task<Result>) -> boolean);
    DidFail: ((self: Task<Result>) -> boolean);

    Await: ((self: Task<Result>, Timeout: number?) -> (boolean, Result));
    Get: ((self: Task<Result>) -> (boolean, Result));

    AwaitValue: ((self: Task<Result>, Timeout: number?) -> (Result));
    GetValue: ((self: Task<Result>) -> (Result));

    ResolveRoot: ((self: Task<Result>, Result: Result?) -> ());
    Resolve: ((self: Task<Result>, Result: Result?) -> ());

    CancelRoot: ((self: Task<Result>, Result: Result?) -> ());
    Cancel: ((self: Task<Result>, Result: Result?) -> ());

    AwaitDescendants: ((self: Task<Result>, Timeout: number?) -> ());
    FireSignal: ((self: Task<Result>, Data: any, Depth: number?, AllowFinishedThreads: boolean?) -> ());
}

--- Creates a new Task whose execution is delayed for a certain time.
function Task.usingDelay<Return>(DelayTime: number, Callback: TaskCallback<Return>, ...: any): Task<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED">
    local self = setmetatable({Delay(DelayTime, Callback, ...)}, Task)
    return self :: any
end

--- Creates a new Task whose execution is deferred to the next defer point.
function Task.usingDefer<Return>(Callback: TaskCallback<Return>, ...: any): Task<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED">
    local self = setmetatable({Defer(Callback, ...)}, Task)
    return self :: any
end

--- Creates a new Task whose execution is time limited.
function Task.usingTimeLimit<Return>(Callback: TaskCallback<Return>, Timeout: number?): Task<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT">
    local self = setmetatable({SpawnTimed(Callback, Timeout)}, Task)
    return self :: any
end

function Task.usingSpawn<Return>(Callback: TaskCallback<Return>, ...: any): Task<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED">
    local self = setmetatable({Spawn(Callback, ...)}, Task)
    return self :: any
end

function Task.usingRetries<Return>(Callback: TaskCallback<Return>, Count: number, Delay: number?): Task<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "RETRIES_EXHAUSTED">
    local self = setmetatable({Retries(Callback, Count, Delay)}, Task)
    return self :: any
end

--- Time limit as default is safer. It forces the user to think about
--- how long the task should take and prevents memory leaks.
Task.new = Task.usingTimeLimit

--- Returns a boolean indicating whether the task has completed yet.
function Task:DidComplete()
    local Success = Results(self[1])
    return Success ~= nil
end

--- Returns a boolean indicating whether the task completed successfully.
function Task:DidSucceed()
    local Success = Results(self[1])
    return Success == true
end

--- Returns a boolean indicating whether the task failed to complete.
function Task:DidFail()
    local Success = Results(self[1])
    return Success == false
end

--- Obtains the success indicator and results from the task.
--- @see Async.Results
function Task:Get()
    return Results(self[1])
end

--- Obtains only the value result from the task.
function Task:GetValue()
    local _, Value = Results(self[1])
    return Value
end

--- Awaits the success indicator and results from the task, with an
--- optional mapper to transform the results on failure or success.
--- @see Async.Await
function Task:Await(Timeout)
    return Await(self[1], Timeout)
end

--- Awaits only the value result from the task.
function Task:AwaitValue(Timeout)
    local _, Value = Await(self[1], Timeout)
    return Value
end

--- @see Async.Cancel
function Task:Cancel(Result)
    Cancel(self[1], Result)
end

--- @see Async.Resolve
function Task:Resolve(Result)
    Resolve(self[1], Result)
end

--- @see Async.CancelRoot
function Task:CancelRoot(Result)
    CancelRoot(self[1], Result)
end

--- @see Async.ResolveRoot
function Task:ResolveRoot(Result)
    ResolveRoot(self[1], Result)
end

--- Waits for the task and its descendant tasks (or threads spawned with Async) to complete.
--- @see Async.AwaitDescendants
function Task:AwaitDescendants(Timeout)
    return AwaitDescendants(self[1], Timeout)
end

--- Fires a signal to the task and its descendant tasks (or threads spawned with Async).
--- @see Async.FireSignal
function Task:FireSignal(Data, Depth, AllowFinishedThreads)
    FireSignal(self[1], Data, Depth, AllowFinishedThreads)
end

--- Awaits the results from an array of Tasks.
--- @see Async.AwaitAll
function Task.AwaitAll<T>(Tasks: {Task<T>}): {{T}}
    local Results = table.create(#Tasks)

    for _, Task in Tasks do
        table.insert(Results, Task[1])
    end

    return AwaitAll(Results)
end

--- Awaits the values from an array of Tasks.
--- @see Async.AwaitAll
function Task.AwaitAllValues<T>(Tasks: {Task<T>}): {T}
    local Results = table.create(#Tasks)

    for _, Task in Tasks do
        table.insert(Results, Task[1])
    end

    local Temp = AwaitAll(Results)

    for Index, Pair in Temp do
        Results[Index] = Pair[2]
    end

    return Temp :: any
end

--- Awaits the results from the first completed Task.
--- @see Async.AwaitFirst
function Task.AwaitFirst<T>(Tasks: {Task<T>}): (boolean, T?)
    local Results = table.create(#Tasks)

    for _, Task in Tasks do
        table.insert(Results, Task[1])
    end

    return AwaitFirst(Results)
end

--- Awaits the value from the first completed Task.
--- @see Async.AwaitFirst
function Task.AwaitFirstValue<T>(Tasks: {Task<T>}): T?
    local Results = table.create(#Tasks)

    for _, Task in Tasks do
        table.insert(Results, Task[1])
    end

    local _, Value = AwaitFirst(Results)
    return Value
end

Task.OnFinish = Async.OnFinish
Task.OnSignal = Async.OnSignal

return table.freeze(Task)