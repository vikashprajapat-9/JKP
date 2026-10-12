@RestResource(urlMapping='/api/v1/properties/documents')
global without sharing class API_DocumentDetails {

    private static final String CATEGORY_MY_DOCUMENTS       = 'my_documents';
    private static final String CATEGORY_PROPERTY_DOCUMENTS = 'property_documents';
    private static final String CATEGORY_HOME_LOAN          = 'home_loan';

    private static final List<String> CATEGORY_ORDER = new List<String>{
        CATEGORY_MY_DOCUMENTS,
        CATEGORY_PROPERTY_DOCUMENTS,
        CATEGORY_HOME_LOAN
    };

    private static final Boolean HIDE_UNAUTHORIZED_AS_NOT_FOUND = false;

    @HttpGet
    global static void getPropertyDocuments() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            String propertyId = getPropertyIdParam();

            String userId = UserInfo.getUserId();

            ResponseWrapper result = buildPropertyDocuments(userId, propertyId);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_DocumentDetails.getPropertyDocuments ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_DocumentDetails', 'getPropertyDocuments', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(500, false, 'Failed to retrieve property documents', null)));
        }
    }

    @TestVisible
    private static String getPropertyIdParam() {
        String raw = RestContext.request.params.get('propertyId');
        return String.isBlank(raw) ? null : raw.trim();
    }

    private static ResponseWrapper buildPropertyDocuments(String userId, String propertyId) {
        if (String.isBlank(userId)) {
            return createResponse(400, false, 'Unable to identify the authenticated user', null);
        }
        if (String.isBlank(propertyId)) {
            return createResponse(400, false, 'propertyId is required', null);
        }

        Id accountId = getCustomerAccountId(userId);
        if (accountId == null) {
            return propertyNotAccessible(propertyId);
        }

        List<Opportunity> customerOpportunities = [SELECT Id, Unit__c, Unit__r.Unit_Name_Code__c,Unit__r.Floor__r.Block__r.Project__r.Name FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null AND Unit__r.Unit_Name_Code__c = :propertyId WITH SYSTEM_MODE];
        if (customerOpportunities.isEmpty()) {
            return propertyNotAccessible(propertyId);
        }

        Opportunity firstOpportunity = customerOpportunities[0];
        Id unitId = firstOpportunity.Unit__c;

        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity opp : customerOpportunities) {
            if (opp.Unit__c == unitId) {
                opportunityIds.add(opp.Id);
            }
        }

        PropertyDocumentsDataWrapper data = new PropertyDocumentsDataWrapper();
        data.propertyId   = firstOpportunity.Unit__r.Unit_Name_Code__c;
        data.propertyName = getProjectName(firstOpportunity.Unit__r);
        data.categories   = new List<DocumentCategoryWrapper>();

        Map<Id, Document__c> documentById = new Map<Id, Document__c>([SELECT Id, Name, Opportunity__c FROM Document__c WHERE Opportunity__c IN :opportunityIds WITH SYSTEM_MODE ]);
        if (!documentById.isEmpty()) {
            data.categories = buildCategories(documentById);
        }

        return createResponse(200, true, 'Property documents details retrieved successfully', data);
    }

    private static Id getCustomerAccountId(String userId) {
        List<User> users = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty() || users[0].Contact == null) {
            return null;
        }
        return users[0].Contact.AccountId;
    }

    private static String getProjectName(Unit__c unit) {
        if (unit == null || unit.Floor__r == null || unit.Floor__r.Block__r == null|| unit.Floor__r.Block__r.Project__r == null) {
            return null;
        }
        return unit.Floor__r.Block__r.Project__r.Name;
    }

    private static List<DocumentCategoryWrapper> buildCategories(Map<Id, Document__c> documentById) {
        Map<String, List<DocumentWrapper>> documentsByCategory = new Map<String, List<DocumentWrapper>>();

        Set<Id> documentIds = documentById.keySet();
        List<Sub_Document__c> subDocuments = [SELECT Id, Name, File_URL__c, Document__c FROM Sub_Document__c WHERE Document__c IN :documentIds WITH SYSTEM_MODE ORDER BY Name ASC, Id ASC ];

        for (Sub_Document__c subDocument : subDocuments) {
            Document__c parentDocument = documentById.get(subDocument.Document__c);
            if (parentDocument == null) {
                continue;
            }

            String categoryKey = resolveCategoryKey(parentDocument);
            if (categoryKey == null) {
                continue;
            }

            if (!documentsByCategory.containsKey(categoryKey)) {
                documentsByCategory.put(categoryKey, new List<DocumentWrapper>());
            }
            documentsByCategory.get(categoryKey).add(toDocumentWrapper(subDocument));
        }

        List<DocumentCategoryWrapper> categories = new List<DocumentCategoryWrapper>();
        for (String categoryKey : CATEGORY_ORDER) {
            List<DocumentWrapper> documents = documentsByCategory.get(categoryKey);
            if (documents == null || documents.isEmpty()) {
                continue;
            }
            DocumentCategoryWrapper category = new DocumentCategoryWrapper();
            category.key       = categoryKey;
            category.documents = documents;
            categories.add(category);
        }
        return categories;
    }

    @TestVisible
    private static String resolveCategoryKey(Document__c documentRecord) {
        if (documentRecord == null || String.isBlank(documentRecord.Name)) {
            return null;
        }
        String name = documentRecord.Name.trim().toLowerCase();
        if (name == 'my documents') {
            return CATEGORY_MY_DOCUMENTS;
        }
        if (name == 'property documents') {
            return CATEGORY_PROPERTY_DOCUMENTS;
        }
        if (name == 'home loans') {
            return CATEGORY_HOME_LOAN;
        }
        return null;
    }

    private static DocumentWrapper toDocumentWrapper(Sub_Document__c subDocument) {
        DocumentWrapper wrapper = new DocumentWrapper();
        wrapper.id       = String.valueOf(subDocument.Id);
        wrapper.fileName = subDocument.Name;
        wrapper.title    = removeExtension(subDocument.Name);
        wrapper.fileType = extractExtension(subDocument.Name);
        wrapper.fileUrl  = subDocument.File_URL__c;
        return wrapper;
    }

    @TestVisible
    private static String extractExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return '';
        }
        String trimmed = fileName.trim();
        Integer lastDot = trimmed.lastIndexOf('.');
        if (lastDot <= 0 || lastDot == trimmed.length() - 1) {
            return '';
        }
        return trimmed.substring(lastDot + 1).toLowerCase();
    }

    @TestVisible
    private static String removeExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return '';
        }
        String trimmed = fileName.trim();
        Integer lastDot = trimmed.lastIndexOf('.');
        if (lastDot <= 0) {
            return trimmed;
        }
        return trimmed.substring(0, lastDot);
    }

    private static ResponseWrapper propertyNotAccessible(String propertyId) {
        if (HIDE_UNAUTHORIZED_AS_NOT_FOUND) {
            return createResponse(404, false, 'Property not found', null);
        }
        Boolean unitExists = ![SELECT Id FROM Unit__c WHERE Unit_Name_Code__c = :propertyId LIMIT 1].isEmpty();
        return unitExists? createResponse(403, false, 'You do not have access to this property', null): createResponse(404, false, 'Property not found', null);
    }

    private static ResponseWrapper createResponse(Integer statusCode, Boolean success, String message, PropertyDocumentsDataWrapper data) {
        ResponseWrapper response = new ResponseWrapper();
        response.statusCode = statusCode;
        response.success    = success;
        response.message    = message;
        response.data       = data;
        return response;
    }

    public class ResponseWrapper {
        public Integer statusCode;
        public Boolean success;
        public String message;
        public PropertyDocumentsDataWrapper data;
    }

    public class PropertyDocumentsDataWrapper {
        public String propertyId;
        public String propertyName;
        public List<DocumentCategoryWrapper> categories;
    }

    public class DocumentCategoryWrapper {
        public String key;
        public List<DocumentWrapper> documents;
    }

    public class DocumentWrapper {
        public String id;
        public String title;
        public String fileName;
        public String fileType;
        public String fileUrl;
    }
}