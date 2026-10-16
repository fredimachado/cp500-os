namespace Cp500Os.C5fs;

public sealed class C5fsException : Exception
{
    public C5fsException(C5fsError error, string message)
        : base(message)
    {
        if (error == C5fsError.None)
        {
            throw new ArgumentOutOfRangeException(nameof(error), "An exception must carry an error.");
        }

        Error = error;
    }

    public C5fsError Error { get; }
}
