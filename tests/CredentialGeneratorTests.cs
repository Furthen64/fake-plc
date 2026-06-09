namespace OpcPlc.Tests;

using FakePlc.AddUser;
using FluentAssertions;
using NUnit.Framework;
using System;
using System.IO;
using System.Linq;

[TestFixture]
public class CredentialGeneratorTests
{
    [Test]
    public void Generate_ReturnsDefaultUserArguments_ForStandardUser()
    {
        var credential = CredentialGenerator.Generate();

        credential.Role.Should().Be("default");
        credential.Username.Should().StartWith("user-");
        credential.UserArgument.Should().Be("--du");
        credential.PasswordArgument.Should().Be("--dc");
        credential.Password.Length.Should().Be(20);
    }

    [Test]
    public void Generate_ReturnsAdminArguments_ForAdminUser()
    {
        var credential = CredentialGenerator.Generate(admin: true);

        credential.Role.Should().Be("admin");
        credential.Username.Should().StartWith("admin-");
        credential.UserArgument.Should().Be("--au");
        credential.PasswordArgument.Should().Be("--ac");
    }

    [Test]
    public void Generate_UsesExplicitUsername_WhenProvided()
    {
        var credential = CredentialGenerator.Generate("custom-user", passwordLength: 24);

        credential.Username.Should().Be("custom-user");
        credential.Password.Length.Should().Be(24);
    }

    [Test]
    public void Generate_UsesExplicitPassword_WhenProvided()
    {
        var credential = CredentialGenerator.Generate("custom-user", "changeme", passwordLength: 24);

        credential.Username.Should().Be("custom-user");
        credential.Password.Should().Be("changeme");
    }

    [Test]
    public void Generate_AllowsShortExplicitPassword()
    {
        var credential = CredentialGenerator.Generate(password: "short");

        credential.Password.Should().Be("short");
    }

    [Test]
    public void Generate_RejectsShortPasswords()
    {
        Action act = () => CredentialGenerator.Generate(passwordLength: 11);

        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Test]
    public void ToCliArgumentString_QuotesBothValues()
    {
        var credential = new GeneratedCredential("user one", "P@ss word", "--du", "--dc", "default");

        credential.ToCliArgumentString().Should().Be("--du=\"user one\" --dc=\"P@ss word\"");
    }

    [Test]
    public void Generate_UsesSupportedPasswordAlphabet()
    {
        var credential = CredentialGenerator.Generate(passwordLength: 64);
        const string supportedAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%*-_";

        credential.Password.All(supportedAlphabet.Contains).Should().BeTrue();
    }

    [Test]
    public void PersistedUserStore_Upsert_WritesHashedCredential()
    {
        var credential = CredentialGenerator.Generate("operator1", "pass1");
        var tempPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.json");

        try
        {
            PersistedUserStore.Upsert(tempPath, credential);

            var stored = PersistedUserStore.Load(tempPath);

            stored.Should().NotBeNull();
            stored.Users.Should().ContainSingle();
            stored.Users[0].Username.Should().Be("operator1");
            stored.Users[0].Role.Should().Be("default");
            stored.Users[0].PasswordHash.Should().NotBe("pass1");
            stored.Users[0].PasswordSalt.Should().NotBeNullOrEmpty();
        }
        finally
        {
            File.Delete(tempPath);
        }
    }

    [Test]
    public void PersistedUserStore_Upsert_ReplacesExistingUser()
    {
        var tempPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.json");

        try
        {
            PersistedUserStore.Upsert(tempPath, CredentialGenerator.Generate("operator1", "pass1"));
            PersistedUserStore.Upsert(tempPath, CredentialGenerator.Generate("operator1", "pass2", admin: true));

            var stored = PersistedUserStore.Load(tempPath);

            stored.Should().NotBeNull();
            stored.Users.Should().ContainSingle();
            stored.Users[0].Role.Should().Be("admin");
        }
        finally
        {
            File.Delete(tempPath);
        }
    }
}
