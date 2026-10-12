@RestResource(urlMapping='/api/v1/documents/overview')
global without sharing class API_MyDocuments {

    @HttpGet
    global static void getDocumentsOverview() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String userId = UserInfo.getUserId();
            ResponseWrapper result = getCustomerDocumentsOverview(userId, request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_MyDocuments.getDocumentsOverview ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyDocuments', 'getDocumentsOverview', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'Failed to retrieve customer property documents', null)));
        }
    }

    private static ResponseWrapper getCustomerDocumentsOverview(String userId, RestRequest request) {
        try {
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'Unable to identify the authenticated user', null);
            }

            Map<String, String> requestParams = request != null && request.params != null ? request.params : new Map<String, String>();
            Integer offsetValue = requestParams.containsKey('offsetValue') && String.isNotBlank(requestParams.get('offsetValue')) ? Integer.valueOf(requestParams.get('offsetValue')) : 0;
            Integer limitValue = requestParams.containsKey('limitValue') && String.isNotBlank(requestParams.get('limitValue')) ? Integer.valueOf(requestParams.get('limitValue')) : 20;
            if (offsetValue == null || offsetValue < 0) {
                offsetValue = 0;
            }
            if (limitValue == null || limitValue <= 0) {
                limitValue = 20;
            }

            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];

            PropertiesDataWrapper propertiesData = new PropertiesDataWrapper();
            propertiesData.properties = new List<PropertyDocumentOverviewWrapper>();

            if (matchedUsers.isEmpty()) {
                return createResponse(false, 404, 'User not found', null);
            }

            Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
            if (accountId == null) {
                propertiesData.pagination = buildPagination(0, offsetValue, limitValue, 0);
                return createResponse(true, 200, 'Customer property documents retrieved successfully', propertiesData);
            }

            Integer totalCount = [SELECT COUNT() FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE];

            List<Opportunity> pagedOpportunities = [SELECT Id, Unit__c,Unit__r.Unit_Name_Code__c,Unit__r.Floor__r.Block__r.Project__r.Id,Unit__r.Floor__r.Block__r.Project__r.Name FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE ORDER BY createdDate LIMIT :limitValue OFFSET :offsetValue];

            propertiesData.pagination = buildPagination(totalCount, offsetValue, limitValue, pagedOpportunities.size());

            if (pagedOpportunities.isEmpty()) {
                return createResponse(true, 200, 'Customer property documents retrieved successfully', propertiesData);
            }

            Set<Id> pagedOpportunityIds = new Map<Id, Opportunity>(pagedOpportunities).keySet();
            Map<Id, Set<String>> documentNamesByOpportunityId = getDocumentNamesByOpportunityId(pagedOpportunityIds);

            Set<Id> processedUnitIds = new Set<Id>();
            for (Opportunity opportunity : pagedOpportunities) {
                if (processedUnitIds.contains(opportunity.Unit__c)) {
                    continue;
                }
                processedUnitIds.add(opportunity.Unit__c);

                Unit__c unit = opportunity.Unit__r;
                Project__c project = getProjectFromUnit(unit);
                Set<String> documentNames = documentNamesByOpportunityId.containsKey(opportunity.Id)? documentNamesByOpportunityId.get(opportunity.Id): new Set<String>();

                PropertyDocumentOverviewWrapper propertyItem = new PropertyDocumentOverviewWrapper();
                propertyItem.id           = unit.Unit_Name_Code__c;
                propertyItem.projectId    = project != null ? String.valueOf(project.Id) : null;
                propertyItem.propertyName = project != null ? project.Name : null;
                propertyItem.subtitle     = buildSubtitle(documentNames);
                propertiesData.properties.add(propertyItem);
            }

            return createResponse(true, 200, 'Customer property documents retrieved successfully', propertiesData);
        } catch (Exception e) {
            System.debug('Error in API_MyDocuments.getCustomerDocumentsOverview ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_MyDocuments', 'getCustomerDocumentsOverview', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'Failed to retrieve customer property documents', null);
        }
    }

    private static Map<String, Object> buildPagination(Integer totalCount, Integer offsetValue, Integer limitValue, Integer returnedCount) {
        return new Map<String, Object>{
            'totalCount'  => totalCount,
            'offsetValue' => offsetValue + limitValue,
            'limitValue'  => limitValue,
            'hasMore'     => (offsetValue + returnedCount) < totalCount
        };
    }

    private static Map<Id, Set<String>> getDocumentNamesByOpportunityId(Set<Id> opportunityIds) {
        Map<Id, Set<String>> namesByOpportunityId = new Map<Id, Set<String>>();
        if (opportunityIds.isEmpty()) {
            return namesByOpportunityId;
        }

        for (Document__c documentRecord : [SELECT Id, Opportunity__c, Name FROM Document__c WHERE Opportunity__c IN :opportunityIds WITH SYSTEM_MODE]) {
            if (documentRecord.Opportunity__c == null || String.isBlank(documentRecord.Name)) {
                continue;
            }
            if (!namesByOpportunityId.containsKey(documentRecord.Opportunity__c)) {
                namesByOpportunityId.put(documentRecord.Opportunity__c, new Set<String>());
            }
            namesByOpportunityId.get(documentRecord.Opportunity__c).add(documentRecord.Name);
        }
        return namesByOpportunityId;
    }

    private static String buildSubtitle(Set<String> documentNames) {
        if (documentNames == null || documentNames.isEmpty()) {
            return null;
        }
        List<String> sortedNames = new List<String>(documentNames);
        sortedNames.sort();
        return String.join(sortedNames, ', ');
    }

    private static Project__c getProjectFromUnit(Unit__c unit) {
        if (unit == null || unit.Floor__r == null || unit.Floor__r.Block__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__r;
    }

    private static ResponseWrapper createResponse(Boolean isSuccess, Integer httpStatusCode, String message, PropertiesDataWrapper data) {
        ResponseWrapper apiResponse = new ResponseWrapper();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ResponseWrapper {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public PropertiesDataWrapper data;
    }

    public class PropertiesDataWrapper {
        public List<PropertyDocumentOverviewWrapper> properties;
        public Map<String, Object> pagination;
    }

    public class PropertyDocumentOverviewWrapper {
        public String id;
        public String projectId;
        public String propertyName;
        public String subtitle;
    }
}