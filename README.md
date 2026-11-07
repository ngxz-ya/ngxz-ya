# ngxz-ya｜通用机械软件 AI 连接与经验复用工具包

把两行交给具备本机文件读取、命令执行权限的 AI Agent：

```text
https://github.com/ngxz-ya/ngxz-ya
连接我本机的〈软件名称〉
```

Agent按包内说明检查环境、选择适配器、尝试支持的操作，再读取实际结果核对。做过的任务可以留下条件、参数、方法和证据，下次先查再用。

## 核心功能

- **不同AI，同一入口。** 不绑定模型服务商，本地模型也可调用接口；纯本地模型自主完成整套任务尚未验收。
- **软件适配器可扩展。** 支持范围和版本见`适配器/索引.json`。没有适配器就明确UNSUPPORTED，不承诺任意软件都能连接。
- **操作后检查结果。** 参考能力会保存模型，由独立软件进程重开测量；发命令成功不等于工程验收成功。
- **积累本机经验。** 保存目标、条件、版本、参数、步骤、验证、恢复和适用边界。新任务能够检索、全文读取并复核旧方法；不同软件分槽。
- **真实工作可查看。** 原YA面板展示任务、经验、实际事件和耗时。Token有来源才显示，无源“未统计”，无公平对照“待对照”。

出厂经验和知识为空，保留查询、保存及扩展机制。私人经验、任务、模型和Token源日志默认留在使用者本机，不随项目上传。

## 真实能力边界

参考适配器在特定版本完成过真实参数实体创建、尺寸修改、保存、独立回读，以及第二任务检索、读取旧经验并关联成功结果。准确产品、版本和限制保留在适配器索引及NOTICE，不能通过删名字隐藏兼容性。

当前返回`VERIFIED_BATCH`、`live_link=false`，不是常驻实时连接。动作仍由固定参考执行器提供，尚未证明经验正文能够自主规划任意任务，也未证明节省多少Token。其他软件、版本、任务和Agent须分别验证。

维护者已将自己有权发布的项目代码按[MIT License](LICENSE)开源，署名ngxz-ya；允许免费使用、修改、二次开发及合法商用，须保留版权和许可声明。MIT不授予厂商软件或SDK许可，不覆盖427张授权未明卡及私人数据，范围见NOTICE.md。

MIT授权不等于远端历史替换批准。本文档和本地测试不证明当前远端已经更新；Git地址接入是否通过，以从实际提交下载后的独立验收记录为准。

## 环境要求

当前验证环境为Windows、Windows PowerShell 5.1 Desktop、.NET Framework及桌面组件。PowerShell 7、Linux、macOS尚未验证。目标软件须合法安装，并具有所需功能和接口使用权限。本包不安装商业软件、不捆绑SDK二进制、不绕过授权。

Agent只定位用户点名的软件，不扫描别的工程目录或借用旧日志。先读AGENTS.md。

## Agent执行流程

1. 从指定仓库下载新ZIP，记录实际提交，解压到不存在的新目录，不能覆盖旧文件。维护者内部测试则以唯一正式源码为来源。
2. 读本次README和AGENTS，检查打包器、允许清单、连接入口及适配器索引。缺文件就报告旧版或不完整，不能从其他项目补齐。
3. 从下载根生成新TestCopy，再进入副本运行。下载根无需已有包信息即可打包；运行标记只由打包器生成，禁止手工补成功标记。

下列命令由Agent执行，目标存在就换一个新名称：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\准备隔离包.ps1" -Destination "..\ngxz-ya-test" -Profile TestCopy
Set-Location -LiteralPath "..\ngxz-ya-test"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接软件.ps1" -Software "<软件名称>" -Action Check
```

READY只证明发现了适配器、版本和依赖，不代表已连接或授权已审查。合法使用前提满足后，再执行明确支持的参考任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接软件.ps1" -Software "<软件名称>" -Action Test -Length 20
powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接软件.ps1" -Software "<软件名称>" -Action Test -Length 35
```

Length只适用于当前参考实体，宽12 mm、高14 mm，不是任意软件的统一建模协议。Test自动包级安装，新建独立文档、修改、保存、独立回读并记录经验。

## 安装、面板与卸载

仅在TestCopy内执行，不能运行正式源码或下载根：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\安装卸载\安装.ps1" -PackageOnly
powershell -NoProfile -ExecutionPolicy Bypass -File ".\YA插件\本包命令.ps1" self_check
powershell -NoProfile -STA -ExecutionPolicy Bypass -File ".\YA插件\ya_hud.ps1"
```

也可双击`YA插件/打开YA插件.bat`。安装、HUD和工作区按包路径标识分开；原始证据位置由实际结果返回，批处理退出后显示“未连接”是正确状态。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\安装卸载\卸载.ps1" -PackageOnly
```

卸载仅处理本包安装，不删除经验、模型、原始事件或其他包。

## 经验、知识与统计

任务先`exp_search`/`exp_recall`，命中再`exp_get`；核对软件、接口版本、条件后执行并独立验证。按`连接教练/方法记录示例.json`记录方法，用`exp_done record=文件`保存。示例不是成功经验，脚本附件不能代替方法。

`verified=1`只是调用方声明，独立可信度需看verification_state、independently_verified和软件原始证据。检索命中或读取一次不等于成功复用。版本、软件或参数边界变化要复核。

通用知识用skill_search/skill_get查询；自有合法方法可经经验分存入口扩展，默认候选v=0。427张授权未明的候选卡及派生材料不随项目发布。

Token接入见YA插件/说明.md和采集真实用量.ps1：必须绑定当次日志、会话和任务。运行环境实测与用户平台快照分开标明，旧会话、字符数、请求数和点击数不能冒充本次用量。

## 失败与恢复

- UNSUPPORTED：没有注册适配器。
- NOT_INSTALLED_OR_NOT_DISCOVERABLE：未定位安装。
- UNVERIFIED_VERSION_OR_MISSING_SDK：版本待验证或缺接口。
- BUSY：同包操作持有锁。
- REQUEST_CONFLICT：同ID与原输入或版本冲突。
- pending、blocked、RECOVERY_REQUIRED：结果不确定，停止自动重发。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\连接软件.ps1" -Software "<软件名称>" -Action Diagnose
```

超时后软件可能仍执行，保留请求、PID启动时间、日志和模型，不按进程名结束软件、不自动清状态。同32位十六进制RequestId和同输入会核对证据再返回缓存。当前有保守阻断，没有完整自动多文件事务恢复。

## 唯一源码与发布

维护者只维护`ngxz_ya`，所有运行使用独立测试目录；历史候选仅供参考，不作为另一套发布源码。允许清单决定交付文件，.gitignore只是补充，不能清理已跟踪文件或旧历史。

打包器默认TestCopy；AuditCandidate仅为旧调用兼容。ReleaseCandidate检查MIT标准文本、明确允许清单、内容隐私及出厂空结构，导出不含运行标记的干净源码；这不等于批准GitHub写入。只从正式源码导出经批准文件和空结构，不能从旧研发Git直接add -A推送。报告、内部原件、包外manifest和用过的TestCopy不上传；外置SHA256SUMS仅含相对文件名及哈希。

维护者生成干净源码交付快照时，在正式源码只运行打包器（目标必须不存在）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\准备隔离包.ps1" -Destination "<包外新快照目录>" -Profile ReleaseCandidate
```

ReleaseCandidate不是长期第二份源码，不在其中运行。运行测试仍需从当次来源生成TestCopy；任何已使用副本都不能直接上传。

更多说明：AGENTS.md、使用说明.txt、经验库/说明.md、适配器/说明.md、YA插件/说明.md、NOTICE.md。
