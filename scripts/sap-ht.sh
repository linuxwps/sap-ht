#!/bin/bash
# sap-ht.sh: Query SAP Portal for cost-type contracts using agent-browser
# Usage: bash sap-ht.sh <乙方名称关键字> [项目名称关键字]
# Output: Excel file saved to ~/Downloads/ + JSON result to stdout

set -euo pipefail

KEYWORD="${1:?Usage: bash sap-ht.sh <乙方名称关键字> [项目名称关键字]}"
PROJECT="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
OA_PWD="${SKILL_DIR}/oa_pwd.txt"
AB="agent-browser"
RESULT_DIR="/private/tmp/sap-ht"
mkdir -p "$RESULT_DIR"

# Read credentials from file or environment variables
if [[ -f "$OA_PWD" ]]; then
  OA_USER=$(sed -n '1p' "$OA_PWD")
  OA_PASS=$(sed -n '2p' "$OA_PWD")
elif [[ -n "${SAP_USER:-}" && -n "${SAP_PASS:-}" ]]; then
  OA_USER="$SAP_USER"
  OA_PASS="$SAP_PASS"
else
  echo "ERROR: No credentials found. Set SAP_USER/SAP_PASS env vars or create oa_pwd.txt" >&2
  exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── Phase 0: Check agent-browser ──
log "Checking agent-browser..."
if ! command -v agent-browser &>/dev/null; then
  echo "ERROR: agent-browser not installed. Run: npm i -g agent-browser" >&2
  exit 1
fi

# ── Phase1: Open SAP Portal directly ──
log "Opening SAP Portal..."
SAP_URL="${SAP_PORTAL_URL:-http://your-sap-portal.example.com:8001/irj/portal}"
$AB open "$SAP_URL"
$AB wait 3000

# ── Phase 2: SAP Portal Login ──
SNAPSHOT=$($AB snapshot -i 2>&1)
if echo "$SNAPSHOT" | grep -q '"登录"'; then
  log "SAP Portal login required..."
  # Extract refs from snapshot for username/password/login button
  USER_REF=$(echo "$SNAPSHOT" | grep -i '用户' | head -1 | sed 's/.*@\([^ ]*\).*/\1/')
  PASS_REF=$(echo "$SNAPSHOT" | grep -i '密码' | head -1 | sed 's/.*@\([^ ]*\).*/\1/')
  LOGIN_REF=$(echo "$SNAPSHOT" | grep -i '登录' | grep -i 'button\|btn' | head -1 | sed 's/.*@\([^ ]*\).*/\1/')

  if [[ -n "$USER_REF" && -n "$PASS_REF" && -n "$LOGIN_REF" ]]; then
    $AB batch "fill @${USER_REF} $OA_USER" "fill @${PASS_REF} $OA_PASS" "click @${LOGIN_REF}"
  else
    # Fallback: try first 3 refs (common pattern: e1=username, e2=password, e3=login)
    log "Could not parse refs, trying @e1/@e2/@e3..."
    $AB batch "fill @e1 $OA_USER" "fill @e2 $OA_PASS" "click @e3"
  fi
  log "Waiting for SAP Portal to load..."
  $AB wait 5000
fi

# ── Phase 3: Navigate to 成本类合同 ──
log "Navigating to 招采管理 > 合同管理 > 成本类合同..."

# Click 招采管理 from top menu
$AB eval --stdin <<'EVALEOF'
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

$AB wait 3000

# Click 合同管理 in left nav
$AB eval --stdin <<'EVALEOF'
(() => {
  const all = document.querySelectorAll('*');
  for (const el of all) {
    const t = el.textContent?.trim();
    if (t === '合同管理' && el.getAttribute('tabindex') && el.onclick) {
      el.click(); return 'clicked 合同管理';
    }
  }
  return 'not found';
})()
EVALEOF

$AB wait 3000

# Click 成本类合同 in left nav
$AB eval --stdin <<'EVALEOF'
(() => {
  const all = document.querySelectorAll('*');
  for (const el of all) {
    const t = el.textContent?.trim();
    if (t === '成本类合同' && el.getAttribute('tabindex') && el.onclick) {
      el.click(); return 'clicked 成本类合同';
    }
  }
  return 'not found';
})()
EVALEOF

log "Waiting for 成本类合同 page to load..."
$AB wait 8000

# ── Phase 4: Fill search and query ──
log "Searching for 乙方名称: $KEYWORD..."

# Build JS for filling form (handle Chinese characters properly)
JS_FILL="/tmp/sap_fill_$(date +%s).js"
cat > "$JS_FILL" <<JSEOF
(() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  if (!ca) return 'no contentAreaFrame';
  const doc = ca.contentDocument;
  if (!doc) return 'no doc access';
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  if (!iwa) return 'no isolatedWorkArea';
  const iDoc = iwa.contentDocument;
  if (!iDoc) return 'no iDoc access';
  
  const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  const inputs = iDoc.querySelectorAll('input[type="text"]');
  
  let filled = [];
  for (const inp of inputs) {
    const title = (inp.title || '').toUpperCase();
    if (title.includes('PARTY_B_NAME') && !inp.readOnly) {
      set.call(inp, '${KEYWORD}');
      inp.dispatchEvent(new Event('input', {bubbles: true}));
      inp.dispatchEvent(new Event('change', {bubbles: true}));
      inp.blur();
      filled.push('PARTY_B_NAME=' + inp.value);
    }
    if (title.includes('PROJECT_NAME') && !inp.readOnly && '${PROJECT}') {
      set.call(inp, '${PROJECT}');
      inp.dispatchEvent(new Event('input', {bubbles: true}));
      inp.dispatchEvent(new Event('change', {bubbles: true}));
      inp.blur();
      filled.push('PROJECT_NAME=' + inp.value);
    }
  }
  return 'filled: ' + filled.join(', ');
})()
JSEOF

$AB eval --stdin < "$JS_FILL"
rm -f "$JS_FILL"

$AB wait 1000

# Click 搜索 button
$AB eval --stdin <<'EVALEOF'
(() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  const doc = ca.contentDocument;
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  const iDoc = iwa.contentDocument;
  
  const all = iDoc.querySelectorAll('*');
  for (const el of all) {
    if (el.id && el.textContent?.trim() === '搜索' && el.className?.includes('lsButton')) {
      el.click(); return 'clicked 搜索';
    }
  }
  return '搜索 button not found';
})()
EVALEOF

log "Waiting for search results..."
$AB wait 10000

# ── Phase 5: Extract data and generate Excel ──
log "Extracting table data..."

EXTRACT_JS="/tmp/sap_extract_$(date +%s).js"
cat > "$EXTRACT_JS" <<'JSEOF'
(() => {
  const ca = document.querySelector('iframe[name="contentAreaFrame"]');
  if (!ca) return 'ERR:contentAreaFrame not found';
  const doc = ca.contentDocument;
  if (!doc) return 'ERR:no contentDocument';
  const iwa = doc.querySelector('iframe#isolatedWorkArea');
  if (!iwa) return 'ERR:no isolatedWorkArea';
  const iDoc = iwa.contentDocument;
  if (!iDoc) return 'ERR:no iDoc';

  // Extract all td texts
  const allText = [];
  const allTds = iDoc.querySelectorAll('td');
  for (const td of allTds) {
    const t = (td.textContent || '').trim();
    if (t) allText.push(t);
  }

  // Group by "serial number + contract number(C/A prefix)" pattern
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
  const b64 = btoa(unescape(encodeURIComponent(json)));
  return 'B64:' + b64;
})()
JSEOF

EXTRACT_RESULT=$($AB eval --stdin < "$EXTRACT_JS" 2>&1)
rm -f "$EXTRACT_JS"

# Decode base64 result
B64_DATA=$(echo "$EXTRACT_RESULT" | grep -o 'B64:[A-Za-z0-9+/=]*' | sed 's/^B64://')

if [[ -z "$B64_DATA" ]]; then
  echo "WARNING: No data extracted from page" >&2
  echo "$EXTRACT_RESULT" > "$RESULT_DIR/extract_debug.txt"
else
  echo "$B64_DATA" | base64 -d 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    with open('${RESULT_DIR}/sap_data.json', 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f'Decoded {len(data)} rows')
except Exception as e:
    print(f'Decode error: {e}', file=sys.stderr)
" || echo "Failed to decode data" >&2
fi

# ── Phase 6: Generate Excel (using Python + openpyxl) ──
log "Generating Excel report..."

if [[ -f "$RESULT_DIR/sap_data.json" ]]; then
  python3 << 'PYEOF'
import json, openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
import os

RESULT_DIR = '/private/tmp/sap-ht'
KEYWORD = os.environ.get('KEYWORD', 'query')

# 1. Load extracted data
with open(f'{RESULT_DIR}/sap_data.json') as f:
    rows = json.load(f)

# 2. Parse contract records
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
                slice_ = row[ci:]
                
                class1 = slice_[3] if len(slice_)>3 else ''
                slice4 = slice_[4] if len(slice_)>4 else ''
                
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

print(f"Parsed {len(records)} contract records")

if len(records) == 0:
    print("WARNING: No records parsed, saving raw data for debug")
    with open(f'{RESULT_DIR}/raw_rows.json', 'w') as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

# 3. Generate Excel
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "成本类合同"

headers = ['序号','合同编号','合同一级分类','合同二级分类','城市公司','合同最新金额(含税)',
           '合同编号编码','乙方名称','项目名称','甲方名称','合同名称','含税金额',
           '期数','创建人','创建日期','修改日期']
ws.append(headers)

# Header style
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

# Data rows
alt_fill = PatternFill('solid', fgColor='D9E1F2')
for ri, rec in enumerate(records, 2):
    vals = [rec[h] for h in headers]
    for ci, val in enumerate(vals, 1):
        cell = ws.cell(row=ri, column=ci, value=val)
        cell.border = thin_border
        if ri % 2 == 0:
            cell.fill = alt_fill
        if headers[ci-1] in ['合同最新金额(含税)', '含税金额']:
            cell.alignment = Alignment(horizontal='right', vertical='center')
        elif headers[ci-1] in ['序号','创建日期','修改日期']:
            cell.alignment = Alignment(horizontal='center', vertical='center')
        else:
            cell.alignment = Alignment(horizontal='left', vertical='center', wrap_text=True)

# Column widths
col_widths = [6, 14, 12, 12, 12, 16, 28, 24, 14, 22, 44, 16, 8, 10, 12, 12]
for i, w in enumerate(col_widths, 1):
    ws.column_dimensions[get_column_letter(i)].width = w

ws.row_dimensions[1].height = 28
for ri in range(2, len(records)+2):
    ws.row_dimensions[ri].height = 30

# 4. Save
out = os.path.expanduser(f'~/Downloads/【{KEYWORD}】合同.xlsx')
wb.save(out)
print(f"Excel saved: {out}")
PYEOF
fi

# ── Phase 7: Output result ──
echo ""
echo "=== 查询完成 ==="
echo "乙方名称关键字: $KEYWORD"
if [[ -n "$PROJECT" ]]; then
  echo "项目名称关键字: $PROJECT"
fi
echo ""

# ── Phase 8: Cleanup ──
log "Closing browser session..."
$AB close

log "Done!"
