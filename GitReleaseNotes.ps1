<#
Usage:
- GitReleaseNotes.ps1 <vcsrooturl> <grepo> <gtk>...
Parameters:
'vcsrooturl' is the github owner name e.g. git@github.company.com:company/AMI-BASE.git
'gtk' is the github api token e.g. xxxxxxxxx
'lgtag' is the latest github tag e.g. V2.0.0
'jurl' is the jira url for your board e.g. https://jira.company.com
'jAuthToken' is the user credetials for jira e.g. joebloggs:password123 encode to base64
'jregex' is the regular expression for your jira tickets e.g. PD-xxx
'file' is the full path to the asset to upload
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
    [Parameter(Mandatory=$true, HelpMessage="Enter latest git tag version...")] [String]$lgtag,
	[Parameter(HelpMessage="Enter jira url...")] [String]$jurl = "https://jira.company.com",
	[Parameter(Mandatory=$true, HelpMessage="Enter jira base64AuthToken...")] [String]$jAuthToken,
    [Parameter(Mandatory=$true, HelpMessage="Enter jira ticket regex pattern...")] [String]$jregex,
    [Parameter(HelpMessage="Extra info for release notes...")] [String]$file,
    [Parameter(HelpMessage="What run type?")] [bool]$isCi = $true,
    [Parameter(HelpMessage="Check CI build Branch")] [String]$ciBuildBranch
)

# Enable TLS 1.2 as Security Protocol
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ;

$global:github_url = "https://github.company.com/api/v3/repos"
$global:github_owner = $vcsrooturl.split(":")[1].split(".")[0].split("/")[0]
$global:github_repo = $vcsrooturl.split(":")[1].split(".")[0].split("/")[1]
$global:github_token = $gtk
$global:jira_url = $jurl
$global:jira_auth_token = $jAuthToken
$global:slack_web_hook = $shook
$latestTagVersion = $lgtag 
$regex = $jregex

#
# GitHub API
# ---------------------------------------------------------
$github = New-Module -ScriptBlock {
    function GetCommits {
        param([string] $base, [string] $head = "master")
 
        $url = "$github_url/$github_owner/$github_repo/compare/" + $base + "..." + $head + "?access_token=$github_token"
        return  Invoke-RestMethod -Uri $url -Verbose
    }

    function CreateRelease {
        param([string] $latestTagVersion, [string] $notes)
 
        $url = "$github_url/$github_owner/$github_repo/releases?access_token=$github_token"
        
        $body = @{
            tag_name=$latestTagVersion
            target_commitish='master'
            name=$latestTagVersion
            body=$notes
            draft=$false
            prerelease=$true
          }

        $json = $body | ConvertTo-Json

        return  Invoke-RestMethod -Uri $url -Method Post -Body $json -ContentType 'application/json' -Verbose
    }

    function UploadAsset {
        param([string] $tag, [string] $filename)

        $uploadUrl = ($github.GetReleaseByTag($tag).upload_url).replace("{?name,label}","")

        $content = Get-Content -Path $filename

        $url = "$uploadUrl`?name=$filename&access_token=$github_token"

        return  Invoke-RestMethod -Uri $url -Method Post -Body $content -ContentType 'text/plain; charset=UTF-8' -Verbose
    }

    function GetReleaseByTag {
        param([string] $Tag)
 
        $url = "$github_url/$github_owner/$github_repo/releases/tags/$tag`?access_token=$github_token"
        return  Invoke-RestMethod -Uri $url -Verbose
    }

    function GetLatestRelease {
 
        $url = "$github_url/$github_owner/$github_repo/releases/latest`?access_token=$github_token"
        return  Invoke-RestMethod -Uri $url -Verbose
    }

    function DeleteRelease {
        param([string] $id)
 
        $url = "$github_url/$github_owner/$github_repo/releases/$id`?access_token=$github_token"

        return  Invoke-RestMethod -Uri $url -Method Delete -Verbose
    }
 
    Export-ModuleMember -Function GetCommits, CreateRelease, UploadAsset, DeleteRelease, GetReleaseByTag, GetLatestRelease
} -AsCustomObject

#
# JIRA API
# ---------------------------------------------------------
$jira = New-Module -ScriptBlock {
 
    function GetIssue {
        param([string] $issueId)
 
        return Invoke-RestMethod -Uri "$jira_url/rest/api/latest/issue/$issueId" -Headers @{"Authorization"="Basic $jira_auth_token"} -ContentType application/json -Verbose
    }
 
    Export-ModuleMember -Function GetIssue
} -AsCustomObject

#
# Check if this is a CI run
# ---------------------------------------------------------
Write-Host ("Checking type of run...")
Write-Host ("Is CI? $isCi")
Write-Host ("The CI Build Branch? $ciBuildBranch")

if ($isCi -and $ciBuildBranch.Contains("pull")) {
    Write-Host ("Pull request is supported in CI mode!!")
    exit 1
}

#
# Delete Release
# -------------------------------

Write-Host "Attempt to get release $latestTagVersion."

try {

    $id = $github.GetReleaseByTag($latestTagVersion).id

    Write-Host "Release id: " $id

    Write-Host "Attempt to delete release $id."

    $github.DeleteRelease($id)
    
}
catch {

    Write-Host "No releases to delete"
    
}

#
# Get all commits from latest deployment to this commit
# ---------------------------------------------------------
Write-Host ("Getting last publish tag...")

$response = $github.GetLatestRelease()
$previousTagVersion = $response.tag_name

Write-Host "Publish Tag "$previousTagVersion

Write-Host ("Getting all commits from git tag " + $latestTagVersion + " to commit sha $teamcity_commitId.")

$response = $github.GetCommits($previousTagVersion)
$commits = $response.commits | Sort-Object -Property @{Expression={$_.commit.author.date}; Ascending=$false} -Descending

#
# Get all JIRA issues from latest deployment to this build
# ---------------------------------------------------------
Write-Host "Getting all issues."

$issues = $response | ConvertTo-Json | Select-String -AllMatches $regex| ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } | Sort-Object -Unique

Write-Host ("Jira Issues Id: " + $issues)

#
# Generate release notes based on commits and issues
# ---------------------------------------------------------
Write-Host "Generating release notes based on commits."
$nl = [Environment]::NewLine
$releaseNotes = "# Automatic release for $github_repo $latestTagVersion created $(Get-Date)"
 
if ($null -ne $commits) {
    if ($null -ne $issues) {
        $releaseNotes = $releaseNotes + "$nl$nl## All stories in Release $latestTagVersion $nl"
 
        foreach ($issue in $issues) {
            $jiraIssue = $jira.GetIssue($issue)
            $releaseNotes = $releaseNotes + "- [" + $issue + "]("+ $jira_url +"/browse/" +  $issue + ") - " + $jiraIssue.fields.summary + "$nl"
        }
    }

    $releaseNotes = $releaseNotes + "$nl$nl## All commits in this Release$nl"

    foreach ($commit in $commits) {
        $releaseNotes = $releaseNotes + "- [" + $commit.sha.Substring(0, 10) + "](https://github.company.com/$github_owner/$github_repo/commit/" + $commit.sha + ") - " + $commit.commit.message + "$nl"
    }
}
else {
    $releaseNotes = $releaseNotes + "$nl There are no new items for this release.$nl"
}

#
# Create Release
# -------------------------------
Write-Host "Creating release for $latestTagVersion."

New-Item releasenotes.md -type file -force -value $releaseNotes


#
# Push Release
# -------------------------------
Write-Host "Push release notes to github for $latestTagVersion."

$github.CreateRelease($latestTagVersion, $releaseNotes)

#
# Add Asset
# -------------------------------

if ($file) {
    Write-Host "Add Asset to release"
    $github.UploadAsset($latestTagVersion, $file)
}

Write-Host "Done----"