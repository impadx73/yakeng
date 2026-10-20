# Yakeng

Ứng dụng macOS nhỏ chạy nền, ánh xạ phím tắt kiểu Windows sang macOS:

| Bấm | Hiểu thành |
|---|---|
| Ctrl + A | Cmd + A (chọn tất cả) |
| Ctrl + C | Cmd + C (sao chép) |
| Ctrl + V | Cmd + V (dán) |

Hoạt động ở mọi app, trừ Terminal và iTerm2 (vì Ctrl+A/C trong shell có ý nghĩa riêng).

## Build

Cần Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.command
```

Script tạo ra:

- `Yakeng.app` — app chạy nền, icon **⌃→⌘** trên thanh menu, bấm để thoát
- `Yakeng.dmg` — file cài đặt (mở, kéo Yakeng vào Applications), universal (Apple Silicon + Intel)

## Cài đặt & cấp quyền

1. Mở `Yakeng.dmg`, kéo **Yakeng** vào **Applications**.
2. Lần đầu mở: nhấp chuột phải vào app → **Open** (app ký ad-hoc, chưa notarize).
3. Khi macOS hỏi quyền **Accessibility**, bật cho Yakeng trong *System Settings → Privacy & Security → Accessibility*. App tự bắt đầu hoạt động ngay sau khi được cấp quyền.
4. Muốn chạy khi đăng nhập: thêm vào *System Settings → General → Login Items*.

## Tuỳ chỉnh

Trong `Sources/main.swift`:

- `targetKeys` — thêm keycode phím khác (X = 7, Z = 6, S = 1, …)
- `excludedBundleIDs` — các app không áp dụng

## Cách hoạt động

Dùng `CGEvent` tap ở mức hệ thống: khi gặp phím A/C/V kèm Ctrl (không kèm Cmd), app đổi cờ Ctrl thành Cmd rồi chuyển tiếp sự kiện, nên ứng dụng nhận được hiểu như Cmd+A/C/V.
