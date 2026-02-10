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
OUTPUT_DIR="${WORKDIR}/posts"
TIMESTAMP=$(date +%Y-%m-%d)
MARKDOWN_FILE="${OUTPUT_DIR}/${TIMESTAMP}-daily-digest.md"

mkdir -p "$OUTPUT_DIR"

echo "🔍 开始搜集24小时内的热门信息..."

# Hacker News
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Hacker News top stories last 24 hours" \
  -n 8 --topic news --days 1 \
  > "${OUTPUT_DIR}/hackernews_raw.txt" 2>/dev/null || echo "" > "${OUTPUT_DIR}/hackernews_raw.txt"

# Reddit
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Reddit popular posts r/technology r/programming past 24 hours" \
  -n 8 --topic news --days 1 \
  > "${OUTPUT_DIR}/reddit_raw.txt" 2>/dev/null || echo "" > "${OUTPUT_DIR}/reddit_raw.txt"

# Product Hunt
node "/root/.openclaw/workspace/skills/tavily-search/scripts/search.mjs" \
  "Product Hunt latest launches past 24 hours" \
  -n 8 --topic news --days 1 \
  > "${OUTPUT_DIR}/producthunt_raw.txt" 2>/dev/null || echo "" > "${OUTPUT_DIR}/producthunt_raw.txt"

echo "✅ 搜索完成，生成Markdown..."

python3 - << 'PYEOF' > "${MARKDOWN_FILE}"
import re
from datetime import datetime

ts = datetime.now().strftime("%Y-%m-%d")
tnow = datetime.now().strftime("%H:%M")

# Hexo Front Matter（兼容标准Hexo主题）
front_matter = f"""---
title: 每日科技摘要 - {ts}
date: {ts} {tnow}
tags: [daily-digest, tech-news]
categories: [科技资讯]
description: 每日科技新闻摘要，包含Hacker News、Reddit和Product Hunt的最新热门内容
---
"""

md = f"{front_matter}# 每日科技摘要\n\n> 📅 采集日期：{ts} {tnow} UTC\n> 📊 数据来源：Hacker News, Reddit, Product Hunt\n\n---\n\n"

def clean_text(text, max_len=300):
    """清理文本，提取前max_len字符作为摘要"""
    # 移除多余空白
    text = re.sub(r'\s+', ' ', text)
    text = text.strip()
    # 截断到合适长度
    if len(text) > max_len:
        text = text[:max_len].rsplit(' ', 1)[0] + '...'
    return text

def parse_tavily(text):
    items = []
    # 提取Answer作为整体摘要
    answer_match = re.search(r'## Answer\s+(.*?)(?=\n##|\Z)', text, re.DOTALL)
    overall_summary = clean_text(answer_match.group(1), 500) if answer_match else ""

    # 提取Sources中的每一条
    sources_match = re.search(r'## Sources\s+(.*)', text, re.DOTALL)
    if not sources_match:
        return [], overall_summary

    src = sources_match.group(1)
    # 分割条目
    entries = re.split(r'(?=^- \*\*)', src, flags=re.MULTILINE)

    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue

        # 标题
        title_match = re.search(r'- \*\*(.*?)\*\*', entry)
        title = title_match.group(1).strip() if title_match else '无标题'

        # 相关性
        rel_match = re.search(r'\(relevance:\s*(\d+)%\)', entry)
        relevance = rel_match.group(1) if rel_match else None

        # URL
        url_match = re.search(r'(https?://[^\s\)]+)', entry)
        url = url_match.group(1) if url_match else '#'

        # 提取描述（去掉标题行、URL行、relevance行之后的内容）
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

md += section("📰", "Hacker News 热门", "/root/.openclaw/workspace/blog-deploy/posts/hackernews_raw.txt")
md += section("🤖", "Reddit 科技/编程", "/root/.openclaw/workspace/blog-deploy/posts/reddit_raw.txt")
md += section("🚀", "Product Hunt 新品", "/root/.openclaw/workspace/blog-deploy/posts/producthunt_raw.txt")

md += "---\n\n*本摘要由 OpenClaw 自动生成，每日更新*"

print(md)
PYEOF

echo "📝 已生成 ${MARKDOWN_FILE}"

cd "$WORKDIR"
git pull --rebase origin master || true
git add posts/
git commit -m "更新每日摘要 ${TIMESTAMP}（Hexo格式+中文摘要）" || true
git push origin master

echo "🚀 推送完成！"