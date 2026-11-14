# 09 · Quản trị

Nhóm **Quản trị** là ba màn hình và **chỉ quản trị viên** mở được. Cả ba nói về cùng
một thứ: **ai được làm gì ở đâu**.

| Màn hình | Trả lời câu hỏi |
| --- | --- |
| **Phê duyệt** | Ai đang xin vào Nền tảng, và cho họ vào với vai trò gì? |
| **Tài khoản** | Người đã vào thì được làm gì, ở đơn vị nào? |
| **Vai trò** | Một vai trò gồm những quyền gì — và tôi muốn đổi định nghĩa đó. |

**Ba câu phải nói trước khi dạy nhóm này.**

1. **Mọi mã quyền của cả ba màn hình chỉ nằm trên `ROLE_ADMIN`.** Không có cách nào
   để một người không phải quản trị viên mở chúng — trừ khi chính quản trị viên gán
   vai trò `admin` cho người đó.
2. **`ROLE_ADMIN` đi qua mọi mã quyền ở máy chủ.** Nghĩa là lấy một quyền ra khỏi vai
   trò `ROLE_ADMIN` **không** làm quản trị viên mất quyền đó. Muốn giới hạn một người,
   hãy **đổi vai trò của họ**, đừng sửa vai trò `ROLE_ADMIN`.
3. **Không có nút xoá Tài khoản nào.** Vô hiệu hoá là chặn đăng nhập; vai trò và các
   quyền trên Đơn vị tổ chức **vẫn giữ nguyên**.

---

## Phê duyệt

**Việc này để làm gì.** Người vừa đăng nhập lần đầu đang chờ; chấp nhận họ với một
vai trò, hoặc từ chối.

**Ai thao tác được.** `ADM_APPROVALS_DISPLAY` để đọc, `ADM_APPROVALS_DECIDE` để quyết
định — **chỉ quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc hàng chờ, tìm theo **địa chỉ email**. | Tài khoản hiện ở đây **ngay khi có người đăng nhập lần đầu** bằng tài khoản ngoài. Không có thông báo tự động nào. | Phải mở màn hình ra xem; không ai gọi bạn. |
| 2 | Bấm **Chấp nhận** để mở hộp thoại: chọn **vai trò**, các **quyền trên Đơn vị tổ chức**, và **Thẩm quyền Chất lượng** / **Thẩm quyền An toàn** nếu cần. | Câu trong hộp thoại nói rõ: **{email} sẽ được vào Nền tảng với vai trò được chọn ở đây.** | |
| 3 | Không chọn quyền nào: Nền tảng cảnh báo tài khoản **đăng nhập được nhưng chưa thao tác được ở đơn vị nào**. | Đây là trạng thái hợp lệ, và hay là điều bạn muốn cho người mới trong tuần đầu. | |
| 4 | Bấm **Chấp nhận**, hoặc **Từ chối**. | Từ chối **không xoá** gì: người đó được báo là yêu cầu đã bị từ chối, và **quản trị viên vẫn chấp nhận được sau**. | |

**Điểm then chốt.** Chọn vai trò `admin` trong hộp thoại này là **trao toàn bộ Nền
tảng**: hộp thoại cảnh báo rằng tài khoản đó sẽ thấy và thay đổi được **mọi Nhà máy,
mọi Đơn vị tổ chức**, và **chấp nhận được các Tài khoản khác**.

> **Vì sao.** Đây là con đường duy nhất để có quản trị viên thứ hai. Nếu trao nhầm, hãy
> mở **Tài khoản → Đổi** và đặt lại vai trò — ngay hôm đó.

---

## Tài khoản

**Việc này để làm gì.** Mọi tài khoản ở nhà máy này: đang giữ gì, và có đăng nhập được
không.

**Ai thao tác được.** `ADM_ACCOUNTS_DISPLAY` để đọc, `ADM_ACCOUNTS_CHANGE` để đổi —
**chỉ quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm theo **tên, email hoặc vai trò**. | | |
| 2 | Đọc từng dòng: **vai trò**, **quyền trên Đơn vị tổ chức**, và trạng thái đăng nhập. | **Không có quyền trên Đơn vị tổ chức nào** là một trạng thái có thật: đăng nhập được nhưng chưa thao tác được ở đâu. | |
| 3 | Đổi vai trò và quyền: bấm **Đổi** → **Đổi vai trò và quyền**. | **Những gì đặt trong hộp thoại này THAY THẾ toàn bộ những gì tài khoản đang có.** | Đây là cái bẫy lớn nhất của màn hình này. |
| 4 | Liên kết với một Nhân viên: **Liên kết Nhân viên** → chọn người, hoặc để trống. | | Không liên kết thì Tài khoản không có hồ sơ nhân sự, và một số màn hình nói rõ điều đó. |
| 5 | Đặt lại mật khẩu: **Đặt lại mật khẩu**, gõ mật khẩu mới. | **Bạn tự báo mật khẩu cho người đó — nó không hiển thị lại lần nữa.** Người đó sẽ bị buộc đổi ngay lần đăng nhập sau. | |
| 6 | Chặn đăng nhập: **Ngừng kích hoạt**, xác nhận. | **Không có gì bị xoá** — vai trò và các quyền trên Đơn vị tổ chức giữ nguyên, và **Kích hoạt lại** đưa họ trở về. | |
| 7 | Chấp nhận/từ chối một tài khoản đang chờ: **Xem trong Phê duyệt**. | | Màn hình này chuyển bạn sang đó thay vì làm trùng việc. |

> **Điểm then chốt quan trọng nhất — nói chậm câu này.** Bước 3 **thay thế toàn bộ**
> quyền. Nếu bạn mở hộp thoại chỉ để đổi vai trò mà không đánh dấu lại các Đơn vị tổ
> chức, **người đó mất hết quyền trên đơn vị**.

> **Vì sao.** Đó là chủ ý: hộp thoại hiện đúng trạng thái hiện tại, để bạn thấy điều
> mình sắp đặt. Nhưng nếu không đọc câu cảnh báo trong hộp thoại, bạn sẽ tưởng nó chỉ
> sửa một trường.

**Ba trạng thái đặc biệt, và hộp thoại nói rõ từng cái:**

| Trạng thái | Câu trong hộp thoại | Lưu lại thì |
| --- | --- | --- |
| Đang bị vô hiệu | "Tài khoản này đang bị vô hiệu…" | **Kích hoạt lại** và cho đăng nhập |
| Đã bị từ chối | "Tài khoản này đã bị từ chối…" | **Chấp nhận** tài khoản vào Nền tảng |
| Vai trò `admin` | "Quản trị viên thao tác được ở mọi nơi…" | Bỏ **toàn bộ** quyền trên Đơn vị tổ chức — vì không cần |

---

## Vai trò

**Việc này để làm gì.** Một vai trò gồm những quyền gì, và ai đang mang nó.

Đây là màn hình **thay đổi định nghĩa của Nền tảng** — không phải nơi xem. Sửa ở đây
là sửa cho **mọi** người mang vai trò đó, cùng lúc.

**Ai thao tác được.** `ADM_ROLES_DISPLAY` để đọc, `ADM_ROLES_CHANGE` để sửa — **chỉ
quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc danh sách: mỗi dòng có **cột quyền** và số **tài khoản** đang mang. | **Tự động: {vai trò}** nghĩa là vai trò này được gán cho mọi Tài khoản có vai trò riêng là `{vai trò}` — nó không gán tay được. | Sửa nó là sửa cho cả một lớp người dùng, không phải một nhóm nhỏ. |
| 2 | Sửa quyền: bấm **Quyền** trên một dòng, đánh dấu/bỏ đánh dấu, **Lưu**. | Hộp thoại đếm **"{n} trên {tổng} quyền"**. Mỗi quyền có mã và mô tả tiếng Anh — đọc mô tả, đừng đoán theo mã. | |
| 3 | Thêm vai trò: **Thêm vai trò** → **Mã**, **Tên**, **Dùng để làm gì**. | Mã **3–30 ký tự**: `A–Z`, `0–9`, dấu gạch dưới. Ví dụ `ROLE_STORE_ROOM`. | Mã là thứ mã nguồn và báo cáo dùng — sai định dạng là từ chối ngay. |
| 4 | Ngừng dùng: **Điều chỉnh** → bỏ **Đang dùng**. | Vai trò đã ngừng **vẫn giữ lịch sử** và **không gán được cho ai**. | |
| 5 | Gán vai trò cho một người: ở **Tài khoản → Vai trò của {tên}**. | Màn hình này **không** gán vai trò; nó chỉ định nghĩa vai trò. | Lẫn hai màn hình là lý do phổ biến của "tôi thêm quyền rồi mà người đó vẫn không làm được". |

> **Điểm then chốt quan trọng nhất.** **Nhóm mặc định** (`ROLE_STANDARD`) là vai trò
> mà **mọi** Tài khoản đều mang. Bỏ một quyền khỏi nó là bỏ quyền đó **cho tất cả mọi
> người trong nhà máy**, không phải cho một người.

> **Vì sao.** Đó là chỗ duy nhất quyền được định nghĩa **một lần cho tất cả**. Nếu bạn
> cần chỉ một người mất quyền, đừng sửa nhóm mặc định — hãy tạo một vai trò và đổi
> vai trò của người đó.

**Nếu màn hình báo "Không có vai trò nào mang quyền".** Đây là tình trạng bản triển
khai chưa chạy đủ bước khởi tạo dữ liệu — không phải một cấu hình bạn tạo ra. Báo người
quản trị hệ thống.

---

## Ba việc hay bị làm sai — và cách làm đúng

| Ý định | Cách làm **sai** hay gặp | Cách làm **đúng** |
| --- | --- | --- |
| Cho một người thêm một quyền | Sửa vai trò của họ trong **Vai trò** | **Tài khoản → Đổi → Đổi vai trò và quyền**: gán thêm vai trò, hoặc thêm Đơn vị tổ chức. **Nhớ đánh dấu lại các đơn vị đang có.** |
| Cho một người mất một quyền | Bỏ quyền khỏi **Vai trò** | Đổi vai trò của người đó, hoặc tạo vai trò mới không có quyền ấy |
| Thêm người mới | Tạo **Nhân viên** ở Danh bạ | **Nhân viên** là hồ sơ; quyền đăng nhập là **Tài khoản** + **Phê duyệt**. Hai việc, hai màn hình |

---

## Bảng tóm tắt phần Quản trị

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem hàng chờ Phê duyệt | · | · | · | · | · | ✓ |
| Chấp nhận / Từ chối một Tài khoản | · | · | · | · | · | ✓ |
| Xem danh sách Tài khoản | · | · | · | · | · | ✓ |
| Đổi vai trò, quyền, liên kết Nhân viên, đặt lại mật khẩu, vô hiệu hoá | · | · | · | · | · | ✓ |
| Xem danh mục Vai trò | · | · | · | · | · | ✓ |
| Sửa quyền của một Vai trò, thêm vai trò, ngừng dùng | · | · | · | · | · | ✓ |
