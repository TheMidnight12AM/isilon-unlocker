# Isilon Unlocker
# Written By Joshua Woleben
# 10/7/2019
# PURPOSE: To unlock files, disconnect users, or specific sessions on an EMC Isilon Samba share
# USAGE: Type part of the file path or username into the appropriate field and click the corresponding search button.
#        The data grid will populate with the array name, the session ID, the file path, and user name.
#        Select one session to disconnect all sessions with that username or all sessions connected to that file.
#         Ctrl+Click or Shift+Click multiple sesions to disconnect those items specifically.
#         Set $username to root (or its equivalent) and either hardcode the $password field, or prompt for it or load from Secure file.
#         Replace "isilon.example.com" with your DNS entry for the primary node.
# REQUIREMENTS:
#               POSH-SSH
#               PowerShell 3.0+
#               Windows Presentation Framework
#               Root Isilon credentials

# Get POSH SSH
Import-Module -Name "\\funzone\team\POSH\Powershell\Modules\Posh-SSH.psm1"
Import-Module -Name "\\funzone\team\POSH\Powershell\Modules\Posh-SSH.psd1"

$username = 'root'
$password = ('arootpassword' | ConvertTo-SecureString -AsPlainText -Force)
$creds = New-Object -TypeName System.Management.Automation.PSCredential ($username,$password)

$script:result_mode = "NONE"

$script:user = ""
$script:file = ""
# GUI Code
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        Title="File Share Unlocker" Height="1000" Width="800" MinHeight="500" MinWidth="400" ResizeMode="CanResizeWithGrip">
    <StackPanel>
        <Label x:Name="FileSearchLabel" Content="File to Search"/>
        <TextBox x:Name="FileSearchTextBox" Height="20"/>
        <Button x:Name="FileSearchButton" Content="Search for File" Margin="10,10,10,0" VerticalAlignment="Top" Height="25"/>
        <Label x:Name="UserSearchLabel" Content="User to Search"/>
        <TextBox x:Name="UserSearchTextBox" Height="20"/>
        <Button x:Name="UserSearchButton" Content="Search for User" Margin="10,10,10,0" VerticalAlignment="Top" Height="25"/> 
        <Button x:Name="ClearFormButton" Content="Clear Form" Margin="10,10,10,0" VerticalAlignment="Top" Height="25"/>
        <Label x:Name="ResultsLabel" Content="Search Results"/>
        <Label x:Name="ResultsHeader" Content="Session ID, Path, User"/>
        <DataGrid x:Name="Results" AutoGenerateColumns="True" Height="400">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Array" Binding="{Binding Array}" Width="100"/>
                <DataGridTextColumn Header="SessionID" Binding="{Binding SessionID}" Width="100"/>
                <DataGridTextColumn Header="Path" Binding="{Binding Path}" Width="450"/>
                <DataGridTextColumn Header="User" Binding="{Binding User}" Width="80"/>
            </DataGrid.Columns>
        </DataGrid>
        <Button x:Name="StopSelectedResultsButton" Content="Disconnect Selected Sessions" Margin="10,10,10,0" VerticalAlignment="Top" Height="25"/>
        <Button x:Name="StopFileButton" Content="Disconnect ALL Sessions with selected file" Margin="10,10,10,0" VerticalAlignment="Top" Height="25"/>
        <Button x:Name="StopUserButton" Content="Disconnect ALL Sessions with selected user" Margin="10,10,10,0" VerticalAlignment="Top" Height="25"/>
    </StackPanel>
</Window>
'@
 
$global:Form = ""
# XAML Launcher
$reader=(New-Object System.Xml.XmlNodeReader $xaml) 
try{$global:Form=[Windows.Markup.XamlReader]::Load( $reader )}
catch{Write-Host "Unable to load Windows.Markup.XamlReader. Some possible causes for this problem include: .NET Framework is missing PowerShell must be launched with PowerShell -sta, invalid XAML code was encountered."; break}
$xaml.SelectNodes("//*[@Name]") | %{Set-Variable -Name ($_.Name) -Value $global:Form.FindName($_.Name)}

# Set up controls
$FileSearchTextBox = $global:Form.FindName('FileSearchTextBox')
$FileSearchButton = $global:Form.FindName('FileSearchButton')
$UserSearchTextBox = $global:Form.FindName('UserSearchTextBox')
$UserSearchButton = $global:Form.FindName('UserSearchButton')
$Results = $global:Form.FindName('Results')
$StopSelectedResultsButton = $global:Form.FindName('StopSelectedResultsButton')
$StopFileButton = $global:Form.FindName('StopFileButton')
$StopUserButton = $global:Form.FindName('StopUserButton')
$ClearFormButton = $global:Form.FindName('ClearFormButton')



$ClearFormButton.Add_Click({
    $UserSearchTextBox.Text = ""
    $FileSearchTextBox.text = ""
    $Results.Items.Clear()
    $global:Form.invalidateVisual()

})
$FileSearchButton.Add_Click({
    $search_pattern = $FileSearchTextBox.Text.ToString()

    $search_command = "isi_for_array isi smb openfiles list --format csv --verbose | grep -i `"$search_pattern`""



    $ssh_session = New-SSHSession -ComputerName "isilon.example.com" -Credential $creds
    $output_status = Invoke-SSHCommand -Command $search_command -Session $ssh_session.SessionId

    if ($output_status.Output.Count -ge 1) {
        $output_status.Output | ForEach-Object {
            $array = ($_ | Select-String -Pattern "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[1].Value.Trim()
            $id =    ($_ | Select-String -Pattern "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[2].Value
            $path = ($_ | Select-String -Pattern  "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[3].Value
            $script:user = ($_ | Select-String -Pattern "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[4].Value.Trim()
            $Results.AddChild([PSCustomObject]@{Array = $array; SessionID = $id; Path = $path; User= $script:user})
        }
    
        $global:Form.invalidateVisual()
        $script:result_mode = "FILE"
    }
    else {
        [System.Windows.MessageBox]::Show("No results returned!")
    }
    Remove-SSHSession -Session $ssh_session.SessionId
})

$UserSearchButton.Add_Click({
    $search_pattern = $UserSearchTextBox.Text.ToString()

    $search_command = "isi_for_array isi smb openfiles list --format csv --verbose | grep -i `"$search_pattern`""

    $ssh_session = New-SSHSession -ComputerName "isilon.example.com" -Credential $creds
    $output_status = Invoke-SSHCommand -Command $search_command -Session $ssh_session.SessionId
    if ($output_status.Output.Count -ge 1) {
        $output_status.Output | ForEach-Object {
            $array = ($_ | Select-String -Pattern "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[1].Value.Trim()
            $id =    ($_ | Select-String -Pattern "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[2].Value
            $path = ($_ | Select-String -Pattern  "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[3].Value
            $script:user = ($_ | Select-String -Pattern "^(isilon.example.com-\d).\s+?(.+?),(.+?),(.+?),.*").Matches.Groups[4].Value.Trim()
            $Results.AddChild([PSCustomObject]@{Array = $array; SessionID = $id; Path = $path; User= $script:user})
        }
        $global:Form.invalidateVisual()
        $script:result_mode = "USER"
    }
    else {
        [System.Windows.MessageBox]::Show("No results returned!")
    }
    Remove-SSHSession -Session $ssh_session.SessionId


})
$Results.Add_CurrentCellChanged({
    $script:file = $Result.SelectedItem.Path
    $script:user = $Result.SelectedItem.User
})

$StopFileButton.Add_click({
     
    
    if ($Results.SelectedItem) {
            $item = ($Results.SelectedItem.Path -replace '\\','[\\]')
            $search_pattern = $item
            $sessions_to_kill_command  = "isi_for_array isi smb openfiles list --verbose --format csv | egrep '$search_pattern,'  | cut -f1 -d, | cut -f2 -d:"
            Write-Host $sessions_to_kill_command
            $ssh_session = New-SSHSession -ComputerName "isilon.example.com" -Credential $creds
            $output_status = Invoke-SSHCommand -Command $sessions_to_kill_command -Session $ssh_session.SessionId -TimeOut 60
            Write-Host $output_status.Output
            $sessions_to_kill = $output_status.Output -join " "

            $kill_command = "for SESSION in $sessions_to_kill; do isi_for_array isi smb openfiles close `$SESSION --force; done"
            $output_status = Invoke-SSHCommand -Command $kill_command -Session $ssh_session.SessionId -TimeOut 60
            Write-Host $output_status.Output
            Remove-SSHSession -Session $ssh_session.SessionId



        }
        else {
            [System.Windows.MessageBox]::Show("No results to clear!")
            return
        }
        [System.Windows.MessageBox]::Show("Done!")
        $Results.Clear()
        $global:Form.invalidateVisual()
        
})
$StopUserButton.Add_Click({
        if ($Results.SelectedItem) {
            $item = $Results.SelectedItem.User
            $search_pattern = $item 
            $kill_command = "isi_for_array isi smb sessions delete-user `"$search_pattern`" --force"
            Write-Host $kill_command
            $ssh_session = New-SSHSession -ComputerName "isilon.example.com" -Credential $creds
            $output_status = Invoke-SSHCommand -Command $kill_command -Session $ssh_session.SessionId
            Write-Host $output_status.Output
            Remove-SSHSession -Session $ssh_session.SessionId
        }
        else {
            [System.Windows.MessageBox]::Show("No results to clear!")
            return
        }
        [System.Windows.MessageBox]::Show("Done!")
        $Results.Clear()
        $global:Form.invalidateVisual()
})
$StopSelectedResultsButton.Add_click({
     
   foreach ($item in $Results.SelectedItems) {
            $search_pattern = ($item.SessionID)
            $array = $item.Array

            $kill_command = ("isi_for_array -n $array isi smb openfiles close " + $search_pattern + " --force")
            Write-Host $kill_command
            $ssh_session = New-SSHSession -ComputerName "isilon.example.com" -Credential $creds
            $output_status = Invoke-SSHCommand -Command $kill_command -Session $ssh_session.SessionId
            Write-Host $output_status.Output
            Remove-SSHSession -Session $ssh_session.SessionId
  
    }
        [System.Windows.MessageBox]::Show("Done!")
        $Results.Clear()
        $global:Form.invalidateVisual()
        
})
# Show GUI
$global:Form.ShowDialog() | out-null