using System.IO.Compression;
using System.Text.Json;

Console.WriteLine("C# 14 / .NET 10");

UserProfile? profile = new("  Ada Lovelace  ");
profile?.LastSeenAt = new DateTimeOffset(2026, 8, 10, 12, 0, 0, TimeSpan.Zero);
Console.WriteLine($"{profile?.DisplayName}: {profile?.LastSeenAt:O}");

int[] values = [10, 20, 30];
Console.WriteLine($"Terminal state = {JobState.Completed.IsTerminal}");
Console.WriteLine($"Every other value = {string.Join(", ", values.EveryOther())}");

TryParse<int> parseInt = (text, out result) => int.TryParse(text, out result);
Console.WriteLine(parseInt("42", out int parsed) ? parsed : -1);
Console.WriteLine(nameof(Dictionary<,>));

Order[] orders =
[
    new(1, 100, 199m),
    new(2, 999, 20m)
];

Customer[] customers =
[
    new(100, "Grace")
];

var orderView = orders.LeftJoin(
    customers,
    order => order.CustomerId,
    customer => customer.Id,
    (order, customer) => new
    {
        order.Id,
        Customer = customer?.Name ?? "<missing>",
        order.Total
    });

foreach (var item in orderView)
{
    Console.WriteLine($"Order {item.Id}: {item.Customer}, {item.Total:C}");
}

const string duplicateJson = """
    { "name": "first", "name": "second" }
    """;

try
{
    _ = JsonSerializer.Deserialize<Payload>(duplicateJson, JsonSerializerOptions.Strict);
}
catch (JsonException exception)
{
    Console.WriteLine($"Strict JSON rejected the payload: {exception.GetType().Name}");
}

Console.WriteLine($"ZIP bytes: {await CreateZipAsync(CancellationToken.None)}");

var counter = new Counter();
counter += 3;
Console.WriteLine($"Counter: {counter.Value}");

var sink = new AuditSink("console");
sink.Written += (_, message) => Console.WriteLine($"audit: {message}");
sink.Write("ready");

static async Task<long> CreateZipAsync(CancellationToken cancellationToken)
{
    await using var destination = new MemoryStream();

    using (ZipArchive archive = await ZipArchive.CreateAsync(
               destination,
               ZipArchiveMode.Create,
               leaveOpen: true,
               entryNameEncoding: null,
               cancellationToken))
    {
        ZipArchiveEntry entry = archive.CreateEntry("hello.txt");
        await using Stream content = await entry.OpenAsync(cancellationToken);
        await content.WriteAsync("hello from .NET 10"u8.ToArray(), cancellationToken);
    }

    return destination.Length;
}

public delegate bool TryParse<T>(string text, out T result);

public enum JobState
{
    Pending,
    Running,
    Completed,
    Failed
}

public static class ExtensionMembers
{
    extension(JobState state)
    {
        public bool IsTerminal =>
            state is JobState.Completed or JobState.Failed;
    }

    extension<T>(IEnumerable<T> source)
    {
        public IEnumerable<T> EveryOther() =>
            source.Where((_, index) => index % 2 == 0);
    }
}

public sealed class UserProfile
{
    public UserProfile(string displayName)
    {
        DisplayName = displayName;
    }

    public string DisplayName
    {
        get => field;
        set => field = string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("Display name is required.", nameof(value))
            : value.Trim();
    }

    public DateTimeOffset? LastSeenAt { get; set; }
}

public sealed record Order(int Id, int CustomerId, decimal Total);

public sealed record Customer(int Id, string Name);

public sealed record Payload(string Name);

public struct Counter
{
    public int Value { get; private set; }

    public void operator +=(int amount)
    {
        Value = checked(Value + amount);
    }
}
