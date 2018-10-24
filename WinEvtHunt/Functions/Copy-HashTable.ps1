function Copy-Hashtable
{
<#
.SYNOPSIS
   Copy hashtable and filter for key names
.DESCRIPTION
   Copy hashtable and filter for key names.  Optionally allow null values to be copied.  Optionally force null keys to be created for unmatched names.
.EXAMPLE
   Copy-Hashtable -InputObject $PSBoundParameters -Name ComputerName,Path,Destination
.EXAMPLE
   Another example of how to use this cmdlet
#>
    param
    (
        [Parameter(Mandatory)]
        [hashtable] $InputObject,

        [Parameter(ParameterSetName='Key')]
        [object[]] $Key,

        [switch] $AllowNull,

        [Parameter(ParameterSetName='Key')]
        [switch] $Force
    )

    $ht = @{}

    if ($Key)
    {
        # Validate object types. Only int, string, and hashtables are allowed
        $ValidatedKeys = @()
        foreach ($k in $Key)
        {
            if ($null -eq $k)
            {
                # do not add to validatedkeys. drop.
                # This is useful for releiving callers of the need to do null conditional checks
            }
            elseif (($k -isnot [string]) -and ($k -isnot [hashtable]) -and ($k -isnot [int]))
            {
                throw "error in Key object type"
            }
            elseif (($k -is [hashtable]) -and ($k.Count -gt 1))
            {
                throw "function only supports single-key hashtables"
            }
            elseif ($k -is [int])
            {
                $ValidatedKeys += ($k -as [string])
            }
            else
            {
                $ValidatedKeys += $k
            }
        }

        $refObj = [psobject]$InputObject
        foreach ($k in $ValidatedKeys)
        {
            # All of this logic needs work, review, and testing
            if ($k -is [hashtable])
            {
                $name = $k.Keys | Select-Object -First 1
                $value = $refObj | Select-Object -First 1 | ForEach-Object {($k[$name]).Invoke()}
                
                # This logic needs work
                if (($null -ne $value) -or ($AllowNull -or $Force))
                {
                    $ht[$name] = $value
                }
            }
            elseif ($AllowNull)
            {
                if (($InputObject.ContainsKey($k)) -or $Force)
                {
                    $ht[$k] = $InputObject[$k]
                }
            }
            else
            {
                if ((($InputObject.ContainsKey($k)) -and ($null -ne $InputObject[$k])) -or $Force)
                {
                    $ht[$k] = $InputObject[$k]
                }
            }
        }
    }
    else
    {
        foreach ($kv in $InputObject.GetEnumerator())
        {
            if (($AllowNull) -or ($null -ne $kv.Value))
            {
                $ht.Add($kv.Name, $kv.Value)
            }
        }
    }

    Write-Output $ht
}