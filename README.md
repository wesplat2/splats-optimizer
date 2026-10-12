# Splat's Optimizer

windows debloat / tweak tool with a gui. run `Splats Optimizer.exe` (asks for admin).

- `assets/` - the app itself (`Splats-Optimizer.ps1`), fonts and app icons
- `launcher-src/` - source for the exe launcher

## shipping an update

1. edit `assets/Splats-Optimizer.ps1` and bump `$AppVersion` at the top
2. put the same version (plus a short note) in `version.json`
3. push to `main` - the app checks `version.json` on launch and offers the update

## rebuilding the exe

```
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /out:"Splats Optimizer.exe" /win32icon:launcher-src\icon.ico /win32manifest:launcher-src\app.manifest /r:System.Windows.Forms.dll launcher-src\Launcher.cs
```

google sans is under the SIL open font license (`assets/fonts/OFL.txt`).