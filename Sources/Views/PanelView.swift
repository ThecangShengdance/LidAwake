import SwiftUI

/// 菜单栏弹出的主面板。
struct PanelView: View {
    @ObservedObject var model: AppModel

    private var accent: Color { model.isEnabled ? .green : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusCard
            detailRows
            if model.isEnabled, model.power.isOnBattery { batteryWarning }
            if let error = model.errorText { errorBanner(error) }
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
                .padding(.vertical, 2)
            preferences
            footer
        }
        .padding(16)
        .frame(width: 368)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.33, green: 0.35, blue: 0.86), Color(red: 0.55, green: 0.38, blue: 0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("合盖不休眠")
                    .font(.system(size: 13, weight: .semibold))
                Text("LidAwake")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }

            Spacer(minLength: 8)
            StatusPill(isEnabled: model.isEnabled, busy: model.busy)
        }
    }

    // MARK: - 主开关卡片

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: model.isEnabled ? "bolt.fill" : "moon.zzz.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(model.statusDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Toggle(
                "",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { model.setEnabled($0) }
                )
            )
            .toggleStyle(PillSwitchStyle(tint: .green))
            .labelsHidden()
            .disabled(model.busy)
            .help(model.isEnabled ? "关闭：恢复默认休眠" : "开启：合盖后继续运行")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(model.isEnabled ? 0.10 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tint.opacity(model.isEnabled ? 0.22 : 0.10), lineWidth: 1)
        )
    }

    private var tint: Color {
        model.isEnabled ? .green : Color(nsColor: .secondaryLabelColor)
    }

    // MARK: - 状态明细

    private var detailRows: some View {
        VStack(spacing: 6) {
            DetailRow(icon: powerIcon, title: "电源", value: powerText, valueColor: model.power.isOnBattery && model.isEnabled ? .orange : .primary)
            DetailRow(icon: "laptopcomputer", title: "机盖", value: model.lidText)
            DetailRow(icon: "clock", title: "已持续", value: model.durationText)
            DetailRow(
                icon: model.passwordless ? "key.fill" : "key",
                title: "切换方式",
                value: model.passwordless ? "免密" : "需密码",
                valueColor: model.passwordless ? .primary : .secondary
            )
        }
        .padding(.horizontal, 2)
    }

    private var powerIcon: String {
        model.power.isOnBattery ? "battery.75percent" : "powerplug.fill"
    }

    private var powerText: String {
        var text = model.power.detailText
        if model.power.hasBattery, model.power.onAC, model.power.charging { text += " ↑" }
        return text
    }

    // MARK: - 提示条

    private var batteryWarning: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text("电池供电下合盖运行：耗电加快、机身发热，建议接通电源。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                model.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    // MARK: - 偏好设置

    private var preferences: some View {
        VStack(spacing: 10) {
            passwordlessRow

            Toggle(isOn: $model.restoreOnQuit) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("退出时恢复默认休眠")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("避免忘记关闭后整晚耗电")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(PillSwitchStyle())

            Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("登录时自动启动")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("开机后在菜单栏待命")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(PillSwitchStyle())
        }
        .disabled(model.busy)
    }

    private var passwordlessRow: some View {
        HStack(spacing: 8) {
            Image(systemName: model.passwordless ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(model.passwordless ? Color.green : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text("免密切换")
                    .font(.system(size: 11.5, weight: .medium))
                Text(model.passwordless ? "已授权 · 仅放行 pmset 开关" : "每次切换需输入管理员密码")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button(model.passwordless ? "移除" : "授权") {
                if model.passwordless {
                    model.removePasswordless()
                } else {
                    model.installPasswordless()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(model.busy)
            .help(model.passwordless
                  ? "删除 /etc/sudoers.d/lidawake"
                  : "写入一条仅允许 pmset -a disablesleep 0|1 的 sudo 规则")
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack {
            Text("v\(Bundle.main.shortVersion)")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// 自绘开关：比系统开关更紧凑，且能在 ImageRenderer 离屏渲染时正确绘制。
struct PillSwitchStyle: ToggleStyle {
    var tint: Color = .accentColor
    var width: CGFloat = 38
    var height: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 6)
            Capsule(style: .continuous)
                .fill(configuration.isOn ? tint : Color(nsColor: .quaternaryLabelColor))
                .frame(width: width, height: height)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(configuration.isOn ? 0 : 0.06), lineWidth: 1)
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.22), radius: 1.2, y: 0.6)
                        .frame(width: height - 4, height: height - 4)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

/// 右上角状态胶囊。
private struct StatusPill: View {
    let isEnabled: Bool
    let busy: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5.5, height: 5.5)
            Text(busy ? "处理中" : (isEnabled ? "运行中" : "已停止"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isEnabled ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((isEnabled ? Color.green : Color.secondary).opacity(0.10))
        )
    }

    private var dotColor: Color {
        if busy { return .orange }
        return isEnabled ? .green : Color(nsColor: .tertiaryLabelColor)
    }
}

/// 一行「图标 + 标题 —— 值」。
private struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }
}
