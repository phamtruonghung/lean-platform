# 05 · Chất lượng

Nhóm **Chất lượng** ghi lại cái không đạt chuẩn và điều gì đã làm với nó. Có **hai
cửa vào** cùng một việc, và người đào tạo phải phân biệt rõ:

- **Sản phẩm không phù hợp** — phát hiện **bên trong** nhà máy, ở một điểm phát hiện.
- **NCR nhà cung cấp** — phát hiện ở khâu **nhận hàng**, hàng về sai.

Và hai cửa **từ phía khách hàng**: **Khiếu nại khách hàng** (khách báo) — rồi từ đó
mới sinh ra một Sản phẩm không phù hợp.

**Điều đáng nói nhất về quyền ở nhóm này.** Bốn danh mục (Sản phẩm, Mã lỗi, Khách
hàng, Nhà cung cấp) là **chỉ quản trị viên**. Nhưng **ghi nhận** và **xử lý** sản
phẩm không phù hợp, ghi nhận khiếu nại, ghi nhận NCR thì **mọi vai trò** làm được —
vì đó là việc của sàn, và một người vận hành phát hiện hàng lỗi phải ghi được ngay.

---

## Sản phẩm

**Việc này để làm gì.** Nhà máy sản xuất gì, và mỗi Sản phẩm được đo bằng gì.

**Ai thao tác được.**
Đọc: `QLT_PRODUCTS_DISPLAY` — mọi vai trò.
Ghi: `QLT_PRODUCTS_CHANGE` — **chỉ quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm Sản phẩm**: **Mã**, **Tên**, **Đơn vị đo**. | **Đơn vị đo** là đơn vị mọi số lượng không phù hợp được đếm bằng. | Đổi đơn vị đo của một Sản phẩm đã có bản ghi là việc phải làm bằng Sản phẩm mới, không sửa. |
| 2 | Sửa: **Điều chỉnh**. Ngừng dùng: bỏ **Đang làm** trong hộp thoại sửa. | | |

**Điểm then chốt.** Danh mục dùng chung cho **mọi** Nhà máy. Thêm một Sản phẩm ở đây
là thêm cho toàn Nền tảng.

---

## Mã lỗi

**Việc này để làm gì.** Các kiểu sai hỏng, mỗi mã có **mức độ khởi điểm** riêng.

**Ai thao tác được.**
Đọc: `QLT_DEFECT_CODES_DISPLAY` — mọi vai trò.
Ghi: `QLT_DEFECT_CODES_CHANGE` — **chỉ quản trị viên**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm Mã lỗi**: **Mã**, **Tên**, **mức độ bắt đầu**, và **Thuộc {mã cha}** nếu là mã con. | Mã con **kế thừa** ngữ cảnh của mã cha; **Cấp cao nhất** là mã gốc. | Cây mã lỗi quyết định báo cáo Pareto đọc được hay không. |
| 2 | Sửa: **Điều chỉnh**. | | |

**Điểm then chốt.** **Mức độ bắt đầu** của mã là mức độ mà một bản ghi mới **mặc
định** nhận. Người ghi nhận vẫn **sửa được** mức độ trên bản ghi của mình — nhưng
sửa lên thì cần thẩm quyền (xem **Chi tiết Sản phẩm không phù hợp**).

---

## Sản phẩm không phù hợp

**Việc này để làm gì.** Những gì không đạt chuẩn, phát hiện ở đâu, và số lượng bao nhiêu.

**Ai thao tác được.**
Đọc: `QLT_NONCONFORMANCES_DISPLAY` — mọi vai trò.
Ghi nhận: `QLT_NONCONFORMANCES_RECORD` — **mọi vai trò**.
Xử lý sản phẩm (nhượng bộ / làm lại / phế): `QLT_NONCONFORMANCES_DISPOSE` — **mọi
vai trò**, nhưng cần **thẩm quyền Chất lượng** ở Đơn vị tổ chức của bản ghi.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Lọc theo **Đơn vị tổ chức**, **Trạng thái**, **Mức độ**, **Mã lỗi**, **Sản phẩm**, **Phát hiện từ/đến ngày**. | Bộ lọc ngày là **ngày phát hiện**, không phải ngày ghi nhận. | |
| 2 | Bấm **Ghi nhận không phù hợp**: **Sản phẩm**, **Mã lỗi**, **Số lượng**, **Điểm phát hiện**, **Đơn vị tổ chức ghi nhận cho**, **Tham chiếu lô**. | **Điểm phát hiện** là câu hỏi "lỗi bị bắt ở đâu" — đó là thứ dùng để biết bước nào đã chặn được. | |
| 3 | Bấm một dòng để mở **Chi tiết**. | | |
| 4 | Xử lý số lượng: xem **Ghi nhận phương án xử lý** bên dưới. | Bản ghi **tự đóng** khi **toàn bộ** số lượng đã có phương án xử lý. | |

**Điểm then chốt quan trọng nhất.** **Số lượng bị ảnh hưởng không bao giờ giảm.**
Phân loại có thể phát hiện nhiều hơn con số ban đầu, nên chỉ **tăng** được
(**Tăng số lượng**), và mọi thay đổi đều được **giữ trong lịch sử số lượng**.

> **Vì sao.** Cho phép giảm số lượng là cho phép một người làm nhỏ con số trên báo
> cáo chất lượng. Lịch sử để mọi thay đổi có tên người làm.

---

## Chi tiết Sản phẩm không phù hợp

**Việc này để làm gì.** Đọc toàn bộ một bản ghi và chọn việc phải làm với số hàng đó.

**Ai thao tác được.** Đọc `QLT_NONCONFORMANCES_DISPLAY`; mỗi nút ghi theo bảng dưới.

**Đường dẫn.** `/non-conformances/:id`.

**Mục "Có thể làm gì" — nói đúng từng nút, đúng mã quyền mà máy chủ hỏi:**

| Nút | Cần quyền | Dùng khi |
| --- | --- | --- |
| **Tăng số lượng** | `QLT_NONCONFORMANCES_RECORD` + quyền sửa ở Đơn vị tổ chức | Phân loại phát hiện thêm hàng lỗi cùng lô |
| **Nâng mức độ hoặc ngăn chặn** | `QLT_NONCONFORMANCES_RECORD` + quyền sửa ở Đơn vị tổ chức | Đổi mức độ lên, hoặc ghi biện pháp ngăn chặn tức thời |
| **Ghi nhận phương án xử lý** | `QLT_NONCONFORMANCES_RECORD` + quyền sửa ở Đơn vị tổ chức | Nhượng bộ / làm lại / phế một phần số lượng |
| **Cho phép nhượng bộ** | `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | Chấp nhận bán/phát hàng lỗi có điều kiện |
| **Hạ mức độ** | `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | Đánh giá lại thấy nhẹ hơn |
| **Mở lại** | `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | Bản ghi đã đóng nhưng còn việc |
| **Huỷ vì ghi nhầm** | `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | Ghi nhầm hoàn toàn |
| **Nêu một Concern** | `ACT_RAISE` | Vấn đề cần điều tra nguyên nhân |
| **Liên kết với một Concern** | `ACT_CHANGE` | Vấn đề đã có Concern từ trước |

> **Điểm then chốt về quyền — nói chính xác câu này.** `QLT_NONCONFORMANCES_DISPOSE`
> **không** phải quyền "xử lý sản phẩm" nói chung. Bốn việc cần nó là bốn **quyết
> định**: nhượng bộ, hạ mức độ, mở lại, huỷ. Còn **ghi nhận phương án xử lý** cho
> một phần số lượng chỉ cần `QLT_NONCONFORMANCES_RECORD` — máy chủ coi đó là việc
> ghi sổ, không phải quyết định.

> **Vì sao.** Nếu ghi phương án xử lý cũng đòi thẩm quyền Chất lượng, một người vận
> hành đứng cạnh 100 cái hàng lỗi không tự ghi được "40 cái này phế" — và con số
> trên sổ chất lượng sẽ do người không nhìn thấy hàng ghi.

> **Một chỗ lệch đáng biết.** Nhãn của `QLT_NONCONFORMANCES_DISPOSE` trong danh mục
> quyền đọc là "Concede, rework or scrap nonconforming product" — rộng hơn việc mà
> mã này thật sự chặn. Theo đúng mã nguồn thì **làm lại / phế** đi qua quyền ghi
> thường, còn **nhượng bộ** mới là quyết định. Tài liệu này ghi theo mã nguồn.

**Điểm then chốt về nguyên nhân.** Bản ghi này xử lý **sản phẩm**. Vấn đề **phía
sau** được giải quyết trong **Nhật ký hành động**, dưới dạng **Concern** — và một
vấn đề xuất hiện nhiều lần vẫn chỉ là **một** Concern.

---

## Ghi nhận phương án xử lý

**Ai thao tác được.** `QLT_NONCONFORMANCES_RECORD` **và** quyền sửa ở Đơn vị tổ
chức của bản ghi. (Không cần thẩm quyền Chất lượng — xem bảng ở trên.)

**Đường dẫn.** `/non-conformances/:id/disposition`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **phương án** (nhượng bộ / làm lại / phế) và **số lượng**. | Xử lý **theo từng phần**: 100 cái lỗi có thể chia 60 làm lại + 40 phế. | |
| 2 | Ghi **số phút làm lại** nếu chọn làm lại. | Số phút này là căn cứ tính chi phí làm lại, dùng **Chi phí chuẩn sản phẩm**. | |
| 3 | Bấm ghi nhận. | Dòng **{đã xử lý}/{tổng} {đơn vị}** ở chi tiết cho biết còn lại bao nhiêu. | |

**Điểm then chốt.** Bản ghi **tự đóng** khi **toàn bộ** số lượng đã có phương án.
Còn 1 cái chưa quyết định là bản ghi còn mở.

---

## Cho phép nhượng bộ

**Ai thao tác được.** `QLT_NONCONFORMANCES_DISPOSE`. Đường dẫn
`/non-conformances/:id/concession`.

Dùng khi hàng **không đúng chuẩn nhưng vẫn bán/phát được** có điều kiện. Ghi rõ điều
kiện — đó là thứ khách hàng và kiểm tra sau này đọc.

---

## Hạ mức độ

**Ai thao tác được.** `QLT_NONCONFORMANCES_DISPOSE`. Đường dẫn
`/non-conformances/:id/lower-severity`.

Hạ mức độ là **quyết định về sản phẩm**, nên nó cần thẩm quyền Chất lượng, không chỉ
quyền ghi bản ghi.

---

## Mở lại và Huỷ vì ghi nhầm

**Ai thao tác được.** `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng ở
Đơn vị tổ chức. Đường dẫn `/non-conformances/:id/reopen`,
`/non-conformances/:id/cancel`.

| Nút | Dùng khi | Điểm then chốt |
| --- | --- | --- |
| **Mở lại** | Bản ghi đã đóng nhưng còn việc | Số lượng và phương án đã ghi **giữ nguyên** |
| **Huỷ vì ghi nhầm** | Ghi hoàn toàn sai | Bản ghi **vẫn nằm trong sổ** ở trạng thái đã huỷ, có lý do |

Cả hai đều là **quyết định trên sổ chất lượng**, nên chúng đi qua quyền xử lý chứ
không đi qua quyền ghi.

---

## Nêu hoặc Liên kết một Concern

**Ai thao tác được.** Nêu: `ACT_RAISE`. Liên kết: `ACT_CHANGE`.
Đường dẫn `/non-conformances/:id/raise-concern`, `/non-conformances/:id/link-concern`.

| Bước | Điểm then chốt | Vì sao |
| --- | --- | --- |
| **Nêu một Concern** | Tạo Concern mới và **liên kết** nó với bản ghi này | Vấn đề mới, chưa từng có |
| **Liên kết với một Concern** | Chọn Concern **đã có** | Vấn đề lặp lại — **luôn dùng cái này** khi đã có Concern |

> **Điểm then chốt.** Concern mới **rơi vào Đơn vị tổ chức của bản ghi không phù
> hợp**, không phải đơn vị của bạn — vấn đề được giải quyết ở nơi nó xảy ra. Bạn
> cũng không chọn được đơn vị khác trong hộp thoại này.

> **Điểm then chốt thứ hai.** Trước khi nêu, hãy tìm trong **Nhật ký hành động**
> xem vấn đề này đã có Concern chưa. Nêu trùng là điều làm hỏng thống kê hành động.

---

## Khách hàng

**Việc này để làm gì.** Khách hàng của nhà máy — để khiếu nại có người thuộc về và
phản hồi có nơi gửi tới.

**Ai thao tác được.**
Đọc: `QLT_CUSTOMERS_DISPLAY` — mọi vai trò.
Ghi: `QLT_CUSTOMERS_CHANGE` — **chỉ quản trị viên**.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Thêm Khách hàng**: **Mã**, **Tên**. | Danh sách dùng chung cho mọi Nhà máy. | |
| 2 | Sửa: **Điều chỉnh**. | | |

---

## Khiếu nại khách hàng

**Việc này để làm gì.** Khách đã khiếu nại gì, và sản phẩm bị khiếu nại **có đang
được kiểm soát hay không**.

**Ai thao tác được.**
Đọc: `QLT_COMPLAINTS_DISPLAY` — mọi vai trò.
Ghi nhận: `QLT_COMPLAINTS_RECORD` — **mọi vai trò**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Ghi nhận khiếu nại**: **Khách hàng**, **Sản phẩm**, **Mã lỗi**, **Loại** (khiếu nại thường / **Yêu cầu bảo hành**), **Đơn vị tổ chức sẽ trả lời**. | **Đơn vị tổ chức trả lời** quyết định **ai** thao tác được trên khiếu nại này. | Đây là trường hay bị bỏ qua nhất. |
| 2 | Mở khiếu nại để xử lý (xem **Chi tiết Khiếu nại**). | | |

---

## Chi tiết Khiếu nại

**Ai thao tác được.** Đọc `QLT_COMPLAINTS_DISPLAY`; ghi `QLT_COMPLAINTS_RECORD`.

**Đường dẫn.** `/complaints/:id`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Sản phẩm mà khiếu nại này nói tới**. | | |
| 2 | **Ghi nhận không phù hợp** từ khiếu nại (cần `QLT_NONCONFORMANCES_RECORD`), **hoặc** **Liên kết một bản đã có** cho cùng Sản phẩm (cần `QLT_COMPLAINTS_RECORD`). | Khiếu nại do khách phát hiện, nên nó là **nơi mọi việc bắt đầu** — nhưng bản ghi kiểm soát hàng thì nằm ở Sổ không phù hợp. | Chưa có gì kiểm soát sản phẩm bị khiếu nại là một lỗ hổng thật, và màn hình nói thẳng điều đó bằng đỏ. |
| 3 | Trả lời khách: **Phản hồi**, ghi **Phản hồi** (`QLT_COMPLAINTS_RECORD`). | | |
| 4 | Đóng khiếu nại: **Đóng bằng phản hồi**. | Phải có phản hồi trước khi đóng. | Không có phản hồi thì khách không biết đã được xử lý. |

**Điểm then chốt.** Khiếu nại **không tự** sinh Sản phẩm không phù hợp. Nếu bạn chỉ
ghi khiếu nại rồi đóng, hàng lỗi không được kiểm soát ở đâu cả.

---

## Trình chiếu

**Việc này để làm gì.** Các vấn đề chất lượng được chọn cho Nhà máy này, từng **ảnh**
một, chạy trên màn hình ở xưởng.

**Ai thao tác được.**
Đọc: `QLT_SLIDESHOW_DISPLAY` — mọi vai trò.
Chọn và sắp thứ tự: `QLT_SLIDESHOW_CHOOSE` — **mọi vai trò**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn một **Khiếu nại khách hàng** hoặc một **Sản phẩm không phù hợp** trong danh sách của nó, rồi **thêm ít nhất một ảnh** trên màn hình của vấn đề đó. | **Một trang trình chiếu cần ảnh.** Vấn đề chưa có ảnh **sẽ không hiện** trên màn hình. | Đây là lỗi phổ biến nhất: người dùng chọn vấn đề rồi thắc mắc sao màn hình trống. |
| 2 | Sắp thứ tự: **Chuyển lên trước** / **Chuyển ra sau**. | | |
| 3 | Bỏ khỏi màn hình: **Bỏ khỏi màn hình**. | | |
| 4 | Chạy: **Chạy trình chiếu**, **Tạm dừng trình chiếu**, **Trang trước** / **Trang sau**. | | |

**Điểm then chốt.** Câu trên đầu trang đếm cho bạn: "{n} đã chọn nhưng chưa có ảnh".
Đọc con số đó trước khi hỏi vì sao trình chiếu trống.

---

## Nhà cung cấp

**Việc này để làm gì.** Nhà máy mua hàng từ ai — để một lô về sai có người thuộc về
và một yêu cầu đòi bồi thường có nơi gửi tới.

**Ai thao tác được.**
Đọc: `QLT_SUPPLIERS_DISPLAY` — mọi vai trò.
Ghi: `QLT_SUPPLIERS_CHANGE` — **chỉ quản trị viên**.

**Các bước chính:** **Thêm Nhà cung cấp** (Mã, Tên) / **Điều chỉnh**. Danh sách dùng
chung cho mọi Nhà máy.

---

## NCR nhà cung cấp

**Việc này để làm gì.** Hàng về từ nhà cung cấp bị sai, và vật tư đi kèm **có đang
được kiểm soát hay không**.

**Ai thao tác được.**
Đọc: `QLT_SUPPLIER_NCRS_DISPLAY` — mọi vai trò.
Ghi nhận: `QLT_SUPPLIER_NCRS_RECORD` — **mọi vai trò**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Ghi nhận NCR nhà cung cấp**: **Nhà cung cấp**, **Sản phẩm/vật tư**, **Số lượng**, **Đơn vị tổ chức**, **Tham chiếu lô**. | **Tham chiếu lô** là thứ nối NCR với số hàng thực tế đang nằm trong kho. | Không có số lô thì không biết phải giữ lại bao nhiêu hàng. |
| 2 | Lọc theo **Nhà cung cấp**, **Đơn vị tổ chức**, **Trạng thái**. | | |

**Điểm then chốt.** NCR **không** tự tạo Sản phẩm không phù hợp, cũng như khiếu nại.
Phải làm ở bước tiếp theo, hoặc vật tư sai không được kiểm soát.

---

## Chi tiết NCR nhà cung cấp

**Ai thao tác được.** Đọc `QLT_SUPPLIER_NCRS_DISPLAY`; ghi `QLT_SUPPLIER_NCRS_RECORD`.

**Đường dẫn.** `/supplier-ncrs/:id`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Ghi nhận phương án xử lý** của nhà cung cấp (sửa **Sửa phương án xử lý** khi cần). | Đây là **phương án của nhà cung cấp**, không phải của nhà máy. | |
| 2 | Ghi **số tiền thu hồi được** nếu có. | Chi tiết hiện **Đã thu hồi {số tiền}**. | Đây là con số duy nhất cho biết NCR có mang lại tiền về hay không. |
| 3 | **Ghi nhận không phù hợp** từ NCR, **hoặc** **Liên kết một bản đã có** cho cùng lô. | | Chưa có gì kiểm soát vật tư là lỗ hổng thật. |
| 4 | **Đóng NCR** khi xong. | | |

---

## Bảng tóm tắt phần Chất lượng

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem mọi sổ Chất lượng | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ghi nhận Sản phẩm không phù hợp | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Tăng số lượng, nâng mức độ, ngăn chặn | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Ghi nhận phương án xử lý** (làm lại / phế một phần) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Nêu / liên kết một Concern | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ghi nhận Khiếu nại, NCR nhà cung cấp | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Phản hồi khách, đóng khiếu nại | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Chọn vấn đề cho Trình chiếu | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Nhượng bộ · Hạ mức độ · Mở lại · Huỷ** | **cần thẩm quyền Chất lượng** | | | | | |
| **Danh mục** Sản phẩm, Mã lỗi, Khách hàng, Nhà cung cấp | · | · | · | · | · | ✓ |

**Thẩm quyền Chất lượng** không phải một vai trò — nó là một quyền gắn với một Đơn
vị tổ chức, quản trị viên cấp trong màn hình **Tài khoản** (mục *Thẩm quyền Chất
lượng*). Một người vận hành **có thể** được cấp thẩm quyền này; một quản lý có thể
**không** được cấp.
