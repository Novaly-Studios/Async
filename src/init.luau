--!strict
--!optimize 2
--!native

-- Allows easy command bar paste.
if (not script and Instance) then
    script = game:GetService("ReplicatedFirst").Async
end

local TypeGuard = require(script.Parent:WaitForChild("TypeGuard"))

local DEFAULT_THREAD_TIMEOUT = 240

local METADATA_KEY_FINISH_CALLBACKS = 1
local METADATA_KEY_SIGNAL_CALLBACKS = 2
local METADATA_KEY_CHILDREN = 3
local METADATA_KEY_SUCCESS = 4
local METADATA_KEY_RESULT = 5
local METADATA_KEY_PARENT = 6

local METADATA_SIZE = METADATA_KEY_PARENT

local crrunning = coroutine.running
local crstatus = coroutine.status
local cryield = coroutine.yield

local tbinsert = table.insert
local tbcreate = table.create

local tscancel = task.cancel
local tsspawn = task.spawn
local tsdelay = task.delay
local tsdefer = task.defer
local tswait = task.wait

local mfloor = math.floor
local mhuge = math.huge

local osclock = os.clock

local dbprofilebegin = debug.profilebegin
local dbprofileend = debug.profileend
local dbtraceback = debug.traceback

local strmatch = string.match

--- An extension of the Roblox task library with error handling, tree-based task termination, and await support.
local Async = {}

type ThreadFunction<Return, Args...> = ((Args...) -> (Return)) | ((Args...) -> ())
type FinishCallback = ((Success: boolean, Result: any?) -> ())
type SignalCallback = ((any) -> ())
type ThreadMetadata = {[number]: any}
type AnyFunction = ((...any) -> (...any))
type Thread<Return> = {_ReturnType: Return} & thread

local WEAK_VALUE_RESIZE_MT = {__mode = "vs"}
local WEAK_KEY_RESIZE_MT = {__mode = "ks"}

local _ThreadMetadata: {[thread]: ThreadMetadata} = {}
setmetatable(_ThreadMetadata, WEAK_KEY_RESIZE_MT)
Async._ThreadMetadata = _ThreadMetadata -- External access can be useful for debugging memory leak commonalities via debug.traceback on the thread.

--#region Internal Functions
local function _AssertGetThreadMetadata(Thread: thread?): ThreadMetadata
    local Result = _ThreadMetadata[Thread :: thread]

    if (Result) then
        return Result
    end

    error("Thread metadata not found")
end

local _ErrorReporter = function(Error: string)
    tsspawn(error, Error)
end :: ((string) -> ())?

local function _RegisterOnFinish(Thread: thread, Callback: FinishCallback)
    local Metadata = _ThreadMetadata[Thread]
        local FinishCallbacks = Metadata[METADATA_KEY_FINISH_CALLBACKS]

    if (FinishCallbacks) then
        tbinsert(FinishCallbacks, Callback)
        return
    end

    Metadata[METADATA_KEY_FINISH_CALLBACKS] = {Callback}
end

local function _RegisterOnSignal(Thread: thread, Callback: SignalCallback)
    local Metadata = _ThreadMetadata[Thread]
        local SignalCallbacks = Metadata[METADATA_KEY_SIGNAL_CALLBACKS]

    if (SignalCallbacks) then
        tbinsert(SignalCallbacks, Callback)
        return
    end

    Metadata[METADATA_KEY_SIGNAL_CALLBACKS] = {Callback}
end

local function _IsDescendantOf(Thread1: thread, Thread2: thread): boolean
    local CurrentThread = Thread1

    while (CurrentThread) do
        if (CurrentThread == Thread2) then
            return true
        end

        local Metadata = _ThreadMetadata[CurrentThread]

        if (not Metadata) then
            return false
        end

        CurrentThread = Metadata[METADATA_KEY_PARENT]
    end

    return false
end

local function _Finish(Thread: thread, FinishAll: boolean?, Success: boolean, Result: any?)
    local Target = _ThreadMetadata[Thread]

    if (not Target) then
        return
    end

    if (Target[METADATA_KEY_SUCCESS] == nil) then
        Target[METADATA_KEY_SUCCESS] = Success
        Target[METADATA_KEY_RESULT] = Result

        if (crstatus(Thread) == "suspended") then
            tscancel(Thread)
        end

        local FinishCallbacks = Target[METADATA_KEY_FINISH_CALLBACKS]

        if (FinishCallbacks) then
            for _, FinishCallback in FinishCallbacks do
                tsspawn(FinishCallback, Success, Result)
            end
        end
    end

    -- We want this to be separate from the above condition as a thread can succeed but still have running sub-threads.
    if (FinishAll) then
        local Children = Target[METADATA_KEY_CHILDREN]

        if (Children) then
            for _, Child in Children do
                _Finish(Child, true, Success, (Success and "PARENT_RESOLVED" or "PARENT_CANCELLED"))
            end
        end
    end
end

local function _FireSignal(Thread: thread, Data: any, Depth: number, AllowFinishedThreads: boolean?)
    if (Depth == 0) then
        return
    end

    local Metadata = _ThreadMetadata[Thread]
        local SignalCallbacks = Metadata[METADATA_KEY_SIGNAL_CALLBACKS]

    if (SignalCallbacks and (AllowFinishedThreads or (not AllowFinishedThreads and Metadata[METADATA_KEY_SUCCESS] == nil))) then
        for _, SignalCallback in SignalCallbacks do
            tsspawn(SignalCallback, Data)
        end
    end

    local Children = Metadata[METADATA_KEY_CHILDREN]

    if (not Children) then
        return
    end

    for _, Child in Children do
        _FireSignal(Child, Data, Depth - 1, AllowFinishedThreads)
    end
end

local function _AddChildThread(Metadata: ThreadMetadata, Thread: thread)
    local Children = Metadata[METADATA_KEY_CHILDREN]

    if (Children) then
        tbinsert(Children, Thread)
        return
    end

    Metadata[METADATA_KEY_CHILDREN] = setmetatable({Thread}, WEAK_VALUE_RESIZE_MT) :: any
end

local function _CaptureThread(ParentThread: thread, Callback: AnyFunction, ...)
    -- Create metadata for captured / running thread if it doesn't exist already.
    -- Parent will always be referenced as long as this thread is running.
    -- So it can't break the _Finish chain by accident.
    local Running = crrunning()
    local CapturedMetadata = tbcreate(METADATA_SIZE)
    CapturedMetadata[METADATA_KEY_PARENT] = ParentThread
    _ThreadMetadata[Running] = (CapturedMetadata :: any)

    -- Multiple threads can have the same parent, so we need to check if parent metadata is already initialized.
    local ParentMetadata = _ThreadMetadata[ParentThread]

    if (not ParentMetadata) then
        ParentMetadata = tbcreate(METADATA_SIZE)
        _ThreadMetadata[ParentThread] = ParentMetadata
    end

    _AddChildThread(ParentMetadata, Running)

    -- Catch any errors (this is still a bit weird).
    local GotError
    local ReportError
    local CallSuccess, ReportedResult = xpcall(Callback, function(Error)
        local Tag = strmatch(Error, "<<([%w_]+)>>")
        local Trace = "\n" .. dbtraceback(nil, 2)

        if (Tag) then
            GotError = Tag
            ReportError = Tag .. Trace
        else
            GotError = Error .. Trace
            ReportError = GotError
        end
    end, ...)

    -- Threw an error -> terminate all sub-threads.
    if (CallSuccess == false) then
        _Finish(Running, true, false, GotError)

        if (_ErrorReporter) then
            _ErrorReporter(ReportError)
        end

        return
    end

    -- Success signal - should not terminate sub-threads.
    _Finish(Running, false, true, ReportedResult)
end

local function _AssertFinalizeRules(Thread: thread)
    local Running = crrunning()

    if (Thread == Running) then
        error("Cannot cancel a thread within itself")
    end

    assert(_ThreadMetadata[Running] == nil or _IsDescendantOf(Thread, Running), "Cannot cancel an ancestor thread from a descendant thread")
end

local function _InternalDelay(Time: number?, Callback: AnyFunction, ...)
    tswait(Time)
    Callback(...)
end

local function _InternalDefer(Callback: AnyFunction, ...)
    tsdefer(tsspawn, crrunning())
    cryield()
    Callback(...)
end

-- One arg specifically to ensure this gets inlined.
local function _Spawn(Callback: ((...any) -> (...any)), Arg): thread
    return tsspawn(_CaptureThread, crrunning(), Callback, Arg)
end

local function _Timer(Interval: number, Call: ((number) -> ()), ProfileTag: string?): (() -> ())
    if (ProfileTag) then
        ProfileTag = ProfileTag .. "(" .. mfloor(Interval * 100) / 100 .. ")"
    end

    local LastTime = osclock()
    local Active = true

    local function StopFunction()
        Active = false
    end

    -- Profile tag sometimes is not applicable because the timer function can yield, which breaks the profiling.
    if (ProfileTag) then
        _Spawn(function()
            while (Active) do
                dbprofilebegin(ProfileTag)
                local CurrentTime = osclock()

                if (Call(CurrentTime - LastTime)) then
                    dbprofileend()
                    return
                end

                dbprofileend()
                tswait(Interval)
                LastTime = CurrentTime
            end
        end)
    else
        _Spawn(function()
            while (Active) do
                local CurrentTime = osclock()
    
                if (Call(CurrentTime - LastTime)) then
                    return
                end
            
                tswait(Interval)
                LastTime = CurrentTime
            end
        end)
    end

    return StopFunction
end

local function _Await(Thread: thread, Timeout: number?): (boolean, any?)
    Timeout = Timeout or DEFAULT_THREAD_TIMEOUT

    -- It might have finished before we even got here.
    local Target = _AssertGetThreadMetadata(Thread)
    local InitialSuccess = Target[METADATA_KEY_SUCCESS]

    if (InitialSuccess ~= nil) then
        return InitialSuccess, Target[METADATA_KEY_RESULT]
    end

    -- Didn't finish, so we need to wait for it.
    -- TODO: do we really need all the boolean checks?
    local Current = crrunning()

    local Result = nil
    local Success = nil

    local DidYield = false
    local DidResume = false
    local DidTimeout = false

    _RegisterOnFinish(Thread, function(PassedSuccess, PassedResult)
        Success = PassedSuccess
        Result = PassedResult

        if (not DidYield or DidTimeout) then
            return
        end

        tsspawn(Current)
    end)

    if (Success ~= nil) then
        return Success, Result
    end

    if (Timeout ~= mhuge) then
        tsdelay(Timeout, function()
            -- Could time out at a later point, so once we resume we know it is only yielding for this & can cancel in future.
            if (DidResume) then
                return
            end

            DidTimeout = true
            Success = false
            Result = "TIMEOUT"
            tsspawn(Current)
        end)
    end

    DidYield = true
    cryield()
    DidResume = true

    return Success, Result
end

local function _GetDescendants(Root: thread, Results: {thread}): {thread}
    tbinsert(Results, Root)

    local Metadata = _ThreadMetadata[Root]

    if (Metadata) then
        local Children = Metadata[METADATA_KEY_CHILDREN]

        if (Children) then
            for _, ChildThread in Children do
                _GetDescendants(ChildThread, Results)
            end
        end
    end

    return Results
end

local function _DoRetries(Callback: AnyFunction, Retries: number, Delay: number?)
    for _ = 1, Retries do
        local Success, Result = _Await(_Spawn(Callback))

        if (Success) then
            return Result
        end

        if (Delay) then
            tswait(Delay)
        end
    end

    error("<<RETRIES_EXHAUSTED>>")
end
--#endregion

--#region User Functions
local _SpawnTimedParams = TypeGuard.Params(
    TypeGuard.Function(),
    TypeGuard.Number()
)
--- Spawns a new thread, with a timeout, and returns it. Will terminate all sub-threads on timeout.
local function SpawnTimed<Return, Args...>(Callback: ThreadFunction<Return, Args...>, Timeout: number?, ...): Thread<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT">
    Timeout = Timeout or DEFAULT_THREAD_TIMEOUT
    _SpawnTimedParams(Callback, Timeout)

    local Thread = tsspawn(_CaptureThread, crrunning(), Callback :: any, ...)

    if (Timeout ~= mhuge) then
        tsdelay(Timeout, _Finish, Thread, true, false, "TIMEOUT") -- TODO: insert this into thread's children?
    end

    return Thread :: any
end
Async.SpawnTimed = SpawnTimed

local _SpawnParams = TypeGuard.Params(
    TypeGuard.Function()
)
--- Spawns a new thread and returns it.
local function Spawn<Return, Args...>(Callback: ThreadFunction<Return, Args...>, ...): Thread<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT">
    _SpawnParams(Callback)
    return tsspawn(_CaptureThread, crrunning(), Callback :: any, ...) :: any
end
Async.Spawn = Spawn


local _DelayParams = TypeGuard.Params(
    TypeGuard.Optional(TypeGuard.Number()),
    TypeGuard.Function()
)
--- Extension of task.delay.
function Async.Delay<Return, Args...>(Time: number?, Callback: ThreadFunction<Return, Args...>, ...: Args...): Thread<Return>
    _DelayParams(Time, Callback)
    return tsspawn(_CaptureThread, crrunning(), _InternalDelay :: any, Time, Callback, ...) :: any
end


local _DeferParams = TypeGuard.Params(
    TypeGuard.Function()
)
--- Extension of task.defer.
function Async.Defer<Return, Args...>(Callback: ThreadFunction<Return, Args...>, ...: Args...): Thread<Return>
    _DeferParams(Callback)
    return tsspawn(_CaptureThread, crrunning(), _InternalDefer :: any, Callback, ...) :: any
end


local _RetriesParams = TypeGuard.Params(
    TypeGuard.Function(),
    TypeGuard.Number():Integer(),
    TypeGuard.Optional(TypeGuard.Number()),
    TypeGuard.Optional(TypeGuard.Number())
)
--- Retries a thread a given number of times if it fails, with an optional delay.
function Async.Retries<Return, Args...>(Callback: ThreadFunction<Return, Args...>, Retries: number, Delay: number?, Timeout: number?, ...: Args...): Thread<Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT" | "RETRIES_EXHAUSTED">
    _RetriesParams(Callback, Retries, Delay, Timeout)
    return SpawnTimed(_DoRetries, Timeout, Callback, Retries, Delay, ...)
end


local _AsyncCancelParams = TypeGuard.Params(
    TypeGuard.Thread()
)
-- Halts a task with a fail status (false, Result) and all descendant threads.
function Async.Cancel<Return>(Thread: Thread<Return>, Result: Return?)
    _AsyncCancelParams(Thread)
    _AssertFinalizeRules(Thread)
    _AssertGetThreadMetadata(Thread)
    _Finish(Thread, true, false, Result)
end


-- Halts a task with a fail status (false, Result).
function Async.CancelRoot<Return>(Thread: Thread<Return>, Result: Return?)
    _AsyncCancelParams(Thread)
    _AssertFinalizeRules(Thread)
    _AssertGetThreadMetadata(Thread)
    _Finish(Thread, false, false, Result)
end


local _AsyncResolveParams = TypeGuard.Params(
    TypeGuard.Thread()
)
-- Halts a task with a success status (true, Result) and all descendant threads.
function Async.Resolve<Return>(Thread: Thread<Return>, Result: Return?)
    _AsyncResolveParams(Thread)
    _AssertFinalizeRules(Thread)
    _AssertGetThreadMetadata(Thread)
    _Finish(Thread, true, true, Result)
end


-- Halts a task with a success status (true, Result).
function Async.ResolveRoot<Return>(Thread: Thread<Return>, Result: Return?)
    _AsyncResolveParams(Thread)
    _AssertFinalizeRules(Thread)
    _AssertGetThreadMetadata(Thread)
    _Finish(Thread, false, true, Result)
end


local _OnFinishParams = TypeGuard.Params(
    TypeGuard.Function()
)
--- Registers a callback to be called when a thread finishes.
function Async.OnFinish(Callback: FinishCallback)
    _OnFinishParams(Callback)

    local Running = crrunning()
    _AssertGetThreadMetadata(Running)
    _RegisterOnFinish(Running, Callback)
end


local _ResultsParams = TypeGuard.Params(
    TypeGuard.Thread()
)
--- Returns the results of a thread, if it has finished.
function Async.Results<Return>(Thread: Thread<Return>): (boolean?, Return?)
    _ResultsParams(Thread)

    local Target = _ThreadMetadata[Thread]

    if (Target) then
        return Target[METADATA_KEY_SUCCESS], Target[METADATA_KEY_RESULT]
    end

    return nil, nil
end


local _AwaitParams = TypeGuard.Params(
    TypeGuard.Thread(),
    TypeGuard.Optional(TypeGuard.Number())
)
--- Waits for a thread to finish, with an optional timeout or default resorted timeout, and returns the result.
function Async.Await<Return>(Thread: Thread<Return>, Timeout: number?): (boolean, Return--[[  | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT" ]])
    _AwaitParams(Thread, Timeout)

    local Success, Result = _Await(Thread, Timeout)
    return Success, Result :: any
end


local _AwaitAllParams = TypeGuard.Params(
    TypeGuard.Array(TypeGuard.Thread()):MinLength(1),
    TypeGuard.Optional(TypeGuard.Number())
)
--- Waits for all threads to finish, with an optional timeout or default resorted timeout, and returns the results.
function Async.AwaitAll<Return>(Threads: {Thread<Return>}, Timeout: number?): {{Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT"}}
    _AwaitAllParams(Threads, Timeout)

    local Length = #Threads
    local Running = crrunning()
    local Results = tbcreate(Length)
    local Count = 0

    local DidYield = false

    for Index, Value in Threads do
        _AssertGetThreadMetadata(Value)
        _Spawn(function()
            local Success, Result = _Await(Value, Timeout)
            Results[Index] = {Success :: any, Result}
            Count += 1

            if (Count == Length and DidYield) then
                tsspawn(Running)
            end
        end)
    end

    if (Count < Length) then
        DidYield = true
        cryield()
    end

    return Results
end


local _AwaitFirstParams = TypeGuard.Params(
    TypeGuard.Array(TypeGuard.Thread()):MinLength(1),
    TypeGuard.Optional(TypeGuard.Number())
)
--- Waits for the first thread in a list of threads to finish and returns its finishing result.
function Async.AwaitFirst<Return>(Threads: {Thread<Return>}, Timeout: number?): (boolean, (Return | "PARENT_RESOLVED" | "PARENT_CANCELLED" | "TIMEOUT")?)
    _AwaitFirstParams(Threads, Timeout)

    local DidYield = false
    local Running = crrunning()

    local Success
    local Result

    for Index, Value in Threads do
        _AssertGetThreadMetadata(Value)
        _Spawn(function()
            if (Success == nil) then
                local TempSuccess, TempResult = _Await(Value, Timeout)

                if (Success ~= nil) then
                    return
                end

                Success = TempSuccess
                Result = TempResult

                if (DidYield) then
                    tsspawn(Running)
                end
            end
        end)
    end

    if (Success == nil) then
        DidYield = true
        cryield()
    end

    return Success, Result
end


local _TimerParams = TypeGuard.Params(
    TypeGuard.Number(),
    TypeGuard.Function(),
    TypeGuard.Optional(TypeGuard.String())
)
--- Creates a synchronized, blockable timer loop.
function Async.Timer(Interval: number, Call: ((number) -> ()), ProfileTag: string?): (() -> ())
    _TimerParams(Interval, Call, ProfileTag)
    return _Timer(Interval, Call, ProfileTag)
end


local _TimerAsyncParams = TypeGuard.Params(
    TypeGuard.Number(),
    TypeGuard.Function(),
    TypeGuard.Optional(TypeGuard.String()),
    TypeGuard.Optional(TypeGuard.Boolean())
)
--- Creates a timer which spawns a new thread each call, preventing operations from blocking the timer thread.
--- Optional UseAsyncSpawn parameter will use Async.Spawn instead of task.spawn - this can (currently) be costly on the garbage collector at high frequencies due to weak tables, so task.spawn is assumed by default.
function Async.TimerAsync(Interval: number, Call: ((number) -> ()), Name: string?, UseAsyncSpawn: boolean?): (() -> ())
    _TimerAsyncParams(Interval, Call, Name, UseAsyncSpawn)

    local SpawnFunction = (UseAsyncSpawn and _Spawn or tsspawn)
    local Stop = false

    _Timer(Interval, function(DeltaTime)
        if (Stop) then
            return true
        end

        local Temp = SpawnFunction :: any
        Temp(Call, DeltaTime)
        return
    end, Name)

    return function()
        Stop = true
    end
end


local _ParentParams = TypeGuard.Params(
    TypeGuard.Optional(TypeGuard.Thread())
)
--- Gets the parent of a given thread, or the parent of the current thread if no thread is passed.
function Async.Parent(Thread: Thread<any>?): Thread<any>?
    _ParentParams(Thread)
    return _AssertGetThreadMetadata(Thread or crrunning())[METADATA_KEY_PARENT]
end


--- Uses task.defer to initiate a yield.
function Async.DeferWait()
    tsdefer(tsspawn, crrunning())
    cryield()
end


--- Gets the number of threads currently allocated. Helps debugging.
function Async.Count()
    local Result = 0

    for _ in (_ThreadMetadata :: any) do
        Result += 1
    end

    return Result
end


local _SetErrorReporterParams = TypeGuard.Params(
    TypeGuard.Optional(TypeGuard.Function())
)
--- Sets the function which handles error reporting for all threads.
--- By default, errors are reported to the console.
--- This can be set to a blank callback to speed up performance if necessary.
local function SetErrorReporter(Handler: ((string) -> ())?)
    _SetErrorReporterParams(Handler)
    _ErrorReporter = Handler
end
Async.SetErrorReporter = SetErrorReporter


local _AwaitDescendantParams = TypeGuard.Params(
    TypeGuard.Thread(),
    TypeGuard.Optional(TypeGuard.Number())
)
local AwaitAll = Async.AwaitAll
--- Waits for all threads in the tree to finish.
function Async.AwaitDescendants<Return>(Thread: Thread<Return>, Timeout: number?)
    _AwaitDescendantParams(Thread, Timeout)
    _AssertGetThreadMetadata(Thread)
    return AwaitAll(_GetDescendants(Thread, {}) :: {Thread<Return>}, Timeout)
end


local _OnSignalParams = TypeGuard.Params(
    TypeGuard.Function()
)
--- Registers a callback which fires when the thread receives a signal.
function Async.OnSignal(Callback: SignalCallback)
    _OnSignalParams(Callback)

    local Running = crrunning()
    _AssertGetThreadMetadata(Running)
    _RegisterOnSignal(Running, Callback)
end


local _FireSignalParams = TypeGuard.Params(
    TypeGuard.Thread(),
    TypeGuard.Any,
    TypeGuard.Optional(TypeGuard.Number()),
    TypeGuard.Optional(TypeGuard.Boolean())
)
--- Fires a signal with arbitrary data to a thread and all its descendants.
--- Depth is optional and defaults to infinite.
function Async.FireSignal(Thread: thread, Data: any, Depth: number?, AllowFinishedThreads: boolean?)
    _FireSignalParams(Thread, Data, Depth, AllowFinishedThreads)
    _AssertGetThreadMetadata(Thread)
    _FireSignal(Thread, Data, Depth or mhuge, AllowFinishedThreads)
end
--#endregion

return table.freeze(Async)