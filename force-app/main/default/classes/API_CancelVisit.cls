@RestResource(urlMapping='/api/v1/visits/*')
global without sharing class API_CancelVisit {

    @HttpPost
    global static void cancelVisit() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String userId = UserInfo.getUserId();
            CancelVisitResponse result = cancelCustomerVisit(userId, request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_CancelVisit.cancelVisit ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_CancelVisit', 'cancelVisit', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to cancel visit', null)));
        }
    }

    private static CancelVisitResponse cancelCustomerVisit(String userId, RestRequest request) {
        try {
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'Unable to identify the authenticated user', null);
            }

            String visitId = extractVisitId(request);
            if (String.isBlank(visitId)) {
                return createResponse(false, 400, 'visit_id is required', null);
            }
            if (!isValidSalesforceId(visitId)) {
                return createResponse(false, 400, 'visit_id is invalid', null);
            }

            String cancellationReason = extractCancellationReason(request);
            if (String.isBlank(cancellationReason)) {
                return createResponse(false, 400, 'cancellation_reason is required', null);
            }

            List<User> matchedUsers = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId LIMIT 1];
            if (matchedUsers.isEmpty() || matchedUsers[0].Contact == null) {
                return createResponse(false, 404, 'Visit not found', null);
            }
            Id accountId = matchedUsers[0].Contact.AccountId;

            List<Visit__c> matchedVisits = [
                SELECT Id, Status__c, Visit_Date__c, Visit_Time__c,Completed_At_Date_Time__c, Cancelled_At_Date_Time__c, Remarks__c,
                       Reason_of_Cancellation__c, Sales_Manager__c, Opportunity__c,Opportunity__r.AccountId,Unit__r.Unit_Name_Code__c,
                       Unit__r.Unit_Type__c,Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Id,Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Name,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__Street__s,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__City__s,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__StateCode__s,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__PostalCode__s,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__CountryCode__s
                FROM Visit__c
                WHERE Id = :visitId WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (matchedVisits.isEmpty()) {
                return createResponse(false, 404, 'Visit not found', null);
            }
            Visit__c visit = matchedVisits[0];

            if (visit.Opportunity__r == null || visit.Opportunity__r.AccountId != accountId) {
                return createResponse(false, 404, 'Visit not found', null);
            }

            String cancelledStatusValue = getPicklistValueByName(Visit__c.Status__c, 'Cancelled');
            if (cancelledStatusValue == null) {
                return createResponse(false, 500, 'Failed to cancel visit', null);
            }

            visit.Status__c                 = cancelledStatusValue;
            visit.Reason_of_Cancellation__c = cancellationReason;
            visit.Cancelled_At_Date_Time__c = System.now();
           // update visit;
			Database.SaveResult saveResult = Database.update(visit, AccessLevel.SYSTEM_MODE);
            if (!saveResult.isSuccess()) {
                String errorMessage = !saveResult.getErrors().isEmpty() ? saveResult.getErrors()[0].getMessage() : 'Unknown error';
                System.debug('Failed to update visit ===> ' + errorMessage);
                IntegrationLogUtility.captureError('API_CancelVisit', 'cancelCustomerVisit', null, null, 'SFA - SFDC');
                return createResponse(false, 500, 'Failed to cancel visit', null);
            }
            Project__c project = getProject(visit);
            List<String> imageUrls = project != null ? getFileUrlsForProject(project.Id) : new List<String>();

            PropertyWrapper property = new PropertyWrapper();
            property.id        = project != null ? String.valueOf(project.Id) : null;
            property.name      = project != null ? project.Name : null;
            property.address   = project != null ? buildAddress(project) : null;
            property.unit_type = visit.unit__c != null ? visit.unit__r.Unit_Type__c : null;
            property.image_url = imageUrls;

            VisitWrapper visitWrapper = new VisitWrapper();
            visitWrapper.id                  = String.valueOf(visit.Id);
            visitWrapper.status               = cancelledStatusValue;
            visitWrapper.status_label         = getPicklistLabel(Visit__c.Status__c, cancelledStatusValue);
            visitWrapper.scheduled_at         = getScheduledAt(visit);
            visitWrapper.completed_at         = formatDateTime(visit.Completed_At_Date_Time__c);
            visitWrapper.cancelled_at         = formatDateTime(visit.Cancelled_At_Date_Time__c);
            visitWrapper.comments             = visit.Remarks__c;
            visitWrapper.sales_order_no       = null;
            visitWrapper.unit_number          = visit.unit__c != null ? visit.unit__r.Unit_Name_Code__c : null;
            visitWrapper.customer_id          = visit.Opportunity__c != null ? String.valueOf(visit.Opportunity__c) : null;
            visitWrapper.cancellation_reason  = visit.Reason_of_Cancellation__c;
            visitWrapper.property             = property;

            CancelVisitData data = new CancelVisitData();
            data.visit = visitWrapper;

            return createResponse(true, 200, 'Visit cancelled successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_CancelVisit.cancelCustomerVisit ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_CancelVisit', 'cancelCustomerVisit', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to cancel visit', null);
        }
    }

    private static String extractVisitId(RestRequest request) {
        String requestUri = request != null && request.requestURI != null ? request.requestURI : '';
        List<String> uriSegments = requestUri.split('/');
        Integer visitsIndex = uriSegments.indexOf('visits');
        return visitsIndex >= 0 && visitsIndex + 1 < uriSegments.size() ? uriSegments[visitsIndex + 1] : null;
    }

    private static String extractCancellationReason(RestRequest request) {
        if (request == null || request.requestBody == null) {
            return null;
        }
        try {
            Map<String, Object> requestBody = (Map<String, Object>) JSON.deserializeUntyped(request.requestBody.toString());
            Object reasonValue = requestBody.get('cancellation_reason');
            return reasonValue != null ? String.valueOf(reasonValue).trim() : null;
        } catch (Exception e) {
            return null;
        }
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

    private static Project__c getProject(Visit__c visit) {
        if (visit.Opportunity__r == null || visit.Opportunity__r.Unit__r == null|| visit.Opportunity__r.Unit__r.Floor__r == null|| visit.Opportunity__r.Unit__r.Floor__r.Block__r == null) {
            return null;
        }
        return visit.Opportunity__r.Unit__r.Floor__r.Block__r.Project__r;
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

    private static String getScheduledAt(Visit__c visit) {
        if (visit.Visit_Date__c == null) {
            return null;
        }
        Time visitTime = visit.Visit_Time__c != null ? visit.Visit_Time__c : Time.newInstance(0, 0, 0, 0);
        return formatDateTime(Datetime.newInstance(visit.Visit_Date__c, visitTime));
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ssXXX');
    }

    private static CancelVisitResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, CancelVisitData data) {
        CancelVisitResponse apiResponse = new CancelVisitResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class CancelVisitResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public CancelVisitData data;
    }

    public class CancelVisitData {
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
        public String crm_person;
        public String cancellation_reason;
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