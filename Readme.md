# GitVault

Store private development files inside a public Git repository using a single encrypted vault file.

## Overview

GitVault allows developers to keep sensitive or machine-specific files alongside a project without requiring:

- Private repositories
- Cloud drives
- USB transfers
- Additional synchronization services

Selected files are collected, compressed, encrypted, and stored inside a single file:

```text
vault.blob
```

The encrypted vault can be safely committed to a public repository.

Without the correct password, the contents cannot be restored.

---

# Motivation

Many projects contain files that should not be visible publicly but are still important for development:

```text
.env
database.db
secrets/
logs/
local_config.json
test_data/
```

Normally these files are:

- Ignored by Git
- Stored manually
- Forgotten on another machine
- Lost after system reinstalls

GitVault keeps those files inside the repository in encrypted form.

---

# Project Structure

Example:

```text
MyProject/
│
├─ src/
├─ docs/
├─ README.md
│
├─ .git_vault
├─ vault.blob
│
└─ git_vault/
   └─ windows.ps1
```

---

# Manifest File

GitVault uses a manifest file named:

```text
.git_vault
```

Example:

```text
# Environment

.env

# Database

database.db

# Directories

secrets/
logs/
```

Blank lines and comments are ignored.

---

# Encryption Workflow

Run:

```powershell
.\git_vault\windows.ps1 encrypt
```

GitVault will:

1. Read `.git_vault`
2. Collect all listed files
3. Recursively collect directory contents
4. Create an archive
5. Compress archive
6. Ask for a password
7. Encrypt the compressed data
8. Create `vault.blob`

Result:

```text
vault.blob
```

can be committed and pushed normally.

---

# Decryption Workflow

Run:

```powershell
.\git_vault\windows.ps1 decrypt
```

GitVault will:

1. Ask for password
2. Read `vault.blob`
3. Decrypt data
4. Decompress archive
5. Restore original files

---

# Example Usage

Machine A:

```bash
git pull

.\git_vault\windows.ps1 decrypt

# work

.\git_vault\windows.ps1 encrypt

git add .
git commit -m "update"
git push
```

Machine B:

```bash
git pull

.\git_vault\windows.ps1 decrypt

# continue working
```

---

# Vault Format

Current format:

```text
FILES
  ↓
CUSTOM ARCHIVE
  ↓
GZIP
  ↓
AES ENCRYPTION
  ↓
vault.blob
```

Restoration:

```text
vault.blob
  ↓
AES DECRYPTION
  ↓
GZIP DECOMPRESSION
  ↓
FILE RESTORATION
```

---

# Archive Format

Each file is stored with:

```text
Path Length
Path
File Size
File Data
```

Example:

```text
.env
secrets/api.txt
database.db
```

Only relative paths are stored.

Absolute paths are never written into the vault.

---

# Root Detection

GitVault treats the directory containing:

```text
.git_vault
```

as the project root.

This allows commands to run from anywhere inside the project tree.

Example:

```text
Project/
├─ .git_vault
└─ src/
   └─ service/
```

Command:

```powershell
..\..\git_vault\windows.ps1 encrypt
```

still operates on the project root.

---

# Security

GitVault stores:

```text
vault.blob
```

inside Git.

GitVault never stores:

```text
passwords
decryption keys
plaintext files
```

inside the repository.

Only users with the correct password can restore vault contents.

---

# Limitations

## Binary Vaults

`vault.blob` is a binary file.

Git cannot automatically merge encrypted vault contents.

If multiple developers modify the same vault simultaneously, conflicts must be resolved manually.

---

## Intended Usage

GitVault is primarily designed for:

- Solo developers
- Multiple development machines
- Personal projects
- Development assets
- Public repositories containing private development files

---

# Future Features

## Planned

- Linux support
- macOS support
- Status command
- Automatic root detection
- Empty directory preservation
- Selective extraction
- Vault metadata
- Vault versioning
