$command = $args[0]


# "fetch": Copy pages/config from test or prod environment into local dev environment 
if ($command -eq "fetch") {
  $env = $args[1]

  if (($env -ne "test") -and ($env -ne "main")) {
    throw "Invalid environment. Use 'wema fetch test' or 'wema fetch main'."
  }

  if (-not (Test-Path -Path '.\web\user')) {
    throw "You do not seem to be at the root of a Grav project."
  }

  $confirm = Read-Host "This will override all existing pages and config in your current development environment. Proceed with (y). Abort with anything else."

  if ($confirm -ne "y") {
    throw "Aborted."
  }


  $folderName = Split-Path -Path (Get-Location) -Leaf
  $dataRepoName = "$folderName-data"
  $dataRepoUrl = "git@github.com:websitemacherei/$dataRepoName.git"

  git clone $dataRepoUrl DATA_REPO_TEMP
  Set-Location DATA_REPO_TEMP
  git checkout $env
  Set-Location ..

  Remove-Item -Recurse -Force .\web\user\pages
  Move-Item -Path .\DATA_REPO_TEMP\pages -Destination .\web\user
  Remove-Item -Recurse -Force .\web\user\data
  Move-Item -Path .\DATA_REPO_TEMP\data -Destination .\web\user
  Remove-Item -Recurse -Force .\web\user\config
  Move-Item -Path .\DATA_REPO_TEMP\config -Destination .\web\user
  # Loop over folders in .\DATA_REPO_TEMP\sites
  if (Test-Path -Path .\DATA_REPO_TEMP\sites) {
    $sites = Get-ChildItem -Path .\DATA_REPO_TEMP\sites -Directory
    foreach ($site in $sites) {
	  $siteName = $site.Name
    Remove-Item -Recurse -Force .\web\user\sites\$siteName\config -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force .\web\user\sites\$siteName\pages -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force .\web\user\sites\$siteName\data -ErrorAction SilentlyContinue
	  Move-Item -Path .\DATA_REPO_TEMP\sites\$siteName\config -Destination .\web\user\sites\$siteName
	  Move-Item -Path .\DATA_REPO_TEMP\sites\$siteName\pages -Destination .\web\user\sites\$siteName
	  Move-Item -Path .\DATA_REPO_TEMP\sites\$siteName\data -Destination .\web\user\sites\$siteName
    }
  }

  Remove-Item -Recurse -Force DATA_REPO_TEMP 
}
elseif ($command -eq "update") {
  $scriptPath = $MyInvocation.MyCommand.Path
  Remove-Item -Recurse -Force $scriptPath 
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/websitemacherei/wema-cli/main/wema.ps1" -OutFile "$scriptPath"
}
elseif ($command -eq "init") {
  $dirName = $args[1]
  $hostBase = $dirName.split(".")[0]
  # Get defaults for prompts
  $hostLocalDefault = "$($hostBase).local"
  $hostTestDefault = "$($hostBase).test.wema.work"
  $hostProdDefault = $dirName 
  $repoNameDefault = $dirName 
  # Prompt user for hostnames and repo names
  $hostLocal = Read-Host "Enter local hostname [$($hostLocalDefault)]"
  if ($hostLocal -eq "") { $hostLocal = $hostLocalDefault }
  $hostTest = Read-Host "Enter hostname for test instance [$($hostTestDefault)]"
  if ($hostTest -eq "") { $hostTest = $hostTestDefault }
  $hostProd = Read-Host "Enter hostname for production instance [$($hostProdDefault)]"
  if ($hostProd -eq "") { $hostProd = $hostProdDefault }
  $repoName = Read-Host "Enter name for GitHub repo [$($repoNameDefault)]"
  if ($repoName -eq "") { $repoName = $repoNameDefault }

  # Create code repo
  $repoAddress = "git@github.com:websitemacherei/$($repoName).git"
  $repoCreationRequestHeaders = @{
    "Authorization"        = "Bearer $($Env:GITHUB_TOKEN)"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  } 
  $repoCreationRequestBody = @{
    "name"    = $repoName
    "private" = $true
  } | ConvertTo-Json

  Invoke-RestMethod -Uri "https://api.github.com/orgs/websitemacherei/repos" -Method 'Post' -Body $repoCreationRequestBody -Headers $repoCreationRequestHeaders | ConvertTo-HTML | Out-Null
  # Create data repo
  $dataRepoAddress = "git@github.com:websitemacherei/$($repoName)-data.git"
  $dataRepoCreationRequestHeaders = @{
    "Authorization"        = "Bearer $($Env:GITHUB_TOKEN)"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  } 
  $dataRepoCreationRequestBody = @{
    "name"    = "$repoName-data"
    "private" = $true
  } | ConvertTo-Json

  Invoke-RestMethod -Uri "https://api.github.com/orgs/websitemacherei/repos" -Method 'Post' -Body $dataRepoCreationRequestBody -Headers $dataRepoCreationRequestHeaders | ConvertTo-HTML | Out-Null


  # Initialize data repo
  git clone git@github.com:websitemacherei/boilergrav-data.git $repoName-data
  Set-Location $repoName-data
  Remove-Item -Recurse -Force .git
  Get-ChildItem -Include .git -Recurse -Force | Remove-Item -Force -Recurse
  git init --initial-branch=main
  git remote add origin $dataRepoAddress
  # Set code repo env variable
((Get-Content -path .github/workflows/deploy_test.yml -Raw) -replace '%CODE_REPO%', $repoName) | Set-Content -Path .github/workflows/deploy_test.yml 
((Get-Content -path .github/workflows/deploy_test_without_sync.yml -Raw) -replace '%CODE_REPO%', $repoName) | Set-Content -Path .github/workflows/deploy_test_without_sync.yml 
((Get-Content -path .github/workflows/deploy_prod.yml -Raw) -replace '%CODE_REPO%', $repoName) | Set-Content -Path .github/workflows/deploy_prod.yml 
  git add .
  git commit -m "#skipaction"
  git checkout -b test
  git push --all origin
  Set-Location ..
  Remove-Item -Recurse -Force $reponame-data 

  # Initialize code repo
  git clone git@github.com:websitemacherei/boilergrav.git $repoName
  Set-Location $repoName
  Remove-Item -Recurse -Force .git
  Get-ChildItem -Include .git -Recurse -Force | Remove-Item -Force -Recurse
  git init --initial-branch=main
  git remote add origin $repoAddress
  # Set data repo address in 
  # Project name is domain name where dots are replaced with underscores
  $projectName = $hostProd -replace '\.', '_'
  # project name dev has suffix -dev
  $projectNameDev = $projectName + "-dev"
  $projectNameTest = $projectName + "-test"
  $projectNameProd = $projectName + "-prod"
((Get-Content -path .env -Raw) -replace '%PROJECT_NAME%', $projectNameDev) | Set-Content -Path .env 
((Get-Content -path .env -Raw) -replace '%HOST%', $hostLocal) | Set-Content -Path .env 
((Get-Content -path .env.test -Raw) -replace '%PROJECT_NAME%', $projectNameTest) | Set-Content -Path .env.test
((Get-Content -path .env.test -Raw) -replace '%HOST%', $hostTest) | Set-Content -Path .env.test
((Get-Content -path .env.prod -Raw) -replace '%PROJECT_NAME%', $projectNameProd) | Set-Content -Path .env.prod 
((Get-Content -path .env.prod -Raw) -replace '%HOST%', $hostProd) | Set-Content -Path .env.prod 
((Get-Content -path .\.git-sync-config\test.yaml -Raw) -replace '%DATAREPO%', $repoName) | Set-Content -Path .\.git-sync-config\test.yaml 
((Get-Content -path .\.git-sync-config\prod.yaml -Raw) -replace '%DATAREPO%', $repoName) | Set-Content -Path .\.git-sync-config\prod.yaml 
((Get-Content -path .\web\setup.php -Raw) -replace '%LOCAL%', $hostLocal) | Set-Content -Path .\web\setup.php 
((Get-Content -path .\web\setup.php -Raw) -replace '%TEST%', $hostTest) | Set-Content -Path .\web\setup.php 
((Get-Content -path .\web\setup.php -Raw) -replace '%PROD%', $hostProd) | Set-Content -Path .\web\setup.php 
((Get-Content -path .\web\setup.php -Raw) -replace '%PROJECT%', $hostBase) | Set-Content -Path .\web\setup.php 

  git add .
  git commit -m "Automated setup by WeMa-CLI"
  git checkout -b test 
  git checkout -b develop
  git push --all origin

  docker-compose up

  Write-Host "All done"
}
elseif ($command -eq "multisite") {
  git clone git@github.com:websitemacherei/grav-plugin-websitemacherei_routing.git web/user/plugins/websitemacherei_routing
  mv web/user/plugins/websitemacherei_routing/setup.php ./web/setup.php
  Write-Host "Please add the setup.php as a docker volume and adjust the setup.php to your liking."
}
elseif ($command -eq "update-test") {
  git push origin develop
  git checkout test
  git merge develop -m "Automatic merge performed by wema-cli"
  git push origin test
  git checkout develop
}

elseif ($command -eq "go-live") {
  Write-Host "This action will override all code and data in production with disregard to the current production state."
  $confirmation = Read-Host "Continue? (y/n)"
  if ($confirmation -eq "y") {
    Write-Host "Proceeding..."
    git push origin test
    git checkout main
    git merge test -m "Automatic merge performed by wema-cli"
    git push origin main
    git checkout develop
    $repoAddress = git ls-remote --get-url origin
    $repoAddress = $repoAddress.replace('.git', '-data.git')
    git clone $repoAddress DATA_TEMP
    Set-Location DATA_TEMP 
    git checkout test
    git checkout main
    Remove-Item -Recurse -Force config/* 
    Remove-Item -Recurse -Force pages/* 
    Remove-Item -Recurse -Force data/theme/*
    # Remove-Item -Recurse -Force data/*
    git checkout test -- config/
    git checkout test -- pages/
    git checkout test -- data/theme
    # Loop over folders in .\DATA_REPO_TEMP\sites
    if (Test-Path -Path .\sites) {
      $sites = Get-ChildItem -Path .\sites -Directory
      foreach ($site in $sites) {
	      $siteName = $site.Name
        Remove-Item -Recurse -Force .\sites\$siteName\config -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force .\sites\$siteName\pages -ErrorAction SilentlyContinue
        git checkout test -- sites/$siteName/config/
        git checkout test -- sites/$siteName/pages/
      }
    }
    git add .
    git commit -m "Update main from test" 
    git push origin main 
    Set-Location ..
    git checkout develop
    Write-Host "You may now run the workflow to deploy the production state."
  } else {
    Write-Host "Aborting..."
  }
}
elseif ($command -eq "reset-test") {
  Write-Host "This action will override all data on test if there is currently a test server"
  $confirmation = Read-Host "Continue? (y/n)"
  if ($confirmation -eq "y") {
    Write-Host "Proceeding..."
    $repoAddress = git ls-remote --get-url origin
    $repoAddress = $repoAddress.replace('.git', '-data.git')
    git clone $repoAddress DATA_TEMP
    Set-Location DATA_TEMP 
    git checkout test
    Remove-Item -Recurse -Force config/* 
    Remove-Item -Recurse -Force pages/* 
    Remove-Item -Recurse -Force data/*
    git checkout main -- config/
    git checkout main -- pages/
    git checkout main -- data/
    git add .
    git commit -m "Reset test" 
    git push origin test
    Set-Location ..
    Remove-Item -Recurse -Force DATA_TEMP 
  } else {
    Write-Host "Aborting..."
  }
}

elseif ($command -eq "help") {
  Write-Host "wema init <project-name>: Initializes a new project with a code repo and a data repo"
  Write-Host "wema update: Updates the wema-cli script to the latest version"
  Write-Host "wema fetch <environment (test|main)>: Fetches pages and config from the data repo into the local dev environment"
  Write-Host "wema update-test: Merges develop into test and pushes the result to the remote test branch"
  Write-Host "wema go-live: Merges test into main and pushes the result to the remote main branch"
  Write-Host "wema reset-test: Resets the test environment to the state of the main branch"
  Write-Host "wema version: Returns the version of the wema-cli script"
}

elseif ($command -eq "version") {
  Write-Host "1.5.1"
}
else {
  throw "Invalid action."
}