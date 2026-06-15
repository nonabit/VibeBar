# Issue tracker: Local Markdown

本仓库的 issues 和 PRD 以 Markdown 文件形式保存在 `.scratch/` 下。

## 约定

- 每个功能一个目录：`.scratch/<feature-slug>/`
- PRD 文件为 `.scratch/<feature-slug>/PRD.md`
- 实现 issue 文件为 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号
- triage 状态记录在每个 issue 文件顶部附近的 `Status:` 行中；角色字符串见 `triage-labels.md`
- 评论和对话历史追加在文件底部的 `## Comments` 标题下

## 当技能要求“publish to the issue tracker”时

在 `.scratch/<feature-slug>/` 下创建新文件；如果目录不存在，先创建目录。

## 当技能要求“fetch the relevant ticket”时

读取用户给出的路径对应的文件。用户通常会直接提供文件路径或 issue 编号。
