//
//  StoryVideoGenerateView.swift
//  MemoriesApp
//

import SwiftUI
import Photos

// MARK: - Network Models

private struct GenerateResponse: Codable {
    let jobId: String
    let status: String
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
    }
}

private struct StatusResponse: Codable {
    let status: String
    let progress: Int
    let step: String
    let videoUrl: String?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case status, progress, step
        case videoUrl = "video_url"
        case error
    }
}

// MARK: - View State

private enum GenerateState {
    case idle
    case loading
    case generating(jobId: String, progress: Int, step: String)
    case done(videoUrl: String)
    case failed(message: String)
}

// MARK: - Event Row Model

private let kMaxPhotosPerEvent = 5

private struct EventRow: Identifiable {
    let id: UUID
    let title: String
    let photos: [Photo]
    var isSelected: Bool
    var selectedPhotoIds: Set<String>
}

// MARK: - Access Token Gate

private struct AccessTokenGateView: View {
    var onSave: (String) -> Void
    @State private var input: String = ""
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent)

            VStack(spacing: 6) {
                Text("输入访问密码")
                    .font(.title3.bold())
                Text("视频生成功能需要付费密码才能使用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            SecureField("请输入密码", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .offset(x: shakeOffset)
                .onSubmit { confirm() }
                .padding(.horizontal, 40)

            Button(action: confirm) {
                Text("确认")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(input.isEmpty ? AppTheme.accentSoft : AppTheme.accent)
                    .foregroundStyle(input.isEmpty ? Color(.tertiaryLabel) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(input.isEmpty)
            .padding(.horizontal, 40)

            Spacer()
        }
        .onAppear { focused = true }
    }

    private func confirm() {
        guard !input.isEmpty else { return }
        onSave(input)
    }
}

// MARK: - Main View

struct StoryVideoGenerateView: View {
    @Environment(\.dismiss) private var dismiss
    var collection: Collection

    @AppStorage("VideoAccessToken") private var storedToken: String = ""
    @State private var showWrongToken = false
    @State private var eventRows: [EventRow] = []
    @State private var generateState: GenerateState = .idle
    @State private var pollingTask: Task<Void, Never>?
    @State private var isSavingVideo = false
    @State private var videoSaveResult: String? = nil

    private let apiBase = "http://18.142.186.126:8000"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if storedToken.isEmpty {
                    AccessTokenGateView { entered in
                        storedToken = entered
                        showWrongToken = false
                    }
                } else if showWrongToken {
                    wrongTokenView
                } else {
                    switch generateState {
                    case .idle:
                        idleView
                    case .loading:
                        loadingView
                    case .generating(_, let progress, let step):
                        generatingView(progress: progress, step: step)
                    case .done(let videoUrl):
                        doneView(videoUrl: videoUrl)
                    case .failed(let message):
                        failedView(message: message)
                    }
                }
            }
            .navigationTitle("生成回忆视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        pollingTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: buildEventRows)
    }

    // MARK: - Wrong Token View

    private var wrongTokenView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("密码错误")
                    .font(.title2.bold())
                Text("请联系开发者获取正确的访问密码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                storedToken = ""
                showWrongToken = false
            } label: {
                Text("重新输入")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Sub Views

    private var idleView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach($eventRows) { $row in
                        EventRowView(row: $row)
                    }
                } header: {
                    Text("选择要生成的事件")
                } footer: {
                    Text("勾选的事件及其照片将用于生成视频，每个事件最多使用 5 张照片。")
                }
            }
            .listStyle(.insetGrouped)

            VStack(spacing: 10) {
                Button(action: startGeneration) {
                    HStack(spacing: 8) {
                        Image(systemName: "film.stack")
                        Text("开始生成")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        eventRows.contains(where: \.isSelected)
                            ? AppTheme.accent
                            : AppTheme.accentSoft
                    )
                    .foregroundStyle(
                        eventRows.contains(where: \.isSelected)
                            ? Color.white
                            : Color(.tertiaryLabel)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!eventRows.contains(where: \.isSelected))
                .padding(.horizontal, 20)

                Text("生成约需 3–5 分钟，请耐心等待")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
                .tint(AppTheme.accent)
            Text("正在准备照片…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func generatingView(progress: Int, step: String) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("正在生成中…")
                    .font(.title2.bold())
                Text(chineseStep(step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                ProgressView(value: Double(progress), total: 100)
                    .progressViewStyle(.linear)
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 40)
                Text("\(progress)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("生成期间请不要关闭此页面")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
    }

    private func doneView(videoUrl: String) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.successGreen)

            VStack(spacing: 8) {
                Text("视频已生成！")
                    .font(.title2.bold())
                Text("保存到相册即可在手机相册中查看")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let url = URL(string: videoUrl) {
                // 主按钮：保存到相册
                Button {
                    Task { await saveVideoToPhotos(urlString: videoUrl) }
                } label: {
                    HStack(spacing: 8) {
                        if isSavingVideo {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down.fill")
                        }
                        Text(isSavingVideo ? "保存中…" : "保存到相册")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isSavingVideo ? AppTheme.accent.opacity(0.6) : AppTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 40)
                }
                .disabled(isSavingVideo)

                // 保存结果提示
                if let result = videoSaveResult {
                    Text(result == "ok" ? "✓ 已保存到相册" : result)
                        .font(.subheadline)
                        .foregroundStyle(result == "ok" ? AppTheme.successGreen : .red)
                }

                // 次要操作
                HStack(spacing: 24) {
                    Link(destination: url) {
                        Label("在浏览器中观看", systemImage: "play.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = videoUrl
                    } label: {
                        Label("复制链接", systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    private func saveVideoToPhotos(urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        isSavingVideo = true
        videoSaveResult = nil
        defer { isSavingVideo = false }
        do {
            let (tempUrl, _) = try await URLSession.shared.download(from: url)
            let destUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mp4")
            try FileManager.default.moveItem(at: tempUrl, to: destUrl)
            defer { try? FileManager.default.removeItem(at: destUrl) }

            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                videoSaveResult = "请在设置中允许访问相册"
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destUrl)
            }
            videoSaveResult = "ok"
        } catch {
            videoSaveResult = "保存失败：\(error.localizedDescription)"
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("生成失败")
                    .font(.title2.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                generateState = .idle
            } label: {
                Text("重新选择")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Data Preparation

    private func buildEventRows() {
        let storyPhotos = collection.photos
            .filter { $0.deletedAt == nil }
            .sorted { $0.timestamp < $1.timestamp }

        if !collection.events.isEmpty {
            let sorted = collection.events.sorted { $0.startTime < $1.startTime }
            eventRows = sorted.compactMap { event in
                let photos = storyPhotos.filter { $0.eventId == event.id }
                guard !photos.isEmpty else { return nil }
                let title: String
                if let name = event.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    title = name
                } else {
                    title = photos.first?.displayLocationName.isEmpty == false
                        ? photos.first!.displayLocationName
                        : "这段回忆"
                }
                let defaultIds = Set(photos.prefix(kMaxPhotosPerEvent).map(\.assetLocalId))
                return EventRow(id: event.id, title: title, photos: photos, isSelected: true, selectedPhotoIds: defaultIds)
            }
        } else {
            let grouped = Dictionary(grouping: storyPhotos) {
                Calendar.current.startOfDay(for: $0.timestamp)
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日"
            eventRows = grouped.keys.sorted().map { day in
                let photos = (grouped[day] ?? []).sorted { $0.timestamp < $1.timestamp }
                let defaultIds = Set(photos.prefix(kMaxPhotosPerEvent).map(\.assetLocalId))
                return EventRow(id: UUID(), title: formatter.string(from: day), photos: photos, isSelected: true, selectedPhotoIds: defaultIds)
            }
        }
    }

    // MARK: - Progress Step Localisation

    private func chineseStep(_ step: String) -> String {
        switch step {
        case "initializing":                    return "初始化中"
        case "building story config":           return "整理故事配置"
        case "generating script synopsis":      return "生成剧情概要"
        case "planning scenes & shots":         return "规划场景与镜头"
        case "ShotPlotCreate":                  return "编排分镜"
        case "generating keyframes & video":    return "生成关键帧与视频"
        case "concatenating final video":       return "拼接最终视频"
        case "uploading to S3":                 return "上传视频"
        default:                                return step
        }
    }

    // MARK: - Generation

    private func startGeneration() {
        let selectedRows = eventRows.filter(\.isSelected)
        guard !selectedRows.isEmpty else { return }

        generateState = .loading

        Task {
            do {
                var photoDataBatches: [[Data]] = []
                for row in selectedRows {
                    var batch: [Data] = []
                    let photosToSend = row.photos.filter { row.selectedPhotoIds.contains($0.assetLocalId) }
                    for photo in photosToSend {
                        if let data = await PhotoService.imageDataForUpload(localIdentifier: photo.assetLocalId) {
                            batch.append(data)
                        }
                    }
                    photoDataBatches.append(batch)
                }

                let eventTitles = selectedRows.map(\.title)
                let jobId = try await postGenerate(
                    title: collection.title,
                    events: eventTitles,
                    photoDataBatches: photoDataBatches
                )

                await MainActor.run {
                    generateState = .generating(jobId: jobId, progress: 0, step: "initializing")
                }

                startPolling(jobId: jobId)

            } catch {
                await MainActor.run {
                    generateState = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    private func startPolling(jobId: String) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }

                do {
                    let statusResp = try await fetchStatus(jobId: jobId)
                    await MainActor.run {
                        switch statusResp.status {
                        case "done":
                            if let url = statusResp.videoUrl {
                                generateState = .done(videoUrl: url)
                            } else {
                                generateState = .failed(message: "生成完成但未获取到视频链接")
                            }
                        case "error":
                            generateState = .failed(message: statusResp.error ?? "服务器返回了未知错误")
                        default:
                            generateState = .generating(
                                jobId: jobId,
                                progress: statusResp.progress,
                                step: statusResp.step
                            )
                        }
                    }
                } catch {
                    // 网络抖动忽略，继续轮询
                }

                switch generateState {
                case .done, .failed: return
                default: break
                }
            }
        }
    }

    // MARK: - Network

    private func postGenerate(title: String, events: [String], photoDataBatches: [[Data]]) async throws -> String {
        let url = URL(string: "\(apiBase)/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(storedToken)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func appendTextField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }

        appendTextField("story_title", title)
        let eventsJSON = try JSONSerialization.data(withJSONObject: events)
        appendTextField("events_json", String(data: eventsJSON, encoding: .utf8)!)

        for (i, batch) in photoDataBatches.enumerated() {
            for imageData in batch {
                body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photos_\(i)\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                body.append(imageData)
                body.append("\r\n".data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            await MainActor.run { storedToken = ""; showWrongToken = true }
            throw URLError(.userAuthenticationRequired)
        }
        let result = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return result.jobId
    }

    private func fetchStatus(jobId: String) async throws -> StatusResponse {
        let url = URL(string: "\(apiBase)/status/\(jobId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(storedToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            await MainActor.run { storedToken = ""; showWrongToken = true }
            throw URLError(.userAuthenticationRequired)
        }
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }
}

// MARK: - Event Row View

private struct EventRowView: View {
    @Binding var row: EventRow
    @State private var shakePhotoId: String? = nil

    private var selectedCount: Int { row.selectedPhotoIds.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 事件行头部
            HStack(spacing: 10) {
                Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.isSelected ? AppTheme.accent : Color(.tertiaryLabel))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.body.weight(.medium))
                    if row.photos.count > kMaxPhotosPerEvent {
                        Text("已选 \(selectedCount)/\(kMaxPhotosPerEvent) 张（共 \(row.photos.count) 张，点击照片可换选）")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    } else {
                        Text("\(row.photos.count) 张照片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { row.isSelected.toggle() }

            // 照片横滑列表
            if !row.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(row.photos) { photo in
                            let isPhotoSelected = row.selectedPhotoIds.contains(photo.assetLocalId)
                            AssetImageView(
                                localIdentifier: photo.assetLocalId,
                                size: CGSize(width: 60, height: 60)
                            )
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .opacity(row.isSelected ? (isPhotoSelected ? 1.0 : 0.3) : 0.2)
                            .offset(x: shakePhotoId == photo.assetLocalId ? 4 : 0)
                            .overlay(alignment: .topTrailing) {
                                if row.isSelected && isPhotoSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(AppTheme.accent)
                                        .background(Circle().fill(.white).padding(1))
                                        .padding(4)
                                }
                            }
                            .onTapGesture {
                                guard row.isSelected else { return }
                                if isPhotoSelected {
                                    // 至少保留1张
                                    if selectedCount > 1 {
                                        row.selectedPhotoIds.remove(photo.assetLocalId)
                                    }
                                } else {
                                    if selectedCount < kMaxPhotosPerEvent {
                                        row.selectedPhotoIds.insert(photo.assetLocalId)
                                    } else {
                                        // 已满5张，轻微震动提示
                                        shakePhotoId = photo.assetLocalId
                                        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {}
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            shakePhotoId = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 34)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
