SSH Profile Management — Feature Specification
- Project: SSH Client for macOS
- Feature ID: SSH-PROFILE-001
- Priority: P0 — MVP
- Status: Implemented (2026-10-25 — see the implementation status section at the end)
- Version: 1.0
- Last updated: 2026-10-25
1. Mục tiêu
Xây dựng module quản lý SSH Profile giúp người dùng lưu, phân nhóm, tìm kiếm, nhân bản và trao đổi cấu hình kết nối SSH nhanh chóng. Người dùng có thể cấu hình hostname/IP, username, port, phương thức xác thực, private key và timeout; đồng thời nhận biết rõ môi trường Production, Staging và Development trước khi kết nối.

Module phải phù hợp với SSH Client macOS-first, hỗ trợ kết nối bằng password hoặc private key, ưu tiên bảo mật và không làm lộ thông tin xác thực khi lưu trữ hoặc export.
2. Phạm vi
2.1 In scope — P0
- Tạo, xem, sửa và xóa SSH Profile.
- Phân nhóm profile theo Project, Environment hoặc Client.
- Gắn environment label: Production, Staging, Development; cho phép Other/Unspecified khi cần.
- Tìm kiếm profile theo tên, hostname, IP, username và group/project/client.
- Duplicate profile.
- Import/Export cấu hình profile.
- Cấu hình hostname/IP, port SSH, username, authentication method, Identity File và connection timeout.
- Kiểm tra dữ liệu đầu vào và cung cấp chức năng Test Connection.
- Lưu profile metadata trong local database.
- Lưu secrets bằng macOS Keychain; profile chỉ tham chiếu tới secret, không lưu password/passphrase dạng plaintext.
- Phân biệt trực quan môi trường, đặc biệt Production.
2.2 Out of scope — không bắt buộc trong P0
- Đồng bộ profile qua cloud hoặc nhiều thiết bị.
- Chia sẻ profile và secrets giữa người dùng.
- Quản lý team/role.
- ProxyJump/Bastion và SSH tunneling (có thể bổ sung ở phase sau).
- Tự động chạy lệnh sau khi kết nối.
- Quản lý chứng chỉ/SSH CA nâng cao.
- Nhập trực tiếp cấu hình từ mọi ứng dụng SSH khác nếu chưa có adapter riêng.
3. Thuật ngữ và mô hình phân nhóm
- SSH Profile: Một cấu hình kết nối đến một SSH endpoint.
- Environment: Môi trường vận hành, ví dụ Production, Staging, Development.
- Group: Nhóm profile theo Project hoặc Client. Environment là thuộc tính độc lập, không bắt buộc phải là cây thư mục.
- Identity File: Đường dẫn tới private key trên máy local.
- Secret reference: Tham chiếu đến password/passphrase được lưu trong Keychain.
Một profile có thể thuộc một group và có đúng một environment label. Không yêu cầu người dùng tạo group nếu chỉ quản lý một vài server.
4. User stories
1. Là người dùng, tôi muốn tạo profile với hostname, username và port để kết nối nhanh mà không phải nhập lại thông tin.
2. Là người dùng, tôi muốn phân nhóm server theo project/client và lọc theo environment để tìm đúng server.
3. Là người dùng, tôi muốn thấy rõ Production trước khi kết nối để giảm nguy cơ thao tác nhầm môi trường.
4. Là người dùng, tôi muốn tìm server bằng tên, IP, hostname hoặc username.
5. Là người dùng, tôi muốn duplicate một profile để tạo cấu hình tương tự mà không phải nhập lại toàn bộ.
6. Là người dùng, tôi muốn import/export profile để sao lưu hoặc chuyển cấu hình sang máy khác.
7. Là người dùng, tôi muốn chọn private key và đặt timeout để phù hợp với từng server.
8. Là người dùng, tôi muốn test kết nối và nhận thông báo lỗi có thể hành động được trước khi lưu hoặc sử dụng profile.
5. Trường dữ liệu SSH Profile
Field	Type	Required	Default / Validation	Notes
id	UUID/string	Yes	Tự sinh	Định danh nội bộ ổn định
name	string	Yes	1–100 ký tự sau trim	Tên hiển thị, không bắt buộc unique
host	string	Yes	Hostname hoặc IP hợp lệ	Không bao gồm scheme như ssh://
port	integer	Yes	22, từ 1–65535	Có thể đổi theo server
username	string	Yes	Không rỗng, trim khoảng trắng đầu/cuối	Tên user trên remote
authMethod	enum	Yes	password hoặc privateKey	Password/private key là scope MVP
identityFilePath	string/null	Conditional	Bắt buộc khi authMethod=privateKey	Đường dẫn local; không copy private key vào database
secretRef	string/null	Conditional	Bắt buộc khi cần lưu password/passphrase	Keychain reference; không phải secret value
environment	enum	Yes	development mặc định khi tạo mới hoặc yêu cầu người dùng chọn	production, staging, development, other
groupId	UUID/string/null	No	Null nếu chưa phân nhóm	Group theo Project hoặc Client
groupType	enum	No	project, client, custom	Có thể lưu trên entity Group thay vì profile
connectionTimeoutSeconds	integer	Yes	Mặc định 15; cho phép 1–120	Timeout cho bước thiết lập kết nối
description	string	No	Tối đa 500 ký tự	Ghi chú server
tags	string[]	No	Không trùng lặp	Nhãn bổ sung nếu cần
createdAt	datetime	Yes	Tự sinh	Audit metadata
updatedAt	datetime	Yes	Tự cập nhật	Audit metadata
lastConnectedAt	datetime/null	No	Null ban đầu	Hỗ trợ sắp xếp gần đây
lastConnectionStatus	enum/null	No	success, failed, unknown	Không lưu thông tin nhạy cảm


Lưu ý về timeout: connectionTimeoutSeconds là timeout thiết lập kết nối TCP/SSH và xác thực trong phạm vi mà SSH implementation hỗ trợ; không dùng thay cho timeout lệnh chạy trên terminal.
5.1 Group entity
Field	Type	Required	Notes
id	UUID/string	Yes	ID ổn định
name	string	Yes	Tên group
type	enum	Yes	project, client, custom
parentId	UUID/string/null	No	P0 có thể không hỗ trợ nested group; giữ null nếu chưa triển khai
createdAt	datetime	Yes	Thời điểm tạo
updatedAt	datetime	Yes	Thời điểm cập nhật


Để tránh tăng độ phức tạp MVP, group phẳng là đủ. Chỉ bổ sung group lồng nhau nếu UI hiện tại đã có cây group và cần thiết cho luồng chính.
6. UI/UX requirements
6.1 Khu vực quản lý profile
- Hiển thị danh sách profile và group ở sidebar hoặc khu vực quản lý kết nối hiện có.
- Mỗi profile hiển thị tên, host, username và environment badge.
- Production phải có dấu hiệu nhận diện nổi bật nhưng không chỉ dựa vào màu sắc; hiển thị rõ chữ PRODUCTION.
- Cho phép mở rộng/thu gọn group.
- Có trạng thái empty state và nút tạo profile đầu tiên.
- Có menu thao tác theo profile: Connect, Edit, Duplicate, Test Connection, Export (nếu hỗ trợ export từng profile), Delete.
- Thao tác xóa phải có xác nhận.
6.2 Search và filter
- Ô tìm kiếm hiển thị ngay tại khu vực profile.
- Tìm không phân biệt hoa/thường.
- Trim khoảng trắng đầu/cuối truy vấn.
- Tìm theo các trường: name, host, hostname/IP, username, description, group name và tags.
- Lọc environment: All, Production, Staging, Development, Other.
- Có thể kết hợp search với environment filter.
- Khi không có kết quả, hiển thị empty state kèm nút xóa bộ lọc.
- Không cần gọi mạng để tìm kiếm; tìm trên dữ liệu local.
6.3 Create/Edit Profile form
Các trường nên chia nhóm:

Connection
- Profile Name
- Hostname / IP
- Port
- Username
- Connection Timeout (seconds)
Organization
- Group Type (Project/Client/Custom)
- Group
- Environment
- Description / Tags (nếu có)
Authentication
- Authentication Method: Password / Private Key
- Với Password: nhập password; có tùy chọn lưu trong Keychain.
- Với Private Key: chọn file qua native macOS file picker; hiển thị đường dẫn file; có tùy chọn lưu passphrase trong Keychain khi key cần passphrase.
- Không hiển thị hoặc log secret sau khi lưu.
- Không bắt buộc lưu secret; nếu không lưu, ứng dụng có thể yêu cầu nhập khi kết nối.
Buttons: Test Connection, Save, Cancel.

Behavior:
- Khi đổi authentication method, chỉ hiển thị trường liên quan.
- Không xóa secret cũ một cách âm thầm khi đổi phương thức xác thực; hỏi người dùng hoặc thực hiện cleanup an toàn sau khi lưu thành công.
- Nếu test connection thất bại, giữ nguyên form và cho phép sửa.
- Khi đóng form có thay đổi chưa lưu, hỏi xác nhận bỏ thay đổi.
6.4 Duplicate Profile
- Tạo profile mới với ID mới.
- Sao chép các trường cấu hình không nhạy cảm: host, port, username, environment, group, timeout, description và tags.
- Tên mặc định: <original name> Copy; nếu trùng, thêm hậu tố số.
- Không tự động sao chép secret sang một secret record độc lập.
- Có thể giữ tham chiếu Keychain hiện có nếu thiết kế bảo mật xác định rằng nhiều profile được phép tham chiếu cùng một secret; UI phải minh bạch và không tạo bản sao plaintext. Nếu chưa có cơ chế an toàn, profile duplicate yêu cầu xác thực lại.
- Không tự động kết nối sau khi duplicate.
- Mở form Edit cho profile mới để người dùng xác nhận trước khi lưu.
6.5 Import/Export
Định dạng MVP: JSON có version schema.

Ví dụ cấu trúc export không chứa secrets:
{
  "schemaVersion": 1,
  "exportedAt": "2026-10-25T00:00:00Z",
  "profiles": [
    {
      "name": "BigERP Staging",
      "host": "staging.example.com",
      "port": 22,
      "username": "deploy",
      "authMethod": "privateKey",
      "identityFilePath": "~/.ssh/id_ed25519",
      "environment": "staging",
      "group": {
        "name": "BigERP",
        "type": "project"
      },
      "connectionTimeoutSeconds": 15,
      "description": "Staging application server",
      "tags": ["app", "linux"]
    }
  ]
}
Quy tắc:
- Export mặc định loại bỏ password, passphrase, private key contents, Keychain IDs và mọi credential.
- Có cảnh báo rõ ràng trước khi export: file chỉ chứa cấu hình kết nối, không chứa secrets.
- Import validate schemaVersion, field types, enum values, port range và timeout range.
- Không tin tưởng file import: giới hạn kích thước file và số lượng profile hợp lý; từ chối JSON malformed hoặc cấu trúc không hợp lệ.
- Import preview trước khi ghi dữ liệu.
- Xử lý trùng lặp: cho phép lựa chọn Skip, Import as Copy hoặc Update Existing; không âm thầm ghi đè.
- Profile import không tự kết nối.
- identityFilePath có thể không tồn tại trên máy đích; đánh dấu cần kiểm tra và cho phép chọn lại.
- Group được ghép theo tên + type trong phạm vi import; tránh tạo group trùng ngoài ý muốn.
- Không import secret từ JSON trong MVP.
- Export path qua native save dialog; import path qua native open dialog.
7. Luồng nghiệp vụ
7.1 Tạo profile
1. Người dùng chọn Add Profile.
2. Nhập Name, Host, Port, Username.
3. Chọn Environment và Group tùy chọn.
4. Chọn Password hoặc Private Key.
5. Nếu cần, chọn file key và nhập/lưu credential.
6. Chọn Test Connection (tùy chọn).
7. Chọn Save.
8. Ứng dụng validate dữ liệu, lưu profile vào local database và lưu secret vào Keychain nếu người dùng yêu cầu.
9. Hiển thị thông báo thành công; profile xuất hiện trong danh sách.
7.2 Edit profile
1. Mở Edit từ menu profile.
2. Form hiển thị giá trị hiện tại nhưng không điền secret vào control.
3. Người dùng chỉnh sửa và lưu.
4. Chỉ commit thay đổi sau khi validation thành công.
5. Nếu thay đổi secret, cập nhật Keychain theo cách tránh mất credential cũ khi thao tác lưu thất bại.
7.3 Test connection
1. Validate host, port, username và authentication configuration.
2. Thử kết nối trong thời gian timeout cấu hình.
3. Hiển thị Success hoặc lỗi có hướng xử lý: DNS/host không hợp lệ, timeout, connection refused, host key verification failed, authentication failed, key file missing/unsupported.
4. Không hiển thị password/passphrase trong lỗi hoặc log.
5. Không tạo terminal session lâu dài sau test; đóng socket/transport thử nghiệm sau khi hoàn tất.
7.4 Delete profile
1. Người dùng chọn Delete.
2. Hiển thị tên profile và xác nhận.
3. Xóa profile metadata.
4. Không xóa private key file trên đĩa.
5. Với Keychain secret, chỉ xóa secret khi chắc chắn secret không được profile khác tham chiếu; nếu còn tham chiếu, giữ lại. Thông báo nếu cần cleanup thủ công.
8. Validation và error handling
- name, host, username không được rỗng.
- port phải là số nguyên từ 1 đến 65535.
- connectionTimeoutSeconds phải là số nguyên từ 1 đến 120.
- identityFilePath bắt buộc khi chọn private key.
- Không yêu cầu file key phải tồn tại để lưu profile, nhưng phải cảnh báo và không cho Test Connection thành công nếu file không đọc được.
- Hostname không được chứa scheme hoặc path.
- Tránh hiển thị lỗi kỹ thuật thô cho người dùng cuối; cung cấp thông điệp dễ hiểu và chi tiết kỹ thuật có thể xem khi cần.
- Lỗi lưu DB/Keychain phải giữ dữ liệu form để người dùng thử lại.
- Nếu chỉ lưu một phần dữ liệu thất bại, phải rollback hoặc khôi phục trạng thái nhất quán.
9. Security requirements
- Secrets lưu trong macOS Keychain, không lưu plaintext trong SQLite, JSON export, preferences, crash reports hoặc logs.
- Private key file không được đọc/copy vào database; chỉ lưu đường dẫn.
- Không ghi credential trong analytics hoặc diagnostic logs.
- Dùng native file picker cho Identity File.
- Không tự động chấp nhận SSH host key không xác minh được. Dùng cơ chế known-hosts/fingerprint của kiến trúc SSH và yêu cầu xác nhận khi phù hợp.
- Import file được coi là dữ liệu không đáng tin cậy; validate nghiêm ngặt trước khi lưu.
- Export phải loại bỏ secret kể cả khi profile có credential đã lưu.
- Nếu dùng ID tham chiếu Keychain, ID đó không được coi là secret nhưng vẫn nên loại khỏi file export.
- Không hiển thị credential cũ trong Edit form; trường secret chỉ nhận giá trị mới.
- Không chạy command hoặc tự động kết nối do import profile.
10. Persistence và kiến trúc
Phù hợp với kiến trúc đã định hướng của dự án:
- Flutter Desktop/macOS-first.
- Riverpod cho state management.
- SQLite cho profile/group metadata.
- macOS Keychain cho secrets.
- SSH transport/service nằm trong core SSH layer; UI không gọi trực tiếp implementation SSH.
- Tách repository, model, validation và service khỏi widget/UI.
Đề xuất module logic (tên có thể điều chỉnh theo source thực tế):
- SSHProfile model.
- SSHProfileGroup model.
- SSHProfileRepository — CRUD và query local.
- SSHProfileService — orchestration, duplicate, import/export.
- SSHProfileValidator — validation dùng chung.
- CredentialStore — abstraction cho Keychain.
- SSHConnectionTester — test connection với timeout.
- UI: Profile List, Profile Form, Import Preview, Export confirmation.
Không đặt credential trong Riverpod persisted state, debug serialization hoặc SQLite row. Chỉ truyền secret tới CredentialStore/SSH authentication service trong thời gian cần thiết.
11. Acceptance criteria
CRUD và nhóm
- [ ] Người dùng tạo được profile với các trường bắt buộc hợp lệ.
- [ ] Người dùng sửa và xóa profile.
- [ ] Người dùng tạo/chọn group theo Project, Client hoặc Custom.
- [ ] Người dùng gán và lọc environment.
- [ ] Profile và group vẫn tồn tại sau khi khởi động lại ứng dụng.
Search
- [ ] Search theo name, host/IP, username và group name.
- [ ] Search không phân biệt hoa/thường.
- [ ] Search kết hợp được với environment filter.
- [ ] Empty state có thể xóa filter để xem lại danh sách.
Duplicate
- [ ] Duplicate tạo ID mới, không ghi đè profile gốc.
- [ ] Tên mặc định không trùng hoặc tự tăng hậu tố.
- [ ] Không tự động kết nối.
- [ ] Secret không bị sao chép thành plaintext hoặc tạo bản sao không kiểm soát.
Connection settings
- [ ] Port chỉ chấp nhận 1–65535.
- [ ] Timeout chỉ chấp nhận 1–120 giây.
- [ ] Chọn được Identity File bằng native file picker.
- [ ] Test Connection áp dụng timeout cấu hình.
- [ ] Lỗi kết nối được hiển thị rõ và không làm mất form data.
Import/Export
- [ ] Export JSON thành công và không chứa secrets/Keychain IDs.
- [ ] Import preview dữ liệu trước khi ghi.
- [ ] JSON không hợp lệ bị từ chối an toàn.
- [ ] Có xử lý trùng lặp rõ ràng; không âm thầm ghi đè.
- [ ] Profile imported không tự kết nối.
Security
- [ ] Password/passphrase không xuất hiện trong database, export hoặc logs.
- [ ] Xóa profile không xóa file private key local.
- [ ] Secret chỉ bị xóa khỏi Keychain khi không còn profile tham chiếu.
- [ ] Host key không được tự động trust khi không xác minh.
- [ ] Không có secret trong lỗi hiển thị hoặc debug output.
12. Test plan
Unit tests
- Validation profile fields.
- Port/timeout boundary values.
- Search normalization và các trường tìm kiếm.
- Duplicate naming và tạo ID mới.
- JSON import/export schema validation.
- Export secret stripping.
- Duplicate/import collision resolution.
- Group matching theo tên và loại.
Integration tests
- CRUD với SQLite.
- Keychain adapter qua mock và kiểm tra xử lý lỗi.
- Test connection thành công, authentication failed, timeout, refused và host-key mismatch bằng SSH test server/mock phù hợp.
- Import/export file qua service layer.
- Xóa profile có và không có secret được chia sẻ.
UI tests
- Tạo/sửa/xóa profile.
- Chuyển đổi authentication method.
- Chọn Identity File.
- Search và environment filter.
- Duplicate flow.
- Import preview và conflict resolution.
- Xác nhận export không chứa credential.
- Cảnh báo khi đóng form chưa lưu.
Security regression tests
- Quét output JSON export để xác nhận không có secret.
- Xác nhận logs không chứa password/passphrase.
- Kiểm tra profile duplicate không làm lộ hoặc sao chép secret ngoài ý muốn.
- Kiểm tra file import malformed không làm crash ứng dụng.
13. Definition of Done
- Mọi acceptance criteria P0 được đáp ứng.
- Unit, integration và UI tests liên quan đều pass.
- Không lưu secrets dạng plaintext.
- Không làm hỏng các chức năng SSH Profile/connection hiện có.
- UI có loading, empty, success và error states.
- Tài liệu kiến trúc, roadmap và test plan được cập nhật khi tích hợp vào source repository.
- Có ít nhất một kiểm thử thủ công trên macOS với password authentication và private-key authentication.
14. Open implementation notes
- Giữ environment là enum riêng, không phụ thuộc vào tên group.
- Trong MVP, ưu tiên group phẳng để tránh UI và migration phức tạp.
- Xác định rõ cách biểu diễn ~ trong Identity File path; nên chuẩn hóa đường dẫn tại thời điểm sử dụng, không thay đổi đường dẫn gốc mà không báo người dùng.
- Nếu SSH library chưa hỗ trợ connection timeout theo từng giai đoạn, tạo timeout orchestration ở service layer và đảm bảo socket/transport được đóng khi timeout.
- Với import/update existing, cần định nghĩa khóa nhận diện rõ ràng; không dùng host đơn lẻ làm unique key vì nhiều profile có thể dùng cùng host với username hoặc auth khác nhau.
---

## Implementation status (2026-10-25, ADR-012)

Implemented against this spec; decisions and the full
already-compliant inventory are recorded as ADR-012 in
`docs/DECISIONS.md`.

**Verified as already present and left unchanged:** profile CRUD
with delete confirmation; flat AND nested groups (beyond the
flat minimum); persistence across restarts; Keychain-only
secrets referenced by ID; private keys referenced by path only
with `~` expanded at use time; per-field validation (name, host
without scheme, port 1–65535, username); connection timeouts
applied at the SSH transport; native file picker for the
Identity File; secrets never pre-filled in the Edit form;
deleting a profile never deletes the key file, and deletes its
Keychain secret only when no other profile references it.

**Added by this implementation:**
- `environment` (production/staging/development/other) as an
  independent profile field — legacy profiles load as `other`,
  new ones default to development; full-word **PRODUCTION**
  badge in the list; environment filter chips combining with
  search; search also covers description, tags and group name;
  a Clear-filters action in the no-results state.
- `description` (≤500) and normalized `tags`; folder `type`
  (project/client/custom) with an editor; collapsible groups.
- `lastConnectionStatus` (success/failed outcome only) recorded
  on every connect attempt and shown in the list.
- Duplicate per section 6.4's shared-reference option: the copy
  SHARES the original's Keychain reference (no secret copy is
  created), is named `<name> Copy` with numeric suffixes, and
  opens in the editor. Sharing is made safe by copy-on-write
  secret edits and the reference-counted delete.
- Test Connection (section 7.3) in the editor (on the unsaved
  draft) and in the session menu: a real connect through the
  SSH layer with the usual host-key/password prompts and the
  profile's timeout, closed immediately, reporting typed
  secret-free errors; a failed test keeps the form intact.
- Import/Export (section 6.5) exactly in the documented JSON
  shape: export strips secrets AND Keychain reference IDs;
  import enforces the 2 MB / 500-profile limits and strict
  schema/type/enum/range validation (rejecting malformed files
  whole, with a readable reason), previews New/Duplicate per
  profile, and applies Skip / Import as Copy / Update Existing.
  Conflict identity is name+host+username+port (section 14);
  groups match by name+type; update preserves the existing
  profile's ID and stored credential; imports never connect.
- Editor unsaved-changes guard (confirm before discarding).

**Deliberate deviations, recorded in ADR-012:**
- Persistence stays on the established JSON library store
  (ADR-006) rather than SQLite — it already meets the spec's
  persistence and security requirements.
- The connection timeout range is now 1–120 s with default 15
  (sections 5/8/11), superseding the earlier 1–600 s / 20 s;
  older profiles with a longer timeout are flagged by
  validation when next edited.
- A missing Identity File is a warning in the editor, not a
  save blocker (section 8).
- Duplicate saves immediately and then opens the editor for
  review (rather than editing an unsaved draft).

**Verification:** full automated suite (model/validation,
controller incl. duplicate sharing + copy-on-write + import
strategies, transfer incl. export secret-stripping scan and
import rejection cases, tester, and widget tests for the badge,
filter, form test and discard guard) plus a live check against
a local SSH fixture: Test Connection success, wrong-password
failure with a secret-free message, and an export→import round
trip.

---

## Revision note — ADR-013 (2026-10-25, user-directed)

After using the implementation above, the user directed a simplification that supersedes parts of this spec: the **environment label and its filter** (sections 5/6.2) and **tags** are replaced by a single **Labels** feature — named, coloured labels, multiple per profile, shown on each item and filterable via chips under the search box. Sessions and folders also gained an optional icon + colour, and the session item's endpoint subtitle moved into a hover tooltip. Existing environment/tags data migrates to labels automatically (Production red, Staging orange, Development blue); old export files still import (their environment/tags become labels). The rest of this spec (CRUD, shared-reference duplicate, Test Connection, strict import/export, validation, timeout range) is unchanged. See `docs/DECISIONS.md` ADR-013.
