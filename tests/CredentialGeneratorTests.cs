namespace OpcPlc.Tests;

using FakePlc.AddUser;
using FluentAssertions;
using NUnit.Framework;
using System;
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
}
