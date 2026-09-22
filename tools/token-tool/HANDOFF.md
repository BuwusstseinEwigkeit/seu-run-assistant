# 交接提示词：微信小程序 Token 提取工具合并

> **用法**：把本文档全文（或从「## 0」开始的部分）粘贴给接收方 AI，它包含完整的任务描述、接口契约、实现要点和限制条件，可独立完成合并，无需额外上下文。
>
> **本文档不含任何 token / 密钥 / 账号**。粘贴前请确认你没有手动加进去。

---

## 0. 你的任务

你收到一个**已经跑通并验证过的 Windows 小工具**，用途是：在不开任何代理、不装证书、不修改系统设置的条件下，从微信小程序的进程内存中提取它正在使用的 Bearer token（JWT）。

请你把它**合并进我的项目**。当前合并目标：

- 目标项目：`BuwusstseinEwigkeit/seu-run-assistant`（本机路径：`D:\Vibe Coding\seu-run-assistant`）
- 期望形态：仓库内 `tools/token-tool` 的独立 Windows CLI / 双击本地桥接服务；网页按钮通过 `127.0.0.1` 请求扫描结果并自动回填，桥接服务同时复制一份到剪贴板作为备用
- 必须保留的能力：命令行参数、打码输出、剪贴板复制、循环扫描
- 允许的改动：重写语言、拆分模块、增加测试

如果你的实现语言不是 PowerShell，请参照「## 3 技术实现」用目标语言重新实现，**语义必须等价**。

---

## 1. 交付物清单

```
tools/token-tool/
├── scan_token.ps1     # 核心工具：纯 PowerShell + 内联 C#（P/Invoke），零第三方依赖
├── bridge_server.ps1  # 127.0.0.1 本地桥接：网页按钮触发扫描并回填 Token
├── get-token.bat      # 双击入口：启动 bridge_server.ps1
└── HANDOFF.md         # 本文档
```

**运行环境**：Windows 10/11。只需系统自带的 PowerShell 5.1（PowerShell 7 亦兼容）。
**不需要**：Python、Node、.NET SDK、管理员权限、任何第三方库、任何外网访问。桥接服务只监听 `127.0.0.1:17864`。

---

## 2. CLI 接口契约

```
scan_token.ps1 [参数]
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `-Proc` | string[] | `WeChatAppEx, Weixin, WeChat` | 目标进程名，可多个。覆盖微信 3.x（`WeChat.exe`）与 4.x（`Weixin.exe` + `WeChatAppEx.exe`） |
| `-Prefix` | string | `eyJ` | 内存搜索前缀。JWT 固定以 `eyJ` 开头；非 JWT 平台改为头名，如 `Blade-Auth`、`Authorization`、`satoken`、`X-Access-Token` |
| `-Full` | switch | off | 显示完整 token。默认打码：前 28 字符 + 12 个 `*` + 后 6 字符 + 长度 |
| `-Copy` | switch | off | 命中后把**完整** token 写入剪贴板，并立即结束扫描 |
| `-Library` | switch | off | 仅加载内存扫描类，供本地桥接脚本调用，不执行命令行扫描 |
| `-Loop` | int | 1 | 循环扫描轮数。配合 `-Interval` 实现"边操作小程序边抓" |
| `-Interval` | int | 2 | 每轮间隔秒数 |

**输出样例**（打码模式）：

```
########## 第 1 / 15 轮（17 个进程）##########

[命中 #1]  PID 80052  第 1 轮
  上文: ...Content-Encoding: br.............Blade-Auth: bearer 
  >>> TOKEN: <前28字符>************<后6字符>  (长度 539)
  [√] 完整 token 已复制到剪贴板

--- 扫描结束，共 1 个唯一 JWT ---
```

**约定的内部返回格式**（C# → PowerShell 之间）：

```
token + (char)1 + 上下文
```

⚠️ **不要用 `` 转义写法**。实测某些写文件环节会把转义序列吞掉，导致 token 与上下文粘连，剪贴板里拿到脏数据。用 `((char)1).ToString()` 这类无转义构造。

**退出码**：`0` 正常（含"未命中"）；`1` 一个目标进程都没找到。

---

## 3. 技术实现要点

### 3.1 为什么可行
token 在拼进 HTTP 请求头的那一刻，必然是内存里的一个明文 ASCII 字符串（如 `Blade-Auth: bearer eyJ...`）。所以只要进程还活着且发过请求，就能从它内存里读出来。

这条路径**不做中间人**，因此：
- 不需要 Charles/Fiddler/Proxifier
- 不需要安装根证书、不需要改系统代理、不需要改注册表
- **完全不受 SSL Pinning 影响**（Pinning 防的是假证书，而这里根本没碰 TLS）

### 3.2 核心算法（伪代码）

```
for each target pid:
    h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, pid)
    addr = 0
    while VirtualQueryEx(h, addr, &mbi) != 0:
        if mbi.State == MEM_COMMIT
           and not (mbi.Protect & PAGE_GUARD)
           and not (mbi.Protect & PAGE_NOACCESS)
           and mbi.Protect in {READONLY, READWRITE, EXECUTE_READ, EXECUTE_READWRITE}:
            for each 4MB chunk of region (cap 256MB per region):
                ReadProcessMemory(chunk -> buf)
                搜索 buf 中的 ASCII 前缀
                命中后向后提取连续 token 字符 [0-9A-Za-z._\-+=]
                校验：长度 >= 80 且以 '.' 分割恰好 3 段   ← JWT 结构
                取命中点前 200 字节，把可打印字符留作"上下文"
                去重（HashSet）
        addr = mbi.BaseAddress + mbi.RegionSize
```

### 3.3 两个必须注意的结构细节

**① `MEMORY_BASIC_INFORMATION` 的 x64 布局**

```
PVOID  BaseAddress;        // 8
PVOID  AllocationBase;     // 8
DWORD  AllocationProtect;  // 4
                           // ← 4 字节填充（Win10+ 此处是 WORD PartitionId）
SIZE_T RegionSize;         // 8
DWORD  State;              // 4
DWORD  Protect;            // 4
DWORD  Type;               // 4
```

用 `[StructLayout(LayoutKind.Sequential)]` 让运行时自然对齐即可。**不要手写偏移量**——填充字节恰好落在 `PartitionId` 位置，顺序布局天然正确。

**② PowerShell 文件编码（最容易翻车的地方）**

| 文件 | 必需编码 | 原因 |
|---|---|---|
| `.ps1` | **UTF-8 with BOM** | PowerShell 5.1 对无 BOM 的 UTF-8 文件**按 GBK 解码**。如果脚本里有中文注释/字符串，会被解码成乱码并撕裂引号，报 `字符串缺少终止符` 之类的解析错误。**如果你用工具重写这个 .ps1，务必保证 BOM 还在**，否则整个脚本会崩。 |
| `.bat` | ASCII only + **CRLF** | `cmd.exe` 需要 CRLF 换行，且按当前代码页（简体中文系统为 GBK）解析文件字节。UTF-8 中文 + LF 会导致命令行被切碎（实测出现 `'wershell' 不是内部或外部命令` 这种把 `powershell` 咬掉两个字符的错误）。bat 只用 ASCII，最稳。 |

---

## 4. 已验证结果（可复现）

**环境**：Windows 11 Home China · 微信 4.x（`Weixin.exe` + `WeChatAppEx.exe`）· PowerShell 5.1 · 未安装 Python
**目标**：某高校 BladeX/SpringBlade 后端，业务请求头为 `Blade-Auth: bearer <JWT>`

| 测试 | 命令 | 结果 |
|---|---|---|
| 1 · 基本扫描 | `scan_token.ps1 -Loop 2 -Interval 3` | ✅ 命中 1 个 JWT，长度 539，上下文显示 `Blade-Auth: bearer ` |
| 2 · 剪贴板管线 | `scan_token.ps1 -Copy` + `Get-Clipboard` 校验 | ✅ `eyJ` 开头、恰好 3 段、长度 539、判定 JWT = True |
| 3 · 双击入口 | `cmd /c get-token.bat` | ✅ 启动本地桥接服务；网页按钮触发扫描并自动回填 |

补充事实：
- 命中进程是 `WeChatAppEx.exe`（小程序进程，与 PID 无关，每次重启都会变）
- 网页只允许本地文件来源调用 `/scan`；桥接服务拒绝带有其他 Origin 的扫描请求。
- 桥接不会只依赖 `Blade-Auth` 文本是否紧挨 JWT；微信内存可能把请求头和 JWT 分开保存，因此还会解码 JWT payload，匹配 `iss=bladex.cn`、`aud=bladex` 或 `token_type=access_token + user_id`。
- 小程序的 appid 形如 `wx5da07e9f6f45cabf`（不影响本工具运行）
- **磁盘上找不到明文 token**：小程序 storage 是加密落盘的，`grep eyJ` 在 `applet\data`、`applet\local` 里零命中。所以"翻本地存储"这条路不通，只能走内存。

---

## 5. 已知限制与陷阱

1. **进程必须存活且发过请求**。小程序没打开、或打开后还没触发过任何请求时，内存里没有 token 字符串 → 扫描结果为 0。这不是 bug。
2. **可能被安全软件拦截**。读其他进程内存在 AV/EDR 眼里与凭证窃取工具的行为特征一致，可能被 Defender/360/火绒报毒或静默拦截。**不要在有安全管控的机器（学校机房、公司电脑）上运行。**
3. **只能拿到本机当前登录用户自己的 token**。它不是越权工具：在别人的机器/账号上运行，读到的也只是那个人的 token。
4. **JWT 校验偏严格**。当前用"长度≥80 且恰好 3 段"识别 JWT。若目标平台用不透明字符串（UUID、Sa-Token 值），会被过滤掉——此时需改用 `-Prefix` 搜头名，并放宽校验。
5. **只搜单字节 ASCII（存在盲区）**。V8 引擎对字符串有两种存储形式：纯 ASCII 的用单字节（one-byte string，能搜到）；一旦字符串曾包含非 ASCII 字符，会升级为 **UTF-16**（字节间夹 `00`），此时按 ASCII 搜 `eyJ` **会漏掉**。改进见「## 6」。
6. **性能**：单轮扫描 17 个进程、总内存数 GB，需数秒到数十秒。建议 `-Copy`（命中即退出）而不是增大 `-Loop`。
7. **token 会过期**。JWT 一般数小时，过期后需重新扫一次（或走「## 6」的登录接口方案）。

---

## 6. 建议的后续改进（按价值排序）

- [ ] **UTF-16LE 宽字符搜索**：把前缀构造成 `e\0y\0J\0` 再搜一遍，提取时按 2 字节步进。补齐限制 5 的盲区，改动小、收益高。
- [ ] **按网络连接定位 PID**：用 `Get-NetTCPConnection` 找出对目标 IP:443 有 ESTABLISHED 连接的进程，只扫它，避免盲扫全部进程。又快又准。
- [ ] **放宽 token 识别**：支持不透明 token（改为"命中前缀后提取连续 token 字符，长度≥20 即收"），并允许用户自定义正则。
- [ ] **与登录接口结合（最彻底）**：BladeX 的 `POST /api/blade-auth/oauth/token` 支持 `grant_type=password` 与 `refresh_token`。抓一次登录请求拿到 `Authorization: Basic <client_id:client_secret>` 后，即可纯 HTTP 换 token，**彻底不需要内存扫描、不需要小程序在运行**，配合 `refresh_token` 还能自动续期。
- [ ] **解析 `exp` 自动续期**：base64 解 JWT 第二段，到期前自动重取。

---

## 7. 使用边界（合并时必须原样保留在文档/注释中）

- 仅限**本人账号、本人设备**上的调试与学习用途
- **不得**用于他人设备、他人账号，**不得**用于绕过他人授权
- token 是敏感凭证：**不得**提交到代码仓库、**不得**写入日志、**不得**外传或分享
- 遵守目标平台的服务条款与你所在机构的网络使用规定
