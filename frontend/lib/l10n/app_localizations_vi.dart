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
}
