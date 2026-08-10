public sealed partial class AuditSink
{
    public partial AuditSink(string name);

    public partial event EventHandler<string>? Written;
}
