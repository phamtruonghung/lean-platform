# Hướng dẫn vận hành Nền tảng (lean-platform)

Tài liệu này viết cho **người vận hành trên sàn máy** và **người đào tạo họ** — không
phải cho lập trình viên. Nó là một bộ **TWI Job Instruction** đầy đủ, không phải một
quyển mô tả chức năng: **bốn điểm chuẩn bị** (dưới đây), **một thẻ cách hướng dẫn bốn
bước**, và **một Bảng phân tích công việc cho mỗi thao tác** — bảng nằm ở chương của
thao tác đó, mỗi chương một nhóm việc.

Tên nút, tên trường và tên màn hình trong tài liệu là **chữ tiếng Việt đúng như
trên màn hình** (lấy từ `frontend/lib/l10n/app_vi.arb`). Nếu màn hình của bạn
đang để tiếng Anh, vào **Cài đặt → Ngôn ngữ → Tiếng Việt**.

## Chuẩn bị hướng dẫn

Bốn việc phải xong **trước** buổi đào tạo đầu tiên. Thiếu một việc là buổi đào tạo
dừng giữa chừng để đi tìm thứ đáng lẽ có sẵn.

### 1. Thời biểu đào tạo

Ai học việc gì, xong trước ngày nào. Ngày là kế hoạch đang áp dụng của Ban Lean —
đổi lịch thì sửa **bảng này**, đừng sửa từng phiếu.

| Người học | Phải làm được | Phiếu | Hoàn thành trước |
| --- | --- | --- | --- |
| Người vận hành mới | Đăng nhập, đổi mật khẩu tạm, chọn tiếng Việt, đọc Trang chủ, nêu một Yêu cầu và đọc kết quả | 01.1–01.8, 03.9 | 22/11/2026 — trước ca đầu tiên |
| Nhân viên khối văn phòng | Như trên, cộng: tìm người trong Danh bạ, đọc hồ sơ của mình, lưu Chữ ký, gửi đơn xin nghỉ, tự xác nhận đào tạo | + 02.1–02.4, 02.12, 02.15, 02.16 | 29/11/2026 |
| Giám sát mới | Như trên, cộng: mở và xác nhận Bảng chấm công, tổ chức một buổi đào tạo, duyệt đơn xin nghỉ, và toàn bộ nhóm Bảo trì trừ **Phụ tùng** | + 02.8–02.11, 02.17, 03.1, 03.3–03.13 | 06/12/2026 |
| Kỹ sư và Quản lý | Toàn bộ nhóm Bảo trì, kể cả **Thêm/sửa Phụ tùng** | + 03.2 | 13/12/2026 |
| Quản trị viên | Tất cả, cộng: thêm Nhân viên, Chức danh, Kỹ năng, Đơn vị tổ chức, Đơn giá giờ, Chi phí chuẩn, Kế hoạch công việc | + 02.2, 02.5–02.7, 02.18, 02.19, 03.14 | 20/12/2026 |

### 2. Phân tích công việc

Mỗi thao tác có **một Bảng phân tích công việc** (Job Breakdown Sheet) đã viết xong.
Bảng gồm hai phần, không có phần thứ ba:

- **Khối đầu phiếu, bảy dòng, đúng thứ tự này:** **Công việc** (tên thao tác, màn hình,
  đường dẫn) · **Ai thao tác được** (vai trò mở được, vai trò ghi được) · **Vật tư, dữ
  liệu có trước** (bản ghi phải tồn tại trước khi bắt đầu) · **Công cụ** (màn hình, nút,
  mã quyền ghi) · **An toàn** (cảnh báo trước khi làm) · **Thiết bị đào tạo** (ảnh chụp
  dùng trong bảng) · **Chủ tài liệu · Rev · Ngày · Trang**.
- **Một bảng, cột đúng là `Các bước chính · Điểm then chốt · Vì sao · Minh hoạ`** — ba
  cột TWI (WHAT / HOW / WHY) cộng ảnh chụp đặt ngay tại bước nó minh hoạ. Bài học nằm ở
  cột **Vì sao**: một điểm then chốt không có lý do thì bị xoá, không phải được giữ.

Một **điểm then chốt** chỉ thuộc ba loại, ghi ngay trong ô: **`[Hỏng]`** — làm đúng mới
ra việc; **`[An toàn]`** — sai thì hại người, hại máy hoặc ghi bẩn dữ liệu thật;
**`[Dễ]`** — làm công việc dễ hơn. Điểm đúng cho **mọi** bước được viết một lần ở dòng
**Chung** đầu bảng, không lặp lại ở từng bước. Một bảng không quá **~10 bước chính**;
việc dài hơn thì tách thành hai phiếu.

**"Trang"** trong dòng cuối là **số phiếu** (`03.4`), không phải số trang in: số trang
PDF đổi theo mỗi lần dựng lại, còn số phiếu thì đứng yên và là thứ để gọi phiếu ra.

Danh sách phiếu — bấm tên để mở bảng. Cột **Bước chính** và **Ảnh** là số đếm thật của
từng phiếu.

**01 · Vào cửa và Tài khoản**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **01.1** | [Đăng nhập](01-vao-cua-va-tai-khoan.md#đăng-nhập) | 4 | 2 |
| **01.2** | [Chờ phê duyệt](01-vao-cua-va-tai-khoan.md#chờ-phê-duyệt) | 3 | 1 |
| **01.3** | [Chọn mật khẩu mới (bắt buộc)](01-vao-cua-va-tai-khoan.md#chọn-mật-khẩu-mới-bắt-buộc) | 3 | 1 |
| **01.4** | [Trang chủ](01-vao-cua-va-tai-khoan.md#trang-chủ) | 4 | 1 |
| **01.5** | [Cài đặt](01-vao-cua-va-tai-khoan.md#cài-đặt) | 2 | 2 |
| **01.6** | [Không tìm thấy màn hình](01-vao-cua-va-tai-khoan.md#không-tìm-thấy-màn-hình) | 2 | 1 |
| **01.7** | [Không có quyền xem mục này](01-vao-cua-va-tai-khoan.md#không-có-quyền-xem-mục-này) | 2 | 1 |
| **01.8** | [Không kiểm tra được phiên làm việc](01-vao-cua-va-tai-khoan.md#không-kiểm-tra-được-phiên-làm-việc) | 3 | 1 |

**02 · Nhân sự**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **02.1** | [Danh bạ](02-nhan-su.md#danh-bạ) | 3 | 1 |
| **02.2** | › [Thêm một Nhân viên](02-nhan-su.md#thêm-một-nhân-viên) | 3 | 1 |
| **02.3** | [Hồ sơ Nhân viên](02-nhan-su.md#hồ-sơ-nhân-viên) | 5 | 1 |
| **02.4** | [Giờ đã làm của một Nhân viên](02-nhan-su.md#giờ-đã-làm-của-một-nhân-viên) | 4 | 1 |
| **02.5** | [Chức danh công việc](02-nhan-su.md#chức-danh-công-việc) | 3 | 1 |
| **02.6** | [Kỹ năng](02-nhan-su.md#kỹ-năng) | 5 | 1 |
| **02.7** | [Đơn vị tổ chức](02-nhan-su.md#đơn-vị-tổ-chức) | 6 | 1 |
| **02.8** | [Chấm công](02-nhan-su.md#chấm-công) | 3 | 1 |
| **02.9** | [Bảng chấm công một ca](02-nhan-su.md#bảng-chấm-công-một-ca) | 4 | 1 |
| **02.10** | [Chấm công cần xác nhận](02-nhan-su.md#chấm-công-cần-xác-nhận) | 2 | — |
| **02.11** | [Đào tạo](02-nhan-su.md#đào-tạo) | 4 | 1 |
| **02.12** | › [Xác nhận một buổi đào tạo](02-nhan-su.md#xác-nhận-một-buổi-đào-tạo) | 3 | — |
| **02.13** | [Bản ghi đào tạo (chi tiết)](02-nhan-su.md#bản-ghi-đào-tạo-chi-tiết) | 2 | — |
| **02.14** | [Biểu mẫu in của bản ghi đào tạo](02-nhan-su.md#biểu-mẫu-in-của-bản-ghi-đào-tạo) | 2 | — |
| **02.15** | [Chữ ký của tôi](02-nhan-su.md#chữ-ký-của-tôi) | 3 | 1 |
| **02.16** | [Đơn xin nghỉ](02-nhan-su.md#đơn-xin-nghỉ) | 2 | 1 |
| **02.17** | › [Duyệt hoặc từ chối một đơn](02-nhan-su.md#duyệt-hoặc-từ-chối-một-đơn) | 3 | — |
| **02.18** | [Đơn giá giờ](02-nhan-su.md#đơn-giá-giờ) | 4 | 1 |
| **02.19** | [Chi phí chuẩn sản phẩm](02-nhan-su.md#chi-phí-chuẩn-sản-phẩm) | 3 | 1 |

**03 · Bảo trì**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **03.1** | [Tài sản](03-bao-tri.md#tài-sản) | 6 | 2 |
| **03.2** | [Phụ tùng](03-bao-tri.md#phụ-tùng) | 3 | 1 |
| **03.3** | [Kho](03-bao-tri.md#kho) | 3 | 2 |
| **03.4** | [Lệnh công việc](03-bao-tri.md#lệnh-công-việc) | 7 | 2 |
| **03.5** | [Chi tiết Lệnh công việc](03-bao-tri.md#chi-tiết-lệnh-công-việc) | 5 | 2 |
| **03.6** | [Phân công Lệnh công việc](03-bao-tri.md#phân-công-lệnh-công-việc) | 1 | 1 |
| **03.7** | [Hoàn thành Lệnh công việc](03-bao-tri.md#hoàn-thành-lệnh-công-việc) | 2 | 1 |
| **03.8** | [Huỷ Lệnh công việc](03-bao-tri.md#huỷ-lệnh-công-việc) | 2 | — |
| **03.9** | [Yêu cầu của tôi](03-bao-tri.md#yêu-cầu-của-tôi) | 3 | 1 |
| **03.10** | [Hàng chờ phân loại](03-bao-tri.md#hàng-chờ-phân-loại) | 4 | 1 |
| **03.11** | [Thời gian dừng máy](03-bao-tri.md#thời-gian-dừng-máy) | 4 | 1 |
| **03.12** | [Lịch bảo trì định kỳ](03-bao-tri.md#lịch-bảo-trì-định-kỳ) | 4 | 1 |
| **03.13** | [Đồng hồ đo](03-bao-tri.md#đồng-hồ-đo) | 3 | 1 |
| **03.14** | [Kế hoạch công việc](03-bao-tri.md#kế-hoạch-công-việc) | 3 | 1 |

**04 · Hành động**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **04.1** | [Nhật ký hành động](04-hanh-dong.md#nhật-ký-hành-động) | 4 | 1 |
| **04.2** | [Nêu một Concern](04-hanh-dong.md#nêu-một-concern) | 5 | 1 |
| **04.3** | [Chi tiết Hành động](04-hanh-dong.md#chi-tiết-hành-động) | 7 | 1 |
| **04.4** | [Hoàn thành một giai đoạn](04-hanh-dong.md#hoàn-thành-một-giai-đoạn) | 4 | 1 |
| **04.5** | [Chuyển Hành động lên trên](04-hanh-dong.md#chuyển-hành-động-lên-trên) | 3 | — |
| **04.6** | [Huỷ một Hành động](04-hanh-dong.md#huỷ-một-hành-động) | 3 | — |
| **04.7** | [Thêm một biện pháp](04-hanh-dong.md#thêm-một-biện-pháp) | 5 | — |
| **04.8** | [CAPA](04-hanh-dong.md#capa) | 3 | 1 |
| **04.9** | [Mở một CAPA](04-hanh-dong.md#mở-một-capa) | 4 | 1 |
| **04.10** | [Chi tiết CAPA](04-hanh-dong.md#chi-tiết-capa) | 7 | 1 |
| **04.11** | [Chuỗi Why](04-hanh-dong.md#chuỗi-why) | 4 | — |
| **04.12** | [Nguyên nhân và kết luận](04-hanh-dong.md#nguyên-nhân-và-kết-luận) | 4 | — |
| **04.13** | [Ghi bước kiểm tra hiệu quả](04-hanh-dong.md#ghi-bước-kiểm-tra-hiệu-quả) | 4 | — |
| **04.14** | [Báo cáo CAPA](04-hanh-dong.md#báo-cáo-capa) | 3 | 1 |

**05 · Chất lượng**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **05.1** | [Sản phẩm](05-chat-luong.md#sản-phẩm) | 3 | 1 |
| **05.2** | [Mã lỗi](05-chat-luong.md#mã-lỗi) | 3 | 1 |
| **05.3** | [Sản phẩm không phù hợp](05-chat-luong.md#sản-phẩm-không-phù-hợp) | 7 | 2 |
| **05.4** | [Chi tiết Sản phẩm không phù hợp](05-chat-luong.md#chi-tiết-sản-phẩm-không-phù-hợp) | 6 | 1 |
| **05.5** | [Ghi nhận phương án xử lý](05-chat-luong.md#ghi-nhận-phương-án-xử-lý) | 4 | 1 |
| **05.6** | [Bốn quyết định cần thẩm quyền Chất lượng](05-chat-luong.md#bốn-quyết-định-cần-thẩm-quyền-chất-lượng) | 4 | — |
| **05.7** | [Nêu hoặc Liên kết một Concern](05-chat-luong.md#nêu-hoặc-liên-kết-một-concern) | 4 | — |
| **05.8** | [Khách hàng](05-chat-luong.md#khách-hàng) | 2 | 1 |
| **05.9** | [Khiếu nại khách hàng](05-chat-luong.md#khiếu-nại-khách-hàng) | 4 | 1 |
| **05.10** | [Chi tiết Khiếu nại](05-chat-luong.md#chi-tiết-khiếu-nại) | 4 | 1 |
| **05.11** | [Trình chiếu](05-chat-luong.md#trình-chiếu) | 5 | — |
| **05.12** | [Nhà cung cấp](05-chat-luong.md#nhà-cung-cấp) | 2 | 1 |
| **05.13** | [NCR nhà cung cấp](05-chat-luong.md#ncr-nhà-cung-cấp) | 4 | 1 |
| **05.14** | [Chi tiết NCR nhà cung cấp](05-chat-luong.md#chi-tiết-ncr-nhà-cung-cấp) | 4 | 1 |

**06 · An toàn**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **06.1** | [Sự cố](06-an-toan.md#sự-cố) | 7 | 2 |
| **06.2** | [Chi tiết Sự cố an toàn](06-an-toan.md#chi-tiết-sự-cố-an-toàn) | 5 | 1 |
| **06.3** | [Phân loại thương tích](06-an-toan.md#phân-loại-thương-tích) | 4 | 1 |
| **06.4** | [Sửa mức độ và Ghi nhận số ngày](06-an-toan.md#sửa-mức-độ-và-ghi-nhận-số-ngày) | 5 | — |
| **06.5** | [Đóng sự cố và Nêu Concern](06-an-toan.md#đóng-sự-cố-và-nêu-concern) | 3 | — |
| **06.6** | [Quan sát](06-an-toan.md#quan-sát) | 7 | 2 |
| **06.7** | [Chi tiết Quan sát an toàn](06-an-toan.md#chi-tiết-quan-sát-an-toàn) | 4 | 1 |
| **06.8** | [Nêu Hành động từ một quan sát](06-an-toan.md#nêu-hành-động-từ-một-quan-sát) | 3 | — |
| **06.9** | [Hai danh mục chẩn đoán](06-an-toan.md#hai-danh-mục-chẩn-đoán) | 3 | 2 |
**07 · Sản xuất**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **07.1** | [Chọn Bộ phận](07-san-xuat.md#chọn-bộ-phận) | 3 | 1 |
| **07.2** | [Bảng của một Bộ phận](07-san-xuat.md#bảng-của-một-bộ-phận) | 6 | 1 |
| **07.3** | [Viết và gửi bàn giao](07-san-xuat.md#viết-và-gửi-bàn-giao) | 8 | 1 |
| **07.4** | [Xác nhận bàn giao](07-san-xuat.md#xác-nhận-bàn-giao) | 4 | — |

**08 · Phân tích**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **08.1** | [Bảng phân cấp](08-phan-tich.md#bảng-phân-cấp) | 5 | 1 |
| **08.2** | [Danh mục KPI](08-phan-tich.md#danh-mục-kpi) | 5 | — |
| **08.3** | [Mục tiêu của một KPI](08-phan-tich.md#mục-tiêu-của-một-kpi) | 5 | — |
| **08.4** | [Đánh giá KPI](08-phan-tich.md#đánh-giá-kpi) | 6 | — |
| **08.5** | [Độ phủ kỹ năng](08-phan-tich.md#độ-phủ-kỹ-năng) | 3 | 1 |

**09 · Quản trị**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **09.1** | [Hàng chờ phê duyệt](09-quan-tri.md#hàng-chờ-phê-duyệt) | 7 | — |
| **09.2** | [Tài khoản](09-quan-tri.md#tài-khoản) | 6 | — |
| **09.3** | [Vai trò](09-quan-tri.md#vai-trò) | 5 | — |

**10 · Xưởng**

| Phiếu | Việc | Bước chính | Ảnh |
| --- | --- | ---: | ---: |
| **10.1** | [Màn hình Xưởng](10-xuong-may-thiet-bi.md#màn-hình-xưởng) | 4 | — |
| **10.2** | [Bắt đầu và Hoàn thành một Lệnh công việc](10-xuong-may-thiet-bi.md#bắt-đầu-và-hoàn-thành-một-lệnh-công-việc) | 5 | — |
| **10.3** | [Đào tạo của tôi](10-xuong-may-thiet-bi.md#đào-tạo-của-tôi) | 3 | — |
| **10.4** | [Ghi nhận không phù hợp](10-xuong-may-thiet-bi.md#ghi-nhận-không-phù-hợp) | 5 | — |
| **10.5** | [Báo sự cố an toàn](10-xuong-may-thiet-bi.md#báo-sự-cố-an-toàn) | 4 | — |
| **10.6** | [Ghi nhận quan sát an toàn](10-xuong-may-thiet-bi.md#ghi-nhận-quan-sát-an-toàn) | 5 | — |

**Mọi chương đã chuyển xong.** `00-tong-quan.md` và `90-phu-luc-ma-quyen.md` không phải
chương thao tác nên không có phiếu: chương 00 vẽ bản đồ các Phân hệ nối với nhau ra sao,
và phụ lục 90 là bảng tra 84 mã quyền. Ba phiếu KPI (08.2–08.4) và toàn bộ chương 10
chưa có ảnh chụp — lý do ghi trong đầu mỗi chương, và `t_30897c2a` là thẻ chụp bổ sung.

### 3. Chuẩn bị đủ

Những thứ phải có sẵn trước bước 1 của bất kỳ phiếu nào:

- **Tài khoản của chính người học** — đã được **chấp nhận** ở **Phê duyệt** (phiếu
  01.2), đã đổi khỏi mật khẩu tạm (phiếu 01.3), và đã gắn với một Nhân viên (Trang chủ
  nói rõ nếu chưa). Đào tạo bằng Tài khoản quản trị viên là dạy một người trên quyền
  của người khác — mọi thứ họ bấm đều thành công, kể cả thứ đáng lẽ bị từ chối.
- **Vai trò và quyền đúng** — [§1](#1-sáu-vai-trò-và-cách-đọc-phần-ai-thao-tác-được) có
  sáu vai trò và cách đọc dòng **Ai thao tác được**; bảng **84 mã quyền** ở
  [`90-phu-luc-ma-quyen.md`](90-phu-luc-ma-quyen.md). Ba điều phải nói với người học
  trước khi họ bấm nút đầu tiên: vào được màn hình **không** có nghĩa là ghi được; ghi
  còn cần **phạm vi Đơn vị tổ chức**; đọc rộng — ghi hẹp là chủ ý, không phải lỗi.
- **Dữ liệu mẫu đủ để làm hết phiếu.** Không có bản ghi thì bước 2 của nhiều phiếu
  không chạy được (không có Tài sản thì không tạo được Lệnh công việc, không có Phụ
  tùng thì không xuất được kho):

  | Nhóm | Phải có trước |
  | --- | --- |
  | Nhân sự | 1 Nhà máy · 1 bộ phận và 2 tổ bên dưới · 3 Nhân viên đã được **Phân công** vào tổ · 1 Chức danh · 1 Kỹ năng có **chu kỳ đánh giá lại** |
  | Bảo trì | 2 Tài sản, một cái có **Đồng hồ đo** · 2 Phụ tùng và 1 Kho · 1 Kế hoạch công việc · 1 Lệnh công việc đang mở · 1 Yêu cầu đang chờ phân loại |

  Dạy trên **dữ liệu demo**: `dev/seed-demo.sql` (Nhà máy Demo) là bộ dữ liệu mà mọi
  ảnh trong tài liệu này được chụp từ đó — không có tên người thật, không có số liệu
  thật. Đừng dạy người mới trên dữ liệu sản xuất thật.

### 4. Sắp xếp nơi làm việc

Chỗ ngồi và cái máy, đúng như ảnh trong tài liệu:

- **Một máy, một người, một trình duyệt.** Ngôn ngữ và giao diện sáng/tối lưu **theo
  trình duyệt**, không theo Tài khoản: đổi người học thì đăng xuất, đừng để hai người
  dùng chung một cửa sổ.
- **Cửa sổ rộng 1440 × 900**, thanh điều hướng **mở rộng** (260 px). Dưới 700 px bề
  ngang, thanh điều hướng thu về 64 px và **tên các mục biến mất** — người học mất
  đường đi, và mọi ảnh trong tài liệu không còn khớp màn hình.
- **Ngôn ngữ Tiếng Việt**, đặt ở **Cài đặt → Ngôn ngữ** (phiếu 01.5) và kiểm tra lại
  đầu mỗi buổi: người ca trước có thể đã đổi về tiếng Anh trên cùng máy đó.
- **Tắt thông báo**, để sẵn tab **Trang chủ** — người học bắt đầu từ đó, và đó cũng là
  chỗ họ thấy việc đang chờ mình.
- **Phiếu giấy cạnh máy**: in phiếu đang dạy từ bản PDF (xem [phụ lục](#phụ-lục-bản-pdf-sơ-đồ-và-ảnh-chụp)),
  không mở điện thoại vừa bấm vừa đọc.

## Cách hướng dẫn

Một buổi đào tạo, bốn bước, đúng thứ tự này. Bước 2 và bước 3 là hai nửa của cùng một
việc: người hướng dẫn làm trước, người học làm lại y hệt.

| Bước | Nói và làm |
| --- | --- |
| **Bước 1 — Chuẩn bị người học** | Làm người học thoải mái · Nói rõ việc sắp học và hỏi xem họ đã biết gì · Gây hứng thú · Để họ đứng/ngồi đúng chỗ thao tác. |
| **Bước 2 — Trình bày công việc** | Nói, làm mẫu và minh hoạ **từng bước chính một** · Nhấn từng **điểm then chốt** và **lý do** · Hướng dẫn rõ, đủ, kiên nhẫn · Không đưa nhiều hơn người học tiếp thu được một lúc. |
| **Bước 3 — Người học làm thử** | Để người học làm, sửa lỗi · Để người học **nói lại từng bước chính, điểm then chốt, lý do** trong khi làm lại · Bảo đảm họ hiểu · Làm tiếp cho tới khi **bạn biết là người học biết**. |
| **Bước 4 — Theo dõi tiếp** | Để họ tự làm · Chỉ rõ hỏi ai khi cần · Kiểm tra thường xuyên, khuyến khích đặt câu hỏi · Giảm dần việc kèm cặp. |

> *Nếu người học chưa học được, người hướng dẫn chưa dạy đúng.*

Ba điều rút ra từ chính các phiếu trong tài liệu này:

1. **Điểm then chốt, không phải danh sách bước, mới là bài học.** Cột **Vì sao** là
   thứ người học phải nói lại được ở bước 3 — nếu họ thuộc bước mà không nói được lý
   do, họ sẽ bỏ qua điểm then chốt ngay khi có việc gấp.
2. **Không dạy quá một phiếu một lúc.** Mỗi phiếu đã được cắt còn ~10 bước chính vì lý
   do đó; hai phiếu trong một buổi là quá tải, trừ khi người học đã làm nghề.
3. **Dạy trên dữ liệu demo, không dạy trên dữ liệu thật.** Một bước ghi sai trong lúc
   học mà đã vào sổ thật thì phải sửa bằng nghiệp vụ, không phải bằng cách nói "làm
   lại đi".

---

Chương [**00 · Toàn cảnh**](00-tong-quan.md) là bản đồ của cả tài liệu: Nền tảng gồm những
nhóm việc gì, nhóm nào cấp dữ liệu cho nhóm nào, và một việc trên sàn đi qua những màn
hình nào trước khi thành con số.

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
| An toàn | Loại thương tích | `/safety/injury-types` | `SAF_INJURY_TYPES_MAINTAIN` | `SAF_INJURY_TYPES_MAINTAIN` | [06](06-an-toan.md#hai-danh-mục-chẩn-đoán) |
| An toàn | Bộ phận cơ thể | `/safety/body-parts` | `SAF_BODY_PARTS_MAINTAIN` | `SAF_BODY_PARTS_MAINTAIN` | [06](06-an-toan.md#hai-danh-mục-chẩn-đoán) |
| Sản xuất | Bàn giao ca | `/production/sections` | `PRD_HANDOVER_DISPLAY` | `PRD_HANDOVER_WRITE` · `PRD_HANDOVER_ACKNOWLEDGE` | [07](07-san-xuat.md#chọn-bộ-phận) |
| Phân tích | Bảng phân cấp | `/tier-board` | `INS_TIER_BOARD_DISPLAY` | — | [08](08-phan-tich.md#bảng-phân-cấp) |
| Phân tích | Độ phủ kỹ năng | `/skill-coverage` | `INS_SKILL_COVERAGE_DISPLAY` | — | [08](08-phan-tich.md#độ-phủ-kỹ-năng) |
| Phân tích | Danh mục KPI | `/kpi` | `INS_KPI_CATALOGUE_DISPLAY` | `INS_KPI_CATALOGUE_CHANGE` | [08](08-phan-tich.md#danh-mục-kpi) |
| Phân tích | Đánh giá KPI | `/kpi/review` | `INS_KPI_REVIEW_DISPLAY` | `INS_KPI_REVIEW_RECORD` | [08](08-phan-tich.md#đánh-giá-kpi) |
| Quản trị | Phê duyệt | `/approvals` | `ADM_APPROVALS_DISPLAY` | `ADM_APPROVALS_DECIDE` | [09](09-quan-tri.md#hàng-chờ-phê-duyệt) |
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
| Chấp nhận một Yêu cầu | hộp thoại trên `/requests` — nút **Chấp nhận** trên dòng | Mang `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Từ chối một Yêu cầu | hộp thoại trên `/requests` — menu ⋮ của dòng | Mang `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Đánh dấu Yêu cầu trùng lặp | hộp thoại trên `/requests` — menu ⋮ của dòng | Mang `MTN_REQUESTS_TRIAGE` | [03](03-bao-tri.md#hàng-chờ-phân-loại) |
| Nêu một Concern | `/actions/new` | Mang `ACT_RAISE` | [04](04-hanh-dong.md#nêu-một-concern) |
| Chi tiết Hành động | `/actions/:id` | Mang `ACT_LOG_DISPLAY` | [04](04-hanh-dong.md#chi-tiết-hành-động) |
| Hoàn thành một giai đoạn | `/actions/:id/phases/:phase/complete` | Mang `ACT_MEASURE` / `ACT_VERIFY` theo giai đoạn | [04](04-hanh-dong.md#hoàn-thành-một-giai-đoạn) |
| Chuyển Hành động lên trên | `/actions/:id/escalate` | Mang `ACT_CHANGE` | [04](04-hanh-dong.md#chuyển-hành-động-lên-trên) |
| Mở một CAPA | `/actions/:id/capa` | Mang `ACT_CAPA_OPEN` **và** thẩm quyền Chất lượng | [04](04-hanh-dong.md#mở-một-capa) |
| Huỷ một Hành động | `/actions/:id/cancel` | Mang `ACT_CHANGE` | [04](04-hanh-dong.md#huỷ-một-hành-động) |
| Bỏ liên kết Sản phẩm không phù hợp | `/actions/:id/nonconformances/:nonconformanceId/unlink` | Mang `ACT_CHANGE` | [04](04-hanh-dong.md#chi-tiết-hành-động) |
| Thêm một biện pháp | `/actions/:id/measures/:measureType/new` | Mang `ACT_MEASURE` | [04](04-hanh-dong.md#thêm-một-biện-pháp) |
| Chi tiết CAPA | `/actions/capas/:id` | Mang `ACT_CAPA_DISPLAY` | [04](04-hanh-dong.md#chi-tiết-capa) |
| Thêm / sửa / bỏ một Why | `/actions/capas/:id/whys/:chain/new`, `/actions/capas/:id/whys/:chain/:whyId/edit`, `/actions/capas/:id/whys/:chain/:whyId/remove` | Mang `ACT_CAPA_VERIFY` | [04](04-hanh-dong.md#chuỗi-why) |
| Thêm / sửa / kết luận / bỏ một nguyên nhân | `/actions/capas/:id/causes/:category/new`, `/actions/capas/:id/causes/:category/:causeId/edit`, `/actions/capas/:id/causes/:category/:causeId/verdict`, `/actions/capas/:id/causes/:category/:causeId/remove`, `/actions/capas/:id/causes/:category/:causeId/why` | Mang `ACT_CAPA_VERIFY` | [04](04-hanh-dong.md#nguyên-nhân-và-kết-luận) |
| Ghi bước kiểm tra hiệu quả | `/actions/capas/:id/effectiveness` | Mang `ACT_CAPA_EFFECTIVENESS` **và** thẩm quyền Chất lượng — trưởng nhóm không ghi được | [04](04-hanh-dong.md#ghi-bước-kiểm-tra-hiệu-quả) |
| Báo cáo CAPA | `/actions/capas/:id/report` | Mang `ACT_CAPA_DISPLAY` | [04](04-hanh-dong.md#báo-cáo-capa) |
| Ghi nhận Sản phẩm không phù hợp | `/non-conformances/new` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#sản-phẩm-không-phù-hợp) |
| Chi tiết Sản phẩm không phù hợp | `/non-conformances/:id` | Mang `QLT_NONCONFORMANCES_DISPLAY` | [05](05-chat-luong.md#chi-tiết-sản-phẩm-không-phù-hợp) |
| Tăng số lượng · Nâng mức độ/ngăn chặn | `/non-conformances/:id/quantity`, `/non-conformances/:id/update` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#chi-tiết-sản-phẩm-không-phù-hợp) |
| Ghi nhận phương án xử lý | `/non-conformances/:id/disposition` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#ghi-nhận-phương-án-xử-lý) |
| Cho phép nhượng bộ | `/non-conformances/:id/concession` | Mang `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | [05](05-chat-luong.md#bốn-quyết-định-cần-thẩm-quyền-chất-lượng) |
| Hạ mức độ | `/non-conformances/:id/lower-severity` | Mang `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | [05](05-chat-luong.md#bốn-quyết-định-cần-thẩm-quyền-chất-lượng) |
| Mở lại · Huỷ vì ghi nhầm | `/non-conformances/:id/reopen`, `/non-conformances/:id/cancel` | Mang `QLT_NONCONFORMANCES_DISPOSE` **và** thẩm quyền Chất lượng | [05](05-chat-luong.md#bốn-quyết-định-cần-thẩm-quyền-chất-lượng) |
| Nêu / Liên kết một Concern | `/non-conformances/:id/raise-concern`, `/non-conformances/:id/link-concern` | Mang `QLT_NONCONFORMANCES_RECORD` | [05](05-chat-luong.md#nêu-hoặc-liên-kết-một-concern) |
| Ghi nhận khiếu nại | `/complaints/new` | Mang `QLT_COMPLAINTS_RECORD` | [05](05-chat-luong.md#khiếu-nại-khách-hàng) |
| Chi tiết Khiếu nại khách hàng | `/complaints/:id` | Mang `QLT_COMPLAINTS_DISPLAY` | [05](05-chat-luong.md#chi-tiết-khiếu-nại) |
| Phản hồi · Ghi nhận/liên kết không phù hợp | `/complaints/:id/respond`, `/complaints/:id/nonconformance`, `/complaints/:id/link` | Mang `QLT_COMPLAINTS_RECORD` | [05](05-chat-luong.md#chi-tiết-khiếu-nại) |
| Ghi nhận NCR nhà cung cấp | `/supplier-ncrs/new` | Mang `QLT_SUPPLIER_NCRS_RECORD` | [05](05-chat-luong.md#ncr-nhà-cung-cấp) |
| Chi tiết NCR nhà cung cấp | `/supplier-ncrs/:id` | Mang `QLT_SUPPLIER_NCRS_DISPLAY` | [05](05-chat-luong.md#chi-tiết-ncr-nhà-cung-cấp) |
| Phương án xử lý · Ghi nhận/liên kết không phù hợp | `/supplier-ncrs/:id/disposition`, `/supplier-ncrs/:id/nonconformance`, `/supplier-ncrs/:id/link` | Mang `QLT_SUPPLIER_NCRS_RECORD` | [05](05-chat-luong.md#chi-tiết-ncr-nhà-cung-cấp) |
| Ghi nhận sự cố an toàn | `/safety/incidents/record` | Mang `SAF_INCIDENTS_RECORD`; nêu người bị thương / loại thương tích / bộ phận cơ thể thêm `SAF_CLASSIFY` **và** thẩm quyền An toàn | [06](06-an-toan.md#sự-cố) |
| Chi tiết Sự cố an toàn | `/safety/incidents/:id` | Mang `SAF_INCIDENTS_DISPLAY` | [06](06-an-toan.md#chi-tiết-sự-cố-an-toàn) |
| Hạn điều tra · Chuyển trạng thái | `/safety/incidents/:id/due-date`, `/safety/incidents/:id/status` | Mang `SAF_INCIDENTS_RECORD` | [06](06-an-toan.md#chi-tiết-sự-cố-an-toàn) |
| Phân loại thương tích | `/safety/incidents/:id/classify` | Mang `SAF_CLASSIFY` **và** thẩm quyền An toàn | [06](06-an-toan.md#phân-loại-thương-tích) |
| Sửa mức độ · Ghi nhận số ngày | `/safety/incidents/:id/severity`, `/safety/incidents/:id/days` | Mang `SAF_CLASSIFY` (mức độ) và `SAF_INCIDENTS_RECORD` (số ngày), cả hai **và** thẩm quyền An toàn | [06](06-an-toan.md#sửa-mức-độ-và-ghi-nhận-số-ngày) |
| Đóng sự cố · Nêu Concern | `/safety/incidents/:id/close`, `/safety/incidents/:id/raise-concern` | Mang `SAF_INCIDENTS_RECORD` **và** thẩm quyền An toàn (đóng) · `ACT_RAISE` (Concern) | [06](06-an-toan.md#đóng-sự-cố-và-nêu-concern) |
| Ghi nhận quan sát an toàn | `/safety/observations/record` | Mang `SAF_OBSERVATIONS_RECORD` | [06](06-an-toan.md#quan-sát) |
| Chi tiết Quan sát an toàn | `/safety/observations/:id` | Mang `SAF_OBSERVATIONS_DISPLAY` | [06](06-an-toan.md#chi-tiết-quan-sát-an-toàn) |
| Nêu một Hành động từ quan sát | `/safety/observations/:id/raise-action` | Mang `SAF_OBSERVATIONS_RECORD` **và** `ACT_RAISE` | [06](06-an-toan.md#nêu-hành-động-từ-một-quan-sát) |
| Bảng của một Bộ phận | `/production/sections/:orgUnitId/board` | Mang `PRD_HANDOVER_DISPLAY` | [07](07-san-xuat.md#bảng-của-một-bộ-phận) |
| Xác nhận bàn giao | `/production/sections/:orgUnitId/board/acknowledge/:handoverId` | Mang `PRD_HANDOVER_ACKNOWLEDGE` | [07](07-san-xuat.md#xác-nhận-bàn-giao) |
| Bàn giao ca của một ca | `/production/sections/:orgUnitId/handover/:shiftInstanceId` | Mang `PRD_HANDOVER_WRITE` để ghi, `PRD_HANDOVER_DISPLAY` để đọc | [07](07-san-xuat.md#viết-và-gửi-bàn-giao) |
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

1. [Toàn cảnh](00-tong-quan.md) — năm phút: Nền tảng gồm những nhóm việc gì và các Phân
   hệ nối với nhau ra sao. Đọc trước mọi thứ khác.
2. [Vào cửa và Tài khoản](01-vao-cua-va-tai-khoan.md) — đăng nhập, Trang chủ, Cài đặt.
3. [An toàn](06-an-toan.md) — ghi nhận quan sát và sự cố. Đây là việc **mọi**
   Tài khoản làm được, nên dạy trước tiên.
4. [Chất lượng](05-chat-luong.md) — ghi nhận sản phẩm không phù hợp, cũng mọi
   Tài khoản làm được.
5. [Hành động](04-hanh-dong.md) — nêu Concern, chạy các giai đoạn, mở CAPA.
6. [Bảo trì](03-bao-tri.md) — nêu Yêu cầu trước (mọi Tài khoản), rồi mới tới
   Lệnh công việc và phần dành cho giám sát.
7. [Nhân sự](02-nhan-su.md) — Danh bạ, Chữ ký, Đào tạo của tôi, Đơn xin nghỉ.
8. [Sản xuất](07-san-xuat.md) và [Phân tích](08-phan-tich.md).
9. [Quản trị](09-quan-tri.md) — chỉ quản trị viên.

## 5. Tài liệu này không nói gì

- **Không** hướng dẫn cài đặt, triển khai hay vận hành máy chủ — việc đó ở
  `README.md` và `deploy/`.
- **Không** giải thích vì sao Nền tảng được thiết kế như vậy — các quyết định đó
  ở `docs/adr/`, và từ vựng ở `CONTEXT.md`.
- **Không** thay thế màn hình **Vai trò**: quản trị viên có thể đổi quyền của một
  vai trò bất cứ lúc nào, nên câu trả lời đúng nhất cho "tôi làm được gì" luôn là
  màn hình đó, không phải quyển tài liệu này.

---

## Phụ lục: bản PDF, sơ đồ và ảnh chụp


Tài liệu này đọc được hai cách: các tệp Markdown trong thư mục này (bản gốc, sửa được,
xem thẳng trên GitHub), và một **bản PDF để đọc hoặc in**.

- **Bản PDF**: [`pdf/huong-dan-su-dung.pdf`](pdf/huong-dan-su-dung.pdf) — toàn bộ chương
  00–90 trong một tệp, kèm **mười sơ đồ** (mỗi sơ đồ in trên một **trang ngang** riêng) và
  **ảnh chụp màn hình thật của ứng dụng** đặt ngay tại bước nó minh hoạ.
- **Sinh lại bản PDF** sau khi sửa Markdown: `bash scripts/build-user-guide-pdf.sh`.
  Script dựng lại ảnh sơ đồ rồi in PDF vào `pdf/`. Nó cần ba thứ, và dừng lại nói rõ
  nếu thiếu cái nào:
  - `node` + gói **playwright** — script tìm nó trong `docs/user-guide/diagrams/node_modules`
    (chạy `cd docs/user-guide/diagrams && npm i playwright` một lần là đủ), rồi tới
    bản cài sẵn của Hermes, rồi `NODE_PATH`;
  - **Chromium** cho playwright — `npx playwright install chromium`, hoặc trỏ `CHROME`
    vào một binary có sẵn;
  - `python3` + module **markdown**, và tuỳ chọn ImageMagick `convert` (thiếu `convert`
    thì PDF vẫn ra, chỉ nặng hơn).
- **Nguồn của sơ đồ** là `diagrams/*.html` + `diagrams/diagram.css`, sinh ảnh bằng
  `node docs/user-guide/diagrams/render.js` → `images/*.png`. Muốn đổi chữ trong sơ đồ
  thì sửa HTML rồi render lại, đừng sửa thẳng tệp PNG.

### Ảnh chụp màn hình: `images/screens/`

Ảnh trong `images/screens/` là **ảnh chụp ứng dụng thật**, không phải hình vẽ. Cách chụp
lại một ảnh, để lần sau ai sửa màn hình còn chụp lại được giống hệt:

- **Môi trường**: `./scripts/review.sh` (dựng cả stack ở `http://localhost:3002`), dữ liệu
  là `dev/seed-demo.sql` — Nhà máy Demo. Nhờ vậy ảnh **không có tên người thật, không có
  mặt người, không có số liệu KPI/tài chính thật**: mọi tên trong ảnh là dữ liệu demo
  (`Demo Admin`, `DEMO-001 Nour Haddad`, `Meridian Pumps`, `Widget A`). Không chụp từ
  bản triển khai thật.
- **Khung nhìn cố định**: rộng **1440 × 900** CSS px, `deviceScaleFactor: 2`, chụp toàn
  bộ cửa sổ (kể cả thanh điều hướng), lưu PNG rồi thu về **1440 px** rộng cho nhẹ.
- **Ngôn ngữ**: **Tiếng Việt** — vì các chương viết bằng tiếng Việt và tên nút trong
  chương là chuỗi tiếng Việt lấy từ `app_vi.arb`. Chương 01 có thêm một ảnh ở trạng thái
  **tiếng Anh** để minh hoạ chính bước đổi ngôn ngữ.
- **Tên tệp**: `<chương>-<bước>-<việc>.png`, ví dụ `03-2-them-tai-san.png` — chương 03,
  bước 2 của bảng **Các bước chính**, việc "thêm tài sản". Một bước có hai ảnh thì đặt
  tên khác phần việc, đừng đánh số lại. Ảnh chụp một **nút** của màn hình, không ứng với
  bước nào trong bảng, thì **bỏ phần `<bước>`** — `02-danh-ba-them-nhan-vien.png` — và chú
  thích theo nút, không ghi "bước n". Số trong tên tệp là **bước tại lúc chụp**: phiếu
  được biên tập lại thì tên tệp giữ nguyên, còn số hiệu để dẫn trong phiếu là số của
  **Ảnh <chương>.<số>** — đánh lại theo thứ tự trong chương, và là thứ cột **Minh hoạ**
  cùng dòng **Thiết bị đào tạo** phải khớp.
- **Chú thích**: mỗi ảnh là một khối `![Ảnh <ch>.<số> — <tên màn hình>](…)` rồi một dòng
  `***Ảnh <ch>.<số>.** …*` ngay dưới. Khối này nằm **ngay sau bảng Các bước chính của
  việc đó**, không gom vào một phòng trưng bày ở cuối chương: trong PDF ảnh in ở cỡ
  trang, cùng trang với bước nó giải thích. Một bước không có ảnh thì ô **Minh hoạ** ghi
  `—`, không vẽ sơ đồ thay ảnh chụp màn hình.
- **Quy tắc dữ liệu**: một ảnh chỉ được commit khi không có tên người thật, mặt người,
  danh tính khách hàng/nhà cung cấp thật, hay số liệu KPI/tài chính thật. Không chụp
  được màn hình nào mà không vi phạm thì **bỏ ảnh đó và ghi lý do vào mô tả PR**, đừng
  che bằng cách sửa số liệu.
