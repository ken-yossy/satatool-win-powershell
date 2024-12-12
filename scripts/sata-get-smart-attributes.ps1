<#
sata-get-smart-attributes.ps1: Retrieve S.M.A.R.T. attribute(s) from SATA drive

Usage: ./sata-get-smart-attributes.ps1 drive_no [attr_id]

    @arg[in]    drive_no    physical drive no. to access (MANDATORY)
    @arg[in]    attr_id     SMART attribute ID to be displayed (OPTION)
                            Default is zero; zero means all attributes are displayed.

Copyright (c) 2024 Kenichiro Yoshii
Copyright (c) 2024 Hagiwara Solutions Co., Ltd.
#>
Param(
    [parameter(mandatory)][Int]$_drive_no,
    [Int]$_attr_id = 0
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

Write-Host "";
if( ( $_attr_id -lt 0 ) -or ( 254 -lt $_attr_id ) )
{
    Write-Host "Specified attribute ID ($_attr_id) is out of range (0 < ID < 255), stop.";
    Write-Host "When 0 is specified for ID, all attributes are displayed.";
    Return;
}

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

$CMDDescriptor.Length = 48;
$CMDDescriptor.AtaFlags = 1 + 2; # ATA_FLAGS_DRDY_REQUIRED | ATA_FLAGS_DATA_IN
$CMDDescriptor.PathId = 0;
$CMDDescriptor.TargetId = 0;
$CMDDescriptor.Lun = 0;
$CMDDescriptor.DataTransferLength = 512; # one sector
$CMDDescriptor.TimeOutValue = 5;
$CMDDescriptor.DataBufferOffset = 48; # offsetof( stATAPassThroughEx, ucDataBuf )
$CMDDescriptor.CurrTF0 = 0xD0; # Features
$CMDDescriptor.CurrTF1 = 0; # Counts
$CMDDescriptor.CurrTF2 = 0; # LBA Low
$CMDDescriptor.CurrTF3 = 0x4F; # LBA Mid
$CMDDescriptor.CurrTF4 = 0xC2; # LBA High
$CMDDescriptor.CurrTF5 = 0; # Device
$CMDDescriptor.CurrTF6 = 0xB0; # SMART READ DATA (28bit command)
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

$Ver = [System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, 48 );
$Ver += ([Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, 49 ) -shl 8);
Write-Host "S.M.A.R.T. structure version = $Ver";
Write-Host "S.M.A.R.T. attributes:";

$Offset   = 48;
$Position = 2;
$isFound = 0;
do {
    $Id     =  [Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 0 );
    $IdStr  = $Id.ToString().PadLeft(3);

    $Flags  =  [Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 1 );
    $Flags += ([Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 2 ) -shl  8 );
    $FlagsStr = $Flags.ToString("X2");

    $Curr   =  [Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 3 );
    $CurrStr = $Curr.ToString().PadLeft(3);

    $Worst  =  [Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 4 );
    $WorstStr = $Worst.ToString().PadLeft(3);

    $Raw    =  [Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 5 );
    $Raw   += ([Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 6 ) -shl  8 );
    $Raw   += ([Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 7 ) -shl 16 );
    $Raw   += ([Int][System.Runtime.InteropServices.Marshal]::ReadByte( $OutBuffer, $Offset + $Position + 8 ) -shl 24 );
    $RawStr = $Raw.ToString("X8");

    if( $_attr_id -ne 0 )
    {
        if( $Id -eq $_attr_id )
        {
            Write-Host "ID = $IdStr, Flags = 0x$FlagsStr, Current value = $CurrStr, Worst value = $WorstStr, Raw value = 0x$RawStr";
            $isFound = 1;
        }
    }
    elseif( $Id -ne 0 )
    {
        Write-Host "ID = $IdStr, Flags = 0x$FlagsStr, Current value = $CurrStr, Worst value = $WorstStr, Raw value = 0x$RawStr";
    }
    $Position += 12;
} while( $Position -lt 362 )

if( ( $_attr_id -ne 0 ) -and ( $isFound -eq 0 ) )
{
    Write-Host "S.M.A.R.T. attribute (ID = $_attr_id) is not found.";
}
Write-Host "";

[System.Runtime.InteropServices.Marshal]::FreeCoTaskMem( $OutBuffer );
[void]$KernelService::CloseHandle( $DeviceHandle );

# eof

