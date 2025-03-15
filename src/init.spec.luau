local function anyfn(...) return ({} :: any) end
it = it or anyfn
expect = expect or anyfn
describe = describe or anyfn

local Async = require(script.Parent)
Async.SetErrorReporter(nil)

return function()
    describe("OnFinish", function()
        it("should reject non-functions as first arg", function()
            expect(function()
                Async.OnFinish(1)
            end).to.throw()

            expect(function()
                Async.OnFinish("test")
            end).to.throw()

            expect(function()
                Async.OnFinish({})
            end).to.throw()
        end)

        it("should accept functions as first arg when called in an Async-created thread", function()
            expect(function()
                Async.Spawn(function()
                    Async.OnFinish(function() end)
                end)
            end).never.to.throw()
        end)
    end)

    describe("Spawn", function()
        it("should reject non-functions as first arg", function()
            expect(function()
                Async.Spawn(1)
            end).to.throw()

            expect(function()
                Async.Spawn("test")
            end).to.throw()

            expect(function()
                Async.Spawn({})
            end).to.throw()
        end)

        it("should accept functions as first arg", function()
            expect(function()
                Async.Spawn(function() end)
            end).never.to.throw()
        end)

        it("should immediately run functions", function()
            local Ran = false

            Async.Spawn(function()
                Ran = true
            end)

            expect(Ran).to.equal(true)
        end)

        it("should return a thread", function()
            expect(Async.Spawn(function() end)).to.be.a("thread")
        end)

        it("should pass all args in order", function()
            local Results

            Async.Spawn(function(...)
                Results = {...}
            end, 1, 2, 3)

            expect(Results[1]).to.equal(1)
            expect(Results[2]).to.equal(2)
            expect(Results[3]).to.equal(3)
        end)

        it("should call OnFinish with whatever returns from a regularly terminating thread", function()
            local Success, Result

            Async.Spawn(function()
                Async.OnFinish(function(GotSuccess, GotResult)
                    Success = GotSuccess
                    Result = GotResult
                end)

                return "Test"
            end)

            expect(Success).to.equal(true)
            expect(Result).to.equal("Test")
        end)

        it("should call OnFinish if the thread yields", function()
            local Success, Result

            Async.Spawn(function()
                Async.OnFinish(function(GotSuccess, GotResult)
                    Success = GotSuccess
                    Result = GotResult
                end)

                task.wait()
                return "Test"
            end)

            expect(Success).to.equal(nil)
            expect(Result).to.equal(nil)
            task.wait()
            expect(Success).to.equal(true)
            expect(Result).to.equal("Test")
        end)

        it("should call OnFinish if the thread errors", function()
            local Success, Result

            Async.Spawn(function()
                Async.OnFinish(function(GotSuccess, GotResult)
                    Success = GotSuccess
                    Result = GotResult
                end)

                error("/Test/")
            end)

            expect(Success).to.equal(false)
            expect(Result:match("/Test/")).to.be.ok()
        end)

        it("should call OnFinish if the thread errors and yields", function()
            local Success, Result

            Async.Spawn(function()
                Async.OnFinish(function(GotSuccess, GotResult)
                    Success = GotSuccess
                    Result = GotResult
                end)

                task.wait()
                error("/Test/")
            end)

            expect(Success).to.equal(nil)
            expect(Result).to.equal(nil)
            task.wait()
            expect(Success).to.equal(false)
            expect(Result:match("/Test/")).to.be.ok()
        end)

        it("should terminate yielded sub-threads and call OnFinish when cancelled externally", function()
            local Call1 = false
            local Call2 = false

            local Finish1 = false
            local Finish2 = false

            local Thread = Async.Spawn(function()
                Async.OnFinish(function()
                    Call1 = true
                end)

                Async.Spawn(function()
                    Async.OnFinish(function()
                        Call2 = true
                    end)

                    task.wait()
                    Finish2 = true
                end)

                Finish1 = true
            end)

            expect(Call1).to.equal(true)
            expect(Finish1).to.equal(true)

            expect(Call2).to.equal(false)
            expect(Finish2).to.equal(false)

            Async.Cancel(Thread)

            expect(Call1).to.equal(true)
            expect(Finish1).to.equal(true)

            expect(Call2).to.equal(true)
            expect(Finish2).to.equal(false)
        end)

        it("should never terminate yielded sub-threads if the parent thread is resolved", function()
            local Call1 = false
            local Call2 = false

            local Finish1 = false
            local Finish2 = false

            local Thread = Async.Spawn(function()
                Async.OnFinish(function()
                    Call1 = true
                end)

                Async.Spawn(function()
                    Async.OnFinish(function()
                        Call2 = true
                    end)

                    task.wait()
                    Finish2 = true
                end)

                Finish1 = true
            end)

            expect(Call1).to.equal(true)
            expect(Finish1).to.equal(true)

            expect(Call2).to.equal(false)
            expect(Finish2).to.equal(false)

            Async.Cancel(Thread)

            expect(Call1).to.equal(true)
            expect(Finish1).to.equal(true)

            expect(Call2).to.equal(true)
            expect(Finish2).to.equal(false)
        end)
    end)

    describe("SpawnTimed", function()
        it("should accept a function as first arg and reject non-functions", function()
            expect(function()
                Async.SpawnTimed(1)
            end).to.throw()

            expect(function()
                Async.SpawnTimed("test")
            end).to.throw()

            expect(function()
                Async.SpawnTimed({})
            end).to.throw()

            expect(function()
                Async.SpawnTimed(function() end)
            end).never.to.throw()
        end)

        it("should accept a timeout number as second arg and reject non-numbers", function()
            expect(function()
                Async.SpawnTimed(function() end, 1)
            end).never.to.throw()

            expect(function()
                Async.SpawnTimed(function() end, "test")
            end).to.throw()

            expect(function()
                Async.SpawnTimed(function() end, {})
            end).to.throw()
        end)

        it("should spawn a new thread", function()
            local Finished = false

            local Thread = Async.SpawnTimed(function()
                task.wait()
                Finished = true
            end)

            expect(Thread).to.be.ok()
            expect(Thread).to.be.a("thread")
            expect(Finished).to.equal(false)
            task.wait()
            expect(Finished).to.equal(true)
        end)

        it("should terminate all sub-threads after the timeout", function()
            local Terminate1 = false
            local Terminate2 = false
            local Terminate3 = false

            Async.SpawnTimed(function()
                Async.OnFinish(function()
                    Terminate1 = true
                end)

                Async.Spawn(function()
                    Async.OnFinish(function()
                        Terminate2 = true
                    end)

                    Async.Spawn(function()
                        Async.OnFinish(function()
                            Terminate3 = true
                        end)

                        task.wait(1)
                    end)

                    task.wait(1)
                end)

                task.wait(1)
            end, 0)

            expect(Terminate1).to.equal(false)
            expect(Terminate2).to.equal(false)
            expect(Terminate3).to.equal(false)
            task.wait()
            expect(Terminate1).to.equal(true)
            expect(Terminate2).to.equal(true)
            expect(Terminate3).to.equal(true)
        end)
    end)

    describe("Delay", function()
        it("should reject non-numbers as first arg", function()
            expect(function()
                Async.Delay("test")
            end).to.throw()

            expect(function()
                Async.Delay({})
            end).to.throw()

            expect(function()
                Async.Delay(function() end)
            end).to.throw()
        end)

        it("should reject non-functions as second arg", function()
            expect(function()
                Async.Delay(1, 1)
            end).to.throw()

            expect(function()
                Async.Delay(1, "test")
            end).to.throw()

            expect(function()
                Async.Delay(1, {})
            end).to.throw()
        end)

        it("should accept a number as first arg & a function as second arg", function()
            expect(function()
                Async.Delay(1, function() end)
            end).never.to.throw()
        end)

        it("should return a thread", function()
            expect(Async.Delay(1, function() end)).to.be.a("thread")
        end)

        it("should delay for the specified amount of time", function()
            local Ran = false

            Async.Delay(1, function()
                Ran = true
            end)

            expect(Ran).to.equal(false)
            task.wait(1)
            expect(Ran).to.equal(true)
        end)
    end)

    describe("Defer", function()
        it("should reject non-functions as first arg", function()
            expect(function()
                Async.Defer(1)
            end).to.throw()

            expect(function()
                Async.Defer("test")
            end).to.throw()

            expect(function()
                Async.Defer({})
            end).to.throw()
        end)

        it("should accept functions as first arg", function()
            expect(function()
                Async.Defer(function() end)
            end).never.to.throw()
        end)

        it("should return a thread", function()
            expect(Async.Defer(function() end)).to.be.a("thread")
        end)

        it("should defer the function", function()
            local Ran = false

            Async.Defer(function()
                Ran = true
            end)

            expect(Ran).to.equal(false)
            task.wait()
            expect(Ran).to.equal(true)
        end)
    end)

    describe("Finish Rules", function()
        it("should disallow cancellation & resolution from the same thread", function()
            local CancelCompleted = false

            Async.Spawn(function()
                Async.Cancel(coroutine.running())
                CancelCompleted = true
            end)

            expect(CancelCompleted).to.equal(false)

            local ResolveCompleted = false

            Async.Spawn(function()
                Async.Resolve(coroutine.running())
                ResolveCompleted = true
            end)

            expect(ResolveCompleted).to.equal(false)
        end)

        it("should disallow cancellation & resolution from a sub-thread", function()
            local CancelCompleted = false

            Async.Spawn(function()
                local Ref = coroutine.running()

                Async.Spawn(function()
                    Async.Cancel(Ref)
                    CancelCompleted = true
                end)
            end)

            expect(CancelCompleted).to.equal(false)

            local ResolveCompleted = false

            Async.Spawn(function()
                local Ref = coroutine.running()

                Async.Spawn(function()
                    Async.Resolve(Ref)
                    ResolveCompleted = true
                end)
            end)

            expect(ResolveCompleted).to.equal(false)
        end)
    end)

    describe("Cancel", function()
        it("should reject non-threads as first arg", function()
            expect(function()
                Async.Cancel(1)
            end).to.throw()

            expect(function()
                Async.Cancel("test")
            end).to.throw()

            expect(function()
                Async.Cancel({})
            end).to.throw()

            expect(function()
                Async.Cancel(function() end)
            end).to.throw()
        end)

        it("should accept threads as first arg", function()
            expect(function()
                Async.Cancel(Async.Spawn(function() end))
            end).never.to.throw()
        end)

        it("should cancel a yielding thread", function()
            local Ran = false

            local Thread = Async.Spawn(function()
                task.wait()
                Ran = true
            end)

            Async.Cancel(Thread)

            expect(Ran).to.equal(false)
            task.wait()
            task.wait()
            expect(Ran).to.equal(false)
        end)

        it("should cancel the thread with OnFinish, passing false & extra args", function()
            Async.Spawn(function()
                local Success, Result

                local Thread = Async.Spawn(function()
                    Async.OnFinish(function(GotSuccess, GotResult)
                        Success = GotSuccess
                        Result = GotResult
                    end)

                    task.wait()
                    return "Success"
                end)

                expect(Success).to.equal(nil)
                expect(Result).to.equal(nil)
                Async.Cancel(Thread, "CustomFail")
                expect(Success).to.equal(false)
                expect(Result).to.equal("CustomFail")
                task.wait()
                expect(Success).to.equal(false)
                expect(Result).to.equal("CustomFail")
            end)
        end)

        it("should cancel all sub-threads", function()
            local FirstSuccess, SecondSuccess

            local Main = Async.Spawn(function()
                Async.OnFinish(function(Success)
                    FirstSuccess = Success
                end)

                Async.Spawn(function()
                    Async.OnFinish(function(Success)
                        SecondSuccess = Success
                    end)

                    task.wait(0.1)
                end)
            end)

            expect(FirstSuccess).to.equal(true)
            expect(SecondSuccess).to.equal(nil)

            Async.Cancel(Main)

            expect(FirstSuccess).to.equal(true)
            expect(SecondSuccess).to.equal(false)

            task.wait(0.1)

            expect(FirstSuccess).to.equal(true)
            expect(SecondSuccess).to.equal(false)
        end)

        it("should only cancel or resolve a thread and sub-threads once", function()
            local FirstSuccess, SecondSuccess

            local Main = Async.Spawn(function()
                Async.OnFinish(function(Success)
                    FirstSuccess = Success
                end)

                Async.Spawn(function()
                    Async.OnFinish(function(Success)
                        SecondSuccess = Success
                    end)

                    task.wait(0.1)
                end)

                task.wait(0.1)
            end)

            expect(FirstSuccess).to.equal(nil)
            expect(SecondSuccess).to.equal(nil)

            Async.Cancel(Main)

            expect(FirstSuccess).to.equal(false)
            expect(SecondSuccess).to.equal(false)

            Async.Resolve(Main)

            expect(FirstSuccess).to.equal(false)
            expect(SecondSuccess).to.equal(false)
        end)
    end)

    describe("CancelRoot", function()
        it("should only cancel the top-level thread and not its descendants", function()
            local SubThread
            local MainThread = Async.Spawn(function()
                SubThread = Async.Spawn(function()
                    task.wait(0.1)
                end)
            end)

            Async.CancelRoot(MainThread)

            expect(SubThread).to.be.ok()
            expect(coroutine.status(SubThread)).to.equal("suspended")
        end)
    end)

    describe("Resolve", function()
        it("should reject non-threads as first arg", function()
            expect(function()
                Async.Resolve(1)
            end).to.throw()

            expect(function()
                Async.Resolve("test")
            end).to.throw()

            expect(function()
                Async.Resolve({})
            end).to.throw()

            expect(function()
                Async.Resolve(function() end)
            end).to.throw()
        end)

        it("should accept threads as first arg", function()
            expect(function()
                Async.Resolve(Async.Spawn(function() end))
            end).never.to.throw()
        end)

        it("should finish a yielding thread", function()
            local Ran = false

            local Thread = Async.Spawn(function()
                task.wait()
                Ran = true
            end)

            Async.Resolve(Thread)

            expect(Ran).to.equal(false)
            task.wait()
            task.wait()
            expect(Ran).to.equal(false)
        end)

        it("should finish the thread with OnFinish, passing true & extra args", function()
            Async.Spawn(function()
                local Success, Result

                local Thread = Async.Spawn(function()
                    Async.OnFinish(function(GotSuccess, GotResult)
                        Success = GotSuccess
                        Result = GotResult
                    end)

                    task.wait()
                    return "Success"
                end)

                expect(Success).to.equal(nil)
                expect(Result).to.equal(nil)
                Async.Resolve(Thread, "CustomSuccess")
                expect(Success).to.equal(true)
                expect(Result).to.equal("CustomSuccess")
                task.wait()
                expect(Success).to.equal(true)
                expect(Result).to.equal("CustomSuccess")
            end)
        end)

        it("should recursively terminate threads", function()
            local Results = table.create(2)

            Async.Defer(function()
                Async.OnFinish(function(Success, Result)
                    Results[1] = {Success, Result}
                end)

                Async.Spawn(function()
                    task.wait()

                    Async.OnFinish(function(Success, Result)
                        Results[2] = {Success, Result}
                    end)
                end)
            end)

            expect(Results[1]).to.equal(nil)
            expect(Results[2]).to.equal(nil)
        end)
    end)

    describe("ResolveRoot", function()
        it("should only resolve the top-level thread and not its descendants", function()
            local SubThread
            local MainThread = Async.Spawn(function()
                SubThread = Async.Spawn(function()
                    task.wait(0.1)
                end)
            end)

            Async.ResolveRoot(MainThread)

            expect(SubThread).to.be.ok()
            expect(coroutine.status(SubThread)).to.equal("suspended")
        end)
    end)

    describe("Await", function()
        it("should reject non-threads as first arg", function()
            expect(function()
                Async.Await(1)
            end).to.throw()

            expect(function()
                Async.Await("test")
            end).to.throw()

            expect(function()
                Async.Await({})
            end).to.throw()

            expect(function()
                Async.Await(function() end)
            end).to.throw()
        end)

        it("should accept threads as first arg", function()
            expect(function()
                Async.Await(Async.Spawn(function() end))
            end).never.to.throw()
        end)

        it("should return for immediate execution threads", function()
            local Success, Result = Async.Await(Async.Spawn(function()
                return "Success"
            end))

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return for yielding threads", function()
            local Success, Result = Async.Await(Async.Spawn(function()
                task.wait()
                return "Success"
            end))

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return nil for timeout and not cancel the thread", function()
            local Finished = false

            local Success, Result = Async.Await(Async.Spawn(function()
                task.wait(0.2)
                Finished = true
            end), 0.1)

            expect(Success).to.equal(false)
            expect(Result).to.equal("TIMEOUT")

            task.wait(0.1)

            expect(Finished).to.equal(true)
        end)
    end)

    describe("AwaitAll", function()
        it("should reject non-tables as first arg", function()
            expect(function()
                Async.AwaitAll(1)
            end).to.throw()

            expect(function()
                Async.AwaitAll("test")
            end).to.throw()

            expect(function()
                Async.AwaitAll(Async.Spawn(function() end))
            end).to.throw()

            expect(function()
                Async.AwaitAll(function() end)
            end).to.throw()
        end)
        
        it("should accept non-empty tables as first arg", function()
            expect(function()
                Async.AwaitAll({})
            end).to.throw()

            expect(function()
                Async.AwaitAll({Async.Spawn(function() end)})
            end).never.to.throw()
        end)

        it("should return a table of results given one thread", function()
            local Results = Async.AwaitAll({
                Async.Spawn(function()
                    return "Success"
                end)
            })

            expect(Results).to.be.ok()
            expect(Results).to.be.a("table")
            expect(Results[1]).to.be.ok()
            expect(Results[1]).to.be.a("table")
            expect(Results[1][1]).to.equal(true)
            expect(Results[1][2]).to.equal("Success")
        end)

        it("should return a table of results given multiple threads", function()
            local Results = Async.AwaitAll({
                Async.Spawn(function()
                    return "Success"
                end),
                Async.Spawn(function()
                    error("Failure")
                end)
            })

            expect(Results).to.be.ok()
            expect(Results).to.be.a("table")
            expect(Results[1]).to.be.ok()
            expect(Results[1]).to.be.a("table")
            expect(Results[1][1]).to.equal(true)
            expect(Results[1][2]).to.equal("Success")
            expect(Results[2]).to.be.ok()
            expect(Results[2]).to.be.a("table")
            expect(Results[2][1]).to.equal(false)
            expect(Results[2][2]:match("Failure")).to.equal("Failure")
        end)

        it("should return a table of results for multiple yielding threads and wait for all of them", function()
            local Ran = 0

            local Results = Async.AwaitAll({
                Async.Spawn(function()
                    task.wait()
                    Ran += 1
                    return "Success"
                end),
                Async.Spawn(function()
                    task.wait()
                    Ran += 1
                    error("Failure")
                end),
                Async.Spawn(function()
                    task.wait(0.1)
                    Ran += 1
                end)
            })

            expect(Ran).to.equal(3)

            expect(Results).to.be.ok()
            expect(Results).to.be.a("table")
            expect(Results[1]).to.be.ok()
            expect(Results[1]).to.be.a("table")
            expect(Results[1][1]).to.equal(true)
            expect(Results[1][2]).to.equal("Success")
            expect(Results[2]).to.be.ok()
            expect(Results[2]).to.be.a("table")
            expect(Results[2][1]).to.equal(false)
            expect(Results[2][2]:match("Failure")).to.equal("Failure")
        end)
    end)

    describe("AwaitFirst", function()
        it("should reject non-tables as first arg", function()
            expect(function()
                Async.AwaitFirst(1)
            end).to.throw()

            expect(function()
                Async.AwaitFirst("test")
            end).to.throw()

            expect(function()
                Async.AwaitFirst(Async.Spawn(function() end))
            end).to.throw()

            expect(function()
                Async.AwaitFirst(function() end)
            end).to.throw()
        end)
        
        it("should accept non-empty tables as first arg", function()
            expect(function()
                Async.AwaitFirst({})
            end).to.throw()

            expect(function()
                Async.AwaitFirst({
                    Async.Spawn(function() end)
                })
            end).never.to.throw()
        end)

        it("should return the results of a thread", function()
            local Success, Result = Async.AwaitFirst({
                Async.Spawn(function()
                    return "Success"
                end)
            })

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return the results of the first thread given immediate execution", function()
            local Success, Result = Async.AwaitFirst({
                Async.Spawn(function()
                    return "Success"
                end),
                Async.Spawn(function()
                    error("Failure")
                end)
            })

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return the first thread to finish", function()
            local Success, Result = Async.AwaitFirst({
                Async.Spawn(function()
                    task.wait(0.3)
                    return "Success"
                end),
                Async.Spawn(function()
                    task.wait()
                    error("Failure")
                end)
            })

            expect(Success).to.equal(false)
            expect(Result:match("Failure")).to.equal("Failure")
        end)

        it("should return failure and timeout code given a timeout", function()
            local Success, Result = Async.AwaitFirst({
                Async.Spawn(function()
                    task.wait(0.2)
                end)
            }, 0.1)

            expect(Success).to.equal(false)
            expect(Result).to.equal("TIMEOUT")
        end)
    end)

    describe("Timer", function()
        it("should only accept a number & function as first 2 args", function()
            expect(function()
                Async.Timer(1)
            end).to.throw()

            expect(function()
                Async.Timer(1, "test")
            end).to.throw()

            expect(function()
                Async.Timer(1, 1)
            end).to.throw()

            expect(function()
                Async.Timer(1, {})
            end).to.throw()

            expect(function()
                Async.Timer("test", function() end)
            end).to.throw()

            expect(function()
                Async.Timer({}, function() end)
            end).to.throw()

            expect(function()
                Async.Timer(function() end, function() end)()
            end).to.throw()
        end)

        it("should accept an optional third argument as an optional string", function()
            expect(function()
                Async.Timer(1, function() end, 1)
            end).to.throw()

            expect(function()
                Async.Timer(1, function() end, "test")()
            end).never.to.throw()
        end)

        it("should activate twice per second for 0.5s interval", function()
            local Ran = 0

            local Stop = Async.Timer(0.5, function()
                Ran += 1
            end)

            task.wait(1)
            Stop()

            expect(Ran).to.equal(2)
        end)

        it("should activate thrice per second for 1/3s interval", function()
            local Ran = 0

            local Stop = Async.Timer(1/3, function()
                Ran += 1
            end)

            task.wait(1)
            Stop()

            expect(Ran).to.equal(3)
        end)

        it("should stop activating when cancelled", function()
            local Ran = 0

            local Stop = Async.Timer(0.1, function()
                Ran += 1
            end)

            task.wait(0.2)
            Stop()
            task.wait(0.2)

            expect(Ran).to.equal(2)
        end)
    end)

    describe("TimerAsync", function()
        it("should only accept a number & function as first 2 args", function()
            expect(function()
                Async.TimerAsync(1)
            end).to.throw()

            expect(function()
                Async.TimerAsync(1, "test")
            end).to.throw()

            expect(function()
                Async.TimerAsync(1, 1)
            end).to.throw()

            expect(function()
                Async.TimerAsync(1, {})
            end).to.throw()

            expect(function()
                Async.TimerAsync("test", function() end)
            end).to.throw()

            expect(function()
                Async.TimerAsync({}, function() end)
            end).to.throw()

            expect(function()
                Async.TimerAsync(function() end, function() end)
            end).to.throw()

            expect(function()
                Async.TimerAsync(1, function() end)()
            end).never.to.throw()
        end)

        it("should accept an optional third argument as an optional string", function()
            expect(function()
                Async.TimerAsync(1, function() end, 1)
            end).to.throw()

            expect(function()
                Async.TimerAsync(1, function() end, "test")()
            end).never.to.throw()
        end)

        it("should not block for yielding threads", function()
            local Count = 0
            local Stop = Async.TimerAsync(0, function()
                task.wait(0.1)
                Count += 1
            end)
            
            expect(Count).to.equal(0)
            task.wait()
            task.wait()
            task.wait(0.1)
            Stop()
            expect(Count).to.equal(3)
        end)

        it("should pass difference in time as first arg", function()
            local Count = 0
            local Stop = Async.TimerAsync(0, function(Delta)
                Count += 1
                expect(Delta).to.be.a("number")
            end)
            
            task.wait()
            Stop()
            expect(Count).to.equal(2)
        end)

        it("should pass difference in time as first arg for UseTaskSpawn", function()
            local Count = 0
            local Stop = Async.TimerAsync(0, function(Delta)
                Count += 1
                expect(Delta).to.be.a("number")
            end, nil, true)
            
            task.wait()
            Stop()
            expect(Count).to.equal(2)
        end)
    end)

    describe("Parent", function()
        it("should accept a thread or nil as the first arg only", function()
            expect(function()
                Async.Parent(1)
            end).to.throw()

            expect(function()
                Async.Parent("test")
            end).to.throw()
            
            expect(function()
                Async.Parent({})
            end).to.throw()

            expect(function()
                Async.Spawn(function()
                    Async.Parent()
                end)
            end).never.to.throw()

            expect(function()
                Async.Parent(Async.Spawn(function() end))
            end).never.to.throw()
        end)

        it("should throw for non Async-spawned threads given no args", function()
            task.spawn(function()
                expect(function()
                    Async.Parent()
                end).to.throw()
            end)
        end)

        it("should return the parent thread given one Spawn call", function()
            local Thread = coroutine.running()
            local SubThread

            Async.Spawn(function()
                SubThread = Async.Parent()
            end)

            expect(SubThread).to.equal(Thread)
        end)

        it("should return the parent thread given two Spawn calls", function()
            local Thread
            local SubThread

            Async.Spawn(function()
                Thread = coroutine.running()

                Async.Spawn(function()
                    SubThread = Async.Parent()
                end)
            end)

            expect(SubThread).to.equal(Thread)
        end)
    end)

    describe("Results", function()
        it("should accept a thread as the first arg only", function()
            expect(function()
                Async.Results(1)
            end).to.throw()

            expect(function()
                Async.Results("test")
            end).to.throw()
            
            expect(function()
                Async.Results({})
            end).to.throw()

            expect(function()
                Async.Results()
            end).to.throw()

            expect(function()
                Async.Results(Async.Spawn(function() end))
            end).never.to.throw()
        end)

        it("should return a table of results if the thread has finished", function()
            local Thread = Async.Spawn(function()
                return 123
            end)

            local Success, Result = Async.Results(Thread)
            expect(Success).to.equal(true)
            expect(Result).to.equal(123)
        end)

        it("should return nil if the thread has not finished", function()
            local Thread = Async.Spawn(function()
                task.wait(1)
                return 123
            end)

            expect(Async.Results(Thread)).to.equal(nil)
        end)

        it("should return nil for unregistered threads", function()
            local Success, Result
            task.spawn(function()
                Success, Result = Async.Results(coroutine.running())
            end)

            expect(Success).to.equal(nil)
            expect(Result).to.equal(nil)
        end)
    end)

    describe("FireSignal", function()
        it("should fire a signal to all running descendant threads", function()
            local Count = 0
            local Root = Async.Spawn(function()
                Async.OnSignal(function(Data)
                    Count += (Data == "Test" and 1 or 0)
                end)

                Async.Spawn(function()
                    Async.OnSignal(function(Data)
                        Count += (Data == "Test" and 1 or 0)
                    end)

                    coroutine.yield()
                end)

                coroutine.yield()
            end)

            expect(Count).to.equal(0)
            Async.FireSignal(Root, "Test")
            expect(Count).to.equal(2)
            Async.FireSignal(Root, "Irrelevant")
            expect(Count).to.equal(2)
            Async.FireSignal(Root, "Test")
            expect(Count).to.equal(4)
        end)

        it("should ignore finished threads by default", function()
            local Count = 0
            local Root = Async.Spawn(function()
                Async.OnSignal(function(Data)
                    Count += (Data == "Test" and 1 or 0)
                end)

                Async.Spawn(function()
                    Async.OnSignal(function(Data)
                        Count += (Data == "Test" and 1 or 0)
                    end)

                    coroutine.yield()
                end)
            end)

            expect(Count).to.equal(0)
            Async.FireSignal(Root, "Test")
            expect(Count).to.equal(1)
            Async.FireSignal(Root, "Irrelevant")
            expect(Count).to.equal(1)
            Async.FireSignal(Root, "Test")
            expect(Count).to.equal(2)
        end)

        it("should stop at a given depth number", function()
            local Count = 0
            
            local function Make(Callback)
                return Async.Spawn(function()
                    Async.OnSignal(function(Data)
                        Count += (Data == "Test" and 1 or 0)
                    end)

                    if (Callback) then Callback() end
                    coroutine.yield()
                end)
            end

            local Root = Make(function()
                Make(function()
                    Make(function() end)
                    Make(function() end)
                    Make(function() end)
                    Make(function() end)
                end)
                Make(function()
                    Make(function() end)
                    Make(function() end)
                    Make(function() end)
                    Make(function() end)
                end)
            end)

            expect(Count).to.equal(0)
            Async.FireSignal(Root, "Test", 2)
            expect(Count).to.equal(3)
            Async.FireSignal(Root, "Irrelevant")
            expect(Count).to.equal(3)
            Async.FireSignal(Root, "Test", 2)
            expect(Count).to.equal(6)
        end)

        it("should include finished threads if AllowFinishedThreads is true", function()
            local Count = 0
            local Root = Async.Spawn(function()
                Async.OnSignal(function(Data)
                    Count += (Data == "Test" and 1 or 0)
                end)

                Async.Spawn(function()
                    Async.OnSignal(function(Data)
                        Count += (Data == "Test" and 1 or 0)
                    end)

                    coroutine.yield()
                end)
            end)

            expect(Count).to.equal(0)
            Async.FireSignal(Root, "Test", nil, true)
            expect(Count).to.equal(2)
            Async.FireSignal(Root, "Irrelevant", nil, true)
            expect(Count).to.equal(2)
            Async.FireSignal(Root, "Test", nil, true)
            expect(Count).to.equal(4)
        end)
    end)

    describe("Retries", function()
        it("should retry the function a given number of times before failing", function()
            local Ran = 0
            local Success, Result = Async.Await(Async.Retries(function()
                Ran += 1
                error("<<Test>>")
            end, 3))

            expect(Ran).to.equal(3)
            expect(Success).to.equal(false)
            expect(Result).to.equal("RETRIES_EXHAUSTED")
        end)

        it("should retry the function a given number of times with a delay", function()
            local Ran = 0
            local Start = os.clock()
            Async.Await(Async.Retries(function()
                Ran += 1
                error("<<Test>>")
            end, 3, 0.1))

            expect(Ran).to.equal(3)
            expect((os.clock() - Start) > 0.3).to.equal(true)
        end)

        it("should accept a timeout and give a TIMEOUT result if it occurs", function()
            local Finished = false
            local Success, Result = Async.Await(Async.Retries(function()
                Async.OnFinish(function()
                    Finished = true
                end)
                error("<<Test>>")
            end, 3, 0.1, 0.1))

            expect(Success).to.equal(false)
            expect(Result).to.equal("TIMEOUT")
            expect(Finished).to.equal(true)
        end)

        it("should return the result of the first successful call", function()
            local Success, Result = Async.Await(Async.Retries(function()
                return "Success"
            end, 3))
            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")

            local Count = 0
            Success, Result = Async.Await(Async.Retries(function()
                Count += 1

                if (Count < 2) then
                    error("<<Test>>")
                end

                return "Success"
            end, 3))
            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)
    end)

    describe("AwaitDescendants", function()
        it("should yield until all descendants finish", function()
            local Start = os.clock()
            local Root = Async.Spawn(function()
                Async.Spawn(function()
                    Async.Spawn(function()
                        task.wait(0.1)
                    end)

                    task.wait(0.1)
                end)

                task.wait(0.1)
            end)
            Async.AwaitDescendants(Root)
            expect((os.clock() - Start) > 0.1).to.equal(true)
        end)

        it("should immediately accept dead threads", function()
            local Start = os.clock()
            local Root = Async.Spawn(function()
                Async.Spawn(function()
                    Async.Spawn(function()
                        error("<<wah>>")
                    end)

                    task.wait(0.1)
                end)

                task.wait(0.1)
            end)
            local Results = Async.AwaitDescendants(Root)
            expect((os.clock() - Start) > 0.1).to.equal(true)
            expect(#Results).to.equal(3)
        end)
    end)
end