# 接口协议（开发者笔记）

> 本文件记录本工具与微信小程序「东南大学体育管理」对接的底层细节，供二次开发 / 排查使用。
> 普通用户不需要读这个，看 [README.md](README.md) 即可。

本页面的请求格式与微信小程序「东南大学体育管理」（appid `wx5da07e9f6f45cabf`，版本 V2.1.7）一致。
下面的结论是解密本地小程序包（`%APPDATA%\Tencent\xwechat\radium\users\<user>\applet\packages\wx5da07e9f6f45cabf\41\*.wxapkg`）
读其源码得到的，不是猜测。

## 请求头

小程序所有接口都带这三个头，**并且从不发送 `Tenant-Id`**（租户由 Token 自身携带）：

```http
Authorization: Basic d2VjaGF0OndlY2hhdF9zZWNyZXQ=   # base64("wechat:wechat_secret")，OAuth 客户端凭据
blade-requested-with: BladeHttpRequest
Blade-Auth: bearer <JWT>
```

漏掉 `Authorization` 或 `blade-requested-with` 会被网关直接拒为 `401 请求未授权`，这与 Token 新旧、是否过期都无关。反过来，只发 `Blade-Auth` 是过去 401 的唯一原因。

## 为什么必须经过本地桥接服务

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

## 接口路径

页面里的接口地址都指向桥接服务，由它转发到 `https://tyxsjpt.seu.edu.cn`；
桥接只放行 `/api/` 开头的路径，且上游主机固定，不是开放代理。

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

## 请求体加密

`saveStartRecord` 和 `saveRecord` 的请求体**必须加密**，明文 JSON 会被服务端拒绝（返回 `500 服务器异常`）：

```text
body = base64( AES-256-CBC( JSON.stringify(payload), key = aesKey, iv = aesKey 前 16 字节, PKCS7 ) )
Content-Type: text/plain
```

- `aesKey` = `q7znliW59ytgZ9reVofvVSUaf7ZMwyCt`
- **响应体同样是密文**，需要用同一密钥解密后再 `JSON.parse`，才能读到 `code` / `msg` / `data`
- 服务端异常时返回的是明文 JSON，所以解密要有回退分支

页面实现见 `index.html` 的 `ml_aes_encrypt` / `ml_aes_decrypt` / `ml_encrypted_post`：用的是浏览器原生 WebCrypto，与小程序使用的 crypto-js 等价，回归测试用固定密文向量逐字节校验。

## 场地表必须在运行时刷新

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

所以页面在**校验 Token 后**和**提交前**各调一次 `listRule`，用返回值重建场地表；轨迹取服务端的
`latlngs`，里程取 `max(多边形周长, 官方 routeKilometre)`。

## 开始记录的 payload

小程序在调用 `saveStartRecord` 前会 `delete exerciseObj.strLatitudeLongitude`，因此该字段不需要发送；其余字段与小程序 `exerciseObj` 对齐（含 `id` / `nowStatus` / `userId`）。
