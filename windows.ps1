param(
    [ValidateSet("encrypt", "decrypt")]
    [string]$Mode = "encrypt"
)

$ManifestPath = ".git_vault"
$VaultFile = "vault.blob"

function Get-PasswordString {
    $SecurePass = Read-Host "Password" -AsSecureString
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

if ($Mode -eq "encrypt") {
    if (!(Test-Path $ManifestPath)) {
        Write-Host ".git_vault not found"
        exit 1
    }

    $Password = Get-PasswordString

    $ArchiveStream = New-Object System.IO.MemoryStream
    $Writer = New-Object System.IO.BinaryWriter($ArchiveStream)

    # Archive Header
    $Writer.Write([byte[]][Text.Encoding]::ASCII.GetBytes("GVLT"))
    $Writer.Write([int]1)

    $Entries = Get-Content $ManifestPath | Where-Object {
        $_.Trim() -ne "" -and
        -not $_.Trim().StartsWith("#")
    }

    foreach ($Entry in $Entries) {
        if (!(Test-Path $Entry)) {
            Write-Host "Missing: $Entry"
            continue
        }

        if ((Get-Item $Entry) -is [System.IO.DirectoryInfo]) {
            $Files = Get-ChildItem $Entry -File -Recurse
        }
        else {
            $Files = @(Get-Item $Entry)
        }

        foreach ($File in $Files) {
            $RelativePath = Resolve-Path $File.FullName -Relative

            $PathBytes = [Text.Encoding]::UTF8.GetBytes($RelativePath)
            $DataBytes = [IO.File]::ReadAllBytes($File.FullName)

            $Writer.Write([int]$PathBytes.Length)
            $Writer.Write($PathBytes)

            $Writer.Write([long]$DataBytes.Length)
            $Writer.Write($DataBytes)

            Write-Host "Added $RelativePath"
        }
    }

    $Writer.Flush()

    $RawArchive = $ArchiveStream.ToArray()

    Write-Host ""
    Write-Host "Archive Size:" $RawArchive.Length

    # Compress
    $CompressedStream = New-Object System.IO.MemoryStream

    $Gzip = New-Object System.IO.Compression.GZipStream(
        $CompressedStream,
        [IO.Compression.CompressionMode]::Compress
    )

    $Gzip.Write($RawArchive, 0, $RawArchive.Length)
    $Gzip.Close()

    $CompressedBytes = $CompressedStream.ToArray()

    Write-Host "Compressed Size:" $CompressedBytes.Length

    # Salt
    $Salt = New-Object byte[] 16
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $Rng.GetBytes($Salt)

    # Key
    $PBKDF2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password,
        $Salt,
        100000
    )

    $Key = $PBKDF2.GetBytes(32)

    # AES
    $AES = [System.Security.Cryptography.Aes]::Create()
    $AES.Key = $Key
    $AES.GenerateIV()

    $Encryptor = $AES.CreateEncryptor()

    $CipherStream = New-Object System.IO.MemoryStream

    $CryptoStream = New-Object System.Security.Cryptography.CryptoStream(
        $CipherStream,
        $Encryptor,
        [System.Security.Cryptography.CryptoStreamMode]::Write
    )

    $CryptoStream.Write(
        $CompressedBytes,
        0,
        $CompressedBytes.Length
    )

    $CryptoStream.Close()

    $CipherBytes = $CipherStream.ToArray()

    # Vault File
    $Out = New-Object System.IO.MemoryStream
    $BlobWriter = New-Object System.IO.BinaryWriter($Out)

    $BlobWriter.Write([byte[]][Text.Encoding]::ASCII.GetBytes("GVLT"))
    $BlobWriter.Write([int]1)

    $BlobWriter.Write([int]$Salt.Length)
    $BlobWriter.Write($Salt)

    $BlobWriter.Write([int]$AES.IV.Length)
    $BlobWriter.Write($AES.IV)

    $BlobWriter.Write([long]$CipherBytes.Length)
    $BlobWriter.Write($CipherBytes)

    $BlobWriter.Flush()

    [IO.File]::WriteAllBytes(
        $VaultFile,
        $Out.ToArray()
    )

    Write-Host ""
    Write-Host "Vault created: $VaultFile"
}

elseif ($Mode -eq "decrypt") {
    if (!(Test-Path $VaultFile)) {
        Write-Host "vault.blob not found"
        exit 1
    }

    $Password = Get-PasswordString

    $Bytes = [IO.File]::ReadAllBytes($VaultFile)
    Write-Host "Vault Size:" $Bytes.Length

    if ($Bytes.Length -ge 4) {
        Write-Host "Header:" ([Text.Encoding]::ASCII.GetString($Bytes[0..3]))
    }
    
    $Stream = New-Object System.IO.MemoryStream
    $Stream.Write($Bytes, 0, $Bytes.Length)
    $Stream.Position = 0

    $Reader = New-Object System.IO.BinaryReader($Stream)

    $Magic = [Text.Encoding]::ASCII.GetString(
        $Reader.ReadBytes(4)
    )

    if ($Magic -ne "GVLT") {
        Write-Host "Invalid vault"
        exit 1
    }

    $Version = $Reader.ReadInt32()

    $SaltLength = $Reader.ReadInt32()
    $Salt = $Reader.ReadBytes($SaltLength)

    $IvLength = $Reader.ReadInt32()
    $IV = $Reader.ReadBytes($IvLength)

    $CipherLength = $Reader.ReadInt64()
    $CipherBytes = $Reader.ReadBytes($CipherLength)

    $PBKDF2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password,
        $Salt,
        100000
    )

    $Key = $PBKDF2.GetBytes(32)

    $AES = [System.Security.Cryptography.Aes]::Create()
    $AES.Key = $Key
    $AES.IV = $IV

    try {
        $Decryptor = $AES.CreateDecryptor()

        $PlainStream = New-Object System.IO.MemoryStream

        $CryptoStream = New-Object System.Security.Cryptography.CryptoStream(
            $PlainStream,
            $Decryptor,
            [System.Security.Cryptography.CryptoStreamMode]::Write
        )

        $CryptoStream.Write(
            $CipherBytes,
            0,
            $CipherBytes.Length
        )

        $CryptoStream.Close()

        $CompressedBytes = $PlainStream.ToArray()
    }
    catch {
        Write-Host "Wrong password or corrupted vault"
        exit 1
    }

    # Decompress
    $InputStream = New-Object System.IO.MemoryStream
    $InputStream.Write($CompressedBytes, 0, $CompressedBytes.Length)
    $InputStream.Position = 0

    $Gzip = New-Object System.IO.Compression.GZipStream(
        $InputStream,
        [IO.Compression.CompressionMode]::Decompress
    )

    $ArchiveStream = New-Object System.IO.MemoryStream

    $Buffer = New-Object byte[] 4096

    while (($Read = $Gzip.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
        $ArchiveStream.Write($Buffer, 0, $Read)
    }

    $ArchiveBytes = $ArchiveStream.ToArray()
    $ArchiveStreamReader = New-Object System.IO.MemoryStream
    $ArchiveStreamReader.Write($ArchiveBytes, 0, $ArchiveBytes.Length)
    $ArchiveStreamReader.Position = 0

    $ArchiveReader = New-Object System.IO.BinaryReader(
        $ArchiveStreamReader
    )

    $InnerMagic = [Text.Encoding]::ASCII.GetString(
        $ArchiveReader.ReadBytes(4)
    )

    if ($InnerMagic -ne "GVLT") {
        Write-Host "Archive corrupt"
        exit 1
    }

    $InnerVersion = $ArchiveReader.ReadInt32()

    while ($ArchiveReader.BaseStream.Position -lt $ArchiveReader.BaseStream.Length) {
        $PathLength = $ArchiveReader.ReadInt32()

        $Path = [Text.Encoding]::UTF8.GetString(
            $ArchiveReader.ReadBytes($PathLength)
        )

        $FileSize = $ArchiveReader.ReadInt64()

        $Data = $ArchiveReader.ReadBytes($FileSize)

        $Dir = Split-Path $Path -Parent

        if ($Dir -and !(Test-Path $Dir)) {
            New-Item `
                -ItemType Directory `
                -Force `
                -Path $Dir | Out-Null
        }

        [IO.File]::WriteAllBytes($Path, $Data)

        Write-Host "Restored $Path"
    }

    Write-Host ""
    Write-Host "Vault restored"
}