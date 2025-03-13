local Async = require(script:WaitForChild("Async"))

local Task = require(script:WaitForChild("Task"))
export type Task<Result> = Task.Task<Result>

return {
    Async = Async;
    Task = Task;
}