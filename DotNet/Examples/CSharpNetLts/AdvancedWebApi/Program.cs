using System.Collections.Frozen;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.Extensions.Options;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

builder.Services
    .AddOptions<CatalogOptions>()
    .BindConfiguration(CatalogOptions.SectionName)
    .Validate(
        options => options.MaxPageSize is > 0 and <= 100,
        "Catalog:MaxPageSize must be between 1 and 100.")
    .ValidateOnStart();

builder.Services.AddSingleton<ProductCatalog>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddKeyedSingleton<ITimeFormatter, IsoTimeFormatter>("iso");

builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.TypeInfoResolverChain.Insert(
        0,
        AppJsonContext.Default));

WebApplication app = builder.Build();

app.UseExceptionHandler();

app.MapGet(
    "/products/{id:int}",
    Results<Ok<Product>, NotFound> (int id, ProductCatalog catalog) =>
        catalog.Find(id) is { } product
            ? TypedResults.Ok(product)
            : TypedResults.NotFound());

app.MapGet(
    "/products",
    Ok<IReadOnlyList<Product>> (
        int? take,
        ProductCatalog catalog,
        IOptions<CatalogOptions> options) =>
    {
        int pageSize = Math.Clamp(
            take ?? options.Value.DefaultPageSize,
            1,
            options.Value.MaxPageSize);

        return TypedResults.Ok(catalog.Take(pageSize));
    });

app.MapGet(
    "/time",
    Ok<TimeResponse> (
        [FromKeyedServices("iso")] ITimeFormatter formatter,
        TimeProvider timeProvider) =>
        TypedResults.Ok(new TimeResponse(formatter.Format(timeProvider.GetUtcNow()))));

app.MapGet("/boom", static IResult () =>
    throw new InvalidOperationException("Demonstration exception."));

app.Run();

public sealed record Product(int Id, string Name, decimal Price);

public sealed record TimeResponse(string UtcNow);

public sealed class ProductCatalog
{
    private readonly FrozenDictionary<int, Product> _products =
        new Product[]
        {
            new(1, "Keyboard", 99m),
            new(2, "Mouse", 49m),
            new(3, "Monitor", 399m)
        }.ToFrozenDictionary(product => product.Id);

    public Product? Find(int id) => _products.GetValueOrDefault(id);

    public IReadOnlyList<Product> Take(int count) =>
        _products.Values.Take(count).ToArray();
}

public sealed class CatalogOptions
{
    public const string SectionName = "Catalog";

    public int DefaultPageSize { get; init; } = 20;
    public int MaxPageSize { get; init; } = 100;
}

public interface ITimeFormatter
{
    string Format(DateTimeOffset value);
}

public sealed class IsoTimeFormatter : ITimeFormatter
{
    public string Format(DateTimeOffset value) => value.ToString("O");
}

public sealed class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.LogError(exception, "Unhandled request failure");

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;
        await TypedResults.Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "Unexpected server error")
            .ExecuteAsync(httpContext);

        return true;
    }
}

[JsonSerializable(typeof(Product))]
[JsonSerializable(typeof(Product[]))]
[JsonSerializable(typeof(IReadOnlyList<Product>))]
[JsonSerializable(typeof(TimeResponse))]
internal sealed partial class AppJsonContext : JsonSerializerContext;
