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
}
