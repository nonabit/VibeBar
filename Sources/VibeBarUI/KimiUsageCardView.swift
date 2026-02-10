import SwiftUI

public enum ProviderTab: String, CaseIterable, Hashable {
    case kimi = "Kimi"
    case codex = "Codex"
}

private struct ThinProgressBar: View {
    let value: Double
    let tint: Color
    let height: CGFloat

    private var clamped: Double {
        max(0.0, min(1.0, self.value))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                Capsule()
                    .fill(self.tint)
                    .frame(width: proxy.size.width * self.clamped)
            }
        }
        .frame(height: self.height)
    }
}

private struct UsageSectionView: View {
    public let title: String
    public let used: Int
    public let limit: Int
    public let remaining: Int
    public let resetText: String

    public init(
        title: String,
        used: Int,
        limit: Int,
        remaining: Int,
        resetText: String)
    {
        self.title = title
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.resetText = resetText
    }

    private var clampedRemaining: Int {
        max(0, min(self.remaining, self.limit))
    }

    private var remainingPercent: Int {
        guard self.limit > 0 else { return 0 }
        return Int((Double(self.clampedRemaining) / Double(self.limit) * 100.0).rounded())
    }

    private var remainingProgress: Double {
        max(0.0, min(1.0, Double(self.clampedRemaining) / Double(max(1, self.limit))))
    }

    private var tintColor: Color {
        switch self.remainingPercent {
        case 60...100:
            return .green
        case 30..<60:
            return .yellow
        default:
            return .red
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(self.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(self.used)/\(self.limit)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ThinProgressBar(
                value: self.remainingProgress,
                tint: self.tintColor,
                height: 5)

            HStack {
                Text("\(self.remainingPercent)% left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.tintColor)
                Spacer()
                Text(self.resetText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct KimiUsageCardView: View {
    private let menuEdgeInset: CGFloat = 16

    public let selectedProvider: ProviderTab
    public let onSelectProvider: ((ProviderTab) -> Void)?
    public let providerTitle: String
    public let planText: String?
    public let primaryTitle: String
    public let secondaryTitle: String
    public let snapshot: KimiUsageSnapshot?
    public let tokenSourceText: String
    public let updatedText: String
    public let weeklyResetText: String
    public let rateResetText: String
    public let lastError: String?

    public init(
        selectedProvider: ProviderTab,
        onSelectProvider: ((ProviderTab) -> Void)?,
        providerTitle: String,
        planText: String?,
        primaryTitle: String,
        secondaryTitle: String,
        snapshot: KimiUsageSnapshot?,
        tokenSourceText: String,
        updatedText: String,
        weeklyResetText: String,
        rateResetText: String,
        lastError: String?)
    {
        self.selectedProvider = selectedProvider
        self.onSelectProvider = onSelectProvider
        self.providerTitle = providerTitle
        self.planText = planText
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.snapshot = snapshot
        self.tokenSourceText = tokenSourceText
        self.updatedText = updatedText
        self.weeklyResetText = weeklyResetText
        self.rateResetText = rateResetText
        self.lastError = lastError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabBar

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.providerTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text("更新 \(self.updatedText)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let planText = self.planText, !planText.isEmpty {
                    Text(planText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let snapshot = self.snapshot {
                UsageSectionView(
                    title: self.primaryTitle,
                    used: snapshot.weeklyUsed,
                    limit: snapshot.weeklyLimit,
                    remaining: snapshot.weeklyRemaining,
                    resetText: self.weeklyResetText)

                if let rateUsed = snapshot.rateLimitUsed,
                   let rateLimit = snapshot.rateLimitLimit
                {
                    Divider()

                    UsageSectionView(
                        title: self.secondaryTitle,
                        used: rateUsed,
                        limit: rateLimit,
                        remaining: snapshot.rateLimitRemaining ?? max(0, rateLimit - rateUsed),
                        resetText: self.rateResetText)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("尚未获取到可用数据")
                        .font(.system(size: 13, weight: .medium))
                    if let lastError = self.lastError, !lastError.isEmpty {
                        Text(lastError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                    Text(self.selectedProvider == .kimi ? "请先在浏览器登录 Kimi，再点击“立即刷新”。" : "请先运行 codex 完成登录，再点击“立即刷新”。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("来源: \(self.tokenSourceText)")
                Spacer()
                if let lastError = self.lastError, !lastError.isEmpty, self.snapshot == nil {
                    Text("错误")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, self.menuEdgeInset)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(ProviderTab.allCases, id: \.self) { tab in
                Button {
                    self.onSelectProvider?(tab)
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.selectedProvider == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(self.selectedProvider == tab ? Color.primary.opacity(0.14) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
