---
name: sap-ht
description: 查询企业内网 SAP Portal 成本类合同。通过乙方名称关键字搜索合同，支持按项目名称筛选，并将结果导出Excel自动保存到下载文件夹。触发关键词：合同编号、查合同、ht、乙方查合同、成本类合同、sap合同。仅在对应企业内网或 VPN 环境下可用。使用 agent-browser 执行，稳定可靠。
---

# SAP 合同查询 (sap-ht)

使用 agent-browser 控制 Chrome 浏览器，查询 SAP Portal 系统中的成本类合同，
按乙方名称/项目名称搜索，通过页面数据提取（非导出按钮）生成 Excel。

## 技术特点

- **引擎**: agent-browser → Chrome (CDP)
- **稳定性**: 官方 CLI，自动管理浏览器生命周期
- **登录态**: 支持状态持久化（`--session-name` / `--profile`）
- **数据提取**: 通过 eval 直接读取页面表格数据，绕过"导出至电子表格"按钮无法程序触发的问题
- **适用场景**: 自动化/批量查询/生产部署

## ⚠️ 关键经验（必须阅读）

1. **"导出至电子表格"按钮无法通过程序点击触发下载**
   SAP Web Dynpro 的 Export 按钮依赖特殊事件（SAP 专有），
   `el.click()` / `dispatchEvent` 多种方式均无效。
   **正确做法：用 eval 直接读取页面表格数据，本地生成 Excel。**

2. **SAP Web Dynpro input 必须用 native setter**
   `inp.value = 'x'` 会被 SAP 数据模型拦截，值不进入查询条件。
   必须用 `Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set` 设值。

3. **iframe 结构固定为三层**
   Portal 页面 → `iframe[name="contentAreaFrame"]` → `iframe#isolatedWorkArea` → 实际表单
   必须通过 `contentDocument` 逐层访问，不可直接 `document.querySelector`。

4. **元素 ID 动态变化，不可硬编码**
   每次登录后 input ID 都会变化（如 WD97、WDEF、WD0470 等），
   必须通过 `title` 属性或 `textContent` 匹配。

5. **中文字符传入 eval heredoc 需用 Unicode 转义**
   shell heredoc 中直接写中文可能导致 JS 语法错误，
   建议用 `\uXXXX` 形式（如 `\u9879\u76ee` 表示"项目"）。

---

## 前置条件

- 在目标企业内网或已连接 VPN
- agent-browser 已安装（`agent-browser --version` 检测）
- Chrome 浏览器已安装（`agent-browser install` 可自动下载）
- Python 3 + openpyxl 可用（用于生成 Excel）
- 凭据文件 `oa_pwd.txt` 在 skill 根目录下（第一行用户名，第二行密码）

---

## 执行流程

### 阶段 0：检查环境

```bash
agent-browser --version
python3 -c "import openpyxl; print('openpyxl OK')"
```

如果 agent-browser 未安装：`npm i -g agent-browser`
如果 openpyxl 未安装：`python3 -m pip install openpyxl`

### 阶段 1：打开 SAP Portal 并登录

```bash
agent-browser open 'http://your-sap-portal.example.com:8001/irj/portal'
agent-browser wait 5000
agent-browser snapshot -i
```

检查 snapshot 输出：
- **已登录**（看到对应菜单）→ 跳到阶段 2
- **登录页** → 用 eval 填写（snapshot ref 动态变化，推荐 eval）：

```bash
agent-browser eval --stdin <<'EVALEOF'
(() => {
  const u = document.querySelector('input[name="j_username"], input[type="text"]');
  const p = document.querySelector('input[name="j_password"], input[type="password"]');
  if (u && p) {
    const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    set.call(u, process.env.SAP_USER || 'YOUR_USERNAME');  // 用户名，建议从环境变量读取
    set.call(p, process.env.SAP_PASS || 'YOUR_PASSWORD');    // 密码，建议从环境变量读取
    u.dispatchEvent(new Event('input', {bubbles:true}));
    p.dispatchEvent(new Event('input', {bubbles:true}));
    // 找登录按钮
    const all = document.querySelectorAll('*');
    for (const el of all) {
      if ((el.value || el.textContent || '').includes('登录')) { el.click(); return 'logging in'; }
    }
    // 尝试 submit
    u.form?.submit();
    return 'filled, submitted form';
  }
  return 'login inputs not found';
})()
EVALEOF
agent-browser wait 5000
```

> **推荐**：用户名密码从环境变量或 `oa_pwd.txt` 读取，不要硬编码在脚本里。

### 阶段 2：导航到成本类合同

操作路径：招采管理 → 合同管理 → 成本类合同

SAP Portal 菜单是嵌套的 generic div，用 eval 按 textContent 定位最可靠：

```bash
# 点击「招采管理」
agent-browser eval --stdin <<'EVALEOF'
(() => {
  const all = document.querySelectorAll('*');
  for (const el of all) {
    if (el.textContent?.trim() === '招采管理' && el.getAttribute('tabindex')) {
      el.click(); return 'clicked 招采管理';
    }
  }
  return 'not found';
})()
EVALEOF
agent-browser wait 3000

# 点击「合同管理」
agent-browser eval --stdin <<'EVALEOF'
(() => {
  const all = document.querySelectorAll('*');
  for (const el of all) {
    if (el.textContent?.trim() === '合同管理' && el.getAttribute('tabindex')) {
      el.click(); return 'clicked 合同管理';
    }
  }
  return 'not found';
})()
EVALEOF
agent-browser wait 3000

# 点击「成本类合同」
agent-browser eval --stdin <<'EVALEOF'
(() => {
  const all = document.querySelectorAll('*');
  for (const el of all) {
    if (el.textContent?.trim() === '成本类合同' && el.getAttribute('tabindex')) {
      el.click(); return 'clicked 成本类合同';
    }
  }
  return 'not found';
})()
EVALEOF
agent-browser wait 8000
```

> ⚠️ 成本类合同页面加载很慢（约 5-10 秒），wait 不能太短。

### 阶段 3：填写搜索条件并执行

**支持两个筛选条件：**
- `PARTY_B_NAME`（乙方名称）— 必填或可选
- `PROJECT_NAME`（项目名称）— 可选

#### 3a. 填写表单（eval + native setter）

```bash
# 填写乙方名称和项目名称
agent-browser eval --stdin <<'EVALEOF'
(() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  if (!ca) return 'contentAreaFrame not found';
  const doc = ca.contentDocument;
  if (!doc) return 'contentDocument not accessible';
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  if (!iwa) return 'isolatedWorkArea not found';
  const iDoc = iwa.contentDocument;
  if (!iDoc) return 'iDoc not accessible';

  const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  const inputs = iDoc.querySelectorAll('input[type="text"]');
  
  let filled = [];
  for (const inp of inputs) {
    const title = (inp.title || '').toUpperCase();
    if (title.includes('PARTY_B_NAME') && !inp.readOnly) {
      set.call(inp, process.env.SEARCH_KEYWORD || '乙方关键字');  // 从参数读取
      inp.dispatchEvent(new Event('input', {bubbles:true}));
      inp.blur();
      filled.push('PARTY_B_NAME=' + inp.value);
    }
    if (title.includes('PROJECT_NAME') && !inp.readOnly) {
      // 项目名称含中文，用 Unicode 转义避免 heredoc 编码问题
      set.call(inp, '\u9879\u76ee\u540d\u79f0');  // "项目名称"的示例
      inp.dispatchEvent(new Event('input', {bubbles:true}));
      inp.blur();
      filled.push('PROJECT_NAME=' + inp.value);
    }
  }
  return 'filled: ' + filled.join(', ');
})()
EVALEOF
```

> **中文处理技巧**：在 heredoc 中写中文可能导致 JS 语法错误。
> 用 Python 生成 JS 文件可完美解决：
> ```bash
> python3 -c "
> js = '''const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
> const inputs = iDoc.querySelectorAll('input[type=text]');
> for (const inp of inputs) {
>   if (inp.title?.includes('PROJECT_NAME')) { set.call(inp, '项目名称'); inp.blur(); }
> }''';
> with open('/tmp/fill_proj.js','w') as f: f.write(js)
> ```
> 然后 `agent-browser eval --stdin < /tmp/fill_proj.js`

#### 3b. 点击搜索按钮

```bash
agent-browser eval --stdin <<'EVALEOF'
(() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  const doc = ca.contentDocument;
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  const iDoc = iwa.contentDocument;
  const all = iDoc.querySelectorAll('*');
  for (const el of all) {
    if (el.textContent?.trim() === '搜索' && el.className?.includes('lsButton')) {
      el.click(); return 'clicked 搜索';
    }
  }
  return '搜索 button not found';
})()
EVALEOF
agent-browser wait 10000
```

### 阶段 4：提取表格数据（核心替代"导出"按钮）

> ⚠️ **千万不要尝试点击"导出至电子表格"按钮**，已验证多种方式均无法触发下载。
> 正确做法：用 eval 读取页面表格数据，base64 编码后传到本地，用 Python 生成 Excel。

#### 4a. 提取数据并 base64 编码

```bash
cat > /tmp/extract_data.js << 'JSEOF'
(() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  if (!ca) return 'contentAreaFrame not found';
  const doc = ca.contentDocument;
  if (!doc) return 'no contentDocument';
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  if (!iwa) return 'no isolatedWorkArea';
  const iDoc = iwa.contentDocument;
  if (!iDoc) return 'no iDoc';

  // SAP Web Dynpro 表格通常在有 id 包含 'table' 或 class 包含 'lsListbox' 的元素内
  // 实际数据在大量 <tr> <td> 中，直接提取所有可见的 td 文本
  const allCells = [];
  const rows = iDoc.querySelectorAll('tr');
  for (const row of rows) {
    const cells = row.querySelectorAll('td');
    if (cells.length < 3) continue;  // 跳过无数据行
    const rowData = [];
    for (const cell of cells) {
      const t = (cell.textContent || '').trim();
      if (t) rowData.push(t);
    }
    if (rowData.length > 0) allCells.push(rowData);
  }
  
  // 如果上面方法没拿到数据，fallback：拿所有有文本的 div/span
  if (allCells.length === 0) {
    const allEls = iDoc.querySelectorAll('*');
    let curRow = [];
    for (const el of allEls) {
      if (el.children.length > 0) continue;  // 跳过有子元素的
      const t = (el.textContent || '').trim();
      if (!t || t.length > 100) continue;
      curRow.push(t);
      if (curRow.length > 20) { allCells.push([...curRow]); curRow = []; }
    }
    if (curRow.length > 0) allCells.push(curRow);
  }

  const json = JSON.stringify(allCells);
  const b64 = btoa(unescape(encodeURIComponent(json)));
  
  // 写入 /tmp（通过 data URL 触发下载，或写入变量让 outer 读取）
  // 这里返回 b64 字符串，由 agent-browser 的 eval 结果返回
  return 'B64:' + b64;
})()
JSEOF

agent-browser eval --stdin < /tmp/extract_data.js > /tmp/sap_extract_result.txt 2>&1
```

> **注意**：上面的 JS 是一个模板。实际 SAP 表格结构需要用更精确的方式提取。
> 经过实战验证的可靠方式是：直接取页面所有 `td` 的 `textContent`，
> 然后由 Python 按"序号+合同编号"模式解析（见阶段 5）。

#### 4b. 实战验证的可靠数据提取 JS

以下 JS 经过实战验证，可直接使用（将结果输出到页面某个可见元素，或写入 window 全局变量）：

```javascript
// 写入 /tmp 需要通过 Chrome DevTools Protocol，较复杂
// 简便方案：eval 返回 base64 字符串，exec 侧写入文件
const result = (() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  const doc = ca.contentDocument;
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  const iDoc = iwa.contentDocument;
  
  // 提取所有 td 文本（SAP WD 表格渲染为普通 HTML table）
  const allText = [];
  const allTds = iDoc.querySelectorAll('td');
  for (const td of allTds) {
    const t = (td.textContent || '').trim();
    if (t) allText.push(t);
  }
  
  // 按 "序号 + 合同编号(C/A开头)" 模式分组
  const rows = [];
  let cur = [];
  for (const t of allText) {
    if (/^[1-9]$|^1[0-9]$/.test(t) && cur.length > 0) {
      rows.push(cur);
      cur = [];
    }
    cur.push(t);
  }
  if (cur.length > 0) rows.push(cur);
  
  const json = JSON.stringify(rows);
  return 'B64:' + btoa(unescape(encodeURIComponent(json)));
})();
result;  // eval 返回此值
```

#### 4c. 将 base64 数据传回本地

```bash
agent-browser eval --stdin < /path/to/extract_script.js 2>&1 | tee /tmp/sap_raw_output.txt

# 从输出中提取 base64 部分
grep -o 'B64:[A-Za-z0-9+/=]*' /tmp/sap_raw_output.txt | sed 's/^B64://' > /tmp/sap_b64.txt

# Python 解码
python3 << 'PYEOF'
import base64, json

with open('/tmp/sap_b64.txt') as f:
    b64 = f.read().strip()

data = json.loads(base64.b64decode(b64).decode('utf-8'))

with open('/tmp/sap_data.json', 'w') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"Decoded {len(data)} rows to /tmp/sap_data.json")
PYEOF
```

### 阶段 5：解析数据并生成 Excel

> ⚠️ **必须在本地用 Python + openpyxl 生成 Excel**，不要依赖 SAP 的导出功能。

以下 Python 脚本是经过实战验证的完整解析+生成逻辑：

```python
import json, openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

# 1. 加载提取的数据
with open('/tmp/sap_data.json') as f:
    rows = json.load(f)
# rows: list of list, 每个子 list 是一行的所有文本单元格

# 2. 解析合同记录
# 识别模式：单元格文本 == 数字序号（1-8），下一个单元格是以 C 或 A 开头的合同编号
KNOWN_CLASS2 = {'工程类','维保工程','勘察类','设计类','监理类','咨询类','检测类',
                '评估类','测量类','招标代理类','造价类','营销类','商业类','物业类',
                '酒店类','租赁类','保险类','顾问类'}

records = []
seen = set()
for row in rows:
    for ci, cell in enumerate(row):
        if cell in '12345678' and ci+1 < len(row):
            nxt = row[ci+1]
            if (nxt.startswith('C') or nxt.startswith('A')) and nxt not in seen:
                seen.add(nxt)
                slice_ = row[ci:]  # 从序号开始的后续单元格
                
                class1 = slice_[3] if len(slice_)>3 else ''
                slice4 = slice_[4] if len(slice_)>4 else ''
                
                # 判断是否有合同二级分类
                if slice4 in KNOWN_CLASS2:
                    has_class2 = True
                elif '地产' in slice4:
                    has_class2 = False
                else:
                    has_class2 = slice4 in KNOWN_CLASS2
                
                if has_class2:
                    class2 = slice4
                    city   = slice_[5] if len(slice_)>5 else ''
                    amt    = slice_[6] if len(slice_)>6 else ''
                    code   = slice_[7] if len(slice_)>7 else ''
                    party_b = slice_[8] if len(slice_)>8 else ''
                    project = slice_[9] if len(slice_)>9 else ''
                    party_a = slice_[10] if len(slice_)>10 else ''
                    name   = slice_[11] if len(slice_)>11 else ''
                    amt2   = slice_[12] if len(slice_)>12 else ''
                    period = slice_[13] if len(slice_)>13 else ''
                else:
                    class2 = ''
                    city   = slice4
                    amt    = slice_[5] if len(slice_)>5 else ''
                    code   = slice_[6] if len(slice_)>6 else ''
                    party_b = slice_[7] if len(slice_)>7 else ''
                    project = slice_[8] if len(slice_)>8 else ''
                    party_a = slice_[9] if len(slice_)>9 else ''
                    name   = slice_[10] if len(slice_)>10 else ''
                    amt2   = slice_[11] if len(slice_)>11 else ''
                    period = slice_[12] if len(slice_)>12 else ''
                
                # 找创建人/创建日期/修改日期（在 'No' 关键字附近）
                user = created = modified = ''
                try:
                    no_idx = slice_.index('No')
                    user    = slice_[no_idx+1] if no_idx+1 < len(slice_) else ''
                    created = slice_[no_idx+2] if no_idx+2 < len(slice_) else ''
                    modified= slice_[no_idx+3] if no_idx+3 < len(slice_) else ''
                except ValueError:
                    pass
                
                records.append({
                    '序号': int(cell),
                    '合同编号': nxt,
                    '合同一级分类': class1,
                    '合同二级分类': class2,
                    '城市公司': city,
                    '合同最新金额(含税)': amt,
                    '合同编号编码': code,
                    '乙方名称': party_b,
                    '项目名称': project,
                    '甲方名称': party_a,
                    '合同名称': name,
                    '含税金额': amt2,
                    '期数': period,
                    '创建人': user,
                    '创建日期': created,
                    '修改日期': modified,
                })
                break

print(f"解析到 {len(records)} 条合同记录")

# 3. 生成 Excel
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "成本类合同"

headers = ['序号','合同编号','合同一级分类','合同二级分类','城市公司','合同最新金额(含税)',
           '合同编号编码','乙方名称','项目名称','甲方名称','合同名称','含税金额',
           '期数','创建人','创建日期','修改日期']
ws.append(headers)

# 表头样式
hdr_font = Font(bold=True, color='FFFFFF', size=11)
hdr_fill = PatternFill('solid', fgColor='4472C4')
hdr_align = Alignment(horizontal='center', vertical='center', wrap_text=True)
thin = Side(style='thin')
thin_border = Border(left=thin, right=thin, top=thin, bottom=thin)

for col_idx, h in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col_idx, value=h)
    cell.font = hdr_font
    cell.fill = hdr_fill
    cell.alignment = hdr_align
    cell.border = thin_border

# 数据行
alt_fill = PatternFill('solid', fgColor='D9E1F2')
for ri, rec in enumerate(records, 2):
    vals = [rec[h] for h in headers]
    for ci, val in enumerate(vals, 1):
        cell = ws.cell(row=ri, column=ci, value=val)
        cell.border = thin_border
        if ri % 2 == 0:
            cell.fill = alt_fill
        # 金额列右对齐
        if headers[ci-1] in ['合同最新金额(含税)', '含税金额']:
            cell.alignment = Alignment(horizontal='right', vertical='center')
        elif headers[ci-1] in ['序号','创建日期','修改日期']:
            cell.alignment = Alignment(horizontal='center', vertical='center')
        else:
            cell.alignment = Alignment(horizontal='left', vertical='center', wrap_text=True)

# 列宽
col_widths = [6, 14, 12, 12, 12, 16, 28, 24, 14, 22, 44, 16, 8, 10, 12, 12]
for i, w in enumerate(col_widths, 1):
    ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = w

ws.row_dimensions[1].height = 28
for ri in range(2, len(records)+2):
    ws.row_dimensions[ri].height = 30

# 4. 保存
out = '/tmp/sap_contracts.xlsx'
wb.save(out)
print(f"Excel 已保存: {out}")
```

### 阶段 6：输出结果（必须执行）

#### 步骤 1：告知文件路径

```bash
ls -lt /tmp/sap_contracts.xlsx
```

#### 步骤 2：输出 Markdown 表格

用 Python 读取刚生成的 Excel，输出 Markdown 表格（最多 20 条）：

```bash
python3 << 'PYEOF'
import openpyxl

wb = openpyxl.load_workbook('/tmp/sap_contracts.xlsx')
ws = wb[wb.sheetnames[0]]

headers = [cell.value for cell in next(ws.rows)]
print("| " + " | ".join(str(h) for h in headers) + " |")
print("|" + "|".join(["---"] * len(headers)) + "|")

for ri, row in enumerate(ws.iter_rows(values_only=True), 1):
    if ri == 1: continue   # 跳过表头
    if ri > 21: break      # 最多 20 条
    print("| " + " | ".join(str(c) if c is not None else '' for c in row) + " |")

total = ws.max_row - 1
if total > 20:
    print(f"\n...还有 {total-20} 条记录，详见 Excel 文件")
PYEOF
```

### 阶段 7：清理

```bash
agent-browser close
rm -f /tmp/sap_data.json /tmp/sap_b64.txt /tmp/extract_data.js /tmp/sap_extract_result.txt
```

---

## 凭据文件

`oa_pwd.txt` 格式（位于 skill 根目录）：

```
<用户名>
<密码>
```

**禁止在 SKILL.md 或日志中输出明文凭据。**

> **推荐**：使用环境变量 `SAP_USER` 和 `SAP_PASS` 替代明文文件。

---

## 注意事项

### 已验证的关键问题

| 问题 | 结论 |
|------|------|
| "导出至电子表格"按钮能否程序触发？ | **不能**。已验证 click/dispatchEvent/mousedown 等多种方式，均无效。必须提取页面数据本地生成 Excel。 |
| input 填写后搜索条件为空？ | 必须用 `native setter`，不能用 `inp.value = 'x'`。详见阶段 3a。 |
| iframe 内元素如何访问？ | `contentAreaFrame.contentDocument → isolatedWorkArea.contentDocument → 目标元素` |
| 元素 ID 变化怎么办？ | 通过 `title` 属性匹配，不要硬编码 ID |
| 中文传入 eval JS 乱码？ | 用 Unicode 转义（`\uXXXX`）或通过 Python 生成 .js 文件再传入 |
| 提取数据量大 eval 返回被截断？ | 用 `btoa(unescape(encodeURIComponent(JSON.stringify(...))))` 编码为 base64，在本地解码 |
| 合同记录有/无二级分类怎么办？ | 解析时判断 `slice[4]` 是否为已知二级分类值，动态调整索引（详见阶段 5 Python 代码） |

### 通用注意

- 直接访问 SAP Portal 比从 OA 进入更稳定
- 成本类合同页面加载慢，wait 建议 8000ms 以上
- 避免使用 `wait --load networkidle`（SAP 可能有持久网络活动导致超时）
- 复杂 JS 必须用 `eval --stdin <<'EVALEOF'`，避免 shell 转义
- 任务结束后必须调用 `agent-browser close` 释放浏览器进程
- 临时文件（`/tmp/sap_*`）在任务结束后应清理

---

## 技能脚本

自动化脚本位于 `scripts/sap-ht.sh`，可直接执行：
```bash
bash scripts/sap-ht.sh <乙方名称关键字> [项目名称关键字]
```

示例：
```bash
bash scripts/sap-ht.sh 乙方公司名
bash scripts/sap-ht.sh 乙方公司名 项目名称
```

> 脚本当前版本可能未包含所有最新修复，建议优先参照本 SKILL.md 手动执行。
