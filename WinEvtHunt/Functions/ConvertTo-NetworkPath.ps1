function ConvertTo-NetworkPath
{
<#
.SYNOPSIS
   TODO
.DESCRIPTION
   TODO
.EXAMPLE
   TODO
.EXAMPLE
   TODO
#>
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true)]
        [string] $ComputerName
    )

    if ([System.IO.Path]::IsPathRooted($Path))
    {
        $drive = (Split-Path $path -Qualifier) -replace '\:','$' # Gets the drive letter without the path
        $newpath = Split-Path $path -NoQualifier # Get the path without the drive letter
        Join-Path "\\$ComputerName\$drive" $newpath # Combine the pieces with the computer name into a network path
    }
    else
    {
        throw "Path must be rooted or have a drive letter"
    }
}