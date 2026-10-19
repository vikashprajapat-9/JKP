@RestResource(urlMapping='/api/v1/referrals')
global without sharing class API_Referrals {

    private static final Integer DEFAULT_OFFSET = 0;
    private static final Integer DEFAULT_LIMIT  = 10;
    private static final Integer MAX_LIMIT      = 100;

    @HttpGet
    global static void getReferrals() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ReferralsResponse result = buildReferralsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_Referrals.getReferrals ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Referrals', 'getReferrals', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving referrals', null)));
        }
    }

    private static ReferralsResponse buildReferralsResponse(RestRequest request) {
        try {
            Map<String, String> params = request != null && request.params != null ? request.params : new Map<String, String>();

            String period = params.get('period');
            if (String.isBlank(period)) {
                return createResponse(false, 400, 'period is required', null);
            }
            period = period.trim().toLowerCase();
            Set<String> supportedPeriods = new Set<String>{ 'week', 'month', '6month', 'custom' };
            if (!supportedPeriods.contains(period)) {
                return createResponse(false, 400, 'Invalid period. Supported values are week, month, 6month and custom', null);
            }

            Date fromDate;
            Date toDate;
            String periodLabel;
            Date today = Date.today();

            if (period == 'week') {
                fromDate = today.addDays(-6);
                toDate = today;
                periodLabel = 'This week';
            } else if (period == 'month') {
                fromDate = today.toStartOfMonth();
                toDate = fromDate.addMonths(1).addDays(-1);
                periodLabel = 'This month';
            } else if (period == '6month') {
                fromDate = today.addMonths(-6).addDays(1);
                toDate = today;
                periodLabel = 'Last 6 months';
            } else {
                String fromDateParam = params.get('fromDate');
                String toDateParam   = params.get('toDate');
                if (String.isBlank(fromDateParam) || String.isBlank(toDateParam)) {
                    return createResponse(false, 400, 'fromDate and toDate are required for period=custom', null);
                }
                try {
                    fromDate = Date.valueOf(fromDateParam.trim());
                    toDate   = Date.valueOf(toDateParam.trim());
                } catch (Exception ex) {
                    return createResponse(false, 400, 'fromDate and toDate must be valid dates in YYYY-MM-DD format', null);
                }
                if (fromDate > toDate) {
                    return createResponse(false, 400, 'fromDate cannot be greater than toDate', null);
                }
                periodLabel = 'Custom';
            }

            Integer offsetValue = parseInteger(params.get('offsetValue'), DEFAULT_OFFSET);
            Integer limitValue  = parseInteger(params.get('limitValue'), DEFAULT_LIMIT);
            if (offsetValue == null || offsetValue < 0 || limitValue == null || limitValue <= 0) {
                return createResponse(false, 400, 'Invalid pagination parameters', null);
            }
            limitValue = Math.min(limitValue, MAX_LIMIT);

            PeriodWrapper periodWrapper = new PeriodWrapper();
            periodWrapper.type     = period;
            periodWrapper.label    = periodLabel;
            periodWrapper.fromDate = String.valueOf(fromDate);
            periodWrapper.toDate   = String.valueOf(toDate);

            ReferralsData data = new ReferralsData();
            data.period    = periodWrapper;
            data.referrals = new List<ReferralWrapper>();

            String currentUserId = UserInfo.getUserId();
            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :currentUserId LIMIT 1];
            Id accountId = (!matchedUsers.isEmpty() && matchedUsers[0].Contact != null) ? matchedUsers[0].Contact.AccountId : null;

            if (accountId == null) {
                data.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Referrals retrieved successfully', data);
            }

            Datetime fromDateTime = Datetime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
            Datetime toDateTime   = Datetime.newInstance(toDate, Time.newInstance(23, 59, 59, 999));

            Integer totalCount = [SELECT COUNT() FROM Lead WHERE Referred_By__c = :accountId AND CreatedDate >= :fromDateTime AND CreatedDate <= :toDateTime WITH SYSTEM_MODE];

            if (totalCount == 0) {
                data.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Referrals retrieved successfully', data);
            }

            List<Lead> matchedLeads = [SELECT Id, Name, Email, Phone, Status, Project__c, Project__r.Name FROM Lead WHERE Referred_By__c = :accountId AND CreatedDate >= :fromDateTime AND CreatedDate <= :toDateTime WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT :limitValue OFFSET :offsetValue];

            Map<String, String> statusLabelByApiValue = getLeadStatusLabels();

            for (Lead leadRecord : matchedLeads) {
                ReferralWrapper referral = new ReferralWrapper();
                referral.referralId   = String.valueOf(leadRecord.Id);
                referral.fullName     = leadRecord.Name;
                referral.propertyName = leadRecord.Project__r != null ? leadRecord.Project__r.Name : null;
                referral.propertyId   = leadRecord.Project__c != null ? String.valueOf(leadRecord.Project__c) : null;
                referral.email        = leadRecord.Email;
                referral.phone        = leadRecord.Phone;
                referral.status       = leadRecord.Status;
                referral.statusLabel  = leadRecord.Status != null && statusLabelByApiValue.containsKey(leadRecord.Status) ? statusLabelByApiValue.get(leadRecord.Status) : leadRecord.Status;
                data.referrals.add(referral);
            }

            data.pagination = buildPagination(totalCount, offsetValue, limitValue, matchedLeads.size());

            return createResponse(true, 200, 'Referrals retrieved successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_Referrals.buildReferralsResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Referrals', 'buildReferralsResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving referrals', null);
        }
    }

    private static Map<String, String> getLeadStatusLabels() {
        Map<String, String> statusLabelByApiValue = new Map<String, String>();
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            statusLabelByApiValue.put(entry.getValue(), entry.getLabel());
        }
        return statusLabelByApiValue;
    }

    private static Integer parseInteger(String rawValue, Integer defaultValue) {
        if (String.isBlank(rawValue)) {
            return defaultValue;
        }
        String trimmed = rawValue.trim();
        return trimmed.isNumeric() ? Integer.valueOf(trimmed) : null;
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'hasMore'     => (offsetValue + returnedCount) < totalCount,
            'limitValue'  => limitValue,
            'offsetValue' => offsetValue + limitValue,
            'totalCount'  => totalCount
        };
    }

    private static ReferralsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ReferralsData data) {
        ReferralsResponse apiResponse = new ReferralsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ReferralsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ReferralsData data;
    }

    public class ReferralsData {
        public PeriodWrapper period;
        public List<ReferralWrapper> referrals;
        public Map<String, Object> pagination;
    }

    public class PeriodWrapper {
        public String type;
        public String label;
        public String fromDate;
        public String toDate;
    }

    public class ReferralWrapper {
        public String referralId;
        public String fullName;
        public String propertyName;
        public String propertyId;
        public String email;
        public String phone;
        public String status;
        public String statusLabel;
    }
}