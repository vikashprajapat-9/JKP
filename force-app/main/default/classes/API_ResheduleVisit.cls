@RestResource(urlMapping='/api/v1/reschedule-visits/*')
global without sharing class API_ResheduleVisit {

    @HttpPost
    global static void rescheduleVisit() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String userId = UserInfo.getUserId();
            RescheduleVisitResponse result = rescheduleCustomerVisit(userId, request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ResheduleVisit.rescheduleVisit ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ResheduleVisit', 'rescheduleVisit', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to reschedule visit', null)));
        }
    }

    private static RescheduleVisitResponse rescheduleCustomerVisit(String userId, RestRequest request) {
        try {
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'Unable to identify the authenticated user', null);
            }

            String previousVisitId = extractVisitId(request);
            if (String.isBlank(previousVisitId)) {
                return createResponse(false, 400, 'Invalid visit_id', null);
            }
            if (!isValidSalesforceId(previousVisitId)) {
                return createResponse(false, 400, 'Invalid visit_id', null);
            }

            if (request == null || request.requestBody == null) {
                return createResponse(false, 400, 'Request body is required', null);
            }

            RescheduleRequest rescheduleRequest;
            try {
                rescheduleRequest = (RescheduleRequest) JSON.deserialize(request.requestBody.toString(), RescheduleRequest.class);
            } catch (Exception parseException) {
                return createResponse(false, 400, 'Invalid request body', null);
            }
            if (rescheduleRequest == null) {
                return createResponse(false, 400, 'Invalid request body', null);
            }

            if (String.isBlank(rescheduleRequest.visit_date)) {
                return createResponse(false, 400, 'visit_date is required', null);
            }
            if (String.isBlank(rescheduleRequest.time_slot)) {
                return createResponse(false, 400, 'time_slot is required', null);
            }

            if (!Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', rescheduleRequest.visit_date)) {
                return createResponse(false, 400, 'Invalid visit_date. Expected format YYYY-MM-DD', null);
            }
            Date newVisitDate;
            try {
                newVisitDate = Date.valueOf(rescheduleRequest.visit_date);
            } catch (Exception dateException) {
                return createResponse(false, 400, 'Invalid visit_date. Expected format YYYY-MM-DD', null);
            }

            if (!Pattern.matches('^([01]\\d|2[0-3]):[0-5]\\d$', rescheduleRequest.time_slot)) {
                return createResponse(false, 400, 'Invalid time_slot. Expected format HH:mm', null);
            }
            List<String> timeParts = rescheduleRequest.time_slot.split(':');
            Time newVisitTime = Time.newInstance(Integer.valueOf(timeParts[0]), Integer.valueOf(timeParts[1]), 0, 0);

            List<User> matchedUsers = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId LIMIT 1];
            if (matchedUsers.isEmpty() || matchedUsers[0].Contact == null) {
                return createResponse(false, 404, 'Visit not found', null);
            }
            Id accountId = matchedUsers[0].Contact.AccountId;

            List<Visit__c> matchedVisits = [
                SELECT Id, Status__c, Visit_Date__c, Visit_Time__c, Remarks__c, Sales_Manager__c,Opportunity__c, Opportunity__r.AccountId, Unit__c,
                       Unit__r.Unit_Name_Code__c, Unit__r.Unit_Type__c,Project__c,Project__r.Id,Project__r.Name,Project__r.Project_Code__c,
                       Project__r.Project_Location__Street__s,Project__r.Project_Location__City__s,Project__r.Project_Location__StateCode__s,
                       Project__r.Project_Location__PostalCode__s,Project__r.Project_Location__CountryCode__s
                FROM Visit__c
                WHERE Id = :previousVisitId WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (matchedVisits.isEmpty()) {
                return createResponse(false, 404, 'Visit not found', null);
            }
            Visit__c previousVisit = matchedVisits[0];

            if (previousVisit.Opportunity__r == null || previousVisit.Opportunity__r.AccountId != accountId) {
                return createResponse(false, 404, 'Visit not found', null);
            }

            String upcomingStatusValue    = getPicklistValueByName(Visit__c.Status__c, 'Upcoming');
            String rescheduledStatusValue = getPicklistValueByName(Visit__c.Status__c, 'Rescheduled');
            if (upcomingStatusValue == null || rescheduledStatusValue == null) {
                return createResponse(false, 500, 'Failed to reschedule visit', null);
            }

            if (previousVisit.Status__c != upcomingStatusValue) {
                return createResponse(false, 400, 'This visit cannot be rescheduled', null);
            }

            Datetime previousScheduledAt = previousVisit.Visit_Date__c != null ? Datetime.newInstance(previousVisit.Visit_Date__c, previousVisit.Visit_Time__c != null ? previousVisit.Visit_Time__c : Time.newInstance(0, 0, 0, 0)) : null;

            Integer rescheduleCount = countRescheduleChain(previousVisit.Id) + 1;

            String rescheduleReasonText = String.isNotBlank(rescheduleRequest.reschedule_reason) ? rescheduleRequest.reschedule_reason : rescheduleRequest.reschedule_reason_id;

            Project__c project = previousVisit.Project__r;

            PropertyWrapper property = new PropertyWrapper();
            property.id        = project != null ? (String.isNotBlank(project.Project_Code__c) ? project.Project_Code__c : String.valueOf(project.Id)) : null;
            property.name      = project != null ? project.Name : null;
            property.address   = project != null ? buildAddress(project) : null;
            property.unit_type = previousVisit.Unit__r != null ? previousVisit.Unit__r.Unit_Type__c : null;
            property.image_url = project != null ? getFirstFileUrlForProject(project.Id) : null;

            Visit__c newVisit = new Visit__c();
            newVisit.Opportunity__c        = previousVisit.Opportunity__c;
            newVisit.Unit__c               = previousVisit.Unit__c;
            newVisit.Project__c            = previousVisit.Project__c;
            newVisit.Visit_Date__c         = newVisitDate;
            newVisit.Visit_Time__c         = newVisitTime;
            newVisit.Status__c             = upcomingStatusValue;
            newVisit.Follow_Up_of_Visit__c = previousVisit.Id;
            newVisit.Remarks__c            = rescheduleRequest.details;

            Savepoint savepoint = Database.setSavepoint();

            try {
                previousVisit.Status__c = rescheduledStatusValue;
                Database.SaveResult updateResult = Database.update(previousVisit, AccessLevel.SYSTEM_MODE);
                if (!updateResult.isSuccess()) {
                    Database.rollback(savepoint);
                    String errorMessage = !updateResult.getErrors().isEmpty() ? updateResult.getErrors()[0].getMessage() : 'Unknown error';
                    System.debug('Failed to update previous visit status ===> ' + errorMessage);
                    return createResponse(false, 500, 'Failed to reschedule visit', null);
                }

                Database.SaveResult insertResult = Database.insert(newVisit, AccessLevel.SYSTEM_MODE);
                if (!insertResult.isSuccess()) {
                    Database.rollback(savepoint);
                    String errorMessage = !insertResult.getErrors().isEmpty() ? insertResult.getErrors()[0].getMessage() : 'Unknown error';
                    System.debug('Failed to insert rescheduled visit ===> ' + errorMessage);
                    return createResponse(false, 500, 'Failed to reschedule visit', null);
                }
            } catch (Exception dmlException) {
                Database.rollback(savepoint);
                System.debug('DML error while rescheduling visit ===> ' + dmlException.getMessage() + ' | line ' + dmlException.getLineNumber());
                IntegrationLogUtility.captureError('API_ResheduleVisit', 'rescheduleCustomerVisit', dmlException, null, 'SFA - SFDC');
                return createResponse(false, 500, 'Failed to reschedule visit', null);
            }

            Datetime rescheduledAt  = System.now();
            Datetime newScheduledAt = Datetime.newInstance(newVisitDate, newVisitTime);

            VisitWrapper visitWrapper = new VisitWrapper();
            visitWrapper.id                    = String.valueOf(newVisit.Id);
            visitWrapper.status                = 'upcoming';
            visitWrapper.status_label          = getPicklistLabel(Visit__c.Status__c, upcomingStatusValue);
            visitWrapper.scheduled_at          = formatDateTime(newScheduledAt);
            visitWrapper.previous_scheduled_at = formatDateTime(previousScheduledAt);
            visitWrapper.rescheduled_at        = formatDateTime(rescheduledAt);
            visitWrapper.reschedule_count      = rescheduleCount;
            visitWrapper.completed_at          = null;
            visitWrapper.cancelled_at          = null;
            visitWrapper.comments              = newVisit.Remarks__c;
            visitWrapper.sales_order_no        = null;
            visitWrapper.unit_number           = previousVisit.Unit__r != null ? previousVisit.Unit__r.Unit_Name_Code__c : null;
            visitWrapper.customer_id           = previousVisit.Opportunity__c != null ? String.valueOf(previousVisit.Opportunity__c) : null;
            // visitWrapper.crm_person            = previousVisit.Sales_Manager__c;
            visitWrapper.details               = rescheduleRequest.details;
            visitWrapper.property              = property;

            RescheduleVisitData data = new RescheduleVisitData();
            data.visit = visitWrapper;

            return createResponse(true, 200, 'Visit rescheduled successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_ResheduleVisit.rescheduleCustomerVisit ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ResheduleVisit', 'rescheduleCustomerVisit', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to reschedule visit', null);
        }
    }

    private static Integer countRescheduleChain(Id startingVisitId) {
        Map<Id, Id> followUpByVisitId = new Map<Id, Id>();
        for (Visit__c visit : [SELECT Id, Follow_Up_of_Visit__c FROM Visit__c WHERE Id != null WITH SYSTEM_MODE]) {
            followUpByVisitId.put(visit.Id, visit.Follow_Up_of_Visit__c);
        }

        Integer chainLength = 0;
        Id currentVisitId = startingVisitId;
        Set<Id> visitedIds = new Set<Id>();
        while (currentVisitId != null && !visitedIds.contains(currentVisitId)) {
            visitedIds.add(currentVisitId);
            chainLength++;
            currentVisitId = followUpByVisitId.get(currentVisitId);
        }
        return chainLength;
    }

    private static String extractVisitId(RestRequest request) {
        String requestUri = request != null && request.requestURI != null ? request.requestURI : '';
        List<String> uriSegments = requestUri.split('/');
        Integer visitsIndex = uriSegments.indexOf('reschedule-visits');
        return visitsIndex >= 0 && visitsIndex + 1 < uriSegments.size() ? uriSegments[visitsIndex + 1] : null;
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static String getPicklistValueByName(Schema.SObjectField field, String targetName) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(targetName)) {
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

    private static String getFirstFileUrlForProject(Id projectId) {
        List<Sub_Document__c> subDocuments = [SELECT Id, File_Url__c FROM Sub_Document__c WHERE Document__r.Project__c = :projectId AND Document__r.Name = 'Project Images' AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT 1];
        // Direct file link, so the app can show the picture itself (the sharing link opens a SharePoint page)
        return subDocuments.isEmpty() ? null : SharePointService.directUrl(subDocuments[0].File_Url__c);
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

    private static RescheduleVisitResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, RescheduleVisitData data) {
        RescheduleVisitResponse apiResponse = new RescheduleVisitResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class RescheduleRequest {
        public String visit_date;
        public String time_slot;
        public String reschedule_reason_id;
        public String reschedule_reason;
        public String details;
    }

    public class RescheduleVisitResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public RescheduleVisitData data;
    }

    public class RescheduleVisitData {
        public VisitWrapper visit;
    }

    public class VisitWrapper {
        public String id;
        public String status;
        public String status_label;
        public String scheduled_at;
        public String previous_scheduled_at;
        public String rescheduled_at;
        public Integer reschedule_count;
        public String completed_at;
        public String cancelled_at;
        public String comments;
        public String sales_order_no;
        public String unit_number;
        public String customer_id;
        public String crm_person;
        // public VisitTypeWrapper visit_type;
        public String details;
        public PropertyWrapper property;
    }

    public class VisitTypeWrapper {
        public String id;
        public String label;
    }

    public class PropertyWrapper {
        public String id;
        public String name;
        public String address;
        public String unit_type;
        public String image_url;
    }
}