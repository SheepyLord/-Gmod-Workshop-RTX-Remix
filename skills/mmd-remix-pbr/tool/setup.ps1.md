# setup.ps1

Creates the Python 3.12 venv in `RPAI_HOME\venv`, installs PyTorch 2.8.0 (CUDA 12.9 wheels) and `requirements.txt`, and downloads the PBRify_Remix v1.7.2 weights (CC0, 72.5 MB) into `RPAI_HOME\models\pbrify`.

```
powershell -ExecutionPolicy Bypass -File setup.ps1
```

## Side effects

Network downloads (PyTorch wheels, the weights zip): ask the user before running it. Writes only `RPAI_HOME` and a temporary zip in `%TEMP%` that it removes.

## Exit codes

0 on success; a terminating error (non-zero) when a step fails.
