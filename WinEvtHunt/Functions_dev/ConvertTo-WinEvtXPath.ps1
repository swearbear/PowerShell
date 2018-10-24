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

    foreach ($n in $FilterHashtable.Keys)
    {
        switch ($n)
        {
            LogName {}
            Provider {
                    if ($xpath -match "^\*\[System")
                    {
                    }
                    $xpath += ("*[System[Provider[@Name='{0}']]]" -f $FilterHashtable[$n])
                }
            EventID {}
            ID {}
            Start {}
            End {}
            Data {}
        }
    }
}