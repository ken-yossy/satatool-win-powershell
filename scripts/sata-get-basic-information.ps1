<#
sata-get-basic-information.ps1: Retrieve SATA drive's basic information from IDENTIFY DEVICE data

Usage: ./sata-get-basic-information.ps1 drive_no

    @arg[in]    drive_no    physical drive no to access (MANDATORY)

Copyright (c) 2024 Kenichiro Yoshii
Copyright (c) 2024 Hagiwara Solutions Co., Ltd.
#>
Param( [parameter(mandatory)][Int]$_drive_no )

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

function myReadByte()
{
    param( $_pBuffer, $_iOffset );
    $Data = [Int][System.Runtime.InteropServices.Marshal]::ReadByte( $_pBuffer, $_iOffset );
    return( $Data );
}

Write-Host "";

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
$CMDDescriptor.CurrTF0 = 0; # Features
$CMDDescriptor.CurrTF1 = 0; # Counts
$CMDDescriptor.CurrTF2 = 0; # LBA Low
$CMDDescriptor.CurrTF3 = 0; # LBA Mid
$CMDDescriptor.CurrTF4 = 0; # LBA High
$CMDDescriptor.CurrTF5 = 0; # Device
$CMDDescriptor.CurrTF6 = 0xEC; # IDENTIFY DEVICE (28bit command)
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

# calculate checksum
$checksum = 0;
for( $Cnt = 0; $Cnt -lt 512; $Cnt++ )
{
    $checksum += myReadByte $OutBuffer ( 48 + $Cnt );
}
$checksum = ( $checksum -band 0xFF );

if( $checksum -eq 0 )
{
    # From Word 10 to 19 is Serial Number field
    $WordCnt = 10;
    $SerialNMStr = "";
    for( $i = 0; $i -lt 10; $i++ )
    {
        $Code_L = myReadByte $OutBuffer ( 48 + ( $WordCnt * 2 ) + ( 2 * $i + 0 ) );
        $Code_H = myReadByte $OutBuffer ( 48 + ( $WordCnt * 2 ) + ( 2 * $i + 1 ) );
        $SerialNMStr += [Char]$Code_H;
        $SerialNMStr += [Char]$Code_L;
    }
    $SerialNMStr = $SerialNMStr.TrimEnd(); # chop

    # From Word 23 to 26 is Firmware Revision field
    $WordCnt = 23;
    $FWRevStr = "";
    for( $i = 0; $i -lt 4; $i++ )
    {
        $Code_L = myReadByte $OutBuffer ( 48 + ( $WordCnt * 2 ) + ( 2 * $i + 0 ) );
        $Code_H = myReadByte $OutBuffer ( 48 + ( $WordCnt * 2 ) + ( 2 * $i + 1 ) );
        $FWRevStr += [Char]$Code_H;
        $FWRevStr += [Char]$Code_L;
    }
    $FWRevStr = $FWRevStr.TrimEnd(); # chop

    # From Word 27 to 46 is Model Number field
    $WordCnt = 27;
    $MNStr = "";
    for( $i = 0; $i -lt 20; $i++ )
    {
        $Code_L = myReadByte $OutBuffer ( 48 + ( $WordCnt * 2 ) + ( 2 * $i + 0 ) );
        $Code_H = myReadByte $OutBuffer ( 48 + ( $WordCnt * 2 ) + ( 2 * $i + 1 ) );
        $MNStr += [Char]$Code_H;
        $MNStr += [Char]$Code_L;
    }
    $MNStr = $MNStr.TrimEnd(); # chop

    Write-Host "Model Number     : $MNStr";
    Write-Host "Serial Number    : $SerialNMStr";
    Write-Host "Firmware Revision: $FWRevStr";
}
else
{
    Write-Host "[E] Checksum error is detected, retrieved data may contain some error. abort.";
}

Write-Host "";

[System.Runtime.InteropServices.Marshal]::FreeCoTaskMem( $OutBuffer );
[void]$KernelService::CloseHandle( $DeviceHandle );

# eof

