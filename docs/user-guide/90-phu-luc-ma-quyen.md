# Phụ lục: 84 mã quyền và vai trò mang chúng

Sinh ra từ cơ sở dữ liệu sau khi chạy đủ migration tới `1804100000000_kpi-catalogue-write-roles` — không chép tay, nên không lệch được với mã nguồn.

`Mọi` = `ROLE_STANDARD`, nhóm mặc định mà **mọi Tài khoản đều mang**. Một vai trò mang quyền của chính nó **cộng** nhóm mặc định; bảng dưới đã tính sẵn phần cộng đó.

`Quản trị viên` không đọc bảng này để biết mình làm được gì: máy chủ cho vai trò `ROLE_ADMIN` đi qua mọi mã quyền, nên admin làm được tất cả 84.

## Nhân sự

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `PPL_DIRECTORY_DISPLAY` | Directory | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_DIRECTORY_CHANGE` | Maintain Employees | · | · | · | · | · | ✓ |
| `PPL_JOB_ROLES_DISPLAY` | Job roles | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_JOB_ROLES_CHANGE` | Maintain Job roles | · | · | · | · | · | ✓ |
| `PPL_SKILLS_DISPLAY` | Skills | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_SKILLS_CHANGE` | Maintain Skills | · | · | · | · | · | ✓ |
| `PPL_ORG_UNITS_DISPLAY` | Org Units | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_ORG_UNITS_CHANGE` | Maintain Org Units | · | · | · | · | · | ✓ |
| `PPL_ATTENDANCE_DISPLAY` | Attendance | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_ATTENDANCE_CHANGE` | Confirm Attendance | · | · | ✓ | ✓ | ✓ | ✓ |
| `PPL_TRAINING_DISPLAY` | Training | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_TRAINING_CHANGE` | Raise Training | · | · | ✓ | ✓ | ✓ | ✓ |
| `PPL_SIGNATURE_OWN` | My signature | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_LEAVE_REQUESTS_DISPLAY` | Leave requests | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_LEAVE_REQUESTS_DECIDE` | Decide Leave | · | · | ✓ | ✓ | ✓ | ✓ |
| `PPL_COST_RATES_MAINTAIN` | Cost rates | · | · | · | · | · | ✓ |
| `PPL_PRODUCT_COSTS_MAINTAIN` | Product standard costs | · | · | · | · | · | ✓ |
| `PPL_TRAINING_ANSWER_OWN` | Answer my Training | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PPL_LEAVE_REQUESTS_RAISE` | Raise my Leave | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

## Bảo trì

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `MTN_ASSETS_DISPLAY` | Assets | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_ASSETS_CHANGE` | Maintain Assets | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_WORK_ORDERS_DISPLAY` | Work orders | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_WORK_ORDERS_CHANGE` | Maintain Work orders | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_PARTS_DISPLAY` | Parts | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_PARTS_CHANGE` | Maintain Parts | · | · | · | ✓ | ✓ | ✓ |
| `MTN_STORES_DISPLAY` | Stores | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_STORES_CHANGE` | Maintain Stores | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_REQUESTS_RAISE` | Raise a Request | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `MTN_REQUESTS_TRIAGE` | Triage Requests | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_DOWNTIME_DISPLAY` | Downtime | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_DOWNTIME_CHANGE` | Record Downtime | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_PM_SCHEDULES_DISPLAY` | PM schedules | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_PM_SCHEDULES_CHANGE` | Maintain PM schedules | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_METERS_DISPLAY` | Meters | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_METERS_CHANGE` | Record meter readings | · | · | ✓ | ✓ | ✓ | ✓ |
| `MTN_JOB_PLANS_MAINTAIN` | Job plans | · | · | · | · | · | ✓ |

## Hành động

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `ACT_LOG_DISPLAY` | Action log | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_RAISE` | Raise a Concern | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_MEASURE` | Record measures | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_VERIFY` | Verify an Action | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_CAPA_DISPLAY` | CAPAs | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_CAPA_OPEN` | Open a CAPA | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_CAPA_VERIFY` | Verify a CAPA | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_CAPA_EFFECTIVENESS` | Check effectiveness | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `ACT_CHANGE` | Change an Action | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

## Chất lượng

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `QLT_PRODUCTS_DISPLAY` | Products | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_PRODUCTS_CHANGE` | Maintain Products | · | · | · | · | · | ✓ |
| `QLT_DEFECT_CODES_DISPLAY` | Defect codes | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_DEFECT_CODES_CHANGE` | Maintain defect codes | · | · | · | · | · | ✓ |
| `QLT_NONCONFORMANCES_DISPLAY` | Non-conformances | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_NONCONFORMANCES_RECORD` | Record a Non-conformance | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_NONCONFORMANCES_DISPOSE` | Dispose of nonconforming product | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_CUSTOMERS_DISPLAY` | Customers | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_CUSTOMERS_CHANGE` | Maintain Customers | · | · | · | · | · | ✓ |
| `QLT_COMPLAINTS_DISPLAY` | Customer complaints | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_COMPLAINTS_RECORD` | Record a complaint | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_SLIDESHOW_DISPLAY` | Slide show | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_SLIDESHOW_CHOOSE` | Choose slide-show issues | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_SUPPLIERS_DISPLAY` | Suppliers | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_SUPPLIERS_CHANGE` | Maintain Suppliers | · | · | · | · | · | ✓ |
| `QLT_SUPPLIER_NCRS_DISPLAY` | Supplier NCRs | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `QLT_SUPPLIER_NCRS_RECORD` | Record a supplier NCR | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

## An toàn

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `SAF_INCIDENTS_DISPLAY` | Incidents | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `SAF_INCIDENTS_RECORD` | Record an Incident | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `SAF_CLASSIFY` | Classify an injury | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `SAF_OBSERVATIONS_DISPLAY` | Observations | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `SAF_OBSERVATIONS_RECORD` | Record an Observation | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `SAF_INJURY_TYPES_MAINTAIN` | Injury types | · | · | · | · | · | ✓ |
| `SAF_BODY_PARTS_MAINTAIN` | Body parts | · | · | · | · | · | ✓ |

## Sản xuất

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `PRD_HANDOVER_DISPLAY` | Shift handovers | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PRD_HANDOVER_WRITE` | Write a Shift handover | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PRD_HANDOVER_ACKNOWLEDGE` | Acknowledge a Shift handover | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

## Phân tích

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `INS_TIER_BOARD_DISPLAY` | Tier board | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `INS_SKILL_COVERAGE_DISPLAY` | Skill coverage | · | · | · | · | · | ✓ |
| `INS_KPI_CATALOGUE_DISPLAY` | KPI catalogue | · | · | ✓ | ✓ | ✓ | ✓ |
| `INS_KPI_CATALOGUE_CHANGE` | Maintain the KPI catalogue | · | · | ✓ | ✓ | ✓ | ✓ |
| `INS_KPI_REVIEW_DISPLAY` | KPI review | · | · | ✓ | ✓ | ✓ | ✓ |
| `INS_KPI_REVIEW_RECORD` | Record a KPI review | · | · | ✓ | ✓ | ✓ | ✓ |

## Quản trị

| Mã quyền | Việc được làm | Mọi | Operator | Supervisor | Engineer | Manager | Admin |
| --- | --- | :-: | :-: | :-: | :-: | :-: | :-: |
| `ADM_APPROVALS_DISPLAY` | Approvals | · | · | · | · | · | ✓ |
| `ADM_APPROVALS_DECIDE` | Decide an Approval | · | · | · | · | · | ✓ |
| `ADM_ACCOUNTS_DISPLAY` | Accounts | · | · | · | · | · | ✓ |
| `ADM_ACCOUNTS_CHANGE` | Administer Accounts | · | · | · | · | · | ✓ |
| `ADM_ROLES_DISPLAY` | Roles | · | · | · | · | · | ✓ |
| `ADM_ROLES_CHANGE` | Maintain roles | · | · | · | · | · | ✓ |

## Tổng số quyền mỗi vai trò

| Vai trò | Mã (`app_roles.code`) | Số quyền |
| --- | --- | ---: |
| Nhóm mặc định | `ROLE_STANDARD` | 42 |
| Operator | `ROLE_OPERATOR` | 42 |
| Supervisor | `ROLE_SUPERVISOR` | 63 |
| Engineer | `ROLE_ENGINEER` | 64 |
| Manager | `ROLE_MANAGER` | 64 |
| Quản trị viên | `ROLE_ADMIN` | 84 |

