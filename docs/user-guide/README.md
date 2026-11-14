# Hướng dẫn sử dụng Nền tảng (lean-platform)

Tài liệu này viết cho **người dùng trên sàn máy** và **người đào tạo họ** — không
phải cho lập trình viên. Nó dạy cách làm từng việc một trên Nền tảng, theo hình
thức **TWI Job Instruction**: mỗi chức năng là một thẻ gồm bốn phần, đúng thứ tự
một người đào tạo sẽ nói với một người vận hành.

| Phần của thẻ | Trả lời câu hỏi |
| --- | --- |
| **Việc này để làm gì** | Một câu. Khi nào thì mở màn hình này ra. |
| **Ai thao tác được** | Vai trò nào mở được, vai trò nào ghi được — lấy từ mã quyền trong mã nguồn, không phải phỏng đoán. |
| **Các bước chính** | Làm theo thứ tự. Mỗi bước một dòng. |
| **Điểm then chốt · Vì sao** | Chỗ hay sai, và cái gì hỏng nếu sai. Đây là phần biến một danh sách bước thành một buổi đào tạo. |

Tên nút, tên trường và tên màn hình trong tài liệu là **chữ tiếng Việt đúng như
trên màn hình** (lấy từ `frontend/lib/l10n/app_vi.arb`). Nếu màn hình của bạn
đang để tiếng Anh, vào **Cài đặt → Ngôn ngữ → Tiếng Việt**.

---

## 1. Sáu vai trò, và cách đọc phần "Ai thao tác được"

Nền tảng không cấp quyền cho từng người một cách tuỳ tiện. Mỗi Tài khoản mang
**các vai trò**, mỗi vai trò mang **các mã quyền**, và mỗi nút trên màn hình
tương ứng với một mã quyền ở máy chủ. Có sáu vai trò được tạo sẵn:

| Vai trò | Mã | Ai có |
| --- | --- | --- |
| **Nhóm mặc định** | `ROLE_STANDARD` | **Mọi** Tài khoản, luôn luôn. Không ai bị bỏ. |
| **Operator** (vận hành) | `ROLE_OPERATOR` | Tài khoản có vai trò riêng là `operator` |
| **Supervisor** (giám sát) | `ROLE_SUPERVISOR` | Tài khoản có vai trò riêng là `supervisor` |
| **Engineer** (kỹ sư) | `ROLE_ENGINEER` | Tài khoản có vai trò riêng là `engineer` |
| **Manager** (quản lý) | `ROLE_MANAGER` | Tài khoản có vai trò riêng là `manager` |
| **Quản trị viên** | `ROLE_ADMIN` | Tài khoản có vai trò riêng là `admin` |

Một Tài khoản **cộng dồn**: nhóm mặc định + vai trò riêng của nó (+ vai trò nào
quản trị viên gán thêm trong màn hình **Vai trò**). Số quyền thực tế hôm nay:

| Vai trò | Số quyền | Ghi chú cho người đào tạo |
| --- | ---: | --- |
| Nhóm mặc định | 42 | Đọc mọi danh mục và sổ; nêu Yêu cầu, nêu Concern; tự trả lời đào tạo của mình; tự xin nghỉ |
| Operator | 42 | **Không thêm quyền nào** so với nhóm mặc định. Hôm nay "operator" chỉ là một cái tên |
| Supervisor | 63 | Toàn bộ màn hình Bảo trì và các thao tác ghi của chúng; xác nhận Chấm công; tạo Đào tạo; quyết định Đơn xin nghỉ; KPI |
| Engineer | 64 | Bằng Supervisor **cộng đúng một quyền**: `MTN_PARTS_CHANGE` (thêm/sửa Phụ tùng) |
| Manager | 64 | Bằng Engineer, không hơn một quyền nào |
| Quản trị viên | 84 | Tất cả. Máy chủ cho vai trò này đi qua mọi mã quyền |

> **Ba điều người đào tạo cần nói trước, vì chúng hay bị hiểu sai:**
>
> 1. **Vào được màn hình không có nghĩa là ghi được.** Quyền đọc mở cửa; quyền
>    ghi mới là cái cho phép bấm nút. Một giám sát mở **Lệnh công việc** được
>    nhưng bấm **Phân công** có thể bị từ chối nếu thiếu quyền ghi hoặc thiếu
>    quyền trên **Đơn vị tổ chức** của lệnh đó.
> 2. **Ghi còn cần phạm vi Đơn vị tổ chức.** Ngoài vai trò, mỗi thao tác ghi còn
>    phải nằm trong Đơn vị tổ chức mà Tài khoản được cấp quyền. Thiếu phạm vi thì
>    máy chủ trả lời từ chối, dù vai trò đúng.
> 3. **Đọc rộng, ghi hẹp — đây là chủ ý.** Danh bạ Nhân viên và danh sách Tài sản
>    đọc được toàn Nền tảng; chỉ thao tác ghi mới bị lọc theo Đơn vị tổ chức.

Bảng đầy đủ **84 mã quyền × 6 vai trò** ở [`90-phu-luc-ma-quyen.md`](90-phu-luc-ma-quyen.md) —
đó là nguồn để tra khi một mục trong tài liệu ghi tên mã quyền.

### Tài liệu ghi theo mã nguồn, kể cả khi mã nguồn khác tài liệu cũ

Ba chỗ trong kho mã này đang lệch nhau. Khi lệch, **mã nguồn đúng**, và tài liệu
này ghi theo mã nguồn:

1. `docs/authorization-model.md` mở đầu bằng "83 quyền"; danh mục thực tế có
   **84** (`permissions`, tới migration `1804100000000`).
2. Chính tài liệu đó mô tả Engineer là "bộ của Supervisor **cộng** quyền ghi trên
   Tài sản, Lệnh công việc, Phụ tùng, Kho và Lịch bảo trì định kỳ, cùng việc mở
   và xác minh CAPA". Sau migration `1803500000000` (Supervisor nhận bốn mã ghi
   Bảo trì) và `1803800000000` (cả sáu vai trò nhận các mã ghi Hành động), phần
   "cộng" đó chỉ còn đúng **một** mã: `MTN_PARTS_CHANGE`.
3. Operator hôm nay không mang quyền nào ngoài nhóm mặc định — hai vai trò trùng
   nhau đúng từng mã.

---

## 2. Mục lục — 44 màn hình vào từ cửa

Mỗi dòng dưới đây xuất hiện **đúng một lần**. Cột "Đọc" là mã quyền mở cửa vào;
cột "Ghi" là mã quyền của các thao tác ghi trên màn hình đó (ghi còn cần phạm vi
Đơn vị tổ chức — xem mục 1).

| Nhóm | Màn hình | Đường dẫn | Đọc | Ghi | Tài liệu |
| --- | --- | --- | --- | --- | --- |
| — | Trang chủ | `/` | *(mọi Tài khoản đã chấp nhận)* | — | [01](01-vao-cua-va-tai-khoan.md#trang-chủ) |
| — | Cài đặt | `/settings` | *(mọi Tài khoản đã chấp nhận)* | — | [01](01-vao-cua-va-tai-khoan.md#cài-đặt) |
| Nhân sự | Danh bạ | `/directory` | `PPL_DIRECTORY_DISPLAY` | `PPL_DIRECTORY_CHANGE` | [02](02-nhan-su.md#danh-bạ) |
| Nhân sự | Chức danh công việc | `/job-roles` | `PPL_JOB_ROLES_DISPLAY` | `PPL_JOB_ROLES_CHANGE` | [02](02-nhan-su.md#chức-danh-công-việc) |
| Nhân sự | Kỹ năng | `/skills` | `PPL_SKILLS_DISPLAY` | `PPL_SKILLS_CHANGE` | [02](02-nhan-su.md#kỹ-năng) |
| Nhân sự | Đơn vị tổ chức | `/org-units` | `PPL_ORG_UNITS_DISPLAY` | `PPL_ORG_UNITS_CHANGE` | [02](02-nhan-su.md#đơn-vị-tổ-chức) |
| Nhân sự | Chấm công | `/attendance` | `PPL_ATTENDANCE_DISPLAY` | `PPL_ATTENDANCE_CHANGE` | [02](02-nhan-su.md#chấm-công) |
| Nhân sự | Đào tạo | `/training` | `PPL_TRAINING_DISPLAY` | `PPL_TRAINING_CHANGE` | [02](02-nhan-su.md#đào-tạo) |
| Nhân sự | Chữ ký của tôi | `/me/signature` | `PPL_SIGNATURE_OWN` | `PPL_SIGNATURE_OWN` | [02](02-nhan-su.md#chữ-ký-của-tôi) |
| Nhân sự | Đơn xin nghỉ | `/leave-requests` | `PPL_LEAVE_REQUESTS_DISPLAY` | `PPL_LEAVE_REQUESTS_RAISE` · `PPL_LEAVE_REQUESTS_DECIDE` | [02](02-nhan-su.md#đơn-xin-nghỉ) |
| Nhân sự | Đơn giá giờ | `/cost-rates` | `PPL_COST_RATES_MAINTAIN` | `PPL_COST_RATES_MAINTAIN` | [02](02-nhan-su.md#đơn-giá-giờ) |
| Nhân sự | Chi phí chuẩn sản phẩm | `/product-costs` | `PPL_PRODUCT_COSTS_MAINTAIN` | `PPL_PRODUCT_COSTS_MAINTAIN` | [02](02-nhan-su.md#chi-phí-chuẩn-sản-phẩm) |
| Bảo trì | Tài sản | `/assets` | `MTN_ASSETS_DISPLAY` | `MTN_ASSETS_CHANGE` | [03](03-bao-tri.md#tài-sản) |
| Bảo trì | Phụ tùng | `/parts` | `MTN_PARTS_DISPLAY` | `MTN_PARTS_CHANGE` | [03](03-bao-tri.md#phụ-tùng) |
| Bảo trì | Kho | `/stores` | `MTN_STORES_DISPLAY` | `MTN_STORES_CHANGE` | [03](03-bao-tri.md#kho) |
| Bảo trì | Lệnh công việc | `/work-orders` | `MTN_WORK_ORDERS_DISPLAY` | `MTN_WORK_ORDERS_CHANGE` | [03](03-bao-tri.md#lệnh-công-việc) |
| Bảo trì | Yêu cầu của tôi | `/my-requests` | `MTN_REQUESTS_RAISE` | `MTN_REQUESTS_RAISE` | [03](03-bao-tri.md#yêu-cầu-của-tôi) |
| Bảo trì | Hàng chờ phân loại | `/requests` | `MTN_REQUESTS_TRIAGE` | `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Bảo trì | Thời gian dừng máy | `/downtime` | `MTN_DOWNTIME_DISPLAY` | `MTN_DOWNTIME_CHANGE` | [03](03-bao-tri.md#thời-gian-dừng-máy) |
| Bảo trì | Lịch bảo trì định kỳ | `/pm-schedules` | `MTN_PM_SCHEDULES_DISPLAY` | `MTN_PM_SCHEDULES_CHANGE` | [03](03-bao-tri.md#lịch-bảo-trì-định-kỳ) |
| Bảo trì | Đồng hồ đo | `/meters` | `MTN_METERS_DISPLAY` | `MTN_METERS_CHANGE` | [03](03-bao-tri.md#đồng-hồ-đo) |
| Bảo trì | Kế hoạch công việc | `/job-plans` | `MTN_JOB_PLANS_MAINTAIN` | `MTN_JOB_PLANS_MAINTAIN` | [03](03-bao-tri.md#kế-hoạch-công-việc) |
| Hành động | Nhật ký hành động | `/actions` | `ACT_LOG_DISPLAY` | `ACT_RAISE` · `ACT_MEASURE` · `ACT_VERIFY` · `ACT_CHANGE` | [04](04-hanh-dong.md#nhật-ký-hành-động) |
| Hành động | CAPA | `/actions/capas` | `ACT_CAPA_DISPLAY` | `ACT_CAPA_OPEN` · `ACT_CAPA_VERIFY` · `ACT_CAPA_EFFECTIVENESS` | [04](04-hanh-dong.md#capa) |
| Chất lượng | Sản phẩm | `/products` | `QLT_PRODUCTS_DISPLAY` | `QLT_PRODUCTS_CHANGE` | [05](05-chat-luong.md#sản-phẩm) |
| Chất lượng | Mã lỗi | `/defect-codes` | `QLT_DEFECT_CODES_DISPLAY` | `QLT_DEFECT_CODES_CHANGE` | [05](05-chat-luong.md#mã-lỗi) |
| Chất lượng | Sản phẩm không phù hợp | `/non-conformances` | `QLT_NONCONFORMANCES_DISPLAY` | `QLT_NONCONFORMANCES_RECORD` · `QLT_NONCONFORMANCES_DISPOSE` | [05](05-chat-luong.md#sản-phẩm-không-phù-hợp) |
| Chất lượng | Khách hàng | `/customers` | `QLT_CUSTOMERS_DISPLAY` | `QLT_CUSTOMERS_CHANGE` | [05](05-chat-luong.md#khách-hàng) |
| Chất lượng | Khiếu nại khách hàng | `/complaints` | `QLT_COMPLAINTS_DISPLAY` | `QLT_COMPLAINTS_RECORD` | [05](05-chat-luong.md#khiếu-nại-khách-hàng) |
| Chất lượng | Trình chiếu | `/slide-show` | `QLT_SLIDESHOW_DISPLAY` | `QLT_SLIDESHOW_CHOOSE` | [05](05-chat-luong.md#trình-chiếu) |
| Chất lượng | Nhà cung cấp | `/suppliers` | `QLT_SUPPLIERS_DISPLAY` | `QLT_SUPPLIERS_CHANGE` | [05](05-chat-luong.md#nhà-cung-cấp) |
| Chất lượng | NCR nhà cung cấp | `/supplier-ncrs` | `QLT_SUPPLIER_NCRS_DISPLAY` | `QLT_SUPPLIER_NCRS_RECORD` | [05](05-chat-luong.md#ncr-nhà-cung-cấp) |
| An toàn | Sự cố | `/safety/incidents` | `SAF_INCIDENTS_DISPLAY` | `SAF_INCIDENTS_RECORD` · `SAF_CLASSIFY` | [06](06-an-toan.md#sự-cố) |
| An toàn | Quan sát | `/safety/observations` | `SAF_OBSERVATIONS_DISPLAY` | `SAF_OBSERVATIONS_RECORD` | [06](06-an-toan.md#quan-sát) |
| An toàn | Loại thương tích | `/safety/injury-types` | `SAF_INJURY_TYPES_MAINTAIN` | `SAF_INJURY_TYPES_MAINTAIN` | [06](06-an-toan.md#loại-thương-tích) |
| An toàn | Bộ phận cơ thể | `/safety/body-parts` | `SAF_BODY_PARTS_MAINTAIN` | `SAF_BODY_PARTS_MAINTAIN` | [06](06-an-toan.md#bộ-phận-cơ-thể) |
| Sản xuất | Bàn giao ca | `/production/sections` | `PRD_HANDOVER_DISPLAY` | `PRD_HANDOVER_WRITE` · `PRD_HANDOVER_ACKNOWLEDGE` | [07](07-san-xuat.md#bàn-giao-ca) |
| Phân tích | Bảng phân cấp | `/tier-board` | `INS_TIER_BOARD_DISPLAY` | — | [08](08-phan-tich.md#bảng-phân-cấp) |
| Phân tích | Độ phủ kỹ năng | `/skill-coverage` | `INS_SKILL_COVERAGE_DISPLAY` | — | [08](08-phan-tich.md#độ-phủ-kỹ-năng) |
| Phân tích | Danh mục KPI | `/kpi` | `INS_KPI_CATALOGUE_DISPLAY` | `INS_KPI_CATALOGUE_CHANGE` | [08](08-phan-tich.md#danh-mục-kpi) |
| Phân tích | Đánh giá KPI | `/kpi/review` | `INS_KPI_REVIEW_DISPLAY` | `INS_KPI_REVIEW_RECORD` | [08](08-phan-tich.md#đánh-giá-kpi) |
| Quản trị | Phê duyệt | `/approvals` | `ADM_APPROVALS_DISPLAY` | `ADM_APPROVALS_DECIDE` | [09](09-quan-tri.md#phê-duyệt) |
| Quản trị | Tài khoản | `/accounts` | `ADM_ACCOUNTS_DISPLAY` | `ADM_ACCOUNTS_CHANGE` | [09](09-quan-tri.md#tài-khoản) |
| Quản trị | Vai trò | `/roles` | `ADM_ROLES_DISPLAY` | `ADM_ROLES_CHANGE` | [09](09-quan-tri.md#vai-trò) |

## 3. Mục lục — màn hình con (mở từ trong một màn hình ở trên)

Màn hình con không có mục riêng trên thanh điều hướng. Cửa vào của chúng là **một
Tài khoản đã được chấp nhận**; cái quyết định việc ghi trên đó là mã quyền ghi
của chức năng mẹ, và — với mọi thao tác ghi — phạm vi Đơn vị tổ chức.

| Màn hình con | Đường dẫn | Ai mở được | Tài liệu |
| --- | --- | --- | --- |
| Hồ sơ Nhân viên | `/directory/:id` (hoặc `/directory/me`) | Mọi Tài khoản | [02](02-nhan-su.md#hồ-sơ-nhân-viên) |
| Giờ đã làm của một Nhân viên | `/directory/:employeeId/work-hours` | Mọi Tài khoản | [02](02-nhan-su.md#giờ-đã-làm-của-một-nhân-viên) |
| Chấm công cần xác nhận | `/attendance/to-confirm` | Mang `PPL_ATTENDANCE_CHANGE` | [02](02-nhan-su.md#chấm-công-cần-xác-nhận) |
| Bảng chấm công một ca | `/attendance/:shiftInstanceId` | Mang `PPL_ATTENDANCE_CHANGE` **và** quyền sửa trên Đơn vị tổ chức của ca | [02](02-nhan-su.md#bảng-chấm-công-một-ca) |
| Đào tạo cần xác nhận | `/training/to-confirm` | Mọi Tài khoản | [02](02-nhan-su.md#đào-tạo) |
| Bản ghi đào tạo (chi tiết) | `/training/:id` | Mọi Tài khoản | [02](02-nhan-su.md#bản-ghi-đào-tạo-chi-tiết) |
| Biểu mẫu in của bản ghi đào tạo | `/training/:id/form` | Mọi Tài khoản | [02](02-nhan-su.md#biểu-mẫu-in-của-bản-ghi-đào-tạo) |
| Gửi đơn xin nghỉ | `/leave-requests/new` | Mang `PPL_LEAVE_REQUESTS_RAISE` | [02](02-nhan-su.md#đơn-xin-nghỉ) |
| Duyệt / Từ chối đơn xin nghỉ | một tuyến `/leave-requests/:id/$action` (`$action` là `approve` hoặc `reject`) | Mang `PPL_LEAVE_REQUESTS_DECIDE` | [02](02-nhan-su.md#đơn-xin-nghỉ) |
| Huỷ đơn xin nghỉ của mình | `/leave-requests/:id/cancel` | Mang `PPL_LEAVE_REQUESTS_RAISE` | [02](02-nhan-su.md#đơn-xin-nghỉ) |
| Tồn kho một Kho | `/stores/:id` | Mang `MTN_STORES_DISPLAY` | [03](03-bao-tri.md#kho) |
| Chi tiết Lệnh công việc | `/work-orders/:id` | Mang `MTN_WORK_ORDERS_DISPLAY` | [03](03-bao-tri.md#chi-tiết-lệnh-công-việc) |
| Tạo Lệnh công việc | `/work-orders/new` | Mang `MTN_WORK_ORDERS_CHANGE` | [03](03-bao-tri.md#lệnh-công-việc) |
| Phân công / Phân công lại | `/work-orders/:id/assign` | Mang `MTN_WORK_ORDERS_CHANGE` | [03](03-bao-tri.md#phân-công-lệnh-công-việc) |
| Hoàn thành Lệnh công việc | `/work-orders/:id/complete` | Mang `MTN_WORK_ORDERS_CHANGE` | [03](03-bao-tri.md#hoàn-thành-lệnh-công-việc) |
| Huỷ Lệnh công việc | `/work-orders/:id/cancel` | Mang `MTN_WORK_ORDERS_CHANGE` | [03](03-bao-tri.md#huỷ-lệnh-công-việc) |
| Chấp nhận một Yêu cầu | `/requests/:id/accept` | Mang `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Từ chối một Yêu cầu | `/requests/:id/decline` | Mang `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Đánh dấu Yêu cầu trùng lặp | `/requests/:id/duplicate` | Mang `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Nêu một Concern | `/actions/new` | Mang `ACT_RAISE` | [04](04-hanh-dong.md#nêu-một-concern) |
| Chi tiết Hành động | `/actions/:id` | Mang `ACT_LOG_DISPLAY` | [04](04-hanh-dong.md#chi-tiết-hành-động) |
| Hoàn thành một giai đoạn | `/actions/:id/phases/:phase/complete` | Mang `ACT_MEASURE` / `ACT_VERIFY` theo giai đoạn | [04](04-hanh-dong.md#hoàn-thành-một-giai-đoạn) |
| Chuyển Hành động lên trên | `/actions/:id/escalate` | Mang `ACT_CHANGE` | [04](04-hanh-dong.md#chuyển-hành-động-lên-trên) |
| Mở một CAPA | `/actions/:id/capa` | Mang `ACT_CAPA_OPEN` | [04](04-hanh-dong.md#mở-một-capa) |
| Huỷ một Hành động | `/actions/:id/cancel` | Mang `ACT_CHANGE` | [04](04-hanh-dong.md#huỷ-một-hành-động) |
| Bỏ liên kết Sản phẩm không phù hợp | `/actions/:id/nonconformances/:nonconformanceId/unlink` | Mang `ACT_CHANGE` | [04](04-hanh-dong.md#bỏ-liên-kết-sản-phẩm-không-phù-hợp) |
| Thêm một biện pháp | `/actions/:id/measures/:measureType/new` | Mang `ACT_MEASURE` | [04](04-hanh-dong.md#thêm-một-biện-pháp) |
| Chi tiết CAPA | `/actions/capas/:id` | Mang `ACT_CAPA_DISPLAY` | [04](04-hanh-dong.md#chi-tiết-capa) |
| Thêm / sửa / bỏ một Why | `/actions/capas/:id/whys/:chain/new`, `/actions/capas/:id/whys/:chain/:whyId/edit`, `/actions/capas/:id/whys/:chain/:whyId/remove` | Mang `ACT_CAPA_VERIFY` | [04](04-hanh-dong.md#chuỗi-why) |
| Thêm / sửa / kết luận / bỏ một nguyên nhân | `/actions/capas/:id/causes/:category/new`, `/actions/capas/:id/causes/:category/:causeId/edit`, `/actions/capas/:id/causes/:category/:causeId/verdict`, `/actions/capas/:id/causes/:category/:causeId/remove`, `/actions/capas/:id/causes/:category/:causeId/why` | Mang `ACT_CAPA_VERIFY` | [04](04-hanh-dong.md#nguyên-nhân-và-kết-luận) |
| Ghi bước kiểm tra hiệu quả | `/actions/capas/:id/effectiveness` | Mang `ACT_CAPA_EFFECTIVENESS` | [04](04-hanh-dong.md#ghi-bước-kiểm-tra-hiệu-quả) |
| Báo cáo CAPA | `/actions/capas/:id/report` | Mang `ACT_CAPA_DISPLAY` | [04](04-hanh-dong.md#báo-cáo-capa) |
| Ghi nhận Sản phẩm không phù hợp | `/non-conformances/new` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#sản-phẩm-không-phù-hợp) |
| Chi tiết Sản phẩm không phù hợp | `/non-conformances/:id` | Mang `QLT_NONCONFORMANCES_DISPLAY` | [05](05-chat-luong.md#chi-tiết-sản-phẩm-không-phù-hợp) |
| Tăng số lượng · Nâng mức độ/ngăn chặn | `/non-conformances/:id/quantity`, `/non-conformances/:id/update` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#chi-tiết-sản-phẩm-không-phù-hợp) |
| Ghi nhận phương án xử lý | `/non-conformances/:id/disposition` | Mang `QLT_NONCONFORMANCES_DISPOSE` | [05](05-chat-luong.md#ghi-nhận-phương-án-xử-lý) |
| Cho phép nhượng bộ | `/non-conformances/:id/concession` | Mang `QLT_NONCONFORMANCES_DISPOSE` | [05](05-chat-luong.md#cho-phép-nhượng-bộ) |
| Hạ mức độ | `/non-conformances/:id/lower-severity` | Mang `QLT_NONCONFORMANCES_DISPOSE` | [05](05-chat-luong.md#hạ-mức-độ) |
| Mở lại · Huỷ vì ghi nhầm | `/non-conformances/:id/reopen`, `/non-conformances/:id/cancel` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#mở-lại-và-huỷ-vì-ghi-nhầm) |
| Nêu / Liên kết một Concern | `/non-conformances/:id/raise-concern`, `/non-conformances/:id/link-concern` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#nêu-hoặc-liên-kết-một-concern) |
| Ghi nhận khiếu nại | `/complaints/new` | Mang `QLT_COMPLAINTS_RECORD` | [05](05-chat-luong.md#khiếu-nại-khách-hàng) |
| Chi tiết Khiếu nại khách hàng | `/complaints/:id` | Mang `QLT_COMPLAINTS_DISPLAY` | [05](05-chat-luong.md#chi-tiết-khiếu-nại) |
| Phản hồi · Ghi nhận/liên kết không phù hợp | `/complaints/:id/respond`, `/complaints/:id/nonconformance`, `/complaints/:id/link` | Mang `QLT_COMPLAINTS_RECORD` | [05](05-chat-luong.md#chi-tiết-khiếu-nại) |
| Ghi nhận NCR nhà cung cấp | `/supplier-ncrs/new` | Mang `QLT_SUPPLIER_NCRS_RECORD` | [05](05-chat-luong.md#ncr-nhà-cung-cấp) |
| Chi tiết NCR nhà cung cấp | `/supplier-ncrs/:id` | Mang `QLT_SUPPLIER_NCRS_DISPLAY` | [05](05-chat-luong.md#chi-tiết-ncr-nhà-cung-cấp) |
| Phương án xử lý · Ghi nhận/liên kết không phù hợp | `/supplier-ncrs/:id/disposition`, `/supplier-ncrs/:id/nonconformance`, `/supplier-ncrs/:id/link` | Mang `QLT_SUPPLIER_NCRS_RECORD` | [05](05-chat-luong.md#chi-tiết-ncr-nhà-cung-cấp) |
| Ghi nhận sự cố an toàn | `/safety/incidents/record` | Mang `SAF_INCIDENTS_RECORD` | [06](06-an-toan.md#sự-cố) |
| Chi tiết Sự cố an toàn | `/safety/incidents/:id` | Mang `SAF_INCIDENTS_DISPLAY` | [06](06-an-toan.md#chi-tiết-sự-cố-an-toàn) |
| Hạn điều tra · Chuyển trạng thái | `/safety/incidents/:id/due-date`, `/safety/incidents/:id/status` | Mang `SAF_INCIDENTS_RECORD` | [06](06-an-toan.md#chi-tiết-sự-cố-an-toàn) |
| Phân loại thương tích | `/safety/incidents/:id/classify` | Mang `SAF_CLASSIFY` | [06](06-an-toan.md#phân-loại-thương-tích) |
| Sửa mức độ · Ghi nhận số ngày | `/safety/incidents/:id/severity`, `/safety/incidents/:id/days` | Mang `SAF_INCIDENTS_RECORD` | [06](06-an-toan.md#sửa-mức-độ-và-ghi-nhận-số-ngày) |
| Đóng sự cố · Nêu Concern | `/safety/incidents/:id/close`, `/safety/incidents/:id/raise-concern` | Mang `SAF_INCIDENTS_RECORD` | [06](06-an-toan.md#đóng-sự-cố-và-nêu-concern) |
| Ghi nhận quan sát an toàn | `/safety/observations/record` | Mang `SAF_OBSERVATIONS_RECORD` | [06](06-an-toan.md#quan-sát) |
| Chi tiết Quan sát an toàn | `/safety/observations/:id` | Mang `SAF_OBSERVATIONS_DISPLAY` | [06](06-an-toan.md#chi-tiết-quan-sát-an-toàn) |
| Nêu một Hành động từ quan sát | `/safety/observations/:id/raise-action` | Mang `SAF_OBSERVATIONS_RECORD` **và** `ACT_RAISE` | [06](06-an-toan.md#nêu-hành-động-từ-một-quan-sát) |
| Bảng của một Bộ phận | `/production/sections/:orgUnitId/board` | Mang `PRD_HANDOVER_DISPLAY` | [07](07-san-xuat.md#bảng-của-một-bộ-phận) |
| Xác nhận bàn giao | `/production/sections/:orgUnitId/board/acknowledge/:handoverId` | Mang `PRD_HANDOVER_ACKNOWLEDGE` | [07](07-san-xuat.md#xác-nhận-bàn-giao) |
| Bàn giao ca của một ca | `/production/sections/:orgUnitId/handover/:shiftInstanceId` | Mang `PRD_HANDOVER_WRITE` để ghi, `PRD_HANDOVER_DISPLAY` để đọc | [07](07-san-xuat.md#bàn-giao-của-một-ca) |
| Mục tiêu của một KPI | `/kpi/:kpiId/targets` | Mang `INS_KPI_CATALOGUE_DISPLAY` | [08](08-phan-tich.md#mục-tiêu-của-một-kpi) |
| Đăng nhập | `/sign-in` | *(chưa đăng nhập)* | [01](01-vao-cua-va-tai-khoan.md#đăng-nhập) |
| Chờ phê duyệt | `/awaiting-approval` | Tài khoản đã đăng nhập nhưng chưa được chấp nhận | [01](01-vao-cua-va-tai-khoan.md#chờ-phê-duyệt) |
| Chọn mật khẩu mới (bắt buộc) | `/change-password` | Tài khoản có mật khẩu tạm thời | [01](01-vao-cua-va-tai-khoan.md#chọn-mật-khẩu-mới-bắt-buộc) |
| Không tìm thấy màn hình | mọi địa chỉ không tồn tại | Mọi Tài khoản | [01](01-vao-cua-va-tai-khoan.md#không-tìm-thấy-màn-hình) |
| Không có quyền xem mục này | mọi địa chỉ bị chặn | Mọi Tài khoản | [01](01-vao-cua-va-tai-khoan.md#không-có-quyền-xem-mục-này) |
| Không kiểm tra được phiên làm việc | khi `/me` lỗi | Mọi Tài khoản | [01](01-vao-cua-va-tai-khoan.md#không-kiểm-tra-được-phiên-làm-việc) |
| Xưởng — thiết bị dùng chung trên sàn | `/floor` | Thiết bị Xưởng đã đăng ký + mã nhân viên/PIN | [10](10-xuong-may-thiet-bi.md) |

## 4. Thứ tự đọc đề nghị

Đào tạo một người mới, đi theo đúng thứ tự này — mỗi bước chỉ dùng cái bước trước
đã dạy:

1. [Vào cửa và Tài khoản](01-vao-cua-va-tai-khoan.md) — đăng nhập, Trang chủ, Cài đặt.
2. [An toàn](06-an-toan.md) — ghi nhận quan sát và sự cố. Đây là việc **mọi**
   Tài khoản làm được, nên dạy trước tiên.
3. [Chất lượng](05-chat-luong.md) — ghi nhận sản phẩm không phù hợp, cũng mọi
   Tài khoản làm được.
4. [Hành động](04-hanh-dong.md) — nêu Concern, chạy các giai đoạn, mở CAPA.
5. [Bảo trì](03-bao-tri.md) — nêu Yêu cầu trước (mọi Tài khoản), rồi mới tới
   Lệnh công việc và phần dành cho giám sát.
6. [Nhân sự](02-nhan-su.md) — Danh bạ, Chữ ký, Đào tạo của tôi, Đơn xin nghỉ.
7. [Sản xuất](07-san-xuat.md) và [Phân tích](08-phan-tich.md).
8. [Quản trị](09-quan-tri.md) — chỉ quản trị viên.

## 5. Tài liệu này không nói gì

- **Không** hướng dẫn cài đặt, triển khai hay vận hành máy chủ — việc đó ở
  `README.md` và `deploy/`.
- **Không** giải thích vì sao Nền tảng được thiết kế như vậy — các quyết định đó
  ở `docs/adr/`, và từ vựng ở `CONTEXT.md`.
- **Không** thay thế màn hình **Vai trò**: quản trị viên có thể đổi quyền của một
  vai trò bất cứ lúc nào, nên câu trả lời đúng nhất cho "tôi làm được gì" luôn là
  màn hình đó, không phải quyển tài liệu này.
