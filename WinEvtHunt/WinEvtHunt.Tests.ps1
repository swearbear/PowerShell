# Unit Tests
# - Test for expected output values and exceptions
# - Mock all commands that change machine state
# - Assert that mocks have been called the expected number of times
#
# Functional Tests
# - Test for actual state change
# - Minimal usage of Mock objects
# - Use TestDrive to isolate state changes where possible
#

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.ps1', '.psm1'
Remove-Module WinEvtHunt > $null
Import-Module "$here\$sut"


Describe "Test-LocalHost" {
    Context "When there are no IP addresses" {
        Mock -ModuleName WinEvtHunt Get-LocalIPAddress { }

        $result = Test-LocalHost -ComputerName $env:COMPUTERNAME
        
        It "answers if the argument ids the localhost" {
            $result | Should -Be $true
        }
    }

    Context "When there is one IP address" {
        Mock -ModuleName WinEvtHunt Get-LocalIPAddress {return "192.168.9.1"}

        $result = Test-LocalHost -ComputerName $env:COMPUTERNAME
        
        It "answers if the argument ids the localhost" {
            $result | Should -Be $true
        }
    }

    Context "When there are multiple IP addresses" {
        Mock -ModuleName WinEvtHunt Get-LocalIPAddress {return "192.168.9.78","141.54.4.11"}

        $result = Test-LocalHost -ComputerName $env:COMPUTERNAME
        
        It "answers if the argument ids the localhost" {
            $result | Should -Be $true
        }
    }
}


