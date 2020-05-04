# Automated Release Notes

The goals repository:

 - The Automated release notes attempts to bridge the communication and visibility gap of releases.
 - Provide a consistent and unified approach to creating release notes
 - Cross platform works on windows and linux
 - Integrates with CI e.g Teamcity

## Prerequisites

You will need to install the following: 

- Powershell
- you have Jira token built from user credentials
- you have a slack web hook setup to use slack integration
- you have a git hub token for github api

    **Jira Token - Please use a service user **
    
    **You need to have powershell installed on your Teamcity Agents**


## Params description

| Parameter| Description   |
|----------|:-------------:|
|vcsrooturl| github owner name e.g. git@github.company.com:myRepo/AMI-BASE.git|
|gtk| github api token e.g. xxxxxxxxx|
|lgtag| github tag to be created e.g. V2.0.0|
|gtag| published github tag e.g. V1.2.3|
|env| deployment environment e.g. Production|
|shook| slack web hook for your channel e.g. https://hooks.slack.com/services/xxxxxxxxx|
|sicons| slack icons to include in the title message|
|jurl| jira url for your board e.g. https://jira.company.com|
|jAuthToken| user credetials for jira e.g. joebloggs:password123 encode to base64|
|jregex| regular expression for your jira tickets e.g. MY-xxx|
|file| full path to the asset to upload|
|isCi| in ci mode?|
|Check CI build Branch| check its not a pull request?|

## Running Locally or CI Mode example

```powershell
.\GitReleaseNotes.ps1 `
-vcsrooturl 'git@github.company.com:myRepo/repo.git' `
-gtk 'token' `
-jurl 'https://jira.company.com' `
-jAuthToken 'token' `
-lgtag 'v1.458' `
-jregex 'MY-[0-9]*' ` 
-file '.\manifest.txt'
-ciBuildBranch 'refs/heads/master' ##%teamcity.build.branch%
```

```powershell
.\PublishRelease.ps1 `
-vcsrooturl 'git@github.company.com:myRepo/repo.git' `
-gtk 'token' `
-env 'Production' `
-shook 'https://hooks.slack.com/services/xxx/xxx' `
-gtag 'v1.458'
```

## Not yet supported!
- Jira Release notes
- Gitlab support
