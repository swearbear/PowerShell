<#
.Synopsis
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
.Notes
   Author: Swearbear
   Version: 1.0
#>

function Get-ParsedDate
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $InputString,

        [Parameter(Mandatory=$true)]
        [string] $FormatString,

        [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None,

        [switch] $Exact
    )

    [ref]$parsedDate = Get-Date
    [regex]$pattern = $FormatString -replace '((?<!y)yy(?!y)|(?<!M)MM(?!M)|(?<!d)dd(?!d)|(?<!H)HH(?!H)|(?<!h)hh(?!h)|(?<!m)mm(?!m)|(?<!s)ss(?!s))','\d\d' -replace '(?<!y)yyyy(?!y)','\d{4}' -replace '(?<!M)MMM(?!M)','[A-Z]{3}'
    $dateString = $pattern.Match($InputString).Value

    if ([DateTime]::TryParseExact($dateString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
    {
        Write-Output $parsedDate.Value
    }
}