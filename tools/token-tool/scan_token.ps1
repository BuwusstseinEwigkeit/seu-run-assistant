<#
  scan_token.ps1 —— 直接在微信小程序进程内存里搜 Bearer / JWT token
  不需要代理、不需要装证书、不受 SSL Pinning 影响、不装任何第三方工具。

  用法（PowerShell 里执行）：
    powershell -ExecutionPolicy Bypass -File .\scan_token.ps1
    powershell -ExecutionPolicy Bypass -File .\scan_token.ps1 -Full -Copy
    powershell -ExecutionPolicy Bypass -File .\scan_token.ps1 -Loop 30 -Interval 2
    powershell -ExecutionPolicy Bypass -File .\scan_token.ps1 -Proc WeChat

  参数：
    -Proc      进程名，可传多个。默认同时扫 WeChatAppEx / Weixin / WeChat，
               覆盖微信 3.x（WeChat.exe）和 4.x（Weixin.exe + WeChatAppEx.exe）
    -Prefix    搜索前缀，默认 eyJ（JWT 的 Base64 开头）。
               非 JWT 的平台改搜头名，如 -Prefix "Blade-Auth" / "Authorization" / "satoken"
    -Full      显示完整 token；默认打码，只显示头尾
    -Copy      扫到后自动把完整 token 放进剪贴板，并立即结束
    -Loop      循环扫描轮数（默认 1）。设成 30，一边点小程序一边扫，
               才能抓到"请求发出瞬间才存在"的 token 字符串
    -Interval  每轮间隔秒数（默认 2）
#>
param(
    [string[]]$Proc = @('WeChatAppEx','Weixin','WeChat'),
    [string]$Prefix = 'eyJ',
    [switch]$Full,
    [switch]$Copy,
    [switch]$Library,
    [int]$Loop      = 1,
    [int]$Interval  = 2
)

$src = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;

public class MemScan
{
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MEMORY_BASIC_INFORMATION mbi, IntPtr len);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORY_BASIC_INFORMATION
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint   AllocationProtect;
        public IntPtr RegionSize;
        public uint   State;
        public uint   Protect;
        public uint   Type;
    }

    const uint PROCESS_QUERY_INFORMATION = 0x0400;
    const uint PROCESS_VM_READ           = 0x0010;
    const uint MEM_COMMIT                = 0x1000;
    const uint PAGE_GUARD                = 0x100;
    const uint PAGE_NOACCESS             = 0x01;

    static bool IsTokenChar(byte b)
    {
        return (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
            || b == '.' || b == '_' || b == '-' || b == '+' || b == '=';
    }

    /// 返回 null = 打不开进程；否则返回 "token上文"
    public static List<string> Scan(int pid, string prefix)
    {
        IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) return null;

        var results = new List<string>();
        var seen    = new HashSet<string>();
        byte[] pat  = Encoding.ASCII.GetBytes(prefix);
        const int CHUNK = 4 * 1024 * 1024;
        const long MAX_REGION = 256L * 1024 * 1024;
        byte[] buf  = new byte[CHUNK];
        MEMORY_BASIC_INFORMATION mbi;
        long mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));

        try
        {
            long addr = 0;
            while (VirtualQueryEx(h, (IntPtr)addr, out mbi, (IntPtr)mbiSize) != IntPtr.Zero)
            {
                long baseAddr = mbi.BaseAddress.ToInt64();
                long size     = mbi.RegionSize.ToInt64();
                if (size <= 0) break;

                bool readable = mbi.State == MEM_COMMIT
                             && (mbi.Protect & PAGE_GUARD) == 0
                             && (mbi.Protect & PAGE_NOACCESS) == 0
                             && ((mbi.Protect & 0x02) != 0 || (mbi.Protect & 0x04) != 0
                              || (mbi.Protect & 0x20) != 0 || (mbi.Protect & 0x40) != 0);

                if (readable)
                {
                    long limit = Math.Min(size, MAX_REGION);
                    long off = 0;
                    while (off < limit)
                    {
                        int want = (int)Math.Min(CHUNK, limit - off);
                        IntPtr got;
                        if (ReadProcessMemory(h, (IntPtr)(baseAddr + off), buf, (IntPtr)want, out got))
                        {
                            int n = got.ToInt32();
                            for (int i = 0; i + pat.Length <= n; i++)
                            {
                                if (buf[i] != pat[0]) continue;
                                bool ok = true;
                                for (int k = 1; k < pat.Length; k++)
                                    if (buf[i + k] != pat[k]) { ok = false; break; }
                                if (!ok) continue;

                                int j = i;
                                var sb = new StringBuilder();
                                while (j < n && sb.Length < 4096 && IsTokenChar(buf[j]))
                                { sb.Append((char)buf[j]); j++; }

                                string tok = sb.ToString();
                                if (tok.Length >= 80 && tok.Split('.').Length == 3 && seen.Add(tok))
                                {
                                    int cs = (int)Math.Max(0, i - 200);
                                    var cb = new StringBuilder();
                                    for (int x = cs; x < i; x++)
                                        cb.Append(buf[x] >= 32 && buf[x] < 127 ? (char)buf[x] : '.');
                                    results.Add(tok + ((char)1).ToString() + cb.ToString());
                                }
                                i = j;
                            }

                            // Chromium/V8 frequently stores JavaScript strings
                            // as UTF-16. Scan the same allocation for the wide
                            // form (e\0y\0J\0...) so a fresh token in a newer
                            // renderer is not missed while an older ASCII copy
                            // is still present in another renderer.
                            for (int i = 0; i + (pat.Length * 2) <= n; i++)
                            {
                                if (buf[i] != pat[0] || buf[i + 1] != 0) continue;
                                bool ok = true;
                                for (int k = 1; k < pat.Length; k++)
                                    if (buf[i + (k * 2)] != pat[k] || buf[i + (k * 2) + 1] != 0)
                                    { ok = false; break; }
                                if (!ok) continue;

                                int j = i;
                                var sb = new StringBuilder();
                                while (j + 1 < n && sb.Length < 4096 && buf[j + 1] == 0 && IsTokenChar(buf[j]))
                                { sb.Append((char)buf[j]); j += 2; }

                                string tok = sb.ToString();
                                if (tok.Length >= 80 && tok.Split('.').Length == 3 && seen.Add(tok))
                                {
                                    int cs = (int)Math.Max(0, i - 200);
                                    var cb = new StringBuilder();
                                    for (int x = cs; x < i; x++)
                                        cb.Append(buf[x] >= 32 && buf[x] < 127 ? (char)buf[x] : '.');
                                    results.Add(tok + ((char)1).ToString() + cb.ToString());
                                }
                                i = j;
                            }
                        }
                        off += want;
                    }
                }
                long next = baseAddr + size;
                if (next <= addr) break;
                addr = next;
            }
        }
        finally { CloseHandle(h); }

        return results;
    }
}
'@
Add-Type -TypeDefinition $src

if ($Library) { return }

$seenAll = New-Object System.Collections.Generic.HashSet[string]
$total   = 0

for ($round = 1; $round -le $Loop; $round++) {
    $targets = @(Get-Process -Name $Proc -ErrorAction SilentlyContinue)
    if ($targets.Count -eq 0) {
        Write-Host "[!] 没找到进程 $($Proc -join ' / ') —— 先打开微信小程序，再运行。" -ForegroundColor Yellow
        exit 1
    }

    if ($Loop -gt 1) {
        Write-Host "`n########## 第 $round / $Loop 轮（$($targets.Count) 个进程）##########" -ForegroundColor DarkCyan
    }

    foreach ($p in $targets) {
        if ($Loop -eq 1) {
            Write-Host "`n=== PID $($p.Id)  $($p.ProcessName)  内存 $([math]::Round($p.WorkingSet64/1MB)) MB ===" -ForegroundColor Cyan
        }
        $res = [MemScan]::Scan($p.Id, $Prefix)
        if ($null -eq $res) {
            Write-Host "  PID $($p.Id) 打不开（用管理员 PowerShell 再试）" -ForegroundColor Yellow
            continue
        }
        if ($res.Count -eq 0) { continue }

        foreach ($r in $res) {
            $parts = $r.Split([char]1)
            $tok = $parts[0]
            if (-not $seenAll.Add($tok)) { continue }   # 跨轮去重
            $total++
            $ctx   = if ($parts.Length -gt 1) { $parts[1] } else { '' }
            $shown = if ($Full) { $tok }
                     else { $tok.Substring(0,28) + ('*' * 12) + $tok.Substring($tok.Length - 6) + "  (长度 $($tok.Length))" }
            Write-Host "`n[命中 #$total]  PID $($p.Id)  第 $round 轮" -ForegroundColor Green
            Write-Host "  上文: ...$ctx"
            Write-Host "  >>> TOKEN: $shown" -ForegroundColor Green

            if ($Copy) {
                try {
                    Set-Clipboard -Value $tok
                    Write-Host "  [√] 完整 token 已复制到剪贴板" -ForegroundColor Magenta
                } catch {
                    Write-Host "  [!] 复制到剪贴板失败：$_" -ForegroundColor Yellow
                }
            }
        }
    }

    if ($Copy -and $total -gt 0) { break }          # 拿到就收工
    if ($round -lt $Loop) { Start-Sleep -Seconds $Interval }
}

Write-Host "`n--- 扫描结束，共 $total 个唯一 JWT ---" -ForegroundColor Cyan
if ($total -eq 0) {
    Write-Host "没搜到。检查顺序：" -ForegroundColor Yellow
    Write-Host "  1) 小程序是否已打开，并进入过会加载数据的页面（要有请求发生）" -ForegroundColor Yellow
    Write-Host "  2) 换进程名试：-Proc Weixin / WeChat / WeChatAppEx" -ForegroundColor Yellow
    Write-Host "  3) 非 JWT 平台换前缀：-Prefix 'Blade-Auth' / 'Authorization' / 'satoken'" -ForegroundColor Yellow
    Write-Host "  4) 循环扫描：-Loop 30 -Interval 2（一边点小程序一边扫）" -ForegroundColor Yellow
}

