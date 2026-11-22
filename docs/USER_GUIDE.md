# HeroTerm — Hướng dẫn sử dụng

HeroTerm là ứng dụng SSH client cho macOS: quản lý nhiều server,
mở terminal tương tác, duyệt/truyền file qua SFTP ngay trong
sidebar, và theo dõi CPU/RAM/disk của server ở thanh dưới cùng.

## 1. Chạy ứng dụng

- Khi phát triển: `flutter run -d macos` trong thư mục project.
- Cài bản production lên chính máy Mac này (build release, cài
  vào `/Applications`, thay bản cũ): `./scripts/install_macos.sh
  --open` — xem thêm `docs/RELEASE.md` mục 1b.
- Bản đóng gói: mở file `.dmg` (xem `docs/RELEASE.md`), kéo
  **HeroTerm** vào thư mục Applications rồi mở từ đó. Lần đầu mở
  bản chưa ký Developer ID: chuột phải vào app → **Open** → Open.

## 2. Tạo session (server)

1. Bấm **+** ở sidebar để tạo session mới; có thể tạo folder để
   nhóm các server.
2. Điền: tên, host (IP hoặc hostname), port (mặc định 22),
   username.
3. Chọn cách đăng nhập:
   - **Password:** nhập mật khẩu — mật khẩu được lưu trong macOS
     Keychain, không lưu dạng text trong file cấu hình.
   - **Private key:** bấm **Browse…** để chọn file key (bắt buộc
     dùng nút Browse để macOS cấp quyền đọc file cho app); nếu key
     có passphrase, nhập vào ô secret.
4. Tuỳ chọn: thư mục khởi động (startup directory) trên server,
   timeout kết nối (1–120 giây, mặc định 15).
5. Gán **Label** cho session: trong form, mục *Labels* cho chọn
   các label có sẵn hoặc bấm **New label** để tạo label mới (tên
   + màu). Một session gắn được nhiều label; label hiển thị ngay
   trên item trong danh sách. Mục *Icon & colour* cho chọn icon
   và màu cho session để dễ phân biệt; folder cũng chọn được
   icon/màu tương tự trong hộp sửa folder. Có thể thêm
   Description — tìm kiếm sẽ quét cả description, tên label và
   tên folder.
6. Bấm **Test Connection** trong form để thử kết nối ngay với
   thông số đang nhập (app kết nối thật rồi ngắt ngay, có hỏi
   host key/mật khẩu như khi kết nối thường); đạt thì bấm
   **Save**. Đóng form khi đã sửa mà chưa lưu sẽ có hộp xác nhận
   bỏ thay đổi.
7. Nhấn đúp/chọn session rồi bấm **Connect**.

Quản lý nâng cao (menu ⋮ của từng session và menu ở đầu danh sách):

- **Duplicate:** tạo bản sao cấu hình tên dạng `<tên> Copy`. Bản
  sao *dùng chung* mật khẩu đã lưu với bản gốc (không chép thêm
  bản sao mật khẩu nào); nếu sau này bạn đổi mật khẩu ở một
  profile, profile còn lại không bị ảnh hưởng. Form sửa sẽ mở
  ngay để bạn kiểm tra bản sao.
- **Test Connection** cũng có trong menu của session đã lưu.
- **Export/Import:** menu ở đầu danh sách session có *Export all
  profiles…* và *Import profiles…*; menu của từng session có
  *Export profile…*. File export (JSON) **chỉ chứa cấu hình kết
  nối — không chứa mật khẩu, passphrase hay key**. Khi import,
  app cho xem trước danh sách, đánh dấu profile trùng (cùng tên +
  host + username + port) và cho chọn: bỏ qua bản trùng / nhập
  thành bản sao / cập nhật profile cũ (cách này giữ nguyên mật
  khẩu đã lưu của profile cũ). Folder được ghép theo tên + loại
  (Project/Client/Custom).
- Lọc theo Label: dưới ô tìm kiếm là hàng chip các label theo
  màu của chúng; bấm để bật/tắt — session phải mang *tất cả*
  label đang chọn mới hiện. Bấm biểu tượng 🏷 (Manage labels) để
  đổi tên, đổi màu hoặc xoá label (xoá label chỉ gỡ nó khỏi các
  session, không xoá session). Khi không có kết quả, bấm **Clear
  filters** để xem lại toàn bộ.
- Dòng `user@host` không còn hiện thường trực dưới tên session
  nữa cho gọn danh sách — **di chuột lên item** sẽ thấy dạng
  tooltip (kèm lần kết nối gần nhất).
- Folder có thể thu gọn bằng nút chevron ở đầu nhóm.
- *Lưu ý di trú:* Environment và Tags của bản cũ tự động chuyển
  thành Label tương ứng khi mở app (Production giữ màu đỏ,
  Staging cam, Development xanh dương); file export cũ vẫn
  import được và cũng được chuyển như vậy.

## 3. Kết nối và host key

- Lần đầu kết nối tới một server, app hiện **vân tay (fingerprint)
  SHA-256** của host key. Đối chiếu với quản trị viên nếu cần, rồi
  bấm **Trust** để lưu và kết nối. Nếu host key thay đổi so với lần
  đã tin cậy, app **chặn kết nối** và cảnh báo — đừng bỏ qua cảnh
  báo này nếu server không hề cài lại.
- Nếu session chưa lưu mật khẩu, app hỏi mật khẩu ngay lúc kết
  nối; mật khẩu gõ lúc này không được lưu lại.

## 4. Terminal

- Gõ lệnh như terminal thường; app tự cài hook để sidebar bám theo
  thư mục hiện tại khi bạn `cd`.
- Gõ tiếng Việt Telex bình thường (đã sửa lỗi `w` → `ưư`).
- **Disconnect** ngắt kết nối; **Reconnect** (hoặc ⌘⇧R) kết nối lại
  đúng session đó khi shell bị đóng hoặc mạng rớt.

### Nhiều session cùng lúc (tab)

- Mỗi kết nối mở trong một **tab** phía trên terminal; chấm màu
  trên tab cho biết trạng thái (xanh = đã kết nối, vàng = đang
  kết nối, đỏ = lỗi, xám = đã ngắt). Mỗi tab giữ nguyên nội dung
  terminal và scrollback của nó khi chuyển qua lại.
- Bấm **+** (hoặc ⌘T) để mở panel chọn session: có tìm kiếm, nhóm
  theo folder; panel giữ mở để bạn mở liền nhiều session. Session
  đã mở sẽ có nhãn **Open** — bấm vào là chuyển sang tab đó; bấm
  nút **+ hình tròn** nếu muốn mở thêm một tab nữa của cùng
  server (tab mới tên dạng `tên (2)`).
- Đóng tab bằng nút **×** trên tab hoặc ⌘⇧W: chỉ session đó bị
  đóng, các tab khác chạy tiếp. Đóng hết tab sẽ quay về danh
  sách session.
- Remote Explorer và thanh metrics luôn hiển thị theo **tab đang
  active**; thư mục explorer của từng tab được nhớ riêng.
- Giới hạn 12 tab cùng lúc. Thoát app (⌘Q) sẽ đóng mọi session —
  session SSH không được giữ qua lần mở app sau.

## 5. Remote Explorer (sidebar khi đã kết nối)

- Danh sách file hiển thị dạng **bảng nhiều cột**: Name, Size,
  Last modified, Owner, Group, Permission (dạng `drwxr-xr-x`).
  Owner/Group hiện tên tài khoản nếu server tra được, không thì
  hiện số UID/GID.
- **Sắp xếp:** bấm vào tiêu đề cột để sort tăng dần, bấm lần nữa
  để đảo chiều (có mũi tên chỉ hướng). Folder luôn nằm trước file.
- **Đổi độ rộng cột:** kéo mép phải của tiêu đề cột; nhấp đúp vào
  mép để cột tự vừa nội dung. **Đổi độ rộng sidebar:** kéo mép
  phải của sidebar. Cả hai đều được nhớ lại ở lần mở app sau.
  Bảng rộng hơn sidebar thì cuộn ngang.
- Thanh đường dẫn: hiện path hiện tại — **copy được**, gõ path mới
  rồi **Enter** để nhảy tới, nút mũi tên xuống để chọn các thư mục
  đã vào gần đây. Breadcrumb ở dưới để đi lên từng cấp.
- Chuột phải vào file/thư mục: **Rename**, **Download** (có tiến
  trình và nút huỷ ở panel dưới cùng của sidebar), **Delete** (app
  hỏi xác nhận kèm đường dẫn đầy đủ).
- **Upload:** kéo-thả file/thư mục từ Finder vào sidebar, hoặc bấm
  nút **Upload** ở đầu sidebar để chọn file. Trùng tên sẽ có hộp
  thoại: ghi đè / giữ cả hai (tự đổi tên) / bỏ qua.
- Nút mắt (eye) bật/tắt file ẩn; nút link bật/tắt chế độ bám theo
  thư mục của terminal.

## 6. Thanh metrics

Hiển thị số liệu **của server remote** (không phải máy Mac của
bạn): `CPU %`, `Memory đã dùng / tổng (%)`, `Disk / (%)`, cập nhật
mỗi ~4 giây kèm giờ cập nhật. Nếu server không hỗ trợ hoặc lệnh bị
chặn quyền, thanh hiện "unavailable"; nếu mất kết nối giữa chừng,
số cũ được giữ và đánh dấu **Stale**.

## 7. Phím tắt

| Phím | Tác dụng |
| --- | --- |
| ⌘⇧C | Kết nối session đang chọn |
| ⌘⇧D | Ngắt kết nối tab đang active |
| ⌘⇧R | Kết nối lại tab đang active |
| ⌘T | Mở panel chọn session (tab mới) |
| ⌘⇧W | Đóng tab đang active |
| ⌘1 – ⌘9 | Nhảy tới tab thứ 1 – 9 |
| Ctrl+Tab / Ctrl+⇧Tab | Chuyển tab kế tiếp / trước đó |

(Trên bàn phím non-macOS dùng Ctrl thay cho ⌘.)

## 8. Xử lý sự cố thường gặp

- **"Operation not permitted" khi connect:** bản build cũ thiếu
  quyền mạng — hãy `git pull` bản mới nhất và **chạy lại từ đầu**
  (`flutter run -d macos`), hot reload không cập nhật quyền này.
- **Không đọc được private key sau khi khởi động lại app:** sửa
  session, chọn lại key bằng nút **Browse…**.
- **Kéo-thả từ Finder không chạy:** dùng nút **Upload** ở đầu
  sidebar; đồng thời kiểm tra file có nằm ngoài vùng app được phép
  (file trên Desktop/Documents thường cần thao tác kéo-thả đúng
  cách để macOS cấp quyền).
- **Sidebar không bám theo `cd`:** shell trên server có thể không
  hỗ trợ — app sẽ báo và bạn vẫn duyệt thư mục thủ công được.
- **Gõ phím trong terminal bị rớt chữ / nhảy con trỏ:** giúp
  khoanh vùng nguyên nhân bằng hai bước sau rồi gửi kết quả:
  1. Trên server, chạy lệnh `cat` (chế độ echo thô, không qua bộ
     soạn dòng của shell), gõ thử một câu dài và cụm
     `queue-worker`, rồi bấm Ctrl+C. Nếu trong `cat` chữ vẫn rớt
     thì lỗi nằm ở đường nhập liệu của app; nếu `cat` sạch mà
     gõ ở prompt vẫn lỗi thì lỗi nằm ở tương tác vẽ lại dòng.
  2. Bấm **⌘⇧L** để bật ghi log nhập liệu (thông báo "Input log
     ON"), lặp lại thao tác gây lỗi, bấm **⌘⇧L** lần nữa để tắt,
     rồi gửi file `heroterm-input-log.txt` trong thư mục
     Application Support của app (`~/Library/Application
     Support/HeroTerm/`). **Lưu ý:** khi log đang bật, mọi thứ
     gõ trong terminal đều được ghi lại — đừng gõ mật khẩu
     (kể cả `sudo`) trong lúc ghi.

## 9. Chỉnh sửa file trực tiếp trên server (Edit File)

Khi đã kết nối, chuột phải vào một **file** trong Remote Explorer:

- **Edit**: mở bằng trình soạn thảo tích hợp. File mở thành một
  tab cạnh các tab terminal; chấm cam trên tab/tên file nghĩa là
  chưa lưu. Có tô màu cú pháp, số dòng, Undo/Redo (⌘Z/⌘⇧Z),
  Find & Replace (⌘F), lưu bằng nút **Save** hoặc ⌘S, đóng tab
  bằng ⌘W. Giới hạn: tối đa 2 MB, chỉ file text UTF-8 — file nhị
  phân hoặc encoding khác sẽ bị từ chối kèm thông báo (không bao
  giờ tự ý sửa nội dung).
- **Open With…**: mở bằng ứng dụng macOS (VS Code, Sublime
  Text...). HeroTerm tải file về thư mục tạm riêng, mở app, và
  tự đồng bộ lên server mỗi khi bạn lưu trong app đó (nếu bật
  Auto Sync). Đóng tab phiên sửa ngoài khi còn thay đổi chưa
  đồng bộ sẽ được hỏi Sync / Discard / Cancel — file tạm không
  bao giờ bị xoá khi chưa đồng bộ.
- Nhấp đúp vào file cũng mở editor mặc định (cấu hình trong
  Settings).

**An toàn dữ liệu:** trước mỗi lần lưu, HeroTerm kiểm tra file
trên server có bị ai khác sửa kể từ lúc bạn mở không (theo dung
lượng + thời gian sửa). Nếu có, bạn được chọn **Overwrite**
(ghi đè), **Reload remote** (nạp lại bản trên server, bỏ thay
đổi của mình) hoặc **Cancel** — không bao giờ ghi đè âm thầm.
Đóng file chưa lưu luôn hiện hộp thoại **Save / Don't Save /
Cancel**; lưu thất bại thì editor giữ nguyên nội dung.

**Settings** (nút bánh răng ở thanh trên cùng), nhóm File Editor:

- *Default Editor*: editor dùng khi nhấp đúp file.
- *External Application*: ứng dụng ngoài mặc định.
- *Auto Sync*: tự đồng bộ thay đổi từ editor ngoài.
- *Save Confirmation*: hỏi xác nhận trước mỗi lần lưu (mặc định
  bật; tắt được tại đây nếu bạn thấy phiền). Sau 3 lần lưu thành
  công cùng một file, HeroTerm hỏi có muốn bỏ qua xác nhận cho
  riêng file đó không (**Smart Save**) —
  lựa chọn này chỉ bỏ qua xác nhận khi lưu, **không** bỏ cảnh
  báo khi đóng file chưa lưu. Danh sách file đã bỏ qua nằm ngay
  trong Settings, bấm **Ask again** để bật lại xác nhận.
- *Temp Directory*: nơi chứa file tạm khi sửa bằng app ngoài.
