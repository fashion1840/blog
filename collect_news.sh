#!/bin/bash
# 每日搜集 Hacker News, Reddit, Product Hunt 24小时内热门信息
# 输出为Markdown并推送到GitHub博客

set -e

# 加载环境变量（token从.env文件读取）
if [ -f "/root/.openclaw/workspace/blog-deploy/.env" ]; then
    export $(grep -v '^#' /root/.openclaw/workspace/blog-deploy/.env | xargs)
fi

# 必需的环境变量检查
: "${TAVILY_API_KEY:?需要设置TAVILY_API_KEY}"
: "${GITHUB_TOKEN:?需要设置GITHUB_TOKEN}"

REPO_URL="https://${GITHUB_TOKEN}@github.com/fashion1840/blog.git"
WORKDIR="/root/.openclaw/workspace/blog-deploy"
OUTPUT_DIR="${WORKDIR}/posts"
TIMESTAMP=$(date +%Y-%m-%d)
MARKDOWN_FILE="${OUTPUT_DIR}/${TIMESTAMP}-daily-digest.md"

echo "🔍 开始搜集24小时内的热门信息..."

# 使用tavily搜索各平台
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Hacker News top stories last 24 hours" \
  -n 8 \
  --topic news \
  --days 1 \
  > "${OUTPUT_DIR}/hackernews_raw.json" 2>/dev/null || echo "[]" > "${OUTPUT_DIR}/hackernews_raw.json"

node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Reddit popular posts r/technology r/programming past 24 hours" \
  -n 8 \
  --topic news \
  --days 1 \
  > "${OUTPUT_DIR}/reddit_raw.json" 2>/dev/null || echo "[]" > "${OUTPUT_DIR}/reddit_raw.json"

node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Product Hunt latest launches past 24 hours" \
  -n 8 \
  --topic news \
  --days 1 \
  > "${OUTPUT_DIR}/producthunt_raw.json" 2>/dev/null || echo "[]" > "${OUTPUT_DIR}/producthunt_raw.json"

echo "✅ 搜索完成，开始生成Markdown..."

# 解析JSON并生成Markdown
python3 - << 'PYTHON_EOF' > "${MARKDOWN_FILE}"
import json
import sys
from datetime import datetime

timestamp = datetime.now().strftime("%Y-%m-%d")
time_str = datetime.now().strftime("%H:%M UTC")

md = f"""# Daily Tech Digest - {timestamp}

*采集时间：{timestamp} {time_str} | 数据来源：Hacker News, Reddit, Product Hunt*

---

"""

# Hacker News
try:
    with open("/root/.openclaw/workspace/blog-deploy/posts/hackernews_raw.json") as f:
        data = json.load(f)
        if isinstance(data, list) and data:
            md += "## 📰 Hacker News 热门\n\n"
            for i, item in enumerate(data[:8], 1):
                title = item.get('title', 'No title')
                url = item.get('url', '#')
                relevance = item.get('relevance', 'N/A')
                md += f"{i}. **{title}**\n   - 链接: {url}\n   - 相关性: {relevance}%\n\n"
        else:
            md += "## 📰 Hacker News 热门\n\n*暂无新内容*\n\n"
except Exception as e:
    md += "## 📰 Hacker News 热门\n\n*读取数据失败*\n\n"

# Reddit
try:
    with open("/root/.openclaw/workspace/blog-deploy/posts/reddit_raw.json") as f:
        data = json.load(f)
        if isinstance(data, list) and data:
            md += "## 🤖 Reddit 科技/编程\n\n"
            for i, item in enumerate(data[:8], 1):
                title = item.get('title', 'No title')
                url = item.get('url', '#')
                md += f"{i}. **{title}**\n   - 链接: {url}\n\n"
        else:
            md += "## 🤖 Reddit 科技/编程\n\n*暂无新内容*\n\n"
except Exception as e:
    md += "## 🤖 Reddit 科技/编程\n\n*读取数据失败*\n\n"

# Product Hunt
try:
    with open("/root/.openclaw/workspace/blog-deploy/posts/producthunt_raw.json") as f:
        data = json.load(f)
        if isinstance(data, list) and data:
            md += "## 🚀 Product Hunt 新品\n\n"
            for i, item in enumerate(data[:8], 1):
                title = item.get('title', 'No title')
                url = item.get('url', '#')
                md += f"{i}. **{title}**\n   - 链接: {url}\n\n"
        else:
            md += "## 🚀 Product Hunt 新品\n\n*暂无新内容*\n\n"
except Exception as e:
    md += "## 🚀 Product Hunt 新品\n\n*读取数据失败*\n\n"

md += "---\n\n*自动生成，每日更新*"

print(md)
PYTHON_EOF

echo "📝 生成完成：${MARKDOWN_FILE}"

# 推送到GitHub
cd "${WORKDIR}"
git add posts/
git commit -m "Add daily digest ${TIMESTAMP}" || echo "No changes to commit"
git push origin master

echo "🚀 推送完成！"