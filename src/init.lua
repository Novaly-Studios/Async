--!nonstrict
-- Allows easy command bar paste
if (not script) then
    script = game:GetService("ReplicatedFirst").Async
end

local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))

--- An extension of the Roblox task library with error handling, tree-based task termination, and await support.
local Async = {}

local DEFAULT_THREAD_TIMEOUT = 30

type FinishCallback = ((Success: boolean, Result: any?) -> ())
type ThreadMetadata = {
    TerminatePropagate: (() -> ())?;
    FinishCallbacks: {FinishCallback};
    Children: {thread};

    Success: boolean;
    Result: any?;
}
type ThreadFunction = ((FinishCallback?, ...any) -> (boolean, any?))

local ThreadMetadata: {[thread]: ThreadMetadata} = {}
setmetatable(ThreadMetadata, {__mode = "ks"})

local function GetOrCreateThreadMetadata(Thread: thread): ThreadMetadata
    local Metadata = ThreadMetadata[Thread]

    if (not Metadata) then
        Metadata = {
            FinishCallbacks = {};
            Children = {};

            Success = nil;
            Result = nil;
        }
        ThreadMetadata[Thread] = Metadata
    end

    return Metadata
end

local function RegisterOnFinish(Thread: thread, Callback: FinishCallback)
    table.insert(GetOrCreateThreadMetadata(Thread).FinishCallbacks, Callback)
end

local function Finish(Thread: thread, Success: boolean, Result: any?)
    local Target = ThreadMetadata[Thread]

    if (not Target) then
        return
    end

    Target.Success = Success
    Target.Result = Result

    local Status = coroutine.status(Thread)

    if (Status == "suspended") then
        task.cancel(Thread)
    end

    for Index, FinishCallback in Target.FinishCallbacks do
        FinishCallback(Success, Result)
    end
end

local function Resolve(Thread: thread, Result: any?)
    Finish(Thread, true, Result)
end

local function Cancel(Thread: thread, Result: any?)
    Finish(Thread, false, Result)
end

local function CaptureThread(ParentThread: thread, Callback: ThreadFunction, ...)
    local Running = coroutine.running()

    RegisterOnFinish(Running, function() end)
    RegisterOnFinish(ParentThread, function(Success, Result)
        if (Success) then
            return
        end

        Cancel(Running, Result)
    end)

    local CallSuccess, ReportedSuccess, ReportedResult = pcall(Callback, function(OnFinishCallback)
        RegisterOnFinish(Running, OnFinishCallback)
    end, ...)

    if (CallSuccess == false) then
        task.spawn(error, ReportedSuccess)
        Finish(Running, CallSuccess, ReportedSuccess)
        return
    end

    local ReportedSuccessType = typeof(ReportedSuccess)

    if (ReportedSuccessType == "boolean") then
        Finish(Running, ReportedSuccess, ReportedResult)
        return
    end

    if (ReportedSuccessType == "nil") then
        Finish(Running, true, ReportedResult)
        return
    end

    task.spawn(error, "Thread did not return a success signifier. Must return: (Success: boolean, Result: any?)")
    Finish(Running, false, "INVALID_RETURN")
end

-- User Functions
local SpawnParams = TypeGuard.Params(TypeGuard.Function())
--- Spawns a new thread and returns it.
function Async.Spawn(Callback: ThreadFunction, ...): thread
    SpawnParams(Callback, ...)
    return task.spawn(CaptureThread, coroutine.running(), Callback, ...)
end

local DelayParams = TypeGuard.Params(TypeGuard.Number():Optional(), TypeGuard.Function())
--- Extension of task.delay.
function Async.Delay(Time: number?, Callback: ThreadFunction, ...): thread
    DelayParams(Time, Callback)
    return task.delay(Time, CaptureThread, coroutine.running(), Callback, ...)
end

local DeferParams = TypeGuard.Params(TypeGuard.Function())
--- Extension of task.defer.
function Async.Defer(Callback: ThreadFunction, ...): thread
    DeferParams(Callback)
    return task.defer(CaptureThread, coroutine.running(), Callback, ...)
end

local CancelParams = TypeGuard.Params(TypeGuard.Thread():HasStatus("Running"):Negate():FailMessage("Cannot cancel a thread from within itself - use 'return false, ...' instead"))
-- Halts a task with a fail status (false, Result).
function Async.Cancel(Thread: thread, Result: any?)
    CancelParams(Thread)
    Cancel(Thread, Result)
end

local ResolveParams = TypeGuard.Params(TypeGuard.Thread():HasStatus("Running"):Negate():FailMessage("Cannot resolve a thread from within itself - use 'return true, ...' instead"))
-- Halts a task with a success status (true, Result).
function Async.Resolve(Thread: thread, Result: any?)
    ResolveParams(Thread)
    Resolve(Thread, Result)
end

local AwaitParams = TypeGuard.Params(TypeGuard.Thread(), TypeGuard.Number():Optional())
--- Waits for a thread to finish, with an optional timeout or default resorted timeout (30s), and returns the result.
function Async.Await(Thread: thread, Timeout: number?): (boolean, any?)
    AwaitParams(Thread, Timeout)
    Timeout = Timeout or DEFAULT_THREAD_TIMEOUT

    -- It might have finished before we even got here.
    local Target = GetOrCreateThreadMetadata(Thread)
    local InitialSuccess = Target.Success

    if (InitialSuccess ~= nil) then
        return InitialSuccess, Target.Result
    end

    -- Didn't finish, so we need to wait for it.
    -- TODO: do we really need all the boolean checks?
    local Current = coroutine.running()

    local Result = nil
    local Success = nil

    local DidYield = false
    local DidResume = false
    local DidTimeout = false

    RegisterOnFinish(Thread, function(PassedSuccess, PassedResult)
        Success = PassedSuccess
        Result = PassedResult

        if (not DidYield or DidTimeout) then
            return
        end

        task.spawn(Current)
    end)

    if (Success ~= nil) then
        return Success, Result
    end

    if (Timeout ~= math.huge) then
        task.delay(Timeout, function()
            -- Could time out at a later point, so once we resume we know it is only yielding for this & can cancel in future
            if (DidResume) then
                return
            end

            DidTimeout = true
            Success = false
            Result = "TIMEOUT"
            task.spawn(Current)
        end)
    end

    DidYield = true
    coroutine.yield()
    DidResume = true

    return Success, Result
end

local AwaitAllParams = TypeGuard.Params(TypeGuard.Array(TypeGuard.Thread()):MinLength(1), TypeGuard.Number():Optional())
--- Waits for all threads to finish, with an optional timeout or default resorted timeout (30s), and returns the results.
function Async.AwaitAll(Threads: {thread}, Timeout: number?): {{any}}
    AwaitAllParams(Threads, Timeout)

    local Length = #Threads

    local Running = coroutine.running()
    local Results = table.create(Length)
    local Count = 0

    local DidYield = false

    for Index, Value in Threads do
        Async.Spawn(function()
            Results[Index] = {Async.Await(Value, Timeout)}
            Count += 1

            if (Count == Length and DidYield) then
                task.spawn(Running)
            end
        end)
    end

    if (Count < Length) then
        DidYield = true
        coroutine.yield()
    end

    return Results
end

local AwaitFirstParams = TypeGuard.Params(TypeGuard.Array(TypeGuard.Thread()):MinLength(1), TypeGuard.Number():Optional())
--- Waits for the first thread in a list of threads to finish and returns its finishing result.
function Async.AwaitFirst(Threads: {thread}, Timeout: number?): (boolean, any?)
    AwaitFirstParams(Threads, Timeout)

    local DidYield = false
    local Running = coroutine.running()

    local Success
    local Result

    for Index, Value in Threads do
        Async.Spawn(function()
            if (Success == nil) then
                local TempSuccess, TempResult = Async.Await(Value, Timeout)

                if (Success ~= nil) then
                    return
                end

                Success = TempSuccess
                Result = TempResult

                if (DidYield) then
                    task.spawn(Running)
                end
            end
        end)
    end

    if (Success == nil) then
        DidYield = true
        coroutine.yield()
    end

    return Success, Result
end

local TimerParams = TypeGuard.Params(TypeGuard.Number(), TypeGuard.Function(), TypeGuard.String():Optional())
--- Creates a synchronized, blockable timer loop.
function Async.Timer(Interval: number, Call: ((number) -> ()), Name: string?): thread
    TimerParams(Interval, Call, Name)

    if (Name) then
        Name = Name .. "(" .. math.floor(Interval * 100) / 100 .. ")"
    end

    local LastTime = os.clock()

    if (Name) then
        return Async.Spawn(function()
            while (true) do
                debug.profilebegin(Name)
                local CurrentTime = os.clock()
                Call(CurrentTime - LastTime)
                debug.profileend()
                task.wait(Interval)
                LastTime = CurrentTime
            end
        end)
    end

    return Async.Spawn(function()
        while (true) do
            local CurrentTime = os.clock()
            Call(CurrentTime - LastTime)
            task.wait(Interval)
            LastTime = CurrentTime
        end
    end)
end

return Async