<#
.Synopsis
   Convert ARAD's comma separated vomit to JSON.
.DESCRIPTION
   Attempts to convert ARAD's awful CSV exports into something readable for scripts.
   This script assumes that the operator has manually added headers to the CSV, because,
   wouldn't you know it, ARAD doesn't provide them.
   
   Output is to the pipeline in order to simplify script complexity and reinforce
   inter-operability and operator choice. Personal choice is to pipe the output to
   ConvertTo-Json then out to file.
   
   Functionality is limited in this version:
   -Input only from file.
.EXAMPLE
   (TODO) Example of how to use this cmdlet
.EXAMPLE
   (TODO) Another example of how to use this cmdlet
.NOTES
   By: SSgt Chester Swearingen
   Date: 20 June 2018
   Version: 0.1 (beta)

   Requires many more than the two ARAD export samples available when coding. Please contact
   me with ARAD export samples this script can't handle.
#>

param(
    [string]$Path
)

$rawCsv = Import-Csv $Path
$headers = $rawCsv[0] |gm -view Extended |select -exp name
Add-Type -AssemblyName System.Web

$rawCsv |ForEach-Object {
    
    $props = [ordered]@{}
    foreach ($name in $headers) {
        if ($_.$name -match '^\n$') {
            $value = ""
        } elseif ($_.$name -match '(?<!\r)\n') {
            $value = [System.Web.HttpUtility]::HtmlDecode($_.$name) -split '(?<!\r)\n'
        } else {
            $value = [System.Web.HttpUtility]::HtmlDecode($_.$name)
        }
        if ($value.Count -gt 1) {
            if ($value[0] -match '^"[^$]*(?<!")$') {
                $value[0] = $value[0].Substring[1, ($value[0].Length -1)]
            }
            if ($value[-1] -match '^(?!")[^$]*"$') {
                $value[-1] = $value[-1].Substring[1, ($value[-1].Length -1)]
            }
        }
        $value = $value |Select -Unique
        $props.Add($name, $value)
    }

    New-Object pscustomobject -Property $props

}
