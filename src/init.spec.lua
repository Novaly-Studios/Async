local function anyfn(...) return ({} :: any) end
it = it or anyfn
expect = expect or anyfn
describe = describe or anyfn

return function()
    local Async = require(script.Parent)

    describe("Async.Spawn", function()
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

        it("should pass an OnFinish callback as first arg", function()
            local GotType = ""

            Async.Spawn(function(OnFinish)
                GotType = typeof(OnFinish)
            end)

            expect(GotType).to.equal("function")
        end)

        it("should call OnFinish with whatever returns from a regularly terminating thread", function()
            local Success, Result

            Async.Spawn(function(OnFinish)
                OnFinish(function(GotSuccess, GotResult)
                    Success = GotSuccess
                    Result = GotResult
                end)

                return true, "Test"
            end)

            expect(Success).to.equal(true)
            expect(Result).to.equal("Test")
        end)

        it("should call OnFinish if the thread yields", function()
            local Success, Result

            Async.Spawn(function(OnFinish)
                OnFinish(function(GotSuccess, GotResult)
                    Success = GotSuccess
                    Result = GotResult
                end)

                task.wait()
                return true, "Test"
            end)

            expect(Success).to.equal(nil)
            expect(Result).to.equal(nil)
            task.wait()
            expect(Success).to.equal(true)
            expect(Result).to.equal("Test")
        end)

        it("should call OnFinish if the thread errors", function()
            local Success, Result

            Async.Spawn(function(OnFinish)
                OnFinish(function(GotSuccess, GotResult)
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

            Async.Spawn(function(OnFinish)
                OnFinish(function(GotSuccess, GotResult)
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

            local Thread = Async.Spawn(function(OnFinish1)
                OnFinish1(function()
                    Call1 = true
                end)

                Async.Spawn(function(OnFinish2)
                    OnFinish2(function()
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

            local Thread = Async.Spawn(function(OnFinish1)
                OnFinish1(function()
                    Call1 = true
                end)

                Async.Spawn(function(OnFinish2)
                    OnFinish2(function()
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

    describe("Async.SpawnTimeLimit", function()
        it("should reject non-numbers as first arg", function()
            expect(function()
                Async.SpawnTimeLimit("test")
            end).to.throw()

            expect(function()
                Async.SpawnTimeLimit({})
            end).to.throw()

            expect(function()
                Async.SpawnTimeLimit(function() end)
            end).to.throw()
        end)

        it("should reject non-functions as second arg", function()
            expect(function()
                Async.SpawnTimeLimit(1, 1)
            end).to.throw()

            expect(function()
                Async.SpawnTimeLimit(1, "test")
            end).to.throw()

            expect(function()
                Async.SpawnTimeLimit(1, {})
            end).to.throw()
        end)

        it("should accept a number as first arg & a function as second arg", function()
            expect(function()
                Async.SpawnTimeLimit(1, function() end)
            end).never.to.throw()
        end)

        it("should spawn a thread immediately", function()
            local Finished = false

            Async.SpawnTimeLimit(1, function()
                Finished = true
            end)

            expect(Finished).to.equal(true)
        end)

        it("should terminate a thread which has been running for more than the timeout", function()
            local Finished = false

            Async.SpawnTimeLimit(0, function()
                task.wait()
                task.wait()
                Finished = true
            end)

            expect(Finished).to.equal(false)
            task.wait()
            task.wait()
            expect(Finished).to.equal(false)
        end)

        it("should not cancel sub-threads if the main thread does not timeout", function()
            local Cancelled

            Async.SpawnTimeLimit(0, function()
                Async.Spawn(function(OnFinish)
                    OnFinish(function(Success)
                        if (not Success) then
                            Cancelled = true
                        end
                    end)

                    task.wait()
                    task.wait()
                end)
            end)

            expect(Cancelled).to.equal(nil)
            task.wait()
            task.wait()
            expect(Cancelled).to.equal(nil)
        end)
    end)

    describe("Async.SpawnTimedCancel", function()
        it("should cancel sub-threads if the main thread does not timeout", function()
            local Cancelled

            Async.SpawnTimedCancel(0, function()
                Async.Spawn(function(OnFinish)
                    OnFinish(function(Success)
                        if (not Success) then
                            Cancelled = true
                        end
                    end)

                    task.wait()
                    task.wait()
                end)
            end)

            expect(Cancelled).to.equal(nil)
            task.wait()
            task.wait()
            expect(Cancelled).to.equal(true)
        end)
    end)

    describe("Async.Delay", function()
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

    describe("Async.Defer", function()
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

    describe("Async.Cancel", function()
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

                local Thread = Async.Spawn(function(OnFinish)
                    OnFinish(function(GotSuccess, GotResult)
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

            local Main = Async.Spawn(function(OnFinish)
                OnFinish(function(Success)
                    FirstSuccess = Success
                end)

                Async.Spawn(function(OnFinish)
                    OnFinish(function(Success)
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

            local Main = Async.Spawn(function(OnFinish)
                OnFinish(function(Success)
                    FirstSuccess = Success
                end)

                Async.Spawn(function(OnFinish)
                    OnFinish(function(Success)
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

    describe("Async.Resolve", function()
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

                local Thread = Async.Spawn(function(OnFinish)
                    OnFinish(function(GotSuccess, GotResult)
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
    end)

    describe("Async.Await", function()
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
                return true, "Success"
            end))

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return for yielding threads", function()
            local Success, Result = Async.Await(Async.Spawn(function()
                task.wait()
                return true, "Success"
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

    describe("Async.AwaitAll", function()
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
                    return true, "Success"
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
                    return true, "Success"
                end),
                Async.Spawn(function()
                    return false, "Failure"
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
            expect(Results[2][2]).to.equal("Failure")
        end)

        it("should return a table of results for multiple yielding threads and wait for all of them", function()
            local Ran = 0

            local Results = Async.AwaitAll({
                Async.Spawn(function()
                    task.wait()
                    Ran += 1
                    return true, "Success"
                end),
                Async.Spawn(function()
                    task.wait()
                    Ran += 1
                    return false, "Failure"
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
            expect(Results[2][2]).to.equal("Failure")
        end)
    end)

    describe("Async.AwaitFirst", function()
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
                    return true, "Success"
                end)
            })

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return the results of the first thread given immediate execution", function()
            local Success, Result = Async.AwaitFirst({
                Async.Spawn(function()
                    return true, "Success"
                end),
                Async.Spawn(function()
                    return false, "Failure"
                end)
            })

            expect(Success).to.equal(true)
            expect(Result).to.equal("Success")
        end)

        it("should return the first thread to finish", function()
            local Success, Result = Async.AwaitFirst({
                Async.Spawn(function()
                    task.wait(0.3)
                    return true, "Success"
                end),
                Async.Spawn(function()
                    task.wait()
                    return false, "Failure"
                end)
            })

            expect(Success).to.equal(false)
            expect(Result).to.equal("Failure")
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

    describe("Async.Timer", function()
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
                Async.Timer(function() end, function() end)
            end).to.throw()

            expect(function()
                task.cancel(Async.Timer(1, function() end))
            end).never.to.throw()
        end)

        it("should accept an optional third argument as an optional string", function()
            expect(function()
                Async.Timer(1, function() end, 1)
            end).to.throw()

            expect(function()
                task.cancel(Async.Timer(1, function() end, "test"))
            end).never.to.throw()
        end)

        it("should activate twice per second for 0.5s interval", function()
            local Ran = 0

            local Thread = Async.Timer(0.5, function()
                Ran += 1
            end)

            task.wait(1)
            task.cancel(Thread)

            expect(Ran).to.equal(2)
        end)

        it("should activate thrice per second for 1/3s interval", function()
            local Ran = 0

            local Thread = Async.Timer(1/3, function()
                Ran += 1
            end)

            task.wait(1)
            task.cancel(Thread)

            expect(Ran).to.equal(3)
        end)

        it("should stop activating when cancelled", function()
            local Ran = 0

            local Thread = Async.Timer(0.1, function()
                Ran += 1
            end)

            task.wait(0.2)
            task.cancel(Thread)
            task.wait(0.2)

            expect(Ran).to.equal(2)
        end)
    end)
end