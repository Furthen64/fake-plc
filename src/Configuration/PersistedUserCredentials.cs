namespace OpcPlc.Configuration;

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public sealed class PersistedUserCredential
{
    public string Username { get; set; }

    public string PasswordHash { get; set; }

    public string PasswordSalt { get; set; }

    public int PasswordIterations { get; set; } = PersistedUserCredentialStore.DefaultPasswordIterations;

    public string Role { get; set; } = PersistedUserCredentialStore.DefaultRole;
}

public sealed class PersistedUserCredentialCollection
{
    public List<PersistedUserCredential> Users { get; set; } = [];
}

public static class PersistedUserCredentialStore
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

    public static List<PersistedUserCredential> Load(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return [];
        }

        var raw = JsonSerializer.Deserialize<PersistedUserCredentialCollection>(File.ReadAllText(path), s_jsonOptions)
            ?? new PersistedUserCredentialCollection();

        return raw.Users
            .Where(user => user is not null && !string.IsNullOrWhiteSpace(user.Username))
            .Select(Normalize)
            .ToList();
    }

    public static PersistedUserCredential Create(string username, string password, string role)
    {
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new ArgumentException("Username must not be empty.", nameof(username));
        }

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
            Username = username.Trim(),
            PasswordHash = Convert.ToBase64String(hash),
            PasswordSalt = Convert.ToBase64String(salt),
            PasswordIterations = DefaultPasswordIterations,
            Role = NormalizeRole(role)
        };
    }

    public static bool Verify(PersistedUserCredential user, string password)
    {
        if (user is null || string.IsNullOrEmpty(password) ||
            string.IsNullOrWhiteSpace(user.PasswordHash) ||
            string.IsNullOrWhiteSpace(user.PasswordSalt) ||
            user.PasswordIterations <= 0)
        {
            return false;
        }

        var expectedHash = Convert.FromBase64String(user.PasswordHash);
        var salt = Convert.FromBase64String(user.PasswordSalt);
        var actualHash = Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(password),
            salt,
            user.PasswordIterations,
            HashAlgorithmName.SHA256,
            expectedHash.Length);

        return CryptographicOperations.FixedTimeEquals(expectedHash, actualHash);
    }

    public static string NormalizeRole(string role)
    {
        return string.Equals(role, AdminRole, StringComparison.OrdinalIgnoreCase)
            ? AdminRole
            : DefaultRole;
    }

    private static PersistedUserCredential Normalize(PersistedUserCredential user)
    {
        user.Username = user.Username.Trim();
        user.Role = NormalizeRole(user.Role);
        if (user.PasswordIterations <= 0)
        {
            user.PasswordIterations = DefaultPasswordIterations;
        }

        return user;
    }
}
