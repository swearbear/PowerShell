
# Load functions
foreach ($script in (Get-ChildItem -Path "$PSScriptRoot\Functions" -Filter "*.ps1" -File))
{
    . $script.FullName
}

