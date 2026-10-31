# rpai.cmd

Launcher: sets `RPAI_HOME` (default `%USERPROFILE%\.rpai`) and `PYTHONPATH` to `tool\`, then runs `python -m rpai` from the rpai venv with all arguments.

```
rpai.cmd run "E:\path\model.pmx"
rpai.cmd doctor
```

## Side effects

None of its own (it runs `rpai`).

## Exit codes

1 when the venv is missing (run `setup.ps1`); otherwise `rpai`'s exit code.
