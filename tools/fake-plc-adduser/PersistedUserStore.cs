namespace FakePlc.AddUser;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public sealed class PersistedUserCredential
{
    public string Username { get; set; } = string.Empty;

    public string PasswordHash { get; set; } = string.Empty;

    public string PasswordSalt { get; set; } = string.Empty;

    public int PasswordIterations { get; set; } = PersistedUserStore.DefaultPasswordIterations;

    public string Role { get; set; } = PersistedUserStore.DefaultRole;
}

public sealed class PersistedUserCredentialCollection
{
    public List<PersistedUserCredential> Users { get; set; } = [];
}

public static class PersistedUserStore
{
    public const string DefaultRole = "default";
    public const string AdminRole = "admin";
    public const int DefaultPasswordIterations = 100_000;

    private const int SaltSize = 16;
    private const int HashSize = 32;

    private static readonly JsonSerializerOptions s_jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public static void Upsert(string path, GeneratedCredential credential)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var store = Load(path);
        var normalizedRole = NormalizeRole(credential.Role);
        var hashedCredential = Create(credential.Username, credential.Password, normalizedRole);

        var existing = store.Users.FindIndex(user => string.Equals(user.Username, credential.Username, StringComparison.Ordinal));
        if (existing >= 0)
        {
            store.Users[existing] = hashedCredential;
        }
        else
        {
            store.Users.Add(hashedCredential);
        }

        store.Users = store.Users
            .OrderBy(user => user.Role, StringComparer.Ordinal)
            .ThenBy(user => user.Username, StringComparer.Ordinal)
            .ToList();

        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(path, JsonSerializer.Serialize(store, s_jsonOptions));
    }

    public static PersistedUserCredentialCollection Load(string path)
    {
        if (!File.Exists(path))
        {
            return new PersistedUserCredentialCollection();
        }

        var loaded = JsonSerializer.Deserialize<PersistedUserCredentialCollection>(File.ReadAllText(path), s_jsonOptions);
        if (loaded is null)
        {
            return new PersistedUserCredentialCollection();
        }

        loaded.Users ??= [];
        return loaded;
    }

    private static PersistedUserCredential Create(string username, string password, string role)
    {
        var normalizedUsername = string.IsNullOrWhiteSpace(username)
            ? throw new ArgumentException("Username must not be empty.", nameof(username))
            : username.Trim();

        if (string.IsNullOrEmpty(password))
        {
            throw new ArgumentException("Password must not be empty.", nameof(password));
        }

        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(password),
            salt,
            DefaultPasswordIterations,
            HashAlgorithmName.SHA256,
            HashSize);

        return new PersistedUserCredential
        {
            Username = normalizedUsername,
            PasswordHash = Convert.ToBase64String(hash),
            PasswordSalt = Convert.ToBase64String(salt),
            PasswordIterations = DefaultPasswordIterations,
            Role = role
        };
    }

    private static string NormalizeRole(string role)
    {
        return string.Equals(role, AdminRole, StringComparison.OrdinalIgnoreCase)
            ? AdminRole
            : DefaultRole;
    }
}
