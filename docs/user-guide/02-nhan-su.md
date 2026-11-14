# 02 · Nhân sự

Nhóm **Nhân sự** trả lời bốn câu: ai làm việc ở đây, họ làm được gì, ai có mặt ở
ca nào, và ai đã được đào tạo cái gì. Ngoài ra có hai danh mục tiền (**Đơn giá
giờ**, **Chi phí chuẩn sản phẩm**) và một màn hình tự phục vụ (**Chữ ký của tôi**).

**Đọc rộng, ghi hẹp.** Danh bạ, Chức danh, Kỹ năng, Đơn vị tổ chức, Đào tạo và
Đơn xin nghỉ ai cũng **đọc** được. Nhưng **ghi** thì phần lớn chỉ quản trị viên,
và mọi thao tác ghi đều cần phạm vi **Đơn vị tổ chức**.

---

## Danh bạ

**Việc này để làm gì.** Tìm một Nhân viên, xem hồ sơ của họ, và — nếu bạn là quản
trị viên — thêm hoặc sửa hồ sơ.

**Ai thao tác được.**
Đọc: `PPL_DIRECTORY_DISPLAY` — **mọi vai trò**, kể cả người vận hành.
Ghi: `PPL_DIRECTORY_CHANGE` — **chỉ quản trị viên**.
Đọc hồ sơ của chính mình: mọi Tài khoản, qua **Hồ sơ của tôi**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Gõ tên vào ô **Tìm theo tên**. | Tìm theo **tên**, không theo mã nhân viên. | Mã nhân viên dùng để tìm trong các ô chọn Nhân viên khác (ví dụ khi thêm học viên đào tạo). |
| 2 | Thu hẹp bằng **Đơn vị tổ chức** và **Chức danh công việc** nếu danh sách dài. | Bộ lọc Đơn vị tổ chức **bao gồm mọi đơn vị bên dưới** nó. | Chọn "Bộ phận Sản xuất" là thấy cả các tổ bên trong. |
| 3 | Người đã nghỉ việc **bị ẩn** cho tới khi bạn bật **Gồm cả người đã rời**. | Đừng kết luận "không có người này" khi chưa bật ô đó. | Đây là lỗi hay gặp nhất ở Danh bạ. |
| 4 | Bấm một dòng để mở **Hồ sơ Nhân viên**. | | |

**Điểm then chốt cho quản trị viên thêm người mới** (`PPL_DIRECTORY_CHANGE`):

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm Nhân viên**. | | |
| 2 | Điền **Mã nhân viên**, **Họ**, **Tên**, **Loại hình làm việc**. | Mã nhân viên không đổi được về sau và là thứ công nhân quét ở thiết bị Xưởng. | Sai mã nhân viên là công nhân không đăng nhập được ở Xưởng. |
| 3 | Điền **Email công việc** nếu có (không bắt buộc). | | |
| 4 | Bấm lưu, rồi mở hồ sơ vừa tạo và bấm **Phân công** để gán vào Đơn vị tổ chức. | **Một Nhân viên chưa được phân công thì chưa thuộc tổ nào** — không hiện trong bảng chấm công của ca. | Tạo hồ sơ mà quên phân công là nguyên nhân số một của "người này không có trong bảng chấm công". |

> **Một điều phải nói rõ trước khi dạy.** Thêm **Nhân viên** không phải là tạo
> **Tài khoản**. Nhân viên là một con người trong Danh bạ; Tài khoản là quyền đăng
> nhập, và Tài khoản do quản trị viên tạo ở màn hình **Tài khoản**, rồi **chấp
> nhận** ở **Phê duyệt**. Hai việc khác nhau, hai màn hình khác nhau.

---

## Hồ sơ Nhân viên

**Việc này để làm gì.** Xem một người: đang làm ở đâu, đã từng làm ở đâu, có
chứng nhận gì, chữ ký nào, và đã làm bao nhiêu giờ.

**Ai thao tác được.** Mọi Tài khoản đã được chấp nhận (đọc). Các nút ghi:
**Sửa hồ sơ**, **Phân công**, **Ghi nhận đã rời**, **Khôi phục** cần
`PPL_DIRECTORY_CHANGE` (quản trị viên). **Ghi nhận kỹ năng** / **Đánh giá lại**
cần `PPL_SKILLS_CHANGE` (quản trị viên).

**Đường dẫn.** `/directory/:id`, hoặc `/directory/me` cho **Hồ sơ của tôi**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Vào từ một dòng ở Danh bạ, hoặc bấm **Hồ sơ của tôi**. | **Hồ sơ của tôi** mở đúng hồ sơ gắn với Tài khoản đang đăng nhập. | Ai cũng xem được hồ sơ mình mà không cần tìm mình trong danh sách. |
| 2 | Xem **Lịch sử phân công**: dòng **Hiện tại**, rồi các dòng đã hết hiệu lực. | Một người có thể đổi tổ nhiều lần; chỉ dòng **Hiện tại** quyết định họ thuộc ca nào bây giờ. | Đọc nhầm dòng cũ là ghi giờ công sai tổ. |
| 3 | Xem phần **Kỹ năng** và **Chữ ký**. | Nút **Ghi nhận kỹ năng** nằm ngay trên phần kỹ năng. | |
| 4 | Bấm **Giờ đã làm** để xem số giờ theo ngày. | | |

**Điểm then chốt.** **Ghi nhận đã rời** không xoá ai. Người đó chỉ chuyển sang
trạng thái **Đã rời** và bị ẩn khỏi Danh bạ; **Khôi phục** đưa họ trở lại.

> **Vì sao.** Lịch sử chấm công, đào tạo và lệnh công việc đều trỏ về hồ sơ này.
> Xoá hồ sơ sẽ làm hỏng các bản ghi đó. Vì vậy Nền tảng **không có** nút xoá Nhân viên.

---

## Giờ đã làm của một Nhân viên

**Việc này để làm gì.** Xem số giờ một người **thực sự** đã làm, theo từng ngày.

**Ai thao tác được.** Mọi Tài khoản đã được chấp nhận.

**Đường dẫn.** `/directory/:employeeId/work-hours`, mở từ hồ sơ Nhân viên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đặt **Từ** và **Đến**. | | |
| 2 | Đọc bảng: **Ngày**, **Đã làm**, **Ngoài giờ**, và "trên {X} theo lịch". | Cột "theo lịch" là số giờ ca dự kiến, không phải giờ đã làm. | |
| 3 | Đọc dòng **Tổng cộng**. | | |

**Điểm then chốt quan trọng nhất.** **Chỉ chấm công đã xác nhận mới được tính.**
Bảng chấm công chưa bấm **Xác nhận** chỉ là bản nháp và **không** hiện ở đây.

> **Vì sao.** Nếu bảng trống, câu trả lời không phải "người này không đi làm" mà
> thường là "giám sát chưa xác nhận chấm công". Kiểm tra ở **Chấm công cần xác
> nhận** trước khi kết luận.

---

## Chức danh công việc

**Việc này để làm gì.** Danh mục nghề: nhân viên làm gì. Khai báo **một lần**,
dùng chung cho **mọi** Nhà máy.

**Ai thao tác được.**
Đọc: `PPL_JOB_ROLES_DISPLAY` — mọi vai trò.
Ghi: `PPL_JOB_ROLES_CHANGE` — chỉ quản trị viên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm theo **tên hoặc mã**. | | |
| 2 | Bấm **Thêm chức danh**: điền **Mã**, **Tên**. | Mã nên ngắn, không dấu, viết hoa — vì mã xuất hiện trong danh sách chọn ở hồ sơ Nhân viên. | |
| 3 | Để ngừng dùng một chức danh, bấm **Điều chỉnh** và bỏ **Đang làm**. | Ngừng dùng **không** làm mất chức danh khỏi hồ sơ người đang giữ nó. | Danh mục là lịch sử, không phải danh sách hiện hành. |

---

## Kỹ năng

**Việc này để làm gì.** Danh mục điều nhà máy **công nhận** một Nhân viên làm
được, và ai đang có kỹ năng đó.

**Ai thao tác được.**
Đọc: `PPL_SKILLS_DISPLAY` — mọi vai trò.
Ghi danh mục và ghi nhận kỹ năng cho một người: `PPL_SKILLS_CHANGE` — **chỉ quản
trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm theo **tên, mã hoặc hạng mục**. | | |
| 2 | Bấm **Thêm kỹ năng**: **Mã**, **Tên**, **Hạng mục**, **Cần chứng nhận**, **Chu kỳ đánh giá lại (tháng)**. | Để trống chu kỳ đánh giá lại nghĩa là kỹ năng này **không bao giờ** hết hạn. | Điền chu kỳ cho mọi kỹ năng cần chứng nhận — đó là thứ Nền tảng dùng để cảnh báo hết hạn. |
| 3 | Bấm **Ai đang có kỹ năng này** để xem danh sách người đủ điều kiện. | | |
| 4 | Ghi nhận cho một người: mở **Hồ sơ Nhân viên → Ghi nhận kỹ năng**, chọn **Mức thành thạo (0–4, ILUO)**, **Đánh giá ngày**, **Hết hạn ngày**, **Tham chiếu minh chứng**. | **0 — không có** là một mức hợp lệ, nghĩa là không đạt. | Ghi 0 khác với không ghi gì: 0 là đã đánh giá và không đạt. |

**Điểm then chốt.** **Hết hạn ngày** để trống thì Nền tảng tự tính từ **chu kỳ
đánh giá lại** của kỹ năng đó.

---

## Đơn vị tổ chức

**Việc này để làm gì.** Hình thù của nhà máy: **Nhà máy** ở trên, các **Đơn vị tổ
chức** lồng nhau bên dưới. Đây là nơi KPI được đo, nơi Tài khoản được cấp quyền,
và nơi một Tài sản nằm.

**Ai thao tác được.**
Đọc: `PPL_ORG_UNITS_DISPLAY` — mọi vai trò.
Ghi: `PPL_ORG_UNITS_CHANGE` — **chỉ quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy** ở đầu trang. | Nền tảng hỗ trợ nhiều Nhà máy; cây bên dưới chỉ là của Nhà máy đang chọn. | Lẫn hai nhà máy là lỗi hay gặp khi nhà máy thứ hai vừa được thêm. |
| 2 | **Thu gọn / Mở rộng** các nhánh, hoặc gõ vào ô **Tìm Đơn vị tổ chức theo tên**. | Chọn một kết quả tìm kiếm sẽ **mở và chọn** đơn vị đó trong cây. | |
| 3 | Bấm **Thêm Đơn vị tổ chức ở đây** trên một đơn vị để thêm đơn vị con: **Mã**, **Tên**, **Loại đơn vị**, **Thứ tự sắp xếp**. | **Loại đơn vị** quyết định rất nhiều chỗ khác: bộ phận / tổ / khu vực. | Chọn sai loại là bảng chấm công và bảng Bộ phận không hiện đúng. |
| 4 | Bấm **Thêm Nhà máy** khi bắt đầu một nhà máy mới: **Mã**, **Tên**, **Mã quốc gia**. | Mọi Đơn vị tổ chức đều nằm dưới một Nhà máy — không có đơn vị nào đứng ngoài. | |
| 5 | Để ngừng một đơn vị: bấm **Ngừng sử dụng**, xác nhận. | Đơn vị được **ghi là đã ngừng** chứ **không bị xoá**, và **Khôi phục** được bất cứ lúc nào. | Lịch sử công việc và chấm công vẫn trỏ về nó. |

**Điểm then chốt cho người nhập cây lớn.** **Nhập một nhánh** nhận **một mảng
JSON**; mỗi dòng tham chiếu cha bằng **`parentCode`** — một dòng khác trong cùng
mảng, hoặc một mã đã có ở Nhà máy này — **không bao giờ bằng id**.

> **Vì sao.** Bạn nhập cây trước khi biết id (id do máy chủ sinh). Dùng `parentCode`
> thì cùng một tệp nhập được vào cả môi trường thử và môi trường thật.

---

## Chấm công

**Việc này để làm gì.** Mở bảng chấm công của một ca, xác nhận ai có mặt, và ghi
ngoại lệ (vắng, đi trễ, người thay ca).

**Ai thao tác được.**
Xem danh sách ca để chọn: `PPL_ATTENDANCE_DISPLAY` — mọi vai trò.
**Mở và xác nhận** một bảng: `PPL_ATTENDANCE_CHANGE` — **supervisor, engineer,
manager, quản trị viên** — **và** quyền sửa trên Đơn vị tổ chức của ca đó.
Một giám sát không có quyền sửa ở tổ đó **không mở được bảng**, kể cả khi cùng vai trò.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy**, **Đơn vị tổ chức** và **Ngày sản xuất**. | **Ngày sản xuất** không phải ngày dương lịch của bạn — ca đêm thuộc về ngày sản xuất của nó. | Ghi nhầm ngày là giờ công rơi sang ca khác. |
| 2 | Chọn ca trong danh sách để mở **Bảng chấm công**. | Ngày đó không có ca nào thì Nền tảng nói rõ, không phải lỗi. | |
| 3 | Trong bảng, bấm một dòng để **Chấm công** người đó: **Trạng thái**, **Số phút đã làm**, **Số phút ngoài giờ**, **Lý do**, **Ghi chú**. | **Số phút**, không phải số giờ. | 8 giờ là `480`. Đây là chỗ sai nhiều nhất. |
| 4 | Người không có trong ca nhưng có mặt: bấm **Thêm người thay ca** rồi tìm trong **Danh bạ**. | | |
| 5 | Người trong ca nhưng không đi làm: **Đánh dấu ngoại lệ**, không phải bỏ khỏi bảng. | **Bỏ khỏi bảng** là xoá người khỏi ca; **ngoại lệ** là có đi làm hay không. | Bỏ khỏi bảng làm mất dấu người đó đã được xếp ca. |
| 6 | Bấm **Xác nhận**. | Bảng đã xác nhận hiện **Đã xác nhận**, và **chỉ từ lúc đó** giờ công mới vào **Giờ đã làm**. | |

**Điểm then chốt quan trọng nhất.** Bảng ghi được **nhiều hơn một lần** — nhưng
chỉ lần **Xác nhận** mới có giá trị. Đừng rời màn hình khi chưa bấm **Xác nhận**.

---

## Chấm công cần xác nhận

**Việc này để làm gì.** Danh sách việc: các ca **đã qua** mà bảng chấm công còn
thiếu hoặc chưa xác nhận.

**Ai thao tác được.** Người mang `PPL_ATTENDANCE_CHANGE` — supervisor trở lên —
và chỉ thấy các Đơn vị tổ chức mình xác nhận được.

**Đường dẫn.** `/attendance/to-confirm`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đặt **Từ** / **Đến** và **Lọc theo Đơn vị tổ chức**. | Danh sách xếp **cũ nhất trước**. | Việc cũ nhất là việc đang chặn báo cáo giờ công tháng. |
| 2 | Bấm **Mở bảng chấm công** trên một dòng. | | |
| 3 | Làm xong bảng, quay lại — dòng đó biến mất. | | |

---

## Bảng chấm công một ca

Đã dạy ở mục **Chấm công** bước 3–6. Đường dẫn trực tiếp:
`/attendance/:shiftInstanceId`.

**Một điểm riêng cần nói.** Bảng **chỉ mở được cho người có quyền sửa bao trùm ca
này** (hoặc quản trị viên). Một người vận hành mở địa chỉ này sẽ thấy câu "Chưa có
ai có quyền sửa ở đây mở bảng này" — đó là câu trả lời đúng, không phải lỗi.

---

## Đào tạo

**Việc này để làm gì.** Sổ đào tạo: nhà máy đã đào tạo ai, điều gì, khi nào — và
học viên tự xác nhận mình có tham gia.

**Ai thao tác được.**
Đọc: `PPL_TRAINING_DISPLAY` — mọi vai trò.
Tạo / sửa / thêm học viên / gửi: `PPL_TRAINING_CHANGE` — **supervisor trở lên**.
Tự trả lời đào tạo của mình: `PPL_TRAINING_ANSWER_OWN` — **mọi vai trò**.

**Các bước chính — người tổ chức buổi đào tạo**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Tạo bản ghi đào tạo**: **Tiêu đề**, **Đào tạo ngày**, **Thời lượng (giờ)**, **Người đào tạo**, **Mục tiêu**. | **Thời lượng** dùng dấu phẩy thập phân: `1,5`. | Dấu chấm bị hiểu là phân cách nghìn. |
| 2 | Mở bản ghi vừa tạo, bấm **Thêm học viên**: chọn **Nhân viên của {đơn vị}** hoặc **Toàn bộ Danh bạ**. | | |
| 3 | Bấm **Gửi cho học viên**. | Trước khi gửi, đây là **bản nháp**: sửa và thêm người được. Sau khi gửi thì **chốt**. | Sửa sau khi gửi là sửa việc người khác đã ký. |
| 4 | Bỏ cả bản nháp nếu ghi nhầm: **Bỏ bản nháp**. | Chỉ làm được khi **chưa ai được hỏi**. | Bản nháp đã gửi thì không bỏ được. |

**Các bước chính — học viên**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Vào **Đào tạo cần xác nhận** (`/training/to-confirm`), hoặc ô "Đào tạo cần xác nhận" ở Trang chủ. | Danh sách xếp **cũ nhất trước** và chỉ có bản gửi **cho chính bạn**. | |
| 2 | Bấm **Xác nhận** nếu bạn đã tham gia, hoặc **Từ chối** nếu bản ghi sai. | | |
| 3 | Ký: **Dùng chữ ký của tôi**, hoặc **Vẽ ngay**, hoặc **Không có chữ ký**. | Chọn **Không có chữ ký** vẫn xác nhận được — người xác nhận không bị chặn. | Có người chưa lưu chữ ký; chặn họ lại thì sổ đào tạo không khép được. |

> **Điểm then chốt cho người đào tạo.** Sổ đào tạo chỉ có giá trị khi học viên
> **tự** bấm xác nhận. Không có cách nào để người tổ chức xác nhận thay.

---

## Bản ghi đào tạo (chi tiết)

**Việc này để làm gì.** Xem một buổi đào tạo: mục tiêu, thời lượng, người đào tạo,
và câu trả lời của từng học viên.

**Ai thao tác được.** Mọi Tài khoản (đọc). Ghi theo `PPL_TRAINING_CHANGE`.

**Đường dẫn.** `/training/:id`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc phần **Buổi đào tạo** và **Học viên (n)**. | | |
| 2 | Đọc **Câu trả lời** của từng người: đã xác nhận hay từ chối. | | |
| 3 | Bấm **Biểu mẫu** để mở bản in (`/training/:id/form`) khi cần ký giấy. | | |

---

## Biểu mẫu in của bản ghi đào tạo

**Việc này để làm gì.** Bản in "Biên bản ghi nhận đào tạo" — danh sách tham gia,
trên giấy, để ký tay.

**Ai thao tác được.** Mọi Tài khoản.

**Đường dẫn.** `/training/:id/form`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Mở biểu mẫu từ trang chi tiết. | | |
| 2 | In bằng **trình duyệt** (Ctrl+P). | Không có nút in riêng của Nền tảng. | |
| 3 | Ký giấy là **thêm** vào sổ điện tử, không thay thế nó. | | |

---

## Chữ ký của tôi

**Việc này để làm gì.** Lưu dấu của chính bạn, để dùng ở mọi nơi bạn phải ký —
xác nhận đào tạo, xác nhận sự cố.

**Ai thao tác được.** Mọi Tài khoản: `PPL_SIGNATURE_OWN`. Không ai đặt chữ ký thay
người khác ở màn hình này. (Quản trị viên đặt chữ ký **cho** một Nhân viên được,
nhưng ở **Hồ sơ Nhân viên → Chữ ký**, bằng `PPL_DIRECTORY_CHANGE`.)

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Mở **Chữ ký của tôi**. | | |
| 2 | Hoặc **Tải ảnh lên** một ảnh chữ ký có sẵn, hoặc **Vẽ tại đây** rồi bấm **Giữ chữ ký này**. | Ảnh cần nền sáng, nét đậm. | |
| 3 | Đổi chữ ký: **Vẽ chữ ký mới** hoặc **Thay bằng ảnh**; bỏ hẳn: **Xoá**. | | |

> **Điểm then chốt quan trọng nhất.** **Thay chữ ký không làm thay đổi bảng nào
> bạn đã ký.** Chữ ký được gắn vào bản ghi tại thời điểm ký.

> **Vì sao.** Nếu đổi chữ ký mà các bản ghi cũ đổi theo, một chữ ký mới hôm nay sẽ
> "ký lại" cả năm trước — và biên bản đào tạo mất giá trị.

---

## Đơn xin nghỉ

**Việc này để làm gì.** Nhân viên gửi đơn xin nghỉ và theo dõi kết quả; người phụ
trách duyệt hoặc từ chối.

**Ai thao tác được.**
Đọc: `PPL_LEAVE_REQUESTS_DISPLAY` — mọi vai trò, nhưng chỉ thấy **đơn của mình** và
**đơn mình phải quyết định**.
Gửi / huỷ đơn của mình: `PPL_LEAVE_REQUESTS_RAISE` — **mọi vai trò**.
Duyệt / Từ chối: `PPL_LEAVE_REQUESTS_DECIDE` — **supervisor trở lên**.

**Các bước chính — gửi đơn**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Xin nghỉ** (`/leave-requests/new`). | | |
| 2 | Chọn **Loại nghỉ**, **Ngày đầu**, **Ngày cuối**, **Ghi chú**. | Kiểm tra kỹ **Ngày cuối** — đơn tính cả hai đầu. | Nhập ngày cuối là ngày đi làm lại thì đơn dài hơn thực tế một ngày. |
| 3 | Bấm gửi. Đơn nằm trong tab **Của tôi**. | | |
| 4 | Huỷ đơn khi **chưa có quyết định**: **Huỷ đơn** → **Huỷ đơn**. | Đơn đã duyệt rồi thì không huỷ được. | |

**Các bước chính — quyết định**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Mở tab **Cần quyết định** ở **Đơn xin nghỉ**. | Tab này chỉ có đơn thuộc phạm vi Đơn vị tổ chức bạn quyết định được. | |
| 2 | Bấm **Duyệt** hoặc **Từ chối**, ghi **Ghi chú**. | Ghi chú đi vào sổ và người xin nghỉ đọc được. | |
| 3 | Không quyết định cũng là một lựa chọn hợp lệ — đơn ở lại tab chờ. | | |

> **Điểm then chốt.** Người quyết định là người có quyền trên **Đơn vị tổ chức của
> Nhân viên xin nghỉ**, không phải quản lý trực tiếp trong sơ đồ tổ chức. Kiểm tra
> phạm vi khi thấy "không có gì cần quyết định".

---

## Đơn giá giờ

**Việc này để làm gì.** Một giờ công tốn bao nhiêu. Danh mục dùng chung cho mọi
Nhà máy, và là căn cứ tính các số **Chi phí** trên bảng phân cấp.

**Ai thao tác được.** Chỉ quản trị viên: `PPL_COST_RATES_MAINTAIN`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm đơn giá giờ**. | | |
| 2 | Chọn **Phạm vi** (Nhà máy / Đơn vị tổ chức / Tài sản / trung tâm chi phí) và **Loại đơn giá**. | **Phạm vi và loại không sửa được sau khi lưu.** | Muốn đổi thì thêm đơn giá cho phạm vi mới — Nền tảng báo rõ điều này trong hộp thoại. |
| 3 | Điền **Số tiền mỗi giờ**, **Tiền tệ**, **Hệ số** (1,5 cho giờ làm thêm gấp rưỡi), **Có hiệu lực từ**. | **Hệ số** là số nhân, không phải phần trăm. | `1,5` = gấp rưỡi; `150` sẽ ra số tiền gấp 150 lần. |
| 4 | Để **Áp dụng đến** trống nếu đây là đơn giá **hiện hành**. | Đặt ngày kết thúc thì đơn giá đóng **vào ngày đó**, không tính ngày ấy. | |
| 5 | Đổi giá: bấm **Thay thế** trên đơn giá cũ. | Đơn giá cũ **bị đóng**, không bị ghi đè. | |

> **Điểm then chốt quan trọng nhất.** **Đơn giá không bao giờ bị ghi đè.** Chi phí
> đã báo cho tháng trước giữ nguyên con số của tháng trước.

> **Vì sao.** Nếu sửa giá cũ, mọi báo cáo chi phí quá khứ sẽ đổi theo — và báo cáo
> đã gửi cho quản lý thành sai.

---

## Chi phí chuẩn sản phẩm

**Việc này để làm gì.** Một đơn vị sản phẩm tốn bao nhiêu — căn cứ tính hàng lỗi và
hàng làm lại.

**Ai thao tác được.** Chỉ quản trị viên: `PPL_PRODUCT_COSTS_MAINTAIN`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm chi phí chuẩn**, chọn **Sản phẩm**. | **Sản phẩm của một chi phí không sửa được** — ghi chi phí cho Sản phẩm kia thay vì sửa. | |
| 2 | Điền **Chi phí chuẩn, mỗi đơn vị**, **Tiền tệ**, **Có hiệu lực từ**. | | |
| 3 | Đổi giá: **Thay thế**. | Chi phí cũ **đóng**, chi phí mới mở — cùng luật với Đơn giá giờ. | |

**Điểm then chốt.** Chưa đặt chi phí thì **hàng lỗi và làm lại không được tính
giá** — số tiền hiện là 0, không phải "miễn phí".

---

## Bảng tóm tắt phần Nhân sự

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem Danh bạ, hồ sơ, giờ đã làm | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Xem Chức danh, Kỹ năng, Đơn vị tổ chức | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Xem Đào tạo, Đơn xin nghỉ (của mình) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Lưu và đổi **Chữ ký của tôi** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Gửi / huỷ **đơn xin nghỉ của mình** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Tự xác nhận **đào tạo của mình** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Duyệt / Từ chối đơn xin nghỉ | · | · | ✓ | ✓ | ✓ | ✓ |
| Tạo bản ghi Đào tạo, thêm học viên, gửi | · | · | ✓ | ✓ | ✓ | ✓ |
| Mở và xác nhận **Bảng chấm công** | · | · | ✓ | ✓ | ✓ | ✓ |
| Thêm Nhân viên, sửa hồ sơ, phân công, cho rời | · | · | · | · | · | ✓ |
| Thêm/sửa Chức danh, Kỹ năng, Đơn vị tổ chức | · | · | · | · | · | ✓ |
| Ghi nhận kỹ năng cho một người | · | · | · | · | · | ✓ |
| Đơn giá giờ, Chi phí chuẩn sản phẩm | · | · | · | · | · | ✓ |

(✓ = theo mã quyền ở từng mục. Ghi còn cần phạm vi Đơn vị tổ chức — xem
[README §1](README.md#1-sáu-vai-trò-và-cách-đọc-phần-ai-thao-tác-được).)
