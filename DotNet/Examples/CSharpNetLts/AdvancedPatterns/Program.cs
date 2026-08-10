using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Metrics;
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Threading.Channels;

int[] numbers = [1, 2, 3, 4, 5];
Console.WriteLine($"Generic sum: {Numeric.Sum<int>(numbers)}");

if (Text.TryNormalize("  codex  ", out string? normalized))
{
    Console.WriteLine(normalized.ToUpperInvariant());
}

OrderResult result = PlaceOrder(quantity: 2);
Console.WriteLine(result switch
{
    OrderResult.Accepted(var orderId) => $"Accepted: {orderId}",
    OrderResult.Rejected(var reason) => $"Rejected: {reason}",
    _ => throw new UnreachableException()
});

if (Csv.TryParsePair("21,34", out (int Left, int Right) pair))
{
    Console.WriteLine($"Span parser: {pair.Left + pair.Right}");
}

using var listener = new ActivityListener
{
    ShouldListenTo = source => source.Name == Telemetry.SourceName,
    Sample = static (ref ActivityCreationOptions<ActivityContext> _) =>
        ActivitySamplingResult.AllData
};
ActivitySource.AddActivityListener(listener);

using (Activity? activity = Telemetry.ActivitySource.StartActivity("advanced-demo"))
{
    activity?.SetTag("demo.version", 1);
    Telemetry.Executions.Add(1);
    await RunPipelineAsync(CancellationToken.None);
}

await foreach (int item in ReadSequenceAsync(3, CancellationToken.None))
{
    Console.WriteLine($"Async stream: {item}");
}

static OrderResult PlaceOrder(int quantity) => quantity switch
{
    <= 0 => new OrderResult.Rejected("Quantity must be positive."),
    > 100 => new OrderResult.Rejected("Quantity exceeds the limit."),
    _ => new OrderResult.Accepted(Guid.NewGuid())
};

static async Task RunPipelineAsync(CancellationToken cancellationToken)
{
    Channel<int> channel = Channel.CreateBounded<int>(new BoundedChannelOptions(4)
    {
        SingleWriter = true,
        SingleReader = true,
        FullMode = BoundedChannelFullMode.Wait
    });

    Task producer = ProduceAsync(channel.Writer, cancellationToken);
    Task<int> consumer = ConsumeAsync(channel.Reader, cancellationToken);

    await producer;
    Console.WriteLine($"Channel sum: {await consumer}");
}

static async Task ProduceAsync(
    ChannelWriter<int> writer,
    CancellationToken cancellationToken)
{
    try
    {
        for (int value = 1; value <= 5; value++)
        {
            await writer.WriteAsync(value, cancellationToken);
        }
    }
    finally
    {
        writer.TryComplete();
    }
}

static async Task<int> ConsumeAsync(
    ChannelReader<int> reader,
    CancellationToken cancellationToken)
{
    int sum = 0;

    await foreach (int value in reader.ReadAllAsync(cancellationToken))
    {
        sum += value;
    }

    return sum;
}

static async IAsyncEnumerable<int> ReadSequenceAsync(
    int count,
    [EnumeratorCancellation] CancellationToken cancellationToken = default)
{
    for (int value = 0; value < count; value++)
    {
        await Task.Delay(10, cancellationToken);
        yield return value;
    }
}

public static class Numeric
{
    public static T Sum<T>(ReadOnlySpan<T> values)
        where T : INumber<T>
    {
        T result = T.Zero;

        foreach (T value in values)
        {
            result += value;
        }

        return result;
    }
}

public static class Text
{
    public static bool TryNormalize(
        string? input,
        [NotNullWhen(true)] out string? normalized)
    {
        normalized = input?.Trim();
        return !string.IsNullOrEmpty(normalized);
    }
}

public abstract record OrderResult
{
    private OrderResult()
    {
    }

    public sealed record Accepted(Guid OrderId) : OrderResult;

    public sealed record Rejected(string Reason) : OrderResult;
}

public static class Csv
{
    public static bool TryParsePair(
        ReadOnlySpan<char> input,
        out (int Left, int Right) pair)
    {
        int separator = input.IndexOf(',');
        if (separator < 0
            || !int.TryParse(input[..separator], out int left)
            || !int.TryParse(input[(separator + 1)..], out int right))
        {
            pair = default;
            return false;
        }

        pair = (left, right);
        return true;
    }
}

public static class Telemetry
{
    public const string SourceName = "SkillTree.AdvancedPatterns";

    public static readonly ActivitySource ActivitySource = new(SourceName);
    public static readonly Meter Meter = new(SourceName);
    public static readonly Counter<long> Executions =
        Meter.CreateCounter<long>("demo.executions");
}
