@RestResource(urlMapping='/api/v1/visits')
global without sharing class API_MyVisits {

    @HttpGet
    global static void getVisits() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String userId = UserInfo.getUserId();
            VisitsResponse result = getCustomerVisits(userId, request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_MyVisits.getVisits ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyVisits', 'getVisits', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to retrieve visits', null)));
        }
    }

    private static VisitsResponse getCustomerVisits(String userId, RestRequest request) {
        try {
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'Unable to identify the authenticated user', null);
            }

            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();

            String requestedStatus = requestParams.get('status');
            requestedStatus = requestedStatus != null ? requestedStatus.trim().toLowerCase() : null;
            if (String.isBlank(requestedStatus)) {
                return createResponse(false, 400, 'Status parameter is required', null);
            }

            Map<String, Schema.PicklistEntry> statusEntries = new Map<String, Schema.PicklistEntry>();
            for (Schema.PicklistEntry entry : Visit__c.Status__c.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    statusEntries.put(entry.getValue().toLowerCase(), entry);
                }
            }
            if (!statusEntries.containsKey(requestedStatus)) {
                List<String> allowedValues = new List<String>();
                for (Schema.PicklistEntry entry : statusEntries.values()) {
                    allowedValues.add(entry.getValue());
                }
                allowedValues.sort();
                return createResponse(false, 400, 'Invalid status. Allowed values are ' + String.join(allowedValues, ', '), null);
            }
            Schema.PicklistEntry statusEntry = statusEntries.get(requestedStatus);
            String statusValue = statusEntry.getValue();

            Integer offsetValue = requestParams.containsKey('offsetValue') && String.isNotBlank(requestParams.get('offsetValue'))? Integer.valueOf(requestParams.get('offsetValue')): 0;
            Integer limitValue = requestParams.containsKey('limitValue') && String.isNotBlank(requestParams.get('limitValue'))? Integer.valueOf(requestParams.get('limitValue')): 20;
            if (offsetValue == null || offsetValue < 0) {
                offsetValue = 0;
            }
            if (limitValue == null || limitValue <= 0) {
                limitValue = 20;
            }

            VisitsData data = new VisitsData();
            data.visits = new List<VisitWrapper>();

            List<User> matchedUsers = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId LIMIT 1];
            if (matchedUsers.isEmpty() || matchedUsers[0].Contact == null) {
                data.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Visits retrieved successfully', data);
            }
            Id accountId = matchedUsers[0].Contact.AccountId;

            Integer totalCount = [SELECT COUNT() FROM Visit__c WHERE Opportunity__r.AccountId = :accountId AND Status__c = :statusValue WITH SYSTEM_MODE];

            List<Visit__c> pagedVisits = [
                SELECT Id, Status__c, Visit_Date__c, Visit_Time__c,Completed_At_Date_Time__c, Cancelled_At_Date_Time__c, Remarks__c, Opportunity__c,
                       Unit__r.Unit_Name_Code__c,Unit__r.Unit_Type__c,Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Id,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Name,Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__Street__s,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__City__s,Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__StateCode__s,
                       Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__PostalCode__s,Opportunity__r.Unit__r.Floor__r.Block__r.Project__r.Project_Location__CountryCode__s
                FROM Visit__c
                WHERE Opportunity__r.AccountId = :accountId
                AND Status__c = :statusValue WITH SYSTEM_MODE
                ORDER BY Visit_Date__c DESC, Visit_Time__c DESC, Id DESC
                LIMIT :limitValue OFFSET :offsetValue
            ];

            data.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedVisits.size());

            if (pagedVisits.isEmpty()) {
                return createResponse(true, 200, 'Visits retrieved successfully', data);
            }

            Set<Id> projectIds = new Set<Id>();
            for (Visit__c visit : pagedVisits) {
                Project__c project = getProject(visit);
                if (project != null) {
                    projectIds.add(project.Id);
                }
            }
            Map<Id, List<String>> fileUrlsByProjectId = getFileUrlsByProjectId(projectIds);

            for (Visit__c visit : pagedVisits) {
                Project__c project = getProject(visit);

                PropertyWrapper property = new PropertyWrapper();
                property.id        = project != null ? String.valueOf(project.Id) : null;
                property.name      = project != null ? project.Name : null;
                property.address   = project != null ? buildAddress(project) : null;
                property.unit_type = visit.unit__c != null ? visit.unit__r.Unit_Type__c : null;
                property.image_url = project != null && fileUrlsByProjectId.containsKey(project.Id)? fileUrlsByProjectId.get(project.Id): new List<String>();

                VisitWrapper wrapper = new VisitWrapper();
                wrapper.id           = String.valueOf(visit.Id);
                wrapper.status       = statusEntry.getValue();
                wrapper.status_label = statusEntry.getLabel();
                wrapper.scheduled_at = getScheduledAt(visit);
                wrapper.completed_at = formatDateTime(visit.Completed_At_Date_Time__c);
                wrapper.cancelled_at = formatDateTime(visit.Cancelled_At_Date_Time__c);
                wrapper.comments     = visit.Remarks__c;
                wrapper.unit_number  = visit.unit__c != null ? visit.unit__r.Unit_Name_Code__c : null;
                wrapper.customer_id  = visit.Opportunity__c != null ? String.valueOf(visit.Opportunity__c) : null;
                wrapper.property     = property;
                data.visits.add(wrapper);
            }

            return createResponse(true, 200, 'Visits retrieved successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_MyVisits.getCustomerVisits ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyVisits', 'getCustomerVisits', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to retrieve visits', null);
        }
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

    private static Project__c getProject(Visit__c visit) {
        if (visit.Opportunity__r == null || visit.Opportunity__r.Unit__r == null || visit.Opportunity__r.Unit__r.Floor__r == null || visit.Opportunity__r.Unit__r.Floor__r.Block__r == null) {
            return null;
        }
        return visit.Opportunity__r.Unit__r.Floor__r.Block__r.Project__r;
    }

    private static Map<Id, List<String>> getFileUrlsByProjectId(Set<Id> projectIds) {
        Map<Id, List<String>> fileUrlsByProjectId = new Map<Id, List<String>>();
        if (projectIds.isEmpty()) {
            return fileUrlsByProjectId;
        }
        for (Sub_Document__c subDocument : [SELECT Id, Document__r.Project__c, File_Url__c FROM Sub_Document__c WHERE Document__r.Project__c IN :projectIds AND Document__r.Name = 'Project Images' AND File_Url__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            if (!fileUrlsByProjectId.containsKey(subDocument.Document__r.Project__c)) {
                fileUrlsByProjectId.put(subDocument.Document__r.Project__c, new List<String>());
            }
            List<String> projectFileUrls = fileUrlsByProjectId.get(subDocument.Document__r.Project__c);
            // Direct file link, so the app can show the picture itself (the sharing link opens a SharePoint page)
            String imageUrl = SharePointService.directUrl(subDocument.File_Url__c);
            if (!projectFileUrls.contains(imageUrl)) {
                projectFileUrls.add(imageUrl);
            }
        }
        return fileUrlsByProjectId;
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

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'totalCount'  => totalCount,
            'offsetValue' => offsetValue + limitValue,
            'limitValue'  => limitValue,
            'hasMore'     => (offsetValue + returnedCount) < totalCount
        };
    }

    private static VisitsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, VisitsData data) {
        VisitsResponse apiResponse = new VisitsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class VisitsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public VisitsData data;
    }

    public class VisitsData {
        public List<VisitWrapper> visits;
        public Map<String, Object> pagination;
    }

    public class VisitWrapper {
        public String id;
        public String status;
        public String status_label;
        public String scheduled_at;
        public String completed_at;
        public String cancelled_at;
        public String comments;
        public String unit_number;
        public String customer_id;
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