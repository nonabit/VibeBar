# Domain Docs

本文件说明工程技能在探索代码库时应如何消费本仓库的领域文档。

## 探索前读取这些文件

- 根目录 `CONTEXT.md`
- 如果根目录存在 `CONTEXT-MAP.md`，则它会指向每个上下文对应的 `CONTEXT.md`；读取与当前任务相关的上下文
- `docs/adr/`：读取与当前工作区域相关的 ADR

如果这些文件不存在，静默继续。不要仅因为文件缺失就提示创建；生产者技能会在术语或决策真正沉淀时按需创建。

## 文件结构

本仓库按 single-context repo 处理：

```text
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-example-decision.md
│   └── 0002-example-decision.md
└── Sources/
```

## 使用 glossary 中的词汇

当输出中命名领域概念时，例如 issue 标题、重构建议、诊断假设或测试名称，优先使用 `CONTEXT.md` 中定义的术语。

如果需要的概念还没有进入 glossary，说明可能存在命名偏移或真实文档缺口；在输出中简短指出即可。

## 标记 ADR 冲突

如果输出与已有 ADR 冲突，明确指出冲突，而不是静默覆盖。
