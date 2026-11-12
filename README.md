# ngxz-ya

让 AI Agent 连上你电脑上的建模软件，在你眼前的软件窗口里实时建模、改模。做过一次的连接方法和建模技巧会存成经验，下次直接读，省时间也省 TOKEN。

## 给 Agent：一句话用法

用户只说：`用 https://github.com/ngxz-ya/ngxz-ya 连接我电脑上的 <目标软件>`。收到后照做：

1. 把包放到当前用户桌面的 `ngxz-ya` 文件夹（桌面路径用 PowerShell `[Environment]::GetFolderPath('Desktop')` 取，桌面可能不在 C 盘）：没有就 `git clone https://github.com/ngxz-ya/ngxz-ya.git "<桌面>\ngxz-ya"`；已有就在 `<桌面>\ngxz-ya` 里 `git pull`；没装 git 就下载 `https://github.com/ngxz-ya/ngxz-ya/archive/refs/heads/main.zip`，解压后把文件夹改名为 `ngxz-ya` 放到桌面。成功标志：`<桌面>\ngxz-ya\AGENTS.md` 存在。
2. 读 `<桌面>\ngxz-ya\AGENTS.md`，从第 1 步照做到第 8 步，每步达到成功标志再往下走。

## 样例：连接 FreeCAD

对 Agent 说一句：

```
读 <本包路径>\AGENTS.md，连接本机的 FreeCAD，建一个 100×50×30 的方块，然后把高度改成 60。
```

Agent 会：
1. 在 `软件清单.md` 里找到软件；
2. 先搜经验；
3. 一键连上前台软件；
4. 边做边从软件里读回尺寸；
5. 做完把经验存进去。

右上角的 YA 小窗显示连接状态、最近一次改模的实读尺寸，这次用到了哪些经验、新存了哪些经验。

## 目录

- `AGENTS.md`：给 Agent 的一页工作流。
- `软件清单.md`：支持的软件，一行一家。
- `经验.ps1`：搜经验、存经验（`-Soft <软件名>` 指定软件），同时给 YA 写本次经验使用。
- `软件/<软件名>/`：每个软件的连接程序、说明和经验。FreeCAD 是实测跑通的参考样例。
- `通用经验/`：不绑定软件的经验，包括工程图逐号对照流程。
- `YA插件/`：状态小窗，只做显示。

## 两条路

- **开源软件**：包里预置已验证的连接程序和经验，下载即连。目前是 [FreeCAD](https://www.freecad.org/) 1.1.4。
- **商业成熟软件**：包里不预置，Agent 参考 `软件/FreeCAD/` 的开源样例自己搭连接。第一次连会慢，连通后经验存在本机包内，下次就快。

两条路用同一套方法存经验、读经验。

## 许可

MIT。FreeCAD 本身按它自己的 LGPL 许可，需要另外安装，不随本包分发。
