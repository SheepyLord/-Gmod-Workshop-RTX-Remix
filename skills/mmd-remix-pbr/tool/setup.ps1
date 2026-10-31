# Creates the Python environment and downloads the PBRify models.
# Everything goes to $env:RPAI_HOME (default %USERPROFILE%\.rpai): PyTorch's
# DLLs fail to load from long paths, so the venv must not live in a deep folder.
$ErrorActionPreference = "Stop"
$root = if ($env:RPAI_HOME) { $env:RPAI_HOME } else { Join-Path $env:USERPROFILE ".rpai" }
$python = Join-Path $root "venv\Scripts\python.exe"

if (-not (Test-Path $python)) {
    Write-Host "Creating venv in $root\venv"
    py -3.12 -m venv (Join-Path $root "venv")
}
& $python -m pip install --upgrade pip
# cu129 wheels include Blackwell (RTX 50) kernels; this is the index NVIDIA's Remix ComfyUI setup uses.
& $python -m pip install torch==2.8.0 torchvision==0.23.0 --index-url https://download.pytorch.org/whl/cu129
& $python -m pip install -r (Join-Path $PSScriptRoot "requirements.txt")

$models = Join-Path $root "models\pbrify"
if (-not (Test-Path (Join-Path $models "1x-PBRify_NormalV3.pth"))) {
    $zip = Join-Path $env:TEMP "PBRify_Remix_1.7.2_ComfyUI_ONLY.zip"
    Write-Host "Downloading PBRify_Remix v1.7.2 (CC0, 72.5 MB)"
    Invoke-WebRequest -Uri "https://github.com/Kim2091/PBRify_Remix/releases/download/v1.7.2_ComfyOnly/PBRify_Remix_1.7.2_ComfyUI_ONLY.zip" -OutFile $zip
    New-Item -ItemType Directory -Force $models | Out-Null
    Expand-Archive $zip -DestinationPath $models -Force
    Remove-Item $zip
}
Write-Host "Done. Check the installation with:  .\rpai.cmd doctor"
