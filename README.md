# sap-ht

使用 agent-browser 自动化查询 SAP Portal 成本类合同的Skill。

## 功能特点

- 🔍 **智能查询**：按乙方名称/项目名称搜索 SAP 成本类合同
- 📊 **自动导出**：本地生成格式化 Excel 文件，无需依赖 SAP 导出按钮
- 🤖 **浏览器自动化**：基于 agent-browser (CDP) 控制 Chrome
- 🔐 **凭据安全**：支持环境变量或本地文件，不硬编码密码
- 📝 **Markdown 输出**：同时输出 Markdown 表格预览（≤20条）

## 技术亮点

本项目解决了 SAP Web Dynpro 自动化的多个坑：

1. **"导出至电子表格"按钮无法程序触发** → 用 eval 直接读取页面表格数据
2. **SAP input 必须用 native setter** → `inp.value='x'` 会被 SAP 数据模型拦截
3. **iframe 三层嵌套** → `contentAreaFrame → isolatedWorkArea → 表单`
4. **元素 ID 动态变化** → 通过 `title` 属性匹配，不硬编码 ID
5. **中文 heredoc 乱码** → Unicode 转义或通过 Python 生成 JS 文件

## 前置条件

- 在目标企业内网或已连接 VPN
- [agent-browser](https://github.com/agent-browser/agent-browser) 已安装
  ```bash
  npm i -g agent-browser
  agent-browser install   # 自动下载 Chrome
  ```
- Python 3 + openpyxl
  ```bash
  python3 -m pip install openpyxl
  ```

## 安装

将本 skill 放入 skills 目录（以 openclaw 举例）：

```bash
cp -r sap-ht ~/.openclaw/skills/
```

## 配置

### 方式一：环境变量（推荐）

```bash
export SAP_PORTAL_URL="http://your-sap-portal.example.com:8001/irj/portal"
export SAP_USER="your_username"
export SAP_PASS="your_password"
```

### 方式二：凭据文件

在 skill 根目录创建 `oa_pwd.txt`：

```
your_username
your_password
```

## 使用方法

### 通过 OpenClaw等 agent 触发

对话中提及以下关键词即可触发：
- `查合同`、`合同编号`、`ht`
- `乙方查合同`、`成本类合同`、`sap合同`

### 直接运行脚本

```bash
bash ~/.openclaw/skills/sap-ht/scripts/sap-ht.sh <乙方名称关键字> [项目名称关键字]
```

示例：

```bash
# 按乙方名称查询
bash ~/.openclaw/skills/sap-ht/scripts/sap-ht.sh <乙方名称关键字> 

# 按乙方名称 + 项目名称筛选
bash ~/.openclaw/skills/sap-ht/scripts/sap-ht.sh <乙方名称关键字> [项目名称关键字]
```

## 输出文件

| 文件 | 路径 | 说明 |
|------|------|------|
| Excel 报表 | `~/Downloads/【关键字】合同.xlsx` | 完整字段，带格式 |
| JSON 数据 | `/private/tmp/sap-ht/result_*.txt` | 原始提取数据 |
| Markdown 表格 | 对话窗口 | 最多 20 条预览 |

Excel 包含字段：序号、合同编号、合同一级分类、合同二级分类、城市公司、合同最新金额(含税)、合同编号编码、乙方名称、项目名称、甲方名称、合同名称、含税金额、期数、创建人、创建日期、修改日期

## 项目结构

```
sap-ht/
├── SKILL.md              # Skill 说明（供 AI agent 阅读）
├── oa_pwd.txt.example    # 凭据模板
└── scripts/
    └── sap-ht.sh         # 主执行脚本
```

## 工作原理

```
┌─────────────────┐
│  agent-browser  │ 打开 SAP Portal（CDP 控制 Chrome）
└────────┬────────┘
         │
    ┌────▼────┐
    │ 登录页  │  eval + native setter 填写用户名密码
    └────┬────┘
         │
    ┌────▼────┐
    │ 导航菜单  │  eval 按 textContent 点击：招采管理 → 合同管理 → 成本类合同
    └────┬────┘
         │
    ┌────▼────┐
    │ 填写表单  │  eval + native setter 填写乙方名称/项目名称
    └────┬────┘
         │
    ┌────▼────┐
    │ 提取数据  │  eval 读取 iframe 内表格 → base64 编码 → 本地解码
    └────┬────┘
         │
    ┌────▼────┐
    │ 生成Excel │  Python + openpyxl 生成格式化 Excel
    └──────────┘
```

## 常见问题

### Q: 为什么不用 SAP 自带的"导出至电子表格"按钮？
A: SAP Web Dynpro 的 Export 按钮依赖 SAP 专有事件，`el.click()` / `dispatchEvent` 等多种方式均无效。已验证，必须用 eval 直接读取页面数据。

### Q: 为什么 input 填写后搜索条件为空？
A: SAP 数据模型会拦截 `inp.value = 'x'`，必须用 `Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set` 原生 setter。

### Q: 中文在 eval JS 里乱码怎么办？
A: shell heredoc 中直接写中文可能导致 JS 语法错误。方案：（1）用 Unicode 转义 `\uXXXX`；（2）用 Python 生成 .js 文件再传入。

### Q: 元素 ID 每次都变怎么办？
A: SAP Web Dynpro 每次登录后 input ID 都会变化。必须通过 `title` 属性匹配，不能硬编码 ID。

## 依赖

- [agent-browser](https://github.com/agent-browser/agent-browser) — 浏览器自动化 CLI
- [openpyxl](https://openpyxl.readthedocs.io/) — Python Excel 生成库
- Chrome/Chromium — 被 agent-browser 控制

## 注意事项

- ⚠️ 浏览器自动化对网络条件苛刻，如网络较差可能因为 timeout 时间不足而无法顺利进入下一阶段
- ⚠️ 技能能否稳定运行与模型能力尤其上下文窗口有直接关系
- ✅ 用户名和密码推荐使用环境变量 `SAP_USER` / `SAP_PASS`
- ⚠️ 导出的 Excel 默认存放于（MacOS下的）~/Downloads/，用户可根据自身情况让 agent 适应调整
  
## 许可

MIT License

## 作者

[@linuxwps](https://github.com/linuxwps)

---

> 💡 本 Skill 是 OpenClaw agent 生态的一部分，可在其他 agent 按本文配置后复用。欢迎提交 PR 改进！
