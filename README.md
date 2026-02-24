# 回忆 App（Memories MVP）

iPhone App：用照片 + 地点 + 时间轴做「回忆」记录，地图 / 时间轴 / 列表三联动。

## 技术栈

- **UI**: SwiftUI  
- **地图**: MapKit  
- **相册**: PhotosUI (PhotosPicker)  
- **存储**: SwiftData（iOS 17+）  
- **Deployment Target**: iOS 17.0  

## 项目结构

```
MemoriesApp/
  Models/
    Memory.swift              # SwiftData 模型
  Views/
    Home/
      HomeView.swift          # 回忆 Tab：时间轴 + 地图 + 列表
      TimelineSliderView.swift
      MemoryListView.swift
      MemoryMapView.swift
    Add/
      AddMemoryView.swift     # 添加 Tab：照片 + 地图选点 + 备注/时间
      LocationPickerMap.swift
      PhotoPickerView.swift
    Detail/
      MemoryDetailView.swift  # 详情：照片横滑 + 文本 + 地点 + 时间
      AssetImageView.swift
  Services/
    PhotoService.swift        # 按 localIdentifier 加载缩略图、取拍摄时间
  MemoriesAppApp.swift
  ContentView.swift           # Tab：回忆 | 添加
  Info.plist                  # 相册/定位权限描述
```

## 如何运行

1. 用 **Xcode** 打开 `MemoriesApp.xcodeproj`。  
2. 确认 **Deployment Target** 为 **iOS 17**。  
3. 选择模拟器或真机，**Run**。

## 权限（Info.plist 已配置）

- `NSPhotoLibraryUsageDescription`：导入照片创建回忆  
- `NSLocationWhenInUseUsageDescription`：选地点与展示位置  

## 功能验收（MVP）

| 里程碑 | 验收点 |
|--------|--------|
| **M0+1** | 能添加无照片回忆 → 列表展示 → 重启数据仍在 |
| **M2** | 有坐标的回忆在地图上显示 pins |
| **M3** | 添加页可在地图点选位置，保存后 Home 地图有对应 pin |
| **M4** | 拖时间轴 Slider → 列表与地图只显示窗口内（±3 天）回忆 |
| **M5** | 点地图 pin → 列表滚到该条并弹出详情；点列表卡片同理 |
| **M6** | 添加页可多选照片，保存 localIdentifier；详情页照片横滑展示 |

## 数据模型（Memory）

- `id`, `timestamp`, `latitude`, `longitude`, `locationName`, `note`  
- `assetLocalIds: [String]`：Photos 的 localIdentifier，不存图文件  
- `createdAt`, `updatedAt`  

## 后续可做（未实现）

- 已接入： https://github.com/ZichaoJin/character-video-agent.git
  - 说明：本仓库调用 `character-video-agent` 的 API，能够根据 story 文本与自动分出的 events 生成定制角色回忆视频。该 agent 负责角色渲染、配音与场景合成，应用端只需提供故事文本、事件列表与相关媒体 URL，即可获得定制视频输出。

---

在 Cursor 中按「一次只改一个 milestone」迭代即可；每次改完在 Xcode 里跑一下做验收。
