public sealed partial class AuditSink
{
    private readonly string _name;
    private EventHandler<string>? _written;

    public partial AuditSink(string name)
    {
        _name = name;
    }

    public partial event EventHandler<string>? Written
    {
        add => _written += value;
        remove => _written -= value;
    }

    public void Write(string message) =>
        _written?.Invoke(this, $"[{_name}] {message}");
}
