

# The root folder
$RootFloder = "$pwd\"


# Add the working directory to the environment path.
# This is required for the ChromeDriver to work.
if (($env:Path -split ';') -notcontains $RootFloder) {
    $env:Path += ";$RootFloder"
}

# Check the Path environment variable
#$env:Path -split ';'

function WriteLog {
    Param ([string]$Logfile, [string]$LogString)

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "$Stamp $LogString"
    Add-content $LogFile -value $LogMessage
}

function Get-IniFile {  
    param(  
        [parameter(Mandatory = $true)] [string] $filePath  
    )  
    
    $anonymous = "NoSection"
  
    $ini = @{}  
    switch -regex -file $filePath {  
        "^\[(.+)\]$" {
            # Section    
            $section = $matches[1]  
            $ini[$section] = @{}  
            $CommentCount = 0  
        }  

        "^(;.*)$" {
            # Comment    
            if (!($section)) {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $value = $matches[1]  
            $CommentCount = $CommentCount + 1  
            $name = "Comment" + $CommentCount  
            $ini[$section][$name] = $value  
        }   

        "(.+?)\s*=\s*(.*)" {
            # Key    
            if (!($section)) {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $name, $value = $matches[1..2]  
            $ini[$section][$name] = $value  
        }  
    }  

    return $ini  
}  

function SendEmail {
    param(  
        [parameter(Mandatory = $true)] [string] $EmailSubject,
        [Parameter(Mandatory = $true, 
            HelpMessage = "Email attachments.")]
        [string[]]$Attachments
    
    )  
    try {
        $BaseConfig = Get-IniFile  "$RootFloder\config.ini"
        $EmailFrom = $BaseConfig.Base.SendFrom
        $EmailTo = $BaseConfig.Base.SendTo.split(';')           
        $SMTPserver = $BaseConfig.Base.SMTP      
        #$EmailSubject = "Auto Health Checked Result on " + (Get-Date).toString("yyyyMMdd")
        $EmailBody = "Dear Admin, <br><br>Please find the below attachment for the health check result!<br><br><br><br>"    

        #Write-Output "$EmailTo SMTP: $SMTPserver"
        #Send-MailMessage CmdLet
        Send-MailMessage -ErrorAction Stop -from "$EmailFrom" -to "$EmailTo" -subject "$EmailSubject" -body "$EmailBody" -BodyAsHtml -SmtpServer "$SMTPserver" -Attachments $Attachments
            
    }
    catch {

        Write-Output "There was a problem with sending email, check error log. Value of error is: $_"

        $ErrorLogFileName = (Get-Date).toString("yyyyMMdd-HHmmss")
        $ErrorLogfile = "$RootFloder\logs\Errors_$ErrorLogFileName.log"

        WriteLog $ErrorLogfile $_.ToString()
    }

}


$LogFileName = (Get-Date).toString("yyyyMMdd-HHmmss")
$Logfile = "$RootFloder\logs\$LogFileName.log"

# OPTION 1: Import Selenium to PowerShell using the Add-Type cmdlet.
# Add-Type -Path "$($RootFloder)\libs\WebDriver.dll"

# OPTION 2: Import Selenium to PowerShell using the Import-Module cmdlet.
# Import-Module "$($RootFloder)\libs\WebDriver.dll"

# OPTION 3: Import Selenium to PowerShell using the .NET assembly class.
[System.Reflection.Assembly]::LoadFrom("$($RootFloder)\libs\WebDriver.dll")

$ChromeOption = New-Object OpenQA.Selenium.Chrome.ChromeOptions 
$ChromeOption.AddExcludedArgument("enable-automation") 
$ChromeOption.AddArguments("--start-maximized") 
#$ChromeOption.AddArguments('--headless') #don't open the browser
# Ignore the SSL non secure issue
$ChromeOption.AcceptInsecureCertificates = $true

# Create a new ChromeDriver Object instance.
$ChromeDriver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($ChromeOption) 

$CheckItems = Get-IniFile  "$RootFloder\config.ini"

# Get Base settings
$IsDebug = $CheckItems.Base["IsDebug"] -eq "true"

$IsSuccess = $true
$EmailSubject = "Auto Health Checked Result on " + (Get-Date).toString("yyyyMMdd")

# $ChromeDriver.Navigate().GoToURL('http://localhost:4810/login')
# $ChromeDriver.Manage().Timeouts().ImplicitWait = 5
# $Element = $ChromeDriver.FindElement([OpenQA.Selenium.By]::XPath('//*[@id="wrapper"]'))
# $Element = $ChromeDriver.FindElements([OpenQA.Selenium.By]::TagName('div'))[0]

# Write-Output $Element


Foreach ($key in $CheckItems.keys ) {

    if ($key -ne "NoSection" -and $key -ne "Base") {

        if ($IsDebug) {
            Write-Output "=====$key===Start===Checking========="
            Write-Output $CheckItems.$key
        }
        
        $Item = $CheckItems.$key
        if ($null -ne $Item["Url"]) {
            # Launch a browser and go to URL if the Url is not null
            $ChromeDriver.Navigate().GoToURL($Item["Url"])
            # Wait for x seconds for loading the website content
            $ChromeDriver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($Item["Delay"])
            Start-Sleep -s $Item["Delay"]
        }

        if ($Item["IsLoginPage"] -eq "true") {
            # Handle the login page case
            
            # Get the encrypt user name and password
            $UserInfo = Get-Content $Item.LoginInfo
            $UserName = $UserInfo.Split("|")[0] | ConvertTo-SecureString
            $Password = $UserInfo.Split("|")[1] | ConvertTo-SecureString
            
            # decrypt the username and password and send to web page
            $UserName = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($UserName))
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
            #Write-Output $UserName

            # Write-Output "user name: $UserName password: $Password"

            # Pass the user and password
            $ChromeDriver.FindElement([OpenQA.Selenium.By]::XPath($Item["UserXPath"])).SendKeys($UserName)
            $ChromeDriver.FindElement([OpenQA.Selenium.By]::XPath($Item["PwdXPath"])).SendKeys($Password)
            $ChromeDriver.FindElement([OpenQA.Selenium.By]::XPath($Item["SubmitForm"])).Submit()
        }
        else {
            if ($null -ne $Item["SubSections"]) {
                foreach ($subSection in $Item["SubSections"].split(',')) {
                
                    $result = $key + " $subSection checked result: "

                    try {
                        $Element = $ChromeDriver.FindElement([OpenQA.Selenium.By]::XPath($Item[$subSection + "XPath"]))
                        if ($null -ne $Item[$subSection + "CheckByTagNames"]) {
                            # Get the elements by tag name and check it, if there is no that element then will be cause exception
                            $tagNames = $Item[$subSection + "CheckByTagNames"].split(",")
                            foreach ($tag in $tagNames) {
                                $tagName = $tag.split('|')[0]
                                $tagIndex = $tag.split('|')[1]
                                $Element = $Element.FindElements([OpenQA.Selenium.By]::TagName($tagName))[$tagIndex]
                            }
                        
                            # Perform onclick event on element
                            $ChromeDriver.ExecuteScript("arguments[0].click()", $Element)
                        }
    
                        # If there is no error, then means successfully and wirte to log
                        $result = "$result OK"
                        WriteLog $Logfile $result
                    }
                    catch {          
                        # If can't find the element then will be throw exception and failed
                        if ($IsDebug) {
                            Write-Output "Error: ==  " $_
                        }
                        $result = $result + $PSItem.Exception.Message
                        WriteLog $Logfile $result
                        $IsSuccess = $false
                    }
                }
            }
            else {
                # There is no sub section, then just check the content base on xpath
                $result = $key + " checked result: "
                try {
                    $Element = $ChromeDriver.FindElement([OpenQA.Selenium.By]::XPath($Item["XPath"]))

                    # If there is no error, then means successfully and wirte to log
                    $result = "$result OK"
                    WriteLog $Logfile $result
                }
                catch {          
                    # If can't find the element then will be throw exception and failed
                    Write-Output "Error: ==  " $_
                    $result = $result + $PSItem.Exception.Message
                    WriteLog $Logfile $result
                    $IsSuccess = $false
                }
            }
        }
    }
}


if (!$IsSuccess) {
    $EmailSubject = "[Failed] " + $EmailSubject
}

#SendEmail $EmailSubject $Logfile

# if(!$IsDebug){
#     $ChromeDriver.Close()
#     $ChromeDriver.Quit()
# }

# $ChromeDriver.Close()
# $ChromeDriver.Quit()