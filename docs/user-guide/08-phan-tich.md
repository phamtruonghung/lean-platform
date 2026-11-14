# 08 · Phân tích

Nhóm **Phân tích** trả lời "nhà máy đang chạy thế nào" bằng **số liệu đã có sẵn trong
Nền tảng**, không phải bằng cách nhập thêm.

Có một điều phải nói trước, vì nó giải thích gần hết các câu hỏi về nhóm này: **KPI
sống trong một cơ sở dữ liệu thứ hai** (ADR-0055). Danh mục KPI, Mục tiêu và bản Đánh
giá là dữ liệu của chuyền MTU, tách khỏi dữ liệu vận hành hằng ngày. Vì vậy một KPI
chưa có trong danh mục thì **không** hiện trên Bảng phân cấp, dù công việc đã được ghi
đủ.

---

## Bảng phân cấp

**Việc này để làm gì.** Những số liệu mà công việc của Nhà máy này tạo ra, báo cáo
theo **năm Trụ cột**.

**Ai thao tác được.** `INS_TIER_BOARD_DISPLAY` — **mọi vai trò**. Màn hình chỉ đọc.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy**, **Kỳ**, **Ngày**. | **Kỳ** là độ dài thời gian mà KPI được đo — ngày, tuần, tháng hoặc năm. Chọn Kỳ mà KPI không có Mục tiêu thì ô hiện **Không có mục tiêu**. | |
| 2 | Chọn **Đơn vị tổ chức** (mặc định **Tất cả đơn vị**). | Thu hẹp đọc **số liệu của mọi thứ bên dưới** đơn vị đó. | |
| 3 | Đọc từng **Trụ cột**, mỗi dòng có **Giá trị** và **Trạng thái**. | **Chưa có dữ liệu** ≠ **Chưa có KPI nào được định nghĩa dưới Trụ cột này**. | Một cái là chưa ai làm; cái kia là chưa ai định nghĩa. Chỉ cái thứ hai mới là việc của quản trị viên. |
| 4 | Lọc **Trạng thái** để chỉ xem cái đang đỏ. | | |

> **Điểm then chốt.** Mọi Trụ cột **luôn hiện**, kể cả trống. Một Trụ cột trống là một
> thông tin, không phải một lỗi hiển thị.

> **Vì sao.** Bỏ một Trụ cột trống đi thì không ai nhận ra nhà máy chưa đo gì dưới Trụ
> cột đó.

---

## Danh mục KPI

**Việc này để làm gì.** Các KPI của chuyền MTU, kèm **Mục tiêu đang áp dụng theo từng
kỳ** và trạng thái đánh giá hôm nay.

**Ai thao tác được.**
Đọc: `INS_KPI_CATALOGUE_DISPLAY` — supervisor, engineer, manager, quản trị viên.
Thêm KPI / đổi Mục tiêu: `INS_KPI_CATALOGUE_CHANGE` — cùng bốn vai trò đó.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy**, tìm theo **mã hoặc tiêu đề**. | | |
| 2 | Bấm **Thêm KPI**: **Mã**, **Tiêu đề**, **Chiều so sánh**, **Đơn vị**, **Số chữ số thập phân**, **Chỉ số giá trị**. | **Chiều so sánh**: `>=` là đạt khi **bằng hoặc trên** Mục tiêu; `<=` là đạt khi **bằng hoặc dưới**. | Chiều sai thì mọi bản đánh giá đảo ngược — một KPI "phế phẩm" bị chấm là đạt khi nó tăng. |
| 3 | Đọc từng dòng để thấy **Mục tiêu** đang áp dụng và **trạng thái đánh giá hôm nay**. | Một dòng có thể hiện nhiều Mục tiêu nếu mỗi kỳ một mức. | |
| 4 | Bấm vào một KPI để mở **Mục tiêu** của nó. | | |

**Điểm then chốt.** **Chiều so sánh** và **Đơn vị** được đặt lúc tạo KPI; hãy kiểm tra
lại hai trường này trước khi đặt Mục tiêu đầu tiên.

---

## Mục tiêu của một KPI

**Việc này để làm gì.** Xem KPI này được đánh giá theo mức nào **hôm nay**, từ **khi
nào**, và toàn bộ lịch sử.

**Ai thao tác được.** Đọc: `INS_KPI_CATALOGUE_DISPLAY`. Đặt mục tiêu:
`INS_KPI_CATALOGUE_CHANGE`.

**Đường dẫn.** `/kpi/:kpiId/targets`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Đang áp dụng**: mỗi kỳ một dòng `{Kỳ}: {giá trị} (từ {ngày})`. | "Hôm nay không có Mục tiêu nào đang áp dụng" là một trạng thái **hợp lệ**, và nó khác "chưa đặt Mục tiêu nào". | |
| 2 | Đổi: bấm **Đổi Mục tiêu**: **Kỳ**, **Mục tiêu**, **Hiệu lực từ**, **Ghi chú**. | **Hiệu lực từ** phải là **hôm nay hoặc muộn hơn**; Nền tảng in ra hôm nay của Nhà máy để bạn đối chiếu. | Đặt mục tiêu lùi ngày là sửa quá khứ — Nền tảng không cho. |
| 3 | Để **Mục tiêu** trống nghĩa là **từ ngày đó không có mục tiêu**. | Đây là cách **huỷ** một mục tiêu đang áp dụng, không phải "xoá". | |
| 4 | Đọc **Lịch sử** ở dưới. | | |

> **Điểm then chốt quan trọng nhất.** **Một mục tiêu không bao giờ bị sửa.** Mục sau
> **thay thế** mục trước bằng một ngày hiệu lực.

> **Vì sao.** Đánh giá của tháng trước phải vẫn đúng với mục tiêu của tháng trước.
> Sửa mục tiêu cũ là làm cho báo cáo đã nộp thành sai.

---

## Đánh giá KPI

**Việc này để làm gì.** Đánh giá từng KPI của chuyền MTU theo **Mục tiêu ngày** của
nó: **đạt**, **không đạt**, hoặc **chưa đo**.

**Ai thao tác được.**
Đọc: `INS_KPI_REVIEW_DISPLAY` — supervisor, engineer, manager, quản trị viên.
Ghi: `INS_KPI_REVIEW_RECORD` — cùng bốn vai trò.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy** và **Ngày**. | Bản đánh giá là **theo ngày**; bấm lùi ngày để đánh giá bù được. | |
| 2 | Với từng KPI, bấm **Sửa** rồi chọn **Đạt** / **Không đạt** / **Chưa đo**. | **Chưa đo** là một câu trả lời, và nó khác "không đạt". | Gộp "chưa đo" vào "không đạt" làm chỉ số trông tệ hơn thực tế và giấu mất việc thiếu dữ liệu. |
| 3 | KPI **không đạt** bắt buộc ghi **Vì sao không đạt Mục tiêu**. | Ghi chú có **độ dài tối thiểu**; màn hình đếm và báo ngay bên dưới ô (hiện có bao nhiêu ký tự). | |
| 4 | Bấm **Lưu**. | Thông báo xác nhận: **Đã lưu {n} {…} cho {ngày}**. | |

**Điểm then chốt — hay bị báo là lỗi.** Đang gõ dở mà ô **Lọc KPI** đang bật thì một
số KPI đã sửa **bị ẩn khỏi danh sách**; màn hình cảnh báo bằng một dòng riêng ("{n}
KPI đã thay đổi đang bị tìm kiếm ẩn đi").

> **Vì sao.** Thay đổi của bạn **vẫn được lưu** — nhưng bạn không nhìn thấy chúng.
> Xoá ô lọc trước khi bấm **Lưu** để chắc chắn mình thấy hết.

**Điểm then chốt thứ hai.** Chưa đặt **Mục tiêu ngày** cho một KPI thì dòng đó hiện
**Mục tiêu ngày: Không có mục tiêu** — và nó **không** bị bắt ghi lý do, vì không có
gì để trượt.

---

## Độ phủ kỹ năng

**Việc này để làm gì.** Nơi Nhà máy này **chưa đạt yêu cầu kỹ năng của chính nó** —
tức là chỗ thiếu người đủ tay nghề.

**Ai thao tác được.** `INS_SKILL_COVERAGE_DISPLAY` — **chỉ quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy**, rồi lọc theo **Đơn vị tổ chức** hoặc **kỹ năng**. | Danh sách chỉ gồm chỗ **thiếu**; "Mọi yêu cầu đều đạt" là trạng thái tốt, không phải danh sách rỗng hỏng. | |
| 2 | Đọc từng dòng: **Yêu cầu** {n} người ở bậc {m}+, **Đủ điều kiện**, **Hết hạn**, **Thiếu {n}**. | Người **hết hạn** đã có kỹ năng nhưng quá chu kỳ đánh giá lại — họ **không** tính vào "đủ điều kiện". | Đây là chỗ hai con số khác nhau hay bị đọc lẫn. |
| 3 | Bấm một dòng để xem **ai đang có kỹ năng đó** và ai hết hạn. | | |

**Điểm then chốt.** Độ phủ tính trên **bậc tối thiểu** của yêu cầu. Một người ở bậc
cao hơn vẫn tính; một người ở bậc thấp hơn thì **không**.

> **Điểm then chốt thứ hai.** Yêu cầu kỹ năng do **chính Nhà máy** đặt. Một chỗ "đủ"
> chỉ có nghĩa là đủ so với mức nhà máy tự đặt, không phải đủ so với chuẩn của ai khác.

---

## Bảng tóm tắt phần Phân tích

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem **Bảng phân cấp** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Xem **Danh mục KPI**, **Mục tiêu**, **Đánh giá KPI** | · | · | ✓ | ✓ | ✓ | ✓ |
| Thêm KPI, đổi Mục tiêu | · | · | ✓ | ✓ | ✓ | ✓ |
| Ghi bản Đánh giá KPI | · | · | ✓ | ✓ | ✓ | ✓ |
| **Độ phủ kỹ năng** | · | · | · | · | · | ✓ |

Cả bốn mã quyền của nhóm này **không** nằm trên nhóm mặc định — trừ
`INS_TIER_BOARD_DISPLAY`, thứ mà mọi vai trò đều có.
