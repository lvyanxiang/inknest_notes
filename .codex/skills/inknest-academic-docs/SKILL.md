---
name: inknest-academic-docs
description: Dedicated workflow for maintaining InkNest Notes graduation academic documents. Use when Codex is asked to update, review, improve, convert, or verify the task book, opening report, academic writing requirements, graduation schedule, formal references, or related docs under docs/academic. Do not use for normal Flutter/Python product development unless the user explicitly asks to update academic documents.
---

# InkNest Academic Docs

## Overview

Use this skill only for the academic graduation document set. Keep it separate
from `inknest-project`: ordinary code, roadmap, and Flutter/Python
implementation work must not automatically rewrite the task book or opening
report.

## Source Files

Read the smallest useful set:

1. `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md`
2. The target document:
   - `docs/academic/GRADUATION_TASK_BOOK.md`
   - `docs/academic/OPENING_REPORT.md`
3. Supporting academic assets when relevant:
   - `docs/academic/assets/2026_summer_graduation_schedule.png`
   - user-provided templates, PDFs, screenshots, or Word files

Use the Documents skill when the user asks for `.doc`, `.docx`, Word layout,
format conversion, comments, or render-and-verify work. Use PDF extraction tools
when the user supplies writing-requirement PDFs that need to be read.

## Boundaries

- Do not update academic documents during normal development tasks unless the
  user explicitly asks for academic document maintenance or invokes this skill.
- Do not change application code, roadmap checkboxes, or implementation scope
  while using this skill unless the user asks for that separately.
- If a code or product plan change may affect the task book or opening report,
  mention that academic docs can be updated later with this skill, but do not
  edit them as part of the code task.
- Keep `inknest-project` focused on development execution; keep this skill
  focused on formal graduation deliverables.

## Workflow

1. Read `ACADEMIC_WRITING_REQUIREMENTS.md` first and treat it as the local rule
   book.
2. Read only the target academic document and any directly relevant support
   files.
3. Confirm the document still uses the topic:
   `基于 Flutter 与 Python 的跨平台数字笔记系统的设计与实现`.
4. Keep formal wording suitable for submission. Do not leave internal phrases
   such as "后续再补", "项目尚未补充", "保留题目合理性", "占位", or "待确认" in
   submit-ready task book or opening report text.
5. Distinguish implemented scope from planned design using formal wording such
   as "Python 模块设计", "接口规划", "扩展方案", and "按实际完成情况纳入测试".
6. Keep task book and opening report consistent on topic name, scope boundary,
   progress plan, expected outputs, and reference basis.
7. Update `ACADEMIC_WRITING_REQUIREMENTS.md` only when the rule itself changes
   or new school guidance is extracted.

## Reference Rules

References are high-risk and must be verified carefully.

- Browse or otherwise verify current bibliographic information when adding,
  replacing, or claiming "latest" literature.
- When replacing literature, search recent 3-5 year academic journal papers
  first and prefer the newest verifiable sources that actually support the
  document's argument. Classic foundational papers may be kept only when they
  directly support a key point and are balanced with newer sources.
- Every formal reference must be real: verify title, authors, journal name,
  year, volume/issue, pages, and DOI or publisher/database record when possible.
- Use the Shanghai University Library journal navigation page at
  `https://findshu.libsp.cn/#/magazineNav` as the required school holdings
  check. Search from that page by journal title, not full article title. Verify
  both: journal title is found, and the cited article year falls inside the
  listed electronic holdings coverage years.
- Treat `https://findshu.libsp.cn/#/magazineNav` as the authoritative school
  library entry for formal reference screening. Other databases, DOI pages, or
  publisher pages may help verify bibliographic details, but they do not replace
  the school journal-navigation holdings check.
- Do not include a paper in the formal reference list unless the body actually
  uses it. Add or adjust body citation markers where the source supports a claim,
  or remove the unused reference.
- Opening report main references must include at least 10 academic journal
  papers and at least one English original source. Task book references must
  include at least 3 sources and at least one English source.
- Do not use arXiv, official framework docs, tutorials, blogs, project docs, or
  generic web pages as the main formal academic reference list unless school
  guidance explicitly allows them. If useful, keep them as auxiliary materials
  outside the main academic-journal list.
- If a candidate cannot be verified, do not present it as confirmed. Replace it
  or state the remaining uncertainty to the user.

## Quality Checks

Before finishing, run focused checks when files were edited:

```bash
git diff --check
rg -n '[ \t]$' docs/academic docs/development/STATUS.md
```

Also check reference counts after reference edits:

```bash
awk '/^## （四）主要文献/{flag=1; next} /^## （五）/{flag=0} flag && /^\[[0-9]+\]/{count++} END{print count}' docs/academic/GRADUATION_TASK_BOOK.md
awk '/^### 4\.1 学术文献/{flag=1; next} /^## 预期成果/{flag=0} flag && /^\[[0-9]+\]/{count++} END{print count}' docs/academic/OPENING_REPORT.md
```

Report whether validation passed and whether `git add` was left for the user.
