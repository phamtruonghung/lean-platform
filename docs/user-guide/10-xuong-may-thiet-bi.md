# 10 · Xưởng — thiết bị dùng chung trên sàn

Màn hình **Xưởng** (`/floor`) không giống mọi màn hình khác trong tài liệu này, và sự
khác biệt đó là điều đầu tiên phải dạy:

> **Thiết bị Xưởng không đăng nhập bằng Tài khoản.** Nó là một thiết bị **dùng chung**
> gắn với **một Đơn vị tổ chức** (ADR-0016). Không ai có "tài khoản thiết bị". Mỗi
> người, mỗi lần, tự nhận diện bằng **mã nhân viên và PIN** ngay trong thao tác mình
> đang làm.

> **Vì sao lại như vậy.** Phần lớn người trên sàn không có email công việc và không
> đăng nhập được (CONTEXT.md). Nếu bắt họ có Tài khoản, họ sẽ không ghi được gì — và
> việc ghi lại sẽ dồn về một người ở văn phòng.

**Thiết bị thấy gì.** Chỉ dữ liệu của **Đơn vị tổ chức nó được đăng ký**. Danh sách
Sản phẩm, Mã lỗi, Tài sản ở mọi ô chọn trên thiết bị đều là "những gì thiết bị này thấy
được".

---

## Ai cài đặt thiết bị — việc của quản trị viên, không phải của công nhân

Phần này dành cho người quản trị hệ thống; người vận hành có thể bỏ qua.

| Việc | Ai làm | Ở đâu |
| --- | --- | --- |
| Đăng ký một thiết bị Xưởng cho một Đơn vị tổ chức | Quản trị viên, hoặc người có quyền ghi bao trùm đơn vị đó | `POST /api/maintenance/floor-devices` — **credential chỉ hiện một lần** |
| Đặt PIN sàn cho một Nhân viên | `PPL_DIRECTORY_CHANGE` (quản trị viên) | `PUT /api/maintenance/floor-technician-credentials/:employeeId` — **PIN không bao giờ hiện lại** |

**Hai điểm then chốt cho người cài đặt.**

1. **Credential của thiết bị chỉ hiện một lần.** Chỉ **hash** được lưu. Mất là phải
   đăng ký lại thiết bị.
2. **PIN gắn với Nhân viên, không gắn với Tài khoản.** Đó là lý do một công nhân không
   có Tài khoản vẫn ký được việc mình đã làm.

---

## Màn hình Xưởng

**Việc này để làm gì.** Một chỗ cho người trên sàn: việc đang mở của tổ, đào tạo của
mình, và ba việc ghi nhận (không phù hợp, sự cố, quan sát) — tất cả không cần đăng nhập.

**Ai thao tác được.** Ai có **mã nhân viên + PIN** mà thiết bị này chấp nhận. Không có
mã quyền nào ở đây — quyền của thiết bị là **đơn vị nó được đăng ký**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc các làn việc: việc đang mở của tổ, **Đào tạo của tôi**, và các nút ghi nhận. | **Không có việc đang mở** là câu trả lời đúng, kèm tên tổ. | |
| 2 | Bấm **Làm mới** khi cần. | Thiết bị **không tự cập nhật**; màn hình đứng yên cho tới khi bạn làm mới. | Nếu hai người cùng nhìn một máy, người thứ hai thấy dữ liệu cũ. |
| 3 | Chọn đúng việc, rồi **nhận diện** ở hộp thoại hiện ra. | Mỗi thao tác hỏi mã nhân viên và PIN **riêng cho thao tác đó**. | Không ai đăng nhập "một lần rồi làm hết" trên thiết bị dùng chung. |

**Điểm then chốt.** Nhận diện có **thời hạn ngắn**. Để hộp thoại mở quá lâu rồi mới gửi
thì Nền tảng báo hết hạn và bạn phải nhận diện lại — đó là chủ ý, không phải lỗi.

**Nhập mã nhân viên nhanh.** Ô số nhận **quét thẻ** hoặc **máy đọc mã vạch**: chỉ cần
đưa máy đọc vào, ký tự Enter của máy đọc được hiểu là "nhập xong".

---

## Công việc trên sàn

**Việc này để làm gì.** Người thợ bắt đầu và hoàn thành Lệnh công việc ngay tại máy,
không phải về văn phòng.

**Ai thao tác được.** Người có mã nhân viên + PIN hợp lệ trên thiết bị của tổ đó.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm Lệnh công việc trong làn **Công việc trên sàn**. | Dòng hiện **mã · tên Tài sản** và **P{mức ưu tiên}**. | **P1 là khẩn cấp nhất**. |
| 2 | Bấm **Bắt đầu {số lệnh}**, rồi nhập **Mã nhân viên** và **PIN**. | Hộp thoại nói rõ: mã và PIN **xác định bạn chỉ cho thao tác này**. | |
| 3 | Xong việc: bấm **Hoàn thành {số lệnh}**, nhập mã và PIN, và ghi **Đã phát hiện gì?**. | Ô **Đã phát hiện gì** là nội dung bắt buộc trên Lệnh công việc — đừng để trống. | Không có nội dung thì lần sau không ai biết đã sửa cái gì. |

**Điểm then chốt.** Hoàn thành trên thiết bị Xưởng **không** đòi quyền trực tiếp của
người đó: quyền là của **thiết bị**, và việc **ai đã làm** được ghi lại bằng mã nhân
viên vừa nhận diện.

> **Vì sao.** Đó là toàn bộ mục đích của ADR-0016: người không có Tài khoản vẫn để lại
> tên mình trên công việc.

---

## Đào tạo của tôi

**Việc này để làm gì.** Người lao động xem việc đào tạo đang chờ mình, ngay trên sàn.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Đào tạo của tôi** (hoặc **Xem đào tạo của tôi**). | | |
| 2 | Nhập **Mã nhân viên** và **PIN**. | Hộp thoại nói: mã và PIN cho thấy **buổi đào tạo đang chờ bạn** ở thiết bị này. | Đây là một lần nhận diện, không phải đăng nhập. |
| 3 | Đọc danh sách **Đào tạo của {tên}**, rồi bấm **Xong**. | | |

**Điểm then chốt.** Thiết bị Xưởng **chỉ xem**. Câu trả lời đào tạo (xác nhận / từ chối
+ chữ ký) làm trên **Đào tạo cần xác nhận** của Tài khoản — xem
[02 · Nhân sự](02-nhan-su.md#đào-tạo).

---

## Ghi nhận không phù hợp

**Việc này để làm gì.** Người vận hành ghi một sản phẩm không phù hợp ngay tại chỗ phát
hiện, không cần Tài khoản.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Sản phẩm không phù hợp**. | | |
| 2 | Chọn **Sản phẩm**, **Mã lỗi**, ghi **Số lượng bao nhiêu**, **Số lô**, **Phát hiện lúc**, **Bạn đã thấy gì**. | Dòng dưới Mã lỗi nói **mức độ bắt đầu** — mức mặc định của mã đó. | Mức độ này dùng cho báo cáo chất lượng; ghi sai mã là sai cả mức độ. |
| 3 | Nhập **Mã nhân viên** và **PIN**. | Bản ghi được ghi nhận **là phát hiện của bạn**. | |
| 4 | Bấm **Ghi nhận**. | | |

**Điểm then chốt.** Các ô chọn (Sản phẩm, Mã lỗi, Điểm phát hiện) **chỉ có dữ liệu của
Đơn vị tổ chức mà thiết bị này được đăng ký**. Không tìm thấy Sản phẩm mình cần là dấu
hiệu thiết bị đăng ký sai đơn vị — báo quản trị viên, đừng chọn đại.

---

## Báo sự cố an toàn

**Việc này để làm gì.** Báo một sự cố ngay khi nó xảy ra, từ sàn.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Sự cố an toàn**. | | |
| 2 | Ghi **Đã xảy ra chuyện gì**, chọn **Loại sự cố**, **Mức độ**, **Xảy ra lúc**, và **Hành động tức thời** nếu đã làm gì. | Mức độ có ghi **· phải báo cáo** ở những mức mà luật đòi báo cáo. | Đây là mức cần báo lên trên ngay, không chỉ ghi sổ. |
| 3 | Nhập **Mã nhân viên** và **PIN**. | Bản ghi được ghi nhận **là báo cáo của bạn**. | |
| 4 | Bấm **Báo cáo**. | | |

> **Điểm then chốt quan trọng nhất.** Báo cáo trên thiết bị Xưởng **không nêu tên người
> bị thương, loại thương tích hay bộ phận cơ thể**. Phần đó là **phân loại thương
> tích** và cần **thẩm quyền An toàn** — làm sau, trên Tài khoản, xem
> [06 · An toàn](06-an-toan.md#phân-loại-thương-tích).

> **Vì sao.** Chẩn đoán là dữ liệu y tế. Một thiết bị dùng chung trên sàn không phải
> chỗ ghi nó, và người đứng cạnh máy không phải người đưa ra chẩn đoán.

---

## Ghi nhận quan sát an toàn

**Việc này để làm gì.** Ghi một điều kiện hoặc hành vi không an toàn **trước khi** nó
thành sự cố.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Quan sát**. | | |
| 2 | Ghi **Đã thấy gì**, chọn **Loại**, **Hạng mục**, **Mức độ tiềm ẩn**, và **Hành động đã làm** nếu có. | **Mức độ tiềm ẩn** là hậu quả xấu nhất **có thể** — không phải hậu quả đã xảy ra. | Một quan sát "chưa ai bị gì" vẫn có thể ở mức nặng nhất; đó chính là giá trị của nó. |
| 3 | Bật **Đã dùng quyền dừng việc** nếu bạn đã dừng công việc lại. | | Đây là thông tin quản lý cần thấy ngay. |
| 4 | Nhập **Mã nhân viên** và **PIN**, bấm **Ghi nhận**. | | |

---

## Bảng tóm tắt phần Xưởng

| Việc trên thiết bị | Cần gì |
| --- | --- |
| Mở màn hình Xưởng | Thiết bị đã đăng ký cho một Đơn vị tổ chức |
| Xem việc đang mở của tổ | Thiết bị đó |
| Bắt đầu / Hoàn thành Lệnh công việc | Mã nhân viên + PIN, cho từng thao tác |
| Xem **Đào tạo của tôi** | Mã nhân viên + PIN |
| Ghi nhận không phù hợp / sự cố / quan sát | Mã nhân viên + PIN |
| **Phân loại thương tích** | **Không làm được ở đây** — cần Tài khoản có thẩm quyền An toàn |
| **Trả lời đào tạo** | **Không làm được ở đây** — làm trên Tài khoản |

**Sai PIN nhiều lần.** Nền tảng khoá **Nhân viên đó** trong một khoảng chờ, không khoá
thiết bị (ADR-0047). Người khác vẫn dùng thiết bị bình thường.

> **Điểm then chốt cho người đào tạo.** Nói rõ với công nhân: **sai PIN thì chính bạn bị
> chờ, không phải cái máy**. Đừng để họ đứng thử tiếp — thời gian chờ sẽ dài ra.
