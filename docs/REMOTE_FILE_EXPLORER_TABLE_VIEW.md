Đặc tả chức năng: Remote File Explorer – Table View
1. Mục tiêu
Hiển thị danh sách file và thư mục trên server SSH dưới dạng bảng nhiều cột, cho phép người dùng:
- Quan sát metadata file mà không cần mở từng file.
- Sắp xếp theo tên, dung lượng, ngày sửa đổi, owner, group và permission.
- Tùy chỉnh độ rộng từng cột.
- Kéo thay đổi độ rộng sidebar để phù hợp với kích thước cửa sổ và nhu cầu hiển thị.
- Tiếp tục điều hướng thư mục, sử dụng context menu và drag & drop upload như các chức năng đã đặc tả.
2. Định nghĩa các cột
Column	Nội dung	Quy tắc hiển thị
Name	Tên file hoặc folder	Icon theo loại; folder có thể click để đi vào
Size	Dung lượng file	Định dạng B, KB, MB, GB; folder hiển thị —
Last modified	Thời gian sửa đổi gần nhất	Hiển thị theo định dạng ngày giờ thống nhất
Owner	Chủ sở hữu	Username hoặc UID nếu server không phân giải được tên
Group	Nhóm sở hữu	Group name hoặc GID
Permission	Quyền truy cập	Dạng Unix như -rw-r--r--, drwxr-xr-x; có thể bổ sung dạng octal như 755

Yêu cầu dữ liệu: Owner, Group và Permission phải được lấy từ metadata của remote filesystem qua SFTP nếu server và thư viện hỗ trợ. Nếu không có dữ liệu, hiển thị — thay vì tự suy đoán.
3. Resize sidebar
Sidebar cần có một thanh kéo phân cách giữa sidebar và vùng terminal.
- Kéo sang phải để tăng chiều rộng sidebar.
- Kéo sang trái để thu hẹp sidebar.
- Quy định chiều rộng tối thiểu và tối đa, ví dụ 260–720 px; các giá trị nên cấu hình được.
- Khi cửa sổ thay đổi kích thước, layout phải thích ứng và không làm terminal bị thu nhỏ quá mức.
- Lưu chiều rộng sidebar để khôi phục khi mở ứng dụng lần sau.
- Khi sidebar quá hẹp, cho phép cuộn ngang bảng hoặc ẩn các cột ít quan trọng theo chính sách responsive; không ép các cột chồng lên nhau.
4. Resize từng column
Mỗi column có một vùng kéo nhỏ ở mép phải header.
- Kéo mép cột để tăng hoặc giảm width.
- Có width mặc định, minimum width và maximum width riêng.
- Không cho cột bị thu nhỏ đến mức không thể đọc hoặc thao tác.
- Tên file dài được ellipsis; có thể hiển thị đầy đủ bằng tooltip.
- Việc resize một cột không được làm mất dữ liệu hoặc reset trạng thái sort.
- Lưu width của từng cột để dùng lại ở lần khởi động sau.
- Có thể bổ sung thao tác double-click mép cột để auto-fit theo nội dung nếu khả thi.
5. Sort khi click column header
Click vào header sẽ sắp xếp tăng dần; click lại chuyển sang giảm dần.
Column	Quy tắc sort
Name	So sánh tên theo thứ tự chữ cái, không phân biệt hoa thường theo mặc định
Size	So sánh dung lượng số thực, không so sánh chuỗi hiển thị
Last modified	So sánh timestamp
Owner	So sánh owner name; fallback UID
Group	So sánh group name; fallback GID
Permission	So sánh theo giá trị permission đã chuẩn hóa, không sort theo chuỗi hiển thị nếu có thể tránh được

Yêu cầu bổ sung:
- Hiển thị icon mũi tên thể hiện cột đang sort và chiều sort.
- Chỉ duy trì một cột sort chính ở phiên bản MVP.
- Mặc định hiển thị folder trước file, sau đó áp dụng sort trong từng nhóm; đây là chính sách nên thống nhất cho tất cả các cột.
- Sort phải ổn định để các mục có giá trị bằng nhau không nhảy vị trí ngẫu nhiên.
- Với danh sách lớn, ưu tiên sort ở client sau khi lấy metadata; không gửi thêm lệnh SSH cho mỗi lần click header.
6. Kết hợp với chức năng hiện có
- Click Name: folder thì điều hướng vào folder; file thì giữ hành vi đã định nghĩa cho file.
- Right-click: mở context menu gồm Rename, Delete, Download.
- Drag & drop: kéo file từ Finder vào vùng bảng để upload vào thư mục hiện tại.
- Breadcrumb: vẫn hiển thị đường dẫn remote đang đứng.
- Terminal cd: cập nhật đường dẫn và danh sách bảng khi shell integration xác định được working directory mới.
- Refresh: tải lại danh sách và metadata, giữ sort/column widths nếu vẫn hợp lệ.
- Selection: hỗ trợ chọn dòng; thao tác Delete/Download phải biết rõ file đang được chọn.
- Loading/error: không để dữ liệu cũ bị hiểu nhầm là dữ liệu mới sau khi đổi thư mục hoặc kết nối.

---

## Trạng thái triển khai (2026-10-25)

Đã triển khai đầy đủ theo đặc tả này (xem ADR-010 trong
`docs/DECISIONS.md` và mục tương ứng trong `docs/FEATURE_SPEC.md`):

- Bảng 6 cột Name / Size / Last modified / Owner / Group /
  Permission (chuỗi Unix 10 ký tự, octal ở tooltip). Dữ liệu lấy
  từ SFTP attributes (UID/GID dạng số, mode đầy đủ).
- Owner/Group: tên tài khoản được tra best-effort một lần mỗi
  phiên kết nối từ `/etc/passwd` + `/etc/group` qua exec read-only;
  không tra được thì hiển thị UID/GID đúng như fallback của đặc tả.
- Sort một cột chính, folder luôn trước, ổn định (stable), xử lý
  hoàn toàn ở client; icon mũi tên ở header đang sort.
- Resize sidebar bằng thanh kéo (260–720 px, không ép terminal
  nhỏ quá mức) và resize từng cột bằng mép phải header (min/max
  riêng), double-click mép cột để auto-fit. Cả hai loại width lưu
  trong `heroterm-ui.json` và khôi phục khi mở app. Bảng cuộn
  ngang khi hẹp hơn tổng độ rộng cột; tên dài ellipsis + tooltip
  đường dẫn đầy đủ.
- Selection theo dòng được lưu trong explorer state và xoá khi đổi
  thư mục; context menu chuột phải, drag & drop upload, breadcrumb,
  follow-cwd và refresh giữ nguyên hành vi cũ (refresh giữ sort và
  widths).
- Kiểm chứng: test tự động (domain sort/parser/preferences,
  controller, widget test trên bảng thật) và live check qua SSH
  với server test (UID/GID/mode thật, uid 0 tra được thành "root").