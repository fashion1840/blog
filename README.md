# 道听书途 - 个人博客

> 一个基于 static pages 的静态博客，分享科技、阅读与生活。

## 📝 每日科技摘要

本博客提供**两种每日科技摘要**，满足不同的信息需求：

### 1️⃣ 每日科技摘要 (Hacker News / Reddit / Product Hunt)

汇集过去24小时内最热门的**技术社区讨论**和**新产品发布**。

- **数据来源**：Hacker News, Reddit (r/technology, r/programming), Product Hunt
- **发布时间**：每天下午（约 18:00-19:00 UTC+8）
- **结构**：按日期归档，路径格式 `posts/YYYY-MM-DD-daily-digest.md`
- **示例**：[2026-02-10 每日科技摘要](posts/2026-02-10-daily-digest.md)

---

### 2️⃣ AI Daily Report (AI 领域深度报道)

由 AI 自动搜集、精选并整理的**人工智能领域深度新闻**。

- **数据来源**：Tavily AI Search (覆盖 WSJ, TechCrunch 等主流科技媒体)
- **发布时间**：每天午夜 00:00（UTC+8）
- **结构**：独立目录 `ai-daily/`，路径格式 `ai-daily/daily-YYYY-MM-DD.html`
- **示例**：[2026-02-11 AI Daily Report](ai-daily/latest.html)
- **自动化**：由 OpenClaw cron 任务自动执行和推送

---

## 🛠️ 技术栈

- **Hexo** - 静态博客生成器 (用于每日科技摘要)
- **Next Theme** - 博客主题
- **GitHub Pages** - 托管平台
- **OpenClaw** - AI 自动化代理，负责 AI Daily Report 生成与部署

## 📬 联系方式
- 作者：疯狂的蜗牛
- 邮箱：your-email@example.com

---

*最后更新时间：2026-02-11*