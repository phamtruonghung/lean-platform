# 07 · Sản xuất

Nhóm **Sản xuất** có đúng một việc, nhưng nó là việc quan trọng nhất trong ngày trên
sàn: **bàn giao ca**. Ca trước nói cho ca sau biết điều gì khác so với bình thường,
và ca sau **xác nhận** là đã nghe.

**Một câu phải nói trước.** Nền tảng giữ **đúng một bản bàn giao cho mỗi Bộ phận, mỗi
lượt ca** — không phải mỗi người một bản. Nếu hai người cùng mở, họ đang sửa **cùng
một bản**.

---

## Bàn giao ca

**Việc này để làm gì.** Chọn một Bộ phận, xem các ca trong **ngày sản xuất**, và mở
bàn giao của từng ca.

**Ai thao tác được.**
Đọc: `PRD_HANDOVER_DISPLAY` — **mọi vai trò**.
Viết / gửi: `PRD_HANDOVER_WRITE`.
Xác nhận bản của ca trước: `PRD_HANDOVER_ACKNOWLEDGE`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Chọn **Nhà máy**, rồi chọn **Bộ phận** trong cây. | Cây Bộ phận là cây **Đơn vị tổ chức**; đây là chỗ Bàn giao ca dùng chung dữ liệu với nhóm Nhân sự. | |
| 2 | Chọn **Ngày sản xuất**. | **Ngày sản xuất** không phải ngày dương lịch — ca đêm thuộc về ngày sản xuất của nó. | Mở nhầm ngày là mở nhầm ca. |
| 3 | Đọc các dòng **Ca {bắt đầu}–{kết thúc}**, kèm **Bàn giao bởi {tên}** và những gì còn mở ở mốc chuyển ca. | **Không có ca nào được xếp** là câu trả lời đúng khi Bộ phận chưa có ca — không phải lỗi. | |
| 4 | Bấm vào một ca để mở **Bàn giao ca** của ca đó. | | |

**Điểm then chốt.** Một bản bàn giao đã **gửi** thì hiện **Chốt tại thời điểm gửi** —
số liệu bên trong **không đổi nữa**, kể cả khi sự cố bên dưới được sửa sau đó.

> **Vì sao.** Bàn giao là một lời tuyên bố tại một thời điểm. Nếu nó tự đổi theo dữ
> liệu về sau, không ai chứng minh được ca trước đã nói gì.

---

## Bàn giao của một ca

**Việc này để làm gì.** Điền bản bàn giao: máy nào đang chạy, điều gì khác thường,
việc gì còn mở, và ca sau phải để ý gì.

**Ai thao tác được.** Ghi: `PRD_HANDOVER_WRITE`. Đọc: `PRD_HANDOVER_DISPLAY`.

**Đường dẫn.** `/production/:orgUnitId/handover/:shiftInstanceId`.

**Các bước chính — theo đúng thứ tự trên màn hình**

| # | Phần | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- | --- |
| 1 | **Máy** | Mỗi Tài sản của Bộ phận là một dòng. Ghi **Trạng thái** (chạy / không chạy). | Máy không chạy: **bắt buộc nêu vì sao**. | Một dòng "không chạy" không có lý do là một dòng vô dụng cho ca sau. |
| 2 | **Máy** | Ghi **Chiều** và các số đang chạy nếu Bộ phận có. | Đây là **các số liệu ca đã chốt**. | |
| 3 | **Điểm thay đổi** | **Thêm điểm thay đổi**: điều gì khác, **Khác ở chỗ nào**, **Điều ca sau phải theo dõi**. | Ít nhất một điểm thay đổi, hoặc bấm xác nhận **Ca này không có điểm thay đổi**. | Không ai ghi gì thì ca sau không biết là "không có gì khác" hay "chưa ai điền". |
| 4 | **Hạng mục quan trọng** | Ghi các hạng mục quan trọng của ca. | | |
| 5 | **Hành động chuyển tiếp** | Mọi Hành động đang mở của Bộ phận đều phải **chuyển tiếp, giao lại, hoặc đóng**. | Đóng ngay tại đây được, với **Điều gì đã đóng nó**. | Đây là cơ chế để Hành động không bị bỏ quên qua ca. |
| 6 | **Bằng chứng bàn giao** | Bật **Đã đi kiểm tra chung** nếu hai ca đã cùng đi một vòng; **Lưu bằng chứng**. | | |
| 7 | **Gửi** | Bấm **Gửi bàn giao**. | Nút không bấm được khi còn phần bắt buộc chưa xong; câu **Chưa gửi được bản bàn giao này** nói thiếu gì. | |

**Điểm then chốt — câu này quan trọng nhất của cả nhóm.** **Hành động chuyển tiếp
không được bỏ trống.** Một Hành động đang mở mà không được chuyển tiếp, giao lại hay
đóng thì bản bàn giao **không gửi được**.

> **Vì sao.** Đó là lý do bản bàn giao tồn tại: không để việc gì rơi giữa hai ca.

**Sửa sau khi đã gửi.** Bản đã gửi thành **Phiên bản {n}**; sửa nó tạo **phiên bản
mới** và phải ghi **lý do sửa** (sai khác so với bàn giao chuẩn).

---

## Bảng của một Bộ phận

**Việc này để làm gì.** Nhìn cả ngày của một Bộ phận: mọi ca, bàn giao của mỗi ca, và
những gì còn mở ở từng mốc chuyển ca.

**Ai thao tác được.** Đọc `PRD_HANDOVER_DISPLAY`; xác nhận cần
`PRD_HANDOVER_ACKNOWLEDGE`.

**Đường dẫn.** `/production/:orgUnitId/board`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc các ca của ngày sản xuất, từ trên xuống. | | |
| 2 | Dòng **xác nhận {lúc} sau khi ca bắt đầu** cho biết ca sau đã nhận bàn giao **lúc nào**. | "xác nhận sau khi ca bắt đầu" là **cờ vàng**: bàn giao được nhận muộn. | Bàn giao nhận muộn nghĩa là có một khoảng thời gian ca sau chạy mà không biết điều gì khác thường. |
| 3 | Bấm **Thu gọn / Mở rộng** để xem gọn cả ngày. | | |

---

## Xác nhận bàn giao

**Việc này để làm gì.** Ca sau nói rõ: tôi đã đọc bàn giao của ca trước, và đây là
những gì tôi thấy.

**Ai thao tác được.** `PRD_HANDOVER_ACKNOWLEDGE` — **mọi vai trò**.

**Đường dẫn.** `/production/:orgUnitId/board/acknowledge/:handoverId`.

**Các bước chính**

| # | Bước | Điểm then chốt | Vì sao |
| --- | --- | --- | --- |
| 1 | Đọc **Điều ca sau phải theo dõi** của từng điểm thay đổi. | Ca trước khai **không có điểm thay đổi nào** thì màn hình nói rõ — bạn vẫn xác nhận được. | |
| 2 | Với mỗi lượt theo dõi, ghi **Mỗi lượt theo dõi cho thấy gì**, và chọn **Đã thấy**. | Bỏ trống = **Chưa trả lời**, không phải "không có gì". | Đây là bằng chứng bạn đã thực sự theo dõi, không chỉ bấm nút. |
| 3 | Ghi **Ghi chú về bàn giao** (không bắt buộc). | | |
| 4 | Bấm **Xác nhận bàn giao**. | Câu xác nhận nói rõ: **Bạn đang nhận {Bộ phận} và ca {…}**. | Đọc câu đó — sai ca là sai người nhận trách nhiệm. |

> **Điểm then chốt quan trọng nhất.** Xác nhận **không phải** thủ tục. Nó gắn tên
> bạn vào việc đã đọc bàn giao, tại một thời điểm. Một sự cố xảy ra sau đó mà bạn đã
> xác nhận "Đã thấy" là chuyện khác với một sự cố xảy ra mà bạn chưa đọc gì.

---

## Bảng tóm tắt phần Sản xuất

| Việc | Mọi vai trò | Người vận hành | Giám sát | Kỹ sư | Quản lý | Quản trị viên |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| Xem bảng Bộ phận, xem bàn giao | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Xác nhận bàn giao của ca trước | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Viết và gửi bàn giao của ca mình | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Toàn bộ ba mã quyền Sản xuất nằm trên cả sáu vai trò** — Sản xuất là nhóm mở nhất
trong Nền tảng. Cái chặn là **Đơn vị tổ chức**: bạn chỉ bàn giao được cho Bộ phận mà
Tài khoản của bạn nằm trong phạm vi.
