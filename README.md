# Yakeng

Bộ công cụ bàn phím "kiểu Windows" cho macOS, chạy nền trên thanh menu. Mọi phím tắt đều đổi được trong **Cài đặt**.

| Tính năng | Mặc định | Mô tả |
|---|---|---|
| **Ctrl → Cmd** | Ctrl+A / C / V | Bấm Ctrl+phím được hiểu như Cmd+phím. Chọn thêm X, Z, S, F, N, T… trong Cài đặt. Loại trừ Terminal/iTerm. |
| **Alt + Tab** | ⌥⇥ (⇧ để lùi) | Bảng chuyển *từng cửa sổ* như Windows (⌘⇥ của macOS chỉ chuyển app). Thả ⌥ để chọn, Esc huỷ. |
| **Lịch sử clipboard** | ⇧⌘S | Bảng mọi thứ đã sao chép (chữ + ảnh). Bấm mục để dán. Nút **Chụp màn hình** kéo chọn vùng như Win+Shift+S. |
| **Gõ tiếng Việt** | ⌥Z bật/tắt | Telex hoặc VNI, kiểu dấu cũ/mới. Thanh menu hiện **VI / EN**. |

## Build

Cần Xcode Command Line Tools (`xcode-select --install`), macOS 12+.

```bash
./build.command
```

Tạo ra `Yakeng.app` và `Yakeng.dmg` (universal nếu có SDK Intel, nếu không thì theo máy hiện tại).

## Cài đặt & cấp quyền

1. Mở `Yakeng.dmg`, kéo **Yakeng** vào **Applications**.
2. Lần đầu mở: nhấp chuột phải vào app → **Open** (app ký ad-hoc, chưa notarize).
3. Cấp quyền **Accessibility** khi macOS hỏi (*System Settings → Privacy & Security → Accessibility*). Mọi tính năng phím tắt cần quyền này.
4. Lần đầu bấm "Chụp màn hình", macOS hỏi thêm quyền **Screen Recording**.
5. Bật "Tự chạy khi đăng nhập" trong Cài đặt (macOS 13+).

## Mã nguồn

```
Sources/
├── main.swift            AppDelegate, icon thanh menu, cửa sổ Cài đặt
├── Settings.swift        Cấu hình (UserDefaults, JSON)
├── Hotkey.swift          Mô hình phím tắt + tên phím
├── EventTap.swift        CGEvent tap duy nhất, phân phối sự kiện, gửi phím giả lập
├── VietInput.swift       Bộ gõ tiếng Việt (Telex/VNI) – Composer ghép dấu
├── WindowSwitcher.swift  Alt+Tab: danh sách cửa sổ (CGWindowList) + kích hoạt (AX)
├── ClipboardManager.swift Theo dõi NSPasteboard, bảng lịch sử, screencapture
└── SettingsView.swift    Giao diện Cài đặt (SwiftUI) + HotkeyRecorder
```

### Cách hoạt động

- **Event tap** (`CGEvent.tapCreate`) nhận mọi phím ở mức hệ thống. Sự kiện do Yakeng tự gửi được đánh dấu bằng `eventSourceUserData` để không xử lý lặp.
- **Ctrl→Cmd**: đổi cờ `.maskControl` → `.maskCommand` rồi chuyển tiếp.
- **Gõ tiếng Việt**: lưu các phím của từ đang gõ, ghép lại bằng `Composer`, so sánh với chuỗi đang hiển thị, gửi backspace + ký tự mới cho phần khác biệt.
- **Alt+Tab**: lấy danh sách cửa sổ bằng `CGWindowListCopyWindowInfo`, kích hoạt bằng Accessibility API (`_AXUIElementGetWindow` để khớp window ID).
- **Clipboard**: kiểm tra `NSPasteboard.changeCount` mỗi 0,5s; chụp màn hình gọi `screencapture -i -c`.
