# Requires -Version 7.0
Describe 'S/MIME Fixture Verification' {

    BeforeAll {
        # Ensure PKCS assembly is loaded
        try {
            Add-Type -AssemblyName System.Security.Cryptography.Pkcs -ErrorAction Stop
        } catch {
            $pkcsDll = Join-Path $PSHOME "System.Security.Cryptography.Pkcs.dll"
            if (Test-Path $pkcsDll) { Add-Type -Path $pkcsDll }
        }

        $testFolder       = $PSScriptRoot
        $keyJsonPath      = Join-Path $testFolder 'key-serials.json'
        $pfxScript        = Join-Path $testFolder 'print-keys-frm-pfx.ps1'
        $recipScript      = Join-Path $testFolder 'print-recip-keys-frm-msg.ps1'
        $fixturePassword  = 'password'

        # Mock Read-Host for any child script invocation
        Mock Read-Host {
            if ($AsSecureString) {
                return (ConvertTo-SecureString -String $fixturePassword -AsPlainText -Force)
            }
            return $fixturePassword
        }
    }

    AfterAll {
        # Optional: clean up artifacts generated during tests
        if (Test-Path $keyJsonPath) {
            Remove-Item -Path $keyJsonPath -Force
        }
    }

    It 'Generates serials JSON from PFX and extracts at least one serial number' {
        $output = & $pfxScript -FolderPath $testFolder -OutputFile $keyJsonPath *>&1 | ForEach-Object { $_.ToString() }
        
        Test-Path $keyJsonPath | Should-Be True
        
        $pfxSerials = @($output | Where-Object { $_ -match 'Serial Number:\s*([0-9a-fA-F]+)' })
        $pfxSerials.Count | Should-BeGreaterThan 0
    }

    It 'Finds matching recipient key from MSG against generated JSON' {
        $output = & $recipScript -FolderPath $testFolder -KeyJsonPath $keyJsonPath *>&1 | ForEach-Object { $_.ToString() }

        $expectedSubstring = 'JSON Match Found'
        $output | Should-Any { $_ -like "*$expectedSubstring*" }
    }
}