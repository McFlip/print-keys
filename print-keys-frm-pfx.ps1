<#
.SYNOPSIS
    Iterates over all PFX/P12 files in a folder and displays their certificate properties.

.DESCRIPTION
    This script scans a specified folder for PKCS#12 (.pfx / .p12) files.
    For each file found, it prompts for the password, loads the certificate,
    displays key properties such as subject, issuer, validity dates,
    thumbprint, and public key information, and exports the collected
    information to a JSON file.
    Handles errors gracefully so one bad file does not stop processing.

.PARAMETER FolderPath
    The path to the folder containing .pfx or .p12 files.
    This parameter is mandatory.

.PARAMETER OutputFile
    The path or filename for the output JSON file.
    Defaults to 'key-serials.json'.

.EXAMPLE
    .\print-keys-frm-pfx.ps1 -FolderPath "C:\Certs"

    Prompts for each file's password, displays certificate details, and writes to 'key-serials.json'.

.EXAMPLE
    .\print-keys-frm-pfx.ps1 -FolderPath "C:\Certs" -OutputFile "custom-output.json"

.NOTES
    Requires: PowerShell 5.1+ or PowerShell Core 7+
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$FolderPath,

    [Parameter(Position = 1)]
    [string]$OutputFile = 'key-serials.json'
)

# Get all .pfx and .p12 files in the folder (non-recursive; use -Recurse if needed)
$pfxFiles = @(Get-ChildItem -Path $FolderPath -Filter *.pfx -File)
$pfxFiles += @(Get-ChildItem -Path $FolderPath -Filter *.p12 -File)

if (-not $pfxFiles) {
    Write-Host "No PFX/P12 files found in $FolderPath" -ForegroundColor Yellow
    return
}

$certRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($file in $pfxFiles) {
    Write-Host "`n=== Processing: $($file.FullName) ===" -ForegroundColor Cyan
    
    # Prompt for password for this specific file
    $pfxPassword = Read-Host -AsSecureString "Enter password for $($file.Name)"
    
    try {
        $cert = Get-PfxCertificate -FilePath $file.FullName -Password $pfxPassword

        if (-not $cert) {
            Write-Host "No certificate found in file." -ForegroundColor Yellow
            continue
        }

        # Display key properties
        Write-Host "Subject:        $($cert.Subject)"
        Write-Host "Issuer:         $($cert.Issuer)"
        Write-Host "Thumbprint:     $($cert.Thumbprint)"
        Write-Host "Serial Number:  $($cert.SerialNumber)"
        Write-Host "Not Before:     $($cert.NotBefore)"
        Write-Host "Not After:      $($cert.NotAfter)"
        Write-Host "Has Private Key: $($cert.HasPrivateKey)"
        Write-Host "Signature Algorithm: $($cert.SignatureAlgorithm.FriendlyName)"
        Write-Host "Public Key:     $($cert.PublicKey.Oid.FriendlyName)"

        $extensions = @()
        # Optional: list extensions
        foreach ($ext in $cert.Extensions) {
            Write-Host "  Extension: $($ext.Oid.FriendlyName) - $($ext.Format(0))"
            $extensions += [PSCustomObject]@{
                OidFriendlyName = $ext.Oid.FriendlyName
                OidValue        = $ext.Oid.Value
                Value           = $ext.Format(0)
            }
        }

        # Collect record for JSON output
        $certRecords.Add([PSCustomObject]@{
            FileName           = $file.Name
            FilePath           = $file.FullName
            Subject            = $cert.Subject
            Issuer             = $cert.Issuer
            Thumbprint         = $cert.Thumbprint
            SerialNumber       = $cert.SerialNumber
            NotBefore          = $cert.NotBefore
            NotAfter           = $cert.NotAfter
            HasPrivateKey      = $cert.HasPrivateKey
            SignatureAlgorithm = $cert.SignatureAlgorithm.FriendlyName
            PublicKeyAlgorithm = $cert.PublicKey.Oid.FriendlyName
            Extensions         = $extensions
        })
    }
    catch {
        Write-Host "Error reading $($file.Name): $_" -ForegroundColor Red
    }
}

if ($certRecords.Count -gt 0) {
    $certRecords | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "`nExported $($certRecords.Count) certificate record(s) to $OutputFile" -ForegroundColor Green
}
else {
    Write-Host "`nNo certificate records to export." -ForegroundColor Yellow
}

