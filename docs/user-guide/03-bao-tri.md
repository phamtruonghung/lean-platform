# 03 · Bảo trì

Nhóm **Bảo trì** là chuỗi công việc trên máy: có máy nào (**Tài sản**), ai báo hỏng
(**Yêu cầu**), ai làm (**Lệnh công việc**), lấy phụ tùng ở đâu (**Kho**, **Phụ
tùng**), và làm phòng ngừa thế nào (**Lịch bảo trì định kỳ**, **Đồng hồ đo**,
**Kế hoạch công việc**).

**Hai điều phải nói trước khi dạy nhóm này.**

1. **Người vận hành không thấy nhóm Bảo trì trên thanh điều hướng** — trừ **Yêu cầu
   của tôi**. Đó là chủ ý: việc của một người vận hành là **nêu Yêu cầu** khi máy
   có vấn đề, rồi theo dõi kết quả. Mọi màn hình còn lại cần `supervisor` trở lên.
2. **Vị trí Đơn vị tổ chức quyết định ai làm được gì.** Một Lệnh công việc thuộc về
   Đơn vị tổ chức của Tài sản; muốn phân công hay đóng nó, bạn cần quyền sửa **ở
   đơn vị đó**. Cùng một vai trò, hai tổ khác nhau, kết quả khác nhau.

---

## Tài sản

**Việc này để làm gì.** Danh sách máy của Nhà máy, và mỗi máy nằm ở Đơn vị tổ chức nào.

**Ai thao tác được.**
Đọc: `MTN_ASSETS_DISPLAY` — supervisor, engineer, manager, quản trị viên.
Ghi: `MTN_ASSETS_CHANGE` — cùng bốn vai trò đó.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy**, rồi tìm theo **tên hoặc mã**. | | |
| 2 | Bấm **Thêm Tài sản**: **Mã**, **Tên**, **Kiểu**, **Mức trọng yếu**, và Đơn vị tổ chức nơi máy nằm. | **Mã Tài sản là duy nhất trên toàn Nền tảng**, không chỉ trong Nhà máy này. | Hai nhà máy dùng chung mã là máy chủ từ chối — và đó là điều đúng, vì lệnh công việc trỏ theo mã. |
| 3 | Đổi vị trí máy: bấm **Đổi Đơn vị tổ chức…**. | Vị trí **không** sửa trong hộp thoại **Sửa thông tin…**. | Sửa vị trí là một thao tác riêng vì nó quyết định ai được nêu và đóng công việc trên máy. |
| 4 | Máy lồng trong máy (một cụm có nhiều bộ phận): **Đặt dưới…** một máy khác. | **Tách ra** để bỏ quan hệ đó. | |
| 5 | Máy thanh lý: **Ngừng dùng**, xác nhận. | Máy được ghi **Đã ngừng dùng** chứ không bị xoá, và **Khôi phục** được. | Lịch sử công việc vẫn trỏ về máy đó. |
| 6 | Xem cả máy đã ngừng: bật **Hiện cả đã ngừng dùng**. | | |

**Điểm then chốt.** Đổi Đơn vị tổ chức của Tài sản **không** làm chuyển công việc
đã ghi nhận: chúng vẫn ở nơi chúng đã xảy ra. Chỉ công việc **mới** đi theo vị trí mới.

---

## Phụ tùng

**Việc này để làm gì.** Danh mục phụ tùng dùng chung cho mọi Nhà máy.

**Ai thao tác được.**
Đọc: `MTN_PARTS_DISPLAY` — supervisor, engineer, manager, quản trị viên.
Ghi: `MTN_PARTS_CHANGE` — **engineer, manager, quản trị viên. Không có supervisor.**

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm theo **mã phụ tùng hoặc mô tả**. | | |
| 2 | Bấm **Thêm phụ tùng**: **Mã phụ tùng**, **Mô tả**, **Đơn vị đo**. | **Đơn vị đo** quyết định số lượng ở mọi chỗ khác (nhập kho, xuất kho). | Chọn sai đơn vị đo là mọi con số tồn kho sai theo. |
| 3 | Sửa: **Điều chỉnh**. | | |

> **Điểm then chốt cho người đào tạo.** Đây là **chỗ duy nhất** trong nhóm Bảo trì
> mà một giám sát bị chặn trong khi một kỹ sư thì không. Nếu giám sát không thấy
> nút **Thêm phụ tùng**, đó không phải lỗi tài khoản — đó là thiết kế: thêm một
> mã phụ tùng mới là khai báo danh mục, không phải việc sàn.

---

## Kho

**Việc này để làm gì.** Những kệ chứa phụ tùng của Nhà máy, và trên mỗi kệ có gì.

**Ai thao tác được.**
Đọc: `MTN_STORES_DISPLAY` — supervisor trở lên.
Ghi: `MTN_STORES_CHANGE` — supervisor trở lên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm kho theo **tên hoặc mã**, bấm một kho để mở **Tồn kho**. | | |
| 2 | Trong Tồn kho, tìm phụ tùng theo **mã hoặc mô tả**. | Kệ trống hiện **Kệ trống** — đó là trạng thái hợp lệ, không phải lỗi. | |
| 3 | Nhập hàng về: bấm **Nhập kho**, chọn **Phụ tùng**, **Số lượng**, **Lý do**. | | |

**Điểm then chốt — đừng dạy sai.** **Xuất phụ tùng không làm ở màn hình Kho.** Nó
làm ở **Chi tiết Lệnh công việc → Xuất phụ tùng**, vì mỗi lần lấy hàng phải gắn với
một công việc.

> **Vì sao.** Gắn phụ tùng với Lệnh công việc là cách duy nhất Nền tảng biết phụ
> tùng nằm trong chi phí của công việc nào. Xuất kho "trắng" sẽ làm chi phí công
> việc thiếu vài món.

---

## Lệnh công việc

**Việc này để làm gì.** Công việc được tạo tại Nhà máy: làm gì, trên máy nào, ai
phụ trách.

**Ai thao tác được.**
Đọc: `MTN_WORK_ORDERS_DISPLAY` — supervisor trở lên.
Ghi (tạo, phân công, hoàn thành, huỷ): `MTN_WORK_ORDERS_CHANGE` — supervisor trở lên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm theo **nội dung, số lệnh công việc hoặc Thiết bị**; **Thu hẹp theo Đơn vị tổ chức** khi danh sách dài. | Thu hẹp theo đơn vị **bao gồm mọi đơn vị bên dưới** nó. | |
| 2 | Bấm **Tạo lệnh công việc**: **Tài sản**, **Nội dung**, **Loại công việc**, **Mức ưu tiên**, **Mô tả**. | **Mức ưu tiên 1 là khẩn cấp nhất**, 5 là ít nhất. | Đọc ngược thang này là lỗi phổ biến khi mới dùng. Ô chọn hiện số **kèm từ tiếng Anh** ("1 - Most urgent") — danh sách này chưa được dịch, nên đọc **số**, đừng đọc từ. |
| 3 | Bấm **Phân công** trên một dòng, hoặc **Phân công lại**. | Danh sách ứng viên tìm theo **tên, mã nhân viên, hoặc chứng nhận họ có**. | Đây là chỗ dùng tới Kỹ năng đã ghi nhận. |
| 4 | Người được phân công bấm **Bắt đầu** khi bắt tay vào việc. | | |
| 5 | Xong: **Hoàn thành**, ghi **Đã phát hiện gì**. | Phải ghi nội dung phát hiện — không hoàn thành "trắng". | Không có nội dung thì lần sau không ai biết đã sửa cái gì. |
| 6 | Không làm nữa: **Huỷ**, nêu **Vì sao huỷ** (không bắt buộc nhưng nên ghi). | | |
| 7 | Xem việc đã xong: bật **Hiện cả đã hoàn thành và đã huỷ**. | | |

**Điểm then chốt.** Danh sách mặc định **chỉ hiện việc đang mở**. Một lệnh vừa
hoàn thành **biến mất** khỏi danh sách — không phải mất dữ liệu.

---

## Chi tiết Lệnh công việc

**Việc này để làm gì.** Làm và ghi lại một việc: các bước, giờ công, phụ tùng,
chỉ số đồng hồ, và chi phí đến nay.

**Ai thao tác được.** Mang `MTN_WORK_ORDERS_DISPLAY` để đọc; ghi giờ công, xuất
phụ tùng, ghi chỉ số cần `MTN_WORK_ORDERS_CHANGE`.

**Đường dẫn.** `/work-orders/:id`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Các bước**. | Các bước được **sao từ Kế hoạch công việc** đã tạo ra lệnh này, **không sửa được** ở đây. | Muốn đổi cách làm thì sửa Kế hoạch, không sửa lệnh — lệnh là bản đã chụp. |
| 2 | Bấm **Ghi giờ công**: **Nhân viên**, **Bắt đầu lúc**, **Kết thúc lúc**, **Hoạt động**, **Ngoài giờ**, **Ghi chú**. | Giờ công đã ghi **nằm trong chi phí nhân công của nhà máy đã báo cáo** — không phải chi phí mới. | |
| 3 | Bấm **Xuất phụ tùng**: **Phụ tùng**, **Kho**, **Số lượng**, **Mã phụ tùng**, **Đơn giá**. | Phụ tùng **là** chi phí mới — thành phần duy nhất làm tăng chi phí bảo trì. | |
| 4 | Nếu Tài sản có đồng hồ đo: **Ghi chỉ số**. | | |
| 5 | Đọc **Chi phí đến nay** ở cuối. | | |

---

## Phân công Lệnh công việc

**Việc này để làm gì.** Chọn người làm một lệnh.

**Ai thao tác được.** `MTN_WORK_ORDERS_CHANGE` **và** quyền sửa trên Đơn vị tổ
chức của Tài sản.

**Đường dẫn.** `/work-orders/:id/assign`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Tìm trong ô **Tìm một người** theo **tên, mã nhân viên, hoặc chứng nhận họ có**. | Danh sách chỉ gồm người **đủ điều kiện theo phạm vi**; rỗng nghĩa là không có ai để giao. | |
| 2 | Bấm tên người. | | |

**Điểm then chốt.** Một người không hiện trong danh sách ứng viên **không phải** vì
Nền tảng "ghét" họ: hoặc họ không thuộc phạm vi, hoặc bộ lọc chứng nhận đang lọc họ
ra. Gõ mã nhân viên trực tiếp để chắc chắn.

---

## Hoàn thành Lệnh công việc

**Ai thao tác được.** `MTN_WORK_ORDERS_CHANGE`.

**Đường dẫn.** `/work-orders/:id/complete`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Ghi **Đã phát hiện gì**. | Đây là trường bắt buộc về mặt thực hành, không chỉ hình thức. | |
| 2 | Bấm **Hoàn thành Lệnh công việc này**. | | |

## Huỷ Lệnh công việc

**Ai thao tác được.** `MTN_WORK_ORDERS_CHANGE`. Đường dẫn `/work-orders/:id/cancel`.

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Ghi **Vì sao huỷ?**. | Huỷ **không** xoá lệnh — nó chuyển sang trạng thái đã huỷ và hiện khi bật lịch sử. | Giữ dấu việc đã được nêu. |
| 2 | Bấm **Huỷ Lệnh công việc này**, hoặc **Để mở** để quay ra. | | |

---

## Yêu cầu của tôi

**Việc này để làm gì.** Báo máy có vấn đề — việc **duy nhất** trong nhóm Bảo trì mà
mọi Tài khoản làm được.

**Ai thao tác được.** `MTN_REQUESTS_RAISE` — **mọi vai trò, kể cả người vận hành**.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Nêu một yêu cầu**: **Tài sản**, **Nội dung**, **Mô tả**, **Mức khẩn**. | Nếu máy đang dừng sản xuất, **bật ô "Sản xuất đang dừng ngay lúc này"**. | Ô đó là thứ đẩy yêu cầu lên đầu hàng chờ của bảo trì. Không bật thì yêu cầu xếp như mọi yêu cầu khác. |
| 2 | Bấm gửi. Yêu cầu nằm ở cột **Kết quả**. | | |
| 3 | Theo dõi **Kết quả** từng yêu cầu. | Ba kết quả có thể: **Đã thành Lệnh công việc {số}**, **Bị từ chối: {lý do}**, hoặc chờ. | Người nêu yêu cầu thấy được kết quả — không cần hỏi bảo trì. |

> **Điểm then chốt cho người đào tạo.** **Mức khẩn** bạn chọn **không** phải mức ưu
> tiên của Lệnh công việc. Người phân loại chọn **Mức ưu tiên** riêng khi chấp nhận.

---

## Hàng chờ phân loại

**Việc này để làm gì.** Quyết định mỗi Yêu cầu thành Lệnh công việc, bị từ chối,
hay là bản trùng.

**Ai thao tác được.** `MTN_REQUESTS_TRIAGE` — supervisor trở lên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc danh sách, chú ý cột **Mức khẩn** và dòng **Sản xuất đang dừng**. | Yêu cầu có "Sản xuất đang dừng" nên xử lý trước. | |
| 2 | Bấm **Chấp nhận**: chọn **Mức ưu tiên** cho Lệnh công việc sẽ sinh ra. | **Mức ưu tiên do bạn quyết định, không phải mức khẩn người báo chọn.** | Người báo nói "khẩn" cho mọi việc; người phân loại nhìn cả hàng chờ. |
| 3 | Hoặc **Từ chối**: ghi **Vì sao từ chối yêu cầu này?**. | Lý do từ chối đi về người đã nêu — nên viết câu người đó hiểu được. | |
| 4 | Yêu cầu trùng: **Đánh dấu trùng**, chọn **Yêu cầu nào được giữ lại**. | Bản bị đánh dấu trùng **rời hàng chờ**; bản giữ lại tiếp tục. | |

**Điểm then chốt.** **Chấp nhận là tạo Lệnh công việc.** Không có bước trung gian —
và không có cách hoàn tác. Nếu nghi ngờ, để yêu cầu chờ tiếp (nút **Để chờ tiếp**).

---

## Thời gian dừng máy

**Việc này để làm gì.** Máy nào đang không chạy, vì sao, và đã dừng bao lâu.

**Ai thao tác được.**
Đọc: `MTN_DOWNTIME_DISPLAY` — supervisor trở lên.
Ghi: `MTN_DOWNTIME_CHANGE` — supervisor trở lên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Báo máy hỏng**: **Tài sản**, **Bắt đầu lúc** (để trống = bây giờ), **Mô tả**. | Để trống **Bắt đầu lúc** nghĩa là tính từ lúc bấm — dùng khi bạn vừa phát hiện máy dừng. | Ghi lùi giờ là cách duy nhất tính đúng thời gian dừng đã xảy ra trước khi bạn tới. |
| 2 | **Phân loại** lần dừng: chọn **Lý do**, ghi **Mô tả** (bắt buộc), hoặc **Để chưa phân loại**. | Chưa phân loại được, nhưng **đừng để lâu** — chỉ số dừng máy theo lý do sẽ thiếu. | |
| 3 | Máy chạy lại: **Đóng**, ghi **Kết thúc lúc**. | Máy chủ tự tính thời gian đã dừng. | |
| 4 | Lọc theo **Tài sản, lý do hoặc mô tả**. | | |

**Điểm then chốt.** Hai thao tác **Phân loại** và **Đóng** là hai việc khác nhau.
Đóng mà chưa phân loại thì lần dừng đó không vào thống kê theo lý do.

---

## Lịch bảo trì định kỳ

**Việc này để làm gì.** Gắn một Kế hoạch công việc với một Tài sản để Nền tảng tự
tạo Lệnh công việc **trước khi** máy hỏng.

**Ai thao tác được.**
Đọc: `MTN_PM_SCHEDULES_DISPLAY` — supervisor trở lên.
Ghi: `MTN_PM_SCHEDULES_CHANGE` — supervisor trở lên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm lịch bảo trì định kỳ**: **Tài sản**, **Kế hoạch công việc**, **Chu kỳ tính theo**. | **Chu kỳ tính theo** có hai lựa chọn: **Thời gian đã trôi qua** (theo ngày) hoặc **Lượng sử dụng tích luỹ** (theo đồng hồ đo). | Chọn sai loại là lịch không bao giờ đến hạn. |
| 2 | Theo ngày: điền **Bao nhiêu ngày một lần**. Theo đồng hồ: chọn **Đồng hồ đo** rồi điền **Bao nhiêu lượng sử dụng tích luỹ một lần**. | Chỉ **đồng hồ đo tích luỹ** mới đặt được lịch. | Đồng hồ đo không tích luỹ (ví dụ nhiệt độ) không có "mỗi X một lần". |
| 3 | Điền **Tạo lệnh sớm bao nhiêu ngày**, **Mức ưu tiên**, **Ngày đến hạn đầu tiên**. | Để trống ngày đầu thì Nền tảng tính **một chu kỳ kể từ hôm nay**. | |
| 4 | Bấm **Lên lịch**. | | |

**Điểm then chốt.** **Tạo lệnh sớm bao nhiêu ngày** là thời gian chuẩn bị, không
phải chu kỳ. Đặt 7 nghĩa là lệnh công việc xuất hiện **7 ngày trước** hạn.

---

## Đồng hồ đo

**Việc này để làm gì.** Các chỉ số chạy của máy (giờ chạy, số lần đóng/mở) mà Lịch
bảo trì định kỳ có thể đến hạn theo.

**Ai thao tác được.**
Đọc: `MTN_METERS_DISPLAY` — supervisor trở lên.
Ghi: `MTN_METERS_CHANGE` — supervisor trở lên.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | **Định nghĩa đồng hồ đo**: **Tài sản**, **Mã**, **Tên**, **Loại đồng hồ đo**, **Đơn vị đo**. | Mã là cách đồng hồ được gọi **trên tài sản**, ví dụ `RUN-HRS`. | |
| 2 | **Ghi chỉ số**: điền **Đồng hồ đang chỉ bao nhiêu**, **Ghi chú**. | Ghi **đúng số trên mặt đồng hồ**, không tự cộng. | Nền tảng tự tính lượng tích luỹ. |
| 3 | Đồng hồ bị đặt lại về 0 hoặc thay mới: bật **Đồng hồ đã được đặt lại hoặc thay mới**, điền **Đồng hồ mới đang chỉ bao nhiêu**. | Nền tảng chuyển lượng tích luỹ sang phần bù để tổng không tụt. | Không bật ô này thì tổng sử dụng tụt về gần 0 và mọi lịch theo đồng hồ sai. |

**Điểm then chốt quan trọng nhất.** Chỉ số **luôn tăng**. Nếu bạn thấy mình đang
ghi một số nhỏ hơn lần trước, hoặc là bạn gõ nhầm, hoặc là đồng hồ đã đặt lại —
trường hợp thứ hai phải bật ô đặt lại.

---

## Kế hoạch công việc

**Việc này để làm gì.** Cách thực hiện mỗi công việc định kỳ: các bước và mỗi bước
yêu cầu gì. Lệnh công việc **đi theo** kế hoạch chứ không sửa kế hoạch.

**Ai thao tác được.** Chỉ quản trị viên: `MTN_JOB_PLANS_MAINTAIN`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Bấm **Thêm kế hoạch công việc**: **Mã**, **Tên**, **Mô tả**, **Loại công việc**, **Số giờ ước tính**, **Cần dừng máy**. | **Cần dừng máy** là thông tin người lập kế hoạch sản xuất cần — đừng bỏ trống cho nhanh. | |
| 2 | Bấm **Thêm bước** cho từng bước: **Hướng dẫn**, **Số giờ**, **Kỹ năng yêu cầu**, **Ghi chú an toàn**. | Bước được đánh số theo thứ tự thêm vào; **Xoá bước này** bỏ một bước. | |
| 3 | Bấm **Thêm kế hoạch**. | | |
| 4 | Ngừng dùng: **Ngừng kích hoạt**, và **Kích hoạt lại** khi cần. | Kế hoạch đã tạo lệnh công việc rồi vẫn ngừng được — các lệnh cũ không đổi. | |

---

## Bảng tóm tắt phần Bảo trì

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Nêu Yêu cầu, theo dõi Yêu cầu của tôi | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Xem Tài sản, Kho, Lệnh công việc, Dừng máy, Lịch, Đồng hồ | · | · | ✓ | ✓ | ✓ | ✓ |
| Thêm/sửa Tài sản, đổi vị trí, ngừng dùng | · | · | ✓ | ✓ | ✓ | ✓ |
| Tạo / phân công / hoàn thành / huỷ Lệnh công việc | · | · | ✓ | ✓ | ✓ | ✓ |
| Ghi giờ công, xuất phụ tùng, ghi chỉ số trên lệnh | · | · | ✓ | ✓ | ✓ | ✓ |
| Phân loại Hàng chờ, chấp nhận / từ chối Yêu cầu | · | · | ✓ | ✓ | ✓ | ✓ |
| Báo hỏng, phân loại và đóng lần dừng máy | · | · | ✓ | ✓ | ✓ | ✓ |
| Nhập kho | · | · | ✓ | ✓ | ✓ | ✓ |
| Lên lịch bảo trì định kỳ, định nghĩa Đồng hồ đo | · | · | ✓ | ✓ | ✓ | ✓ |
| **Thêm / sửa Phụ tùng** | · | · | **·** | ✓ | ✓ | ✓ |
| **Kế hoạch công việc** | · | · | · | · | · | ✓ |

(Ghi còn cần phạm vi Đơn vị tổ chức — xem
[README §1](README.md#1-sáu-vai-trò-và-cách-đọc-phần-ai-thao-tác-được).)
