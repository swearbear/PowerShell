function ConvertTo-WinEvtXPath
{
    param
    (
        [hashtable] $FilterHashtable
    )

    # LogName
    # Provider
    # EventID ( < > )
    # Start ( < > )
    # End ( < > )
    # Data @{"string" = *string*}
    

    $xpath = ""

    foreach ($kv in $FilterHashtable.GetEnumerator())
    {
        if ('LogName' -eq $kv.Name) {
            
        }
        elseif (('ID','EventID','Start','End','Provider') -contains $kv.Name) {
            
            if ($xpath -eq "") {
                $xpath = ("*[System[{0}='{1}']]" -f $kv.Name,$kv.Value)
            }
            if ($xpath -notmatch "^\*\[System") {
                
            }
        }
        elseif ('Data' -eq $kv.Name) {

        }
        

        if (id) {
            $values = [string[]]$value
            $vlen = $values.Length
            if ($vlen -gt 1) {
                
                for ($i=0; $i -lt $vlen; $i++) {
                    if ($i -eq 0) {
                        "[EventID={0}" -f $values[$i]
                    }
                    elseif ($i -eq ($vlen - 1)) {
                        " or EventID={0}]" -f $values[$i]
                    }
                    else {
                        " or EventID={0}" -f $values[$i]
                    }
                }
            }
        }

    }
}