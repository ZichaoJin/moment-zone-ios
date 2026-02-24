Memories — 回忆生成 iOS 应用

简介
- 本项目为 iOS 客户端，用于从照片与事件生成回忆、短视频与故事内容。

接入（已实现）
- 已接入： https://github.com/ZichaoJin/character-video-agent.git
  - 说明：本仓库调用 `character-video-agent` 的 API，能够根据 story 文本与自动分出的 events 生成定制角色回忆视频。该 agent 负责角色渲染、配音与场景合成，应用端只需提供故事文本、事件列表与相关媒体 URL，即可获得定制视频输出。

简要说明
- 打开 Xcode 并选择 `MemoriesApp` 目标构建运行。
- 运行时请通过安全方式注入第三方服务凭证（例如 Runway API key 或视频生成的访问令牌），不要将密钥硬编码到仓库中。

如需我把 README 增补成英文版、或加入开发/CI 指南或 `.env.example`，请告诉我要的内容，我会继续补充。
