<#
Usage:
- PublishRelease.ps1 <vcsrooturl> <grepo> <gtk>...
Parameters:
'vcsrooturl' is the github owner name e.g. git@github.company.com:company/AMI-BASE.git
'gtk' is the github api token e.g. xxxxxxxxx
'gtag' is the published github tag e.g. V2.0.0
'env' is the deployment environment
'shook' is the slack web hook for your channel e.g. https://hooks.slack.com/services/xxxxxxxxx
'sicons' slack icons to include in the title message
'isCi' in ci mode?
'ciBuildBranch' is this master or tag eg. in teamcity teamcity.build.branch param 
Pre-reqs:
you have jira user credentials
you have a slack web hook setup to use slack integration
you have a git hub token for github api
Description:
Gets Access keys and session token for the specified role by passing appropriate credentials.
#>

Param (
    [Parameter(HelpMessage="Enter github ssh url...")] [String]$vcsrooturl,
    [Parameter(Mandatory=$true, HelpMessage="Enter github token...")] [String]$gtk,
    [Parameter(Mandatory=$true, HelpMessage="Enter latest git tag version...")] [String]$gtag,
    [Parameter(Mandatory=$true, HelpMessage="Enter deployment environment...")] [String]$env,
    [Parameter(HelpMessage="Enter slack webhook url...")] [String]$shook,
    [Parameter(HelpMessage="Enter slack icons...")] [String]$sicons,
    [Parameter(HelpMessage="What run type?")] [bool]$isCi = $true,
    [Parameter(HelpMessage="Check CI build Branch")] [String]$ciBuildBranch
)

# Enable TLS 1.2 as Security Protocol
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ;

$global:github_url = "https://github.company.com/api/v3/repos"
$global:github_owner = $vcsrooturl.split(":")[1].split(".")[0].split("/")[0]
$global:github_repo = $vcsrooturl.split(":")[1].split(".")[0].split("/")[1]
$global:github_token = $gtk
$global:slack_web_hook = $shook
$global:icons= $sicons
$global:environment = $env
$global:tag = $gtag 


#
# GitHub API
# ---------------------------------------------------------
$github = New-Module -ScriptBlock {

    function GetRelease {
        param([string] $tag)
 
        $url = "$github_url/$github_owner/$github_repo/releases/tags/$tag`?access_token=$github_token"

        return  Invoke-RestMethod -Uri $url -ContentType 'application/json' -Verbose
    }
    function PublishRelease {
        param([string] $id, [string] $tag)
 
        $url = "$github_url/$github_owner/$github_repo/releases/$id`?access_token=$github_token"
        
        $body = @{
            # tag_name=$tag
            # target_commitish='master'
            # name=$tag
            # body=$notes
            draft=$false
            prerelease=$false
          }

        $json = $body | ConvertTo-Json

        return  Invoke-RestMethod -Uri $url -Method PATCH  -Body $json -ContentType 'application/json' -Verbose
    }
 
    Export-ModuleMember -Function PublishRelease,GetRelease
} -AsCustomObject

#
# SLACK API
# ---------------------------------------------------------
$slack = New-Module -ScriptBlock {
 
    function SendMessage {
        param([string] $pretext, [string] $message) 

        $timestamp = $(get-date -uformat %s)

        $BodyTemplate = @"
    {
            "attachments": [
            {
                "mrkdwn_in": ["text"],
                "color": "#36a64f",
                "pretext": "$pretext",
                "author_name": "TC",
                "author_link": "https://$github_owner.tools.trainline.com/",
                "author_icon": "https://emojis.slackmojis.com/emojis/images/1486744926/1743/teamcity.png",
                "text": "$message",
                "thumb_url": "https://emojis.slackmojis.com/emojis/images/1571878272/6768/greentick.png",
                "footer": "$github_owner Team",
                "footer_icon": "https://emojis.slackmojis.com/emojis/images/1571878272/6768/greentick.png",
                "ts": $timestamp
            }
        ]
    }
}
"@
        
        return Invoke-RestMethod -uri $slack_web_hook -Method Post -body $BodyTemplate -ContentType 'application/json' -Verbose
    }
 
    Export-ModuleMember -Function SendMessage
} -AsCustomObject

#
# Check if this is a CI run
# ---------------------------------------------------------
Write-Host ("Checking type of run...")
Write-Host ("The CI Build Branch? $ciBuildBranch")

if ($isCi -and $ciBuildBranch.Contains("pull")) {
    Write-Host ("Pull request is supported in CI mode!!")
    exit 1
}

#
# Publish Release
# -------------------------------
Write-Host "Publish Release $tag."

$id=$github.GetRelease($tag).id
$release_url=$github.GetRelease($tag).html_url
$message="<$release_url|  $github_repo $tag View Release>"
$pretext = "Release $github_repo $tag $icons deployed on $environment"

$github.PublishRelease($id,$tag)

#skip if not provided
if ($slack_web_hook) {

#
# Push To Slack
# -------------------------------

$slack.SendMessage($pretext, $message)
    
}

Write-Host "Done----"