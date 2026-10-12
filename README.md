# Splat's Optimizer

windows debloat / tweak tool with a gui. run `Splats Optimizer.exe` (asks for admin).

- `assets/` - the app itself, plus its fonts and app icons
- `launcher-src/` - source for the exe launcher

## updates

hit **check for updates** on the start page. it compares your version with `version.json` here and offers to update if there's a newer one.

## rebuilding the exe

```
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /out:"Splats Optimizer.exe" /win32icon:launcher-src\icon.ico /win32manifest:launcher-src\app.manifest /r:System.Windows.Forms.dll launcher-src\Launcher.cs
```

google sans is under the SIL open font license (`assets/fonts/OFL.txt`).