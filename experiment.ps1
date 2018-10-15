
# Start Time
$st = Get-Date

# Create Dictionary
$d = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]'

.\Get-BulkWinEvent.ps1 -cn muhj-ms-lec01p -LogName wec-domain-controllers `
-xpath "*[System[EventID=4624]]" -ArchiveNewerThan (get-date).adddays(-3) `
-SecondaryFilter {-Not $_.Properties[5].Value.EndsWith('$')} |
select data_targetusername,data_ipaddress |
% {$d[$_.Data_TargetUserName] += $_.Data_IPAddress;} |
group data_targetusername

Write-Host "Elapsed: $((Get-Date) - $st)"

$d

    <#
    |select Name,
    @{n='WS';e={$_.Group.data_ipaddress |select -unique}},
    @{n='WSCount';e={($_.Group.data_ipaddress |select -unique).count}} |sort WSCount
    #>