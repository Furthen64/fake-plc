namespace FakePlc.AddUser;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public static class Program
{
    private static readonly JsonSerializerOptions s_jsonOptions = new()
    {
        WriteIndented = true
    };

    public static int Main(string[] args)
    {
        try
        {
            var options = CliOptions.Parse(args);
            if (options.ShowHelp)
            {
                CliOptions.WriteHelp();
                return 0;
            }

            var credential = CredentialGenerator.Generate(options.Username, options.Password, options.Admin, options.PasswordLength);
            if (!string.IsNullOrWhiteSpace(options.StorePath))
            {
                PersistedUserStore.Upsert(options.StorePath, credential);
            }

            if (options.Json)
            {
                Console.WriteLine(JsonSerializer.Serialize(credential, s_jsonOptions));
                return 0;
            }

            Console.WriteLine("fake-plc credentials");
            Console.WriteLine($"Role: {credential.Role}");
            Console.WriteLine($"Username: {credential.Username}");
            Console.WriteLine($"Password: {credential.Password}");
            if (!string.IsNullOrWhiteSpace(options.StorePath))
            {
                Console.WriteLine($"Store: {options.StorePath}");
            }
            Console.WriteLine();
            Console.WriteLine("Status:");
            Console.WriteLine("  Persisted user saved successfully.");
            if (!string.IsNullOrWhiteSpace(options.StorePath))
            {
                Console.WriteLine("  .\\winlaunch.ps1 will load this store automatically.");
            }
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }
}

public static class CredentialGenerator
{
    private const string PasswordAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%*-_";
    private const int MinPasswordLength = 12;
    private const int SuffixLength = 8;

    public static GeneratedCredential Generate(string? username = null, string? password = null, bool admin = false, int passwordLength = 20)
    {
        if (password is null && passwordLength < MinPasswordLength)
        {
            throw new ArgumentOutOfRangeException(nameof(passwordLength), passwordLength,
                $"Password length must be at least {MinPasswordLength} characters.");
        }

        var resolvedUsername = string.IsNullOrWhiteSpace(username)
            ? $"{(admin ? "admin" : "user")}-{CreateRandomString(SuffixLength, "abcdefghijklmnopqrstuvwxyz0123456789")}"
            : username.Trim();

        return new GeneratedCredential(
            resolvedUsername,
            password ?? CreateRandomString(passwordLength, PasswordAlphabet),
            admin ? "--au" : "--du",
            admin ? "--ac" : "--dc",
            admin ? "admin" : "default");
    }

    private static string CreateRandomString(int length, string alphabet)
    {
        var builder = new StringBuilder(length);
        for (var i = 0; i < length; i++)
        {
            builder.Append(alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)]);
        }
        return builder.ToString();
    }
}

public readonly record struct GeneratedCredential(
    string Username,
    string Password,
    string UserArgument,
    string PasswordArgument,
    string Role)
{
    public string ToCliArgumentString()
    {
        return $"{UserArgument}={Quote(Username)} {PasswordArgument}={Quote(Password)}";
    }

    private static string Quote(string value)
    {
        return $"\"{value.Replace("\"", "\\\"", StringComparison.Ordinal)}\"";
    }
}

internal sealed record CliOptions(string? Username, string? Password, bool Admin, int PasswordLength, bool Json, bool ShowHelp, string? StorePath)
{
    public static CliOptions Parse(string[] args)
    {
        string? username = null;
        string? password = null;
        var admin = false;
        var passwordLength = 20;
        var json = false;
        var showHelp = false;
        string? storePath = null;

        foreach (var arg in args)
        {
            if (arg.Equals("--help", StringComparison.OrdinalIgnoreCase) ||
                arg.Equals("-h", StringComparison.OrdinalIgnoreCase))
            {
                showHelp = true;
                continue;
            }

            if (arg.Equals("--admin", StringComparison.OrdinalIgnoreCase) ||
                arg.Equals("--role=admin", StringComparison.OrdinalIgnoreCase))
            {
                admin = true;
                continue;
            }

            if (arg.Equals("--role=default", StringComparison.OrdinalIgnoreCase))
            {
                admin = false;
                continue;
            }

            if (arg.Equals("--json", StringComparison.OrdinalIgnoreCase))
            {
                json = true;
                continue;
            }

            if (arg.StartsWith("--username=", StringComparison.OrdinalIgnoreCase))
            {
                username = arg["--username=".Length..];
                continue;
            }

            if (arg.StartsWith("--password=", StringComparison.OrdinalIgnoreCase))
            {
                password = arg["--password=".Length..];
                continue;
            }

            if (arg.StartsWith("--password-length=", StringComparison.OrdinalIgnoreCase))
            {
                if (!int.TryParse(arg["--password-length=".Length..], out passwordLength))
                {
                    throw new ArgumentException("The --password-length value must be an integer.", nameof(args));
                }
                continue;
            }

            if (arg.StartsWith("--store=", StringComparison.OrdinalIgnoreCase))
            {
                storePath = arg["--store=".Length..];
                continue;
            }

            throw new ArgumentException($"Unknown argument '{arg}'.", nameof(args));
        }

        return new CliOptions(username, password, admin, passwordLength, json, showHelp, storePath);
    }

    public static void WriteHelp()
    {
        Console.WriteLine("fake-plc-adduser");
        Console.WriteLine("Generates username/password pairs for fake-plc startup arguments.");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --username=<name>         Optional explicit username.");
        Console.WriteLine("  --password=<value>        Optional explicit password.");
        Console.WriteLine("  --admin                   Generate admin credentials.");
        Console.WriteLine("  --role=default|admin      Select credential role.");
        Console.WriteLine("  --password-length=<n>     Generated password length, minimum 12. Default: 20.");
        Console.WriteLine("  --store=<path>            Save credentials to a persisted user store.");
        Console.WriteLine("  --json                    Emit JSON output.");
        Console.WriteLine("  --help                    Show help.");
    }
}
