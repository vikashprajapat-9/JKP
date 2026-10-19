@RestResource(urlMapping='/api/v1/visits/schedule')
global without sharing class API_ScheduleVisit {

    @HttpPost
    global static void scheduleVisit() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String userId = UserInfo.getUserId();
            ScheduleVisitResponse result = scheduleCustomerVisit(userId, request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ScheduleVisit.scheduleVisit ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ScheduleVisit', 'scheduleVisit', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to schedule visit', null)));
        }
    }

    private static ScheduleVisitResponse scheduleCustomerVisit(String userId, RestRequest request) {
        try {
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'Unable to identify the authenticated user', null);
            }

            Map<String, Object> requestBody = parseRequestBody(request);
            if (requestBody == null) {
                return createResponse(false, 400, 'A valid JSON request body is required', null);
            }

            String projectId = getStringValue(requestBody, 'project_id');
            String unitNumber = getStringValue(requestBody, 'unit_number');
            String visitDateRaw = getStringValue(requestBody, 'visit_date');
            String timeSlotRaw = getStringValue(requestBody, 'time_slot');
            String details = getStringValue(requestBody, 'details');

            if (String.isBlank(projectId)) {
                return createResponse(false, 400, 'project_id is required', null);
            }
            if (!isValidSalesforceId(projectId)) {
                return createResponse(false, 400, 'project_id is invalid', null);
            }
            if (String.isBlank(unitNumber)) {
                return createResponse(false, 400, 'unit_number is required', null);
            }
            if (String.isBlank(visitDateRaw)) {
                return createResponse(false, 400, 'visit_date is required', null);
            }
            if (String.isBlank(timeSlotRaw)) {
                return createResponse(false, 400, 'time_slot is required', null);
            }

            Date visitDate;
            try {
                visitDate = Date.valueOf(visitDateRaw);
            } catch (Exception ex) {
                return createResponse(false, 400, 'visit_date must be in YYYY-MM-DD format', null);
            }

            Time visitTime = parseTimeSlot(timeSlotRaw);
            if (visitTime == null) {
                return createResponse(false, 400, 'time_slot must be in HH:mm format', null);
            }

            List<User> matchedUsers = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId LIMIT 1];
            if (matchedUsers.isEmpty() || matchedUsers[0].Contact == null) {
                return createResponse(false, 404, 'Property not found', null);
            }
            Id accountId = matchedUsers[0].Contact.AccountId;

            List<Unit__c> matchedUnits = [
                SELECT Id, Unit_Name_Code__c, Unit_Type__c,Floor__r.Block__r.Project__r.Id,Floor__r.Block__r.Project__r.Name,
                       Floor__r.Block__r.Project__r.Project_Location__Street__s,Floor__r.Block__r.Project__r.Project_Location__City__s,
                       Floor__r.Block__r.Project__r.Project_Location__StateCode__s,Floor__r.Block__r.Project__r.Project_Location__PostalCode__s,
                       Floor__r.Block__r.Project__r.Project_Location__CountryCode__s
                FROM Unit__c
                WHERE Unit_Name_Code__c = :unitNumber
                AND Floor__r.Block__r.Project__c = :projectId WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (matchedUnits.isEmpty()) {
                return createResponse(false, 404, 'Property not found', null);
            }
            Unit__c unit = matchedUnits[0];

            List<Opportunity> matchedOpportunities = [SELECT Id, AccountId, Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c = :unit.Id WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];
            if (matchedOpportunities.isEmpty()) {
                return createResponse(false, 404, 'Property not found', null);
            }
            Opportunity opportunity = matchedOpportunities[0];

            String scheduledStatusValue = getPicklistValueByLabel(Visit__c.Status__c, 'UpComing');
            if (scheduledStatusValue == null) {
                return createResponse(false, 500, 'Failed to schedule visit', null);
            }

            Visit__c newVisit = new Visit__c();
            newVisit.Opportunity__c = opportunity.Id;
            newVisit.Unit__c        = unit.Id;
            newVisit.Visit_Date__c  = visitDate;
            newVisit.Visit_Time__c  = visitTime;
            newVisit.Remarks__c     = details;
            newVisit.Status__c      = scheduledStatusValue;
			newVisit.Project__c      = projectId;
            Database.SaveResult saveResult = Database.insert(newVisit, AccessLevel.SYSTEM_MODE);
            if (!saveResult.isSuccess()) {
                String errorMessage = !saveResult.getErrors().isEmpty() ? saveResult.getErrors()[0].getMessage() : 'Unknown error';
                System.debug('Failed to insert visit ===> ' + errorMessage);
                return createResponse(false, 500, 'Failed to schedule visit', null);
            }

            PropertyWrapper property = new PropertyWrapper();
            property.id        = String.valueOf(unit.Floor__r.Block__r.Project__r.Id);
            property.name      = unit.Floor__r.Block__r.Project__r.Name;
            property.address   = buildAddress(unit.Floor__r.Block__r.Project__r);
            property.unit_type = unit.Unit_Type__c;
            property.image_url = getFileUrlsForProject(unit.Floor__r.Block__r.Project__r.Id);

            VisitWrapper visitWrapper = new VisitWrapper();
            visitWrapper.id           = String.valueOf(newVisit.Id);
            visitWrapper.status       = 'upcoming';
            visitWrapper.status_label = getPicklistLabel(Visit__c.Status__c, scheduledStatusValue);
            visitWrapper.scheduled_at = formatDateTime(Datetime.newInstance(visitDate, visitTime));
            visitWrapper.completed_at = null;
            visitWrapper.cancelled_at = null;
            visitWrapper.comments     = null;
            visitWrapper.sales_order_no = null;
            visitWrapper.unit_number  = unit.Unit_Name_Code__c;
            visitWrapper.customer_id  = String.valueOf(opportunity.Id);
            visitWrapper.details      = details;
            visitWrapper.property     = property;

            ScheduleVisitData data = new ScheduleVisitData();
            data.visit = visitWrapper;

            return createResponse(true, 201, 'Visit scheduled successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_ScheduleVisit.scheduleCustomerVisit ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ScheduleVisit', 'scheduleCustomerVisit', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to schedule visit', null);
        }
    }

    private static Map<String, Object> parseRequestBody(RestRequest request) {
        if (request == null || request.requestBody == null) {
            return null;
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(request.requestBody.toString());
        } catch (Exception e) {
            return null;
        }
    }

    private static String getStringValue(Map<String, Object> requestBody, String key) {
        Object rawValue = requestBody.get(key);
        return rawValue != null ? String.valueOf(rawValue).trim() : null;
    }

    private static Time parseTimeSlot(String timeSlotRaw) {
        List<String> timeParts = timeSlotRaw.split(':');
        if (timeParts.size() != 2 || !timeParts[0].isNumeric() || !timeParts[1].isNumeric()) {
            return null;
        }
        Integer hour = Integer.valueOf(timeParts[0]);
        Integer minute = Integer.valueOf(timeParts[1]);
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            return null;
        }
        return Time.newInstance(hour, minute, 0, 0);
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static String getPicklistValueByLabel(Schema.SObjectField field, String targetLabel) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getLabel().equalsIgnoreCase(targetLabel)) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String getPicklistLabel(Schema.SObjectField field, String apiValue) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.getValue() == apiValue) {
                return entry.getLabel();
            }
        }
        return apiValue;
    }

    private static List<String> getFileUrlsForProject(Id projectId) {
        List<String> fileUrls = new List<String>();
        for (Sub_Document__c subDocument : [SELECT Id, File_Url__c FROM Sub_Document__c WHERE Document__r.Project__c = :projectId AND Document__r.Name = 'Project Images' AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            // Direct file link, so the app can show the picture itself (the sharing link opens a SharePoint page)
            String imageUrl = SharePointService.directUrl(subDocument.File_Url__c);
            if (!fileUrls.contains(imageUrl)) {
                fileUrls.add(imageUrl);
            }
        }
        return fileUrls;
    }

    private static String buildAddress(Project__c project) {
        List<String> addressParts = new List<String>{
            project.Project_Location__Street__s,
            project.Project_Location__City__s,
            project.Project_Location__StateCode__s,
            project.Project_Location__PostalCode__s,
            project.Project_Location__CountryCode__s
        };
        List<String> nonBlankParts = new List<String>();
        for (String addressPart : addressParts) {
            if (String.isNotBlank(addressPart)) {
                nonBlankParts.add(addressPart);
            }
        }
        return nonBlankParts.isEmpty() ? null : String.join(nonBlankParts, ', ');
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ssXXX');
    }

    private static ScheduleVisitResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ScheduleVisitData data) {
        ScheduleVisitResponse apiResponse = new ScheduleVisitResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ScheduleVisitResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ScheduleVisitData data;
    }

    public class ScheduleVisitData {
        public VisitWrapper visit;
    }

    public class VisitWrapper {
        public String id;
        public String status;
        public String status_label;
        public String scheduled_at;
        public String completed_at;
        public String cancelled_at;
        public String comments;
        public String sales_order_no;
        public String unit_number;
        public String customer_id;
        public String details;
        public PropertyWrapper property;
    }

    public class PropertyWrapper {
        public String id;
        public String name;
        public String address;
        public String unit_type;
        public List<String> image_url;
    }
}