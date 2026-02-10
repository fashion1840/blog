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
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
POST_DIR="${WORKDIR}/${YEAR}/${MONTH}/${DAY}/daily-digest"
MARKDOWN_FILE="${POST_DIR}/index.md"

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

echo "✅ 搜索完成，生成Markdown..."

python3 - << 'PYEOF' > "${MARKDOWN_FILE}"
import re
from datetime import datetime
import os

# 从环境变量获取路径
post_dir = os.environ.get('POST_DIR', '/tmp')
year = os.path.basename(os.path.dirname(os.path.dirname(post_dir)))
month = os.path.basename(os.path.dirname(post_dir))
day = os.path.basename(post_dir.rstrip('/'))

ts = datetime.now().strftime("%Y-%m-%d")
tnow = datetime.now().strftime("%H:%M")

# Hexo Front Matter - 符合你的博客结构
front_matter = f"""---
title: 每日科技摘要 - {ts}
date: {ts} {tnow}
tags: [daily-digest, tech-news]
categories: [科技资讯]
layout: post
---
"""

md = f"{front_matter}# 每日科技摘要\n\n> 📅 采集日期：{ts} {tnow} UTC\n> 📊 数据来源：Hacker News, Reddit, Product Hunt\n\n---\n\n"

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

def section(icon, name, fn):
    try:
        raw = open(fn).read()
        if not raw.strip():
            return f"## {icon} {name}\n\n*暂无数据*\n\n"
        items, summary = parse_tavily(raw)

        if not items:
            return f"## {icon} {name}\n\n*暂无新内容*\n\n"

        out = f"## {icon} {name}\n\n"

        for i, it in enumerate(items[:8], 1):
            out += f"### {i}. {it['title']}\n\n"
            if it['description']:
                out += f"{it['description']}\n\n"
            out += f"[🔗 阅读原文]({it['url']})\n\n"
            if it['relevance']:
                out += f"*相关性：{it['relevance']}%*\n\n"
            out += "---\n\n"

        if summary:
            out += f"**📌 今日摘要**：{summary}\n\n"

        return out
    except Exception as e:
        return f"## {icon} {name}\n\n*读取失败*\n\n"

md += section("📰", "Hacker News 热门", f"{post_dir}/hackernews_raw.txt")
md += section("🤖", "Reddit 科技/编程", f"{post_dir}/reddit_raw.txt")
md += section("🚀", "Product Hunt 新品", f"{post_dir}/producthunt_raw.txt")

md += "---\n\n*本摘要由 OpenClaw 自动生成，每日更新*"

print(md)
PYEOF

echo "📝 已生成 ${MARKDOWN_FILE}"

cd "$WORKDIR"
git pull --rebase origin master || true
git add "${YEAR}/${MONTH}/${DAY}/"
git commit -m "添加每日摘要 ${ts}" || true
git push origin master

echo "🚀 推送完成！"