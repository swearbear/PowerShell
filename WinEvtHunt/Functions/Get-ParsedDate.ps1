function Get-ParsedDate
{
<#
.SYNOPSIS
   Simplifies the conversion of arbitrary date/time strings to DateTime objects.
.DESCRIPTION
   Simplifies the conversion of arbitrary date/time strings to DateTime objects.  Really just a wrapper around the System.DateTime.TryParseExact method.
.EXAMPLE
   Get-ParsedDate -InputString "Archive-EventLog-2018-10-03-11-03-50-877.evtx" -FormatString "yyyy-MM-dd-HH-mm-ss"
.INPUTS
   String object with a date.
   Custom date string that matches the date substring of the input string.
.OUTPUTS
   DateTime object
.NOTES
   Author: Swearbear
   Version: 1.0
#>
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $InputString,

        [Parameter(Mandatory=$true)]
        [string] $FormatString,

        [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None
    )

    # match only two date/time format characters, (yy, MM, dd, HH, hh, mm, ss)
    $d2 = '((?<!y)yy(?!y)|(?<!M)MM(?!M)|(?<!d)dd(?!d)|(?<!H)HH(?!H)|(?<!h)hh(?!h)|(?<!m)mm(?!m)|(?<!s)ss(?!s))'
    # match only four year format characters
    $d4 = '(?<!y)yyyy(?!y)'
    # match only three month format characters (short month name)
    $a3 = '(?<!M)MMM(?!M)'

    [regex]$pattern = $FormatString -replace $d2, '\d\d' -replace $d4, '\d{4}' -replace $a3,'[A-Z]{3}'
    $dateString = $pattern.Match($InputString).Value
    [ref]$parsedDate = Get-Date

    if ([DateTime]::TryParseExact($dateString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
    {
        Write-Output $parsedDate.Value
    }
    else
    {
        Write-Error -ErrorAction Stop -Message "Failed to parse date from string: ${InputString}."
    }
}
<#
function Get-ParsedDate {
    param(
        [Parameter(Mandatory=$true)]
        [string] $InputString,

        [Parameter(Mandatory=$true)]
        [string] $FormatString,

        [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None,

        [switch] $Exact
    )

    [ref]$parsedDate = Get-Date
    if ([DateTime]::TryParseExact($InputString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
    {
        Write-Output $parsedDate.Value
    }
}
#>