<#
sata-read-sector.ps1: Read one sector from SATA drive

Usage: ./sata-read-sector.ps1 drive_no [lba]

    @arg[in]    drive_no    physical drive no to access (MANDATORY)
    @arg[in]    lba         Logical Block Address (LBA) to be read (option, default is zero)

    @note LBA should be less than 24bit.

Copyright (c) 2024 Kenichiro Yoshii
Copyright (c) 2024 Hagiwara Solutions Co., Ltd.
#>
Param(
    [parameter(mandatory)][Int]$_drive_no,
    [Int]$_lba = 0
    )

$KernelService = Add-Type -Name 'Kernel32' -Namespace 'Win32' -PassThru -MemberDefinition @"
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr CreateFile(
        String lpFileName,
        UInt32 dwDesiredAccess,
        UInt32 dwShareMode,
        IntPtr lpSecurityAttributes,
        UInt32 dwCreationDisposition,
        UInt32 dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("Kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(
        IntPtr  hDevice,
        int     oControlCode,
        IntPtr  InBuffer,
        int     nInBufferSize,
        IntPtr  OutBuffer,
        int     nOutBufferSize,
        ref int pBytesReturned,
        IntPtr  Overlapped);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
"@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, Pack=1)]
public struct stATAPassThroughEx {
    public UInt16 Length;
    public UInt16 AtaFlags;
    public Byte  PathId;
    public Byte  TargetId;
    public Byte  Lun;
    public Byte  ReservedAsUchar;
    public UInt32 DataTransferLength;
    public UInt32 TimeOutValue;
    public UInt32 ReservedAsUlong;
    public UInt32 ReservedAsUlong2;
    public UInt64 DataBufferOffset;
    public Byte  PrevTF0;
    public Byte  PrevTF1;
    public Byte  PrevTF2;
    public Byte  PrevTF3;
    public Byte  PrevTF4;
    public Byte  PrevTF5;
    public Byte  PrevTF6;
    public Byte  PrevTF7;
    public Byte  CurrTF0;
    public Byte  CurrTF1;
    public Byte  CurrTF2;
    public Byte  CurrTF3;
    public Byte  CurrTF4;
    public Byte  CurrTF5;
    public Byte  CurrTF6;
    public Byte  CurrTF7;

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 512)]
    public Byte[] ucDataBuf;
}
"@

$AccessMask = "3221225472"; # = 0xC00000000 = GENERIC_READ (0x80000000) | GENERIC_WRITE (0x40000000)
$AccessMode = 3; # FILE_SHARE_READ | FILE_SHARE_WRITE
$AccessEx   = 3; # OPEN_EXISTING
$AccessAttr = 0x40; # FILE_ATTRIBUTE_DEVICE

$DeviceHandle = $KernelService::CreateFile("\\.\PhysicalDrive$_drive_no", [System.Convert]::ToUInt32($AccessMask), $AccessMode, [System.IntPtr]::Zero, $AccessEx, $AccessAttr, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error()
if ($DeviceHandle -eq [System.IntPtr]::Zero) {
    Write-Host "`n[E] CreateFile failed: $LastError";
    Return;
}

# sizeof( stATAPassThroughEx ) = 48 + 512 = 560
$OutBufferSize = 560;
$OutBuffer     = [System.Runtime.InteropServices.Marshal]::AllocCoTaskMem( $OutBufferSize );

$CMDDescriptor = New-Object stATAPassThroughEx;
$CMDDescSize   = [System.Runtime.InteropServices.Marshal]::SizeOf( $CMDDescriptor );

if ( $CMDDescSize -ne $OutBufferSize ) {
    Write-Host "`n[E] Size of structure is $CMDDescSize bytes, expect 560 bytes, stop";
    [void]$KernelService::CloseHandle($DeviceHandle);
    Return;
}

$lba_l = (   ( $_lba + 1 )           -band 0xFF );
$lba_m = ( ( ( $_lba + 1 ) -shr  8 ) -band 0xFF );
$lba_h = ( ( ( $_lba + 1 ) -shr 16 ) -band 0xFF );
$CMDDescriptor.Length = 48;
$CMDDescriptor.AtaFlags = 1 + 2; # ATA_FLAGS_DRDY_REQUIRED | ATA_FLAGS_DATA_IN
$CMDDescriptor.PathId = 0;
$CMDDescriptor.TargetId = 0;
$CMDDescriptor.Lun = 0;
$CMDDescriptor.DataTransferLength = 512; # one sector
$CMDDescriptor.TimeOutValue = 5;
$CMDDescriptor.DataBufferOffset = 48; # offsetof( stATAPassThroughEx, ucDataBuf )
$CMDDescriptor.CurrTF0 = 0; # Features
$CMDDescriptor.CurrTF1 = 1; # Counts
$CMDDescriptor.CurrTF2 = $lba_l; # LBA Low
$CMDDescriptor.CurrTF3 = $lba_m; # LBA Mid
$CMDDescriptor.CurrTF4 = $lba_h; # LBA High
$CMDDescriptor.CurrTF5 = 0; # Device
$CMDDescriptor.CurrTF6 = 0x20; # READ SECTOR(S) (28bit command)
$CMDDescriptor.CurrTF7 = 0;

$ByteRet = 0;
$IoControlCode = 0x0004D02C; # IOCTL_ATA_PASS_THROUGH

[System.Runtime.InteropServices.Marshal]::StructureToPtr( $CMDDescriptor, $OutBuffer, [System.Boolean]::false );
$CallResult = $KernelService::DeviceIoControl( $DeviceHandle, $IoControlCode, $OutBuffer, $OutBufferSize, $OutBuffer, $OutBufferSize, [ref]$ByteRet, [System.IntPtr]::Zero );
$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error();
if ( $CallResult -eq 0 )
{
    Write-Host "`n[E] DeviceIoControl() failed: $LastError";
    Return;
}
elseif ( $ByteRet -ne 560 )
{
    Write-Host "`n[E] Data size returned ($ByteRet bytes) is wrong; expect $OutBufferSize bytes";
    Return;
}

Write-Host "";
Write-Host "        +0  +1  +2  +3  +4  +5  +6  +7   +8  +9  +A  +B  +C  +D  +E  +F";
Write-Host "        ---------------------------------------------------------------";

$ASCIIStr = "  "; # two spaces

for( $Cnt = 0; $Cnt -lt 512; $Cnt++ )
{
    # print address
    if( $Cnt % 16 -eq 0 )
    {
        $Str = $Cnt.ToString("X4");
        Write-Host -NoNewline "0x$Str  ";
    }
    elseif ( $Cnt % 8 -eq 0 )
    {
        Write-Host -NoNewline " ";
    }

    # print hex data
    $Code = [System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, 48 + $Cnt );
    $Str  = [System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, 48 + $Cnt ).ToString("X2");
    Write-Host -NoNewline "$Str  ";

    if( ( 0x20 -le $Code ) -and ( $Code -le 0x7E ) )
    { # these are ascii printable charactors
        $ASCIIStr += [Char]$Code;
    }
    else {
        $ASCIIStr += "."
    }

    if ( ( $Cnt + 1 ) % 16 -eq 0 )
    {
        Write-Host "$ASCIIStr";
        $ASCIIStr = "  "
    }
}
Write-Host "";

[System.Runtime.InteropServices.Marshal]::FreeCoTaskMem( $OutBuffer );
[void]$KernelService::CloseHandle( $DeviceHandle );

# eof

