<#
.SYNOPSIS
    Decrypts an S/MIME envelope (.p7m) using EnvelopedCms in PowerShell 7.

.EXAMPLE
    # Decrypt using a matching certificate from the CurrentUser\My cert store
    .\Decrypt-SMimeMessage.ps1 -InputPath ".\smime.p7m" -OutputPath ".\decrypted.eml"

.EXAMPLE
    # Decrypt using a specific PFX/P12 key file
    .\Decrypt-SMimeMessage.ps1 -InputPath ".\smime.p7m" -OutputPath ".\decrypted.eml" -PfxPath ".\custodian.pfx" -PfxPassword "SecretPass"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutputPath,

    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$PfxPath
)

# Ensure the CMS cryptography library is available
Add-Type -AssemblyName System.Security.Cryptography.Pkcs

try {
    # 1. Read the encrypted S/MIME (.p7m) bytes
    $resolvedInput = (Resolve-Path $InputPath).Path
    $encryptedBytes = [System.IO.File]::ReadAllBytes($resolvedInput)

    # 2. Instantiate and decode the CMS envelope
    $envelopedCms = [System.Security.Cryptography.Pkcs.EnvelopedCms]::new()
    $envelopedCms.Decode($encryptedBytes)

    # 3. Decrypt the envelope
    if ($PfxPath) {
        # Securely prompt for the PFX password
        $PfxPassword = Read-Host -AsSecureString "Enter password for PFX/P12 file '$PfxPath'"
        # Load the private key certificate from the specified PFX/P12
        $certFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            (Resolve-Path $PfxPath).Path,
            $PfxPassword,
            $certFlags
        )

        $certCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
        [void]$certCollection.Add($cert)

        Write-Host "Decrypting with provided certificate: $($cert.Subject)..." -ForegroundColor Cyan
        $envelopedCms.Decrypt($certCollection)
    }
    else {
        # Defaults to searching CurrentUser\My and LocalMachine\My for the matching private key
        Write-Host "Decrypting using certificates in local certificate store..." -ForegroundColor Cyan
        $envelopedCms.Decrypt()
    }

    # 4. Extract decrypted payload
    $decryptedBytes = $envelopedCms.ContentInfo.Content

    # 5. Output to file or console
    if ($OutputPath) {
        $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        [System.IO.File]::WriteAllBytes($resolvedOutput, $decryptedBytes)
        Write-Host "Successfully decrypted $([math]::Round($decryptedBytes.Length / 1KB, 2)) KB to '$resolvedOutput'" -ForegroundColor Green
    }
    else {
        # Return UTF-8 string to pipeline if no output file was specified
        [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    }
}
catch {
    Write-Error "Failed to decrypt S/MIME message: $_"
}