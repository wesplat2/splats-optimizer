using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Splat's Optimizer")]
[assembly: AssemblyProduct("Splat's Optimizer")]
[assembly: AssemblyDescription("Splat's Optimizer")]
[assembly: AssemblyCompany("Splat")]
[assembly: AssemblyCopyright("Splat")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

// Starts assets\Splats-Optimizer.ps1 with no console window.
// The manifest makes Windows ask for admin before this even runs.
static class Program
{
    [STAThread]
    static int Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string assets = Path.Combine(root, "assets");
        string script = Path.Combine(assets, "Splats-Optimizer.ps1");

        if (!File.Exists(script))
        {
            MessageBox.Show("can't find assets\\Splats-Optimizer.ps1\n\nkeep the exe and the assets folder together in the same place.",
                "Splat's Optimizer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // always use 64-bit PowerShell on 64-bit Windows (sfc/dism need it)
        string sysDir = Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Sysnative")
            : Environment.GetFolderPath(Environment.SpecialFolder.System);
        string powershell = Path.Combine(sysDir, @"WindowsPowerShell\v1.0\powershell.exe");

        var psi = new ProcessStartInfo(powershell,
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = assets;

        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("couldn't start it:\n\n" + ex.Message, "Splat's Optimizer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
