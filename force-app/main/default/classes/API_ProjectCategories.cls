@RestResource(urlMapping='/api/v1/project-categories/*')
global without sharing class API_ProjectCategories {

    @HttpGet
    global static void getProjectCategories() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ResponseWrapper result = buildProjectCategoriesResponse();
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ProjectCategories.getProjectCategories ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProjectCategories', 'getProjectCategories', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving project categories', null)));
        }
    }

    private static ResponseWrapper buildProjectCategoriesResponse() {
        try {
            Integer currentProjectCount  = [SELECT COUNT() FROM Project__c WHERE Project_Status__c != 'upcoming' and Project_Status__c != null WITH SYSTEM_MODE];
            Integer upcomingProjectCount = [SELECT COUNT() FROM Project__c WHERE Project_Status__c = 'upcoming' WITH SYSTEM_MODE];

            Map<String, String> imageUrlByCategory = getCategoryImageUrls();

            Map<String, Object> currentCategory = new Map<String, Object>{
                'title'        => 'Current Projects',
                'imageUrl'     => imageUrlByCategory.get('current'),
                'projectCount' => currentProjectCount,
                'sortOrder'    => 1
            };

            Map<String, Object> upcomingCategory = new Map<String, Object>{
                'title'        => 'Upcoming Projects',
                'imageUrl'     => imageUrlByCategory.get('upcoming'),
                'projectCount' => upcomingProjectCount,
                'sortOrder'    => 2
            };

            DataWrapper data = new DataWrapper();
            data.categories = new List<Map<String, Object>>{ currentCategory, upcomingCategory };

            return createResponse(true, 200, 'Project categories retrieved successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_ProjectCategories.buildProjectCategoriesResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProjectCategories', 'buildProjectCategoriesResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving project categories', null);
        }
    }

    private static Map<String, String> getCategoryImageUrls() {
        Map<String, String> imageUrlByCategory = new Map<String, String>();

        for (Sub_Document__c subDocument : [SELECT Id, File_Url__c, Document__r.Project__r.Project_Status__c FROM Sub_Document__c WHERE Document__r.Name = 'Project Images' AND File_Url__c != null AND Document__r.Project__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
            String projectStatus = subDocument.Document__r.Project__r.Project_Status__c;
            String category = (projectStatus == 'upcoming') ? 'upcoming' : 'current';

            if (!imageUrlByCategory.containsKey(category)) {
                // Direct file link, so the app can show the picture itself (the sharing link opens a SharePoint page)
                imageUrlByCategory.put(category, SharePointService.directUrl(subDocument.File_Url__c));
            }

            if (imageUrlByCategory.containsKey('current') && imageUrlByCategory.containsKey('upcoming')) {
                break;
            }
        }
        return imageUrlByCategory;
    }

    private static ResponseWrapper createResponse(Boolean isSuccess, Integer httpStatusCode, String message, DataWrapper data) {
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
        public DataWrapper data;
    }

    public class DataWrapper {
        public List<Map<String, Object>> categories;
    }
}