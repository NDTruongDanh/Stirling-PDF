using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace StirlingPDFLauncher
{
    static class Program
    {
        private static string _rootDir;
        private static string _appDir;
        private static string _logsDir;
        private static string _javawExe;
        private static string _jarPath;
        private static string _jreBin;

        [STAThread]
        static void Main(string[] args)
        {
            _rootDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            _appDir = Path.Combine(_rootDir, "app");
            _logsDir = Path.Combine(_appDir, "logs");
            _jreBin = Path.Combine(_rootDir, @"jre\bin");
            _javawExe = Path.Combine(_jreBin, "javaw.exe");
            if (!File.Exists(_javawExe))
            {
                _javawExe = Path.Combine(_jreBin, "java.exe");
            }
            string[] jarCandidates = new string[]
            {
                Path.Combine(_appDir, "Stirling-PDF.jar"),
                Path.Combine(_appDir, "Stirling-PDF-server.jar"),
                Path.Combine(_rootDir, "Stirling-PDF.jar"),
                Path.Combine(_rootDir, "Stirling-PDF-server.jar")
            };
            foreach (string candidate in jarCandidates)
            {
                if (File.Exists(candidate))
                {
                    _jarPath = candidate;
                    _appDir = Path.GetDirectoryName(candidate);
                    _logsDir = Path.Combine(_appDir, "logs");
                    break;
                }
            }
            if (string.IsNullOrEmpty(_jarPath) || !File.Exists(_jarPath))
            {
                string searchDir = Directory.Exists(_appDir) ? _appDir : _rootDir;
                string[] jars = Directory.GetFiles(searchDir, "*.jar");
                if (jars.Length > 0)
                {
                    _jarPath = jars[0];
                    _appDir = Path.GetDirectoryName(_jarPath);
                    _logsDir = Path.Combine(_appDir, "logs");
                }
                else
                {
                    _jarPath = Path.Combine(_appDir, "Stirling-PDF.jar");
                }
            }

            try
            {
                if (!Directory.Exists(_logsDir))
                {
                    Directory.CreateDirectory(_logsDir);
                }
            }
            catch { }

            // Check single instance mutex
            bool createdNew;
            using (Mutex mutex = new Mutex(true, "StirlingPDF_AppLauncher_Mutex", out createdNew))
            {
                if (!createdNew)
                {
                    // An instance is already running; open the app window and exit this launcher
                    LaunchAppWindow();
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                Process javaProcess = null;

                // Check if backend is already responding
                if (!IsBackendReady())
                {
                    // Start backend with a sleek Splash Screen
                    using (SplashScreen splash = new SplashScreen(_rootDir))
                    {
                        bool started = false;
                        string startupError = null;

                        Thread worker = new Thread(() =>
                        {
                            try
                            {
                                if (!File.Exists(_jarPath))
                                {
                                    startupError = "Application JAR not found at:\n" + _jarPath;
                                    return;
                                }

                                if (!File.Exists(_javawExe))
                                {
                                    startupError = "Bundled Java runtime not found at:\n" + _javawExe;
                                    return;
                                }

                                string startupLogPath = Path.Combine(_logsDir, "server-startup.log");

                                ProcessStartInfo psi = new ProcessStartInfo();
                                psi.FileName = _javawExe;
                                psi.Arguments = "-Dfile.encoding=UTF-8 -jar \"" + _jarPath + "\"";
                                psi.WorkingDirectory = _appDir;
                                psi.UseShellExecute = false;
                                psi.CreateNoWindow = true;

                                // Set environment variables
                                string libreofficeProgram = Path.Combine(_rootDir, @"libreoffice\program");
                                string tesseractDir = Path.Combine(_rootDir, "tesseract");
                                string qpdfBin = Path.Combine(_rootDir, @"qpdf\bin");
                                string tessdataDir = Path.Combine(tesseractDir, "tessdata");

                                string customPath = _jreBin + ";" + libreofficeProgram + ";" + tesseractDir + ";" + qpdfBin + ";";
                                string currentPath = Environment.GetEnvironmentVariable("PATH") ?? "";
                                psi.EnvironmentVariables["PATH"] = customPath + currentPath;
                                psi.EnvironmentVariables["TESSDATA_PREFIX"] = tessdataDir;

                                javaProcess = new Process();
                                javaProcess.StartInfo = psi;
                                javaProcess.Start();

                                // Wait for backend to be ready (up to 60s)
                                for (int i = 0; i < 120; i++)
                                {
                                    Thread.Sleep(500);

                                    if (javaProcess.HasExited)
                                    {
                                        string logContent = "";
                                        if (File.Exists(startupLogPath))
                                        {
                                            try { logContent = File.ReadAllText(startupLogPath); } catch { }
                                        }
                                        startupError = "The Stirling PDF backend server terminated unexpectedly with exit code " + javaProcess.ExitCode + ".\n\n" +
                                                       (string.IsNullOrEmpty(logContent) ? "Please check logs in:\n" + _logsDir : logContent);
                                        return;
                                    }

                                    if (IsBackendReady())
                                    {
                                        started = true;
                                        return;
                                    }
                                }

                                startupError = "Stirling PDF server timed out while starting.\nPlease check logs in:\n" + _logsDir;
                            }
                            catch (Exception ex)
                            {
                                startupError = "Failed to launch Stirling PDF backend:\n" + ex.Message;
                            }
                            finally
                            {
                                try { splash.Invoke(new Action(() => splash.Close())); } catch { }
                            }
                        });

                        worker.IsBackground = true;
                        worker.Start();

                        Application.Run(splash);

                        if (!started)
                        {
                            if (startupError != null)
                            {
                                MessageBox.Show(startupError, "Stirling PDF Startup Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            }
                            CleanupProcess(javaProcess);
                            return;
                        }
                    }
                }

                // Launch the standalone App Window
                LaunchAppWindow();

                // Run in System Tray so the background server stays alive
                TrayApplicationContext trayContext = new TrayApplicationContext(javaProcess, _rootDir, _logsDir);
                Application.Run(trayContext);
            }
        }

        public static bool IsBackendReady()
        {
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create("http://localhost:8080/api/v1/info/status");
                req.Timeout = 1200;
                req.Method = "GET";
                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                {
                    return resp.StatusCode == HttpStatusCode.OK;
                }
            }
            catch
            {
                return false;
            }
        }

        public static void LaunchAppWindow()
        {
            string edgePath = FindBrowserExecutable();

            if (!string.IsNullOrEmpty(edgePath) && File.Exists(edgePath))
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = edgePath;
                    psi.Arguments = "--app=http://localhost:8080/ --window-size=1280,850";
                    psi.UseShellExecute = false;
                    Process.Start(psi);
                    return;
                }
                catch { }
            }

            // Fallback: Default Browser
            try
            {
                Process.Start("http://localhost:8080/");
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not open web interface:\n" + ex.Message, "Stirling PDF", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static string FindBrowserExecutable()
        {
            // 1. Microsoft Edge
            string[] edgeCandidates = new string[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\Edge\Application\msedge.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\Edge\Application\msedge.exe")
            };
            foreach (string candidate in edgeCandidates)
            {
                if (File.Exists(candidate)) return candidate;
            }

            // 2. Google Chrome
            string[] chromeCandidates = new string[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Google\Chrome\Application\chrome.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Google\Chrome\Application\chrome.exe")
            };
            foreach (string candidate in chromeCandidates)
            {
                if (File.Exists(candidate)) return candidate;
            }

            return null;
        }

        public static void CleanupProcess(Process proc)
        {
            if (proc != null && !proc.HasExited)
            {
                try
                {
                    Process killProc = Process.Start(new ProcessStartInfo
                    {
                        FileName = "taskkill",
                        Arguments = "/F /T /PID " + proc.Id,
                        CreateNoWindow = true,
                        UseShellExecute = false
                    });
                    if (killProc != null)
                    {
                        killProc.WaitForExit(3000);
                    }
                }
                catch { }

                try
                {
                    if (!proc.HasExited)
                    {
                        proc.Kill();
                    }
                }
                catch { }
            }
        }
    }

    class TrayApplicationContext : ApplicationContext
    {
        private NotifyIcon _trayIcon;
        private ContextMenuStrip _contextMenu;
        private Process _javaProcess;

        public TrayApplicationContext(Process javaProcess, string rootDir, string logsDir)
        {
            _javaProcess = javaProcess;

            _contextMenu = new ContextMenuStrip();

            ToolStripMenuItem itemOpen = new ToolStripMenuItem("Open Stirling PDF");
            itemOpen.Font = new Font(itemOpen.Font, FontStyle.Bold);
            itemOpen.Click += (s, e) => Program.LaunchAppWindow();
            _contextMenu.Items.Add(itemOpen);

            ToolStripMenuItem itemBrowser = new ToolStripMenuItem("Open in Default Browser");
            itemBrowser.Click += (s, e) =>
            {
                try { Process.Start("http://localhost:8080/"); } catch { }
            };
            _contextMenu.Items.Add(itemBrowser);

            ToolStripMenuItem itemLogs = new ToolStripMenuItem("View Logs");
            itemLogs.Click += (s, e) =>
            {
                try { Process.Start("explorer.exe", logsDir); } catch { }
            };
            _contextMenu.Items.Add(itemLogs);

            _contextMenu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem itemExit = new ToolStripMenuItem("Exit Stirling PDF");
            itemExit.Click += (s, e) => ExitApp();
            _contextMenu.Items.Add(itemExit);

            _trayIcon = new NotifyIcon();
            _trayIcon.Text = "Stirling PDF (Running)";
            _trayIcon.ContextMenuStrip = _contextMenu;
            _trayIcon.Visible = true;

            string iconPath = Path.Combine(rootDir, @"app\icon.ico");
            if (File.Exists(iconPath))
            {
                try { _trayIcon.Icon = new Icon(iconPath); } catch { }
            }
            else
            {
                _trayIcon.Icon = SystemIcons.Application;
            }

            _trayIcon.DoubleClick += (s, e) => Program.LaunchAppWindow();

            SystemEvents.SessionEnding += (s, e) => ExitApp();
            Application.ApplicationExit += (s, e) => ExitApp();
        }

        private void ExitApp()
        {
            if (_trayIcon != null)
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
                _trayIcon = null;
            }
            Program.CleanupProcess(_javaProcess);
            Application.Exit();
        }
    }

    class SplashScreen : Form
    {
        public SplashScreen(string rootDir)
        {
            this.Text = "Stirling PDF";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.ClientSize = new Size(380, 130);
            this.BackColor = Color.White;

            string iconPath = Path.Combine(rootDir, @"app\icon.ico");
            if (File.Exists(iconPath))
            {
                try { this.Icon = new Icon(iconPath); } catch { }
            }

            Label lblTitle = new Label();
            lblTitle.Text = "Stirling PDF";
            lblTitle.Font = new Font("Segoe UI", 13F, FontStyle.Bold);
            lblTitle.Location = new Point(24, 20);
            lblTitle.AutoSize = true;
            lblTitle.ForeColor = Color.FromArgb(30, 30, 30);
            this.Controls.Add(lblTitle);

            Label lblSubtitle = new Label();
            lblSubtitle.Text = "Starting local backend services, please wait...";
            lblSubtitle.Font = new Font("Segoe UI", 9F);
            lblSubtitle.Location = new Point(25, 48);
            lblSubtitle.AutoSize = true;
            lblSubtitle.ForeColor = Color.FromArgb(100, 100, 100);
            this.Controls.Add(lblSubtitle);

            ProgressBar pb = new ProgressBar();
            pb.Style = ProgressBarStyle.Marquee;
            pb.MarqueeAnimationSpeed = 30;
            pb.Location = new Point(25, 80);
            pb.Size = new Size(330, 18);
            this.Controls.Add(pb);
        }
    }
}
