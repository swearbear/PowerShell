## Get-Base64RegularExpression.ps1 
## Get a regular expression that can be used to search for content that has been 
## Base-64 encoded
param( 
    ## The value that we would like to search for in Base64 encoded content 
    [Parameter(Mandatory)] 
    $Value 
)

## Holds the various byte representations of what we're searching for 
$byteRepresentations = @()

## If we got a string, look for the Unicode and ASCII representations of the string 
if($Value -is [String]) 
{ 
    $byteRepresentations +=  
        [System.Text.Encoding]::Unicode.GetBytes($Value), 
        [System.Text.Encoding]::ASCII.GetBytes($Value) 
}

## If it was a byte array directly, look for the byte representations 
if($Value -is [byte[]]) 
{ 
    $byteRepresentations += ,$Value 
}

## Find the safe searchable sequences for each Base64 representation of input bytes 
$base64sequences = foreach($bytes in $byteRepresentations) 
{ 
    ## Offset 0. Sits on a 3-byte boundary so we can trust the leading characters. 
    $offset0 = [Convert]::ToBase64String($bytes)

    ## Offset 1. Has one byte from preceeding content, so we need to throw away the 
    ## first 2 leading characters 
    $offset1 = [Convert]::ToBase64String( (New-Object 'Byte[]' 1) + $bytes ).Substring(2)

    ## Offset 2. Has two bytes from preceeding content, so we need to throw away the 
    ## first 4 leading characters 
    $offset2 = [Convert]::ToBase64String( (New-Object 'Byte[]' 2) + $bytes ).Substring(4)

    ## If there is any terminating padding, we must remove the characters mixed with that padding. That 
    ## ends up being the number of equals signs, plus one. 
    $base64matches = $offset0,$offset1,$offset2 | % { 
        if($_ -match '(=+)$') 
        { 
            $_.Substring(0, $_.Length - ($matches[0].Length + 1)) 
        } 
        else 
        { 
            $_ 
        } 
    }

    $base64matches | ? { $_ } 
}

## Output a regular expression for these sequences 
"(" + (($base64sequences | Sort-Object -Unique) -join "|") + ")"