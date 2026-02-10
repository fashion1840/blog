#!/bin/bash
set -e

# 加载环境变量
if [ -f "/root/.openclaw/workspace/blog-deploy/.env" ]; then
    set -a
    source /root/.openclaw/workspace/blog-deploy/.env
    set +a
fi

if [ -z "$TAVILY_API_KEY" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "错误: 请确保 .env 文件中设置了 TAVILY_API_KEY 和 GITHUB_TOKEN"
    exit 1
fi

WORKDIR="/root/.openclaw/workspace/blog-deploy"
TIMESTAMP=$(date +%Y-%m-%d)
TNOW=$(date +%H:%M)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
POST_DIR="${WORKDIR}/${YEAR}/${MONTH}/${DAY}/daily-digest"
HTML_FILE="${POST_DIR}/index.html"
INDEX_FILE="${WORKDIR}/index.html"

mkdir -p "$POST_DIR"

echo "🔍 开始搜集24小时内的热门信息..."

# Hacker News
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Hacker News top stories last 24 hours" \
  -n 8 --topic news --days 1 \
  > "${POST_DIR}/hackernews_raw.txt" 2>/dev/null || echo "" > "${POST_DIR}/hackernews_raw.txt"

# Reddit
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Reddit popular posts r/technology r/programming past 24 hours" \
  -n 8 --topic news --days 1 \
  > "${POST_DIR}/reddit_raw.txt" 2>/dev/null || echo "" > "${POST_DIR}/reddit_raw.txt"

# Product Hunt
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Product Hunt latest launches past 24 hours" \
  -n 8 --topic news --days 1 \
  > "${POST_DIR}/producthunt_raw.txt" 2>/dev/null || echo "" > "${POST_DIR}/producthunt_raw.txt"

echo "✅ 搜索完成，生成HTML..."

python3 - << 'PYEOF' > "${HTML_FILE}"
import re
from datetime import datetime

ts = datetime.now().strftime("%Y-%m-%d")
tnow = datetime.now().strftime("%H:%M")

def clean_text(text, max_len=300):
    text = re.sub(r'\s+', ' ', text)
    text = text.strip()
    if len(text) > max_len:
        text = text[:max_len].rsplit(' ', 1)[0] + '...'
    return text

def parse_tavily(text):
    items = []
    answer_match = re.search(r'## Answer\s+(.*?)(?=\n##|\Z)', text, re.DOTALL)
    overall_summary = clean_text(answer_match.group(1), 500) if answer_match else ""

    sources_match = re.search(r'## Sources\s+(.*)', text, re.DOTALL)
    if not sources_match:
        return [], overall_summary

    src = sources_match.group(1)
    entries = re.split(r'(?=^- \*\*)', src, flags=re.MULTILINE)

    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue

        title_match = re.search(r'- \*\*(.*?)\*\*', entry)
        title = title_match.group(1).strip() if title_match else '无标题'

        rel_match = re.search(r'\(relevance:\s*(\d+)%\)', entry)
        relevance = rel_match.group(1) if rel_match else None

        url_match = re.search(r'(https?://[^\s\)]+)', entry)
        url = url_match.group(1) if url_match else '#'

        desc_lines = []
        for line in entry.split('\n')[1:]:
            line = line.strip()
            if line and not line.startswith('-') and 'http' not in line and 'relevance' not in line.lower():
                desc_lines.append(line)
        description = clean_text(' '.join(desc_lines), 200) if desc_lines else ""

        items.append({
            'title': title,
            'url': url,
            'relevance': relevance,
            'description': description
        })
    return items, overall_summary

def generate_section(icon, name, items, summary=""):
    html = f'<section class="section">\n  <h2>{icon} {name}</h2>\n'
    if not items:
        html += '  <p class="no-data">暂无新内容</p>\n'
    else:
        for i, it in enumerate(items[:8], 1):
            html += f'  <article class="news-item">\n'
            html += f'    <h3>{i}. {it["title"]}</h3>\n'
            if it['description']:
                html += f'    <p class="desc">{it["description"]}</p>\n'
            html += f'    <p><a href="{it["url"]}" target="_blank" rel="noopener">🔗 阅读原文</a></p>\n'
            if it['relevance']:
                html += f'    <p class="relevance">相关性：{it["relevance"]}%</p>\n'
            html += '  </article>\n'
        if summary:
            html += f'  <div class="summary"><strong>📌 今日摘要：</strong>{summary}</div>\n'
    html += '</section>\n'
    return html

post_dir = "${POST_DIR}"
try:
    with open(f"{post_dir}/hackernews_raw.txt") as f:
        hn_raw = f.read()
    with open(f"{post_dir}/reddit_raw.txt") as f:
        reddit_raw = f.read()
    with open(f"{post_dir}/producthunt_raw.txt") as f:
        ph_raw = f.read()
except:
    hn_raw = reddit_raw = ph_raw = ""

hn_items, hn_summary = parse_tavily(hn_raw)
reddit_items, reddit_summary = parse_tavily(reddit_raw)
ph_items, ph_summary = parse_tavily(ph_raw)

html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>每日科技摘要 - {ts}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }}
    header {{ margin-bottom: 30px; border-bottom: 1px solid #eee; padding-bottom: 10px; }}
    h1 {{ color: #333; }}
    .meta {{ color: #666; font-size: 0.9em; }}
    .section {{ margin-bottom: 40px; }}
    .news-item {{ margin-bottom: 25px; padding: 15px; border: 1px solid #eee; border-radius: 8px; background: #fafafa; }}
    .news-item h3 {{ margin-top: 0; color: #2c3e50; }}
    .desc {{ color: #555; }}
    .relevance {{ color: #27ae60; font-weight: bold; }}
    .summary {{ background: #e8f4f8; padding: 15px; border-radius: 8px; margin-top: 20px; }}
    .no-data {{ color: #999; font-style: italic; }}
    a {{ color: #3498db; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
  <header>
    <h1>每日科技摘要</h1>
    <p class="meta">📅 采集日期：{ts} {tnow} UTC | 📊 数据来源：Hacker News, Reddit, Product Hunt</p>
  </header>
'''

html += generate_section("📰", "Hacker News 热门", hn_items, hn_summary)
html += generate_section("🤖", "Reddit 科技/编程", reddit_items, reddit_summary)
html += generate_section("🚀", "Product Hunt 新品", ph_items, ph_summary)

html += '''
  <footer style="margin-top: 50px; padding-top: 20px; border-top: 1px solid #eee; color: #999; font-size: 0.8em;">
    <p>本摘要由 OpenClaw 自动生成，每日更新</p>
  </footer>
</body>
</html>
'''

print(html)
PYEOF

echo "📝 已生成 ${HTML_FILE}"

# 生成要插入index.html的文章块
ARTICLE=$(cat << EOF
<article class="post post-type-normal" itemscope itemtype="http://schema.org/Article">
  <div class="post-block">
    <link itemprop="mainEntityOfPage" href="https://fashion1840.github.io/snail-tech-scoop/${YEAR}/${MONTH}/${DAY}/daily-digest/">
    <span hidden itemprop="author" itemscope itemtype="http://schema.org/Person">
      <meta itemprop="name" content="疯狂的蜗牛">
      <meta itemprop="description" content="">
      <meta itemprop="image" content="/snail-tech-scoop/images/Logo.png">
    </span>
    <span hidden itemprop="publisher" itemscope itemtype="http://schema.org/Organization">
      <meta itemprop="name" content="道听书途">
    </span>
    <header class="post-header">
      <h1 class="post-title" itemprop="name headline">
        <a href="/snail-tech-scoop/${YEAR}/${MONTH}/${DAY}/daily-digest/" class="post-title-link" itemprop="url">每日科技摘要 - ${TIMESTAMP}</a>
      </h1>
      <div class="post-meta">
        <span class="post-time">
          <span class="post-meta-item-icon"><i class="fa fa-calendar-o"></i></span>
          <span class="post-meta-item-text">发表于</span>
          <time title="创建时间：${TIMESTAMP} ${TNOW}:00 +08:00" itemprop="dateCreated datePublished" datetime="${TIMESTAMP}T${TNOW}:00+08:00">${TIMESTAMP}</time>
        </span>
      </div>
    </header>
    <div class="post-body" itemprop="articleBody">
      <p>每日科技新闻摘要，点击阅读原文查看详情。</p>
    </div>
    <footer class="post-footer"></footer>
  </div>
</article>
EOF
)

echo "$ARTICLE" > "${POST_DIR}/index_article.html"

# 更新index.html
if [ -f "$INDEX_FILE" ]; then
    echo "📝 更新首页 index.html..."

    SECTION_PATTERN='<section id="posts" class="posts-expand">'
    SECTION_LINE=$(grep -n "$SECTION_PATTERN" "$INDEX_FILE" | cut -d: -f1 | head -1)

    if [ -n "$SECTION_LINE" ]; then
        NEXT_ARTICLE_LINE=$(sed -n "${SECTION_LINE},$p" "$INDEX_FILE" | grep -n '<article' | head -1 | cut -d: -f1)
        if [ -n "$NEXT_ARTICLE_LINE" ]; then
            INSERT_LINE=$((SECTION_LINE + NEXT_ARTICLE_LINE - 1))
        else
            INSERT_LINE=$((SECTION_LINE + 1))
        fi

        TMP_FILE=$(mktemp)
        head -n $((INSERT_LINE - 1)) "$INDEX_FILE" > "$TMP_FILE"
        echo "" >> "$TMP_FILE"
        echo "$ARTICLE" >> "$TMP_FILE"
        echo "" >> "$TMP_FILE"
        tail -n +$INSERT_LINE "$INDEX_FILE" >> "$TMP_FILE"
        mv "$TMP_FILE" "$INDEX_FILE"

        echo "✅ 已更新 index.html（在第${INSERT_LINE}行插入）"
    else
        echo "❌ 未找到posts section"
    fi
else
    echo "❌ index.html 不存在"
fi

cd "$WORKDIR"
git pull --rebase origin master || true
git add "${YEAR}/${MONTH}/${DAY}/"
git add index.html
git commit -m "添加每日摘要 ${TIMESTAMP}（仓库重命名为 snail-tech-scoop）" || true

if git push origin master; then
    echo "🚀 推送完成！"
else
    echo "⚠️ 推送失败，稍后重试"
    exit 1
fi