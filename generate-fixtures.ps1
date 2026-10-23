# Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration
$RecipientEmail = "test@example.com"
$SenderEmail    = "sender@example.com"
$PfxPassword    = "password"
$WorkingDir     = Get-Location

$PfxPath = Join-Path -Path $WorkingDir -ChildPath "certificate.pfx"
$EmlPath = Join-Path -Path $WorkingDir -ChildPath "message.eml"
$P7mPath = Join-Path -Path $WorkingDir -ChildPath "smime.p7m"

Write-Host "==> 1. Generating self-signed S/MIME certificate and PFX..."

# Secure Email (S/MIME) EKU: 1.3.6.1.5.5.7.3.4
# EKU extension OID: 2.5.29.37
# SAN extension OID: 2.5.29.17
$cert = New-SelfSignedCertificate `
    -Subject "CN=$RecipientEmail" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyUsage KeyEncipherment, DataEncipherment `
    -TextExtension @(
        "2.5.29.37={text}1.3.6.1.5.5.7.3.4",
        "2.5.29.17={text}email=$RecipientEmail"
    ) `
    -NotAfter (Get-Date).AddYears(1)

# Export certificate and private key to PFX
$secPassword = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $secPassword | Out-Null

Write-Host "==> 2. Creating test RFC 5322 .eml file..."
$rfcDate = (Get-Date).ToUniversalTime().ToString("r")
$emlContent = @"
From: $SenderEmail
To: $RecipientEmail
Subject: Test S/MIME Message
Date: $rfcDate
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

This is a synthetic email body generated for S/MIME test fixture validation.
"@

[System.IO.File]::WriteAllText($EmlPath, $emlContent, [System.Text.Encoding]::UTF8)

Write-Host "==> 3. Encrypting email to smime.p7m..."

# Load PKCS assembly across PowerShell 7 and Windows PowerShell
try {
    Add-Type -AssemblyName System.Security.Cryptography.Pkcs -ErrorAction Stop
} catch {
    $pkcsDll = Join-Path $PSHOME "System.Security.Cryptography.Pkcs.dll"
    if (Test-Path $pkcsDll) {
        Add-Type -Path $pkcsDll
    } else {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
    }
}

$emlBytes = [System.IO.File]::ReadAllBytes($EmlPath)
$contentInfo = [System.Security.Cryptography.Pkcs.ContentInfo]::new($emlBytes)

# Use AES-256 for the enveloped content encryption
$aesOid = [System.Security.Cryptography.Oid]::new("2.16.840.1.101.3.4.1.42") # AES-256-CBC
$algoIdentifier = [System.Security.Cryptography.Pkcs.AlgorithmIdentifier]::new($aesOid)
$envelopedCms = [System.Security.Cryptography.Pkcs.EnvelopedCms]::new($contentInfo, $algoIdentifier)

# Encrypt with recipient certificate
$recipient = [System.Security.Cryptography.Pkcs.CmsRecipient]::new($cert)
$envelopedCms.Encrypt($recipient)

# Output DER-encoded PKCS#7 envelope
$p7mBytes = $envelopedCms.Encode()
[System.IO.File]::WriteAllBytes($P7mPath, $p7mBytes)

Write-Host "==> Finished! Generated certificate.pfx, message.eml, and smime.p7m."