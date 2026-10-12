@RestResource(urlMapping='/api/v1/get_tickets/*')
global without sharing class API_SupportTickets {

    private static final Integer DEFAULT_OFFSET = 0;
    private static final Integer DEFAULT_LIMIT  = 10;
    private static final Integer MAX_LIMIT      = 100;

    private static final String MSG_SELECT_PROJECT = 'Please select the project to see the DLP period';
    private static final String MSG_SELECT_UNIT    = 'Select the unit to see the DLP';
    private static final String MSG_DLP_EXPIRED    = 'DLP is expired';
	private static final String MSG_DLP_NOT_STARTED = 'DLP not started';
    @HttpGet
    global static void getSupportTickets() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            Map<String, String> params = RestContext.request.params;

            String projectParam = params.get('projectId');
            String unitParam    = params.get('unitId');
            Id projectId = null;
            Id unitId    = null;

            if (String.isNotBlank(projectParam)) {
                if (!isValidId(projectParam, Project__c.SObjectType)) {
                    send(response, 400, createError(400, 'Invalid projectId'));
                    return;
                }
                projectId = Id.valueOf(projectParam.trim());
            }
            if (String.isNotBlank(unitParam)) {
                if (!isValidId(unitParam, Unit__c.SObjectType)) {
                    send(response, 400, createError(400, 'Invalid unitId'));
                    return;
                }
                unitId = Id.valueOf(unitParam.trim());
            }

            Integer offsetValue = parseInteger(params.get('offsetValue'), DEFAULT_OFFSET);
            Integer limitValue  = parseInteger(params.get('limitValue'), DEFAULT_LIMIT);
            if (offsetValue == null || limitValue == null || limitValue <= 0) {
                send(response, 400, createError(400, 'Invalid pagination parameters'));
                return;
            }
            limitValue = Math.min(limitValue, MAX_LIMIT);

            String userId = UserInfo.getUserId();
            List<User> users = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            Id accountId = !users.isEmpty() && users[0].Contact != null ? users[0].Contact.AccountId : null;
            if (accountId == null) {
                send(response, 403, createError(403, 'You do not have access to support tickets'));
                return;
            }

            List<Opportunity> customerOpportunities = [SELECT Id, Unit__c, Unit__r.Floor__r.Block__r.Project__c, DLP_Start_Date__c, DLP_End_Date__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC];

            String whereClause = ' FROM Case WHERE AccountId = :accountId';
            Map<String, Object> binds = new Map<String, Object>{ 'accountId' => accountId };
            if (projectId != null) {
                whereClause += ' AND Project__c = :projectId';
                binds.put('projectId', projectId);
            }
            if (unitId != null) {
                whereClause += ' AND Unit__c = :unitId';
                binds.put('unitId', unitId);
            }

            Integer totalCount = Database.countQueryWithBinds('SELECT COUNT()' + whereClause, binds, AccessLevel.SYSTEM_MODE);

            binds.put('limitValue', limitValue);
            binds.put('offsetValue', offsetValue);
            List<Case> cases = (List<Case>) Database.queryWithBinds(
                'SELECT Id, CaseNumber, Type, Status, Description, CreatedDate, ClosedDate, Project__c, Project__r.Name, Unit__c, Unit__r.Unit_Name_Code__c' +
                whereClause +
                ' ORDER BY CreatedDate DESC, Id DESC LIMIT :limitValue OFFSET :offsetValue',
                binds,
                AccessLevel.SYSTEM_MODE
            );

            Map<String, String> statusLabels = new Map<String, String>();
            for (Schema.PicklistEntry entry : Case.Status.getDescribe().getPicklistValues()) {
                statusLabels.put(entry.getValue(), entry.getLabel());
            }

            SuccessResponse result = new SuccessResponse();
            result.defects_liability_period = buildDlp(customerOpportunities, projectId, unitId);
            result.tickets = new List<TicketWrapper>();

            for (Case supportCase : cases) {
                ProjectWrapper project = new ProjectWrapper();
                project.id   = supportCase.Project__c != null ? String.valueOf(supportCase.Project__c) : null;
                project.name = supportCase.Project__r != null ? supportCase.Project__r.Name : null;

                TicketWrapper ticket = new TicketWrapper();
                ticket.id            = String.valueOf(supportCase.Id);
                ticket.ticket_number = supportCase.CaseNumber;
                ticket.Type          = supportCase.Type;
                ticket.status        = supportCase.Status;
                ticket.status_label  = statusLabels.get(supportCase.Status);
                ticket.description   = supportCase.Description;
                ticket.created_date  = formatDateTime(supportCase.CreatedDate);
                ticket.closed_date   = formatDateTime(supportCase.ClosedDate);
                ticket.project       = project;
                ticket.unit_number   = supportCase.Unit__r != null ? supportCase.Unit__r.Unit_Name_Code__c : null;
                result.tickets.add(ticket);
            }

            PaginationWrapper pagination = new PaginationWrapper();
            pagination.hasMore     = (offsetValue + cases.size()) < totalCount;
            pagination.limitValue  = limitValue;
            pagination.offsetValue = offsetValue;
            pagination.totalCount  = totalCount;
            result.pagination = pagination;

            send(response, 200, result);
        } catch (Exception e) {
            System.debug('Error in API_SupportTickets.getSupportTickets ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_SupportTickets', 'getSupportTickets', e, null, 'SFA - SFDC');
            send(response, 500, createError(500, 'Failed to retrieve support tickets'));
        }
    }

    private static DlpWrapper buildDlp(List<Opportunity> opportunities, Id projectId, Id unitId) {
        Set<Id> projectIds = new Set<Id>();
        Map<Id, Opportunity> opportunityByUnitId = new Map<Id, Opportunity>();

        for (Opportunity opportunity : opportunities) {
            Id opportunityProjectId = getProjectId(opportunity);
            if (projectId != null && opportunityProjectId != projectId) {
                continue;
            }
            if (unitId != null && opportunity.Unit__c != unitId) {
                continue;
            }
            if (opportunityProjectId != null) {
                projectIds.add(opportunityProjectId);
            }
            if (!opportunityByUnitId.containsKey(opportunity.Unit__c)) {
                opportunityByUnitId.put(opportunity.Unit__c, opportunity);
            }
        }

        if (unitId == null) {
            if (projectId == null && projectIds.size() > 1) {
                return createDlp(null, null, MSG_SELECT_PROJECT, false);
            }
            if (opportunityByUnitId.size() > 1) {
                return createDlp(null, null, MSG_SELECT_UNIT, false);
            }
        }

        if (opportunityByUnitId.isEmpty()) {
            return createDlp(null, null, null, false);
        }

        Opportunity opportunity = opportunityByUnitId.values()[0];
        Date startDate = opportunity.DLP_Start_Date__c;
        Date endDate   = opportunity.DLP_End_Date__c;
        if (startDate == null || endDate == null) {
            return createDlp(null, null, null, false);
        }

        String start = String.valueOf(startDate);
        String ending = String.valueOf(endDate);
        Date today = Date.today();

        if (today > endDate) {
            return createDlp(start, ending, MSG_DLP_EXPIRED, false);
        }
		
		if (startDate == null || endDate == null) {
			return createDlp(null, null, MSG_DLP_NOT_STARTED, false);
		}


        return createDlp(start, ending, 'DLP: ' + start + ' - ' + ending, today >= startDate);
    }

    private static Id getProjectId(Opportunity opportunity) {
        if (opportunity.Unit__r == null || opportunity.Unit__r.Floor__r == null || opportunity.Unit__r.Floor__r.Block__r == null) {
            return null;
        }
        return opportunity.Unit__r.Floor__r.Block__r.Project__c;
    }

    private static DlpWrapper createDlp(String startDate, String endDate, String message, Boolean isActive) {
        DlpWrapper dlp = new DlpWrapper();
        dlp.start_date = startDate;
        dlp.end_date   = endDate;
        dlp.message    = message;
        dlp.is_active  = isActive;
        return dlp;
    }

    private static Boolean isValidId(String rawValue, Schema.SObjectType expectedType) {
        try {
            return Id.valueOf(rawValue.trim()).getSObjectType() == expectedType;
        } catch (Exception e) {
            return false;
        }
    }

    private static Integer parseInteger(String rawValue, Integer defaultValue) {
        if (String.isBlank(rawValue)) {
            return defaultValue;
        }
        String trimmed = rawValue.trim();
        return trimmed.isNumeric() ? Integer.valueOf(trimmed) : null;
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? null : value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }

    private static ErrorResponse createError(Integer statusCode, String message) {
        ErrorResponse error = new ErrorResponse();
        error.success    = false;
        error.statusCode = statusCode;
        error.message    = message;
        return error;
    }

    private static void send(RestResponse response, Integer statusCode, Object body) {
        response.statusCode   = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    public class ErrorResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
    }

    public class SuccessResponse {
        public DlpWrapper defects_liability_period;
        public List<TicketWrapper> tickets;
        public PaginationWrapper pagination;
    }

    public class DlpWrapper {
        public String start_date;
        public String end_date;
        public String message;
        public Boolean is_active;
    }

    public class TicketWrapper {
        public String id;
        public String ticket_number;
        public String Type;
        public String status;
        public String status_label;
        public String description;
        public String created_date;
        public String closed_date;
        public ProjectWrapper project;
        public String unit_number;
    }

    public class ProjectWrapper {
        public String id;
        public String name;
    }

    public class PaginationWrapper {
        public Boolean hasMore;
        public Integer limitValue;
        public Integer offsetValue;
        public Integer totalCount;
    }
}