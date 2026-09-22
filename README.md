# SEU Run Assistant

> 基于 [harkerhand/ML-SEU-Exercise-Helper](https://github.com/harkerhand/ML-SEU-Exercise-Helper) 改进的东南大学课外锻炼助手。
> 原版作者：[Midairlogn](https://github.com/midairlogn)，本版在其基础上进行了功能扩展和体验优化。遵循 [GPLv3 许可证](LICENSE)。

---

## 和原版相比，多了什么？

| 功能 | 原版 | 本版 |
|------|------|------|
| 单次提交跑步记录 | ✅ | ✅ |
| Token 认证 / 场地选择 | ✅ | ✅ |
| 手动设置起止时间 | ✅ | ✅ |
| 开始 / 结束照片上传 | ✅ | ✅ |
| **随机轨迹生成**（7 个场地，含边界检测） | ❌ | ✅ |
| **随机时间 + 配速 / 距离联动** | ❌ | ✅ |
| **批量提交**（按日期范围，可跳过周末） | ❌ | ✅ |
| **照片池**（批量模式随机取图） | ❌ | ✅ |
| **随机场地**（每天自动换场地） | ❌ | ✅ |
| **课表 CSV 导入 / 粘贴识别** | ❌ | ✅ |
| **导入后课表时间可直接修改** | ❌ | ✅ |
| **批量失败记录 + 重新提交失败日期** | ❌ | ✅ |
| **提交前本地校验**（Token 格式、时间范围、照片） | ❌ | ✅ |
| **结果反馈弹窗**（成功 / 失败 / 原因摘要） | ❌ | ✅ |
| **使用教程页**（含 Token 获取方法） | ❌ | ✅ |

简单说：原版是一个提交表单，本版是一套完整的批量锻炼记录工具。

---

### **🔥 可以补之前的跑步记录，也可以超前跑！**

---

## 快速开始

1. 直接用浏览器打开 `index.html`（推荐电脑端）
2. 按页面步骤操作即可

> **需要校园网**，在成功提示弹出前不要离开或关闭页面。

### Token获取说明
> 输入框可直接粘贴 `bearer [part1].[part2].[part3]` 的值，也兼容裸 JWT。实际发出的请求还需要另外两个头，见下方「接口协议」。

1. 双击 `tools/token-tool/get-token.bat` 启动本地桥接服务，并保持黑色窗口运行。网页出于浏览器安全限制不会自动执行 `.bat`。
2. 在微信中打开「东南大学体育管理 → 阳光跑」，进入会加载数据的页面。
3. 回到本页点击「从微信小程序提取 Token」，Token 会自动填入输入框；桥接服务同时复制一份到剪贴板作为备用。

### Windows 一键获取 Token（可选）

仓库内置了零第三方依赖的 Windows 辅助工具：[tools/token-tool](tools/token-tool)。它只用于本人账号、本人设备上的调试，通过读取正在运行的微信小程序进程内存查找 JWT，不修改系统代理、证书或注册表。桥接服务只监听 `127.0.0.1:17864`，不写入文件或日志。

1. 双击 `tools/token-tool/get-token.bat`，保持桥接窗口运行。
2. 在微信中打开「东南大学体育管理 → 阳光跑」，并进入一个会加载数据的页面。
3. 回到网页点击「从微信小程序提取 Token」；命中后会自动回填，剪贴板复制仅作为备用。

> Token 属于敏感凭证。工具默认只显示打码结果，不会写入磁盘；请勿提交、记录或分享完整 Token。详细接口、限制和测试记录见 [tools/token-tool/HANDOFF.md](tools/token-tool/HANDOFF.md)。

### 单次提交

1. 填入 Token
2. 选择场地
3. 点击「一键生成时间+轨迹」，或手动设置时间
4. 上传两张自拍照片（开始 / 结束）
5. 提交

> **时间、距离、配速三者是互相推导出来的，不会对不上。** 生成时先在 `[minPace, maxPace]` 里取一个配速，
> 由 `时长 = 距离 × 配速` 反推允许的距离区间（不低于 `standardKilometre`）并生成轨迹，再用轨迹的
> **实际长度**重算时长并夹进 `[minTime, maxTime]`，最后把开始时间安排在规则的起止时间内。
> 批量模式复用同一套逻辑。

### 同一天只跑一次

服务端同一天只计入一次，当天已有记录时（**哪怕那条是无效的**）再提交只会又得到一条无效记录。
所以页面在提交前会调 `getRecordByMonthOrWeek` 查当月记录：

- **单次提交**：命中当天已有记录 → 弹窗拦下，并显示那条记录的日期 / 场地 / 状态
- **批量提交**：跳过该日期，并在失败列表里注明原因，不会白跑完整流程（也不会逐条弹窗打断批量）

查询失败时（例如桥接窗口没开）只记日志、不阻断提交——读不到历史不应该挡住正常提交。

页面上另有一块 **「我的锻炼记录」** 折叠面板，展开后按月份拉取服务端记录并只读展示
（`✅` 有效 / `❌` 无效 / `⏳` 进行中），换月份或点「刷新」都会重新拉取。

### 批量提交

1. 切换到「批量上传」标签页
2. 填 Token → 选日期范围（可跳过周末）
3. 上传照片池（开始和结束各至少一张）
4. 开始批量提交

> 照片用自拍，人脸尽量占满画面，可以重复使用同一张。

### 模拟间隔

页面上有一个「模拟间隔（秒）」输入框，单次和批量共用同一个值，默认 **5 秒**：

- 它是「上传开始记录」与「上传结束记录」之间的等待
- 批量模式下，它同时也是每条记录之间的间隔
- **设为 0 表示完全不等**，提交最快

这段时间**不改变提交的数据**：`recordTime` / `startTime` / `endTime` 全部取自表单，而本工具本来就
支持补录任意日期，`create_time` 与 `startTime` 相差几十天是常态。所以它并不构成任何"反时间戳校验"，
保留一个小值只是让两条记录的建行时间不落在同一秒。

真正决定记录能否通过校验的是数据本身：轨迹点是否落在场地多边形内、里程与配速是否在规则范围内、
时长是否在 `minTime`–`maxTime` 之间、照片能否通过人脸核验，以及**同一天只能跑一次**。

![Screenshot-Main](screenshots/main-page.png)
![Screenshot-Success](screenshots/success.png)

---

## 接口协议（从微信小程序包还原）

本页面的请求格式与微信小程序「东南大学体育管理」（appid `wx5da07e9f6f45cabf`，版本 V2.1.7）一致。
下面的结论是解密本地小程序包（`%APPDATA%\Tencent\xwechat\radium\users\<user>\applet\packages\wx5da07e9f6f45cabf\41\*.wxapkg`）
读其源码得到的，不是猜测。

### 请求头

小程序所有接口都带这三个头，**并且从不发送 `Tenant-Id`**（租户由 Token 自身携带）：

```http
Authorization: Basic d2VjaGF0OndlY2hhdF9zZWNyZXQ=   # base64("wechat:wechat_secret")，OAuth 客户端凭据
blade-requested-with: BladeHttpRequest
Blade-Auth: bearer <JWT>
```

漏掉 `Authorization` 或 `blade-requested-with` 会被网关直接拒为 `401 请求未授权`，这与 Token 新旧、是否过期都无关。反过来，只发 `Blade-Auth` 是过去 401 的唯一原因。

### 为什么必须经过本地桥接服务

服务端**强制要求** `blade-requested-with`（上传接口还要求 `miniappversion`），但它的 CORS 白名单
`Access-Control-Allow-Headers` 里**这两个都不在**（只有 `X-Requested-With`）：

```text
Access-Control-Allow-Headers: X-Requested-With, Tenant-Id, Blade-Auth, Content-Type, Authorization, ...
```

后果是浏览器预检必然被拒，`fetch` 直接抛 `TypeError: Failed to fetch`。在真实 Chrome 里实测：

| 请求头 | 结果 |
|--------|------|
| `Authorization` + `Blade-Auth` | 401（预检通过，服务端拒绝） |
| `+ blade-requested-with` | Failed to fetch（预检被拒） |
| `Blade-Auth` + `Tenant-Id`（旧写法） | 401（预检通过） |
| `+ miniappversion` | Failed to fetch（预检被拒） |

`X-Requested-With: BladeHttpRequest`、query 参数等替代写法都试过，服务端只认
`blade-requested-with: BladeHttpRequest` 这个精确的头名和值。

小程序不受 CORS 约束所以一切正常，浏览器则**没有任何直连写法可行**。因此所有接口调用都改为经
`tools/token-tool/get-token.bat` 启动的本地桥接服务（`127.0.0.1:17864`）转发：桥接服务由本机发起
请求，可以把完整的请求头原样送出去。**提交前桥接窗口必须保持运行。**

### 接口路径

页面里的接口地址都指向 `ml_api_base_url`（桥接服务），由它转发到
`https://tyxsjpt.seu.edu.cn`；桥接只放行 `/api/` 开头的路径，且上游主机固定，不是开放代理。


| 用途 | 方法 | 路径 |
|------|------|------|
| 校验 Token / 取学生信息 | GET | `/api/blade-exercise/exerciseRecord/getStudentInfo` |
| 读规则与场地 | GET | `/api/blade-exercise/v2/exerciseRecord/listRule` |
| 上传开始照片 | POST | `/api/blade-exercise/exerciseRecord/uploadRecordImageStart` |
| 上传结束照片 | POST | `/api/blade-exercise/exerciseRecord/uploadRecordImageEnd` |
| 写开始记录 | POST | `/api/blade-exercise/v2/exerciseRecord/saveStartRecord` |
| 写结束记录 | POST | `/api/blade-exercise/v2/exerciseRecord/saveRecord` |

只有 `saveStartRecord` / `saveRecord` 在 `/v2` 前缀下，两个图片上传接口不在。

图片上传是 multipart，额外带 `miniappversion: V2.1.7`；不要手工设置 `Content-Type`，否则 boundary 会丢。

### 请求体加密

`saveStartRecord` 和 `saveRecord` 的请求体**必须加密**，明文 JSON 会被服务端拒绝（返回 `500 服务器异常`）：

```text
body = base64( AES-256-CBC( JSON.stringify(payload), key = aesKey, iv = aesKey 前 16 字节, PKCS7 ) )
Content-Type: text/plain
```

- `aesKey` = `q7znliW59ytgZ9reVofvVSUaf7ZMwyCt`
- **响应体同样是密文**，需要用同一密钥解密后再 `JSON.parse`，才能读到 `code` / `msg` / `data`
- 服务端异常时返回的是明文 JSON，所以解密要有回退分支

页面实现见 `index.html` 的 `ml_aes_encrypt` / `ml_aes_decrypt` / `ml_encrypted_post`：用的是浏览器原生 WebCrypto，与小程序使用的 crypto-js 等价，回归测试用固定密文向量逐字节校验。

### 场地表必须在运行时刷新

页面内置的 `ml_all_route_info` / `ml_student_route_all_info` 属于旧部署，里面的 ID 早已失效：

| | 内置（旧） | 服务端当前 |
|---|---|---|
| `rule_id` | `403640128840458519`、`402186368309502988` … | `2101919551519227905` |
| `plan_id` | `403640128840458727` … | `2100475362025676801` … |
| `route_rule` | `四牌楼校区` | `2026~2027学年1学期锻炼任务` |
| 场地名 | `小营田径场` | `四牌楼-四牌楼田径场` |
| 时间窗 | `06:00`–`22:00` | `06:00:00`–`22:30:00` |

两代 ID 完全不同。用失效的 `rule_id` 调 `saveStartRecord`，服务端查不到规则会直接抛
`500 服务器异常`（用一个不存在的 ruleId 可以稳定复现）。

所以页面在**校验 Token 后**和**提交前**各调一次 `listRule`，用返回值重建
`ml_all_route_info`、`ml_student_route_all_info` 和两个场地下拉框；轨迹取服务端的
`latlngs`，里程取 `max(多边形周长, 官方 routeKilometre)`。

### 开始记录的 payload

小程序在调用 `saveStartRecord` 前会 `delete exerciseObj.strLatitudeLongitude`，因此该字段不需要发送；其余字段与小程序 `exerciseObj` 对齐（含 `id` / `nowStatus` / `userId`）。

---

## 支持的场地（7 个）

- 橘园田径场
- 桃园田径场
- 梅园田径场
- 丁家桥体育场
- 四牌楼体育场
- 小营田径场
- 无锡国际校区体育馆

---

## 声明

- 本项目基于 [harkerhand/ML-SEU-Exercise-Helper](https://github.com/harkerhand/ML-SEU-Exercise-Helper) 开发，原版作者 [Midairlogn](https://github.com/midairlogn)
- 遵循 [GPLv3 许可](LICENSE)：可自由使用、修改、分发，但修改后的版本必须同样在 GPLv3 下开源
- 反对任何形式的商业化使用（收费服务、出售代码等）

**软件按"原样"提供，不附带任何担保。作者不对因使用本软件产生的任何直接或间接损失、数据丢失、法律责任或其他风险承担责任。**

**用户应对其上传的数据承担全部责任，确保其符合实际情况。**
