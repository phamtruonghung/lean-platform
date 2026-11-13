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
}
