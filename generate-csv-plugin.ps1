# generate-csv-plugin.ps1
# Generate a fake-plc IPluginNodes C# class from a tag CSV export.
#
# Example:
#   .\generate-csv-plugin.ps1 -CsvPath .\togpt.csv
#   .\winbuild.ps1
#   .\winlaunch.ps1
#
# The generated plugin is compiled into the opc-plc assembly and auto-loaded by
# OpcPlcServer.LoadPluginNodes() because it implements IPluginNodes.

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [string]$OutputPath = 'src\PluginNodes\CsvGeneratedPluginNodes.cs',

    [string]$ClassName = 'CsvGeneratedPluginNodes',

    [string]$RootFolder = 'CsvTags',

    [switch]$ReadOnlyValues
)

$ErrorActionPreference = 'Stop'

function Write-Step($message) {
    Write-Host "[STEP] $message" -ForegroundColor Cyan
}

function Write-Ok($message) {
    Write-Host "[OK]   $message" -ForegroundColor Green
}

function Fail($message) {
    throw $message
}

function Escape-CSharpString([string]$value) {
    if ($null -eq $value) {
        return ''
    }

    return $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
}

function Get-CellValue($row, [string]$columnName) {
    $property = $row.PSObject.Properties[$columnName]
    if ($null -eq $property) {
        return ''
    }

    if ($null -eq $property.Value) {
        return ''
    }

    return ([string]$property.Value).Trim()
}

function Get-OpcDataTypeId([string]$dataType) {
    switch -Regex ($dataType.Trim()) {
        '^(Float|Double|Single)$' { return 'DataTypeIds.Double' }
        '^(Integer|Int|Int16|Int32|UInt16|UInt32)$' { return 'DataTypeIds.Int32' }
        '^(Boolean|Bool)$' { return 'DataTypeIds.Boolean' }
        '^(String)$' { return 'DataTypeIds.String' }
        default { return 'DataTypeIds.String' }
    }
}

function Get-CSharpLiteral([string]$dataType, [string]$rawValue) {
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $value = $rawValue.Trim()

    if ([string]::IsNullOrWhiteSpace($value)) {
        switch -Regex ($dataType.Trim()) {
            '^(Float|Double|Single)$' { return '0.0d' }
            '^(Integer|Int|Int16|Int32|UInt16|UInt32)$' { return '0' }
            '^(Boolean|Bool)$' { return 'false' }
            default { return '""' }
        }
    }

    switch -Regex ($dataType.Trim()) {
        '^(Float|Double|Single)$' {
            $parsed = [double]::Parse($value, [System.Globalization.NumberStyles]::Float, $culture)
            return $parsed.ToString('R', $culture) + 'd'
        }
        '^(Integer|Int|Int16|Int32|UInt16|UInt32)$' {
            $parsed = [int]::Parse($value, [System.Globalization.NumberStyles]::Integer, $culture)
            return $parsed.ToString($culture)
        }
        '^(Boolean|Bool)$' {
            if ($value -match '^(1|true|yes|on)$') { return 'true' }
            if ($value -match '^(0|false|no|off)$') { return 'false' }
            Fail "Could not parse Boolean value '$value'."
        }
        default {
            return '"' + (Escape-CSharpString $value) + '"'
        }
    }
}

if ($ClassName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    Fail "ClassName must be a valid C# identifier. Got: $ClassName"
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedCsvPath = Resolve-Path -LiteralPath $CsvPath -ErrorAction Stop
$resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $repoRoot $OutputPath
}

Write-Step "Reading CSV: $resolvedCsvPath"
$pluginRows = Import-Csv -LiteralPath $resolvedCsvPath

$requiredColumns = @(
    'Tag',
    'Value - Data Type',
    'Value - Value',
    'Value - Source',
    'Value - Siemens Address',
    'Value - Siemens Data Type',
    'Value - Siemens String Length',
    'Value - Calculation'
)

if ($pluginRows.Count -eq 0) {
    Fail 'CSV contains no rows.'
}

$availableColumns = $pluginRows[0].PSObject.Properties.Name
foreach ($requiredColumn in $requiredColumns) {
    if ($availableColumns -notcontains $requiredColumn) {
        Fail "CSV is missing required column '$requiredColumn'."
    }
}

$seenTags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$addTagLines = [System.Collections.Generic.List[string]]::new()

$rowNumber = 1
foreach ($row in $pluginRows) {
    $rowNumber++

    $tag = Get-CellValue $row 'Tag'
    if ([string]::IsNullOrWhiteSpace($tag)) {
        continue
    }

    if (-not $seenTags.Add($tag)) {
        Fail "Duplicate tag '$tag' at CSV row $rowNumber."
    }

    $dataType = Get-CellValue $row 'Value - Data Type'
    $value = Get-CellValue $row 'Value - Value'
    $source = Get-CellValue $row 'Value - Source'
    $siemensAddress = Get-CellValue $row 'Value - Siemens Address'
    $siemensDataType = Get-CellValue $row 'Value - Siemens Data Type'
    $calculation = Get-CellValue $row 'Value - Calculation'

    $opcDataType = Get-OpcDataTypeId $dataType
    $literal = Get-CSharpLiteral $dataType $value

    $accessLevel = if ($ReadOnlyValues -or $source -match '^(?i:Calc)$') {
        'AccessLevels.CurrentRead'
    } else {
        'AccessLevels.CurrentReadOrWrite'
    }

    $line = '        AddTag("' +
        (Escape-CSharpString $tag) + '", "' +
        (Escape-CSharpString $dataType) + '", ' +
        $opcDataType + ', ' +
        $literal + ', ' +
        $accessLevel + ', "' +
        (Escape-CSharpString $source) + '", "' +
        (Escape-CSharpString $siemensAddress) + '", "' +
        (Escape-CSharpString $siemensDataType) + '", "' +
        (Escape-CSharpString $calculation) + '");'

    $addTagLines.Add($line)
}

if ($addTagLines.Count -eq 0) {
    Fail 'No valid tag rows found.'
}

$generatedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss UTC')
$escapedRootFolder = Escape-CSharpString $RootFolder

$code = @"
// <auto-generated>
// Generated by generate-csv-plugin.ps1 on $generatedAt.
// Source CSV: $([System.IO.Path]::GetFileName($resolvedCsvPath))
// Rows: $($addTagLines.Count)
// </auto-generated>

namespace OpcPlc.PluginNodes;

using Microsoft.Extensions.Logging;
using Mono.Options;
using Opc.Ua;
using OpcPlc.PluginNodes.Models;
using System;
using System.Collections.Generic;
using System.Linq;

public sealed class $ClassName(TimeService timeService, ILogger logger)
    : PluginNodeBase(timeService, logger), IPluginNodes
{
    private const string RootFolderName = "$escapedRootFolder";

    private PlcNodeManager _plcNodeManager;
    private readonly Dictionary<string, BaseDataVariableState> _nodesByTag = new(StringComparer.OrdinalIgnoreCase);

    public void AddOptions(OptionSet optionSet)
    {
        // CSV-generated tag plugin has no command-line options yet.
    }

    public void AddToAddressSpace(
        FolderState telemetryFolder,
        FolderState methodsFolder,
        PlcNodeManager plcNodeManager)
    {
        _plcNodeManager = plcNodeManager;

        var rootFolder = plcNodeManager.CreateFolder(
            telemetryFolder,
            RootFolderName,
            RootFolderName,
            NamespaceType.OpcPlcApplications);

        var foldersByPath = new Dictionary<string, FolderState>(StringComparer.OrdinalIgnoreCase)
        {
            [RootFolderName] = rootFolder,
        };

        void AddTag(
            string tag,
            string csvDataType,
            NodeId opcDataType,
            object initialValue,
            byte accessLevel,
            string source,
            string siemensAddress,
            string siemensDataType,
            string calculation)
        {
            var parts = tag.Split('.', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0)
            {
                return;
            }

            var parent = rootFolder;
            var folderPath = RootFolderName;

            for (var i = 0; i < parts.Length - 1; i++)
            {
                folderPath = folderPath + "." + parts[i];

                if (!foldersByPath.TryGetValue(folderPath, out var folder))
                {
                    folder = plcNodeManager.CreateFolder(
                        parent,
                        folderPath,
                        parts[i],
                        NamespaceType.OpcPlcApplications);

                    foldersByPath[folderPath] = folder;
                }

                parent = folder;
            }

            var variableName = parts[^1];
            var description = BuildDescription(tag, csvDataType, source, siemensAddress, siemensDataType, calculation);

            var variable = plcNodeManager.CreateBaseVariable(
                parent,
                tag,
                variableName,
                opcDataType,
                ValueRanks.Scalar,
                accessLevel,
                description,
                NamespaceType.OpcPlcApplications,
                initialValue);

            _nodesByTag[tag] = variable;
        }

$($addTagLines -join [Environment]::NewLine)

        Nodes = _nodesByTag.Values
            .Select(node => PluginNodesHelper.GetNodeWithIntervals(node.NodeId, plcNodeManager))
            .ToList();
    }

    public void StartSimulation()
    {
        // This generated plugin is a static tag namespace.
        // Add a timer here later if you want generated values or calculated tags.
    }

    public void StopSimulation()
    {
    }

    private static string BuildDescription(
        string tag,
        string csvDataType,
        string source,
        string siemensAddress,
        string siemensDataType,
        string calculation)
    {
        var parts = new List<string>
        {
            $"CSV tag: {tag}",
            $"CSV data type: {csvDataType}",
            $"Source: {source}",
        };

        if (!string.IsNullOrWhiteSpace(siemensAddress))
        {
            parts.Add($"Siemens address: {siemensAddress}");
        }

        if (!string.IsNullOrWhiteSpace(siemensDataType))
        {
            parts.Add($"Siemens data type: {siemensDataType}");
        }

        if (!string.IsNullOrWhiteSpace(calculation))
        {
            parts.Add($"Calculation: {calculation}");
        }

        return string.Join("; ", parts);
    }
}
"@

$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Write-Step "Writing generated plugin: $resolvedOutputPath"
Set-Content -LiteralPath $resolvedOutputPath -Value $code -Encoding UTF8

Write-Ok "Generated $($addTagLines.Count) tags into $resolvedOutputPath"
Write-Ok "Next: .\winbuild.ps1"
