# print-keys

> [!NOTE]
> These scripts were originally written for use in the US Department of War (DoW) Public Key Infrastructure (PKI) environment, but should work for any PKI using PKCS#12 certificates.

---

> [!WARNING]
> This is intended for use in troubleshooting exceptions in eDiscovery tools, and may not be suitable for the actual production of records.

## Purpose

For use in email decryption during eDiscovery.

When you obtain keys from your certificate authority (CA) key escrow, use these scripts to dump certificate metadata and verify them against your case.

When reviewing validity dates:

- `Not Before`: Start date / valid from
- `Not After`: Expiration date / valid to

When you get `Failed to decrypt` exceptions in EnCase IA, there are 3 possible causes:

1. You are missing the private key for the custodian.
2. The evidence is corrupt.
3. You have a valid key, but EnCase choked on the record. In this case, you can use `print-recip-keys-frm-msg.ps1` to verify that your CA provided you with the correct key for the recipient.

In the first case, you will see the following:

```powershell
=== Processing: E:\p7m\smime.p7m ===
No JSON Match Found:       No match found in <KeyJsonPath>
```

In the second case, you will see the following:

```powershell
=== Processing: E:\p7m\smime.p7m ===
Error parsing smime.p7m: Exception calling "Decode" with "1" argument(s): "ASN1 corrupted data."
```

In the third case, you will see the following for *at least one recipient*:

```powershell
=== Processing: E:\p7m\smime.p7m ===
Total Recipients: 1

  [Recipient #1]
  Type:                   KeyTransport
  ... (other recipient info)
  Local Match Found:      CN=test@example.com (Has Private Key: True)
```

## Requirements

- PowerShell Core 7+
- Pester v6+ (for testing)

---

## Usage

### 1. Extract Key Metadata from PFX/P12 (`print-keys-frm-pfx.ps1`)

Scans a directory for PKCS#12 (`.pfx` / `.p12`) files, displays certificate properties (Subject, Issuer, Validity Dates, Thumbprint, Public Key), and exports the collected records to a JSON file.

```powershell
.\print-keys-frm-pfx.ps1 -FolderPath <Folder Containing pfx/p12 keys> [-OutputFile <output-path.json>]
```

**Parameters:**

- `-FolderPath` *(Mandatory)*: Directory containing `.pfx` or `.p12` files.
- `-OutputFile` *(Optional)*: Output JSON file path. Defaults to `key-serials.json`.

**Examples:**

```powershell
# Default output to key-serials.json
.\print-keys-frm-pfx.ps1 -FolderPath "C:\Certs"

# Custom output path
.\print-keys-frm-pfx.ps1 -FolderPath "C:\Certs" -OutputFile "custom-output.json"
```

You will be prompted for the password for each file. Fault-tolerant error handling ensures one bad file does not stop execution.

---

### 2. Inspect S/MIME Messages for Required Recipient Keys (`print-recip-keys-frm-msg.ps1`)

Scans a folder of S/MIME PKCS#7 encrypted files (`.p7m`), reads the `EnvelopedCms` envelope, and displays recipient identifiers (Issuer/Serial Number or SKI) and encryption algorithms needed for decryption. It checks the local certificate store for matching private keys and can also compare recipients against a JSON file produced by `print-keys-frm-pfx.ps1`.

#### Workflow for Failed-to-Decrypt Exceptions

1. Open the exception `.lef` in EnCase EI.
2. Drill down to the email attachment `smime.p7m`.
3. Export the file using the artifact menu.
4. Run `print-recip-keys-frm-msg.ps1` against the exported folder.

**Parameters:**

- `-FolderPath` *(Mandatory)*: Directory containing `.p7m` files.
- `-KeyJsonPath` *(Optional)*: Path to a JSON file exported from `print-keys-frm-pfx.ps1`. If provided, it will automatically match recipient serial numbers against the key list.

**Examples:**

```powershell
# Inspect .p7m recipient requirements and check local cert store
.\print-recip-keys-frm-msg.ps1 -FolderPath "O:\mycase\export"

# Inspect and cross-reference with exported PFX keys
.\print-recip-keys-frm-msg.ps1 -FolderPath "O:\mycase\export" -KeyJsonPath ".\key-serials.json"
```

---

## Manually Decrypting S/MIME Messages

You can use the `Decrypt-SMimeMessage.ps1` script to decrypt a single S/MIME message using a PFX/P12 file. This is useful for testing or verifying that you have the correct key.

---

## Testing

### Upgrade Pester to v6

This repository uses the `Pester` PowerShell testing framework. The built-in version in Windows PowerShell is `3.4.0`; upgrade manually to v6.

In an admin session:

```PowerShell
Install-Module -Name Pester -Force

# Robocopy to the same path as v3
Get-Module -Name Pester -ListAvailable
robocopy /e /move "C:\Users\<USERNAME>\Documents\PowerShell\Modules\Pester" "C:\Program Files\WindowsPowerShell\Modules\Pester\"

# Import
Import-Module Pester -PassThru
```

Run tests from a standard PowerShell session:

```PowerShell
Invoke-Pester
```

For VS Code, I recommend installing the `pspester.pester-test` extension. It will allow you to run tests from the editor using the integrated test explorer.

## Deep Dive Explanation

Encrypted emails are composed of the following:

- **Outer Message**: The email itself, which contains the encrypted attachment. The header is in plaintext and the body is empty.
- **Encrypted Attachment**: The S/MIME PKCS#7 file (`.p7m`) that contains the encrypted content.

There are multiple keys involved in the encryption process:

1. The sender's email client generates a random symmetric key (session key) to encrypt the email content.
2. The session key is then encrypted with the recipient's public key (from their certificate)
3. The encrypted session key is stored in the `.p7m` file along with the encrypted content.
4. When the recipient receives the email, their email client uses their private key to decrypt the session key, which is then used to decrypt the email content.

> [!NOTE]
> There will be as many asymmetric keys identified by the `.p7m` file as there are recipients. Each recipient has their own encrypted session key, which is why the `print-recip-keys-frm-msg.ps1` script can list multiple recipients and their corresponding identifiers.

---

> [!NOTE]
> Recipients are not identified by their certificate's subject name, but rather by the certificate's Issuer and Serial Number or Subject Key Identifier (SKI). This is because the `.p7m` file does not contain the recipient's certificate, only the encrypted session key and the identifiers needed to locate the correct private key for decryption.

### **Also consider the following complications**

1. **Custodian certificate history.** A custodian may have held multiple encryption certificates during the case timeframe. The tool should not assume that the custodian’s currently available certificate is the certificate used to encrypt a particular message or attachment.
2. **Certificate replacement before expiration.** A custodian may receive a replacement certificate before an existing certificate expires—for example, after loss or replacement of a Common Access Card (CAC). The replacement certificate will normally have a different serial number and may have a different key pair.  
   An encrypted CMS/S/MIME object, such as a `.p7m` file, contains recipient information that protects the content-encryption key for one or more intended recipient certificates. To decrypt the object, the analyst must have the private key corresponding to an eligible recipient certificate identified in that object. A replacement certificate generally cannot decrypt content encrypted to the prior certificate.
3. **Recursive encryption in nested email structures.** Email is a nested data structure. An outer message can contain multiple attachments; an attachment may itself be an email message with additional attachments; and any level of that hierarchy may contain encrypted content. The tool should inspect and process each message and attachment recursively.  
   Each encrypted object must be evaluated independently, and decryption requires private-key material corresponding to a recipient certificate for that specific encryption layer. For example, a custodian may forward an encrypted email as an attachment rather than forwarding its contents inline. The attached message remains encrypted to its original recipients and is not automatically re-encrypted for the new recipient. If the new recipient was not an original recipient, that person will be unable to decrypt the attached message. Analysts may need to trace the attached message to an original recipient and obtain authorized access to the applicable private key or approved key-recovery material.
4. **Certificate serial numbers are not globally unique.** A certificate serial number is unique only within the issuing Certificate Authority (CA) context; it is not a universal identifier. The Department of War (DoW) Public Key Infrastructure (PKI) includes multiple CAs and CA lifecycle changes, including retired and newly established CAs. Although unlikely, two certificates issued by different CAs could have the same serial number.  
   If a certificate that you think should work fails, do not use a serial number alone to identify a certificate. At minimum, identify certificates by issuer/CA identity and serial number. When available, retain and compare the full certificate, its SHA-256 fingerprint, and/or its Subject Key Identifier (SKI) to avoid ambiguity.
