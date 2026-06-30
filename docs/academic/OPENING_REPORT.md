# 毕业设计（论文）开题报告（Markdown 维护版）

> 本文档根据 `开题报告（模板）.docx` 与 `开题报告撰写注意点.pdf` 整理，并结合 InkNest Notes 当前项目计划填写。后续项目计划、技术路线、实现范围或论文题目发生变化时，应先对照 `docs/academic/ACADEMIC_WRITING_REQUIREMENTS.md`，再与 `docs/academic/GRADUATION_TASK_BOOK.md` 同步维护。

## 待补充信息

- 专业：TODO
- 学号：TODO
- 姓名：TODO
- 指导教师：TODO
- Python 项目位置：TODO（后续补充；当前先在本仓库统一维护 Flutter 前端与毕业文档）
- 日期：TODO 年 TODO 月 TODO 日

## 文档定位

本文档是毕业设计开题报告的 Markdown 维护稿，用于跟随项目计划持续更新。正式提交前，应将内容整理到学校 Word 模板中，并补齐个人信息、指导教师、日期和签名栏。当前课题题目包含 Flutter 与 Python 两部分；本仓库先维护 Flutter 前端项目与毕业文档，Python 项目后续补充后，再同步完善系统架构、接口设计、部署方式和测试内容。

## 撰写注意点落实清单

- “意义”必须围绕本项目，不宜过大；要说明科学价值、社会价值或经济价值。
- “国内外发展状况”先写国内，再写国外；围绕本课题相关内容综合概述，再用案例论证。
- 国内外案例应尽量各列 3 个以上；若提交篇幅有限，可保留典型案例并在正文中说明分类逻辑。
- 参考文献用于证明项目有价值、技术可行、方向合理，而不是写文献读后感。
- “研究内容”按软件工程思维组织，可作为论文提纲，后续论文撰写时允许调整章节名称和数量。
- “研究方法、手段及步骤”应与任务书进度计划保持一致。
- 参考文献不少于 10 篇，至少 1 篇英文原文；提交前需按学院格式复核。

## 课题名称

基于 Flutter 与 Python 的跨平台数字笔记系统的设计与实现

## 课题来源

自拟

## 1、本选题的意义及国内外发展状况

### 1.1 选题意义

数字笔记已经从简单的文本记录发展为融合手写、图片、PDF、音频、搜索和知识管理的综合工具。对于学生和办公用户而言，课堂讲义、论文资料、会议纪要和个人灵感常常同时包含手写标注、文档批注、结构化整理和后续复习等需求。传统纸质笔记具有书写自然的优势，但在检索、备份、跨设备使用和资料复用方面存在不足；普通在线文档便于编辑和协作，却难以完整替代手写推导、图形标注和 PDF 阅读批注。

InkNest Notes 选择“手写笔记 + PDF 批注 + 本地可靠保存 + 后续知识库扩展”作为核心方向，具有较明确的应用价值。第一，面向学习场景，用户可以在 PDF 讲义、论文和教材上直接书写、插入空白页并导出批注结果。第二，面向会议和办公场景，用户可以通过多页笔记、文本框、图片、图形和后续音频录制记录复杂信息。第三，面向长期知识管理，项目以可检查的本地文件结构保存笔记，为后续跨设备同步、手机快速捕获和 Web 知识库奠定基础。第四，项目采用 Flutter 与 Python 的组合方向：Flutter 负责跨平台前端与手写交互，Python 后续可承担服务接口、检索、识别、同步或数据处理等扩展能力。当前仓库先统一维护 Flutter 前端项目和毕业文档，待 Python 项目补充后再同步扩展相关章节。

因此，本课题不仅是一个移动端应用开发实践，也包含手写交互、文档渲染、本地持久化、PDF 导出、数据可靠性和软件工程模块化设计等综合训练内容。通过本课题，可以验证 Flutter 在复杂手写交互和跨平台界面开发中的适用性，也可以为后续使用 Python 扩展搜索、识别、同步和知识处理能力提供系统边界。

### 1.2 国内发展状况

国内数字笔记和知识管理产品主要呈现三类发展方向。第一类是在线文档与知识库产品，例如语雀、飞书文档、腾讯文档等，其优势在于多人协作、文档结构化组织、权限管理和团队知识沉淀。这类产品更接近“文档协作”和“知识库”场景，对 Markdown、富文本、表格和链接关系支持较好，但对平板手写、PDF 深度批注和离线书写体验的支持相对不是核心。

第二类是办公套件与 PDF 工具，例如 WPS、金山文档、各类 PDF 阅读器和批注工具。这类产品在文档格式兼容、PDF 阅读、批注和导出方面成熟，适合正式办公资料处理，但常见交互仍以文档编辑、阅读和批注为中心，和“笔记本式分页手写”“课堂笔记复习”“音频与笔迹联动”等学习型笔记流程存在差异。

第三类是手机和平板厂商生态内置笔记，例如华为笔记、Apple 备忘录对应的国内设备替代生态、小米笔记等。这类产品通常具备便捷记录、拍照、基础手写或云同步能力，与硬件结合紧密，但跨平台能力、复杂 PDF 学习流程、开放导出和知识库式组织能力受到生态限制。

从案例上看，语雀代表了知识库式组织，飞书文档和腾讯文档代表了多人协作办公，WPS 与常见 PDF 工具代表了文档编辑和批注处理，厂商自带笔记则代表了设备生态内的快速记录。上述产品各有优势，但通常会在“手写体验、PDF 学习流程、离线优先保存、可导出闭环、跨端扩展”之间有所取舍。InkNest Notes 将毕业设计范围聚焦在个人笔记与 PDF 学习流程，避开早期复杂团队协作，先实现可靠的本地笔记核心，再逐步扩展同步和知识库能力。

### 1.3 国外发展状况

国外数字笔记产品在平板手写和学习场景上已有较成熟的代表。Goodnotes 以手写笔记、笔记本组织、PDF 导入批注、模板和搜索等能力形成了较强的 iPad 学习场景；Notability 强调手写、文本、图片、PDF 和音频录制的混合记录，并通过录音回放与笔记内容关联提升课堂和会议复习效率；Microsoft OneNote 则以跨平台自由画布、云同步、图片 OCR、音频笔记和协作能力形成通用知识记录工具。

除通用软件外，reMarkable、Kindle Scribe 等硬件与软件结合的产品也说明“低干扰、接近纸张的数字书写体验”具有持续需求。这类产品强调纸感书写、专注阅读、手写转文本和云同步，但其生态往往与特定硬件绑定。近年来，学术研究也在持续关注数字墨迹表达、在线手写识别、语音笔记、混合现实课堂记录和 AI 辅助个人知识管理，说明数字笔记正在向多模态、可搜索、可复用的知识系统演进。

从发展趋势看，国外产品已经证明手写笔记和 PDF 批注具有稳定用户需求，但成熟产品通常功能庞大、商业闭源，并且本地数据结构和后续扩展不可控。本课题的价值在于用 Flutter 与 Python 构建结构清晰、可解释、可扩展的跨平台数字笔记系统原型，当前重点验证 Flutter 前端中的分页笔记、可靠保存、PDF 批注导出和后续音频/搜索扩展的技术可行性，后续再补充 Python 服务与数据处理能力。

### 1.4 拟解决的主要问题

本课题拟重点解决以下问题：

1. 如何设计适合手写和 PDF 批注的分页笔记数据模型，兼顾页面顺序、PDF 背景、笔迹、文本、图片和图形等元素。
2. 如何在 Flutter 中实现低冲突的触控交互，使单指书写、双指缩放平移、手指拖动画布和工具栏操作能够稳定配合。
3. 如何设计本地优先的文件存储结构，使笔记内容可保存、可恢复、可迁移，并为后续同步和 Python 服务扩展预留空间。
4. 如何实现 PDF 导入、页面背景渲染、批注叠加和 PDF 导出，使用户可以形成完整的学习资料输出。
5. 如何规划 Python 模块与 Flutter 前端的边界，使后续搜索、识别、同步或数据处理能力能够自然接入系统。

## 2、本课题的研究内容（论文撰写提纲）

### 第一章 绪论

介绍课题背景、研究意义、国内外发展状况、课题目标、主要工作和论文结构。

### 第二章 需求分析与可行性分析

分析目标用户、使用场景和功能需求，包括笔记库管理、手写编辑、多页笔记、PDF 批注、导出、富内容编辑、音频与搜索扩展、Python 服务扩展等。分析技术可行性、经济可行性和操作可行性，明确毕业设计范围与非目标范围。

### 第三章 系统总体设计

阐述系统架构、模块划分、数据模型和存储设计。重点说明 `Notebook`、`NotePage`、`Stroke`、`NoteTextBox`、`NoteImage`、`NoteShape`、`PdfBackground` 等核心模型，以及应用层、功能层、模型层、存储层和导出层的关系；Python 项目补充后，继续完善前后端接口、数据交换和服务层设计。

### 第四章 关键模块设计与实现

详细说明笔记库模块、手写编辑器模块、本地文件仓储、PDF 导入与渲染、PDF 导出、页面缩略图、文本框、图片、图形、Smart Ink 初版、音频录制和搜索扩展的设计与实现方法。说明 Flutter `CustomPainter`、Pointer 事件、文件选择、PDF 渲染、JSON 序列化和导出管线的使用；后续结合 Python 项目补充服务接口、搜索索引、OCR/手写识别或同步处理模块的实现。

### 第五章 Python 扩展模块设计

说明 Python 模块在跨平台数字笔记系统中的定位，包括服务接口、搜索索引、OCR/手写识别、数据同步或知识库处理等候选方向。若后续 Python 项目在答辩前完成，则补充接口定义、运行方式、关键代码和测试结果；若未完成，则作为系统扩展设计与后续工作说明。

### 第六章 系统测试与结果分析

设计功能测试、模型测试、仓储测试、PDF 导出测试和关键交互测试。说明测试环境、测试用例、测试结果和问题修复情况，并结合 `flutter test`、`flutter analyze`、`dart format` 和 `git diff --check` 等检查结果评价系统质量。

### 第七章 总结与展望

总结课题完成情况、主要成果和不足，展望跨设备同步、云备份、手写识别、OCR、音频转写、Web 知识库、协作和 AI 辅助学习等后续方向。

## 3、研究方法、手段及步骤（进度计划）

### 3.1 研究方法

- 文献研究法：查阅数字笔记、手写输入、学习记录、手写识别、移动端离线存储和跨端应用开发等资料，为需求分析和技术选型提供依据。
- 产品比较法：比较 Goodnotes、Notability、OneNote、语雀、WPS/PDF 工具等产品，提炼毕业设计中可实现且有代表性的核心功能。
- 软件工程方法：按照需求分析、概要设计、详细设计、编码实现、测试验证和总结改进的流程推进。
- 原型迭代法：先实现本地笔记和手写核心，再逐步加入 PDF、导出、富内容、音频和搜索能力，保持每个阶段可运行、可测试。
- 测试验证法：通过单元测试、组件测试、手动交互测试和导出文件检查验证系统正确性和稳定性。

### 3.2 技术手段

- 开发框架：Flutter、Dart 与 Python。当前仓库以 Flutter 前端实现为主，Python 项目后续补充。
- 界面绘制：使用 Flutter Widget、`CustomPainter` 和 Pointer 事件实现手写画布、笔迹渲染和交互控制。
- 本地存储：使用 `path_provider` 获取应用文档目录，以 JSON 文件保存笔记本、页面、笔迹和元素数据。
- 文件导入：使用 `file_picker` 选择 PDF 和图片等外部文件。
- PDF 渲染：使用 `pdfrx` 渲染导入 PDF 页面背景。
- PDF 导出：使用 `pdf` 和 `image` 包生成包含背景、笔迹、文本、图片和图形的 PDF 文件。
- Python 扩展：后续用于服务接口、数据处理、搜索索引、OCR/手写识别、同步备份或 Web 知识库支撑；具体框架和项目结构待 Python 项目补充后确定。
- 架构组织：代码按 `lib/app`、`lib/features`、`lib/models`、`lib/storage`、`lib/export` 分层，便于维护和论文说明。

### 3.3 技术路线

本课题采用“前端先行、本地闭环、后续扩展”的技术路线。首先使用 Flutter 搭建跨平台前端，完成笔记库、手写编辑器、PDF 批注和导出等核心流程；其次通过本地 JSON 文件和资源目录建立可检查、可迁移的数据基础；再次在数据模型中预留文本、图片、图形、Smart Ink、音频、搜索和同步字段；最后在 Python 项目补充后，通过接口或文件数据处理方式接入搜索索引、OCR/手写识别、同步备份或知识库处理能力。

### 3.4 可行性分析

- 技术可行性：Flutter 已能满足跨平台界面、触控事件、画布绘制和文件交互需求；现有项目已具备笔记库、编辑器、PDF、导出和本地存储基础。Python 适合后续承担文本处理、检索、识别服务和数据同步等扩展任务。
- 经济可行性：课题主要使用开源框架和本地开发环境，不依赖昂贵硬件或商业云服务；基础功能可在本地完成，后续云能力可作为扩展。
- 操作可行性：系统面向常见学习和办公流程，入口为笔记库，核心操作为创建笔记、书写、导入 PDF、批注和导出，用户理解成本较低。
- 进度可行性：当前 Flutter 前端已经具备较多基础功能，后续重点放在音频、搜索、Python 扩展规划、测试和论文整理，进度风险可控。

### 3.5 实施步骤与进度计划

| 阶段 | 建议时间 | 主要任务 | 输出成果 |
| --- | --- | --- | --- |
| 需求与开题 | 第 1-2 周 | 完成选题、需求调研、技术调研、任务书和开题报告 | 开题报告、任务书 |
| 基础框架 | 第 3-4 周 | 搭建 Flutter 项目、主题、导航、笔记库、模型和仓储接口 | 应用基础框架 |
| 手写编辑 | 第 5-6 周 | 实现手写画布、笔迹模型、画笔工具、橡皮擦、撤销/重做和多页笔记 | 手写编辑器 |
| 本地保存 | 第 7 周 | 实现 JSON 持久化、页面保存、笔记本恢复和仓储测试 | 本地可靠保存 |
| PDF 流程 | 第 8-9 周 | 实现 PDF 导入、背景渲染、批注保存、目录、书签和 PDF 导出 | PDF 批注与导出 |
| 富内容与优化 | 第 10-11 周 | 实现文本框、手写风格文本、图片、图形、缩略图、页面操作和常用笔工具栏 | 完整编辑体验 |
| Python 扩展规划 | 第 12 周 | 明确 Python 项目的职责边界，设计接口、搜索索引、OCR/手写识别、同步或数据处理方案 | Python 模块设计草案 |
| 音频与搜索 | 第 13 周 | 实现音频录制，探索笔迹时间线、PDF 搜索、OCR 和手写识别 | 学习辅助能力 |
| 测试与论文 | 第 14-15 周 | 完成功能测试、静态检查、论文初稿、演示材料和问题修复 | 论文初稿、演示系统 |
| 定稿与答辩 | 学院答辩前 | 完成论文定稿、答辩 PPT、最终演示和项目归档 | 论文定稿、答辩材料 |

## 4、已查阅参考文献

> 提交前需按学院“毕设指导细则”统一格式。以下包含学术论文、预印本和技术资料；若指导教师要求严格限定为“期刊论文”，应将会议论文、预印本和官方文档替换或移入“技术资料”附表。

[1] Mueller P A, Oppenheimer D M. The Pen Is Mightier Than the Keyboard: Advantages of Longhand Over Laptop Note Taking[J]. Psychological Science, 2014, 25(6): 1159-1168.

[2] Jansen R S, Lakens D, IJsselsteijn W A. An integrative review of the cognitive costs and benefits of note-taking[J]. Educational Research Review, 2017, 22: 223-233.

[3] Piolat A, Olive T, Kellogg R T. Cognitive effort during note-taking[J]. Applied Cognitive Psychology, 2005, 19: 291-312.

[4] Makany T, Kemp J, Dror I E. Optimising the use of note-taking as an external cognitive aid for increasing learning[J]. British Journal of Educational Technology, 2009, 40(4): 619-635.

[5] Van Meter P, Yokoi L, Pressley M. College students' theory of note-taking derived from their perceptions of note-taking[J]. Journal of Educational Psychology, 1994, 86(3): 323-338.

[6] Luo L, Kiewra K A, Flanigan A E, Peteranetz M S. Laptop versus longhand note taking: effects on lecture notes and achievement[J]. Instructional Science, 2018.

[7] Jin Z, Webb S. Does writing words in notes contribute to vocabulary learning?[J]. Language Teaching Research, 2021.

[8] Plamondon R, Srihari S N. Online and off-line handwriting recognition: a comprehensive survey[J]. IEEE Transactions on Pattern Analysis and Machine Intelligence, 2000, 22(1): 63-84.

[9] Graves A, Liwicki M, Fernández S, Bertolami R, Bunke H, Schmidhuber J. A novel connectionist system for unconstrained handwriting recognition[J]. IEEE Transactions on Pattern Analysis and Machine Intelligence, 2009, 31(5): 855-868.

[10] LeCun Y, Bottou L, Bengio Y, Haffner P. Gradient-based learning applied to document recognition[J]. Proceedings of the IEEE, 1998, 86(11): 2278-2324.

[11] Fadeeva A, Schlattner P, Maksai A, Collier M, Kokiopoulou E, Berent J, Musat C. Representing Online Handwriting for Recognition in Large Vision-Language Models[EB/OL]. arXiv:2402.15307, 2024.

[12] Mitrevski B, Rak A, Schnitzler J, Li C, Maksai A, Berent J, Musat C. InkSight: Offline-to-Online Handwriting Conversion by Learning to Read and Write[EB/OL]. arXiv:2402.05804, 2024.

[13] Khan A A, Nawaz S, Newn J, Lodge J M, Bailey J, Velloso E. Using voice note-taking to promote learners' conceptual understanding[EB/OL]. arXiv:2012.02927, 2020.

[14] Qiu L, Kim E S, Suh S, Sidenmark L, Grossman T. MaRginalia: Enabling In-person Lecture Capturing and Note-taking Through Mixed Reality[EB/OL]. arXiv:2501.16010, 2025.

[15] Escobar-Velásquez C, Mazuera-Rozo A, Bedoya C, Osorio-Riaño M, Linares-Vásquez M, Bavota G. Studying Eventual Connectivity Issues in Android Apps[EB/OL]. arXiv:2110.08908, 2021.

[16] Flutter documentation[EB/OL]. https://docs.flutter.dev/, 2026-06-29.

[17] Python Software Foundation. Python Documentation[EB/OL]. https://docs.python.org/3/, 2026-06-29.

[18] InkNest Notes project documents[Z]. docs/development/ROADMAP.md, docs/development/POST_MVP_ROADMAP.md, docs/development/SMART_INK_PLAN.md, docs/development/SUBSCRIPTION_PLAN.md.

## 预期成果

- 完成一套基于 Flutter 的数字笔记前端应用原型。
- 完成笔记库、手写编辑、PDF 批注、PDF 导出、本地存储和富内容编辑等核心功能说明。
- 完成 Python 后续扩展模块的职责边界、接口方向和接入方案说明；若 Python 项目补充完成，则同步补充运行和测试材料。
- 完成毕业论文、任务书、开题报告、测试记录和答辩演示材料。

## 5、指导教师意见

TODO：由指导教师填写。

指导教师签名：TODO

日期：TODO 年 TODO 月 TODO 日

## 后续同步维护规则

- 项目题目、目标平台、核心功能或技术栈变化时，同步修改“课题名称”“选题意义”“研究内容”“技术手段”和参考文献。
- Python 项目补充后，应同步补充 Python 模块职责、接口设计、技术栈、部署方式、测试方式和参考文献。
- 当前项目路线图从 `Post-MVP 5 - Audio And Search` 继续推进；若音频、搜索或同步里程碑调整，应同步修改进度计划。
- 若暂停或恢复同步/备份，应同步说明毕业设计范围是否包含云同步，避免任务书、开题报告与 `docs/development/POST_MVP_ROADMAP.md` 冲突。
- 若新增重要实现，例如真实手写识别、OCR、音频转写、Web 知识库或 AI，总结时应同步更新国内外发展状况、研究内容和论文提纲。
- 每次同步后，在 `docs/development/STATUS.md` 记录“任务书与开题报告已同步维护”。
