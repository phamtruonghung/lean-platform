# 06 · An toàn

Nhóm **An toàn** có hai sổ, và người đào tạo phải phân biệt rõ ngay từ câu đầu:

- **Sự cố** — *đã xảy ra chuyện*. Có người bị thương, hoặc suýt bị.
- **Quan sát** — *đã thấy trước khi có chuyện*. Một điều kiện không an toàn, một hành
  vi nguy hiểm, ghi lại để nó không thành sự cố.

**Đây là nhóm mà mọi Tài khoản đều ghi được.** Ghi nhận sự cố, ghi nhận quan sát —
mọi vai trò. Đó là chủ ý: người đứng cạnh cái máy là người phải ghi được, không phải
người có tài khoản quản lý.

**Nhưng có một luật riêng, và nó là điểm then chốt quan trọng nhất của cả nhóm này.**
Khi ghi một sự cố mà bạn **nêu tên người bị thương, loại thương tích, hoặc bộ phận cơ
thể**, hệ thống đòi thêm **thẩm quyền An toàn** ở Đơn vị tổ chức đó. Một "suýt xảy ra"
không nêu ai bị gì thì ai cũng ghi được.

> **Vì sao.** Chẩn đoán của một người là **dữ liệu y tế**, không phải quan sát sàn.
> Một người vận hành ghi "đau lưng" cho đồng nghiệp là một chẩn đoán mà người đó
> không có thẩm quyền đưa ra.

---

## Sự cố

**Việc này để làm gì.** Đã xảy ra chuyện gì tại nhà máy, ở đâu, và nằm ở mức nào trên
thang mức độ.

**Ai thao tác được.**
Đọc: `SAF_INCIDENTS_DISPLAY` — **mọi vai trò**.
Ghi nhận: `SAF_INCIDENTS_RECORD` — **mọi vai trò**, cộng quyền ghi ở Đơn vị tổ chức.
Nêu tên người bị thương / loại thương tích / bộ phận cơ thể: `SAF_CLASSIFY` **và
thẩm quyền An toàn** ở Đơn vị tổ chức.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Ghi nhận sự cố**: **Đơn vị tổ chức**, **Xảy ra lúc**, **Mức độ**, **Mô tả**. | **Mức độ** là câu hỏi "chuyện này nặng tới đâu" — thang từ **suýt xảy ra** (không ai bị gì) lên tới **thương tích mất ngày làm**. | |
| 2 | Nếu có người bị thương, mở phần **Phân loại thương tích** (xem mục dưới). | Phần này **cần thẩm quyền An toàn**. Bỏ trống vẫn ghi được sự cố — chỉ là chưa phân loại. | |
| 3 | Bấm ghi nhận. | | |
| 4 | Lọc danh sách theo **Đơn vị tổ chức**, **Mức độ**, **Trạng thái**, **Từ ngày / Đến ngày**. | | |

**Điểm then chốt.** Ghi nhận lúc **phát hiện**, không phải lúc điền xong giấy tờ.
Một sự cố ghi sau ba ngày là một sự cố mà thống kê sẽ xếp vào tuần sau.

---

## Chi tiết Sự cố an toàn

**Việc này để làm gì.** Điều tra và đóng một sự cố: nó nặng tới đâu, ai phụ trách,
hạn điều tra là khi nào, và đã làm gì.

**Ai thao tác được.** Đọc `SAF_INCIDENTS_DISPLAY`; các nút ghi theo bảng dưới.

**Đường dẫn.** `/safety/incidents/:id`.

**Mục "Có thể làm gì" — đúng mã quyền máy chủ hỏi:**

| Nút | Cần quyền | Dùng khi |
| --- | --- | --- |
| **Đặt hạn điều tra** | `SAF_INCIDENTS_RECORD` | Giao hạn cho người điều tra |
| **Chuyển trạng thái** | `SAF_INCIDENTS_RECORD` | Đi tiếp trên thang: mới → đang điều tra → đã đóng |
| **Phân loại thương tích** | `SAF_CLASSIFY` **+ thẩm quyền An toàn** | Nêu tên người bị thương, loại thương tích, bộ phận cơ thể |
| **Sửa mức độ** | `SAF_INCIDENTS_RECORD` | Điều tra thấy nặng/nhẹ hơn lúc ghi |
| **Ghi nhận số ngày** | `SAF_INCIDENTS_RECORD` | Số ngày mất làm việc — căn cứ chỉ số SAF-LTIFR |
| **Đóng sự cố** | `SAF_INCIDENTS_RECORD` | Đã điều tra xong |
| **Nêu một Concern** | `ACT_RAISE` | Cần điều tra nguyên nhân gốc |

**Điểm then chốt về **Sửa mức độ**.** Nâng lên và hạ xuống **đều** dùng
`SAF_INCIDENTS_RECORD` ở nhóm An toàn — khác với Chất lượng, nơi hạ mức độ là một
quyết định riêng. Đừng dạy chung hai nhóm.

> **Vì sao lại khác?** Mức độ một sự cố là phán đoán điều tra; việc quyết định điều gì
> xảy ra với **sản phẩm** là quyết định kinh doanh. Hai câu hỏi khác nhau, hai luật
> khác nhau.

---

## Phân loại thương tích

**Việc này để làm gì.** Ghi người bị thương, loại thương tích, bộ phận cơ thể, và số
ngày mất làm việc.

**Ai thao tác được.** `SAF_CLASSIFY` **và thẩm quyền An toàn** ở Đơn vị tổ chức của
sự cố.

**Đường dẫn.** `/safety/incidents/:id/classify`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhân viên bị thương**. | | |
| 2 | Chọn **Loại thương tích** và **Bộ phận cơ thể** trong danh mục. | Danh mục do quản trị viên quản lý (xem hai mục cuối). | |
| 3 | Ghi **số ngày mất làm việc** nếu có. | | |
| 4 | Bấm ghi nhận. | | |

**Điểm then chốt.** Không có **thẩm quyền An toàn** thì nút này không mở được, dù bạn
ghi được sự cố. Nếu bạn cần phân loại thương tích, đề nghị quản trị viên cấp thẩm
quyền An toàn ở **Tài khoản → Thẩm quyền An toàn** cho đơn vị của bạn.

---

## Sửa mức độ và Ghi nhận số ngày

**Ai thao tác được.** `SAF_INCIDENTS_RECORD`.

**Đường dẫn.** `/safety/incidents/:id/severity`, `/safety/incidents/:id/days`.

| Bước | Điểm then chốt | Vì sao |
| --- | --- | --- |
| **Sửa mức độ** | Đổi lên hoặc xuống trên thang mức độ | Thang này nuôi chỉ số **SAF-TRIR** và **SAF-LTIFR** |
| **Ghi nhận số ngày** | Số ngày mất làm việc, tính từ ngày bị thương | Chỉ số SAF-LTIFR cộng dồn **12 tháng trượt**, và không có số liệu cho tới khi được xác nhận |

> **Điểm then chốt.** Số ngày **chỉ tăng** — người bị thương nghỉ thêm thì ghi thêm.
> Ghi 0 nghĩa là "đã xác nhận không mất ngày nào", không phải "chưa biết".

---

## Đóng sự cố và Nêu Concern

**Ai thao tác được.** `SAF_INCIDENTS_RECORD`; nêu Concern cần `ACT_RAISE`.

**Đường dẫn.** `/safety/incidents/:id/close`, `/safety/incidents/:id/raise-concern`.

| Bước | Điểm then chốt | Vì sao |
| --- | --- | --- |
| **Đóng sự cố** | Ghi **kết luận điều tra** | Sự cố đã đóng vẫn nằm trong sổ — không bị xoá |
| **Nêu một Concern** | Concern **rơi vào Đơn vị tổ chức của sự cố**, không phải đơn vị của bạn | Vấn đề được giải quyết ở nơi nó xảy ra |

---

## Quan sát

**Việc này để làm gì.** Những gì được thấy **trước khi** có chuyện xảy ra, xếp từ
nặng nhất theo hậu quả xấu nhất có thể hình dung được.

**Ai thao tác được.**
Đọc: `SAF_OBSERVATIONS_DISPLAY` — **mọi vai trò**.
Ghi nhận: `SAF_OBSERVATIONS_RECORD` — **mọi vai trò**, cộng quyền ghi ở Đơn vị tổ chức.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Ghi nhận quan sát**: **Đơn vị tổ chức**, **Quan sát lúc**, **Loại quan sát** (điều kiện không an toàn / hành vi không an toàn / việc làm tốt), **Mức độ**, **Mô tả**. | **Mức độ** ở đây là **hậu quả xấu nhất có thể** — không phải hậu quả đã xảy ra. | Một quan sát "chưa ai bị gì" vẫn có thể là mức nặng nhất, và đó chính là giá trị của nó. |
| 2 | Ghi nhận **ai đã quan sát** và ở đâu nếu khác nơi ghi. | | |
| 3 | Lọc theo **Đơn vị tổ chức**, **Mức độ**, **Loại**, **Trạng thái**, **Từ ngày / Đến ngày**. | | |

**Điểm then chốt quan trọng nhất.** Quan sát **không phải** là chỉ trích cá nhân.
Loại **hành vi không an toàn** nói về **hành vi**, và ghi nó ra là cách duy nhất để
nó không thành sự cố.

---

## Chi tiết Quan sát an toàn

**Việc này để làm gì.** Đóng một quan sát sau khi đã xử lý điều kiện/hành vi đó.

**Ai thao tác được.** Đọc `SAF_OBSERVATIONS_DISPLAY`; ghi `SAF_OBSERVATIONS_RECORD`.

**Đường dẫn.** `/safety/observations/:id`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Mô tả** và **hậu quả xấu nhất có thể**. | | |
| 2 | Nếu đáng làm một việc: **Nêu một Hành động** (xem mục dưới). | | |
| 3 | **Đóng quan sát**, ghi **đã làm gì**. | Quan sát đã đóng vẫn nằm trong sổ. | |

---

## Nêu Hành động từ một quan sát

**Ai thao tác được.** `SAF_OBSERVATIONS_RECORD` **và** `ACT_RAISE`.

**Đường dẫn.** `/safety/observations/:id/raise-action`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Ghi **Nội dung** và **Mô tả** của Concern. | Concern rơi vào **Đơn vị tổ chức của quan sát**. | |
| 2 | Chọn **người phụ trách** và **hạn** nếu biết. | | |
| 3 | Bấm nêu. | Bạn được đưa sang Nhật ký hành động với Concern vừa tạo. | |

**Điểm then chốt.** Nêu Hành động **không đóng** quan sát. Đóng quan sát sau khi đã
nêu — nếu không, sổ an toàn còn một việc mở mãi.

---

## Loại thương tích

**Việc này để làm gì.** Danh mục chẩn đoán dùng khi phân loại thương tích.

**Ai thao tác được.** Chỉ quản trị viên: `SAF_INJURY_TYPES_MAINTAIN` (đọc và ghi cùng
một mã).

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Thêm loại thương tích**: **Mã**, **Tên**, **mức độ khởi điểm**. | | |
| 2 | Sửa / ngừng dùng: **Điều chỉnh**. | Danh mục dùng chung cho mọi Nhà máy. | |

---

## Bộ phận cơ thể

**Việc này để làm gì.** Danh mục bộ phận cơ thể dùng khi phân loại thương tích.

**Ai thao tác được.** Chỉ quản trị viên: `SAF_BODY_PARTS_MAINTAIN`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Thêm bộ phận cơ thể**: **Mã**, **Tên**. | | |
| 2 | Sửa / ngừng dùng: **Điều chỉnh**. | | |

> **Điểm then chốt cho người đào tạo.** Hai danh mục này là **dữ liệu y tế** ở dạng
> chuẩn hoá. Chỉ quản trị viên sửa, vì một bộ phận cơ thể thêm sai sẽ làm mọi báo cáo
> an toàn đọc sai.

---

## Bảng tóm tắt phần An toàn

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem sổ Sự cố, sổ Quan sát | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ghi nhận sự cố (không nêu người bị thương) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ghi nhận quan sát | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Sửa mức độ, số ngày, đóng sự cố | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Đóng quan sát | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Nêu Concern / Hành động từ sự cố, quan sát | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Phân loại thương tích** (người bị thương, loại, bộ phận) | **cần thẩm quyền An toàn** | | | | | |
| **Danh mục** Loại thương tích, Bộ phận cơ thể | · | · | · | · | · | ✓ |

**Thẩm quyền An toàn** không phải một vai trò — quản trị viên cấp nó theo **Đơn vị tổ
chức** trong màn hình **Tài khoản**. Một người vận hành **có thể** được cấp; một quản
lý có thể **không**.
