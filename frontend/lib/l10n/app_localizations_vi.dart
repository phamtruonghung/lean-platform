// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get shellBrand => 'Platform';

  @override
  String get shellSkipToContent => 'Chuyển tới nội dung';

  @override
  String get shellAccountMenu => 'Menu tài khoản';

  @override
  String get shellChangePassword => 'Đổi mật khẩu';

  @override
  String get shellDarkPalette => 'Giao diện tối';

  @override
  String get shellLightPalette => 'Giao diện sáng';

  @override
  String get shellSignOut => 'Đăng xuất';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get settingsDescription =>
      'Cách Nền tảng hiển thị và ngôn ngữ Nền tảng dùng.';

  @override
  String get settingsLanguage => 'Ngôn ngữ';

  @override
  String get settingsLanguageHelp =>
      'Áp dụng ngay cho toàn bộ Nền tảng và được ghi nhớ trên trình duyệt này.';

  @override
  String get settingsLanguageEnglish => 'Tiếng Anh';

  @override
  String get settingsLanguageVietnamese => 'Tiếng Việt';

  @override
  String get groupPeople => 'Nhân sự';

  @override
  String get groupMaintenance => 'Bảo trì';

  @override
  String get groupQuality => 'Chất lượng';

  @override
  String get groupActions => 'Hành động';

  @override
  String get groupSafety => 'An toàn';

  @override
  String get groupProduction => 'Sản xuất';

  @override
  String get groupInsights => 'Phân tích';

  @override
  String get groupAdministration => 'Quản trị';

  @override
  String get navHome => 'Trang chủ';

  @override
  String get navDirectory => 'Danh bạ';

  @override
  String get navJobRoles => 'Chức danh công việc';

  @override
  String get navSkills => 'Kỹ năng';

  @override
  String get navOrgUnits => 'Đơn vị tổ chức';

  @override
  String get navAttendance => 'Chấm công';

  @override
  String get navTraining => 'Đào tạo';

  @override
  String get navMySignature => 'Chữ ký của tôi';

  @override
  String get navLeaveRequests => 'Đơn xin nghỉ';

  @override
  String get navCostRates => 'Đơn giá giờ';

  @override
  String get navProductStandardCosts => 'Chi phí chuẩn sản phẩm';

  @override
  String get navAssets => 'Tài sản';

  @override
  String get navParts => 'Phụ tùng';

  @override
  String get navStores => 'Kho';

  @override
  String get navWorkOrders => 'Lệnh công việc';

  @override
  String get navMyRequests => 'Yêu cầu của tôi';

  @override
  String get navTriageQueue => 'Hàng chờ phân loại';

  @override
  String get navDowntime => 'Thời gian dừng máy';

  @override
  String get navPmSchedules => 'Lịch bảo trì định kỳ';

  @override
  String get navMeters => 'Đồng hồ đo';

  @override
  String get navJobPlans => 'Kế hoạch công việc';

  @override
  String get navTierBoard => 'Bảng phân cấp';

  @override
  String get navSkillCoverage => 'Độ phủ kỹ năng';

  @override
  String get navKpiCatalogue => 'Danh mục KPI';

  @override
  String get navKpiReview => 'Đánh giá KPI';

  @override
  String get navActionLog => 'Nhật ký hành động';

  @override
  String get navProducts => 'Sản phẩm';

  @override
  String get navDefectCodes => 'Mã lỗi';

  @override
  String get navNonConformances => 'Sản phẩm không phù hợp';

  @override
  String get navCapas => 'CAPA';

  @override
  String get navCustomers => 'Khách hàng';

  @override
  String get navCustomerComplaints => 'Khiếu nại khách hàng';

  @override
  String get navSlideShow => 'Trình chiếu';

  @override
  String get navSuppliers => 'Nhà cung cấp';

  @override
  String get navSupplierNcrs => 'NCR nhà cung cấp';

  @override
  String get navIncidents => 'Sự cố';

  @override
  String get navObservations => 'Quan sát';

  @override
  String get navInjuryTypes => 'Loại thương tích';

  @override
  String get navBodyParts => 'Bộ phận cơ thể';

  @override
  String get navShiftHandovers => 'Bàn giao ca';

  @override
  String get navApprovals => 'Phê duyệt';

  @override
  String get navAccounts => 'Tài khoản';

  @override
  String get navRoles => 'Vai trò';

  @override
  String get commonCancel => 'Huỷ';

  @override
  String get commonSaving => 'Đang lưu…';

  @override
  String get accountPasswordCurrent => 'Mật khẩu hiện tại';

  @override
  String get accountPasswordNew => 'Mật khẩu mới';

  @override
  String accountPasswordMinimum(int count) {
    return 'Ít nhất $count ký tự.';
  }

  @override
  String get accountPasswordCurrentRequired => 'Hãy nhập mật khẩu hiện tại.';

  @override
  String accountPasswordTooShort(int count) {
    return 'Mật khẩu mới phải có ít nhất $count ký tự.';
  }

  @override
  String get accountPasswordChanged => 'Mật khẩu của bạn đã được đổi.';

  @override
  String homeGreeting(String name) {
    return 'Chào $name';
  }

  @override
  String get homeNothingWaiting => 'Không có gì đang chờ bạn.';

  @override
  String get homeActionsUnavailable => 'Không đọc được Hành động của bạn';

  @override
  String get homeAssignedToYou => 'Được giao cho bạn';

  @override
  String get homeAssignedToYouCaption =>
      'Hành động đang mở mà bạn là người phụ trách';

  @override
  String get homeAccountNotLinked =>
      'Tài khoản của bạn chưa gắn với hồ sơ Nhân viên, nên không Hành động nào có thể giao cho bạn — hãy gắn ở mục Tài khoản';

  @override
  String get homeTrainingUnavailable =>
      'Không đọc được Đào tạo cần xác nhận của bạn';

  @override
  String get trainingToConfirm => 'Đào tạo cần xác nhận';

  @override
  String get homeTrainingToConfirmCaption =>
      'Bản ghi đào tạo gửi cho bạn mà bạn chưa trả lời';

  @override
  String get homeWorkOrdersUnavailable => 'Không đọc được lệnh công việc';

  @override
  String get homeOpenWorkOrders => 'Lệnh công việc đang mở';

  @override
  String get homeOpenWorkOrdersCaption => 'Đã tạo và chưa hoàn thành';

  @override
  String get homeAwaitingAssignment => 'Chờ phân công';

  @override
  String get homeAwaitingAssignmentScopedCaption =>
      'Trong các Đơn vị tổ chức được cấp cho bạn và mọi đơn vị bên dưới';

  @override
  String get homeAwaitingAssignmentCaption => 'Đang mở, chưa có người nhận';

  @override
  String get homeApprovalsUnavailable => 'Không đọc được Phê duyệt';

  @override
  String get accountsAwaitingApproval => 'Tài khoản chờ phê duyệt';

  @override
  String get homeAccountsAwaitingApprovalCaption => 'Đang chờ được chấp nhận';

  @override
  String get commonSite => 'Nhà máy';

  @override
  String get commonSummary => 'Nội dung';

  @override
  String get commonAsset => 'Tài sản';

  @override
  String get commonOrgUnit => 'Đơn vị tổ chức';

  @override
  String get commonStatus => 'Trạng thái';

  @override
  String get commonAssignee => 'Người phụ trách';

  @override
  String get commonActions => 'Thao tác';

  @override
  String get commonUnassigned => 'Chưa phân công';

  @override
  String get commonMoreActions => 'Thêm thao tác';

  @override
  String workOrdersCount(int count) {
    return '$count lệnh công việc';
  }

  @override
  String workOrdersCountNarrowed(String name) {
    return ', thu hẹp theo $name';
  }

  @override
  String get workOrdersCountHistory => ', gồm cả đã hoàn thành và đã huỷ';

  @override
  String get workOrdersUnavailableTitle => 'Không đọc được lệnh công việc';

  @override
  String get workOrdersDescription =>
      'Công việc được tạo tại Nhà máy này, gắn với Thiết bị nào và ai đang phụ trách.';

  @override
  String get workOrdersRaise => 'Tạo lệnh công việc';

  @override
  String get workOrdersNarrowToOrgUnit => 'Thu hẹp theo Đơn vị tổ chức';

  @override
  String workOrdersNarrowedTo(String name) {
    return 'Đã thu hẹp theo $name';
  }

  @override
  String get workOrdersShowWholeSite => 'Hiện lại toàn bộ Nhà máy';

  @override
  String get workOrdersShowHistory => 'Hiện cả đã hoàn thành và đã huỷ';

  @override
  String get workOrdersNarrowTitle => 'Thu hẹp danh sách';

  @override
  String get workOrdersNarrowDescription =>
      'Chọn Đơn vị tổ chức để thu hẹp danh sách. Mọi đơn vị bên dưới cũng được tính.';

  @override
  String get workOrdersTruncated =>
      'Có nhiều lệnh công việc hơn danh sách này hiển thị. Hãy thu hẹp theo Đơn vị tổ chức, hoặc tắt phần lịch sử, để xem phần còn lại.';

  @override
  String get workOrdersFilter => 'Lọc lệnh công việc';

  @override
  String get workOrdersFilterHelp =>
      'Theo nội dung, số lệnh công việc hoặc Thiết bị.';

  @override
  String get workOrdersNoMatch => 'Không có lệnh công việc nào khớp';

  @override
  String workOrdersNoMatchMessage(String term) {
    return 'Có công việc đang mở tại Nhà máy này, nhưng không việc nào khớp với “$term”. Hãy thử nội dung hoặc Thiết bị khác, hoặc xoá bộ lọc.';
  }

  @override
  String get workOrdersStart => 'Bắt đầu';

  @override
  String get workOrdersComplete => 'Hoàn thành';

  @override
  String get workOrdersNumberColumn => 'Số WO';

  @override
  String get workOrdersAssign => 'Phân công';

  @override
  String get workOrdersReassign => 'Phân công lại';

  @override
  String get workOrdersFilteredEmptyTitle => 'Không có lệnh công việc nào khớp';

  @override
  String workOrdersFilteredEmptyMessage(String name) {
    return 'Có công việc tại Nhà máy này, nhưng không việc nào được tạo tại $name hoặc bên dưới đơn vị đó.';
  }

  @override
  String workOrdersFilteredEmptyMessageOpen(String name) {
    return 'Có công việc tại Nhà máy này, nhưng không việc nào được tạo tại $name hoặc bên dưới đơn vị đó và còn đang mở.';
  }

  @override
  String get workOrdersThisOrgUnit => 'Đơn vị tổ chức này';

  @override
  String get workOrdersClearFilters => 'Xoá bộ lọc';

  @override
  String get workOrdersNoneExistTitle => 'Không có công việc tại Nhà máy này';

  @override
  String get workOrdersNoneOpenTitle =>
      'Không có công việc nào đang mở tại Nhà máy này';

  @override
  String get workOrdersNoneExistMessage =>
      'Chưa có việc nào được tạo trong các Đơn vị tổ chức bạn có thể thao tác. Hãy tạo một lệnh công việc, lệnh sẽ hiện ra ngay.';

  @override
  String get commonWorkType => 'Loại công việc';

  @override
  String get commonPriority => 'Mức ưu tiên';

  @override
  String commonHours(String hours) {
    return '$hours giờ';
  }

  @override
  String get commonNoCostRecorded => 'Chưa ghi nhận chi phí';

  @override
  String get workOrderUnavailableTitle => 'Không đọc được lệnh công việc này';

  @override
  String get workOrderBackToList => 'Về danh sách lệnh công việc';

  @override
  String get workOrderTitle => 'Lệnh công việc';

  @override
  String get workOrderTasksDescription =>
      'Các bước được sao từ Kế hoạch công việc đã tạo ra lệnh này.';

  @override
  String get workOrderBookLabour => 'Ghi giờ công';

  @override
  String get workOrderBookPart => 'Xuất phụ tùng';

  @override
  String get workOrderTasks => 'Các bước';

  @override
  String get workOrderNoTasks =>
      'Lệnh công việc này chưa có bước nào được sao vào.';

  @override
  String get workOrderCostSoFar => 'Chi phí đến nay';

  @override
  String get workOrderNoLabour => 'Chưa ghi giờ công nào.';

  @override
  String workOrderOvertime(String hours, String overtime) {
    return '$hours · $overtime ngoài giờ';
  }

  @override
  String get workOrderLabourNote =>
      'Giờ công đã ghi nằm trong chi phí nhân công của nhà máy đã báo cáo, không phải chi phí mới.';

  @override
  String workOrderOvertimeNote(String hours) {
    return '$hours trong đó là ngoài giờ.';
  }

  @override
  String get workOrderNoParts => 'Chưa lắp phụ tùng nào.';

  @override
  String get workOrderPartsNote =>
      'Phụ tùng là chi phí mới — thành phần duy nhất của bảo trì làm tăng chi phí.';

  @override
  String workOrderRequiresSkill(String name) {
    return 'Yêu cầu $name';
  }

  @override
  String get workOrderNoSkill => 'Không yêu cầu kỹ năng';

  @override
  String workOrderRecordsMeter(String name) {
    return 'Ghi chỉ số $name';
  }

  @override
  String workOrderReading(String value) {
    return 'Chỉ số $value';
  }

  @override
  String get workOrderRecordReading => 'Ghi chỉ số';

  @override
  String get requestsUnavailableTitle => 'Không đọc được các yêu cầu';

  @override
  String get requestsDescription =>
      'Các Yêu cầu đang chờ quyết định tại Nhà máy này. Chấp nhận một yêu cầu sẽ tạo lệnh công việc cho yêu cầu đó.';

  @override
  String get requestsFilter => 'Lọc yêu cầu';

  @override
  String get requestsFilterHelp => 'Theo mô tả, số yêu cầu hoặc Tài sản.';

  @override
  String get requestsNoMatch => 'Không có yêu cầu nào khớp';

  @override
  String requestsNoMatchMessage(String term) {
    return 'Có yêu cầu đang chờ tại Nhà máy này, nhưng không yêu cầu nào khớp với “$term”. Hãy thử mô tả hoặc Tài sản khác.';
  }

  @override
  String get requestsNumberColumn => 'Số yêu cầu';

  @override
  String get requestsRaisedBy => 'Người tạo';

  @override
  String get requestsRaisedDate => 'Ngày tạo';

  @override
  String get requestsUrgency => 'Mức khẩn';

  @override
  String get requestsProductionStopped => 'Sản xuất đang dừng';

  @override
  String get requestsAccept => 'Chấp nhận';

  @override
  String get requestsDecline => 'Từ chối';

  @override
  String get requestsMarkDuplicate => 'Đánh dấu trùng';

  @override
  String requestsRaisedByPerson(String name) {
    return 'Do $name tạo';
  }

  @override
  String get requestsNoneExistTitle => 'Không có gì đang chờ';

  @override
  String get requestsNoneExistMessage =>
      'Không có Yêu cầu nào đang chờ quyết định tại Nhà máy này.';

  @override
  String get downtimeDescription =>
      'Các máy đang không chạy tại Nhà máy này, lý do dừng và thời gian đã dừng.';

  @override
  String get downtimeUnavailableTitle => 'Không đọc được các lần dừng máy';

  @override
  String get downtimeReport => 'Báo máy hỏng';

  @override
  String get downtimeTruncated =>
      'Có nhiều lần dừng máy hơn danh sách này hiển thị.';

  @override
  String get downtimeFilter => 'Lọc thời gian dừng máy';

  @override
  String get downtimeFilterHelp => 'Theo Tài sản, lý do hoặc mô tả.';

  @override
  String get downtimeNoMatch => 'Không có lần dừng máy nào khớp';

  @override
  String downtimeNoMatchMessage(String term) {
    return 'Nhà máy này có ghi nhận thời gian dừng máy, nhưng không lần nào khớp với “$term”. Hãy thử Tài sản, lý do hoặc mô tả khác.';
  }

  @override
  String get downtimeStarted => 'Bắt đầu dừng';

  @override
  String get downtimeReason => 'Lý do';

  @override
  String get downtimeReportedByColumn => 'Người báo';

  @override
  String get downtimeClose => 'Đóng';

  @override
  String get downtimeClassify => 'Phân loại';

  @override
  String downtimeStartedAt(String instant) {
    return 'Bắt đầu $instant';
  }

  @override
  String downtimeReasonLine(String name) {
    return 'Lý do: $name';
  }

  @override
  String downtimeReportedByPerson(String name) {
    return 'Do $name báo';
  }

  @override
  String get downtimeNoneExistTitle => 'Không có máy nào đang dừng';

  @override
  String get downtimeNoneExistMessage =>
      'Không có máy nào được ghi nhận là đang dừng tại Nhà máy này.';

  @override
  String get commonDetails => 'Chi tiết';

  @override
  String get commonDescription => 'Mô tả';

  @override
  String get commonNow => 'bây giờ';

  @override
  String get metersDescription =>
      'Các chỉ số chạy mà lịch bảo trì định kỳ có thể đến hạn theo, và các lần ghi chỉ số cho chúng.';

  @override
  String get metersUnavailableTitle => 'Không đọc được các đồng hồ đo';

  @override
  String get metersDefine => 'Định nghĩa đồng hồ đo';

  @override
  String get metersFilter => 'Lọc đồng hồ đo';

  @override
  String get metersFilterHelp => 'Theo tên, mã hoặc Tài sản.';

  @override
  String get metersNoMatch => 'Không có đồng hồ đo nào khớp';

  @override
  String metersNoMatchMessage(String term) {
    return 'Nhà máy này có đồng hồ đo, nhưng không cái nào khớp với “$term”. Hãy thử tên, mã hoặc Tài sản khác.';
  }

  @override
  String get metersNoReading => 'Chưa có chỉ số';

  @override
  String get metersType => 'Loại';

  @override
  String get metersUnit => 'Đơn vị đo';

  @override
  String get metersLatestReading => 'Chỉ số mới nhất';

  @override
  String get metersAccumulated => 'Tổng sử dụng';

  @override
  String metersCarriedForward(String value, String unit) {
    return 'Chuyển tiếp: $value $unit';
  }

  @override
  String metersLatestLine(String label) {
    return 'Mới nhất: $label';
  }

  @override
  String metersAccumulatedLine(String label) {
    return 'Tổng sử dụng: $label';
  }

  @override
  String get metersNoneExistTitle => 'Chưa có đồng hồ đo';

  @override
  String get metersNoneExistMessage =>
      'Chưa có đồng hồ đo nào được định nghĩa trên Tài sản của Nhà máy này.';

  @override
  String get commonCode => 'Mã';

  @override
  String get commonName => 'Tên';

  @override
  String get jobPlansUnavailableTitle =>
      'Không đọc được các kế hoạch công việc';

  @override
  String get jobPlansDescription =>
      'Cách thực hiện mỗi công việc định kỳ — các bước cần làm và mỗi bước yêu cầu gì. Lệnh công việc đi theo kế hoạch chứ không sửa kế hoạch.';

  @override
  String get jobPlansAdd => 'Thêm kế hoạch công việc';

  @override
  String get jobPlansFilter => 'Lọc kế hoạch công việc';

  @override
  String get jobPlansFilterHelp => 'Theo tên, mã hoặc mô tả.';

  @override
  String get jobPlansNoMatch => 'Không có kế hoạch công việc nào khớp';

  @override
  String jobPlansNoMatchMessage(String term) {
    return 'Nhà máy có kế hoạch công việc, nhưng không kế hoạch nào khớp với “$term”. Hãy thử tên, mã hoặc mô tả khác.';
  }

  @override
  String get jobPlansPlanColumn => 'Kế hoạch';

  @override
  String get jobPlansSteps => 'Số bước';

  @override
  String get jobPlansEstimatedHours => 'Giờ ước tính';

  @override
  String get jobPlansShutdown => 'Dừng máy';

  @override
  String jobPlansStepCount(int count) {
    return '$count bước';
  }

  @override
  String get jobPlansInactive => 'Ngừng dùng';

  @override
  String get jobPlansRequiresShutdown => 'Cần dừng máy';

  @override
  String jobPlansAboutHours(String hours) {
    return 'Khoảng $hours giờ';
  }

  @override
  String get jobPlansNoSteps => 'Chưa ghi bước nào.';

  @override
  String get jobPlansDeactivate => 'Ngừng kích hoạt';

  @override
  String get jobPlansReactivate => 'Kích hoạt lại';

  @override
  String get jobPlansNoneExistTitle => 'Chưa có kế hoạch công việc';

  @override
  String get jobPlansNoneExistMessage =>
      'Chưa có kế hoạch công việc dùng lại được nào. Hãy thêm một kế hoạch, các bước của nó sẽ hiện ở đây.';

  @override
  String get pmSchedulesUnavailableTitle =>
      'Không đọc được các lịch bảo trì định kỳ';

  @override
  String get pmSchedulesDescription =>
      'Các kế hoạch công việc gắn với Tài sản của Nhà máy này, tự tạo lệnh công việc trước khi máy hỏng.';

  @override
  String get pmSchedulesAdd => 'Thêm lịch bảo trì định kỳ';

  @override
  String get pmSchedulesFilter => 'Lọc lịch bảo trì định kỳ';

  @override
  String get pmSchedulesFilterHelp =>
      'Theo tên lịch, Tài sản hoặc kế hoạch công việc.';

  @override
  String get pmSchedulesNoMatch => 'Không có lịch bảo trì định kỳ nào khớp';

  @override
  String pmSchedulesNoMatchMessage(String term) {
    return 'Nhà máy này có lịch bảo trì định kỳ, nhưng không lịch nào khớp với “$term”. Hãy thử tên, Tài sản hoặc kế hoạch công việc khác.';
  }

  @override
  String get pmSchedulesJobPlanColumn => 'Kế hoạch công việc';

  @override
  String get pmSchedulesInterval => 'Chu kỳ';

  @override
  String get pmSchedulesDue => 'Đến hạn';

  @override
  String get pmSchedulesRules => 'Quy tắc';

  @override
  String pmSchedulesRuleCount(int count) {
    return '$count quy tắc';
  }

  @override
  String pmSchedulesRollsFrom(String anchor) {
    return 'Tính từ $anchor';
  }

  @override
  String pmSchedulesLeadTime(int days) {
    return 'Tạo sớm $days ngày';
  }

  @override
  String pmSchedulesAccumulated(String current, String target) {
    return 'Đã tích lũy $current trên $target';
  }

  @override
  String pmSchedulesEveryMeter(String interval, String meter) {
    return 'Mỗi $interval của $meter';
  }

  @override
  String pmSchedulesEveryDays(int days) {
    return 'Mỗi $days ngày';
  }

  @override
  String get pmSchedulesTheMeter => 'đồng hồ đo';

  @override
  String pmSchedulesPriorityLine(String priority) {
    return 'Mức ưu tiên $priority';
  }

  @override
  String get pmSchedulesDueNow => 'Đến hạn ngay';

  @override
  String get pmSchedulesNoMeterTarget => 'Chưa có mốc đồng hồ đo';

  @override
  String pmSchedulesDueAt(String value) {
    return 'Đến hạn ở $value';
  }

  @override
  String get pmSchedulesNoDueDate => 'Chưa có ngày đến hạn';

  @override
  String pmSchedulesNextDue(String date) {
    return 'Đến hạn tiếp theo $date';
  }

  @override
  String pmSchedulesOverdueSince(String date) {
    return 'Quá hạn từ $date';
  }

  @override
  String get pmSchedulesDueToday => 'Đến hạn hôm nay';

  @override
  String pmSchedulesDueIn(String date, int days) {
    return 'Đến hạn $date (còn $days ngày)';
  }

  @override
  String get pmSchedulesNoneExistTitle => 'Chưa có lịch nào';

  @override
  String get pmSchedulesNoneExistMessage =>
      'Chưa có lịch bảo trì định kỳ nào được gắn với Tài sản của Nhà máy này.';

  @override
  String get titleSignIn => 'Đăng nhập';

  @override
  String get titleAwaitingApproval => 'Chờ phê duyệt';

  @override
  String get titleChooseNewPassword => 'Chọn mật khẩu mới';

  @override
  String get titleFloor => 'Xưởng';

  @override
  String get titleCapaReport => 'Báo cáo CAPA';

  @override
  String get titleTrainingRecordForm => 'Mẫu bản ghi đào tạo';

  @override
  String get titleWelcome => 'Chào mừng';

  @override
  String get titleEmployee => 'Nhân viên';

  @override
  String get titleWorkedHours => 'Giờ đã làm';

  @override
  String get titleAttendanceToConfirm => 'Chấm công cần xác nhận';

  @override
  String get titleAttendanceSheet => 'Bảng chấm công';

  @override
  String get titleTrainingRecords => 'Bản ghi đào tạo';

  @override
  String get titleTrainingRecord => 'Bản ghi đào tạo';

  @override
  String get titleQualitySlideShow => 'Trình chiếu chất lượng';

  @override
  String get titleCustomerComplaint => 'Khiếu nại khách hàng';

  @override
  String get titleSupplierNcr => 'NCR nhà cung cấp';

  @override
  String get titleNonConformance => 'Sản phẩm không phù hợp';

  @override
  String get titleShiftHandover => 'Bàn giao ca';

  @override
  String get titleSafetyIncidents => 'Sự cố an toàn';

  @override
  String get titleSafetyIncident => 'Sự cố an toàn';

  @override
  String get titleSafetyObservations => 'Quan sát an toàn';

  @override
  String get titleSafetyObservation => 'Quan sát an toàn';

  @override
  String get titleKpiTargets => 'Mục tiêu KPI';

  @override
  String get titleActions => 'Hành động';

  @override
  String get titleAction => 'Hành động';

  @override
  String get titleApprovalQueue => 'Hàng chờ phê duyệt';

  @override
  String get titleStoreStock => 'Tồn kho';

  @override
  String get commonTryAgain => 'Thử lại';

  @override
  String get commonAssetsFailed => 'Không đọc được danh sách tài sản.';

  @override
  String get commonJobPlan => 'Kế hoạch công việc';

  @override
  String get commonMeter => 'Đồng hồ đo';

  @override
  String get commonEmployee => 'Nhân viên';

  @override
  String get commonUnitOfMeasure => 'Đơn vị đo';

  @override
  String get commonQuantity => 'Số lượng';

  @override
  String get commonPart => 'Phụ tùng';

  @override
  String get commonStore => 'Kho';

  @override
  String get commonNoteOptional => 'Ghi chú (không bắt buộc)';

  @override
  String get commonPriorityMostUrgent => 'Khẩn cấp nhất';

  @override
  String get commonPriorityUrgent => 'Khẩn cấp';

  @override
  String get commonPriorityNormal => 'Bình thường';

  @override
  String get commonPriorityLow => 'Thấp';

  @override
  String get commonPriorityLeastUrgent => 'Ít khẩn cấp nhất';

  @override
  String get pmScheduleFormTitle => 'Lên lịch bảo trì định kỳ';

  @override
  String get pmScheduleFormSubmit => 'Lên lịch';

  @override
  String get pmScheduleFormBasisField => 'Chu kỳ tính theo';

  @override
  String get pmScheduleFormBasisElapsed => 'Thời gian đã trôi qua';

  @override
  String get pmScheduleFormBasisAccumulated => 'Lượng sử dụng tích luỹ';

  @override
  String get pmScheduleFormEveryDays => 'Bao nhiêu ngày một lần';

  @override
  String get pmScheduleFormEveryAccumulated =>
      'Bao nhiêu lượng sử dụng tích luỹ một lần';

  @override
  String get pmScheduleFormMeterNotChosen =>
      'Hãy chọn một đồng hồ đo tích luỹ trước.';

  @override
  String pmScheduleFormMeterIntervalHelp(String uom) {
    return 'Tính bằng $uom, một chu kỳ sau mốc hiện tại của đồng hồ.';
  }

  @override
  String get pmScheduleFormAnchor => 'Chu kỳ tính từ mốc';

  @override
  String get pmScheduleFormLeadTime => 'Tạo lệnh sớm bao nhiêu ngày';

  @override
  String get pmScheduleFormPriorityMostUrgent => '1 — khẩn cấp nhất';

  @override
  String get pmScheduleFormPriorityLeastUrgent => '5 — ít khẩn cấp nhất';

  @override
  String get pmScheduleFormFirstDue => 'Ngày đến hạn đầu tiên (không bắt buộc)';

  @override
  String get pmScheduleFormFirstDueHelp =>
      'Để trống thì ngày đến hạn đầu tiên là một chu kỳ kể từ hôm nay.';

  @override
  String get pmScheduleFormJobPlansFailed =>
      'Không đọc được danh mục kế hoạch công việc.';

  @override
  String get pmScheduleFormMetersFailed =>
      'Không đọc được danh sách đồng hồ đo.';

  @override
  String get pmScheduleFormMeterHelp =>
      'Chỉ đồng hồ đo tích luỹ mới đặt được lịch.';

  @override
  String get jobPlanFormSubmit => 'Thêm kế hoạch';

  @override
  String get jobPlanFormWorkType => 'Loại công việc';

  @override
  String get jobPlanFormDescriptionOptional => 'Mô tả (không bắt buộc)';

  @override
  String get jobPlanFormEstimatedHoursOptional =>
      'Số giờ ước tính (không bắt buộc)';

  @override
  String get jobPlanFormRequiresShutdown => 'Cần dừng máy';

  @override
  String get jobPlanFormSafetyNoteOptional =>
      'Ghi chú an toàn (không bắt buộc)';

  @override
  String get jobPlanFormAddStep => 'Thêm bước';

  @override
  String get jobPlanFormSkillsFailed => 'Không đọc được danh mục kỹ năng.';

  @override
  String get jobPlanFormStep => 'Bước';

  @override
  String get jobPlanFormInstruction => 'Hướng dẫn';

  @override
  String get jobPlanFormRemoveStep => 'Xoá bước này';

  @override
  String get jobPlanFormRequiredSkill => 'Kỹ năng yêu cầu (không bắt buộc)';

  @override
  String get jobPlanFormHoursOptional => 'Số giờ (không bắt buộc)';

  @override
  String get meterFormSubmit => 'Khai báo';

  @override
  String get meterFormCodeHelp =>
      'Cách đồng hồ đo này được gọi trên tài sản, ví dụ RUN-HRS.';

  @override
  String get meterFormType => 'Loại đồng hồ đo';

  @override
  String get meterFormUomFailed => 'Không đọc được danh sách đơn vị đo.';

  @override
  String readingFormTitle(String meter) {
    return 'Ghi chỉ số cho $meter';
  }

  @override
  String get readingFormSubmitRollover => 'Ghi đặt lại';

  @override
  String get readingFormSubmit => 'Ghi chỉ số';

  @override
  String readingFormAccumulatedSoFar(String value) {
    return 'Lượng sử dụng tích luỹ đến nay: $value';
  }

  @override
  String get readingFormNewCounterReads => 'Đồng hồ mới đang chỉ bao nhiêu';

  @override
  String get readingFormCounterReads => 'Đồng hồ đang chỉ bao nhiêu';

  @override
  String get readingFormRolloverHelp =>
      'Lượng sử dụng tích luỹ được chuyển sang phần bù; đồng hồ mới thường đang chỉ 0.';

  @override
  String readingFormReadingHelp(String uom) {
    return 'Tính bằng $uom, đúng như chỉ số trên đồng hồ.';
  }

  @override
  String get readingFormRolloverTitle =>
      'Đồng hồ đã được đặt lại hoặc thay mới';

  @override
  String get readingFormRolloverSubtitle =>
      'Chuyển lượng sử dụng tích luỹ sang phần bù và ghi đây là mốc bắt đầu của đồng hồ mới.';

  @override
  String requestAcceptTitle(String requestNo) {
    return 'Chấp nhận $requestNo?';
  }

  @override
  String get requestAcceptDismiss => 'Để chờ tiếp';

  @override
  String get requestAcceptSubmit => 'Chấp nhận yêu cầu này';

  @override
  String get requestAcceptBody =>
      'Chấp nhận sẽ tạo một lệnh công việc cho yêu cầu này. Mức ưu tiên do bạn quyết định, không phải mức khẩn mà người báo cáo chọn.';

  @override
  String requestDeclineTitle(String requestNo) {
    return 'Từ chối $requestNo?';
  }

  @override
  String get requestDeclineReason => 'Vì sao từ chối yêu cầu này?';

  @override
  String get requestDeclineSubmit => 'Từ chối yêu cầu này';

  @override
  String get requestDuplicateTitle => 'Đánh dấu là trùng lặp';

  @override
  String get requestDuplicateDismiss => 'Giữ riêng';

  @override
  String get requestDuplicateNone =>
      'Không có yêu cầu nào khác đang mở để yêu cầu này trùng vào.';

  @override
  String requestDuplicateWhich(String requestNo) {
    return 'Yêu cầu nào được giữ lại? $requestNo sẽ rời hàng chờ.';
  }

  @override
  String get labourBookingTitle => 'Ghi giờ công';

  @override
  String get labourBookingActivity => 'Hoạt động';

  @override
  String get labourBookingStartedAt => 'Bắt đầu lúc';

  @override
  String get labourBookingEndedAt => 'Kết thúc lúc';

  @override
  String get labourBookingOvertime => 'Ngoài giờ';

  @override
  String get labourBookingEmployeesFailed =>
      'Không đọc được danh sách nhân viên.';

  @override
  String get partBookingTitle => 'Xuất phụ tùng';

  @override
  String get partBookingSubmit => 'Xuất phụ tùng';

  @override
  String get partBookingSourced => 'Nguồn';

  @override
  String get partBookingOptionsFailed => 'Không đọc được các lựa chọn.';

  @override
  String get partBookingPartNoOptional => 'Mã phụ tùng (không bắt buộc)';

  @override
  String get partBookingUnitCostOptional => 'Đơn giá (không bắt buộc)';

  @override
  String get nonconformancesUnavailableTitle =>
      'Không đọc được sổ không phù hợp';

  @override
  String get nonconformancesNoSiteTitle => 'Chưa có nhà máy để hiển thị';

  @override
  String get nonconformancesNoSiteMessage =>
      'Tài khoản của bạn chưa thấy nhà máy nào nên chưa có gì để đọc ở đây.';

  @override
  String get nonconformancesDescription =>
      'Những gì không đạt chuẩn tại nhà máy này, phát hiện ở đâu và số lượng bao nhiêu.';

  @override
  String get nonconformanceRecord => 'Ghi nhận không phù hợp';

  @override
  String get commonAllOrgUnits => 'Tất cả đơn vị';

  @override
  String get nonconformancesAnyStatus => 'Mọi trạng thái';

  @override
  String get commonDefectCode => 'Mã lỗi';

  @override
  String get nonconformancesEveryDefectCode => 'Mọi mã lỗi';

  @override
  String get commonProduct => 'Sản phẩm';

  @override
  String get nonconformancesEveryProduct => 'Mọi sản phẩm';

  @override
  String get nonconformancesSeverity => 'Mức độ';

  @override
  String get nonconformancesAnySeverity => 'Mọi mức độ';

  @override
  String get nonconformancesDetectedFrom => 'Phát hiện từ ngày';

  @override
  String get nonconformancesDetectedTo => 'Phát hiện đến ngày';

  @override
  String get nonconformancesTruncated =>
      'Còn nhiều không phù hợp hơn danh sách này hiển thị. Hãy thu hẹp theo đơn vị, theo trạng thái hoặc theo ngày để xem phần còn lại.';

  @override
  String get nonconformancesNoMatchTitle =>
      'Không có bản ghi nào khớp bộ lọc này';

  @override
  String get nonconformancesNoMatchMessage =>
      'Sổ có không phù hợp, nhưng không bản ghi nào thuộc khu vực, trạng thái, mã lỗi, sản phẩm, mức độ hay khoảng ngày bạn chọn.';

  @override
  String get nonconformancesClearTheFilters => 'Xoá bộ lọc';

  @override
  String get nonconformancesNoneExistTitle => 'Chưa phát hiện gì không phù hợp';

  @override
  String get nonconformancesNoneExistMessage =>
      'Chưa có không phù hợp nào được ghi nhận tại nhà máy này.';

  @override
  String get nonconformancesNumberColumn => 'Không phù hợp';

  @override
  String get nonconformancesFoundColumn => 'Phát hiện gì';

  @override
  String get commonState => 'Trạng thái';

  @override
  String get nonconformancesFiledColumn => 'Đã ghi nhận';

  @override
  String get commonOpen => 'Mở';

  @override
  String nonconformanceQuantityAffected(String count, String uom) {
    return '$count $uom bị ảnh hưởng';
  }

  @override
  String nonconformanceQuantityRaised(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'đã tăng $count lần',
      one: 'đã tăng 1 lần',
    );
    return '$_temp0';
  }

  @override
  String nonconformanceFiledAgainst(String orgUnit, String against) {
    return '$orgUnit · ghi nhận cho $against';
  }

  @override
  String get nonconformanceFormRecord => 'Ghi nhận';

  @override
  String get nonconformanceFormProductHelp => 'Sản phẩm không phù hợp là gì.';

  @override
  String get nonconformanceFormDefectCodeHelp =>
      'Sai ở chỗ nào. Mức độ bắt đầu từ giá trị mặc định của mã lỗi này.';

  @override
  String get nonconformanceFormChooseCode => 'Chọn một mã';

  @override
  String get nonconformanceFormDetectionPoint => 'Điểm phát hiện';

  @override
  String get nonconformanceFormDetectionPointHelp =>
      'Nơi kế hoạch kiểm soát bắt được lỗi.';

  @override
  String get nonconformanceFormChoosePoint => 'Chọn một điểm';

  @override
  String get nonconformanceFormSeverityHelpUnset => 'Được chọn cùng mã lỗi.';

  @override
  String nonconformanceFormSeverityHelpSet(String severity) {
    return 'Bắt đầu từ $severity. Có thể nâng lên; hạ xuống là một quyết định về sau.';
  }

  @override
  String get nonconformanceFormChooseCodeFirst => 'Chọn mã lỗi trước';

  @override
  String nonconformanceFormStartsAt(String severity) {
    return 'Bắt đầu từ $severity';
  }

  @override
  String get nonconformanceFormQuantityHelp => 'Bao nhiêu chiếc.';

  @override
  String get nonconformanceFormLotRef => 'Tham chiếu lô (không bắt buộc)';

  @override
  String get nonconformanceFormLotRefHelp =>
      'Còn gì bị ảnh hưởng — có số lô vẫn hơn là không.';

  @override
  String get nonconformanceFormAssetOptional => 'Tài sản (không bắt buộc)';

  @override
  String get nonconformanceFormAssetHelp =>
      'Máy nào, nếu phát hiện trên máy. Máy đó phải thuộc đơn vị này.';

  @override
  String get nonconformanceFormDetailOptional => 'Chi tiết (không bắt buộc)';

  @override
  String get nonconformanceFormContainment =>
      'Ngăn chặn tức thời (không bắt buộc)';

  @override
  String get nonconformanceFormContainmentHelp =>
      'Đã làm gì ngay lúc đó. Ghi lại thì bản ghi này được coi là đã ngăn chặn.';

  @override
  String get nonconformanceFormDetectedAt => 'Phát hiện lúc (không bắt buộc)';

  @override
  String get nonconformanceFormDetectedAtHelp =>
      'Thời điểm phát hiện, nếu không phải bây giờ. Đây là căn cứ quyết định ngày sản xuất và ca mà bản ghi thuộc về.';

  @override
  String get nonconformanceFormWhereFound => 'Phát hiện ở đâu';

  @override
  String get nonconformanceFormWhereFoundHelp =>
      'Chọn đơn vị nơi phát hiện sản phẩm không phù hợp. Đây là căn cứ quyết định ai được xử lý bản ghi này.';

  @override
  String nonconformanceFormWillBeRecorded(String orgUnit) {
    return 'Không phù hợp này sẽ được ghi nhận tại $orgUnit.';
  }

  @override
  String get nonconformanceFloorIntro =>
      'Phát hiện gì không phù hợp? Những trường có danh sách cố định đều chọn từ dữ liệu thiết bị này thấy được.';

  @override
  String get nonconformanceFloorChooseProduct => 'Chọn một sản phẩm';

  @override
  String get nonconformanceFloorDetectedAt => 'Phát hiện lúc';

  @override
  String nonconformanceFloorStartsAt(String severity) {
    return 'Bắt đầu từ $severity — mức độ mặc định của mã lỗi này.';
  }

  @override
  String get nonconformanceFloorHowMuch => 'Số lượng bao nhiêu';

  @override
  String get nonconformanceFloorLot => 'Số lô (nếu có)';

  @override
  String get nonconformanceFloorWhatDidYouSee => 'Bạn đã thấy gì?';

  @override
  String get nonconformanceFloorWhoFound =>
      'Ai phát hiện? Mã nhân viên và PIN chỉ dùng để nhận diện bạn cho bản ghi này — bản ghi được ghi nhận là phát hiện của bạn.';

  @override
  String get nonconformanceFloorEmployeeNumber => 'Mã nhân viên';

  @override
  String get nonconformanceFloorPin => 'PIN';

  @override
  String get nonconformanceTitle => 'Không phù hợp';

  @override
  String get nonconformanceDetailMissingTitle => 'Không có không phù hợp này';

  @override
  String get nonconformanceDetailMissingMessage =>
      'Không có bản ghi nào ở địa chỉ này. Có thể bản ghi đã bị xoá hoặc địa chỉ bị sai.';

  @override
  String get nonconformanceDetailBack => 'Về sổ không phù hợp';

  @override
  String get nonconformanceDetailUnavailableTitle =>
      'Không đọc được không phù hợp này';

  @override
  String nonconformanceDetailSeverityChip(String severity) {
    return 'Mức độ $severity';
  }

  @override
  String nonconformanceDetailFinishedAt(String date) {
    return 'Kết thúc $date';
  }

  @override
  String get nonconformanceDetailDetail => 'Chi tiết';

  @override
  String get nonconformanceDetailQuantityAffected => 'Số lượng bị ảnh hưởng';

  @override
  String get nonconformanceDetailFiledAgainst => 'Ghi nhận cho';

  @override
  String get commonNoneGiven => 'Không có';

  @override
  String get commonNoneNamed => 'Không nêu';

  @override
  String get commonNotGiven => 'Không có';

  @override
  String get commonNotRecorded => 'Chưa ghi nhận';

  @override
  String get commonNoneRecorded => 'Chưa ghi nhận gì';

  @override
  String get nonconformanceDetailLotRef => 'Tham chiếu lô';

  @override
  String get nonconformanceDetailContainment => 'Ngăn chặn tức thời';

  @override
  String nonconformanceDetailDefectCodeValue(
    String name,
    String code,
    String severity,
  ) {
    return '$name · $code · bắt đầu từ $severity';
  }

  @override
  String get nonconformanceDetailActionsSection => 'Có thể làm gì';

  @override
  String get nonconformanceIncreaseQuantity => 'Tăng số lượng';

  @override
  String get nonconformanceUpdate => 'Nâng mức độ hoặc ngăn chặn';

  @override
  String get nonconformanceDisposition => 'Ghi nhận phương án xử lý';

  @override
  String get nonconformanceConcession => 'Cho phép nhượng bộ';

  @override
  String get nonconformanceLowerSeverity => 'Hạ mức độ';

  @override
  String get nonconformanceReopen => 'Mở lại';

  @override
  String get nonconformanceCancel => 'Huỷ vì ghi nhầm';

  @override
  String get nonconformanceDetailQuantityHistory => 'Lịch sử số lượng';

  @override
  String get nonconformanceDetailQuantityHistoryNote =>
      'Phân loại có thể phát hiện nhiều hơn con số ban đầu. Mọi thay đổi đều được lưu, và số lượng bị ảnh hưởng không bao giờ giảm.';

  @override
  String get nonconformanceDetailNoQuantityHistory =>
      'Số lượng bị ảnh hưởng chưa thay đổi kể từ khi được ghi nhận.';

  @override
  String get nonconformanceDetailDispositions => 'Phương án xử lý';

  @override
  String get nonconformanceDetailDispositionsNote =>
      'Sản phẩm được xử lý theo từng phần. Không phù hợp sẽ tự đóng khi toàn bộ số lượng đã có phương án xử lý.';

  @override
  String nonconformanceDetailDispositioned(
    String done,
    String total,
    String uom,
  ) {
    return '$done/$total $uom đã có phương án xử lý';
  }

  @override
  String get nonconformanceDetailNoDispositions =>
      'Chưa có quyết định nào về sản phẩm này.';

  @override
  String nonconformanceDetailReworkMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count phút làm lại',
      one: '1 phút làm lại',
    );
    return '$_temp0';
  }

  @override
  String get nonconformanceDetailCorrections => 'Chỉnh sửa';

  @override
  String get nonconformanceDetailCorrectionsNote =>
      'Những gì người có thẩm quyền Chất lượng đã thay đổi trên bản ghi này, và vì sao.';

  @override
  String get nonconformanceDetailNoCorrections =>
      'Bản ghi này chưa được chỉnh sửa.';

  @override
  String get nonconformanceDetailCause => 'Nguyên nhân';

  @override
  String get nonconformanceDetailCauseNote =>
      'Sản phẩm không phù hợp được xử lý ở đây; vấn đề phía sau được giải quyết trong nhật ký hành động, dưới dạng Concern. Một vấn đề xuất hiện nhiều lần vẫn chỉ là một Concern.';

  @override
  String get nonconformanceDetailNoConcerns =>
      'Chưa có gì được làm về nguyên nhân.';

  @override
  String get nonconformanceDetailRaisedFrom => 'được nêu từ bản ghi này';

  @override
  String get nonconformanceDetailOverdue => 'quá hạn';

  @override
  String get nonconformanceRaiseConcern => 'Nêu một Concern';

  @override
  String get nonconformanceLinkConcern => 'Liên kết với một Concern';

  @override
  String get commonNoSiteTitle => 'Chưa có nhà máy để hiển thị';

  @override
  String get commonNoSiteMessage =>
      'Tài khoản của bạn chưa thấy nhà máy nào nên chưa có gì để đọc ở đây.';

  @override
  String commonFiledAgainst(String orgUnit, String against) {
    return '$orgUnit · ghi nhận cho $against';
  }

  @override
  String get commonFiledAgainstColumn => 'Ghi nhận cho';

  @override
  String get commonAny => 'Tất cả';

  @override
  String get commonType => 'Loại';

  @override
  String get commonCategory => 'Hạng mục';

  @override
  String get commonAction => 'Hành động';

  @override
  String get commonSeverity => 'Mức độ';

  @override
  String get safetyIncidentsUnavailableTitle =>
      'Không đọc được sổ sự cố an toàn';

  @override
  String get safetyIncidentsDescription =>
      'Đã xảy ra chuyện gì tại nhà máy này, ở đâu, và nằm ở mức nào trên thang mức độ.';

  @override
  String get safetyIncidentRecord => 'Ghi nhận sự cố an toàn';

  @override
  String get safetyIncidentType => 'Loại sự cố';

  @override
  String get safetyRecordable => 'Phải khai báo';

  @override
  String get safetyNotRecordable => 'Không phải khai báo';

  @override
  String get safetyOccurredFrom => 'Xảy ra từ ngày';

  @override
  String get safetyOccurredTo => 'Xảy ra đến ngày';

  @override
  String get safetyIncidentsTruncated =>
      'Còn nhiều sự cố an toàn hơn danh sách này hiển thị. Hãy thu hẹp theo đơn vị, theo trạng thái hoặc theo ngày để xem phần còn lại.';

  @override
  String get safetyIncidentsNoMatchMessage =>
      'Sổ có sự cố an toàn, nhưng không sự cố nào thuộc khu vực, trạng thái, loại, mức độ, khả năng khai báo hay khoảng ngày bạn chọn.';

  @override
  String get safetyIncidentsNoneTitle =>
      'Không có sự cố nào được ghi nhận trong kỳ này';

  @override
  String get safetyIncidentsNoneMessage =>
      'Chưa có sự cố an toàn nào được ghi nhận tại nhà máy này trong khu vực và khoảng ngày đang hiển thị.';

  @override
  String get safetyIncidentNumberColumn => 'Số sự cố';

  @override
  String get safetyObservationsUnavailableTitle =>
      'Không đọc được sổ quan sát an toàn';

  @override
  String get safetyObservationsDescription =>
      'Những gì được thấy trước khi có chuyện xảy ra, xếp từ nặng nhất theo hậu quả xấu nhất có thể hình dung được.';

  @override
  String get safetyObservationRecord => 'Ghi nhận quan sát';

  @override
  String get safetyAnyType => 'Mọi loại';

  @override
  String get safetyAnyCategory => 'Mọi hạng mục';

  @override
  String get safetySeverityPotential => 'Mức độ tiềm ẩn';

  @override
  String get safetyAnyPotential => 'Mọi mức tiềm ẩn';

  @override
  String get safetyStopWork => 'Dừng việc';

  @override
  String get safetyStopWorkOnly => 'Chỉ loại dừng việc';

  @override
  String get safetyNotStopWork => 'Không phải dừng việc';

  @override
  String get safetyNoActionRaised => 'Chưa nêu hành động';

  @override
  String get safetyActionRaised => 'Đã nêu hành động';

  @override
  String get safetyObservedFrom => 'Quan sát từ ngày';

  @override
  String get safetyObservedTo => 'Quan sát đến ngày';

  @override
  String get safetyObservationsTruncated =>
      'Còn nhiều quan sát an toàn hơn danh sách này hiển thị. Hãy thu hẹp theo đơn vị, theo loại hoặc theo ngày để xem phần còn lại.';

  @override
  String get safetyObservationsNoMatchMessage =>
      'Sổ có quan sát an toàn, nhưng không quan sát nào thuộc khu vực, loại, hạng mục, mức tiềm ẩn, dừng việc hay khoảng ngày bạn chọn.';

  @override
  String get safetyObservationsNoneTitle =>
      'Không có quan sát nào được ghi nhận. Chỉ số dẫn dắt đang trống.';

  @override
  String get safetyObservationsNoneMessage =>
      'Chưa có quan sát an toàn nào được ghi nhận tại nhà máy này trong khu vực và khoảng ngày đang hiển thị.';

  @override
  String get safetyPotentialColumn => 'Mức tiềm ẩn';

  @override
  String get safetyIncidentReport => 'Báo sự cố an toàn';

  @override
  String get safetyReportSubmit => 'Báo cáo';

  @override
  String get safetyIncidentFloorIntro =>
      'Đã xảy ra chuyện gì? Những trường có danh sách cố định đều được chọn từ danh sách.';

  @override
  String get safetyWhatHappened => 'Đã xảy ra chuyện gì';

  @override
  String get safetyImmediateAction => 'Hành động tức thời (không bắt buộc)';

  @override
  String get safetyOccurredAt => 'Xảy ra lúc';

  @override
  String get safetyIncidentFloorWho =>
      'Ai đang báo cáo? Mã nhân viên và PIN chỉ dùng để nhận diện bạn cho bản ghi này — bản ghi được ghi nhận là báo cáo của bạn.';

  @override
  String get safetyObservationRecordTitle => 'Ghi nhận quan sát an toàn';

  @override
  String get safetyObservationFloorIntro =>
      'Đã thấy gì? Những trường có danh sách cố định đều được chọn từ danh sách.';

  @override
  String get safetyWhatWasSeen => 'Đã thấy gì';

  @override
  String get safetyActionTaken => 'Hành động đã làm (không bắt buộc)';

  @override
  String get safetyStopWorkExercised => 'Đã dùng quyền dừng việc';

  @override
  String get safetyObservationFloorWho =>
      'Ai đang ghi nhận? Mã nhân viên và PIN chỉ dùng để nhận diện bạn cho bản ghi này.';

  @override
  String get commonBack => 'Quay lại';

  @override
  String get routerLeaveNotDecidable =>
      'Đơn xin nghỉ này không phải đơn bạn được quyết định.';

  @override
  String get routerLeaveNotCancellable => 'Đơn xin nghỉ này không thể huỷ.';

  @override
  String get routerNotAMeasure => 'Đây không phải một biện pháp';

  @override
  String get routerNotAMeasureBody =>
      'Một biện pháp là hành động ngăn chặn, hành động đối phó hoặc hành động phòng ngừa.';

  @override
  String get routerBackToAction => 'Về hành động';

  @override
  String get routerCannotDoThatHere => 'Bạn không thể làm việc này ở đây';

  @override
  String get routerNoWriteGrant =>
      'Bạn không có quyền ghi nào tại nhà máy này.';

  @override
  String get routerBackToList => 'Về danh sách';

  @override
  String get cameraScanButton => 'Quét bằng camera';

  @override
  String get cameraScanTitle => 'Quét mã';

  @override
  String get cameraScanPointAtCode =>
      'Hướng camera vào mã — hệ thống đọc ngay khi nhận ra.';

  @override
  String get cameraScanClose => 'Đóng';

  @override
  String get cameraScanRefusedTitle => 'Không mở được camera';

  @override
  String get cameraScanRefusedBody =>
      'Hãy cho phép trang này dùng camera trong trình duyệt rồi thử lại.';

  @override
  String get cameraScanUnsupportedTitle =>
      'Trình duyệt này không đọc được mã bằng camera';

  @override
  String get cameraScanUnsupportedBody =>
      'Hãy nhập mã bằng tay, hoặc dùng đầu đọc ở xưởng.';

  @override
  String get accountCorrectionChangeRoleAndGrants => 'Đổi vai trò và quyền';

  @override
  String get commonSave => 'Lưu';

  @override
  String accountCorrectionHoldsTheRoleAndTheOrgUnit(Object email) {
    return '$email đang giữ vai trò và các quyền trên Đơn vị tổ chức được chọn ở đây. Những gì đặt bên dưới sẽ thay thế toàn bộ những gì tài khoản đang có.';
  }

  @override
  String get accountCorrectionAnAdministratorCanActEverywhereThisAccount =>
      'Quản trị viên thao tác được ở mọi nơi. Tài khoản này sẽ thấy và thay đổi được mọi Nhà máy và mọi Đơn vị tổ chức, và chấp nhận được các Tài khoản khác. Mọi quyền trên Đơn vị tổ chức mà tài khoản đang giữ đều bị bỏ, và không cần quyền nào.';

  @override
  String get accountCorrectionThisAccountWasTurnedAwaySavingThis =>
      'Tài khoản này đã bị từ chối. Lưu lại sẽ chấp nhận tài khoản vào Nền tảng và cho phép đăng nhập.';

  @override
  String get accountCorrectionThisAccountIsDeactivatedSavingThisReactivates =>
      'Tài khoản này đang bị vô hiệu. Lưu lại sẽ kích hoạt lại và cho phép đăng nhập trở lại.';

  @override
  String get commonChangeEmployeeLink => 'Đổi liên kết Nhân viên';

  @override
  String accountEmployeeWillBeLinkedToTheEmployeeChosen(Object email) {
    return '$email sẽ được liên kết với Nhân viên được chọn ở đây, hoặc không liên kết với ai.';
  }

  @override
  String get commonResetPassword => 'Đặt lại mật khẩu';

  @override
  String accountPasswordChooseANewPasswordForTellThem(Object email) {
    return 'Chọn mật khẩu mới cho $email. Hãy tự báo mật khẩu cho họ; mật khẩu không hiển thị lại lần nữa.';
  }

  @override
  String accountPasswordAtLeastCharacters(Object minimumPasswordLength) {
    return 'Ít nhất $minimumPasswordLength ký tự.';
  }

  @override
  String accountRolesRolesFor(Object accountName) {
    return 'Vai trò của $accountName';
  }

  @override
  String get commonAssigning => 'Đang gán…';

  @override
  String accountRolesRoleAssigned(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: 'đã gán $length vai trò',
      one: 'đã gán 1 vai trò',
    );
    return '$_temp0';
  }

  @override
  String accountRolesEveryAccountHoldsThis(Object code) {
    return '$code — mọi tài khoản đều có';
  }

  @override
  String accountRolesEveryAccountWhoseOwnRoleIs(
    Object code,
    Object legacyRole,
  ) {
    return '$code — mọi tài khoản có vai trò riêng là $legacyRole';
  }

  @override
  String accountRolesPermission(String code, int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length quyền',
      one: '1 quyền',
    );
    return '$code — $_temp0';
  }

  @override
  String get accountsTheAccountsCouldNotBeLoaded =>
      'Không đọc được danh sách tài khoản';

  @override
  String get accountsNoAccountsYet => 'Chưa có tài khoản nào';

  @override
  String get accountsAccountsAppearHereAsSoonAsSomebody =>
      'Tài khoản sẽ hiện ở đây ngay khi có người đăng nhập lần đầu.';

  @override
  String get accountsEveryAccountOnThisPlantWhatIt =>
      'Mọi tài khoản tại nhà máy này: tài khoản giữ gì và có đăng nhập được hay không.';

  @override
  String get commonFilterAccounts => 'Lọc tài khoản';

  @override
  String get accountsByNameEmailOrRole => 'Theo tên, email hoặc vai trò.';

  @override
  String get commonNoAccountsMatch => 'Không có tài khoản nào khớp';

  @override
  String accountsThisPlantHasAccountsButNoneMatches(Object term) {
    return 'Nhà máy có tài khoản, nhưng không tài khoản nào khớp “$term”. Hãy thử tên, email hay vai trò khác, hoặc xoá bộ lọc.';
  }

  @override
  String get accountsEmail => 'Email';

  @override
  String get accountsRole => 'Vai trò';

  @override
  String get accountsStanding => 'Tình trạng';

  @override
  String get accountsSince => 'Từ ngày';

  @override
  String get accountsGrants => 'Quyền';

  @override
  String get accountsReviewInApprovals => 'Xem trong Phê duyệt';

  @override
  String get accountsChange => 'Đổi';

  @override
  String get accountsLinkAnEmployee => 'Liên kết Nhân viên';

  @override
  String get accountsEverywhere => 'Mọi nơi';

  @override
  String get accountsNone => 'Không có';

  @override
  String accountsOrgUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Đơn vị tổ chức',
      one: '1 Đơn vị tổ chức',
    );
    return '$_temp0';
  }

  @override
  String get accountsActsEverywhereInEverySiteNoOrg =>
      'Thao tác ở mọi nơi, trong mọi Nhà máy. Không có quyền trên Đơn vị tổ chức nào, và không cần.';

  @override
  String get accountsNoOrgUnitGrantsCanSignIn =>
      'Không có quyền trên Đơn vị tổ chức nào. Đăng nhập được nhưng chưa thao tác được ở đâu.';

  @override
  String get accountsDeactivateThisAccount => 'Vô hiệu tài khoản này?';

  @override
  String accountsWillNotBeAbleToSignIn(Object email) {
    return '$email sẽ không đăng nhập được. Không có gì bị xoá — vai trò và các quyền trên Đơn vị tổ chức vẫn giữ nguyên, và quản trị viên có thể kích hoạt lại tài khoản bất cứ lúc nào.';
  }

  @override
  String get admissionAdmitThisAccount => 'Chấp nhận tài khoản này';

  @override
  String get commonAdmitting => 'Đang chấp nhận…';

  @override
  String get commonAdmit => 'Chấp nhận';

  @override
  String admissionWillBeLetInToThePlatform(Object email) {
    return '$email sẽ được vào Nền tảng với vai trò được chọn ở đây.';
  }

  @override
  String get admissionAnAdministratorCanActEverywhereThisAccount =>
      'Quản trị viên thao tác được ở mọi nơi. Tài khoản này sẽ thấy và thay đổi được mọi Nhà máy và mọi Đơn vị tổ chức, và chấp nhận được các Tài khoản khác. Không cấp quyền nào trên Đơn vị tổ chức, và không cần.';

  @override
  String get admissionThisAccountWillBeAdmittedWithNo =>
      'Tài khoản này sẽ được chấp nhận mà không có quyền nào trên Đơn vị tổ chức, nên đăng nhập được nhưng chưa thao tác được ở đơn vị nào.';

  @override
  String get approvalQueueTheQueueCouldNotBeLoaded => 'Không đọc được hàng chờ';

  @override
  String get approvalQueueNobodyIsWaiting => 'Không có ai đang chờ';

  @override
  String get approvalQueueEveryAccountHasBeenDealtWithNew =>
      'Mọi tài khoản đã được xử lý. Yêu cầu mới sẽ hiện ở đây.';

  @override
  String get approvalQueueEveryoneWaitingToBeLetInTo =>
      'Mọi người đang chờ được vào Nền tảng.';

  @override
  String get approvalQueueByEmailAddress => 'Theo địa chỉ email.';

  @override
  String approvalQueueAccountsAreWaitingButNoneMatchesTry(Object term) {
    return 'Có tài khoản đang chờ, nhưng không tài khoản nào khớp “$term”. Hãy thử địa chỉ email khác, hoặc xoá bộ lọc.';
  }

  @override
  String get approvalQueueAccount => 'Tài khoản';

  @override
  String get approvalQueueSuggestedEmployee => 'Nhân viên gợi ý';

  @override
  String get approvalQueueWaiting => 'Đang chờ';

  @override
  String get approvalQueueRejecting => 'Đang từ chối…';

  @override
  String get commonReject => 'Từ chối';

  @override
  String get approvalQueueRejectThisAccount => 'Từ chối tài khoản này?';

  @override
  String approvalQueueWillNotBeLetInToThe(Object email) {
    return '$email sẽ không được vào Nền tảng, và sẽ được báo là yêu cầu đã bị từ chối. Quản trị viên vẫn có thể chấp nhận sau.';
  }

  @override
  String get attendancePickerChooseAnOrgUnitAndAProduction =>
      'Chọn một Đơn vị tổ chức và một ngày sản xuất để mở bảng chấm công của ca đó.';

  @override
  String get attendancePickerProductionDay => 'Ngày sản xuất';

  @override
  String get attendancePickerTheShiftsCouldNotBeRead =>
      'Không đọc được danh sách ca';

  @override
  String get attendancePickerNoShiftsAreScheduledHereOnThat =>
      'Ngày đó không có ca nào được xếp ở đây.';

  @override
  String get attendancePickerChooseAnotherProductionDayOrAnotherOrg =>
      'Chọn ngày sản xuất khác, hoặc Đơn vị tổ chức khác.';

  @override
  String get commonTheSitesAreUnavailable =>
      'Không tải được danh sách Nhà máy.';

  @override
  String get commonThereAreNoSitesToBrowseYet => 'Chưa có Nhà máy nào để xem.';

  @override
  String get commonNothingToBrowseInThisSite =>
      'Nhà máy này chưa có gì để xem.';

  @override
  String get commonCollapse => 'Thu gọn';

  @override
  String get commonExpand => 'Mở rộng';

  @override
  String attendanceRecordMark(Object displayName) {
    return 'Chấm công cho $displayName';
  }

  @override
  String get attendanceRecordWorkedMinutes => 'Số phút đã làm';

  @override
  String get attendanceRecordOvertimeMinutes => 'Số phút ngoài giờ';

  @override
  String get attendanceSheetTheAttendanceSheetCouldNotBeRead =>
      'Không đọc được bảng chấm công';

  @override
  String get attendanceSheetNobodyWithAnEditGrantHereHas =>
      'Chưa có ai có quyền sửa ở đây mở bảng này, nên chưa có gì để hiển thị. Chỉ giám sát có quyền sửa bao trùm ca này — hoặc quản trị viên — mới mở được bảng.';

  @override
  String get attendanceSheetConfirmed => 'Đã xác nhận';

  @override
  String get attendanceSheetConfirming => 'Đang xác nhận…';

  @override
  String get commonConfirm => 'Xác nhận';

  @override
  String get attendanceSheetNobodyIsOnThisSheetYet => 'Bảng này chưa có ai.';

  @override
  String get attendanceSheetAddAStandInFromTheDirectory =>
      'Thêm một người thay ca từ Danh bạ bên dưới để mở bảng với ít nhất một người.';

  @override
  String get attendanceSheetASupervisorHoldingAnEditGrantReaching =>
      'Giám sát có quyền sửa bao trùm ca này thêm những người đã có mặt trong ca.';

  @override
  String get attendanceSheetMarkAnException => 'Đánh dấu ngoại lệ';

  @override
  String get attendanceSheetRemoveFromTheSheet => 'Bỏ khỏi bảng';

  @override
  String get attendanceSheetAddAStandIn => 'Thêm người thay ca';

  @override
  String get commonSearchTheDirectory => 'Tìm trong Danh bạ';

  @override
  String get attendanceSheetWorkedMin => 'Đã làm (phút)';

  @override
  String get attendanceSheetOvertimeMin => 'Ngoài giờ (phút)';

  @override
  String get attendanceToConfirmPastShiftsWhoseSheetIsMissingOr =>
      'Các ca đã qua có bảng chấm công còn thiếu hoặc chưa được xác nhận, cũ nhất trước, trong các Đơn vị tổ chức mà bạn xác nhận được.';

  @override
  String get attendanceToConfirmTheWorklistCouldNotBeRead =>
      'Không đọc được danh sách cần làm';

  @override
  String get attendanceToConfirmNothingToConfirmHere =>
      'Ở đây không có gì cần xác nhận.';

  @override
  String get attendanceToConfirmEveryPastShiftYouCanConfirmHas =>
      'Mọi ca đã qua mà bạn xác nhận được đều đã có bảng chấm công được xác nhận.';

  @override
  String get attendanceToConfirmNoShiftInThisWindowNeedsConfirming =>
      'Không có ca nào trong khoảng này cần xác nhận. Hãy mở rộng khoảng ngày, hoặc xoá Đơn vị tổ chức.';

  @override
  String get commonFrom => 'Từ';

  @override
  String commonOrgUnit2(Object orgUnitName) {
    return 'Đơn vị tổ chức: $orgUnitName';
  }

  @override
  String get commonClear => 'Xoá';

  @override
  String get commonHideOrgUnits => 'Ẩn Đơn vị tổ chức';

  @override
  String get commonFilterByOrgUnit => 'Lọc theo Đơn vị tổ chức';

  @override
  String get attendanceToConfirmOpenSheet => 'Mở bảng chấm công';

  @override
  String get commonUsd => 'USD';

  @override
  String get costRateFormTheRateBelowIsClosedOnThe =>
      'Đơn giá bên dưới sẽ được đóng vào ngày đơn giá mới có hiệu lực. Đơn giá này vẫn đọc được, và một chi phí hỏi cho ngày sớm hơn vẫn dùng đơn giá này.';

  @override
  String costRateFormTheListOfSitesOrgUnitsAssets(Object scopesFailure) {
    return 'Không đọc được danh sách Nhà máy, Đơn vị tổ chức, Tài sản và trung tâm chi phí, nên không chọn được phạm vi: $scopesFailure';
  }

  @override
  String get commonScope => 'Phạm vi';

  @override
  String costRateFormWhich(Object value) {
    return 'Loại $value nào';
  }

  @override
  String get costRateFormRateType => 'Loại đơn giá';

  @override
  String get costRateFormScopeAndRateType => 'Phạm vi và loại đơn giá';

  @override
  String get costRateFormARateSScopeAndRateType =>
      'Không sửa được phạm vi và loại đơn giá của một đơn giá — hãy thêm đơn giá cho phạm vi mới';

  @override
  String get costRateFormMultiplier15ForTimeAndA =>
      'Hệ số (1,5 cho giờ làm thêm gấp rưỡi)';

  @override
  String get costRateFormAmountPerHour => 'Số tiền mỗi giờ';

  @override
  String get costRateFormTheNewAmountFromTheDateBelow =>
      'Số tiền mới, áp dụng từ ngày bên dưới';

  @override
  String get commonCurrency => 'Tiền tệ';

  @override
  String get commonAThreeLetterCodeSuchAsUsd => 'Mã ba chữ cái, ví dụ USD';

  @override
  String get costRateFormNewRateTakesEffectOn => 'Đơn giá mới có hiệu lực từ';

  @override
  String get commonTakesEffectOn => 'Có hiệu lực từ';

  @override
  String get costRateFormTheOldRateIsClosedOnThis =>
      'Đơn giá cũ được đóng vào ngày này, và đơn giá mới bắt đầu';

  @override
  String get commonAppliesUntilOptional => 'Áp dụng đến (không bắt buộc)';

  @override
  String get costRateFormLeftBlankThisRateIsTheCurrent =>
      'Để trống thì đây là đơn giá hiện hành. Đặt ngày sẽ đóng đơn giá vào ngày đó, là mốc kết thúc không tính ngày ấy.';

  @override
  String get costRatesTheCostRateCatalogueCouldNotBe =>
      'Không đọc được danh mục đơn giá giờ';

  @override
  String get costRatesWhatAnHourCostsOneCatalogueShared =>
      'Một giờ tốn bao nhiêu — một danh mục dùng chung cho mọi Nhà máy, và là căn cứ tính các số Chi phí trên bảng phân cấp. Đơn giá không bao giờ bị ghi đè: đơn giá được đóng lại và mở đơn giá mới, nên chi phí đã báo cho tháng trước vẫn giữ nguyên.';

  @override
  String get costRatesAddCostRate => 'Thêm đơn giá giờ';

  @override
  String get costRatesNoCostRatesYet => 'Chưa có đơn giá giờ';

  @override
  String get costRatesUntilARateIsSetEveryCost =>
      'Chưa đặt đơn giá thì mọi số Chi phí đều không có giá trị.';

  @override
  String get costRatesRate => 'Đơn giá';

  @override
  String get commonPeriod => 'Kỳ';

  @override
  String get commonCorrect => 'Điều chỉnh';

  @override
  String get commonRevise => 'Thay thế';

  @override
  String get commonClosed => 'Đã đóng';

  @override
  String get directoryTheDirectoryCouldNotBeRead => 'Không đọc được Danh bạ';

  @override
  String get directoryNobodyMatchesThisSearch => 'Không ai khớp tìm kiếm này';

  @override
  String get directoryTryADifferentNameOrClearA =>
      'Hãy thử tên khác, hoặc xoá bộ lọc.';

  @override
  String get directoryWhoWorksHereSearchedFilteredAndDeparted =>
      'Ai làm việc ở đây — tìm kiếm, lọc, và Nhân viên đã rời được ẩn đi cho tới khi cần xem.';

  @override
  String get commonAddEmployee => 'Thêm Nhân viên';

  @override
  String get directoryMyRecord => 'Hồ sơ của tôi';

  @override
  String get directorySearchByName => 'Tìm theo tên';

  @override
  String get commonJobRole => 'Chức danh công việc';

  @override
  String get directoryAllJobRoles => 'Mọi chức danh';

  @override
  String get directoryIncludeDeparted => 'Gồm cả người đã rời';

  @override
  String get commonEmployment => 'Hình thức làm việc';

  @override
  String get commonDeparted => 'Đã rời';

  @override
  String get commonActive => 'Đang làm';

  @override
  String employeeAssignmentAssignToAnOrgUnit(Object displayName) {
    return 'Gán $displayName vào một Đơn vị tổ chức';
  }

  @override
  String get employeeAssignmentWhereItWorksNow => 'Đang làm ở đâu';

  @override
  String get employeeAssignmentJobRoleOptional =>
      'Chức danh công việc (không bắt buộc)';

  @override
  String get employeeAssignmentNoJobRole => 'Không có chức danh';

  @override
  String get employeeAssignmentEffectiveDate => 'Ngày hiệu lực';

  @override
  String employeeCorrectionCorrectSRecord(Object displayName) {
    return 'Sửa hồ sơ của $displayName';
  }

  @override
  String get commonFirstName => 'Tên';

  @override
  String get commonLastName => 'Họ';

  @override
  String get commonEmploymentType => 'Loại hình làm việc';

  @override
  String get commonWorkEmailOptional => 'Email công việc (không bắt buộc)';

  @override
  String employeeDepartureRecordThatHasLeft(Object displayName) {
    return 'Ghi nhận $displayName đã rời';
  }

  @override
  String get employeeDepartureAccountStillLinked =>
      'Tài khoản vẫn được liên kết';

  @override
  String get employeeDepartureTheRecordStaysNothingIsDeletedAnd =>
      'Hồ sơ vẫn còn — không có gì bị xoá, và có thể hoàn tác bằng cách dùng lại hồ sơ bất cứ lúc nào.';

  @override
  String get employeeDepartureEffectiveDateOptional =>
      'Ngày hiệu lực (không bắt buộc)';

  @override
  String get commonLeftBlankTodayIsRecorded => 'Để trống thì ghi nhận hôm nay.';

  @override
  String get employeeDepartureRecording => 'Đang ghi nhận…';

  @override
  String get commonRecordDeparture => 'Ghi nhận đã rời';

  @override
  String employeeDepartureHasLeftAndTheirAccountCanStill(
    Object displayName,
    Object email,
  ) {
    return '$displayName đã rời, và Tài khoản của họ ($email) vẫn đăng nhập được. Dù sao việc rời đi cũng đã được ghi nhận — vô hiệu tài khoản là bước riêng và không bắt buộc.';
  }

  @override
  String get employeeDepartureNotNow => 'Để sau';

  @override
  String get employeeDepartureDeactivating => 'Đang vô hiệu…';

  @override
  String get employeeDepartureDeactivateAccount => 'Vô hiệu tài khoản';

  @override
  String get employeeDetailThisRecordCouldNotBeRead =>
      'Không đọc được hồ sơ này';

  @override
  String get employeeDetailAssignmentHistory => 'Lịch sử phân công';

  @override
  String get employeeDetailNoAssignmentHasBeenRecorded =>
      'Chưa ghi nhận phân công nào.';

  @override
  String get employeeDetailRecordSkill => 'Ghi nhận kỹ năng';

  @override
  String get employeeDetailNoQualificationsRecorded =>
      'Chưa ghi nhận chứng nhận nào.';

  @override
  String get employeeDetailHired => 'Ngày vào làm';

  @override
  String get employeeDetailWorkEmail => 'Email công việc';

  @override
  String get commonCorrectRecord => 'Sửa hồ sơ';

  @override
  String get employeeDetailSignature => 'Chữ ký';

  @override
  String get commonReinstate => 'Khôi phục';

  @override
  String get employeeDetailCurrent => 'Hiện tại';

  @override
  String employeeDetailLapsed(Object name) {
    return '$name · Hết hạn';
  }

  @override
  String get employeeDetailReAssess => 'Đánh giá lại';

  @override
  String get commonAdding => 'Đang thêm…';

  @override
  String employeeLinkPickerSuggestedMatch(Object value) {
    return 'Gợi ý: $value';
  }

  @override
  String employeeLinkPickerLinkedTo(Object value) {
    return 'Đang liên kết với: $value';
  }

  @override
  String get commonRemove => 'Bỏ';

  @override
  String get employeeLinkPickerNoEmployeeWillBeLinked =>
      'Không liên kết với Nhân viên nào.';

  @override
  String employeeSignatureNoSignatureIsKeptForUploadA(Object displayName) {
    return 'Chưa lưu chữ ký nào của $displayName. Hãy tải ảnh chữ ký lên, hoặc vẽ tại đây.';
  }

  @override
  String get commonThisSignatureCouldNotBeShown =>
      'Không hiển thị được chữ ký này.';

  @override
  String employeeSignatureSetForBy(Object displayName, Object who) {
    return 'Đặt cho $displayName bởi $who';
  }

  @override
  String employeeSignatureSetBy(Object displayName) {
    return 'Do $displayName đặt';
  }

  @override
  String employeeSignatureSignatureOf(Object displayName) {
    return 'Chữ ký của $displayName';
  }

  @override
  String get commonUploadAPicture => 'Tải ảnh lên';

  @override
  String get commonReplaceWithAPicture => 'Thay bằng ảnh';

  @override
  String get commonDrawIt => 'Vẽ tại đây';

  @override
  String get commonDrawANewOne => 'Vẽ chữ ký mới';

  @override
  String get commonKeepThisSignature => 'Giữ chữ ký này';

  @override
  String employeeSkillFormReAssessFor(Object value, Object displayName) {
    return 'Đánh giá lại $value cho $displayName';
  }

  @override
  String employeeSkillFormRecordASkillFor(Object displayName) {
    return 'Ghi nhận kỹ năng cho $displayName';
  }

  @override
  String get employeeSkillFormSkill => 'Kỹ năng';

  @override
  String get employeeSkillFormProficiency04Iluo => 'Mức thành thạo (0–4, ILUO)';

  @override
  String get employeeSkillForm0None => '0 — không có';

  @override
  String get employeeSkillFormAssessedOnOptional =>
      'Đánh giá ngày (không bắt buộc)';

  @override
  String get employeeSkillFormExpiresOnOptional =>
      'Hết hạn ngày (không bắt buộc)';

  @override
  String get employeeSkillFormLeftBlankNeverExpiresOrIsRe =>
      'Để trống thì không bao giờ hết hạn (hoặc được tính lại từ chu kỳ đánh giá lại của kỹ năng đó).';

  @override
  String get employeeSkillFormEvidenceReferenceOptional =>
      'Tham chiếu minh chứng (không bắt buộc)';

  @override
  String floorTrainingTrainingFor(Object employeeName) {
    return 'Đào tạo của $employeeName';
  }

  @override
  String get floorTrainingYourTraining => 'Đào tạo của bạn';

  @override
  String get floorTrainingDone => 'Xong';

  @override
  String get floorTrainingShowMyTraining => 'Xem đào tạo của tôi';

  @override
  String get floorTrainingWhoAreYouYourEmployeeNumberAnd =>
      'Bạn là ai? Mã nhân viên và PIN cho thấy buổi đào tạo đang chờ bạn ở thiết bị này.';

  @override
  String get floorTrainingScanTheBadgeOrTypeTheNumber =>
      'Quét thẻ hoặc nhập số.';

  @override
  String get floorTrainingNothingIsWaitingOnYouAtThis =>
      'Không có gì đang chờ bạn ở thiết bị này.';

  @override
  String get jobRoleFormCorrectJobRole => 'Sửa chức danh công việc';

  @override
  String get commonAddJobRole => 'Thêm chức danh';

  @override
  String get jobRolesTheJobRoleCatalogueCouldNotBe =>
      'Không đọc được danh mục chức danh công việc';

  @override
  String get jobRolesWhatAnEmployeeDoesDefinedOnceShared =>
      'Nhân viên làm gì — khai báo một lần, dùng chung cho mọi Nhà máy.';

  @override
  String get jobRolesNoJobRolesYet => 'Chưa có chức danh nào';

  @override
  String get commonNothingHasBeenDefinedInTheCatalogue =>
      'Danh mục chưa có gì.';

  @override
  String get jobRolesFilterJobRoles => 'Lọc chức danh công việc';

  @override
  String get jobRolesByNameOrCode => 'Theo tên hoặc mã.';

  @override
  String get jobRolesNoJobRolesMatch => 'Không có chức danh nào khớp';

  @override
  String jobRolesNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Danh mục không có gì khớp “$term”. Hãy thử tên hoặc mã khác, hoặc xoá bộ lọc.';
  }

  @override
  String get leaveRequestCancelCancelLeaveRequest => 'Huỷ đơn xin nghỉ';

  @override
  String leaveRequestCancelCancelTheRequestFor(
    Object leaveTypeName,
    Object displayName,
    Object periodLabel,
    Object daysLabel,
  ) {
    return 'Huỷ đơn $leaveTypeName của $displayName, $periodLabel ($daysLabel)?';
  }

  @override
  String get leaveRequestCancelKeepRequest => 'Giữ đơn';

  @override
  String get leaveRequestCancelCancelling => 'Đang huỷ…';

  @override
  String get commonCancelRequest => 'Huỷ đơn';

  @override
  String get commonRequestLeave => 'Xin nghỉ';

  @override
  String get leaveRequestFormRequesting => 'Đang gửi…';

  @override
  String get leaveRequestFormLeaveTypesCouldNotBeRead =>
      'Không đọc được các loại nghỉ';

  @override
  String get leaveRequestFormLeaveType => 'Loại nghỉ';

  @override
  String get leaveRequestFormFirstDay => 'Ngày đầu';

  @override
  String get leaveRequestFormLastDay => 'Ngày cuối';

  @override
  String get leaveRequestsLeaveRequestsCouldNotBeRead =>
      'Không đọc được các đơn xin nghỉ';

  @override
  String get leaveRequestsAskToBeAwayFromWorkAnd =>
      'Xin nghỉ việc và theo dõi kết quả của đơn.';

  @override
  String get leaveRequestsMine => 'Của tôi';

  @override
  String get leaveRequestsToDecide => 'Cần quyết định';

  @override
  String get leaveRequestsNoLeaveRequestsYet => 'Chưa có đơn xin nghỉ nào';

  @override
  String get leaveRequestsNothingToDecide => 'Không có gì cần quyết định';

  @override
  String get leaveRequestsRequestLeaveToAskForTimeAway =>
      'Gửi đơn xin nghỉ để xin thời gian vắng mặt.';

  @override
  String get leaveRequestsNoPendingLeaveRequestsAreWaitingFor =>
      'Không có đơn xin nghỉ nào đang chờ bạn quyết định.';

  @override
  String leaveRequestsNote(Object note) {
    return 'Ghi chú: $note';
  }

  @override
  String leaveRequestsDecisionNote(Object decisionNote) {
    return 'Ghi chú quyết định: $decisionNote';
  }

  @override
  String get leaveRequestsApprove => 'Duyệt';

  @override
  String get mySignatureYourSignatureCouldNotBeRead =>
      'Không đọc được chữ ký của bạn';

  @override
  String get mySignatureNoSignatureKept => 'Chưa lưu chữ ký nào';

  @override
  String get mySignatureYouHaveNotKeptASignatureYet =>
      'Bạn chưa lưu chữ ký nào. Hãy tải ảnh chữ ký lên, hoặc vẽ tại đây.';

  @override
  String get mySignatureYourSignature => 'Chữ ký của bạn';

  @override
  String get mySignatureYourOwnMarkKeptOnceAndApplied =>
      'Dấu của chính bạn, lưu một lần và dùng ở mọi nơi mà bạn phải ký tay lên giấy tờ. Thay chữ ký không làm thay đổi bảng nào bạn đã ký.';

  @override
  String get mySignatureDrawYourSignature => 'Vẽ chữ ký của bạn';

  @override
  String get commonAddRootOrgUnit => 'Thêm Đơn vị tổ chức gốc';

  @override
  String get orgUnitFormAddOrgUnit => 'Thêm Đơn vị tổ chức';

  @override
  String get orgUnitFormUnitType => 'Loại đơn vị';

  @override
  String get orgUnitFormSortOrderOptional => 'Thứ tự sắp xếp (không bắt buộc)';

  @override
  String get commonImportABranch => 'Nhập một nhánh';

  @override
  String get orgUnitImportImporting => 'Đang nhập…';

  @override
  String get orgUnitImportImport => 'Nhập';

  @override
  String get orgUnitImportAJsonArrayOfRowsEachRow =>
      'Một mảng JSON các dòng. Mỗi dòng tham chiếu cha của nó bằng \"parentCode\" — một dòng khác trong cùng mảng này, hoặc một mã đã có ở Nhà máy này — không bao giờ bằng id.';

  @override
  String orgUnitImportRow(
    String row,
    String code,
    String field,
    String message,
  ) {
    return 'Dòng $row$code$field: $message';
  }

  @override
  String get orgUnitPickerOrgUnitGrants => 'Quyền trên Đơn vị tổ chức';

  @override
  String get orgUnitPickerEverythingOnTheRightIsWhatThis =>
      'Mọi thứ bên phải là những gì Tài khoản này sẽ giữ. Không cộng thêm vào những gì đang có — đây là toàn bộ danh sách.';

  @override
  String get orgUnitPickerQualityAuthorityAndSafetyAuthorityAreEach =>
      'Thẩm quyền Chất lượng và thẩm quyền An toàn độc lập với cấp quyền và độc lập với nhau — quyền chỉ đọc có thể có một trong hai, quyền sửa không cần có — và mỗi thẩm quyền bao trùm mọi thứ bên dưới Đơn vị tổ chức được cấp.';

  @override
  String get orgUnitPickerBrowse => 'Duyệt';

  @override
  String get orgUnitPickerGranted => 'Đã cấp';

  @override
  String get orgUnitPickerGrantThisOrgUnit => 'Cấp quyền đơn vị này';

  @override
  String get orgUnitPickerNothingBeneathThis => 'Không có đơn vị bên dưới';

  @override
  String orgUnitPickerGranted2(Object length) {
    return 'Đã cấp ($length)';
  }

  @override
  String get orgUnitPickerNoOrgUnitsGrantedThisAccountWill =>
      'Không cấp Đơn vị tổ chức nào. Tài khoản này đăng nhập được nhưng không thao tác được ở đâu.';

  @override
  String get orgUnitPickerQualityAuthority => 'Thẩm quyền Chất lượng';

  @override
  String get orgUnitPickerSafetyAuthority => 'Thẩm quyền An toàn';

  @override
  String get orgUnitPickerRemoveThisGrant => 'Bỏ quyền này';

  @override
  String get orgUnitsASiteSOwnShapeWhereA =>
      'Hình thù của một Nhà máy — nơi KPI được đo, nơi Tài khoản được cấp quyền, và nơi một Tài sản nằm.';

  @override
  String get commonAddSite => 'Thêm Nhà máy';

  @override
  String get commonEditSite => 'Sửa Nhà máy';

  @override
  String get orgUnitsTheSitesCouldNotBeRead =>
      'Không đọc được danh sách Nhà máy';

  @override
  String get orgUnitsThereAreNoSitesYet => 'Chưa có Nhà máy nào.';

  @override
  String get orgUnitsAnAdministratorAddsTheFirstSiteEvery =>
      'Quản trị viên thêm Nhà máy đầu tiên; mọi Đơn vị tổ chức đều nằm dưới một Nhà máy.';

  @override
  String get orgUnitsFindAnOrgUnitByName => 'Tìm Đơn vị tổ chức theo tên';

  @override
  String get orgUnitsPickingOneRevealsAndSelectsItIn =>
      'Chọn một đơn vị sẽ hiện và chọn nó trong cây bên dưới.';

  @override
  String get orgUnitsRetired => 'Đã ngừng sử dụng';

  @override
  String get orgUnitsTheOrgUnitTreeCouldNotBe =>
      'Không đọc được cây Đơn vị tổ chức';

  @override
  String get orgUnitsNothingToBrowseInThisSiteYet =>
      'Nhà máy này chưa có gì để xem.';

  @override
  String get orgUnitsAnAdministratorAddsTheFirstOrgUnit =>
      'Quản trị viên thêm Đơn vị tổ chức đầu tiên, hoặc nhập một nhánh.';

  @override
  String orgUnitsBelow(Object childCount) {
    return '$childCount bên dưới';
  }

  @override
  String get orgUnitsAddAnOrgUnitHere => 'Thêm Đơn vị tổ chức ở đây';

  @override
  String get orgUnitsRetire => 'Ngừng sử dụng';

  @override
  String get orgUnitsRetireThisOrgUnit => 'Ngừng sử dụng Đơn vị tổ chức này?';

  @override
  String orgUnitsWillReadAsRetiredRatherThanDeleted(Object name) {
    return '$name sẽ được ghi là đã ngừng sử dụng thay vì bị xoá, và có thể khôi phục bất cứ lúc nào.';
  }

  @override
  String get productCostFormTheCostBelowIsClosedOnThe =>
      'Chi phí bên dưới sẽ được đóng vào ngày chi phí mới có hiệu lực. Chi phí này vẫn đọc được, và hàng lỗi đã tính theo nó vẫn giữ nguyên con số đó.';

  @override
  String productCostFormTheProductListCouldNotBeRead(Object productsFailure) {
    return 'Không đọc được danh sách Sản phẩm, nên không chọn được Sản phẩm: $productsFailure';
  }

  @override
  String get productCostFormTheProductAStandardCostBelongsTo =>
      'Không sửa được Sản phẩm mà một chi phí chuẩn thuộc về — hãy ghi chi phí cho Sản phẩm kia';

  @override
  String get productCostFormStandardCostPerUnit => 'Chi phí chuẩn, mỗi đơn vị';

  @override
  String get productCostFormTheNewCostFromTheDateBelow =>
      'Chi phí mới, áp dụng từ ngày bên dưới';

  @override
  String get productCostFormNewCostTakesEffectOn =>
      'Chi phí mới có hiệu lực từ';

  @override
  String get productCostFormTheOldCostIsClosedOnThis =>
      'Chi phí cũ được đóng vào ngày này, và chi phí mới bắt đầu';

  @override
  String get productCostFormLeftBlankThisCostIsTheCurrent =>
      'Để trống thì đây là chi phí hiện hành. Đặt ngày sẽ đóng chi phí vào ngày đó, là mốc kết thúc không tính ngày ấy.';

  @override
  String get productCostsTheStandardCostCatalogueCouldNotBe =>
      'Không đọc được danh mục chi phí chuẩn';

  @override
  String get productCostsWhatAUnitIsCostedAtOne =>
      'Một đơn vị sản phẩm tốn bao nhiêu — một danh mục dùng chung cho mọi Nhà máy, và là căn cứ tính hàng lỗi và làm lại. Chi phí không bao giờ bị ghi đè: chi phí được đóng lại và mở chi phí mới, nên chi phí đã báo cho tháng trước vẫn giữ nguyên.';

  @override
  String get productCostsAddStandardCost => 'Thêm chi phí chuẩn';

  @override
  String get productCostsNoStandardCostsYet => 'Chưa có chi phí chuẩn';

  @override
  String get productCostsUntilACostIsSetScrapAnd =>
      'Chưa đặt chi phí thì hàng lỗi và làm lại không được tính giá.';

  @override
  String get roleFormCorrectRole => 'Sửa vai trò';

  @override
  String get commonAddRole => 'Thêm vai trò';

  @override
  String get roleForm330CharactersAZ09 =>
      '3–30 ký tự: A–Z, 0–9 và dấu gạch dưới, ví dụ ROLE_STORE_ROOM';

  @override
  String get roleFormWhatItIsFor => 'Dùng để làm gì';

  @override
  String get roleFormInActiveUse => 'Đang dùng';

  @override
  String get roleFormARetiredRoleKeepsItsHistoryAnd =>
      'Vai trò đã ngừng dùng vẫn giữ lịch sử và không gán được cho ai.';

  @override
  String rolePermissionsWhatCarries(Object code) {
    return '$code gồm những quyền gì';
  }

  @override
  String rolePermissionsOfPermissions(Object length, Object total) {
    return '$length trên $total quyền';
  }

  @override
  String get rolesTheRolesCouldNotBeRead => 'Không đọc được các vai trò';

  @override
  String get rolesWhatAnAccountMayDoEachRole =>
      'Tài khoản được làm gì. Mỗi vai trò là một nhóm quyền; mọi Tài khoản đều có nhóm mặc định, và vai trò được đánh dấu tự động thì do vai trò riêng của Tài khoản quyết định.';

  @override
  String get rolesNoRoles => 'Không có vai trò nào';

  @override
  String get rolesNothingIsCarryingAPermissionThatShould =>
      'Không có vai trò nào mang quyền. Điều này không nên xảy ra: bước khởi tạo dữ liệu tạo nhóm mặc định, nên nghĩa là bản triển khai chưa đầy đủ.';

  @override
  String get rolesDefaultGroup => 'Nhóm mặc định';

  @override
  String rolesAutomatic(Object legacyRole) {
    return 'Tự động: $legacyRole';
  }

  @override
  String rolesReaches(int length, int holderCount) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length quyền',
      one: '1 quyền',
    );
    String _temp1 = intl.Intl.pluralLogic(
      holderCount,
      locale: localeName,
      other: '$holderCount tài khoản',
      one: '1 tài khoản',
    );
    return '$_temp0 · đến $_temp1';
  }

  @override
  String get rolesPermissions => 'Quyền';

  @override
  String get siteFormTimezonesUnavailable => 'Không tải được múi giờ';

  @override
  String get siteFormTheTimezoneListCouldNotBeLoaded =>
      'Không tải được danh sách múi giờ.';

  @override
  String get siteFormTimezone => 'Múi giờ';

  @override
  String get siteFormCountryCodeOptional => 'Mã quốc gia (không bắt buộc)';

  @override
  String get skillCoverageOrgUnitAndSkill => 'Đơn vị tổ chức và kỹ năng';

  @override
  String get skillCoverageRequired => 'Yêu cầu';

  @override
  String get skillCoverageQualified => 'Đủ điều kiện';

  @override
  String get skillCoverageLapsed => 'Hết hạn';

  @override
  String get skillCoverageShortfall => 'Thiếu hụt';

  @override
  String get skillCoverageSkillCoverageCouldNotBeRead =>
      'Không đọc được độ phủ kỹ năng';

  @override
  String get skillCoverageWhereThisSiteFallsShortOfIts =>
      'Nơi Nhà máy này chưa đạt yêu cầu kỹ năng của chính nó.';

  @override
  String get skillCoverageEveryRequirementIsMet => 'Mọi yêu cầu đều đạt';

  @override
  String get skillCoverageThisSiteHasNoShortfallAgainstThe =>
      'Nhà máy này không thiếu hụt so với các yêu cầu kỹ năng mà chính nó đặt ra.';

  @override
  String get skillCoverageFilterSkillCoverage => 'Lọc độ phủ kỹ năng';

  @override
  String get skillCoverageByOrgUnitOrSkill =>
      'Theo Đơn vị tổ chức hoặc kỹ năng.';

  @override
  String get skillCoverageNoShortfallsMatch => 'Không có thiếu hụt nào khớp';

  @override
  String skillCoverageThisSiteIsShortSomewhereButNothing(Object term) {
    return 'Nhà máy này có chỗ thiếu, nhưng không mục nào khớp “$term”. Hãy thử Đơn vị tổ chức hay kỹ năng khác, hoặc xoá bộ lọc.';
  }

  @override
  String skillCoverageNeedsAtLevelQualifiedLapsed(
    Object minimumQualifiedHeadcount,
    Object minimumLevel,
    Object qualifiedHeadcount,
    Object expiredHeadcount,
  ) {
    return 'Cần $minimumQualifiedHeadcount ở mức $minimumLevel+, $qualifiedHeadcount đủ điều kiện, $expiredHeadcount hết hạn';
  }

  @override
  String skillCoverageShort(Object shortfall) {
    return 'Thiếu $shortfall';
  }

  @override
  String get skillFormCorrectSkill => 'Sửa kỹ năng';

  @override
  String get commonAddSkill => 'Thêm kỹ năng';

  @override
  String get skillFormRequiresCertification => 'Cần chứng nhận';

  @override
  String get skillFormRevalidationPeriodInMonthsOptional =>
      'Chu kỳ đánh giá lại, tính bằng tháng (không bắt buộc)';

  @override
  String get skillFormLeftBlankThisSkillNeverNeedsRevalidating =>
      'Để trống thì kỹ năng này không bao giờ cần đánh giá lại.';

  @override
  String skillQualifiedEmployeesWhoHolds(Object name) {
    return 'Ai có $name';
  }

  @override
  String get skillQualifiedEmployeesScopedTo => 'Phạm vi';

  @override
  String get skillQualifiedEmployeesMinimumProficiency =>
      'Mức thành thạo tối thiểu';

  @override
  String get skillQualifiedEmployeesSearch => 'Tìm';

  @override
  String get skillQualifiedEmployeesChooseAnOrgUnitThenSearch =>
      'Chọn một Đơn vị tổ chức, rồi tìm.';

  @override
  String get skillQualifiedEmployeesNobodyCurrentlyQualifiesAtThisOrgUnit =>
      'Hiện không có ai đủ điều kiện ở Đơn vị tổ chức này.';

  @override
  String skillQualifiedEmployeesLevel(Object proficiencyLevel) {
    return 'Mức $proficiencyLevel';
  }

  @override
  String get skillsTheSkillCatalogueCouldNotBeRead =>
      'Không đọc được danh mục kỹ năng';

  @override
  String get skillsWhatThePlantQualifiesAnEmployeeTo =>
      'Nhà máy công nhận Nhân viên làm được gì — khai báo một lần, dùng chung cho mọi Nhà máy.';

  @override
  String get skillsNoSkillsYet => 'Chưa có kỹ năng nào';

  @override
  String get skillsFilterSkills => 'Lọc kỹ năng';

  @override
  String get skillsByNameCodeOrCategory => 'Theo tên, mã hoặc hạng mục.';

  @override
  String get skillsNoSkillsMatch => 'Không có kỹ năng nào khớp';

  @override
  String skillsNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Danh mục không có gì khớp “$term”. Hãy thử tên, mã hoặc hạng mục khác, hoặc xoá bộ lọc.';
  }

  @override
  String get skillsWhoHoldsThis => 'Ai đang có kỹ năng này';

  @override
  String get trainingAnswerSignYourConfirmation => 'Ký xác nhận của bạn';

  @override
  String get trainingAnswerChooseWhatYourAnswerIsSignedWith =>
      'Chọn cách ký cho câu trả lời của bạn. Bạn cũng có thể xác nhận mà không cần chữ ký.';

  @override
  String get trainingAnswerYouKeepNoSignatureDrawOneNow =>
      'Bạn chưa lưu chữ ký nào. Hãy vẽ ngay cho câu trả lời này, hoặc xác nhận mà không cần chữ ký.';

  @override
  String get trainingAnswerYourSignatureWhichUseMySignatureApplies =>
      'Chữ ký của bạn, được “Dùng chữ ký của tôi” áp dụng:';

  @override
  String get trainingAnswerUseMySignature => 'Dùng chữ ký của tôi';

  @override
  String get trainingAnswerDrawOneNow => 'Vẽ ngay';

  @override
  String get trainingAnswerNoSignature => 'Không có chữ ký';

  @override
  String get trainingAnswerConfirmWithThisSignature =>
      'Xác nhận bằng chữ ký này';

  @override
  String get commonNoSuchTrainingRecord => 'Không có bản ghi đào tạo này';

  @override
  String get commonBackToTrainingRecords => 'Về danh sách bản ghi đào tạo';

  @override
  String get trainingDetailTheTrainingRecordCouldNotBeRead =>
      'Không đọc được bản ghi đào tạo này';

  @override
  String get trainingDetailTheForm => 'Biểu mẫu';

  @override
  String get trainingDetailTheTraining => 'Buổi đào tạo';

  @override
  String get commonTrainedOn => 'Đào tạo ngày';

  @override
  String get trainingDetailDuration => 'Thời lượng';

  @override
  String get trainingDetailTrainer => 'Người đào tạo';

  @override
  String get trainingDetailObjective => 'Mục tiêu';

  @override
  String trainingDetailTrainees(Object traineeCount) {
    return 'Học viên ($traineeCount)';
  }

  @override
  String get commonAddTrainee => 'Thêm học viên';

  @override
  String get trainingDetailNoTraineesAreOnThisTrainingRecord =>
      'Bản ghi đào tạo này chưa có học viên nào.';

  @override
  String get trainingDetailSendToTrainees => 'Gửi cho học viên';

  @override
  String get trainingDetailDiscardDraft => 'Bỏ bản nháp';

  @override
  String trainingDetailEvaluated(Object value) {
    return 'Đã đánh giá: $value';
  }

  @override
  String trainingDetailRemove(Object employeeName) {
    return 'Bỏ $employeeName';
  }

  @override
  String get trainingDetailDiscardThisDraft => 'Bỏ bản nháp này?';

  @override
  String get trainingDetailTheDraftAndTheTraineesListedOn =>
      'Bản nháp và các học viên ghi trên đó sẽ bị xoá, không khôi phục được. Chưa ai được hỏi về bản nháp này.';

  @override
  String get trainingDetailDiscard => 'Bỏ';

  @override
  String get commonEvaluation => 'Đánh giá';

  @override
  String get trainingFormThatTrainingFormCouldNotBeRead =>
      'Không đọc được biểu mẫu đào tạo đó';

  @override
  String get trainingFormTrainingRecord => 'Bản ghi đào tạo';

  @override
  String get trainingFormBiNBNGhiNhN => 'Biên bản ghi nhận đào tạo';

  @override
  String get trainingFormAttendanceListDanhSChThamGia => 'Danh sách tham gia:';

  @override
  String get trainingRaiseCorrectTrainingRecord => 'Sửa bản ghi đào tạo';

  @override
  String get commonRaiseTrainingRecord => 'Tạo bản ghi đào tạo';

  @override
  String get trainingRaiseCorrecting => 'Đang sửa…';

  @override
  String get trainingRaiseRaising => 'Đang tạo…';

  @override
  String get trainingRaiseTitle => 'Tiêu đề';

  @override
  String get trainingRaiseWhatTheTrainingWas => 'Buổi đào tạo là gì.';

  @override
  String get trainingRaiseTheDayItWasGiven => 'Ngày buổi đào tạo diễn ra.';

  @override
  String get trainingRaiseDurationHours => 'Thời lượng (giờ)';

  @override
  String get trainingRaiseHowLongItLastedEG1 =>
      'Buổi đào tạo kéo dài bao lâu, ví dụ 1,5.';

  @override
  String get trainingRaiseTrainerOptional => 'Người đào tạo (không bắt buộc)';

  @override
  String get trainingRaiseWhoGaveItFoundInTheDirectory =>
      'Ai đã đào tạo, tìm trong Danh bạ.';

  @override
  String get trainingRaiseObjectiveOptional => 'Mục tiêu (không bắt buộc)';

  @override
  String get trainingRaiseWhatTheTrainingSetOutToTeach =>
      'Buổi đào tạo nhằm dạy điều gì.';

  @override
  String get trainingRecord => 'Bản ghi';

  @override
  String get trainingTrainees => 'Học viên';

  @override
  String get trainingAnswers => 'Câu trả lời';

  @override
  String get trainingTrainingRecordsCouldNotBeRead =>
      'Không đọc được các bản ghi đào tạo';

  @override
  String get trainingNoTrainingRecordsMatch =>
      'Không có bản ghi đào tạo nào khớp';

  @override
  String get trainingNothingWasTrainedUnderThatOrgUnit =>
      'Không có buổi đào tạo nào dưới Đơn vị tổ chức đó trong những ngày ấy.';

  @override
  String get trainingNoTrainingRecordsYet => 'Chưa có bản ghi đào tạo nào';

  @override
  String get trainingRaiseATrainingRecordToStartThe =>
      'Tạo một bản ghi đào tạo để bắt đầu sổ.';

  @override
  String get trainingNothingHasBeenRecordedAsTrainedYet =>
      'Chưa ghi nhận ai được đào tạo điều gì.';

  @override
  String get trainingWhatThePlantHasTrainedPeopleOn =>
      'Nhà máy đã đào tạo người ta những gì, và khi nào.';

  @override
  String get trainingThereAreMoreTrainingRecordsThanThis =>
      'Còn nhiều bản ghi đào tạo hơn danh sách này hiển thị. Hãy thu hẹp theo Đơn vị tổ chức hoặc theo ngày để xem phần còn lại.';

  @override
  String trainingTheFormFor(Object number) {
    return 'Biểu mẫu của $number';
  }

  @override
  String get trainingToConfirmYourTrainingToConfirmCouldNotBe =>
      'Không đọc được các buổi đào tạo cần bạn xác nhận';

  @override
  String get trainingToConfirmNothingWaitingOnYou => 'Không có gì đang chờ bạn';

  @override
  String get trainingToConfirmNoTrainingRecordHasBeenSentTo =>
      'Không có bản ghi đào tạo nào gửi cho bạn mà bạn chưa trả lời.';

  @override
  String get trainingToConfirmTrainingRecordsSentToYouThatYou =>
      'Các bản ghi đào tạo gửi cho bạn mà bạn chưa trả lời, cũ nhất trước. Hãy xác nhận bạn đã tham gia, hoặc từ chối vì bản ghi sai.';

  @override
  String get trainingToConfirmYourAnswer => 'Câu trả lời của bạn';

  @override
  String trainingTraineeEmployeesOf(Object orgUnitName) {
    return 'Nhân viên của $orgUnitName';
  }

  @override
  String get trainingTraineeWholeDirectory => 'Toàn bộ Danh bạ';

  @override
  String get trainingTraineeAnyoneInTheDirectoryFoundByName =>
      'Bất kỳ ai trong Danh bạ, tìm theo tên hoặc mã số.';

  @override
  String trainingTraineeAnEmployeeOfFoundByNameOr(Object orgUnitName) {
    return 'Một Nhân viên của $orgUnitName, tìm theo tên hoặc mã số.';
  }

  @override
  String get workedHoursDay => 'Ngày';

  @override
  String get workedHoursWorked => 'Đã làm';

  @override
  String get workedHoursBackToEmployee => 'Về hồ sơ nhân viên';

  @override
  String get workedHoursTheConfirmedHoursThisEmployeeActuallyWorked =>
      'Số giờ đã xác nhận mà Nhân viên này thực sự làm, theo từng ngày. Chỉ chấm công đã xác nhận mới được tính — bảng chưa xác nhận chỉ là bản nháp.';

  @override
  String get workedHoursTheWorkedHoursSummaryCouldNotBe =>
      'Không đọc được tổng hợp giờ đã làm';

  @override
  String get workedHoursNoConfirmedWorkedHoursInThisWindow =>
      'Không có giờ đã làm nào được xác nhận trong khoảng này.';

  @override
  String get workedHoursWidenTheWindowOrConfirmTheShift =>
      'Hãy mở rộng khoảng ngày, hoặc xác nhận bảng chấm công của những ngày Nhân viên này đã làm.';

  @override
  String get workedHoursTotals => 'Tổng cộng';

  @override
  String workedHoursOfScheduled(Object value) {
    return 'trên $value theo lịch';
  }

  @override
  String get leaveRequestDecisionApproveLeaveRequest => 'Duyệt đơn xin nghỉ';

  @override
  String get leaveRequestDecisionRejectLeaveRequest => 'Từ chối đơn xin nghỉ';

  @override
  String get commonTo => 'Đến';

  @override
  String get commonEmployeeNumber => 'Mã nhân viên';

  @override
  String get commonPin => 'PIN';

  @override
  String get commonInactive => 'Ngừng dùng';

  @override
  String get commonDeactivate => 'Ngừng kích hoạt';

  @override
  String get commonReactivate => 'Kích hoạt lại';

  @override
  String get commonClose => 'Đóng';

  @override
  String get commonReason => 'Lý do';

  @override
  String get commonAssign => 'Phân công';

  @override
  String get commonDecline => 'Từ chối';

  @override
  String get commonOvertime => 'Ngoài giờ';

  @override
  String get commonSessionEnded =>
      'Phiên làm việc đã kết thúc. Hãy đăng nhập lại để tiếp tục.';

  @override
  String get attendanceRecordChooseAReasonForThisAbsence =>
      'Hãy chọn lý do cho lần vắng này.';

  @override
  String get commonThatActionCouldNotBeRead => 'Không đọc được Hành động đó';

  @override
  String get commonThatActionHasEnded => 'Hành động đó đã kết thúc';

  @override
  String get commonDone => 'xong';

  @override
  String get actionCancelItIsClosedSoThereIsNothing =>
      'Hành động đã đóng nên không còn gì để huỷ.';

  @override
  String get actionCancelItWasAlreadyCancelled =>
      'Hành động đã bị huỷ trước đó.';

  @override
  String actionCancelCallOff(Object actionNo) {
    return 'Huỷ $actionNo?';
  }

  @override
  String get actionCancelLeaveItAlone => 'Để nguyên';

  @override
  String get actionCancelCallItOff => 'Huỷ hành động';

  @override
  String get actionCancelCallingItOffEndsTheRecordWithout =>
      'Huỷ sẽ kết thúc hồ sơ mà không khẳng định đã làm được gì. Dòng vẫn còn, kèm lý do bạn ghi.';

  @override
  String get actionCancelWhyOptional => 'Lý do (không bắt buộc)';

  @override
  String get actionCancelRaisedInErrorADuplicateOvertakenBy =>
      'Nêu nhầm, bị trùng, hoặc đã bị việc khác vượt qua.';

  @override
  String get commonBackToTheActionLog => 'Về nhật ký hành động';

  @override
  String get actionDetailHandItUp => 'Chuyển lên trên…';

  @override
  String get actionDetailCallItOff => 'Huỷ hành động…';

  @override
  String get actionDetailWhereItStands => 'Tình trạng hiện tại';

  @override
  String get commonOwner => 'Người phụ trách';

  @override
  String get actionDetailEscalatedTo => 'Đã chuyển tới';

  @override
  String get actionDetailClosingNote => 'Ghi chú khi đóng';

  @override
  String actionDetailPillar(Object pillarCode) {
    return 'Trụ cột $pillarCode';
  }

  @override
  String commonOverdueByDays(Object daysOverdue) {
    return 'Quá hạn $daysOverdue ngày';
  }

  @override
  String actionDetailCycle(Object currentCycle) {
    return 'Chu kỳ $currentCycle';
  }

  @override
  String actionDetailCompleteThe(Object phaseLabel) {
    return 'Hoàn thành $phaseLabel';
  }

  @override
  String get actionDetailThisActionHasNoPhasesLeft =>
      'Hành động này không còn giai đoạn nào.';

  @override
  String get actionDetailEarlierRounds => 'Các vòng trước';

  @override
  String get actionDetailOpenWaitingOnThis =>
      'Đang mở — chờ chính hành động này';

  @override
  String get actionDetailNoNoteRecorded => 'Chưa ghi chú nào';

  @override
  String actionDetailDue(Object dueDate) {
    return 'đến hạn $dueDate';
  }

  @override
  String actionDetailDone(Object value) {
    return 'xong $value';
  }

  @override
  String actionDetailAnswers(Object actionNo) {
    return 'Trả lời $actionNo';
  }

  @override
  String get commonCapa => 'CAPA';

  @override
  String get actionDetailAFormal8dInvestigationOpenedOnThis =>
      'Một cuộc điều tra 8D chính thức đã mở trên Concern này: nhóm của nó, mô tả vấn đề và — khi các phần đó hoàn thành — nguyên nhân gốc và bước kiểm tra hiệu quả. Các hành động của nó là những hành động bên dưới, được ghi một lần trong nhật ký hành động và đọc ở đó.';

  @override
  String actionDetailUnderInvestigation(Object capaNo) {
    return 'Đang điều tra: $capaNo';
  }

  @override
  String get actionDetailOpenACapa => 'Mở một CAPA…';

  @override
  String get actionDetailNobodyHasOpenedACapaOnThis =>
      'Chưa ai mở CAPA trên Concern này. Mở CAPA cần thẩm quyền Chất lượng tại Đơn vị tổ chức của Concern.';

  @override
  String get actionDetailMeasures => 'Biện pháp';

  @override
  String actionDetailMeasuresOfThemCountermeasures(
    Object length,
    Object countermeasureCount,
  ) {
    return 'Biện pháp ($length, trong đó $countermeasureCount là biện pháp khắc phục)';
  }

  @override
  String get actionDetailAddAMeasure => 'Thêm biện pháp';

  @override
  String actionDetailAddA(Object value) {
    return 'Thêm $value…';
  }

  @override
  String get actionDetailEachMeasureIsAnActionOfIts =>
      'Mỗi biện pháp là một Hành động riêng: mở nó và chạy chu kỳ của chính nó đến bước Act, và nó được tính là đã đóng.';

  @override
  String get actionDetailThisActionAnswersNoConcernOfIts =>
      'Hành động này không trả lời Concern nào của riêng nó.';

  @override
  String get actionDetailNothingAnswersThisYetAContainmentStops =>
      'Chưa có gì trả lời vấn đề này. Biện pháp ngăn chặn chặn hậu quả ngay; biện pháp khắc phục loại bỏ nguyên nhân.';

  @override
  String get commonNobodyYet => 'Chưa có ai';

  @override
  String actionDetailOverdueByDays(Object daysOverdue) {
    return 'quá hạn $daysOverdue ngày';
  }

  @override
  String commonWaitingOnIts(Object value) {
    return 'đang chờ $value của nó';
  }

  @override
  String actionDetailCompleteThe2(Object value) {
    return 'Hoàn thành $value…';
  }

  @override
  String actionDetailNonConformances(Object length) {
    return 'Sản phẩm không phù hợp ($length)';
  }

  @override
  String get actionDetailTheOccurrencesThisConcernAnswersOneProblem =>
      'Những lần xuất hiện mà Concern này trả lời. Một vấn đề lặp lại nhiều lần vẫn là một Concern, nên lần xuất hiện sau được liên kết vào đây chứ không nêu thành Concern khác.';

  @override
  String get actionDetailNoNonConformanceIsLinkedToThis =>
      'Chưa có Sản phẩm không phù hợp nào được liên kết với Concern này.';

  @override
  String get actionDetailRaisedFromThis => 'Nêu từ đây';

  @override
  String get actionDetailUnlink => 'Bỏ liên kết…';

  @override
  String get actionDetailTheObservationThisActionWasRaisedFrom =>
      'Quan sát mà Hành động này được nêu từ đó — đã thấy gì, và hậu quả có thể nặng tới đâu.';

  @override
  String get actionDetailTheIncidentThisConcernWasRaisedFrom =>
      'Sự cố mà Concern này được nêu từ đó — số hiệu và mức độ của nó, không bao giờ là ai bị thương hay chẩn đoán.';

  @override
  String get actionEscalateItIsClosedWhoeverNeededToKnow =>
      'Hành động đã đóng. Những ai cần biết đã được báo trước khi đóng.';

  @override
  String get actionEscalateItWasCalledOffSoThereIs =>
      'Hành động đã bị huỷ nên không có gì để chuyển lên.';

  @override
  String get actionEscalateNowhereToHandItUpTo =>
      'Không có nơi nào để chuyển lên';

  @override
  String get actionEscalateThereIsNobodyAboveThis =>
      'Không có ai ở trên đơn vị này';

  @override
  String actionEscalateSitsAtWhichIsAlreadyTheTop(
    Object actionNo,
    Object orgUnitName,
  ) {
    return '$actionNo nằm tại $orgUnitName, vốn đã là cấp cao nhất của Nhà máy này. Không thể báo cho ai ở trên nữa.';
  }

  @override
  String actionEscalateHandUp(Object actionNo) {
    return 'Chuyển $actionNo lên trên';
  }

  @override
  String get actionEscalateHandItUp => 'Chuyển lên trên';

  @override
  String get actionEscalateRaisingThisTellsTheOrgUnitYou =>
      'Việc này báo cho Đơn vị tổ chức bạn chọn. Hành động vẫn ở nguyên chỗ cũ, giữ người phụ trách và chu kỳ — đây là yêu cầu cấp trên biết về nó, không phải chuyển giao.';

  @override
  String actionEscalateNearestAboveIt(Object code) {
    return '$code · đơn vị gần nhất ở trên';
  }

  @override
  String get actionEscalatedToFilterFilterByWhatWasHandedUp =>
      'Lọc theo nơi đã chuyển lên';

  @override
  String get actionEscalatedToFilterAnyone => 'Bất kỳ ai';

  @override
  String get actionEscalatedToFilterWhoseQueue => 'Hàng chờ của ai';

  @override
  String get actionEscalatedToFilterChooseTheOrgUnitThatConcernsWere =>
      'Chọn Đơn vị tổ chức mà các Concern đã được chuyển lên — tức là thứ đang chờ ở khu vực, không phải thứ nằm ở chuyền — hoặc xoá về tất cả.';

  @override
  String get commonRaiseAConcern => 'Nêu một Concern';

  @override
  String get actionFormRaiseIt => 'Nêu';

  @override
  String get actionFormOneLineTheCauseGoesInThe =>
      'Một dòng. Nguyên nhân ghi ở giai đoạn Plan, không phải ở đây.';

  @override
  String get commonKindOfAction => 'Loại hành động';

  @override
  String get actionFormThePillarCatalogueCouldNotBeRead =>
      'Không đọc được danh mục Trụ cột nên không chọn được Trụ cột.';

  @override
  String get actionFormPillarOptional => 'Trụ cột (không bắt buộc)';

  @override
  String get actionFormWhichSqdcpNumberDoesThisThreaten =>
      'Chỉ số SQDCP nào bị đe doạ?';

  @override
  String get actionFormNoPillar => 'Không có trụ cột';

  @override
  String get commonOwnerOptional => 'Người phụ trách (không bắt buộc)';

  @override
  String get actionFormWhoWillDoItAnActionNobody =>
      'Ai sẽ làm. Một Hành động không có người phụ trách thì rõ ràng là của không ai.';

  @override
  String get commonDueOptional => 'Đến hạn (không bắt buộc)';

  @override
  String get actionFormChooseTheOrgUnitThisConcernIs =>
      'Chọn Đơn vị tổ chức mà concern này liên quan. Đây là điều quyết định ai được thao tác trên nó.';

  @override
  String actionFormThisConcernWillBeRecordedAt(Object value) {
    return 'Concern này sẽ được ghi nhận tại $value.';
  }

  @override
  String actionMeasureAddA(Object value) {
    return 'Thêm $value';
  }

  @override
  String actionMeasureAddThe(Object value) {
    return 'Thêm $value';
  }

  @override
  String actionMeasureAnswering(Object actionNo, Object title) {
    return 'Trả lời $actionNo: $title';
  }

  @override
  String get actionMeasureWhatWillBeDone => 'Sẽ làm gì';

  @override
  String get actionMeasureWhoWillDoIt => 'Ai sẽ làm.';

  @override
  String get actionMeasureWhereThisWorkHappens => 'Công việc này diễn ra ở đâu';

  @override
  String actionMeasureLeaveItAloneToRecordTheMeasure(Object orgUnitName) {
    return 'Để trống thì biện pháp được ghi tại $orgUnitName, nơi concern đang nằm. Một sửa đổi thuộc nơi khác — kho, nhà cung cấp — có thể nêu đơn vị đó thay vào.';
  }

  @override
  String get actionOrgUnitFilterNarrowTheLog => 'Thu hẹp nhật ký';

  @override
  String get actionOrgUnitFilterChooseTheOrgUnitWhoseActionsAnd =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc Hành động và mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String get actionPhaseCompleteThatIsNotTheOpenPhase =>
      'Đó không phải giai đoạn đang mở';

  @override
  String get actionPhaseCompleteThisActionHasNoOpenPhaseLeft =>
      'Hành động này không còn giai đoạn nào đang mở.';

  @override
  String actionPhaseCompleteThisActionIsWaitingOnItsPhase(
    Object value,
    Object value2,
  ) {
    return 'Hành động này đang chờ giai đoạn $value của nó, không phải $value2.';
  }

  @override
  String actionPhaseCompleteCompleteThe(Object label) {
    return 'Hoàn thành $label';
  }

  @override
  String get actionPhaseCompleteWhatWasMeasured => 'Đã đo được gì';

  @override
  String get actionPhaseCompleteWhatWasDone => 'Đã làm gì';

  @override
  String get actionPhaseCompleteDidItHold => 'Có giữ được kết quả không?';

  @override
  String get actionPhaseCompleteAnsweringThatItDidNotOpensThe =>
      'Trả lời là không sẽ mở chu kỳ tiếp theo thay vì đóng Hành động, và giữ vòng này trong hồ sơ.';

  @override
  String get actionUnlinkNonconformanceThatConcernCouldNotBeRead =>
      'Không đọc được Concern đó';

  @override
  String get actionUnlinkNonconformanceThatNonConformanceIsNotLinkedHere =>
      'Sản phẩm không phù hợp đó không được liên kết ở đây';

  @override
  String get actionUnlinkNonconformanceThisConcernAnswersNothingByThatId =>
      'Concern này không trả lời gì với mã đó. Có thể nó đã được bỏ liên kết, hoặc địa chỉ sai.';

  @override
  String get actionUnlinkNonconformanceBackToTheConcern => 'Về Concern';

  @override
  String get actionUnlinkNonconformanceUnlinkThisNonConformance =>
      'Bỏ liên kết Sản phẩm không phù hợp này?';

  @override
  String get actionUnlinkNonconformanceKeepItLinked => 'Giữ liên kết';

  @override
  String get actionUnlinkNonconformanceUnlinkIt => 'Bỏ liên kết';

  @override
  String get actionUnlinkNonconformanceItStopsBeingOneOfTheOccurrences =>
      'Nó không còn là một trong những lần xuất hiện mà Concern này trả lời. Bản thân Sản phẩm không phù hợp không bị đụng tới — nó vẫn giữ số hiệu, các Phương án xử lý và số lượng.';

  @override
  String get actionsTheActionLogCouldNotBeRead =>
      'Không đọc được nhật ký hành động';

  @override
  String get actionsWhatThePlantOwesAtThisSite =>
      'Những gì nhà máy còn nợ tại Nhà máy này: đã phát hiện gì, ai phụ trách, và khi nào đến hạn. Quá hạn trước.';

  @override
  String get actionsEscalatedToAnyone => 'Đã chuyển cho bất kỳ ai';

  @override
  String actionsEscalatedTo(Object escalatedToOrgUnitFilterName) {
    return 'Đã chuyển tới $escalatedToOrgUnitFilterName';
  }

  @override
  String get actionsEveryKind => 'Mọi loại';

  @override
  String get actionsShowClosed => 'Hiện cả việc đã đóng';

  @override
  String get actionsThereAreMoreActionsThanThisList =>
      'Còn nhiều Hành động hơn danh sách này hiển thị. Hãy thu hẹp theo Đơn vị tổ chức, trạng thái hoặc loại để xem phần còn lại.';

  @override
  String get actionsTheLogHasActionsButNoneOf =>
      'Nhật ký có Hành động, nhưng không cái nào thuộc Đơn vị tổ chức, trạng thái hay loại bạn đã chọn.';

  @override
  String get actionsNothingOnTheLog => 'Nhật ký trống';

  @override
  String get actionsNoActionHasBeenRaisedAtThis =>
      'Chưa có Hành động nào được nêu tại Nhà máy này.';

  @override
  String get actionsSource => 'Nguồn';

  @override
  String actionsOfThemCountermeasures(
    int measureCount,
    int countermeasureCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      measureCount,
      locale: localeName,
      other: '$measureCount biện pháp',
      one: '1 biện pháp',
    );
    return '$_temp0, trong đó $countermeasureCount là biện pháp khắc phục';
  }

  @override
  String actionsEscalatedTo2(Object escalatedToOrgUnitName) {
    return 'Đã chuyển tới $escalatedToOrgUnitName';
  }

  @override
  String get actionsNoDueDate => 'Không có hạn';

  @override
  String actionsDue(Object dueDate) {
    return 'Đến hạn $dueDate';
  }

  @override
  String get commonBackToTheCapa => 'Về CAPA';

  @override
  String get commonThatCapaCouldNotBeRead => 'Không đọc được CAPA đó';

  @override
  String get capaCauseThatIsNotA6mCategory => 'Đó không phải một hạng mục 6M';

  @override
  String get capaCauseAFishboneHasSixBonesManMachine =>
      'Biểu đồ xương cá có sáu nhánh: Man, Machine, Method, Material, Measurement và Environment.';

  @override
  String get commonThisInvestigationIsOver => 'Cuộc điều tra này đã kết thúc';

  @override
  String capaCauseIsSoItsFishboneIsARecord(Object capaNo, Object value) {
    return '$capaNo đang $value, nên biểu đồ xương cá của nó là hồ sơ chứ không phải danh sách việc.';
  }

  @override
  String get commonNotYoursToWrite => 'Không phải phần bạn được ghi';

  @override
  String get commonWritingACapaSRootCausesNeeds =>
      'Ghi nguyên nhân gốc của CAPA cần quyền sửa tại Đơn vị tổ chức của nó, hoặc một chỗ trong nhóm.';

  @override
  String get capaCauseThatCauseIsNotOnThisBone =>
      'Nguyên nhân đó không nằm trên nhánh này';

  @override
  String get commonItMayHaveBeenRemovedAMoment =>
      'Có thể người khác vừa xoá nó cách đây ít phút.';

  @override
  String get capaCauseRecordACandidateCause => 'Ghi một nguyên nhân ứng viên';

  @override
  String get capaCauseReviseTheCause => 'Sửa nguyên nhân';

  @override
  String get capaCauseRemoveThisCause => 'Xoá nguyên nhân này?';

  @override
  String get commonRemoveIt => 'Xoá';

  @override
  String capaCauseItIsTakenOffTheBoneFor(Object categoryLabel, Object value) {
    return 'Nó bị bỏ khỏi nhánh $categoryLabel vĩnh viễn$value. Một chuỗi bắt đầu từ nó vẫn giữ Why mà nó khởi đầu.';
  }

  @override
  String get capaCauseBothChainsHaveBeenStarted =>
      'Cả hai chuỗi đều đã bắt đầu';

  @override
  String capaCauseAlreadyReasonsBothWhyTheProblemHappened(Object capaNo) {
    return '$capaNo đã lý giải cả vì sao vấn đề xảy ra và vì sao nó không được phát hiện, nên Why cho nguyên nhân này phải nằm trong một trong hai chuỗi chứ không đứng đầu chuỗi mới.';
  }

  @override
  String get capaCauseTheBoneItHangsFrom => 'Nhánh mà nó treo vào';

  @override
  String get capaCauseTheCandidateCause => 'Nguyên nhân ứng viên';

  @override
  String get capaCauseWhatYouSuspectSaidSoTheNext =>
      'Điều bạn nghi ngờ, nói sao cho người sau kiểm tra được.';

  @override
  String get capaCauseDecideThisCause => 'Kết luận nguyên nhân này';

  @override
  String get capaCauseRecordTheVerdict => 'Ghi kết luận';

  @override
  String get capaCauseAVerdictIsADecisionTheReport =>
      'Kết luận là một quyết định mà báo cáo đọc lại, nên nó được ghi kèm bằng chứng.';

  @override
  String get capaCauseTheEvidence => 'Bằng chứng';

  @override
  String get capaCauseWhatYouLookedAtAndWhatIt =>
      'Bạn đã xem gì, và nó cho thấy gì.';

  @override
  String get capaCauseStartAChainFromThisCause =>
      'Bắt đầu một chuỗi từ nguyên nhân này';

  @override
  String get capaCauseStartTheChain => 'Bắt đầu chuỗi';

  @override
  String get capaCauseTheEvidenceConfirmedThisCauseSoA =>
      'Bằng chứng đã xác nhận nguyên nhân này, nên một chuỗi có thể bắt đầu từ nó. Điều nó nói là Why đầu tiên.';

  @override
  String get capaCauseWhichChainItBegins => 'Nó bắt đầu chuỗi nào';

  @override
  String get capaCauseTheFirstWhy => 'Why đầu tiên';

  @override
  String get capaCauseTheConfirmedCauseSaidTheWayThe =>
      'Nguyên nhân đã xác nhận, nói theo cách chuỗi nên đọc.';

  @override
  String capaDetailBackTo(Object actionNo) {
    return 'Về $actionNo';
  }

  @override
  String get capaDetailTheReport => 'Báo cáo';

  @override
  String capaDetailInvestigation(Object methodLabel) {
    return 'Điều tra $methodLabel';
  }

  @override
  String capaDetailDue(Object dueDate) {
    return 'đến hạn $dueDate';
  }

  @override
  String get capaDetailEffectiveness => 'Hiệu quả';

  @override
  String get commonACapaClosesOnlyWhenBothChains =>
      'CAPA chỉ đóng khi cả hai chuỗi đều có nguyên nhân gốc đã xác nhận, Concern của nó đã đóng, và một người có thẩm quyền Chất lượng không phải trưởng nhóm điều tra đã xác minh, sau một thời gian, rằng vấn đề không quay lại.';

  @override
  String capaDetailRecordedByOn(Object value, Object value2) {
    return 'ghi bởi $value ngày $value2';
  }

  @override
  String get capaDetailTheCheckDidNotHoldSoThe =>
      'Bước kiểm tra không giữ được kết quả, nên Concern mở lại ở chu kỳ tiếp theo: công việc nằm trên màn hình của nó, trong Concern mà cuộc điều tra này trả lời.';

  @override
  String commonTheConcernHasClosedSoTheEffectiveness(Object dueAt) {
    return 'Concern đã đóng, nên bước kiểm tra hiệu quả đến hạn vào $dueAt.';
  }

  @override
  String get commonOverdue => 'Quá hạn';

  @override
  String get commonRecordTheEffectivenessCheck => 'Ghi bước kiểm tra hiệu quả';

  @override
  String get capaDetailYouLeadThisInvestigationSoSomebodyElse =>
      'Bạn là người dẫn cuộc điều tra này, nên người khác ghi bước kiểm tra: một người có thẩm quyền Chất lượng không thuộc tài khoản trưởng nhóm.';

  @override
  String get capaDetailRecordingTheCheckNeedsQualityAuthorityAt =>
      'Ghi bước kiểm tra cần thẩm quyền Chất lượng tại Đơn vị tổ chức này.';

  @override
  String capaDetailTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  ) {
    return 'Bước kiểm tra đến hạn $effectivenessCheckDelayDays ngày sau khi Concern đóng, và Concern chưa đóng.';
  }

  @override
  String get capaDetailTeam => 'Nhóm';

  @override
  String get commonNobodyIsOnThisInvestigationYet =>
      'Chưa có ai trong cuộc điều tra này.';

  @override
  String commonTeamLead(Object name) {
    return '$name · trưởng nhóm';
  }

  @override
  String get capaDetailTheProblem => 'Vấn đề';

  @override
  String get commonNobodyHasWrittenTheProblemDescriptionYet =>
      'Chưa ai viết mô tả vấn đề.';

  @override
  String get capaDetailCandidateCauses => 'Nguyên nhân ứng viên';

  @override
  String get capaDetailTheFishboneWhatTheTeamSuspectedBy =>
      'Biểu đồ xương cá: những gì nhóm nghi ngờ, theo hạng mục 6M, và bằng chứng nói gì về từng cái. Chuỗi tiếp theo bắt đầu từ nguyên nhân đã được xác nhận.';

  @override
  String get capaDetailThisInvestigationIsOverSoItsFishbone =>
      'Cuộc điều tra này đã kết thúc, nên biểu đồ xương cá của nó là hồ sơ chứ không phải danh sách việc.';

  @override
  String get capaDetailRecordACause => 'Ghi một nguyên nhân';

  @override
  String capaDetailNothingIsRecordedUnder(Object value) {
    return 'Chưa ghi gì dưới $value.';
  }

  @override
  String capaDetailCause(Object sequence) {
    return 'Nguyên nhân $sequence';
  }

  @override
  String commonEvidence(Object evidenceNote) {
    return 'Bằng chứng: $evidenceNote';
  }

  @override
  String get capaDetailChangeTheVerdict => 'Đổi kết luận';

  @override
  String get capaDetailDecideIt => 'Kết luận';

  @override
  String get capaDetailStartAChainFromIt => 'Bắt đầu chuỗi từ đó';

  @override
  String get capaDetailRootCause => 'Nguyên nhân gốc';

  @override
  String get capaDetailTwoChainsEachEndingAtOneConfirmed =>
      'Hai chuỗi, mỗi chuỗi kết thúc ở một nguyên nhân gốc đã xác nhận: vì sao vấn đề xảy ra, và vì sao nó không được phát hiện.';

  @override
  String get capaDetailThisInvestigationIsOverSoItsChains =>
      'Cuộc điều tra này đã kết thúc, nên các chuỗi của nó là hồ sơ chứ không phải danh sách việc.';

  @override
  String get commonAddAWhy => 'Thêm một Why';

  @override
  String get capaDetailOccurrence => 'lần xuất hiện';

  @override
  String get capaDetailWhyTheProblemHappenedOneStepAt =>
      'Vì sao vấn đề xảy ra, từng bước một.';

  @override
  String get capaDetailWhyItWasNotDetectedOneStep =>
      'Vì sao nó không được phát hiện, từng bước một.';

  @override
  String get commonNobodyHasStartedThisChainYet => 'Chưa ai bắt đầu chuỗi này.';

  @override
  String get commonThisChainHasNoConfirmedRootCause =>
      'Chuỗi này chưa có nguyên nhân gốc đã xác nhận.';

  @override
  String commonConfirmedRootCause(Object statement) {
    return 'Nguyên nhân gốc đã xác nhận: $statement';
  }

  @override
  String capaDetailWhy(Object sequence) {
    return 'Why $sequence';
  }

  @override
  String get capaDetailConfirmedRootCause => 'Nguyên nhân gốc đã xác nhận';

  @override
  String get capaDetailClearTheRootCause => 'Bỏ đánh dấu nguyên nhân gốc';

  @override
  String get capaDetailThisIsTheRootCause => 'Đây là nguyên nhân gốc';

  @override
  String get capaDetailMoveItEarlierInTheChain =>
      'Chuyển lên trước trong chuỗi';

  @override
  String get capaDetailMoveItLaterInTheChain => 'Chuyển ra sau trong chuỗi';

  @override
  String get capaDetailTheConcern => 'Concern';

  @override
  String capaDetailTheConcern2(Object actionNo) {
    return 'Concern: $actionNo';
  }

  @override
  String get capaDetailWhatTheConcernHasDone => 'Những gì Concern đã làm';

  @override
  String capaDetailWhatTheConcernHasDone2(Object length) {
    return 'Những gì Concern đã làm ($length)';
  }

  @override
  String get capaDetailTheContainmentD3TheCountermeasuresD5D6 =>
      'Biện pháp ngăn chặn (D3), biện pháp khắc phục (D5-D6) và hành động phòng ngừa (D7) là của chính Concern, được ghi một lần trong nhật ký hành động — ở đây là nơi đọc chúng, không phải nơi ghi lại.';

  @override
  String get capaDetailNothingAnswersThisConcernYetSoThere =>
      'Chưa có gì trả lời Concern này nên chưa có việc để hiển thị.';

  @override
  String commonCycle(Object cycle, Object phaseLabel) {
    return 'Chu kỳ $cycle · $phaseLabel';
  }

  @override
  String get commonOpen2 => 'mở';

  @override
  String capaEffectivenessIsSoItsEffectivenessIsRecordedAnd(
    Object capaNo,
    Object value,
  ) {
    return '$capaNo đang $value, nên hiệu quả của nó đã được ghi và hồ sơ được đọc chứ không sửa.';
  }

  @override
  String get capaEffectivenessNotYoursToDecide =>
      'Không phải phần bạn được quyết';

  @override
  String get capaEffectivenessRecordingACapaSEffectivenessCheckNeeds =>
      'Ghi bước kiểm tra hiệu quả của CAPA cần thẩm quyền Chất lượng tại Đơn vị tổ chức của nó.';

  @override
  String get capaEffectivenessSomebodyElseHasToCheckThis =>
      'Người khác phải kiểm tra việc này';

  @override
  String capaEffectivenessYouLeadTheInvestigationOnSoYou(Object capaNo) {
    return 'Bạn dẫn cuộc điều tra trên $capaNo, nên bạn là người duy nhất mà đánh giá về bản sửa này không phải bằng chứng. Một người có thẩm quyền Chất lượng không thuộc tài khoản trưởng nhóm sẽ ghi bước kiểm tra.';
  }

  @override
  String capaEffectivenessTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  ) {
    return 'Bước kiểm tra đến hạn $effectivenessCheckDelayDays ngày sau khi Concern đóng.';
  }

  @override
  String capaEffectivenessTheConcernClosedAndTheCheckFell(
    Object effectivenessCheckDueAt,
  ) {
    return 'Concern đã đóng, và bước kiểm tra đến hạn vào $effectivenessCheckDueAt.';
  }

  @override
  String get capaEffectivenessWhatTheCheckFound => 'Bước kiểm tra tìm thấy gì';

  @override
  String capaEffectivenessAChainOfThisInvestigationHasNo(Object value) {
    return 'Một chuỗi của cuộc điều tra này chưa có nguyên nhân gốc đã xác nhận, nên không thể đóng với “$value”: cuộc điều tra phải kết thúc trước khi đánh giá bản sửa có giữ được kết quả hay không.';
  }

  @override
  String get capaEffectivenessWhatYouCheckedAndWhatYouFound =>
      'Bạn đã kiểm tra gì, và tìm thấy gì';

  @override
  String get capaEffectivenessTheEvidenceForTheVerdictSoThe =>
      'Bằng chứng cho kết luận, để người đọc sau cân nhắc được.';

  @override
  String get capaOrgUnitFilterChooseTheOrgUnitWhoseInvestigationsAnd =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc các cuộc điều tra cùng mọi thứ bên dưới nó, hoặc xoá về tất cả.';

  @override
  String get capaReportThatCapaReportCouldNotBeRead =>
      'Không đọc được báo cáo CAPA đó';

  @override
  String get capaReportThe8dRecordOfThisInvestigationIts =>
      'Hồ sơ 8D của cuộc điều tra này: nhóm của nó, vấn đề nó trả lời, đã làm gì, và bản sửa có giữ được kết quả hay không.';

  @override
  String capaReportAnswersTheConcern(Object actionNo, Object title) {
    return 'Trả lời Concern $actionNo · $title';
  }

  @override
  String get capaReportNotYetDone => 'Chưa làm';

  @override
  String get capaReportWhatThisReportIsStillWaitingFor =>
      'Báo cáo này còn đang chờ gì.';

  @override
  String get capaReportD1Team => 'D1 · Nhóm';

  @override
  String get capaReportWhoInvestigatedThisProblemAndWhoLed =>
      'Ai đã điều tra vấn đề này, và ai dẫn dắt.';

  @override
  String get capaReportD2TheProblem => 'D2 · Vấn đề';

  @override
  String get capaReportWhatTheTeamIsInvestigatingInThe =>
      'Nhóm đang điều tra gì, bằng chính lời của cuộc điều tra.';

  @override
  String get capaReportD3Containment => 'D3 · Ngăn chặn';

  @override
  String get capaReportWhatWasDoneToStopTheBad =>
      'Đã làm gì để chặn sản phẩm lỗi lan tiếp.';

  @override
  String get capaReportD4RootCause => 'D4 · Nguyên nhân gốc';

  @override
  String get capaReportTheCandidateCausesTheTeamConsideredAnd =>
      'Các nguyên nhân ứng viên nhóm đã xem xét và kết luận cho từng cái, rồi hai chuỗi kết thúc ở một nguyên nhân gốc đã xác nhận: vì sao vấn đề xảy ra, và vì sao nó không được phát hiện.';

  @override
  String get capaReportD5D6Countermeasures => 'D5–D6 · Biện pháp khắc phục';

  @override
  String get capaReportWhatWasDoneAboutTheCauseAnd =>
      'Đã làm gì về nguyên nhân, và bước Check của nó có giữ được kết quả hay không.';

  @override
  String get capaReportD7PreventiveActions => 'D7 · Hành động phòng ngừa';

  @override
  String get capaReportWhatStopsItHappeningOnThisLine =>
      'Điều gì chặn nó tái diễn trên chuyền này, kèm kết quả của từng vòng.';

  @override
  String get capaReportTheSafetyIncidentThisInvestigationAnswers =>
      'Sự cố an toàn mà cuộc điều tra này trả lời';

  @override
  String get capaReportTheIncidentTheConcernWasRaisedFrom =>
      'Sự cố mà Concern được nêu từ đó, kèm số hiệu và mức độ — không bao giờ là chi tiết thương tích, thứ hồ sơ sự cố tự giới hạn.';

  @override
  String get capaReportTheNonConformancesThisInvestigationAnswers =>
      'Các Sản phẩm không phù hợp mà cuộc điều tra này trả lời';

  @override
  String get capaReportTheOccurrencesTheConcernAnswersWithThe =>
      'Những lần xuất hiện mà Concern trả lời, kèm số hiệu, Sản phẩm, Mã lỗi, số lượng và quyết định về sản phẩm.';

  @override
  String get capaReportNoNonConformanceIsLinkedToThis =>
      'Chưa có Sản phẩm không phù hợp nào được liên kết với Concern này, nên báo cáo không có bằng chứng để liệt kê.';

  @override
  String get capaReportNoPhaseOfThisActionHasBeen =>
      'Chưa giai đoạn nào của Hành động này được hoàn thành.';

  @override
  String get capaReportTheCandidateCausesConsidered =>
      'Các nguyên nhân ứng viên đã xem xét';

  @override
  String get capaReportNoCandidateCauseIsRecordedSoNo =>
      'Chưa ghi nguyên nhân ứng viên nào nên chưa làm biểu đồ xương cá.';

  @override
  String capaReportWhy(Object sequence, Object statement) {
    return 'Why $sequence · $statement';
  }

  @override
  String get capaReportD8Effectiveness => 'D8 · Hiệu quả';

  @override
  String capaReportVerifiedByOn(Object value, Object value2) {
    return 'xác minh bởi $value ngày $value2';
  }

  @override
  String capaReportTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  ) {
    return 'Bước kiểm tra đến hạn $effectivenessCheckDelayDays ngày sau khi Concern đóng, và Concern chưa đóng, nên chưa xác minh gì.';
  }

  @override
  String get capaReportRaisedFromThis => 'nêu từ đây';

  @override
  String get capaReportLinkedToThisConcern => 'liên kết với Concern này';

  @override
  String get capaReportNoProductFromThisOccurrenceHasA =>
      'Chưa sản phẩm nào của lần xuất hiện này có Phương án xử lý.';

  @override
  String capaReportMinRework(Object value) {
    return '$value phút làm lại';
  }

  @override
  String capaReportDecidedBy(Object decidedBy) {
    return 'quyết định bởi $decidedBy';
  }

  @override
  String get capaWhyThatIsNotAChain => 'Đó không phải một chuỗi';

  @override
  String get capaWhyACapaReasonsWithTwoChainsWhy =>
      'CAPA lý luận bằng hai chuỗi: vì sao vấn đề xảy ra, và vì sao nó không được phát hiện.';

  @override
  String capaWhyIsSoItsChainsAreARecord(Object capaNo, Object value) {
    return '$capaNo đang $value, nên các chuỗi của nó là hồ sơ chứ không phải danh sách việc.';
  }

  @override
  String get capaWhyThatWhyIsNotInThisChain =>
      'Why đó không nằm trong chuỗi này';

  @override
  String capaWhyReviseWhy(Object sequence) {
    return 'Sửa Why $sequence';
  }

  @override
  String capaWhyRemoveWhy(Object sequence) {
    return 'Xoá Why $sequence?';
  }

  @override
  String get capaWhyItIsTakenOutOfTheChain =>
      'Nó bị bỏ khỏi chuỗi vĩnh viễn, và các Why sau nó dồn lên một bậc. Phần còn lại của cuộc điều tra không bị đụng tới.';

  @override
  String capaWhyOneStepOfTheReasoningInYour(Object value) {
    return '$value — một bước lập luận, bằng lời của bạn.';
  }

  @override
  String get capaWhyTheWhy => 'Why';

  @override
  String get capaWhyWhatYouFoundSaidSoTheNext =>
      'Điều bạn tìm ra, nói sao cho người sau theo được.';

  @override
  String get capasTheCapaListCouldNotBeRead => 'Không đọc được danh sách CAPA';

  @override
  String get capasTheInvestigationsOpenedOnAConcernAnd =>
      'Các cuộc điều tra đã mở trên một Concern, và bước kiểm tra hiệu quả mà mỗi cuộc đang chờ.';

  @override
  String get capasOverdueChecks => 'Kiểm tra quá hạn';

  @override
  String get capasThereAreMoreInvestigationsThanThisList =>
      'Còn nhiều cuộc điều tra hơn danh sách này hiển thị. Hãy thu hẹp theo Đơn vị tổ chức hoặc trạng thái.';

  @override
  String get capasNoInvestigationMatchesTheOrgUnitStatus =>
      'Không cuộc điều tra nào khớp Đơn vị tổ chức, trạng thái hay bước kiểm tra quá hạn bạn chọn.';

  @override
  String get capasNoInvestigationsYet => 'Chưa có cuộc điều tra nào';

  @override
  String get capasACapaIsOpenedFromAConcern =>
      'CAPA được mở từ một Concern, khi có người quyết định vấn đề cần nguyên nhân gốc và một bản sửa giữ được kết quả.';

  @override
  String get capasInvestigation => 'Cuộc điều tra';

  @override
  String get capasEffectivenessCheck => 'Kiểm tra hiệu quả';

  @override
  String get capasOverdueCheck => 'Kiểm tra quá hạn';

  @override
  String capasRecordedBy(Object value, Object value2) {
    return '$value, ghi bởi $value2.';
  }

  @override
  String capasTheEffectivenessCheckWasDueOn(Object effectivenessCheckDueAt) {
    return 'Bước kiểm tra hiệu quả đã đến hạn vào $effectivenessCheckDueAt.';
  }

  @override
  String capasTheEffectivenessCheckIsDueOn(Object effectivenessCheckDueAt) {
    return 'Bước kiểm tra hiệu quả đến hạn vào $effectivenessCheckDueAt.';
  }

  @override
  String capasTheEffectivenessCheckFallsDueDaysAfter(
    Object effectivenessCheckDelayDays,
  ) {
    return 'Bước kiểm tra hiệu quả đến hạn $effectivenessCheckDelayDays ngày sau khi Concern đóng.';
  }

  @override
  String capasOnTheTeam(Object length) {
    return '$length người trong nhóm';
  }

  @override
  String get openCapaOpeningACapaNeedsAuthority => 'Mở CAPA cần thẩm quyền';

  @override
  String get openCapaOpeningACapaNeedsQualityAuthorityAt =>
      'Mở CAPA cần thẩm quyền Chất lượng tại Đơn vị tổ chức của Concern này.';

  @override
  String openCapaOpenACapaOn(Object actionNo) {
    return 'Mở CAPA trên $actionNo';
  }

  @override
  String get openCapaOpenTheCapa => 'Mở CAPA';

  @override
  String openCapaAn8dInvestigationInTheActionLog(Object title) {
    return '$title — một cuộc điều tra 8D, trong nhật ký hành động, trên Concern này. Biện pháp ngăn chặn, khắc phục và phòng ngừa là của chính Concern và được đọc trên CAPA chứ không ghi lại.';
  }

  @override
  String get openCapaTheProblemOptional => 'Vấn đề (không bắt buộc)';

  @override
  String get openCapaD2WhatTheInvestigationIsAboutIn =>
      'D2 — cuộc điều tra nói về điều gì, bằng lời mà nhóm sẽ làm việc theo.';

  @override
  String get openCapaTheTeam => 'Nhóm';

  @override
  String get openCapaChosenFromTheEmployeeDirectoryLeaveIt =>
      'Chọn từ Danh bạ Nhân viên. Để trống để quyết định nhóm sau — việc đang mở ở đây là cuộc điều tra.';

  @override
  String get openCapaTeamLeadOptional => 'Trưởng nhóm (không bắt buộc)';

  @override
  String get openCapaWhoIsAnswerableForTheInvestigation =>
      'Ai chịu trách nhiệm về cuộc điều tra.';

  @override
  String get openCapaAddATeamMemberOptional =>
      'Thêm thành viên nhóm (không bắt buộc)';

  @override
  String get openCapaNobodyElseIsOnThisInvestigationYet =>
      'Chưa có ai khác trong cuộc điều tra này.';

  @override
  String awaitingApprovalYouReSignedInAsButAn(Object email) {
    return 'Bạn đã đăng nhập với $email, nhưng quản trị viên chưa chấp nhận bạn vào Nền tảng. Hãy quay lại kiểm tra sau khi được chấp nhận.';
  }

  @override
  String get awaitingApprovalCheckAgain => 'Kiểm tra lại';

  @override
  String get signInPassword => 'Mật khẩu';

  @override
  String get signInCreateAnAccount => 'Tạo tài khoản';

  @override
  String get signInContinueWithGoogle => 'Tiếp tục với Google';

  @override
  String get signInOneApplicationForRunningSeveralManufacturingPlants =>
      'Một ứng dụng để vận hành nhiều nhà máy sản xuất.';

  @override
  String get accessDeniedNotAvailableToYou => 'Bạn không có quyền xem mục này';

  @override
  String get accessDeniedThisPartOfThePlatformIsFor =>
      'Phần này của Nền tảng dành cho quản trị viên. Hãy hỏi một quản trị viên nếu bạn cần những gì ở đây.';

  @override
  String get commonBackToHome => 'Về Trang chủ';

  @override
  String get changePasswordAnAdministratorResetYourPasswordSoThe =>
      'Quản trị viên đã đặt lại mật khẩu của bạn, nên mật khẩu bạn nhận được là tạm thời. Hãy chọn mật khẩu của riêng bạn để tiếp tục.';

  @override
  String get notFoundScreenNotFound => 'Không tìm thấy màn hình';

  @override
  String notFoundThereIsNothingAt(Object location) {
    return 'Không có gì ở $location.';
  }

  @override
  String get sessionErrorTheSessionCouldNotBeChecked =>
      'Không kiểm tra được phiên làm việc';

  @override
  String sessionErrorCouldNotCheckThisAccountSStatus(Object message) {
    return 'Không kiểm tra được trạng thái của Tài khoản này: $message';
  }

  @override
  String get appDateFieldChooseADate => 'Chọn một ngày';

  @override
  String get appDateTimeFieldChooseADateAndTime => 'Chọn ngày và giờ';

  @override
  String get appSearchFieldNoMatches => 'Không có kết quả';

  @override
  String appSearchFieldNothingMatchedTryADifferentTerm(Object lastQueriedTerm) {
    return 'Không có gì khớp “$lastQueriedTerm” — hãy thử từ khoá khác.';
  }

  @override
  String get appSearchFieldSearchFailed => 'Tìm kiếm không thành công';

  @override
  String get appSearchFieldThereAreMoreMatchesThanAreShown =>
      'Còn nhiều kết quả hơn số đang hiện — hãy gõ tiếp để thu hẹp danh sách.';

  @override
  String failureStateNotVisibleToYou(Object message) {
    return 'Bạn không có quyền xem. $message';
  }

  @override
  String get failureStateNotVisibleToYou2 => 'Bạn không có quyền xem';

  @override
  String get signaturePadSignatureDrawingArea => 'Vùng vẽ chữ ký';

  @override
  String get complaintDetailThatComplaintCouldNotBeRead =>
      'Không đọc được khiếu nại đó';

  @override
  String get complaintDetailBackToCustomerComplaints =>
      'Về Khiếu nại khách hàng';

  @override
  String get commonPastDue => 'Quá hạn';

  @override
  String get commonWarrantyClaim => 'Yêu cầu bảo hành';

  @override
  String get complaintDetailTheProductThisIsAbout =>
      'Sản phẩm mà khiếu nại này nói tới';

  @override
  String get complaintDetailNothingControlsTheProductThisCustomerComplained =>
      'Chưa có gì kiểm soát sản phẩm mà khách hàng khiếu nại. Hãy ghi nhận một Sản phẩm không phù hợp từ khiếu nại này, hoặc liên kết một bản đã có cho cùng Sản phẩm.';

  @override
  String get commonLinkOneThatExists => 'Liên kết một bản đã có';

  @override
  String get commonOpenRecord => 'Mở bản ghi';

  @override
  String get complaintDetailCustomer => 'khách hàng';

  @override
  String get complaintDetailFoundByTheCustomerSoThisComplaint =>
      'Do khách hàng phát hiện, nên khiếu nại này là nơi mọi việc bắt đầu.';

  @override
  String complaintDetailRecordedAtAndLinkedToThisComplaint(Object value) {
    return 'Ghi nhận ngày $value, và đã liên kết với khiếu nại này.';
  }

  @override
  String get commonOpenTheNonConformance => 'Mở Sản phẩm không phù hợp';

  @override
  String get commonTheResponse => 'Phản hồi';

  @override
  String complaintDetailClosed(Object closedAt) {
    return 'Đã đóng $closedAt';
  }

  @override
  String get complaintDetailNothingHasBeenSaidBackToThis =>
      'Chưa phản hồi gì lại cho khách hàng này.';

  @override
  String get complaintDetailCloseWithTheResponse => 'Đóng bằng phản hồi';

  @override
  String get complaintFormRecordACustomerComplaint =>
      'Ghi nhận khiếu nại khách hàng';

  @override
  String get complaintFormCustomer => 'Khách hàng';

  @override
  String get commonDefectCodeOptional => 'Mã lỗi (không bắt buộc)';

  @override
  String get complaintFormWhatTheCustomerSaysIsWrongA =>
      'Điều khách hàng nói là sai. Sản phẩm không phù hợp ghi nhận từ khiếu nại này sẽ mang theo nội dung đó.';

  @override
  String get commonNotKnownYet => 'Chưa biết';

  @override
  String get complaintFormQuantityOptional => 'Số lượng (không bắt buộc)';

  @override
  String get complaintFormInTheProductSOwnUnitOf =>
      'Theo đơn vị đo của chính Sản phẩm.';

  @override
  String get complaintFormResponseDueOptional =>
      'Hạn phản hồi (không bắt buộc)';

  @override
  String get complaintFormTheDayTheCustomerWasPromisedAn =>
      'Ngày đã hứa với khách hàng là sẽ có câu trả lời.';

  @override
  String get complaintFormWhatTheCustomerSaid => 'Khách hàng đã nói gì';

  @override
  String get complaintFormWhoAnswersIt => 'Ai trả lời khiếu nại này';

  @override
  String get complaintFormChooseTheOrgUnitThatWillAnswer =>
      'Chọn Đơn vị tổ chức sẽ trả lời khiếu nại này. Đây là điều quyết định ai được thao tác trên nó.';

  @override
  String complaintFormThisComplaintWillBeFiledAt(Object value) {
    return 'Khiếu nại này sẽ được ghi nhận tại $value.';
  }

  @override
  String get commonLinkANonConformance => 'Liên kết Sản phẩm không phù hợp';

  @override
  String get commonLinking => 'Đang liên kết…';

  @override
  String get commonLinkIt => 'Liên kết';

  @override
  String complaintLinkANonConformanceThatAlreadyExistsFor(Object productName) {
    return 'Một Sản phẩm không phù hợp đã có cho $productName có thể được liên kết với khiếu nại này, thay vì ghi nhận thêm bản thứ hai cho cùng vấn đề.';
  }

  @override
  String get commonTheNonConformancesCouldNotBeRead =>
      'Không đọc được danh sách Sản phẩm không phù hợp';

  @override
  String get complaintLinkNoNonConformanceHasBeenRecordedFor =>
      'Chưa ghi nhận Sản phẩm không phù hợp nào cho Sản phẩm này nên không có gì để liên kết. Hãy ghi nhận một bản từ khiếu nại này thay vào.';

  @override
  String get commonTheNonConformanceThatControlsIt =>
      'Sản phẩm không phù hợp kiểm soát nó';

  @override
  String get complaintNonconformanceControlTheProduct => 'Kiểm soát sản phẩm';

  @override
  String complaintNonconformanceANonConformanceIsRecordedAtFor(
    Object orgUnitName,
    Object productName,
  ) {
    return 'Một Sản phẩm không phù hợp sẽ được ghi nhận tại $orgUnitName cho $productName, do khách hàng phát hiện.';
  }

  @override
  String get complaintNonconformanceHowMuchProductIsInQuestionIn =>
      'Có bao nhiêu sản phẩm bị nghi vấn, theo đơn vị của chính Sản phẩm.';

  @override
  String get complaintNonconformanceTheComplaintSOwnDefectCodeIs =>
      'Mã lỗi của khiếu nại được mang sang bản ghi.';

  @override
  String get commonTheDefectCodesCouldNotBeRead =>
      'Không đọc được danh mục Mã lỗi';

  @override
  String get complaintNonconformanceThisComplaintCarriesNoneSoChooseThe =>
      'Khiếu nại này không mang mã nào, nên hãy chọn mã để ghi nhận.';

  @override
  String get commonWhatWasDoneAtOnceRecordingIt =>
      'Đã làm gì ngay lúc đó. Ghi nhận bước này sẽ đưa bản ghi vào trạng thái đã ngăn chặn.';

  @override
  String get commonNarrowTheRegister => 'Thu hẹp danh sách';

  @override
  String get complaintOrgUnitFilterChooseTheOrgUnitWhoseComplaintsAnd =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc khiếu nại cùng mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String get complaintRespondAnswerTheCustomer => 'Trả lời khách hàng';

  @override
  String get complaintRespondClosing => 'Đang đóng…';

  @override
  String get complaintRespondCloseTheComplaint => 'Đóng khiếu nại';

  @override
  String complaintRespondWhatWasSaidBackToAboutThis(
    Object customerName,
    Object complaintNo,
  ) {
    return 'Điều đã phản hồi cho $customerName về $complaintNo. Việc này đóng khiếu nại.';
  }

  @override
  String get complaintsTheComplaintRegisterCouldNotBeRead =>
      'Không đọc được danh sách khiếu nại';

  @override
  String get complaintsWhatCustomersHaveComplainedAboutAtThis =>
      'Những gì khách hàng đã khiếu nại tại Nhà máy này, và sản phẩm bị khiếu nại có đang được kiểm soát hay không.';

  @override
  String get complaintsRecordAComplaint => 'Ghi nhận khiếu nại';

  @override
  String get complaintsThereAreMoreComplaintsThanThisList =>
      'Còn nhiều khiếu nại hơn danh sách này hiển thị. Hãy thu hẹp theo Đơn vị tổ chức hoặc theo trạng thái để xem phần còn lại.';

  @override
  String get complaintsTheRegisterHasComplaintsButNoneOf =>
      'Danh sách có khiếu nại, nhưng không cái nào thuộc khu vực hay trạng thái bạn đã chọn.';

  @override
  String get complaintsNoComplaints => 'Không có khiếu nại nào';

  @override
  String get complaintsNoCustomerHasComplainedAboutAnythingFrom =>
      'Chưa khách hàng nào khiếu nại về sản phẩm nào từ Nhà máy này.';

  @override
  String get complaintsComplaint => 'Khiếu nại';

  @override
  String get complaintsCustomerAndProduct => 'Khách hàng và sản phẩm';

  @override
  String get complaintsResponseDue => 'Hạn phản hồi';

  @override
  String get commonControl => 'Kiểm soát';

  @override
  String get complaintsWarranty => 'Bảo hành';

  @override
  String get customerFormCorrectCustomer => 'Sửa Khách hàng';

  @override
  String get commonAddCustomer => 'Thêm Khách hàng';

  @override
  String get customerFormACustomerSCodeCannotBeCorrected =>
      'Không sửa được mã của Khách hàng';

  @override
  String get commonContactEmailOptional => 'Email liên hệ (không bắt buộc)';

  @override
  String get customersTheCustomerListCouldNotBeRead =>
      'Không đọc được danh sách Khách hàng';

  @override
  String get customersWhoThePlantSCustomersAreSo =>
      'Khách hàng của nhà máy là ai — để khiếu nại có người thuộc về và phản hồi có nơi gửi tới.';

  @override
  String get customersNoCustomersYet => 'Chưa có Khách hàng nào';

  @override
  String get commonNothingHasBeenDefinedInTheList => 'Danh sách chưa có gì.';

  @override
  String get customersFilterCustomers => 'Lọc Khách hàng';

  @override
  String get customersNoCustomersMatch => 'Không có Khách hàng nào khớp';

  @override
  String commonNothingInTheListMatchesTryA(Object term) {
    return 'Danh sách không có gì khớp “$term”. Hãy thử tên hoặc mã khác, hoặc xoá bộ lọc.';
  }

  @override
  String get defectCodeFormCorrectDefectCode => 'Sửa Mã lỗi';

  @override
  String get commonAddDefectCode => 'Thêm Mã lỗi';

  @override
  String get defectCodeFormADefectCodeCannotBeCorrected =>
      'Không sửa được Mã lỗi';

  @override
  String get defectCodeFormDefaultSeverity => 'Mức độ mặc định';

  @override
  String get defectCodeFormWhatANonConformanceRecordedAgainstThis =>
      'Mức độ mà một Sản phẩm không phù hợp ghi theo mã này sẽ bắt đầu';

  @override
  String get defectCodeFormParent => 'Mã cha';

  @override
  String get defectCodeFormNoParentTopLevel => 'Không có mã cha — cấp cao nhất';

  @override
  String get defectCodesTheDefectCodeCatalogueCouldNotBe =>
      'Không đọc được danh mục Mã lỗi';

  @override
  String get defectCodesTheKindsOfThingFoundWrongOne =>
      'Các kiểu sai hỏng — một danh mục dùng chung cho mọi Nhà máy, kèm mức độ mà mỗi mã bắt đầu.';

  @override
  String get defectCodesNoDefectCodesYet => 'Chưa có Mã lỗi nào';

  @override
  String get issueImagesRemoveThisPicture => 'Bỏ ảnh này?';

  @override
  String get issueImagesThePictureIsTakenOffTheRecord =>
      'Ảnh bị bỏ khỏi bản ghi. Một trang trình chiếu cần ảnh, nên vấn đề này có thể rời khỏi buổi trình chiếu cho tới khi có ảnh khác.';

  @override
  String get issueImagesAddPicture => 'Thêm ảnh';

  @override
  String get issueImagesPictures => 'Ảnh';

  @override
  String get issueImagesThePicturesCouldNotBeRead =>
      'Không đọc được danh sách ảnh';

  @override
  String get issueImagesNoPictureYetASlideNeedsAt =>
      'Chưa có ảnh. Một trang trình chiếu cần ít nhất một ảnh: hãy thêm ảnh cho thấy vấn đề.';

  @override
  String get commonThePictureCouldNotBeLoaded => 'Không tải được ảnh';

  @override
  String get issueImagesAPictureOfTheIssue => 'Ảnh của vấn đề';

  @override
  String get issueImagesRemoveThisPicture2 => 'Bỏ ảnh này';

  @override
  String get issueImagesAddThisPicture => 'Thêm ảnh này';

  @override
  String get issueImagesTheCaptionIsWhatTheSlideSays =>
      'Chú thích là dòng chữ trang trình chiếu nói dưới ảnh. Không bắt buộc.';

  @override
  String get issueImagesAddIt => 'Thêm vào';

  @override
  String get issueImagesCaptionOptional => 'Chú thích (không bắt buộc)';

  @override
  String get issueImagesBurrOnTheFlangeNearTheLocating =>
      'Ba via trên mặt bích, gần chốt định vị';

  @override
  String get nonconformanceCancelCannotCancelIt => 'Không huỷ được';

  @override
  String
  get nonconformanceCancelCancellingANonConformanceNeedsQualityAuthority =>
      'Huỷ một Sản phẩm không phù hợp cần thẩm quyền Chất lượng tại Đơn vị tổ chức của nó.';

  @override
  String get nonconformanceCancelANonConformanceThatIsClosedOr =>
      'Sản phẩm không phù hợp đã đóng hoặc đã huỷ thì không huỷ lại được.';

  @override
  String get nonconformanceCancelCancelThisNonConformance =>
      'Huỷ Sản phẩm không phù hợp này';

  @override
  String get nonconformanceCancelCancelIt => 'Huỷ bản ghi';

  @override
  String nonconformanceCancelWillBeCancelledRatherThanDealtWith(
    Object issueNo,
  ) {
    return '$issueNo sẽ bị huỷ thay vì được xử lý. Sản phẩm không phù hợp đã huỷ không nhận thêm Phương án xử lý hay thay đổi số lượng nào.';
  }

  @override
  String get commonNote => 'Ghi chú';

  @override
  String get nonconformanceCancelWhyItShouldNeverHaveBeenRecorded =>
      'Vì sao lẽ ra không nên ghi nhận bản này.';

  @override
  String get nonconformanceConcessionCannotGrantIt => 'Không cấp được';

  @override
  String
  get nonconformanceConcessionGrantingAConcessionNeedsQualityAuthorityAt =>
      'Cấp một Nhượng bộ cần thẩm quyền Chất lượng tại Đơn vị tổ chức của Sản phẩm không phù hợp này.';

  @override
  String get nonconformanceConcessionGrantIt => 'Cấp nhượng bộ';

  @override
  String nonconformanceConcessionAcceptingTheProductAsItIsNeeds(
    Object issueNo,
  ) {
    return 'Chấp nhận sản phẩm nguyên trạng cần thẩm quyền Chất lượng, và tên bạn sẽ nằm trên $issueNo.';
  }

  @override
  String get nonconformanceConcessionQuantityAcceptedAsItIs =>
      'Số lượng được chấp nhận nguyên trạng';

  @override
  String nonconformanceConcessionAtMost(Object value, Object unit) {
    return 'Tối đa $value $unit.';
  }

  @override
  String get nonconformanceConcessionReference => 'Số tham chiếu';

  @override
  String get nonconformanceConcessionTheDeviationOrApprovalNumberItIs =>
      'Số cho phép sai lệch hoặc số phê duyệt mà nhượng bộ này được cấp theo.';

  @override
  String get nonconformanceConcessionWhyTheProductIsAcceptableAsIt =>
      'Vì sao sản phẩm nguyên trạng vẫn chấp nhận được.';

  @override
  String nonconformanceDispositionHasStillUndecidedDealWithSomeOf(
    Object issueNo,
    Object value,
    Object unit,
  ) {
    return '$issueNo còn $value $unit chưa quyết. Hãy xử lý một phần ở đây.';
  }

  @override
  String get commonDisposition => 'Phương án xử lý';

  @override
  String get nonconformanceDispositionScrapReworkOrBackToTheSupplier =>
      'Huỷ bỏ, làm lại, hoặc trả lại nhà cung cấp.';

  @override
  String nonconformanceDispositionAtMost(Object value, Object unit) {
    return 'Tối đa $value $unit.';
  }

  @override
  String get nonconformanceDispositionReworkMinutes => 'Số phút làm lại';

  @override
  String get nonconformanceDispositionHowLongTheReworkTookForCost =>
      'Làm lại mất bao lâu, để tính chi phí chất lượng kém.';

  @override
  String get nonconformanceDispositionWhatWasDoneWithIt =>
      'Đã làm gì với số hàng đó.';

  @override
  String nonconformanceLinkConcernBecomesOneOfTheOccurrencesThisConcern(
    Object issueNo,
  ) {
    return '$issueNo trở thành một trong những lần xuất hiện mà Concern này trả lời. Concern vẫn giữ Sản phẩm không phù hợp mà nó được nêu từ đó.';
  }

  @override
  String get nonconformanceLinkConcernThisSiteHasNoOpenConcernTo =>
      'Nhà máy này không có Concern nào đang mở để liên kết. Hãy nêu một Concern mới.';

  @override
  String get nonconformanceLinkConcernConcern => 'Concern';

  @override
  String get nonconformanceLinkConcernByItsNumberOrItsTitle =>
      'Theo số hoặc tiêu đề của nó.';

  @override
  String get nonconformanceLowerSeverityCannotLowerIt => 'Không hạ được';

  @override
  String
  get nonconformanceLowerSeverityLoweringASeverityNeedsQualityAuthorityAt =>
      'Hạ mức độ cần thẩm quyền Chất lượng tại Đơn vị tổ chức của Sản phẩm không phù hợp này.';

  @override
  String get nonconformanceLowerSeverityLowerIt => 'Hạ mức độ';

  @override
  String nonconformanceLowerSeverityIsSeverityAndItsDefectCodeStarts(
    Object issueNo,
    Object value,
    Object value2,
  ) {
    return '$issueNo đang ở mức độ $value, và Mã lỗi của nó bắt đầu ở mức $value2.';
  }

  @override
  String get nonconformanceLowerSeverityThisNonConformanceIsAlreadyAtThe =>
      'Sản phẩm không phù hợp này đã ở mức độ nhẹ nhất.';

  @override
  String get nonconformanceLowerSeverityLowerTheSeverityTo => 'Hạ mức độ xuống';

  @override
  String get nonconformanceLowerSeverityLoweringWhatTheDefectCodeSaysNeeds =>
      'Hạ thấp hơn mức Mã lỗi quy định cần thẩm quyền Chất lượng.';

  @override
  String get commonLeaveTheSeverityAlone => 'Để nguyên mức độ';

  @override
  String get nonconformanceLowerSeverityWhyItIsLessBadThanThe =>
      'Vì sao trường hợp này nhẹ hơn mức Mã lỗi quy định.';

  @override
  String get nonconformanceOrgUnitFilterChooseTheOrgUnitWhoseNonConformances =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc Sản phẩm không phù hợp cùng mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String get nonconformanceQuantityIncreaseTheAffectedQuantity =>
      'Tăng số lượng ảnh hưởng';

  @override
  String get nonconformanceQuantityIncreaseIt => 'Tăng số lượng';

  @override
  String nonconformanceQuantityCurrentlyCoversItCanOnlyGrow(
    Object issueNo,
    Object value,
    Object unit,
  ) {
    return '$issueNo hiện bao $value $unit. Số lượng chỉ có thể tăng.';
  }

  @override
  String get nonconformanceQuantityNewAffectedQuantity =>
      'Số lượng ảnh hưởng mới';

  @override
  String nonconformanceQuantityMoreThanOrNothingAtAll(
    Object value,
    Object unit,
  ) {
    return 'Nhiều hơn $value $unit, hoặc không thêm gì.';
  }

  @override
  String get nonconformanceQuantityWhyItChangedSortingTheBinFound =>
      'Vì sao số lượng thay đổi — “soạn lại thùng thì thấy thêm tám cái”.';

  @override
  String nonconformanceRaiseConcernIsRecordedAtAndTheConcernIs(
    Object issueNo,
    Object orgUnitName,
  ) {
    return '$issueNo được ghi nhận tại $orgUnitName, và Concern được nêu ở đó — vấn đề được giải quyết tại nơi nó xảy ra.';
  }

  @override
  String get nonconformanceRaiseConcernWhatIsTheProblemToSolve =>
      'Vấn đề cần giải quyết là gì?';

  @override
  String get nonconformanceRaiseConcernTheConcernIsReadInTheAction =>
      'Concern được đọc trong nhật ký hành động, nên hãy nói vấn đề, đừng nói sản phẩm.';

  @override
  String get commonAnythingKnownYet => 'Đã biết gì chưa';

  @override
  String
  get nonconformanceRaiseConcernOptionalTheNonConformanceItselfIsAlready =>
      'Không bắt buộc. Bản thân Sản phẩm không phù hợp đã được liên kết làm bằng chứng.';

  @override
  String get common1IsWorst => '1 là nặng nhất.';

  @override
  String get nonconformanceReopenCannotReopenIt => 'Không mở lại được';

  @override
  String
  get nonconformanceReopenReopeningANonConformanceNeedsQualityAuthority =>
      'Mở lại một Sản phẩm không phù hợp cần thẩm quyền Chất lượng tại Đơn vị tổ chức của nó.';

  @override
  String get nonconformanceReopenOnlyAClosedNonConformanceCanBe =>
      'Chỉ Sản phẩm không phù hợp đã đóng mới mở lại được.';

  @override
  String get nonconformanceReopenReopenThisNonConformance =>
      'Mở lại Sản phẩm không phù hợp này';

  @override
  String nonconformanceReopenIsClosedReopeningItPutsItBack(Object issueNo) {
    return '$issueNo đã đóng. Mở lại sẽ đưa nó về trạng thái đã có phương án xử lý, và mốc thời gian đóng bị bỏ theo.';
  }

  @override
  String get nonconformanceReopenWhyItIsBeingReopened => 'Vì sao mở lại.';

  @override
  String nonconformanceUpdateIsSeverityAnd(
    Object issueNo,
    Object value,
    Object value2,
  ) {
    return '$issueNo đang ở mức độ $value và $value2.';
  }

  @override
  String get nonconformanceUpdateThisNonConformanceIsAlreadyAtThe =>
      'Sản phẩm không phù hợp này đã ở mức độ nặng nhất nên không nâng được nữa.';

  @override
  String get nonconformanceUpdateRaiseTheSeverityTo => 'Nâng mức độ lên';

  @override
  String get nonconformanceUpdateSeverityCanBeRaisedHereLoweringIt =>
      'Mức độ có thể nâng ở đây; hạ xuống là một quyết định riêng về sau.';

  @override
  String get nonconformanceUpdateRecordContainment => 'Ghi nhận ngăn chặn';

  @override
  String get nonconformancesNcHcm202600001 => 'NC-HCM-2026-00001';

  @override
  String get productFormCorrectProduct => 'Sửa Sản phẩm';

  @override
  String get commonAddProduct => 'Thêm Sản phẩm';

  @override
  String get productFormAProductSCodeCannotBeCorrected =>
      'Không sửa được mã của Sản phẩm';

  @override
  String get productFormAProductSUnitOfMeasureCannot =>
      'Không sửa được đơn vị đo của Sản phẩm';

  @override
  String get productFormTheUnitsOfMeasureCouldNotBe =>
      'Không đọc được danh sách đơn vị đo';

  @override
  String get productsTheProductCatalogueCouldNotBeRead =>
      'Không đọc được danh mục Sản phẩm';

  @override
  String get productsWhatThePlantMakesOneCatalogueShared =>
      'Nhà máy sản xuất gì — một danh mục dùng chung cho mọi Nhà máy, và mỗi Sản phẩm được đo bằng gì.';

  @override
  String get productsNoProductsYet => 'Chưa có Sản phẩm nào';

  @override
  String get slideShowTheSlideShowCouldNotBeRead =>
      'Không đọc được buổi trình chiếu';

  @override
  String get slideShowTheQualityIssuesChosenForThisSite =>
      'Các vấn đề chất lượng được chọn cho Nhà máy này, từng ảnh một. Hãy chọn vấn đề từ danh sách hoặc từ màn hình của nó, và sắp thứ tự ở đây.';

  @override
  String get slideShowPauseTheShow => 'Tạm dừng trình chiếu';

  @override
  String get slideShowPlayTheShow => 'Chạy trình chiếu';

  @override
  String get slideShowChooseTheOrder => 'Chọn thứ tự';

  @override
  String get slideShowNothingIsOnTheWallYet => 'Chưa có gì trên màn hình';

  @override
  String get slideShowChooseACustomerComplaintOrANon =>
      'Hãy chọn một Khiếu nại khách hàng hoặc một Sản phẩm không phù hợp trong danh sách của nó, và thêm ít nhất một ảnh. Các vấn đề được chọn sẽ hiện ở đây.';

  @override
  String slideShowChosenNoneWithAPicture(Object length) {
    return 'đã chọn $length, không cái nào có ảnh';
  }

  @override
  String slideShowASlideNeedsAPictureOpenAnd(Object value, Object value2) {
    return 'Một trang trình chiếu cần ảnh. Mở $value và thêm ảnh, rồi $value2 sẽ hiện ở đây.';
  }

  @override
  String slideShowAPictureOf(Object value) {
    return 'Ảnh của $value';
  }

  @override
  String get slideShowPreviousSlide => 'Trang trước';

  @override
  String get slideShowNoSlides => 'Không có trang nào';

  @override
  String get slideShowNextSlide => 'Trang sau';

  @override
  String slideShowChosenWithoutAPicture(Object length) {
    return '$length đã chọn nhưng chưa có ảnh';
  }

  @override
  String get slideShowTheOrderTheShowPlaysIn => 'Thứ tự buổi trình chiếu chạy';

  @override
  String get slideShowNothingIsChosenYet => 'Chưa chọn gì.';

  @override
  String slideShowPicture(Object value, Object value2) {
    return '$value ảnh$value2';
  }

  @override
  String get slideShowNoPictureYetItWillNotAppear =>
      'Chưa có ảnh — vấn đề sẽ không hiện cho tới khi có ảnh';

  @override
  String get slideShowMoveEarlier => 'Chuyển lên trước';

  @override
  String get slideShowMoveLater => 'Chuyển ra sau';

  @override
  String get slideShowTakeOffTheWall => 'Bỏ khỏi màn hình';

  @override
  String get slideShowToggleOnTheSlideShow => 'Đang trong buổi trình chiếu';

  @override
  String get slideShowToggleNotOnTheSlideShow => 'Không trong buổi trình chiếu';

  @override
  String get slideShowToggleChosenIssuesPlayInTheQualitySlide =>
      'Các vấn đề được chọn sẽ chạy trong buổi trình chiếu chất lượng, từng ảnh một.';

  @override
  String get supplierFormCorrectSupplier => 'Sửa Nhà cung cấp';

  @override
  String get commonAddSupplier => 'Thêm Nhà cung cấp';

  @override
  String get supplierFormASupplierSCodeCannotBeCorrected =>
      'Không sửa được mã của Nhà cung cấp';

  @override
  String get supplierNcrDetailThatSupplierNcrCouldNotBeRead =>
      'Không đọc được NCR nhà cung cấp đó';

  @override
  String get supplierNcrDetailBackToSupplierNcrs => 'Về NCR nhà cung cấp';

  @override
  String get supplierNcrDetailNothingWasWrittenDownAboutIt =>
      'Chưa ghi lại gì về việc này.';

  @override
  String get supplierNcrDetailTheMaterialThisIsAbout =>
      'Vật tư mà NCR này nói tới';

  @override
  String get supplierNcrDetailNothingControlsTheMaterialThisNcrIs =>
      'Chưa có gì kiểm soát vật tư mà NCR này nói tới. Hãy ghi nhận một Sản phẩm không phù hợp từ NCR này, hoặc liên kết một bản đã có cho cùng lô.';

  @override
  String get supplierNcrDetailIncoming => 'hàng về';

  @override
  String get supplierNcrDetailFoundAtGoodsInSoThisNcr =>
      'Phát hiện ở khâu nhận hàng, nên NCR này là nơi mọi việc bắt đầu.';

  @override
  String supplierNcrDetailRecordedAtAndLinkedToThisNcr(Object value) {
    return 'Ghi nhận ngày $value, và đã liên kết với NCR này.';
  }

  @override
  String get supplierNcrDetailTheSupplierSDisposition =>
      'Phương án xử lý của Nhà cung cấp';

  @override
  String get supplierNcrDetailNothingHasBeenRecoveredFromThisSupplier =>
      'Chưa thu hồi được gì từ Nhà cung cấp này.';

  @override
  String supplierNcrDetailRecovered(Object costRecoveredLabel) {
    return 'Đã thu hồi $costRecoveredLabel.';
  }

  @override
  String supplierNcrDetailClosed(Object closedAt) {
    return 'Đã đóng $closedAt';
  }

  @override
  String get commonRecordTheDisposition => 'Ghi nhận phương án xử lý';

  @override
  String get supplierNcrDetailCorrectTheDisposition => 'Sửa phương án xử lý';

  @override
  String get supplierNcrDetailCloseTheNcr => 'Đóng NCR';

  @override
  String get supplierNcrDispositionDecideTheMaterial => 'Quyết định vật tư';

  @override
  String supplierNcrDispositionWhatHappensToThatCameFromOn(
    Object quantityLabel,
    Object supplierName,
    Object ncrNo,
  ) {
    return 'Điều gì xảy ra với $quantityLabel đến từ $supplierName ngày $ncrNo.';
  }

  @override
  String get supplierNcrDispositionWhatThePlantDecidedHappensToThe =>
      'Nhà máy đã quyết định xử lý vật tư nhận về như thế nào.';

  @override
  String get supplierNcrDispositionCostRecoveredOptional =>
      'Chi phí thu hồi (không bắt buộc)';

  @override
  String get supplierNcrDispositionWhatWasClawedBackFromTheSupplier =>
      'Số tiền đòi lại được từ Nhà cung cấp. Để trống nếu không đòi gì.';

  @override
  String get supplierNcrDispositionThreeLettersTheCurrencyTheCostRecovered =>
      'Ba chữ cái, đơn vị tiền của khoản thu hồi.';

  @override
  String get commonRecordASupplierNcr => 'Ghi nhận NCR nhà cung cấp';

  @override
  String get commonSupplier => 'Nhà cung cấp';

  @override
  String get supplierNcrFormProductOptional => 'Sản phẩm (không bắt buộc)';

  @override
  String get supplierNcrFormWhatTheLotIsWhenThatIs =>
      'Lô hàng là gì, khi đã biết. Sản phẩm không phù hợp ghi nhận từ NCR này cần thông tin đó.';

  @override
  String get supplierNcrFormNotNamedYet => 'Chưa nêu tên';

  @override
  String get supplierNcrFormWhatIsWrongWithItANon =>
      'Sai ở chỗ nào. Sản phẩm không phù hợp ghi nhận từ NCR này sẽ mang theo nội dung đó.';

  @override
  String get supplierNcrFormHowMuchCameInWrong => 'Bao nhiêu hàng về bị sai.';

  @override
  String get supplierNcrFormWhatTheQuantityIsCountedInTaken =>
      'Số lượng được tính theo đơn vị nào. Lấy từ Sản phẩm khi đã chọn Sản phẩm.';

  @override
  String get supplierNcrFormIncomingLotReferenceOptional =>
      'Số tham chiếu lô hàng về (không bắt buộc)';

  @override
  String get supplierNcrFormTheLotTheDeliveryNoteSays =>
      'Lô mà phiếu giao hàng ghi.';

  @override
  String get supplierNcrFormPurchaseReferenceOptional =>
      'Số tham chiếu mua hàng (không bắt buộc)';

  @override
  String get supplierNcrFormTheOrderItArrivedAgainst =>
      'Đơn hàng mà lô này về theo.';

  @override
  String get supplierNcrFormAnswerDueOptional => 'Hạn trả lời (không bắt buộc)';

  @override
  String get supplierNcrFormTheDayTheSupplierWasGivenTo =>
      'Ngày đã giao cho Nhà cung cấp để trả lời.';

  @override
  String get supplierNcrFormWhatIsWrongWithItOptional =>
      'Sai ở chỗ nào (không bắt buộc)';

  @override
  String get supplierNcrFormWhoWorksIt => 'Ai xử lý NCR này';

  @override
  String get supplierNcrFormChooseTheOrgUnitThatWillWork =>
      'Chọn Đơn vị tổ chức sẽ xử lý NCR nhà cung cấp này. Đây là điều quyết định ai được thao tác trên nó.';

  @override
  String supplierNcrFormThisSupplierNcrWillBeFiledAt(Object value) {
    return 'NCR nhà cung cấp này sẽ được ghi nhận tại $value.';
  }

  @override
  String supplierNcrLinkANonConformanceThatAlreadyExistsCan(Object value) {
    return 'Một Sản phẩm không phù hợp đã có$value có thể được liên kết với NCR nhà cung cấp này, thay vì ghi nhận thêm bản thứ hai cho cùng vấn đề.';
  }

  @override
  String get supplierNcrLinkNoNonConformanceHasBeenRecordedFor =>
      'Chưa ghi nhận Sản phẩm không phù hợp nào cho Sản phẩm này nên không có gì để liên kết. Hãy ghi nhận một bản từ NCR nhà cung cấp này thay vào.';

  @override
  String get supplierNcrNonconformanceControlTheMaterial => 'Kiểm soát vật tư';

  @override
  String supplierNcrNonconformanceANonConformanceIsRecordedAtFound(
    Object orgUnitName,
    Object value,
  ) {
    return 'Một Sản phẩm không phù hợp sẽ được ghi nhận tại $orgUnitName$value, phát hiện ở khâu nhận hàng.';
  }

  @override
  String get supplierNcrNonconformanceHowMuchMaterialIsInQuestionIn =>
      'Có bao nhiêu vật tư bị nghi vấn, theo đơn vị mà lô hàng về.';

  @override
  String get supplierNcrNonconformanceTheSupplierNcrSOwnProductIs =>
      'Sản phẩm của chính NCR nhà cung cấp được mang sang bản ghi.';

  @override
  String get supplierNcrNonconformanceTheProductsCouldNotBeRead =>
      'Không đọc được danh sách Sản phẩm';

  @override
  String get supplierNcrNonconformanceThisSupplierNcrNamesNoneSoChoose =>
      'NCR nhà cung cấp này không nêu Sản phẩm nào, nên hãy chọn lô hàng dùng cho việc gì.';

  @override
  String get supplierNcrNonconformanceTheSupplierNcrSOwnDefectCode =>
      'Mã lỗi của chính NCR nhà cung cấp được mang sang bản ghi.';

  @override
  String get supplierNcrNonconformanceThisSupplierNcrCarriesNoneSoChoose =>
      'NCR nhà cung cấp này không mang mã nào, nên hãy chọn mã để ghi nhận.';

  @override
  String get supplierNcrOrgUnitFilterChooseTheOrgUnitWhoseSupplierNcrs =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc NCR nhà cung cấp cùng mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String get supplierNcrSupplierFilterFilterBySupplier =>
      'Lọc theo Nhà cung cấp';

  @override
  String get commonAllSuppliers => 'Tất cả nhà cung cấp';

  @override
  String get supplierNcrSupplierFilterChooseTheSupplierWhoseSupplierNcrsYou =>
      'Chọn Nhà cung cấp mà bạn muốn đọc NCR, hoặc xoá về mọi Nhà cung cấp.';

  @override
  String get supplierNcrsTheSupplierNcrRegisterCouldNotBe =>
      'Không đọc được danh sách NCR nhà cung cấp';

  @override
  String get supplierNcrsWhatArrivedWrongFromASupplierAt =>
      'Những gì về sai từ Nhà cung cấp tại Nhà máy này, và vật tư đi kèm có đang được kiểm soát hay không.';

  @override
  String get supplierNcrsThereAreMoreSupplierNcrsThanThis =>
      'Còn nhiều NCR nhà cung cấp hơn danh sách này hiển thị. Hãy thu hẹp theo Nhà cung cấp hoặc theo trạng thái để xem phần còn lại.';

  @override
  String get supplierNcrsTheRegisterHasSupplierNcrsButNone =>
      'Danh sách có NCR nhà cung cấp, nhưng không bản nào thuộc khu vực, Nhà cung cấp hay trạng thái bạn đã chọn.';

  @override
  String get supplierNcrsNoSupplierNcrs => 'Không có NCR nhà cung cấp nào';

  @override
  String get supplierNcrsNothingHasComeInWrongFromA =>
      'Chưa có gì về sai từ Nhà cung cấp tại Nhà máy này.';

  @override
  String get supplierNcrsNcr => 'NCR';

  @override
  String get supplierNcrsSupplierAndProduct => 'Nhà cung cấp và sản phẩm';

  @override
  String get supplierNcrsAnswerDue => 'Hạn trả lời';

  @override
  String get suppliersTheSupplierListCouldNotBeRead =>
      'Không đọc được danh sách Nhà cung cấp';

  @override
  String get suppliersWhoThePlantBuysFromSoAn =>
      'Nhà máy mua hàng từ ai — để một lô hàng về bị sai có người thuộc về và một yêu cầu đòi bồi thường có nơi gửi tới.';

  @override
  String get suppliersNoSuppliersYet => 'Chưa có Nhà cung cấp nào';

  @override
  String get suppliersFilterSuppliers => 'Lọc Nhà cung cấp';

  @override
  String get suppliersNoSuppliersMatch => 'Không có Nhà cung cấp nào khớp';

  @override
  String get bodyPartFormCorrectBodyPart => 'Sửa Bộ phận cơ thể';

  @override
  String get commonAddBodyPart => 'Thêm Bộ phận cơ thể';

  @override
  String get bodyPartFormABodyPartSCodeCannotBe =>
      'Không sửa được mã của Bộ phận cơ thể';

  @override
  String get bodyPartFormRegion => 'Vùng cơ thể';

  @override
  String get bodyPartFormARetiredBodyPartIsNoLonger =>
      'Bộ phận cơ thể đã ngừng dùng không còn được đưa ra khi phân loại, và vẫn nằm trên mọi sự cố đã nêu nó.';

  @override
  String get bodyPartsTheBodyPartCatalogueCouldNotBe =>
      'Không đọc được danh mục Bộ phận cơ thể';

  @override
  String get bodyPartsWhereOnTheBodyAnInjuryWas =>
      'Thương tích ở đâu trên cơ thể — một danh mục dùng chung cho mọi Nhà máy, xếp theo vùng của từng bộ phận.';

  @override
  String get bodyPartsNoBodyPartsYet => 'Chưa có Bộ phận cơ thể nào';

  @override
  String get commonClassifyTheInjury => 'Phân loại thương tích';

  @override
  String get incidentClassifyClassifyingTheInjuryNeedsSafetyAuthorityAt =>
      'Phân loại thương tích cần thẩm quyền An toàn tại Đơn vị tổ chức của Sự cố an toàn này.';

  @override
  String incidentClassifySitsOnTheNoInjuryRungNobody(Object incidentNo) {
    return '$incidentNo đang ở mức không có thương tích. Không ai bị thương nên không có gì để phân loại — nếu mức độ sai, hãy sửa mức độ trước.';
  }

  @override
  String get incidentClassifyWhoWasHurtWhatTheInjuryWas =>
      'Ai bị thương, thương tích là gì và ở đâu trên cơ thể. Ba thông tin này chỉ người có thẩm quyền An toàn của khu vực này và chính Tài khoản của người bị thương đọc được.';

  @override
  String get incidentClassifySaveTheClassification => 'Lưu phân loại';

  @override
  String get commonInjuredEmployee => 'Nhân viên bị thương';

  @override
  String get incidentClassifyWhoWasHurt => 'Ai bị thương.';

  @override
  String get incidentClassifyClearTheInjuredEmployee =>
      'Bỏ Nhân viên bị thương';

  @override
  String get incidentClassifyTheInjuryTypeAndBodyPartCatalogues =>
      'Không đọc được danh mục Loại thương tích và Bộ phận cơ thể';

  @override
  String get commonInjuryType => 'Loại thương tích';

  @override
  String get incidentClassifyWhatTheInjuryWas => 'Thương tích là gì.';

  @override
  String get incidentClassifyClearTheInjuryType => 'Bỏ Loại thương tích';

  @override
  String get commonBodyPart => 'Bộ phận cơ thể';

  @override
  String get incidentClassifyWhereOnTheBody => 'Ở đâu trên cơ thể.';

  @override
  String get incidentClassifyClearTheBodyPart => 'Bỏ Bộ phận cơ thể';

  @override
  String get incidentCloseCloseThisSafetyIncident => 'Đóng Sự cố an toàn này';

  @override
  String get incidentCloseClosingASafetyIncidentNeedsSafetyAuthority =>
      'Đóng một Sự cố an toàn cần thẩm quyền An toàn tại Đơn vị tổ chức của nó.';

  @override
  String get incidentCloseThisSafetyIncidentIsAlreadyClosed =>
      'Sự cố an toàn này đã đóng.';

  @override
  String incidentCloseWillBeClosedAConcernRaisedFrom(Object incidentNo) {
    return '$incidentNo sẽ được đóng. Concern nêu từ sự cố này, nếu có, vẫn tiếp tục xử lý nguyên nhân một cách độc lập.';
  }

  @override
  String get incidentCloseLeaveItOpen => 'Để mở';

  @override
  String get commonCloseIt => 'Đóng lại';

  @override
  String get incidentCloseWhyThisIncidentIsBeingClosed =>
      'Vì sao đóng sự cố này.';

  @override
  String get commonRecordTheDays => 'Ghi nhận số ngày';

  @override
  String get incidentDaysRecordingTheDaysNeedsSafetyAuthorityAt =>
      'Ghi nhận số ngày cần thẩm quyền An toàn tại Đơn vị tổ chức của Sự cố an toàn này.';

  @override
  String get incidentDaysThisSafetyIncidentIsClosedItsDays =>
      'Sự cố an toàn này đã đóng; số ngày của nó không sửa được.';

  @override
  String incidentDaysWhatCostZeroIsARealAnswer(Object incidentNo) {
    return '$incidentNo gây tốn bao nhiêu — số 0 là một câu trả lời thật, và là câu trả lời chốt.';
  }

  @override
  String get commonLostTimeDays => 'Số ngày nghỉ do thương tích';

  @override
  String get commonRestrictedDays => 'Số ngày làm hạn chế';

  @override
  String get incidentDetailNoSuchSafetyIncident => 'Không có Sự cố an toàn này';

  @override
  String get incidentDetailBackToSafetyIncidents => 'Về Sự cố an toàn';

  @override
  String get incidentDetailTheSafetyIncidentCouldNotBeRead =>
      'Không đọc được Sự cố an toàn này';

  @override
  String get incidentDetailReportedAt => 'Báo cáo lúc';

  @override
  String get incidentDetailImmediateAction => 'Xử lý ngay';

  @override
  String get commonInvestigationDueDate => 'Hạn điều tra';

  @override
  String incidentDetailMoveTo(Object value) {
    return 'Chuyển sang $value';
  }

  @override
  String get commonCorrectTheSeverity => 'Sửa mức độ';

  @override
  String incidentDetailClosed(Object closedAt) {
    return 'Đã đóng $closedAt';
  }

  @override
  String get commonInvestigationDueAt => 'Hạn điều tra';

  @override
  String get incidentDetailTheInjury => 'Thương tích';

  @override
  String get incidentDetailRestrictedVisibleToSafetyAuthorityForThis =>
      'Hạn chế — chỉ người có thẩm quyền An toàn của khu vực này xem được.';

  @override
  String get incidentDetailNotClassifiedYetWhoWasHurtWhat =>
      'Chưa phân loại. Chưa ghi ai bị thương, thương tích là gì và ở đâu trên cơ thể.';

  @override
  String get incidentDetailTheIncidentItselfIsRecordedHereThe =>
      'Bản thân sự cố được ghi ở đây; nguyên nhân phía sau được giải quyết trong nhật ký hành động, dưới dạng Concern.';

  @override
  String get incidentDetailEventHistory => 'Lịch sử thay đổi';

  @override
  String get incidentDetailEverySeverityChangeStatusMoveDaysChange =>
      'Mọi lần đổi mức độ, chuyển trạng thái, đổi số ngày, đóng và đổi phân loại, kèm ai làm và khi nào.';

  @override
  String get incidentDetailNothingHasChangedAboutThisRecordSince =>
      'Bản ghi này chưa thay đổi gì kể từ khi được ghi nhận.';

  @override
  String get incidentDueDateThisSafetyIncidentIsClosedItsInvestigation =>
      'Sự cố an toàn này đã đóng; hạn điều tra của nó không sửa được.';

  @override
  String incidentDueDateSInvestigationDeadline(Object incidentNo) {
    return 'Hạn điều tra của $incidentNo.';
  }

  @override
  String get incidentFormWhatKindOfEventThisWas => 'Đây là loại sự việc gì.';

  @override
  String get incidentFormTheWorstActualOutcomeToAPerson =>
      'Hậu quả thực tế nặng nhất với một người. Theo thứ tự mức độ.';

  @override
  String get incidentFormWhatHappened => 'Đã xảy ra chuyện gì.';

  @override
  String get incidentFormWhatWasDoneAtOnce => 'Đã làm gì ngay lúc đó.';

  @override
  String get incidentFormInjuredEmployeeOptional =>
      'Nhân viên bị thương (không bắt buộc)';

  @override
  String get incidentFormWhoWasHurtIfAnyoneReadOnly =>
      'Ai bị thương, nếu có. Chỉ người có thẩm quyền An toàn của khu vực này và chính Tài khoản của người bị thương đọc được.';

  @override
  String get incidentFormWhenItHappenedThisIsWhatDecides =>
      'Xảy ra khi nào. Đây là điều quyết định ngày sản xuất và ca mà sự cố được ghi vào.';

  @override
  String get incidentFormReportedAtOptional => 'Báo cáo lúc (không bắt buộc)';

  @override
  String get incidentFormWhenItWasReportedIfThatIs =>
      'Được báo khi nào, nếu không phải bây giờ.';

  @override
  String get incidentFormWhereItHappened => 'Xảy ra ở đâu';

  @override
  String get incidentFormChooseTheOrgUnitTheIncidentOccurred =>
      'Chọn Đơn vị tổ chức nơi sự cố xảy ra. Đây là điều quyết định ai được thao tác trên nó.';

  @override
  String incidentFormThisSafetyIncidentWillBeRecordedAt(Object value) {
    return 'Sự cố an toàn này sẽ được ghi nhận tại $value.';
  }

  @override
  String get incidentFormWhichMachineIfTheIncidentWasOn =>
      'Máy nào, nếu sự cố xảy ra trên máy. Máy đó phải nằm tại Đơn vị tổ chức ấy.';

  @override
  String incidentRaiseConcernIsRecordedAtAndTheConcernIs(
    Object incidentNo,
    Object orgUnitName,
  ) {
    return '$incidentNo được ghi nhận tại $orgUnitName, và Concern được nêu ở đó — vấn đề được giải quyết tại nơi nó xảy ra.';
  }

  @override
  String get incidentRaiseConcernWhatIsTheCauseToSolve =>
      'Nguyên nhân cần giải quyết là gì?';

  @override
  String get incidentRaiseConcernTheConcernIsReadInTheAction =>
      'Concern được đọc trong nhật ký hành động, nên hãy nói vấn đề, đừng nói thương tích.';

  @override
  String get incidentRaiseConcernOptionalTheSafetyIncidentItselfIsAlready =>
      'Không bắt buộc. Bản thân Sự cố an toàn đã được liên kết làm bằng chứng.';

  @override
  String get incidentSeverityCorrectingTheSeverityNeedsSafetyAuthorityAt =>
      'Sửa mức độ cần thẩm quyền An toàn tại Đơn vị tổ chức của Sự cố an toàn này.';

  @override
  String incidentSeverityIsCorrectingItRestatesThePeriodIt(
    Object incidentNo,
    Object value,
  ) {
    return '$incidentNo đang ở mức $value. Sửa mức độ sẽ khai lại khoảng thời gian mà sự cố đã xảy ra.';
  }

  @override
  String get incidentSeverityCorrectIt => 'Sửa mức độ';

  @override
  String get incidentSeverityCorrectTheSeverityTo => 'Sửa mức độ thành';

  @override
  String get incidentSeverityWhyTheSeverityIsBeingCorrected =>
      'Vì sao sửa mức độ.';

  @override
  String get incidentStatusMoveTheStatus => 'Chuyển trạng thái';

  @override
  String get incidentStatusThisSafetyIncidentIsClosedItsStatus =>
      'Sự cố an toàn này đã đóng; trạng thái của nó không chuyển được.';

  @override
  String incidentStatusThisSafetyIncidentIsAlreadyOnlyClosing(Object value) {
    return 'Sự cố an toàn này đã ở trạng thái $value; chỉ việc đóng mới đưa nó đi tiếp.';
  }

  @override
  String incidentStatusMovesFromTo(
    Object incidentNo,
    Object statusLabel,
    Object value,
  ) {
    return '$incidentNo chuyển từ $statusLabel sang $value.';
  }

  @override
  String incidentStatusMoveTo(Object value) {
    return 'Chuyển sang $value';
  }

  @override
  String get incidents1SafetyIncident => '1 sự cố an toàn';

  @override
  String incidentsSafetyIncidents(Object length) {
    return '$length sự cố an toàn';
  }

  @override
  String get incidentsSiHcm202600001 => 'SI-HCM-2026-00001';

  @override
  String get injuryTypeFormCorrectInjuryType => 'Sửa Loại thương tích';

  @override
  String get commonAddInjuryType => 'Thêm Loại thương tích';

  @override
  String get injuryTypeFormAnInjuryTypeSCodeCannotBe =>
      'Không sửa được mã của Loại thương tích';

  @override
  String get injuryTypeFormARetiredInjuryTypeIsNoLonger =>
      'Loại thương tích đã ngừng dùng không còn được đưa ra khi phân loại, và vẫn nằm trên mọi sự cố đã nêu nó.';

  @override
  String get injuryTypesTheInjuryTypeCatalogueCouldNotBe =>
      'Không đọc được danh mục Loại thương tích';

  @override
  String get injuryTypesWhatAnInjuryWasOneCatalogueShared =>
      'Thương tích là gì — một danh mục dùng chung cho mọi Nhà máy, và là căn cứ để phân loại một Sự cố an toàn.';

  @override
  String get injuryTypesNoInjuryTypesYet => 'Chưa có Loại thương tích nào';

  @override
  String get observationDetailNoSuchSafetyObservation =>
      'Không có Quan sát an toàn này';

  @override
  String get observationDetailBackToSafetyObservations => 'Về Quan sát an toàn';

  @override
  String get observationDetailTheSafetyObservationCouldNotBeRead =>
      'Không đọc được Quan sát an toàn này';

  @override
  String get observationDetailActionTaken => 'Đã xử lý';

  @override
  String get observationDetailRecordedBy => 'Ghi nhận bởi';

  @override
  String get observationDetailObservedAt => 'Quan sát lúc';

  @override
  String get observationDetailClosingTheLoop => 'Khép vòng';

  @override
  String get observationDetailTheObservationItselfIsRecordedHereWhat =>
      'Bản thân quan sát được ghi ở đây; việc người khác làm gì về nó được quản lý trong nhật ký hành động, dưới dạng Hành động.';

  @override
  String get observationDetailNothingIsBeingDoneAboutThisYet =>
      'Chưa có gì được làm về việc này.';

  @override
  String get commonRaiseAnAction => 'Nêu một Hành động';

  @override
  String get observationFormASafeActAnUnsafeActOr =>
      'Một hành vi an toàn, một hành vi không an toàn, hoặc một điều kiện không an toàn.';

  @override
  String get observationFormTheWorstCredibleOutcomeNotWhatActually =>
      'Hậu quả nặng nhất có thể tin được, không phải điều đã thực sự xảy ra.';

  @override
  String get observationFormWhatWasSeen => 'Đã thấy gì.';

  @override
  String get observationFormWhatWasDoneOnTheSpot => 'Đã làm gì ngay tại chỗ.';

  @override
  String get observationFormRareAndTheSingleStrongestSignalThat =>
      'Hiếm, và là dấu hiệu mạnh nhất cho thấy văn hoá an toàn là thật.';

  @override
  String get observationFormObservedAtOptional =>
      'Quan sát lúc (không bắt buộc)';

  @override
  String get observationFormWhenItWasSeenIfNotNow =>
      'Được thấy khi nào, nếu không phải bây giờ. Đây là điều quyết định ngày sản xuất và ca mà quan sát được ghi vào.';

  @override
  String get observationFormWhereItWasSeen => 'Được thấy ở đâu';

  @override
  String get observationFormChooseTheOrgUnitTheObservationWas =>
      'Chọn Đơn vị tổ chức nơi quan sát được thực hiện. Đây là điều quyết định ai được thao tác trên nó.';

  @override
  String observationFormThisSafetyObservationWillBeRecordedAt(Object value) {
    return 'Quan sát an toàn này sẽ được ghi nhận tại $value.';
  }

  @override
  String observationRaiseActionThisObservationIsRecordedAtAndThe(
    Object orgUnitName,
  ) {
    return 'Quan sát này được ghi nhận tại $orgUnitName, và Hành động được nêu ở đó — vấn đề được nhận tại nơi nó được thấy.';
  }

  @override
  String get observationRaiseActionChooseWhatThisIs => 'Chọn loại quan sát.';

  @override
  String get observationRaiseActionChooseAKind => 'Chọn một loại';

  @override
  String get observationRaiseActionWhatNeedsDoing => 'Cần làm gì?';

  @override
  String get observationRaiseActionTheActionIsReadInTheAction =>
      'Hành động được đọc trong nhật ký hành động, nên hãy nói việc cần làm, đừng nói quan sát.';

  @override
  String
  get observationRaiseActionOptionalTheSafetyObservationItselfIsAlready =>
      'Không bắt buộc. Bản thân Quan sát an toàn đã được liên kết làm bằng chứng.';

  @override
  String get observations1SafetyObservation => '1 quan sát an toàn';

  @override
  String observationsSafetyObservations(Object length) {
    return '$length quan sát an toàn';
  }

  @override
  String safetyIncidentRecordable(Object value) {
    return '$value · phải khai báo';
  }

  @override
  String
  get safetyObservationOrgUnitFilterChooseTheOrgUnitWhoseSafetyObservations =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc Quan sát an toàn cùng mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String get safetyOrgUnitFilterChooseTheOrgUnitWhoseSafetyIncidents =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc Sự cố an toàn cùng mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String handoverAcknowledgeYouAreAcceptingAndTheShift(
    Object value,
    Object value2,
  ) {
    return 'Bạn đang nhận $value và ca$value2.';
  }

  @override
  String get handoverAcknowledgeTheOutgoingShiftDeclaredNoChangePoints =>
      'Ca trước khai không có điểm thay đổi nào.';

  @override
  String get handoverAcknowledgeThereAreNoChangePointsToWatch =>
      'Không có điểm thay đổi nào cần theo dõi.';

  @override
  String get handoverAcknowledgeWhatEachWatchShowed =>
      'Mỗi lượt theo dõi cho thấy gì';

  @override
  String handoverAcknowledgeWatch(Object watchNote) {
    return 'Theo dõi: $watchNote';
  }

  @override
  String get handoverAcknowledgeFound => 'Đã thấy';

  @override
  String get handoverAcknowledgeNotAnswered => 'Chưa trả lời';

  @override
  String get handoverAcknowledgeNoteOnTheHandoverOptional =>
      'Ghi chú về bàn giao (không bắt buộc)';

  @override
  String get handoverAcknowledgeAcknowledgeTheHandover => 'Xác nhận bàn giao';

  @override
  String get handoverAcknowledgeAcknowledging => 'Đang xác nhận…';

  @override
  String get commonAcknowledge => 'Xác nhận';

  @override
  String get sectionThatSectionSDayCouldNotBe =>
      'Không đọc được ngày của Bộ phận đó';

  @override
  String get sectionChooseAnotherSection => 'Chọn Bộ phận khác';

  @override
  String get sectionEveryShiftOfTheProductionDayWith =>
      'Mọi ca của ngày sản xuất, kèm bàn giao và những gì còn mở tại mỗi mốc chuyển ca.';

  @override
  String get sectionNoShiftsScheduled => 'Không có ca nào được xếp';

  @override
  String get sectionNoShiftsAreScheduledAtThisSection =>
      'Ngày đó Bộ phận này không có ca nào được xếp.';

  @override
  String sectionShift(Object value, Object value2) {
    return 'Ca $value–$value2';
  }

  @override
  String get commonLate => 'Trễ';

  @override
  String sectionHandedOverBy(Object value) {
    return 'Bàn giao bởi $value';
  }

  @override
  String sectionAcknowledgedAfterTheShiftBegan(Object value) {
    return 'xác nhận $value sau khi ca bắt đầu';
  }

  @override
  String get sectionThatSectionTreeCouldNotBeRead =>
      'Không đọc được cây Bộ phận';

  @override
  String get sectionNothingToOpenHere => 'Ở đây không có gì để mở';

  @override
  String get sectionChooseASectionToOpenItsBoard =>
      'Chọn một Bộ phận để mở bảng của nó: các ca trong ngày và bàn giao của mỗi ca.';

  @override
  String get shiftHandoverThatHandoverCouldNotBeOpened =>
      'Không mở được bản bàn giao đó';

  @override
  String get shiftHandoverSubmitTheHandover => 'Gửi bàn giao';

  @override
  String get shiftHandoverBackToTheSectionBoard => 'Về bảng Bộ phận';

  @override
  String shiftHandoverShiftHandover(Object value) {
    return 'Bàn giao ca · $value';
  }

  @override
  String shiftHandoverVersion(Object version) {
    return 'Phiên bản $version';
  }

  @override
  String get shiftHandoverTheNumbersTheShiftClosedOn =>
      'Các số liệu ca đã chốt';

  @override
  String get shiftHandoverFrozenWhenTheHandoverIsSubmitted =>
      'Chốt lại khi gửi bàn giao.';

  @override
  String get shiftHandoverFrozenAtSubmit => 'Chốt tại thời điểm gửi.';

  @override
  String get shiftHandoverMachines => 'Máy';

  @override
  String get shiftHandoverOneLinePerAssetInTheSection =>
      'Mỗi Tài sản trong Bộ phận một dòng.';

  @override
  String get shiftHandoverThisSectionHasNoActiveAssets =>
      'Bộ phận này không có Tài sản nào đang hoạt động.';

  @override
  String get shiftHandoverChangePoints => 'Điểm thay đổi';

  @override
  String get shiftHandoverWhatTheIncomingShiftWillMeetThat =>
      'Điều ca sau sẽ gặp mà khác trước, và những gì cần theo dõi.';

  @override
  String get shiftHandoverCarriedActions => 'Hành động chuyển tiếp';

  @override
  String get shiftHandoverEveryOpenActionOfTheSectionIs =>
      'Mọi Hành động đang mở của Bộ phận đều được chuyển tiếp, giao lại hoặc đóng.';

  @override
  String get shiftHandoverHandoverEvidence => 'Bằng chứng bàn giao';

  @override
  String shiftHandoverAcknowledged(Object value, Object value2) {
    return 'Đã xác nhận $value$value2';
  }

  @override
  String get shiftHandoverThisHandoverCannotBeSubmittedYet =>
      'Chưa gửi được bản bàn giao này';

  @override
  String get shiftHandoverNoLineYet => 'Chưa có dòng nào';

  @override
  String get shiftHandoverAbnormality => 'Bất thường';

  @override
  String get shiftHandoverNoneFound => 'Không thấy gì';

  @override
  String get shiftHandoverRequiredSayWhyItIsNotRunning =>
      'Bắt buộc: nêu vì sao máy không chạy bình thường';

  @override
  String get shiftHandoverWhatTheIncomingShiftMustWatch =>
      'Điều ca sau phải theo dõi';

  @override
  String get shiftHandoverWalked => 'Đã đi kiểm tra';

  @override
  String get shiftHandoverSaveLine => 'Lưu dòng';

  @override
  String get shiftHandoverRecordLine => 'Ghi dòng';

  @override
  String get shiftHandoverNoChangePointsThisShift =>
      'Ca này không có điểm thay đổi';

  @override
  String get shiftHandoverNoneRecorded => 'Chưa ghi nhận gì';

  @override
  String shiftHandoverWatch(Object watchNote, Object value) {
    return 'Theo dõi: $watchNote$value';
  }

  @override
  String get shiftHandoverAddAChangePoint => 'Thêm điểm thay đổi';

  @override
  String get shiftHandoverDimension => 'Chiều';

  @override
  String get shiftHandoverWhatIsDifferent => 'Khác ở chỗ nào';

  @override
  String get shiftHandoverWhatTheIncomingShiftMustWatchFor =>
      'Điều ca sau phải để ý';

  @override
  String get shiftHandoverAddChangePoint => 'Thêm điểm thay đổi';

  @override
  String get shiftHandoverTheSectionHasNoOpenActionsTo =>
      'Bộ phận không có Hành động nào đang mở để bàn giao.';

  @override
  String shiftHandoverOld(Object value, Object value2) {
    return '$value $value2 tuổi';
  }

  @override
  String shiftHandoverOwner(Object ownerName) {
    return 'Người phụ trách $ownerName';
  }

  @override
  String get shiftHandoverNoDispositionYet => 'chưa có phương án xử lý';

  @override
  String get shiftHandoverNewOwner => 'Người phụ trách mới';

  @override
  String get shiftHandoverWhatClosedIt => 'Điều gì đã đóng nó';

  @override
  String get shiftHandoverRecordDisposition => 'Ghi nhận phương án xử lý';

  @override
  String get shiftHandoverJointWalkDone => 'Đã đi kiểm tra chung';

  @override
  String get shiftHandoverCriticalItems => 'Hạng mục quan trọng';

  @override
  String get shiftHandoverDeviationFromTheStandardHandover =>
      'Sai khác so với bàn giao chuẩn';

  @override
  String get shiftHandoverSaveEvidence => 'Lưu bằng chứng';

  @override
  String get commonAddKpi => 'Thêm KPI';

  @override
  String get addKpiAdd => 'Thêm';

  @override
  String get addKpiKpi => 'KPI';

  @override
  String get addKpiTheCodeEGOee => 'Mã, ví dụ OEE';

  @override
  String get addKpiUnitOptional => 'Đơn vị (không bắt buộc)';

  @override
  String get addKpiDirection => 'Chiều so sánh';

  @override
  String get addKpiIsMetAtOrAboveTheTarget =>
      '>= là đạt khi bằng hoặc trên Mục tiêu, <= là đạt khi bằng hoặc dưới';

  @override
  String get addKpiDecimals => 'Số chữ số thập phân';

  @override
  String get addKpiAWholeNumberFrom0To6 => 'Một số nguyên từ 0 đến 6';

  @override
  String get addKpiDecimalsMustBeAWholeNumberFrom =>
      'Số chữ số thập phân phải là số nguyên từ 0 đến 6';

  @override
  String get addKpiValueMeasureOptional => 'Chỉ số giá trị (không bắt buộc)';

  @override
  String get commonChangeTarget => 'Đổi Mục tiêu';

  @override
  String get changeTargetGrain => 'Kỳ';

  @override
  String get changeTargetValidFrom => 'Hiệu lực từ';

  @override
  String changeTargetTodayAtThisSiteIsATarget(Object siteToday) {
    return 'Hôm nay tại Nhà máy này là $siteToday; một Mục tiêu bắt đầu từ hôm nay hoặc muộn hơn.';
  }

  @override
  String get changeTargetTarget => 'Mục tiêu';

  @override
  String get changeTargetLeaveBlankForNoTargetFromThat =>
      'Để trống nghĩa là từ ngày đó không có mục tiêu.';

  @override
  String get changeTargetTheTargetMustBeANumberOr =>
      'Mục tiêu phải là một số, hoặc để trống nếu không đặt mục tiêu';

  @override
  String get kpiCatalogueTheKpiCatalogueCouldNotBeRead =>
      'Không đọc được danh mục KPI';

  @override
  String get kpiCatalogueTheKpisOfTheMtuLineWith =>
      'Các KPI của chuyền MTU, kèm Mục tiêu đang áp dụng theo từng kỳ.';

  @override
  String kpiCatalogueTheKpisOfTheMtuLineWith2(Object reviewDate) {
    return 'Các KPI của chuyền MTU, kèm Mục tiêu đang áp dụng theo từng kỳ và trạng thái đánh giá hôm nay, $reviewDate.';
  }

  @override
  String get kpiCatalogueNoKpisInTheCatalogueYet => 'Danh mục chưa có KPI nào';

  @override
  String get kpiCatalogueNothingHasBeenAddedToTheKpi =>
      'Danh mục KPI chưa có gì.';

  @override
  String get commonFilterKpis => 'Lọc KPI';

  @override
  String get kpiCatalogueByCodeOrTitle => 'Theo mã hoặc tiêu đề.';

  @override
  String get commonNoKpisMatch => 'Không có KPI nào khớp';

  @override
  String kpiCatalogueNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Danh mục không có gì khớp “$term”. Hãy thử mã hoặc tiêu đề khác, hoặc xoá bộ lọc.';
  }

  @override
  String kpiCatalogueValueMeasure(Object measure) {
    return 'Chỉ số giá trị: $measure';
  }

  @override
  String get kpiReviewTheKpiReviewCouldNotBeRead =>
      'Không đọc được bản đánh giá KPI';

  @override
  String get kpiReviewKpiReview => 'Đánh giá KPI';

  @override
  String kpiReviewKpiReviewFor(Object reviewDate) {
    return 'Đánh giá KPI ngày $reviewDate';
  }

  @override
  String get kpiReviewJudgeEachKpiOfTheMtuLine =>
      'Đánh giá từng KPI của chuyền MTU theo Mục tiêu ngày của nó: đạt, không đạt hoặc chưa đo.';

  @override
  String get kpiReviewNoKpisToReview => 'Không có KPI nào để đánh giá';

  @override
  String get kpiReviewTheKpiCatalogueHasNoKpiYet =>
      'Danh mục KPI chưa có KPI nào.';

  @override
  String get kpiReviewByTitle => 'Theo tiêu đề.';

  @override
  String kpiReviewNoKpiOfTheReviewMatchesTry(Object term) {
    return 'Không KPI nào của bản đánh giá khớp “$term”. Hãy thử tiêu đề khác, hoặc xoá bộ lọc.';
  }

  @override
  String get kpiReview1ChangedKpiIsHiddenByThe =>
      '1 KPI đã thay đổi đang bị tìm kiếm ẩn đi.';

  @override
  String kpiReviewChangedKpisAreHiddenByTheSearch(Object hiddenChanges) {
    return '$hiddenChanges KPI đã thay đổi đang bị tìm kiếm ẩn đi.';
  }

  @override
  String kpiReviewSavedFor(Object savedCount, Object value, Object reviewDate) {
    return 'Đã lưu $savedCount $value cho $reviewDate.';
  }

  @override
  String get kpiReviewNoTarget => 'Không có mục tiêu';

  @override
  String kpiReviewDailyTarget(Object targetText) {
    return 'Mục tiêu ngày: $targetText';
  }

  @override
  String get kpiReviewReadTheNote => 'Đọc ghi chú';

  @override
  String get kpiReviewWhyWasItMissed => 'Vì sao không đạt?';

  @override
  String kpiReviewWhyWasTheTargetMissed(Object targetText) {
    return 'Vì sao không đạt Mục tiêu ($targetText)?';
  }

  @override
  String kpiReviewANoteOfAtLeastCharactersIs(
    Object minNoteLength,
    Object length,
  ) {
    return 'Khi một KPI không đạt phải ghi chú ít nhất $minNoteLength ký tự (hiện có $length).';
  }

  @override
  String get kpiReviewEdit => 'Sửa';

  @override
  String get kpiTargetsTheTargetsCouldNotBeRead =>
      'Không đọc được các Mục tiêu';

  @override
  String kpiTargetsKpiTargets(Object direction, Object unit) {
    return 'Mục tiêu KPI, $direction $unit';
  }

  @override
  String get kpiTargetsCurrentlyInForce => 'Đang áp dụng';

  @override
  String get kpiTargetsWhatEachGrainIsJudgedAgainstToday =>
      'Mỗi kỳ đang được đánh giá theo mức nào hôm nay, và từ khi nào.';

  @override
  String get kpiTargetsNoTargetIsInForceToday =>
      'Hôm nay không có Mục tiêu nào đang áp dụng.';

  @override
  String kpiTargetsFrom(Object grain, Object value, Object validFrom) {
    return '$grain: $value (từ $validFrom)';
  }

  @override
  String get kpiTargetsHistory => 'Lịch sử';

  @override
  String get kpiTargetsNewestFirstAnEntryIsNeverEdited =>
      'Mới nhất trước. Một mục không bao giờ bị sửa — mục sau thay thế mục trước.';

  @override
  String get kpiTargetsNoTargetHasBeenSet => 'Chưa đặt Mục tiêu nào';

  @override
  String get kpiTargetsEveryEntryMadeForThisKpiWill =>
      'Mọi mục đã đặt cho KPI này sẽ được liệt kê ở đây.';

  @override
  String get assetFormCorrectDetails => 'Sửa thông tin';

  @override
  String get commonAddAnAsset => 'Thêm Tài sản';

  @override
  String get assetFormAddAsset => 'Thêm Tài sản';

  @override
  String get assetFormUniqueAcrossTheWholePlatformNotJust =>
      'Duy nhất trên toàn Nền tảng, không chỉ tại Nhà máy này.';

  @override
  String get assetFormKind => 'Kiểu';

  @override
  String get commonCriticality => 'Mức trọng yếu';

  @override
  String get assetFormWhereThisAssetSitsIsChangedWith =>
      'Vị trí của Tài sản này được đổi bằng thao tác “Đổi Đơn vị tổ chức…” riêng của nó.';

  @override
  String assetFormThisAssetWillSitAt(Object value) {
    return 'Tài sản này sẽ nằm tại $value.';
  }

  @override
  String get assetMoveChangeWhereThisAssetSits => 'Đổi vị trí Tài sản này';

  @override
  String get assetMoveChangeOrgUnit => 'Đổi Đơn vị tổ chức';

  @override
  String assetMoveSitsAtNow(Object name, Object code, Object orgUnitName) {
    return '$name ($code) hiện nằm tại $orgUnitName.';
  }

  @override
  String get assetMoveMoveItTo => 'Chuyển tới';

  @override
  String get assetMoveWhereThisAssetWillSitItDecides =>
      'Vị trí Tài sản sẽ nằm. Điều này quyết định ai được nêu và đóng công việc trên nó; công việc đã ghi nhận vẫn ở nơi nó đã xảy ra.';

  @override
  String assetMoveThisAssetWillSitAt(Object value) {
    return 'Tài sản này sẽ nằm tại $value.';
  }

  @override
  String get assetsTheRegisterCouldNotBeRead =>
      'Không đọc được danh sách Tài sản';

  @override
  String get assetsNoAssetsOnTheRegisterYet => 'Danh sách chưa có Tài sản nào';

  @override
  String get assetsNothingHasBeenRecordedAtThisSite =>
      'Nhà máy này chưa ghi nhận gì. Thêm một máy là có thể làm việc trên máy đó ngay trong ngày.';

  @override
  String get assetsEveryMachineOnTheRegisterAtThis =>
      'Mọi máy trong danh sách tại Nhà máy này, và Đơn vị tổ chức mà mỗi máy nằm.';

  @override
  String get assetsShowRetired => 'Hiện cả đã ngừng dùng';

  @override
  String get assetsFilterAssets => 'Lọc Tài sản';

  @override
  String get assetsNoAssetsMatch => 'Không có Tài sản nào khớp';

  @override
  String assetsThisSiteHasAssetsOnTheRegister(Object term) {
    return 'Nhà máy này có Tài sản trong danh sách, nhưng không cái nào khớp “$term”. Hãy thử tên hoặc mã khác, hoặc xoá bộ lọc.';
  }

  @override
  String get assetsCodeType => 'Mã · Kiểu';

  @override
  String get assetsCorrectDetails => 'Sửa thông tin…';

  @override
  String get assetsChangeOrgUnit => 'Đổi Đơn vị tổ chức…';

  @override
  String get assetsDetach => 'Tách ra';

  @override
  String get assetsNestUnder => 'Đặt dưới…';

  @override
  String get assetsRetireThisAsset => 'Ngừng dùng Tài sản này?';

  @override
  String assetsWillNoLongerAppearOnTheActive(Object name) {
    return '$name sẽ không còn hiện trong danh sách đang hoạt động. Không có gì bị xoá, và có thể dùng lại bất cứ lúc nào.';
  }

  @override
  String get assetsThereIsNothingElseOnThisRegister =>
      'Danh sách không còn mục nào khác để nó nằm dưới.';

  @override
  String get breakdownReportReportABreakdown => 'Báo một lần hỏng máy';

  @override
  String get breakdownReportReport => 'Báo';

  @override
  String get breakdownReportStartedAtOptional => 'Bắt đầu lúc (không bắt buộc)';

  @override
  String get commonLeaveBlankToRecordNow =>
      'Để trống để ghi nhận ngay bây giờ.';

  @override
  String downtimeClassifyClassifyTheStopFor(Object assetName) {
    return 'Phân loại lần dừng của $assetName';
  }

  @override
  String get downtimeClassifyKeepItUnclassified => 'Để chưa phân loại';

  @override
  String get downtimeClassifyDescriptionRequired => 'Mô tả (bắt buộc)';

  @override
  String get downtimeClassifyTheDowntimeReasonsCouldNotBeRead =>
      'Không đọc được các lý do dừng máy.';

  @override
  String downtimeCloseCloseTheStopFor(Object assetName) {
    return 'Đóng lần dừng của $assetName?';
  }

  @override
  String get commonKeepItOpen => 'Để mở';

  @override
  String get downtimeCloseCloseThisStop => 'Đóng lần dừng này';

  @override
  String get downtimeCloseTheMachineIsRunningAgainTheServer =>
      'Máy đã chạy lại. Máy chủ ghi nhận thời gian đã dừng.';

  @override
  String get downtimeCloseEndedAtOptional => 'Kết thúc lúc (không bắt buộc)';

  @override
  String get floorTheFloorWorkCouldNotBeLoaded =>
      'Không tải được công việc trên sàn';

  @override
  String get floorNoOpenWork => 'Không có việc đang mở';

  @override
  String floorThereIsNoOpenWorkForRight(Object orgUnitName) {
    return 'Hiện tại $orgUnitName không có việc nào đang mở.';
  }

  @override
  String get floorRefresh => 'Làm mới';

  @override
  String get floorFloorWork => 'Công việc trên sàn';

  @override
  String get floorObservation => 'Quan sát';

  @override
  String get floorMyTraining => 'Đào tạo của tôi';

  @override
  String floorTechnicianComplete(Object workOrderNo) {
    return 'Hoàn thành $workOrderNo';
  }

  @override
  String floorTechnicianStart(Object workOrderNo) {
    return 'Bắt đầu $workOrderNo';
  }

  @override
  String get floorTechnicianWhoIsRecordingThisYourEmployeeNumber =>
      'Ai đang ghi nhận việc này? Mã nhân viên và PIN xác định bạn chỉ cho thao tác này.';

  @override
  String get commonWhatWasFound => 'Đã phát hiện gì?';

  @override
  String get myRequestsYourRequestsCouldNotBeRead =>
      'Không đọc được các yêu cầu của bạn';

  @override
  String get myRequestsWhatYouRaisedAndWhatBecameOf =>
      'Những gì bạn đã nêu, và kết quả của từng cái.';

  @override
  String get commonRaiseARequest => 'Nêu một yêu cầu';

  @override
  String myRequestsYouHaveRequestsAtThisSiteBut(Object term) {
    return 'Bạn có Yêu cầu tại Nhà máy này, nhưng không cái nào khớp “$term”. Hãy thử mô tả hoặc Tài sản khác.';
  }

  @override
  String get myRequestsOutcome => 'Kết quả';

  @override
  String myRequestsBecameWorkOrder(Object workOrderNo) {
    return 'Đã thành Lệnh công việc $workOrderNo';
  }

  @override
  String myRequestsDeclined(Object rejectionReason) {
    return 'Bị từ chối: $rejectionReason';
  }

  @override
  String get myRequestsNothingRaisedYet => 'Chưa nêu gì';

  @override
  String get myRequestsYouHaveNotRaisedAnyRequestsAt =>
      'Bạn chưa nêu Yêu cầu nào tại Nhà máy này. Hãy nêu một cái và nó sẽ hiện ở đây cùng kết quả sau đó.';

  @override
  String get commonAddPart => 'Thêm phụ tùng';

  @override
  String get commonPartNumber => 'Mã phụ tùng';

  @override
  String get partsThePartsCatalogueCouldNotBeRead =>
      'Không đọc được danh mục phụ tùng';

  @override
  String get partsTheSharedCatalogueDefinedOnceReusedAt =>
      'Danh mục dùng chung — khai báo một lần, dùng lại ở mọi Nhà máy.';

  @override
  String get partsNoPartsYet => 'Chưa có phụ tùng nào';

  @override
  String get partsFilterParts => 'Lọc phụ tùng';

  @override
  String get commonByPartNumberOrDescription => 'Theo mã phụ tùng hoặc mô tả.';

  @override
  String get commonNoPartsMatch => 'Không có phụ tùng nào khớp';

  @override
  String partsNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Danh mục không có gì khớp “$term”. Hãy thử mã phụ tùng hoặc mô tả khác, hoặc xoá bộ lọc.';
  }

  @override
  String get commonReceiveStock => 'Nhập kho';

  @override
  String get receiveReceiving => 'Đang nhập…';

  @override
  String get receiveReceive => 'Nhập kho';

  @override
  String get receiveReasonOptional => 'Lý do (không bắt buộc)';

  @override
  String get commonRaise => 'Nêu';

  @override
  String get requestFormProductionIsStoppedRightNow =>
      'Sản xuất đang dừng ngay lúc này';

  @override
  String get storeStockThisStoreCouldNotBeRead => 'Không đọc được kho này';

  @override
  String get storeStockBackToStores => 'Về danh sách Kho';

  @override
  String get storeStockNothingOnTheShelf => 'Kệ trống';

  @override
  String get storeStockNoPartHasMovedInOrOut =>
      'Chưa có phụ tùng nào ra vào kho này.';

  @override
  String get storeStockFilterStock => 'Lọc tồn kho';

  @override
  String storeStockThisStoreHoldsStockButNothingOn(Object term) {
    return 'Kho này có tồn kho, nhưng không mục nào trên kệ khớp “$term”. Hãy thử mã phụ tùng hoặc mô tả khác.';
  }

  @override
  String get storesTheStoresCouldNotBeRead => 'Không đọc được danh sách Kho';

  @override
  String get storesTheShelvesThatHoldPartsAtThis =>
      'Những kệ chứa phụ tùng tại Nhà máy này.';

  @override
  String get storesNoStoresYet => 'Chưa có kho nào';

  @override
  String get storesNothingHereHoldsParts => 'Ở đây không có gì chứa phụ tùng.';

  @override
  String get storesFilterStores => 'Lọc kho';

  @override
  String get storesNoStoresMatch => 'Không có kho nào khớp';

  @override
  String storesThisSiteHasStoresButNoneMatches(Object term) {
    return 'Nhà máy này có kho, nhưng không kho nào khớp “$term”. Hãy thử tên hoặc mã khác, hoặc xoá bộ lọc.';
  }

  @override
  String get storesTappingAStoreShowsWhatIsOn =>
      'Chạm vào một kho để xem trên kệ có gì.';

  @override
  String get storesCodeOrgUnit => 'Mã · Đơn vị tổ chức';

  @override
  String taskReadingRecordAReadingOn(Object value) {
    return 'Ghi chỉ số cho $value';
  }

  @override
  String get taskReadingWhatTheMeterReads => 'Đồng hồ chỉ bao nhiêu';

  @override
  String get tierBoardOrgUnitFilterNarrowTheBoard => 'Thu hẹp bảng';

  @override
  String get tierBoardOrgUnitFilterChooseTheOrgUnitWhoseNumbersAnd =>
      'Chọn Đơn vị tổ chức mà bạn muốn đọc số liệu cùng mọi thứ bên dưới nó, hoặc xoá về toàn bộ Nhà máy.';

  @override
  String get tierTheTierBoardCouldNotBeRead => 'Không đọc được bảng phân cấp';

  @override
  String get tierTheNumbersThisSiteSWorkProduces =>
      'Những số liệu mà công việc của Nhà máy này tạo ra, báo cáo theo năm Trụ cột. Mọi Trụ cột đều được hiển thị dù chưa có gì báo cáo dưới nó.';

  @override
  String get tierDate => 'Ngày';

  @override
  String get tierNoPillarsToShow => 'Không có Trụ cột nào để hiển thị';

  @override
  String get tierThisSiteHasNoPillarsToReport =>
      'Nhà máy này chưa có Trụ cột nào để báo cáo.';

  @override
  String get tierNoDataYet => 'Chưa có dữ liệu';

  @override
  String get tierNoKpiIsDefinedUnderThisPillar =>
      'Chưa có KPI nào được định nghĩa dưới Trụ cột này.';

  @override
  String get tierValue => 'Giá trị';

  @override
  String get workOrderAssignFindAPerson => 'Tìm một người';

  @override
  String get workOrderAssignByNameEmployeeNumberOrTheQualification =>
      'Theo tên, mã nhân viên, hoặc chứng nhận họ có.';

  @override
  String get workOrderAssignTheCandidatesCouldNotBeRead =>
      'Không đọc được danh sách ứng viên.';

  @override
  String workOrderAssignNobodyMatchesTryADifferentNameNumber(Object term) {
    return 'Không ai khớp “$term” — hãy thử tên, mã số hoặc kỹ năng khác.';
  }

  @override
  String get workOrderAssignThereIsNobodyThisWorkOrderCould =>
      'Không có ai để giao Lệnh công việc này.';

  @override
  String get workOrderAssignNoQualificationsRecorded =>
      'Chưa ghi nhận chứng nhận nào';

  @override
  String get workOrderCancelCancelThisWorkOrder => 'Huỷ Lệnh công việc này?';

  @override
  String get workOrderCancelCancelThisWorkOrder2 => 'Huỷ Lệnh công việc này';

  @override
  String get workOrderCancelWhyIsThisBeingCancelledOptional =>
      'Vì sao huỷ? (không bắt buộc)';

  @override
  String get workOrderCompleteCompleteThisWorkOrder =>
      'Hoàn thành Lệnh công việc này';

  @override
  String get workOrderDialogYouDoNotHoldAWriteGrant =>
      'Bạn không có quyền ghi nào bao trùm Lệnh công việc này.';

  @override
  String get workOrderDialogLoadingThisWorkOrder =>
      'Đang tải Lệnh công việc này';

  @override
  String get workOrderDialogThatIsNoLongerAvailable => 'Mục đó không còn';

  @override
  String workOrderDialogThisWorkOrderIsNowWhichNo(Object statusLabel) {
    return 'Lệnh công việc này hiện ở trạng thái $statusLabel, nên không còn thao tác này.';
  }

  @override
  String get workOrderDialogThatWorkOrderIsNotInThis =>
      'Lệnh công việc đó không có trong danh sách này';

  @override
  String get workOrderDialogItMayHaveBeenCompletedCancelledOr =>
      'Có thể nó đã hoàn thành, đã huỷ, hoặc nằm ngoài Nhà máy hay Đơn vị tổ chức mà danh sách đang hiển thị.';

  @override
  String get workOrdersWoBuc202600001 => 'WO-BUC-2026-00001';
}
