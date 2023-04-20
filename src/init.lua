--!nonstrict
-- Allows easy command bar paste
if (not script) then
    script = game:GetService("ReplicatedFirst").Async
end

local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))

local DEFAULT_THREAD_TIMEOUT = 30

--- An extension of the Roblox task library with error handling, tree-based task termination, and await support.
local Async = {}

type FinishCallback = ((Success: boolean, Result: any?) -> ())
type ThreadMetadata = {
    FinishCallbacks: {FinishCallback}?;
    Children: {[thread]: true};

    Success: boolean?;
    Result: any?;
    Parent: {Value: thread};
    IsRoot: boolean?;
}
type ThreadFunction = ((FinishCallback?, ...any) -> (boolean, any?))

local WEAK_KEY_RESIZE_MT = {__mode = "ks"}
local WEAK_VALUE_MT = {__mode = "v"}

local ThreadMetadata: {[thread]: ThreadMetadata} = {}
setmetatable(ThreadMetadata, WEAK_KEY_RESIZE_MT)

local function CreateThreadMetadata(Thread): ThreadMetadata
    local ParentRef = {Value = nil}

    local Metadata = {
        Children = {};
        Parent = ParentRef;
    }

    setmetatable(ParentRef, WEAK_VALUE_MT)
    ThreadMetadata[Thread] = Metadata
    return Metadata
end

local function AssertGetThreadMetadata(Thread: thread?)
    local Result = ThreadMetadata[Thread :: thread]

    if (Result) then
        return Result
    end

    error("Thread is nil")
end

local function RegisterOnFinish(Thread: thread, Callback: FinishCallback)
    local Metadata = ThreadMetadata[Thread]
    local FinishCallbacks = Metadata.FinishCallbacks

    if (FinishCallbacks) then
        table.insert(FinishCallbacks, Callback)
        return
    end

    Metadata.FinishCallbacks = {Callback}
end

local function IsDescendantOf(Thread1: thread, Thread2: thread): boolean
    local CurrentThread = Thread1

    while (CurrentThread) do
        if (CurrentThread == Thread2) then
            return true
        end

        local Metadata = ThreadMetadata[CurrentThread]

        if (not Metadata) then
            return false
        end

        CurrentThread = Metadata.Parent.Value
    end

    return false
end

local function Finish(Thread: thread, FinishAll: boolean?, Success: boolean, Result: any?)
    local Target = ThreadMetadata[Thread]

    if (not Target) then
        return
    end

    if (Target.Success == nil) then
        Target.Success = Success
        Target.Result = Result

        if (coroutine.status(Thread) == "suspended") then
            task.cancel(Thread)
        end

        local FinishCallbacks = Target.FinishCallbacks

        if (FinishCallbacks) then
            for Index, FinishCallback in FinishCallbacks do
                FinishCallback(Success, Result)
            end
        end
    end

    if (Success) then
        return
    end

    if (FinishAll) then
        local Children = Target.Children

        if (Children) then
            for Child in Children do
                Finish(Child, true, Success, Result)
            end
        end
    end
end

local function Resolve(Thread: thread, Result: any?)
    Finish(Thread, true, true, Result)
end

local function ResolveRoot(Thread: thread, Result: any?)
    Finish(Thread, false, true, Result)
end

local function Cancel(Thread: thread, Result: any?)
    Finish(Thread, true, false, Result)
end

local function CancelRoot(Thread: thread, Result: any?)
    Finish(Thread, false, false, Result)
end

local function CaptureThread(ParentThread: thread, Callback: ThreadFunction, ...)
    local Running = coroutine.running()
    CreateThreadMetadata(Running).Parent.Value = ParentThread

    -- Multiple threads can have the same parent, so we need to check if parent metadata is already initialized.
    local ParentMetadata = ThreadMetadata[ParentThread]

    if (not ParentMetadata) then
        ParentMetadata = CreateThreadMetadata(ParentThread)

        -- Establish root threads (which have no parents).
        if (not ParentMetadata.Parent.Value) then
            ParentMetadata.IsRoot = true
        end
    end

    local Children = ParentMetadata.Children

    if (getmetatable(Children) == nil) then
        setmetatable(Children, WEAK_KEY_RESIZE_MT)
    end

    Children[Running] = true

    -- Catch any errors (this is still a bit weird).
    local GotError
    local CallSuccess, ReportedSuccess, ReportedResult = xpcall(Callback, function(Error)
        GotError = Error .. "\n" .. debug.traceback(nil, 2)
    end, ...)

    -- Fail signal -> terminate all sub-threads.
    if (CallSuccess == false) then
        Cancel(Running, GotError)
        task.spawn(error, GotError)
        return
    end

    local ReportedSuccessType = type(ReportedSuccess)

    -- Fail signal -> terminate all sub-threads.
    -- Success signal -> only terminate top level thread.
    if (ReportedSuccessType == "boolean") then
        if (ReportedSuccess) then
            ResolveRoot(Running, ReportedResult)
        else
            Cancel(Running, ReportedResult)
        end

        return
    end

    -- No return (nil) is implicitly a success signal, success signals should not terminate sub-threads by default.
    if (ReportedSuccessType == "nil") then
        ResolveRoot(Running, ReportedResult)
        return
    end

    task.spawn(error, "Thread did not return a success signifier - must return: (Success: boolean, Result: any?)")
    Cancel(Running, "INVALID_RETURN")
end

-- User Functions
local SpawnParams = TypeGuard.Params(TypeGuard.Function())
--- Spawns a new thread and returns it.
function Async.Spawn(Callback: ThreadFunction, ...): thread
    SpawnParams(Callback)
    return task.spawn(CaptureThread, coroutine.running(), Callback, ...)
end

local SpawnTimedCancelParams = TypeGuard.Params(TypeGuard.Number(), TypeGuard.Function())
--- Spawns a new thread, with a timeout, and returns it. Descendant threads and the root thread are
--- all cancelled on timeout regardless of whether the root thread has completed.
function Async.SpawnTimedCancel(Time: number, Callback: ThreadFunction, ...): thread
    SpawnTimedCancelParams(Time, Callback)

    local Thread = task.spawn(CaptureThread, coroutine.running(), Callback, ...)
    task.delay(Time, Cancel, Thread, "TIMEOUT")
    return Thread
end

local SpawnTimeLimitParams = TypeGuard.Params(TypeGuard.Number(), TypeGuard.Function())
--- Spawns a new thread, with a timeout, and returns it. If the thread completes before
--- the timeout, the timeout is cancelled, preserving all descendant threads.
function Async.SpawnTimeLimit(Time: number, Callback: ThreadFunction, ...): thread
    SpawnTimeLimitParams(Time, Callback)

    local Thread = task.spawn(CaptureThread, coroutine.running(), Callback, ...)
    local Metadata = ThreadMetadata[Thread]

    task.delay(Time, function()
        if (Metadata.Success == nil) then
            Cancel(Thread, "TIMEOUT")
        end
    end)

    return Thread
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

local function AssertFinalizeRules(Thread: thread)
    local Running = coroutine.running()
    assert(Thread ~= Running, "Cannot cancel a thread within itself")
    assert(ThreadMetadata[Running] == nil or IsDescendantOf(Thread, Running), "Cannot cancel an ancestor thread from a descendant thread")
end

local function AssertNotRoot(Thread: thread)
    assert(not ThreadMetadata[Thread].IsRoot, "Operations on root threads are not permitted")
end

local CancelParams = TypeGuard.Params(TypeGuard.Thread())
-- Halts a task with a fail status (false, Result) and all descendant threads.
function Async.Cancel(Thread: thread, Result: any?)
    CancelParams(Thread)
    AssertFinalizeRules(Thread)
    AssertGetThreadMetadata(Thread)
    Cancel(Thread, Result)
end

-- Halts a task with a fail status (false, Result).
function Async.CancelRoot(Thread: thread, Result: any?)
    CancelParams(Thread)
    AssertNotRoot(Thread) -- Meaningless to cancel a root thread.
    AssertFinalizeRules(Thread)
    AssertGetThreadMetadata(Thread)
    CancelRoot(Thread, Result)
end

local ResolveParams = TypeGuard.Params(TypeGuard.Thread())
-- Halts a task with a success status (true, Result) and all descendant threads.
function Async.Resolve(Thread: thread, Result: any?)
    ResolveParams(Thread)
    AssertFinalizeRules(Thread)
    AssertGetThreadMetadata(Thread)
    Resolve(Thread, Result)
end

-- Halts a task with a success status (true, Result).
function Async.ResolveRoot(Thread: thread, Result: any?)
    ResolveParams(Thread)
    AssertNotRoot(Thread)
    AssertFinalizeRules(Thread)
    AssertGetThreadMetadata(Thread)
    ResolveRoot(Thread, Result)
end

local OnFinishParams = TypeGuard.Params(TypeGuard.Function())
--- Registers a callback to be called when a thread finishes.
function Async.OnFinish(Callback: FinishCallback)
    OnFinishParams(Callback)

    local Running = coroutine.running()
    AssertGetThreadMetadata(Running)
    AssertNotRoot(Running)
    RegisterOnFinish(Running, Callback)
end

local AwaitParams = TypeGuard.Params(TypeGuard.Thread(), TypeGuard.Number():Optional())
--- Waits for a thread to finish, with an optional timeout or default resorted timeout (30s), and returns the result.
function Async.Await(Thread: thread, Timeout: number?): (boolean, any?)
    AwaitParams(Thread, Timeout)
    AssertNotRoot(Thread)
    Timeout = Timeout or DEFAULT_THREAD_TIMEOUT

    -- It might have finished before we even got here.
    local Target = AssertGetThreadMetadata(Thread)
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
            -- Could time out at a later point, so once we resume we know it is only yielding for this & can cancel in future.
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
        AssertGetThreadMetadata(Value)
        AssertNotRoot(Value)

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
        AssertGetThreadMetadata(Value)
        AssertNotRoot(Value)

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
function Async.Timer(Interval: number, Call: ((number) -> ()), ProfileTag: string?): (() -> ())
    TimerParams(Interval, Call, ProfileTag)

    if (ProfileTag) then
        ProfileTag = ProfileTag .. "(" .. math.floor(Interval * 100) / 100 .. ")"
    end

    local LastTime = os.clock()
    local Active = true

    local function StopFunction()
        Active = false
    end

    -- Profile tag sometimes is not applicable because the timer function can yield, which breaks the profiling.
    if (ProfileTag) then
        Async.Spawn(function()
            while (Active) do
                debug.profilebegin(ProfileTag)
                local CurrentTime = os.clock()

                if (Call(CurrentTime - LastTime)) then
                    return
                end

                debug.profileend()
                task.wait(Interval)
                LastTime = CurrentTime
            end
        end)
    else
        Async.Spawn(function()
            while (Active) do
                local CurrentTime = os.clock()
    
                if (Call(CurrentTime - LastTime)) then
                    return
                end
            
                task.wait(Interval)
                LastTime = CurrentTime
            end
        end)
    end

    return StopFunction
end

local TimerAsyncParams = TypeGuard.Params(TypeGuard.Number(), TypeGuard.Function(), TypeGuard.String():Optional(), TypeGuard.Boolean():Optional())
--- Creates a timer which spawns a new thread each call, preventing operations from blocking the timer thread.
--- Optional UseAsyncSpawn parameter will use Async.Spawn instead of task.spawn - this can (currently) be costly on the garbage collector at high frequencies due to weak tables, so task.spawn is assumed by default.
function Async.TimerAsync(Interval: number, Call: ((number) -> ()), Name: string?, UseAsyncSpawn: boolean?): (() -> ())
    TimerAsyncParams(Interval, Call, Name, UseAsyncSpawn)

    local Stop = false

    local function StopFunction()
        Stop = true
    end

    local SpawnFunction = UseAsyncSpawn and Async.Spawn or task.spawn

    Async.Timer(Interval, function(DeltaTime)
        if (Stop) then
            return true
        end

        SpawnFunction(Call, DeltaTime)
    end, Name)

    return StopFunction
end

local ParentParams = TypeGuard.Params(TypeGuard.Thread():Optional())
--- Gets the parent of a given thread, or the parent of the current thread if no thread is passed.
function Async.Parent(Thread: thread?): thread?
    ParentParams(Thread)
    Thread = Thread or coroutine.running()
    return AssertGetThreadMetadata(Thread).Parent.Value
end

local GetMetadataParams = TypeGuard.Params(TypeGuard.Thread():Optional())
--- Gets the metadata of a given thread, or the metadata of the current thread if no thread is passed.
function Async.GetMetadata(Thread: thread?): ThreadMetadata
    GetMetadataParams(Thread)
    Thread = Thread or coroutine.running()
    return AssertGetThreadMetadata(Thread)
end

--- Gets the number of threads currently allocated. Helps debugging.
function Async.Count()
    local Result = 0

    for _ in ThreadMetadata do
        Result += 1
    end

    return Result
end

return Async