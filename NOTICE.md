# 来源、依赖和授权范围

## 本项目代码

本包为项目维护的PowerShell、C#连接与经验工具源码，包含自行编写声明的参考适配器。未发现附带第三方代码许可证头或捆绑第三方SDK二进制；这不是对全部代码原创性、贡献者权属或专利的证明。维护者已确认将其有权发布的项目原创代码按MIT许可公开，版权署名为ngxz-ya；继续保留依法需要的第三方署名。

正式许可证为根目录LICENSE中的MIT License，Copyright (c) 2026 ngxz-ya。对维护者拥有发布权利的代码，允许免费使用、修改、二次开发、再分发及合法商用，条件及免责以完整LICENSE为准。MIT不覆盖第三方商业软件、厂商SDK、受限制的他人代码、427张授权未明卡或私人经验、模型、任务和Token记录。本文件说明范围，不修改MIT标准条款。

## 外部运行前提

- Windows PowerShell 5.1 Desktop、.NET Framework、WPF/WinForms及Windows系统接口：由使用者的系统环境提供，不随包再分发。PowerShell 7不是已验证替代品。
- 参考适配器使用NX10的官方NXOpen Journal接口，准确版本及能力见适配器/索引.json。run_journal、ManagedLoader、NXOpen.dll、NXOpen.UF.dll由使用者自行合法安装，本项目不复制它们。
- 软件安装、功能许可、API开发或使用条件依使用者实际版本、订单及协议。接口能执行只能证明当次技术结果，不确认全部合同权利。

原创连接源码、厂商SDK、使用者软件许可是不同对象。不能仅因调用商业接口就断言必须另取厂商书面批准，也不能以没有捆绑DLL断言没有任何限制。当前未找到足以直接认定本包原创调用源码禁止免费公开的依据；实际适用合同及分发条件未提供的部分标UNKNOWN，需核对具体条款，不能凭空增加许可要求。

官方依据：

- [Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_5.1)
- [NX Programming and Customization历史概述](https://www.plm.automation.siemens.com/en_gb/Images/nx%20programming%20and%20customization%20fs%20W%203_tcm642-4564.pdf)：说明官方接口与运行功能许可，不是源码再分发许可文本。
- [Siemens条款入口](https://www.siemens.com/en-gb/company/customer-partner-terms/sw-terms/supplements/)：根据订单代码、基础协议及适用版本核查。现行条款不能直接倒推NX10历史合同；涉及API用途、开发及转售限制时需区分免费源码分发与软件转售。
- [商标指南](https://www.siemens.com/en-us/company/digital-industries-software-trademarks/guidelines/)：产品名称用于准确说明兼容接口，相关商标属于权利人，不表示获得厂商认证或背书。

## 不随包分发

427张来源授权未确认的候选卡及派生资料、私人经验、连接卡、任务账本、Token日志、用户模型、商业SDK、软件许可文件和内部审查记录均不发布。出厂经验和知识为空，使用者自行积累其有权保存的内容。

新增适配器或第三方代码时，应记录来源、许可证、必要版权声明和分发限制。用户软件许可不因本项目开源而免费，也不把本项目许可证延伸到其他厂商材料。

## 发布状态

逐文件允许清单用于生成干净交付快照，内部manifest不上传。MIT决定与公开署名已获维护者批准，适用于其有权发布的源码；已有逐文件来源审查继续有效。没有识别出当前原创适配器源码免费分发的具体禁止条款，不能仅因缺厂商书面许可阻断。实际用户的软件合同适用性仍须按具体协议核对，UNKNOWN不等于已经发现禁止条款，也不授予用户绕过限制的权利。打包许可检查与远端历史替换批准分开，不能因MIT落地就自动推送。

旧Git历史中的材料不会因为工作目录整理自动消失，不能从旧研发提交链直接发布。历史替换须先备份、独立验证并取得维护者最终批准。第三方克隆、Fork及缓存可能继续保留旧内容。
