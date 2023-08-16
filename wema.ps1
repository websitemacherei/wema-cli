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
else {
  throw "Invalid action."
}