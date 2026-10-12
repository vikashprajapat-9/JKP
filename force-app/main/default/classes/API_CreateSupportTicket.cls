@RestResource(urlMapping='/api/v1/support_tickets')
global without sharing class API_CreateSupportTicket {

    private static final String INITIAL_STATUS_LABEL = 'Pending';

    @HttpPost
    global static void createSupportTicket() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            RequestWrapper request = parseRequest(RestContext.request);
            SuccessResponse result = createTicket(UserInfo.getUserId(), request);
            response.statusCode   = 201;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (ApiException e) {
            response.statusCode   = e.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(e.statusCode, e.getMessage())));
        } catch (Exception e) {
            System.debug('Error in API_CreateSupportTicket.createSupportTicket ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_CreateSupportTicket', 'createSupportTicket', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(500, 'Failed to create support ticket')));
        }
    }

    private static RequestWrapper parseRequest(RestRequest restRequest) {
        if (restRequest == null || restRequest.requestBody == null || String.isBlank(restRequest.requestBody.toString())) {
            throw new ApiException(400, 'Request body is required');
        }
        RequestWrapper parsed;
        try {
            parsed = (RequestWrapper) JSON.deserialize(restRequest.requestBody.toString(), RequestWrapper.class);
        } catch (JSONException e) {
            throw new ApiException(400, 'Invalid request body');
        }
        if (parsed == null|| String.isBlank(parsed.issue_type)|| String.isBlank(parsed.property_id)|| String.isBlank(parsed.unit_number)|| String.isBlank(parsed.description)) {
            throw new ApiException(400, 'issue_type, property_id, unit_number and description are required');
        }
        parsed.issue_type = parsed.issue_type.trim();
        parsed.property_id   = parsed.property_id.trim();
        parsed.unit_number   = parsed.unit_number.trim();
        return parsed;
    }


    private static SuccessResponse createTicket(String userId, RequestWrapper request) {
        if (String.isBlank(userId)) {
            throw new ApiException(400, 'Unable to identify the authenticated user');
        }

        Schema.PicklistEntry typeEntry = findActiveEntry(Case.Type.getDescribe().getPicklistValues(), request.issue_type);
        if (typeEntry == null) {
            throw new ApiException(400, 'Invalid issue type');
        }

        Id projectId;
        try {
            projectId = Id.valueOf(request.property_id);
        } catch (StringException e) {
            throw new ApiException(404, 'Property not found');
        }

        Unit__c unit = resolveUnit(request.unit_number, projectId);

        assertCustomerOwnsUnit(userId, unit.Id);

        String location       = resolveOptionalValue(Case.Location__c, request.location, 'Invalid location');
        String masterCategory = resolveOptionalValue(Case.Master_Category__c, request.master_category, 'Invalid master category');
        String subCategory    = resolveOptionalValue(Case.Sub_Category__c, request.sub_category, 'Invalid sub category');

        Case supportCase = new Case(
            Type               = typeEntry.getValue(),
            Project__c         = projectId,
            Unit__c            = unit.Id,
            Description        = request.description,
            Subject            = request.description,
            Status             = 'NEW',
            Sub_Type__c        = request.issue_subtype,
            Location__c        = location,
            Master_Category__c = masterCategory,
            Sub_Category__c    = subCategory
        );
        insert as system supportCase;

        Case saved = [SELECT Id, CaseNumber, Type, Status, Description, CreatedDate, ClosedDate FROM Case WHERE Id = :supportCase.Id WITH SYSTEM_MODE LIMIT 1 ];

        TicketWrapper ticket = new TicketWrapper();
        ticket.id            = String.valueOf(saved.Id);
        ticket.ticket_number = saved.CaseNumber;
        ticket.category      = getLabel(Case.Type.getDescribe().getPicklistValues(), saved.Type);
        ticket.status        = saved.Status;
        ticket.status_label  = getLabel(Case.Status.getDescribe().getPicklistValues(), saved.Status);
        ticket.description   = saved.Description;
        ticket.created_date  = saved.CreatedDate;
        ticket.closed_date   = saved.ClosedDate;
        ticket.project       = new ProjectWrapper();
        ticket.project.id    = String.valueOf(projectId);
        ticket.project.name  = unit.Floor__r.Block__r.Project__r.Name;
        ticket.unit_number   = unit.Unit_Name_Code__c;

        SuccessResponse result = new SuccessResponse();
        result.ticket = ticket;
        return result;
    }

    private static Unit__c resolveUnit(String unitNumber, Id projectId) {
        List<Unit__c> units = [SELECT Id, Unit_Name_Code__c, Floor__r.Block__r.Project__c, Floor__r.Block__r.Project__r.Name FROM Unit__c WHERE Unit_Name_Code__c = :unitNumber WITH SYSTEM_MODE];

        List<Unit__c> inProject = new List<Unit__c>();
        for (Unit__c candidate : units) {
            if (candidate.Floor__r?.Block__r?.Project__c == projectId) {
                inProject.add(candidate);
            }
        }
        if (inProject.isEmpty()) {
            throw new ApiException(404, 'Unit not found');
        }
        if (inProject.size() > 1) {
            throw new ApiException(409, 'Multiple units match the supplied unit_number');
        }
        return inProject[0];
    }

    private static void assertCustomerOwnsUnit(String userId, Id unitId) {
        List<User> users = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1 ];
        Id accountId = (users.isEmpty() || users[0].Contact == null) ? null : users[0].Contact.AccountId;
        if (accountId == null) {
            throw new ApiException(403, 'You do not have access to this property');
        }

        List<Opportunity> owned = [SELECT Id FROM Opportunity WHERE AccountId = :accountId AND Unit__c = :unitId WITH SYSTEM_MODE LIMIT 1 ];
        if (owned.isEmpty()) {
            throw new ApiException(403, 'You do not have access to this property');
        }
    }

    private static Schema.PicklistEntry findActiveEntry(List<Schema.PicklistEntry> entries, String input) {
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()
                && (input.equalsIgnoreCase(entry.getValue()) || input.equalsIgnoreCase(entry.getLabel()))) {
                return entry;
            }
        }
        return null;
    }

    private static String resolveOptionalValue(Schema.SObjectField field, String input, String errorMessage) {
        if (String.isBlank(input)) {
            return null;
        }
        String trimmed = input.trim();
        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        if (fieldDescribe.getType() != Schema.DisplayType.PICKLIST) {
            return trimmed;
        }
        Schema.PicklistEntry entry = findActiveEntry(fieldDescribe.getPicklistValues(), trimmed);
        if (entry == null) {
            throw new ApiException(400, errorMessage);
        }
        return entry.getValue();
    }

    private static String getLabel(List<Schema.PicklistEntry> entries, String value) {
        if (value == null) {
            return null;
        }
        for (Schema.PicklistEntry entry : entries) {
            if (entry.getValue() == value) {
                return entry.getLabel();
            }
        }
        return value;
    }


    public class ApiException extends Exception {
        public Integer statusCode;
        public ApiException(Integer statusCode, String message) {
            this(message);
            this.statusCode = statusCode;
        }
    }

    public class RequestWrapper {
        public String issue_type;
        public String issue_subtype;
        public String property_id;
        public String unit_number;
        public String description;
        public String location;
        public String master_category;
        public String sub_category;
    }

    public class SuccessResponse {
        public TicketWrapper ticket;
    }

    public class ErrorResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;

        public ErrorResponse(Integer statusCode, String message) {
            this.success    = false;
            this.statusCode = statusCode;
            this.message    = message;
        }
    }

    public class TicketWrapper {
        public String id;
        public String ticket_number;
        public String category;
        public String status;
        public String status_label;
        public String description;
        public Datetime created_date;
        public Datetime closed_date;
        public ProjectWrapper project;
        public String unit_number;
    }

    public class ProjectWrapper {
        public String id;
        public String name;
    }
}