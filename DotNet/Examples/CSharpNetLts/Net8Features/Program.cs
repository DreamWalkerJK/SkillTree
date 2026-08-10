using System.Buffers;
using System.Collections.Frozen;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using Point = (int X, int Y);

Console.WriteLine("C# 12 / .NET 8");

var calculator = new PriceCalculator(0.13m);
Console.WriteLine(calculator.Gross(100m));

string[] core = ["C#", ".NET"];
string[] stack = [.. core, "ASP.NET Core", "EF Core"];
Console.WriteLine(string.Join(" -> ", stack));

Point point = (3, 4);
Console.WriteLine($"Point length squared: {point.X * point.X + point.Y * point.Y}");

var greet = (string name = "world") => $"Hello, {name}!";
Console.WriteLine(greet());

var buffer = new IntBuffer8();
for (int index = 0; index < 8; index++)
{
    buffer[index] = index * index;
}

Console.WriteLine($"Inline array last item: {buffer[7]}");

FrozenDictionary<string, int> statusCodes = new Dictionary<string, int>
{
    ["ok"] = 200,
    ["not-found"] = 404
}.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

Console.WriteLine(statusCodes["OK"]);

SearchValues<char> separators = SearchValues.Create([',', ';', '|']);
ReadOnlySpan<char> input = "alpha;beta";
Console.WriteLine($"First separator index: {input.IndexOfAny(separators)}");

string[] choices = ["red", "green", "blue"];
string[] picks = Random.Shared.GetItems(choices, 5);
Random.Shared.Shuffle(picks);
Console.WriteLine(string.Join(", ", picks));

var clock = new ManualTimeProvider(
    new DateTimeOffset(2026, 8, 10, 0, 0, 0, TimeSpan.Zero));
var token = new AccessToken(clock.GetUtcNow().AddMinutes(5));
var tokenService = new TokenService(clock);
Console.WriteLine($"Expired before advance: {tokenService.IsExpired(token)}");
clock.Advance(TimeSpan.FromMinutes(6));
Console.WriteLine($"Expired after advance: {tokenService.IsExpired(token)}");

Customer customer = JsonSerializer.Deserialize<Customer>(
    """{ "tags": ["new", "vip"] }""",
    new JsonSerializerOptions(JsonSerializerDefaults.Web))
    ?? throw new JsonException("Customer payload cannot be null.");

Console.WriteLine(string.Join(", ", customer.Tags));

public sealed class PriceCalculator(decimal taxRate)
{
    private readonly decimal _taxRate = taxRate is >= 0m and <= 1m
        ? taxRate
        : throw new ArgumentOutOfRangeException(nameof(taxRate));

    public decimal Gross(decimal net) => net * (1m + _taxRate);
}

[InlineArray(8)]
public struct IntBuffer8
{
    private int _element0;
}

public sealed class ManualTimeProvider(DateTimeOffset initialUtcNow) : TimeProvider
{
    private DateTimeOffset _utcNow = initialUtcNow;

    public override DateTimeOffset GetUtcNow() => _utcNow;

    public void Advance(TimeSpan duration) => _utcNow += duration;
}

public sealed record AccessToken(DateTimeOffset ExpiresAt);

public sealed class TokenService(TimeProvider timeProvider)
{
    public bool IsExpired(AccessToken token) =>
        timeProvider.GetUtcNow() >= token.ExpiresAt;
}

public sealed class Customer
{
    [JsonObjectCreationHandling(JsonObjectCreationHandling.Populate)]
    public List<string> Tags { get; } = ["existing"];
}
