# param($fileName)
$fileName = "login_info.dat"
$User = Read-Host -Prompt 'Input your login name' -AsSecureString
$Pasword = Read-Host -Prompt 'Input your password' -AsSecureString

$User = $User | ConvertFrom-SecureString 
$Pasword = $Pasword | ConvertFrom-SecureString 

$info = "$User|$Pasword"
Set-content $fileName -value $info