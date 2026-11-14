# 04 · Hành động

Nhóm **Hành động** là chỗ nhà máy trả lời câu "vì sao việc này xảy ra, và mình đã
làm gì để nó không xảy ra nữa". Có hai thứ trong đó:

- **Concern** — một vấn đề được nêu lên, mang theo các **biện pháp** và đi qua các
  **giai đoạn** cho tới khi đóng.
- **CAPA** — một cuộc **điều tra 8D** mở trên một Concern, khi có người quyết định
  vấn đề cần nguyên nhân gốc và một bản sửa giữ được kết quả.

**Quyền ở nhóm này khác hẳn ba nhóm trước.** Chín mã quyền của Hành động nằm trên
**cả sáu vai trò**, kể cả nhóm mặc định — nghĩa là **mọi Tài khoản đều nêu được
Concern, ghi biện pháp, xác minh và mở CAPA**. Đây là chủ ý: nêu ra một vấn đề không
phải là một đặc quyền. Cái chặn là **phạm vi Đơn vị tổ chức**, và với CAPA là
**thẩm quyền Chất lượng**.

---

## Nhật ký hành động

**Việc này để làm gì.** Những gì nhà máy còn nợ: đã phát hiện gì, ai phụ trách, khi
nào đến hạn. **Quá hạn xếp trước.**

**Ai thao tác được.**
Đọc: `ACT_LOG_DISPLAY` — **mọi vai trò**.
Ghi: `ACT_RAISE` (nêu), `ACT_MEASURE` (biện pháp), `ACT_VERIFY` (xác minh),
`ACT_CHANGE` (sửa liên kết, chuyển lên, huỷ) — **mọi vai trò**, trong phạm vi Đơn vị
tổ chức của mình.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Lọc theo **Đơn vị tổ chức**, **Trạng thái**, **Loại hành động**. | Thu hẹp Đơn vị tổ chức **bao gồm mọi đơn vị bên dưới** nó. | |
| 2 | Đọc danh sách: **Đến hạn**, **Quá hạn {n} ngày**, **Người phụ trách**, số **biện pháp**. | Chỉ **biện pháp khắc phục** (countermeasure) mới chữa nguyên nhân; biện pháp ngăn chặn chỉ chặn hậu quả. | Nhìn số biện pháp mà kết luận "đã xử lý" là sai — đọc loại của chúng. |
| 3 | Bật **Hiện cả việc đã đóng** để thấy lịch sử. | | |
| 4 | Bấm một dòng để mở **Chi tiết Hành động**. | | |

---

## Nêu một Concern

**Việc này để làm gì.** Ghi một vấn đề lên nhật ký, tại đúng nơi bạn gặp nó.

**Ai thao tác được.** `ACT_RAISE` — **mọi vai trò**. Ghi còn cần phạm vi Đơn vị tổ chức.

**Đường dẫn.** `/actions/new`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Đơn vị tổ chức** nơi vấn đề xảy ra. | Đây là điều quyết định **ai** thao tác được trên Concern này. | Chọn nhầm đơn vị thì người thực sự phụ trách không đóng được nó. |
| 2 | Ghi **Nội dung** (một câu) và **Mô tả**. | Nội dung là cái hiện trên nhật ký — viết sao cho người ngoài đọc hiểu. | |
| 3 | Chọn **Trụ cột** và **Đến hạn** nếu có. | | |
| 4 | Bấm gửi. | | |

> **Điểm then chốt quan trọng nhất.** **Một vấn đề lặp lại nhiều lần vẫn là MỘT
> Concern.** Lần xuất hiện thứ hai được **liên kết** vào Concern cũ, không nêu
> Concern mới.

> **Vì sao.** Nếu mỗi lần hỏng máy lại nêu một Concern riêng, cùng một nguyên nhân
> sẽ bị điều tra mười lần, và báo cáo đếm mười vấn đề khác nhau.

---

## Chi tiết Hành động

**Việc này để làm gì.** Làm thật một Concern: ghi biện pháp, chạy các giai đoạn,
liên kết cái gì với nó, và đóng nó.

**Ai thao tác được.** Đọc: `ACT_LOG_DISPLAY`. Các nút ghi: xem bảng dưới.

**Đường dẫn.** `/actions/:id`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Tình trạng hiện tại** và **Đang chờ** phần nào. | Một Hành động chờ chính hành động con của nó — đóng con trước thì cha mới đi tiếp. | |
| 2 | Ghi **Biện pháp** (`ACT_MEASURE`): **Thêm biện pháp**, chọn loại. | **Biện pháp ngăn chặn** chặn hậu quả ngay; **biện pháp khắc phục** loại bỏ nguyên nhân. Mỗi biện pháp là một Hành động riêng, có chu kỳ riêng tới bước Act. | Đây là chỗ hay lẫn nhất trong cả nhóm. |
| 3 | Liên kết cái đã xảy ra: **Sản phẩm không phù hợp**, **Sự cố**, **Quan sát**, hoặc **Nêu từ đây**. | Đây là **những lần xuất hiện** mà Concern trả lời. | |
| 4 | Hoàn thành từng giai đoạn: **Hoàn thành {giai đoạn}** (`ACT_MEASURE` / `ACT_VERIFY` theo giai đoạn). | Ghi chú khi đóng là thứ người sau đọc. | |
| 5 | Không giải quyết được ở cấp mình: **Chuyển lên trên…** (`ACT_CHANGE`). | Chuyển lên = đổi Đơn vị tổ chức phụ trách, không phải gửi tin nhắn. | |
| 6 | Cần điều tra nguyên nhân gốc: **Mở một CAPA…** (`ACT_CAPA_OPEN`). | Xem mục **Mở một CAPA**. | |
| 7 | Không còn đúng: **Huỷ hành động…** (`ACT_CHANGE`), ghi lý do. | | |

**Điểm then chốt.** **Bỏ liên kết…** gỡ một Sản phẩm không phù hợp ra khỏi Concern.
Chỉ làm khi đã liên kết nhầm.

---

## Hoàn thành một giai đoạn

**Việc này để làm gì.** Đóng một giai đoạn của Hành động (Plan, Do, Check, Act) và
để nó đi tiếp.

**Ai thao tác được.** `ACT_MEASURE` khi ghi biện pháp; `ACT_VERIFY` khi xác minh.

**Đường dẫn.** `/actions/:id/phases/:phase/complete`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Ghi **Ghi chú khi đóng**. | Không có ghi chú thì người sau chỉ thấy "đã xong", không biết xong thế nào. | |
| 2 | Bấm hoàn thành. | Hành động **không còn giai đoạn nào** thì nó đã đóng. | |

---

## Chuyển Hành động lên trên

**Ai thao tác được.** `ACT_CHANGE`. Đường dẫn `/actions/:id/escalate`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn Đơn vị tổ chức sẽ nhận, hoặc **bất kỳ ai**. | Chuyển lên là đổi **người phụ trách**, và đơn vị mới phải là đơn vị **cấp trên**. | |
| 2 | Ghi lý do. | Người nhận đọc lý do trước khi đọc vấn đề. | |

---

## Huỷ một Hành động

**Ai thao tác được.** `ACT_CHANGE`. Đường dẫn `/actions/:id/cancel`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Ghi **lý do huỷ**. | Hành động đã huỷ **vẫn nằm trong nhật ký**. | Xoá dấu một vấn đề đã nêu là điều nhật ký không cho phép. |
| 2 | Bấm huỷ. | | |

---

## Bỏ liên kết Sản phẩm không phù hợp

**Ai thao tác được.** `ACT_CHANGE`. Đường dẫn
`/actions/:id/nonconformances/:nonconformanceId/unlink`.

Chỉ dùng khi đã liên kết nhầm. Bản ghi không phù hợp **không bị xoá**, chỉ rời khỏi
Concern này.

---

## Thêm một biện pháp

**Ai thao tác được.** `ACT_MEASURE`. Đường dẫn `/actions/:id/measures/:measureType/new`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn đúng **loại** biện pháp. | **Ngăn chặn** (containment) ≠ **khắc phục** (countermeasure). | Chọn sai loại làm báo cáo CAPA thiếu D3 hoặc D5–D6. |
| 2 | Ghi nội dung, người phụ trách, hạn. | Mỗi biện pháp là **một Hành động riêng** và phải chạy hết chu kỳ của nó. | |

---

## CAPA

**Việc này để làm gì.** Danh sách các cuộc điều tra đã mở trên các Concern, và
**bước kiểm tra hiệu quả** mà mỗi cuộc đang chờ.

**Ai thao tác được.**
Đọc: `ACT_CAPA_DISPLAY` — mọi vai trò.
Mở: `ACT_CAPA_OPEN` — mọi vai trò.
Ghi nguyên nhân gốc và Why: `ACT_CAPA_VERIFY` — mọi vai trò, **và** phạm vi ghi ở
Đơn vị tổ chức của CAPA (hoặc là thành viên nhóm điều tra).
Ghi bước kiểm tra hiệu quả: `ACT_CAPA_EFFECTIVENESS` **và thẩm quyền Chất lượng**
(`quality: true`) ở Đơn vị tổ chức đó.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Lọc theo **Đơn vị tổ chức**, **Trạng thái**, và **Kiểm tra quá hạn**. | Cột **Kiểm tra quá hạn** là việc gấp nhất trong cả danh sách. | Bước kiểm tra quá hạn nghĩa là đã quá thời hạn chứng minh vấn đề không quay lại. |
| 2 | Bấm một dòng để mở **Chi tiết CAPA**. | | |

---

## Mở một CAPA

**Việc này để làm gì.** Quyết định rằng một Concern cần điều tra nguyên nhân gốc.

**Ai thao tác được.** `ACT_CAPA_OPEN` — mọi vai trò; ghi còn cần phạm vi Đơn vị tổ chức.

**Đường dẫn.** `/actions/:id/capa`, mở từ **Chi tiết Hành động**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **phương pháp điều tra** (8D) và ghi **mô tả vấn đề**. | Mô tả vấn đề là thứ cả nhóm đọc thay cho nhau — viết một lần, cho đúng. | |
| 2 | Chọn **nhóm** và **trưởng nhóm**. | **Trưởng nhóm không được tự ghi bước kiểm tra hiệu quả của CAPA mình dẫn.** | Đây là luật của máy chủ, không phải khuyến nghị: cần người thứ hai xác nhận bản sửa có giữ được. |
| 3 | Bấm mở CAPA. | | |

**Điểm then chốt.** Mở CAPA **không** đóng Concern. Concern vẫn chạy tiếp và phải
đóng **trước** khi bước kiểm tra hiệu quả đến hạn.

---

## Chi tiết CAPA

**Việc này để làm gì.** Điều tra: vì sao vấn đề xảy ra, vì sao nó không được phát
hiện, và chứng minh bản sửa giữ được.

**Ai thao tác được.** Đọc `ACT_CAPA_DISPLAY`; ghi nguyên nhân/Why cần
`ACT_CAPA_VERIFY`; ghi bước kiểm tra cần `ACT_CAPA_EFFECTIVENESS` + thẩm quyền
Chất lượng.

**Đường dẫn.** `/actions/capas/:id`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Nhóm** và **Vấn đề**. | | |
| 2 | **Biểu đồ xương cá**: ghi **nguyên nhân ứng viên** theo **hạng mục 6M**, kèm **bằng chứng**. | Ứng viên **không** phải nguyên nhân gốc — nó chỉ là cái nhóm nghi ngờ. | Ghi thẳng "nguyên nhân gốc" ở bước này làm hỏng cả cuộc điều tra. |
| 3 | Kết luận một nguyên nhân: **Kết luận** → **Đây là nguyên nhân gốc**. | Đổi ý được: **Đổi kết luận** / **Bỏ đánh dấu nguyên nhân gốc**. | |
| 4 | **Chuỗi Why** — có **hai chuỗi**, mỗi chuỗi kết thúc ở một nguyên nhân gốc đã xác nhận: *vì sao vấn đề xảy ra* và *vì sao nó không được phát hiện*. | **Thêm một Why** cho từng bước; **Chuyển lên trước / ra sau trong chuỗi** để sắp lại. | Thiếu chuỗi thứ hai là thiếu câu trả lời "tại sao QC không bắt được". |
| 5 | Đọc **Những gì Concern đã làm**: D3 (ngăn chặn), D5–D6 (khắc phục), D7 (phòng ngừa). | Đây là nơi **đọc**, không phải nơi **ghi lại** — chúng được ghi trên Concern. | Ghi trùng ở đây sẽ tạo hai bộ biện pháp khác nhau. |
| 6 | Khi Concern đã đóng: **Ghi bước kiểm tra hiệu quả**. | Người ghi **không được là trưởng nhóm**, và phải có thẩm quyền Chất lượng ở Đơn vị tổ chức. | |
| 7 | Bấm **Báo cáo** để in/xem bản 8D. | | |

> **Điều kiện đóng CAPA — nói đúng câu này khi đào tạo.** CAPA chỉ đóng khi **cả
> hai** chuỗi đều có nguyên nhân gốc đã xác nhận, **Concern đã đóng**, **và** một
> người có thẩm quyền Chất lượng **không** phải trưởng nhóm đã xác minh — **sau một
> thời gian** — rằng vấn đề không quay lại.

> **Vì sao.** Đây là điểm khác biệt giữa "đã sửa" và "sửa được". Nếu trưởng nhóm tự
> xác nhận ngay hôm sau, câu trả lời luôn là "ổn rồi" và vấn đề quay lại sau ba tuần.

---

## Chuỗi Why

**Ai thao tác được.** `ACT_CAPA_VERIFY` (+ phạm vi ghi ở Đơn vị tổ chức của CAPA,
hoặc là thành viên nhóm).

**Đường dẫn.** `/actions/capas/:id/whys/:chain/new`, `.../:whyId/edit`,
`.../:whyId/remove`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm một Why** trong đúng chuỗi. | Có **hai** chuỗi (`chain`): vì sao xảy ra, và vì sao không phát hiện. Thêm vào đúng chuỗi. | |
| 2 | Ghi câu Why và bằng chứng. | Mỗi Why phải trả lời được "vì sao" cho câu trên nó. | |
| 3 | Sửa / bỏ: **edit** / **remove** trên dòng. | | |

---

## Nguyên nhân và kết luận

**Ai thao tác được.** `ACT_CAPA_VERIFY`.

**Đường dẫn.** `/actions/capas/:id/causes/:category/new`, `.../:causeId/edit`,
`.../:causeId/verdict`, `.../:causeId/remove`, `.../:causeId/why`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Ghi một nguyên nhân** dưới một **hạng mục** (6M). | Hạng mục là cái làm báo cáo 8D đọc được — đừng dồn hết vào "Con người". | |
| 2 | Ghi **bằng chứng** cho nguyên nhân đó. | Ứng viên không có bằng chứng thì không kết luận được. | |
| 3 | **Kết luận** khi có bằng chứng; **Đổi kết luận** hoặc **Bỏ đánh dấu nguyên nhân gốc** khi cần. | Chỉ một nguyên nhân mỗi chuỗi được là nguyên nhân gốc. | |
| 4 | **Bắt đầu chuỗi từ đó** để nối nguyên nhân đã xác nhận sang chuỗi Why. | | |

---

## Ghi bước kiểm tra hiệu quả

**Ai thao tác được.** `ACT_CAPA_EFFECTIVENESS` **và** thẩm quyền Chất lượng
(`quality: true`) ở Đơn vị tổ chức của CAPA. **Trưởng nhóm CAPA không ghi được** —
máy chủ từ chối.

**Đường dẫn.** `/actions/capas/:id/effectiveness`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chờ **Concern đóng**. | Bước kiểm tra đến hạn **{n} ngày sau khi Concern đóng**; trước đó chưa có mốc. | |
| 2 | Ghi kết quả: vấn đề **có** quay lại hay **không**. | Nếu **không giữ được**, Concern **mở lại ở chu kỳ tiếp theo** — và công việc nằm trên màn hình của Concern, trong Concern đó. | |

**Điểm then chốt.** "Không giữ được" **không phải thất bại của bạn** — đó là kết quả
đúng và cần thiết. Ghi đúng để Concern mở lại chu kỳ mới.

---

## Báo cáo CAPA

**Ai thao tác được.** `ACT_CAPA_DISPLAY`. Đường dẫn `/actions/capas/:id/report`.

Bản 8D để đọc hoặc in bằng trình duyệt (Ctrl+P). Không có nút in riêng.

---

## Bảng tóm tắt phần Hành động

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem Nhật ký hành động | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Nêu Concern | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ghi biện pháp, hoàn thành giai đoạn | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Chuyển lên trên, huỷ Hành động, sửa liên kết | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Mở CAPA | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ghi nguyên nhân gốc, Why, kết luận | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Ghi bước kiểm tra hiệu quả** | **cần thẩm quyền Chất lượng** | | | | | |

Toàn bộ chín mã quyền Hành động đều nằm trên cả sáu vai trò, nên cột nào cũng ✓.
Cái thật sự chặn là **phạm vi Đơn vị tổ chức** — và với bước kiểm tra hiệu quả là
**thẩm quyền Chất lượng**, thứ được cấp riêng trong màn hình **Tài khoản**
(`orgUnitPickerQualityAuthority`).
