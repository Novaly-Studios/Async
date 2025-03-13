local function anyfn(...) return ({} :: any) end
it = it or anyfn
expect = expect or anyfn
describe = describe or anyfn

local Async = require(script.Parent.Async)
local Task = require(script.Parent.Task)

return function()
    describe("usingDelay", function()
        it("should emulate Async.Delay", function()
            local DidRun = false

            Task.usingDelay(0, function()
                DidRun = true
            end)

            expect(DidRun).to.equal(false)
            task.wait()
            expect(DidRun).to.equal(true)
        end)
    end)
    
    describe("usingDefer", function()
        it("should emulate Async.Defer", function()
            local DidRun = false

            Task.usingDefer(function()
                DidRun = true
            end)

            expect(DidRun).to.equal(false)
            Async.DeferWait()
            expect(DidRun).to.equal(true)
        end)
    end)

    describe("usingSpawn", function()
        it("should emulate Async.Spawn", function()
            local DidRun = false

            Task.usingSpawn(function()
                DidRun = true
            end)

            expect(DidRun).to.equal(true)
        end)
    end)

    describe("usingRetries", function()
        it("should emulate Async.Retries", function()
            local DidRun = false
            local Count = 0

            Task.usingRetries(function()
                if (Count < 2) then
                    Count += 1
                    error("<<Test>>")
                end

                DidRun = true
            end, 3)

            expect(DidRun).to.equal(true)
        end)
    end)

    describe("new", function()
        it("should be the same implementation as usingTimeLimit", function()
            expect(Task.new).to.equal(Task.usingTimeLimit)
        end)

        it("should emulate Async.SpawnTimed", function()
            local DidFinish = false
            local DidRun = false

            Task.new(function()
                DidRun = true
                task.wait()
                task.wait()
                DidFinish = true
            end, 0)

            expect(DidRun).to.equal(true)
            expect(DidFinish).to.equal(false)
            task.wait()
            task.wait()
            expect(DidFinish).to.equal(false)
        end)
    end)

    describe("DidComplete", function()
        it("should return false if the task has not completed", function()
            expect(Task.new(function()
                task.wait()
            end):DidComplete()).to.equal(false)
        end)

        it("should return true if the task has completed", function()
            expect(Task.new(function() end):DidComplete()).to.equal(true)

            expect(Task.new(function()
                error("AHHH")
            end):DidComplete()).to.equal(true)
        end)
    end)

    describe("DidSucceed", function()
        it("should return false if the task failed", function()
            expect(Task.new(function()
                error("AHHH")
            end):DidSucceed()).to.equal(false)
        end)

        it("should return false if the task is still running", function()
            expect(Task.new(function()
                task.wait()
            end):DidSucceed()).to.equal(false)
        end)

        it("should return true if the task succeeded", function()
            expect(Task.new(function() end):DidSucceed()).to.equal(true)
        end)
    end)

    describe("DidFail", function()
        it("should return false if the task succeeded", function()
            expect(Task.new(function() end):DidFail()).to.equal(false)
        end)

        it("should return false if the task is still running", function()
            expect(Task.new(function()
                task.wait()
            end):DidFail()).to.equal(false)
        end)

        it("should return true if the task failed", function()
            expect(Task.new(function()
                error("AHHH")
            end):DidFail()).to.equal(true)
        end)
    end)

    describe("Get", function()
        it("should return the success, result pair for the task", function()
            local Success, Result = Task.new(function()
                return "Test"
            end):Get()
            expect(Success).to.equal(true)
            expect(Result).to.equal("Test")
        end)
    end)

    describe("GetValue", function()
        it("should return the result for the task", function()
            expect(Task.new(function()
                return "Test"
            end):GetValue()).to.equal("Test")
        end)
    end)

    describe("Await", function()
        it("should replicate Async.Await", function()
            local Finished = false
            local Success, Result

            task.spawn(function()
                Success, Result = Task.new(function()
                    task.wait()
                    return "Test"
                end):Await()

                Finished = true
            end)

            expect(Finished).to.equal(false)
            expect(Success).to.equal(nil)
            expect(Result).to.equal(nil)
            task.wait()
            expect(Finished).to.equal(true)
            expect(Success).to.equal(true)
            expect(Result).to.equal("Test")
        end)
    end)

    describe("AwaitValue", function()
        it("should only return the value", function()
            expect(Task.new(function()
                task.wait()
                return "Test"
            end):AwaitValue()).to.equal("Test")
        end)
    end)

    describe("Cancel", function()
        it("should terminate the root task", function()
            local Test = Task.new(function()
                task.wait()
            end)
            expect(Test:DidFail()).to.equal(false)
            Test:Cancel()
            expect(Test:DidFail()).to.equal(true)
        end)
    end)

    describe("AwaitDescendants", function()
        it("should wait for all descendant tasks, emulating Async.AwaitDescendants", function()
            local Start = os.clock()
            local Root = Task.new(function()
                Task.new(function()
                    Task.new(function()
                        task.wait(0.1)
                    end)

                    task.wait(0.1)
                end)

                task.wait(0.1)
            end)

            local Results = Root:AwaitDescendants()
            expect((os.clock() - Start) > 0.1).to.equal(true)
            expect(#Results).to.equal(3)
        end)
    end)

    describe("FireSignal", function()
        it("should fire a signal to all descendant tasks, emulating Async.FireSignal", function()
            local Count = 0
            local Root = Task.new(function()
                Task.new(function()
                    Task.OnSignal(function(Data)
                        Count += (Data == "Test" and 1 or 0)
                    end)

                    coroutine.yield()
                end)

                Task.OnSignal(function(Data)
                    Count += (Data == "Test" and 1 or 0)
                end)

                coroutine.yield()
            end)
            
            Root:FireSignal("Test")
            expect(Count).to.equal(2)
            Root:FireSignal("Irrelevant")
            expect(Count).to.equal(2)
            Root:FireSignal("Test")
            expect(Count).to.equal(4)
        end)
    end)
end