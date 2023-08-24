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
  Remove-Item -Recurse -Force .\web\user\config
  Move-Item -Path .\DATA_REPO_TEMP\config -Destination .\web\user

  Remove-Item -Recurse -Force DATA_REPO_TEMP 
}
elseif ($command -eq "update") {
  $scriptPath = $MyInvocation.MyCommand.Path
  Remove-Item -Recurse -Force $scriptPath 
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/websitemacherei/wema-cli/main/wema.ps1" -OutFile "$scriptPath"
}
elseif ($command -eq "init") {
  $dirName = Split-Path -Path (Get-Location) -Leaf
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
    "Authorization"        = "Bearer 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"
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
    "Authorization"        = "Bearer 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"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  } 
  $dataRepoCreationRequestBody = @{
    "name"    = $dataRepoName
    "private" = $true
  } | ConvertTo-Json

  Invoke-RestMethod -Uri "https://api.github.com/orgs/websitemacherei/repos" -Method 'Post' -Body $dataRepoCreationRequestBody -Headers $dataRepoCreationRequestHeaders | ConvertTo-HTML | Out-Null


  # Initialize data repo
  git clone git@github.com:websitemacherei/boilergrav-data.git $repoName-data
  Set-Locatioo $repoName-data
  Remove-Item -Recurse -Force .git
  Get-ChildItem -Include .git -Recurse -Force | Remove-Item -Force -Recurse
  git init --initial-branch=main
  git remote add origin $dataRepoAddress
  # Set code repo env variable
((Get-Content -path .github/workflows/deploy_test.yaml -Raw) -replace '%CODE_REPO%', $repoName) | Set-Content -Path .github/workflows/deploy_test.yaml 
((Get-Content -path .github/workflows/deploy_test_without_sync.yaml -Raw) -replace '%CODE_REPO%', $repoName) | Set-Content -Path .github/workflows/deploy_test_without_sync.yaml 
((Get-Content -path .github/workflows/deploy_prod.yaml -Raw) -replace '%CODE_REPO%', $repoName) | Set-Content -Path .github/workflows/deploy_prod.yaml 
  git add .
  git commit -m "#skipAction"
  git checkout -b test
  git push --all origin
  Set-Location ..

  # Initialize code repo
  git clone git@github.com:websitemacherei/boilergrav.git $repoName
  Set-Location $repoName
  Remove-Item -Recurse -Force .git
  Get-ChildItem -Include .git -Recurse -Force | Remove-Item -Force -Recurse
  git init --initial-branch=main
  git remote add origin $repoAddress
  # Set data repo address in 
((Get-Content -path .env -Raw) -replace '%HOST%', $hostLocal) | Set-Content -Path .env 
((Get-Content -path .env.test -Raw) -replace '%HOST%', $hostTest) | Set-Content -Path .env.test
((Get-Content -path .env.prod -Raw) -replace '%HOST%', $hostProd) | Set-Content -Path .env.prod 
((Get-Content -path .\.git-sync-config\test.yaml -Raw) -replace '%DATAREPO%', $repoName) | Set-Content -Path .\.git-sync-config\test.yaml 
((Get-Content -path .\.git-sync-config\prod.yaml -Raw) -replace '%DATAREPO%', $repoName) | Set-Content -Path .\.git-sync-config\prod.yaml 
  git add .
  git commit -m "Automated setup by WeMa-CLI"
  git checkout -b test 
  git checkout -b develop
  git push --all origin

  docker-compose up

  Write-Host "Let's go"
}
elseif ($command -eq "version") {
  Write-Host "1.1.0"
}
else {
  throw "Invalid action."
}