$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'Sources\AELanguageSwitcherApp\Resources\AppIconSource.png'
$target = Join-Path $repo 'windows\src\AELanguageSwitcher.App\Resources\AppIcon.ico'
$python = 'C:\Users\HWT\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
& $python -c "from PIL import Image; im=Image.open(r'$source').convert('RGBA'); im.save(r'$target', format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
