Console.WriteLine("== 已完成任务 ==");

Res fromResult = await Samples.FromResultAsync();
Res fromAsync = await Samples.AsyncWithRealAwaitAsync();

Console.WriteLine(fromResult);
Console.WriteLine(fromAsync);

Console.WriteLine();
Console.WriteLine("== 异常出现时机 ==");

ObserveCall("普通 Task 返回方法", Samples.ValidateThenFromResultAsync);
ObserveCall("async 方法", Samples.ValidateInsideAsyncMethodAsync);

static void ObserveCall(
    string name,
    Func<string, Task<Res>> operation)
{
    try
    {
        Task<Res> task = operation("");
        Console.WriteLine($"{name}: 调用已返回，状态为 {task.Status}");

        try
        {
            _ = task.GetAwaiter().GetResult();
        }
        catch (Exception exception)
        {
            Console.WriteLine(
                $"{name}: 等待任务时抛出 {exception.GetType().Name}");
        }
    }
    catch (Exception exception)
    {
        Console.WriteLine(
            $"{name}: 调用方法时直接抛出 {exception.GetType().Name}");
    }
}

public static class Samples
{
    public static Task<Res> FromResultAsync()
    {
        return Task.FromResult(new Res(0, "来自 Task.FromResult"));
    }

    public static async Task<Res> AsyncWithRealAwaitAsync()
    {
        await Task.Delay(10);
        return new Res(0, "来自真实异步等待");
    }

    public static Task<Res> ValidateThenFromResultAsync(string input)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(input);
        return Task.FromResult(new Res(0, input));
    }

    public static async Task<Res> ValidateInsideAsyncMethodAsync(
        string input)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(input);
        await Task.Yield();
        return new Res(0, input);
    }
}

public sealed record Res(int Code, string Message);
