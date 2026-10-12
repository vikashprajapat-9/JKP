@RestResource(urlMapping='/api/v1/properties/construction-status-details')
global without sharing class API_ConstructionStatusDetails {

    private static final Set<String> IMAGE_EXTENSIONS = new Set<String>{'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'};
    private static final Set<String> VIDEO_EXTENSIONS = new Set<String>{'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'};

    @HttpGet
    global static void getConstructionStatusDetails() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ConstructionStatusDetailsResponse result = buildConstructionStatusDetailsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ConstructionStatusDetails.getConstructionStatusDetails ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ConstructionStatusDetails', 'getConstructionStatusDetails', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving construction status details', null)));
        }
    }

    private static ConstructionStatusDetailsResponse buildConstructionStatusDetailsResponse(RestRequest request) {
        try {
            String propertyId = request != null && request.params != null ? request.params.get('propertyId') : null;
            propertyId = propertyId != null ? propertyId.trim() : null;

            if (String.isBlank(propertyId)) {
                return createResponse(false, 400, 'propertyId is required', null);
            }

            return getConstructionStatusDetailsData(propertyId);
        } catch (Exception e) {
            System.debug('Error in API_ConstructionStatusDetails.buildConstructionStatusDetailsResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ConstructionStatusDetails', 'buildConstructionStatusDetailsResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving construction status details', null);
        }
    }

    private static ConstructionStatusDetailsResponse getConstructionStatusDetailsData(String propertyId) {
        List<Unit__c> matchedUnits = [SELECT Id, Unit_Name_Code__c, Floor__r.Block__r.Block_Code__c,Floor__r.Block__r.Project__r.Id,Floor__r.Block__r.Project__r.Name,Floor__r.Block__r.Project__r.Completion_Percentage__c FROM Unit__c WHERE Id = :propertyId WITH SYSTEM_MODE LIMIT 1];
        if (matchedUnits.isEmpty()) {
            return createResponse(false, 404, 'Property not found', null);
        }
        Unit__c unit = matchedUnits[0];
        Project__c project = unit.Floor__r != null && unit.Floor__r.Block__r != null ? unit.Floor__r.Block__r.Project__r : null;

        ConstructionStatusDetailsData detailsData = new ConstructionStatusDetailsData();
        detailsData.id                 = unit.Id;
        detailsData.propertyName       = project != null ? project.Name : null;
        detailsData.units              = getCustomerUnitsInProject(project, unit);
        detailsData.progressPercentage = project != null ? project.Completion_Percentage__c : null;
        detailsData.lastUpdated        = null;
        detailsData.updates            = new List<ConstructionUpdateWrapper>();

        if (project == null) {
            return createResponse(true, 200, 'Construction status details retrieved successfully', detailsData);
        }

        List<Project_Updates__c> projectUpdates = [SELECT Id, Name__c, CreatedDate FROM Project_Updates__c WHERE Project__c = :project.Id WITH SYSTEM_MODE ORDER BY CreatedDate DESC];
        if (projectUpdates.isEmpty()) {
            return createResponse(true, 200, 'Construction status details retrieved successfully', detailsData);
        }

        detailsData.lastUpdated = projectUpdates[0].CreatedDate;

        Set<Id> updateIds = new Set<Id>();
        for (Project_Updates__c projectUpdate : projectUpdates) {
            updateIds.add(projectUpdate.Id);
        }

        Map<Id, List<Sub_Document__c>> imageDocsByUpdateId = new Map<Id, List<Sub_Document__c>>();
        Map<Id, List<Sub_Document__c>> videoDocsByUpdateId = new Map<Id, List<Sub_Document__c>>();

        for (Sub_Document__c subDocument : [SELECT Id, Name, Project_Updates__c, File_Url__c FROM Sub_Document__c WHERE Project_Updates__c IN :updateIds WITH SYSTEM_MODE ORDER BY CreatedDate ASC]) {
            String extension = getFileExtension(subDocument.Name);
            if (IMAGE_EXTENSIONS.contains(extension)) {
                if (!imageDocsByUpdateId.containsKey(subDocument.Project_Updates__c)) {
                    imageDocsByUpdateId.put(subDocument.Project_Updates__c, new List<Sub_Document__c>());
                }
                imageDocsByUpdateId.get(subDocument.Project_Updates__c).add(subDocument);
            } else if (VIDEO_EXTENSIONS.contains(extension)) {
                if (!videoDocsByUpdateId.containsKey(subDocument.Project_Updates__c)) {
                    videoDocsByUpdateId.put(subDocument.Project_Updates__c, new List<Sub_Document__c>());
                }
                videoDocsByUpdateId.get(subDocument.Project_Updates__c).add(subDocument);
            }
        }

        for (Integer index = 0; index < projectUpdates.size(); index++) {
            Project_Updates__c projectUpdate = projectUpdates[index];
            List<Sub_Document__c> imageDocs = imageDocsByUpdateId.containsKey(projectUpdate.Id) ? imageDocsByUpdateId.get(projectUpdate.Id) : new List<Sub_Document__c>();
            List<Sub_Document__c> videoDocs = videoDocsByUpdateId.containsKey(projectUpdate.Id) ? videoDocsByUpdateId.get(projectUpdate.Id) : new List<Sub_Document__c>();

            ImagesWrapper images = new ImagesWrapper();
            images.totalCount    = imageDocs.size();
            images.previewImages = new List<ImageWrapper>();
            for (Sub_Document__c imageDoc : imageDocs) {
                ImageWrapper imageItem = new ImageWrapper();
                imageItem.id      = imageDoc.Id;
                imageItem.fullUrl = imageDoc.File_Url__c;
                images.previewImages.add(imageItem);
            }

            VideosWrapper videos = new VideosWrapper();
            videos.totalCount = videoDocs.size();
            videos.items      = new List<VideoWrapper>();
            for (Sub_Document__c videoDoc : videoDocs) {
                VideoWrapper videoItem = new VideoWrapper();
                videoItem.id       = videoDoc.Id;
                videoItem.videoUrl = videoDoc.File_Url__c;
                videos.items.add(videoItem);
            }

            ConstructionUpdateWrapper updateItem = new ConstructionUpdateWrapper();
            updateItem.id                = projectUpdate.Id;
            updateItem.title             = projectUpdate.Name__c;
            updateItem.isExpandedDefault = index == 0;
            updateItem.images            = images;
            updateItem.videos            = videos;
            detailsData.updates.add(updateItem);
        }

        return createResponse(true, 200, 'Construction status details retrieved successfully', detailsData);
    }

    private static List<String> getCustomerUnitsInProject(Project__c project, Unit__c requestedUnit) {
        Set<String> unitEntries = new Set<String>();

        Id accountId = getCustomerAccountId(UserInfo.getUserId());
        if (accountId != null && project != null) {
            for (Opportunity opportunity : [SELECT Id, Unit__c, Unit__r.Unit_Name_Code__c,Unit__r.Floor__r.Block__r.Block_Code__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null AND Unit__r.Floor__r.Block__r.Project__c = :project.Id WITH SYSTEM_MODE]) {
                String blockCode = opportunity.Unit__r.Floor__r != null && opportunity.Unit__r.Floor__r.Block__r != null ? opportunity.Unit__r.Floor__r.Block__r.Block_Code__c : null;
                String entry = buildUnitEntry(opportunity.Unit__r.Unit_Name_Code__c, blockCode);
                if (entry != null) {
                    unitEntries.add(entry);
                }
            }
        }

        if (unitEntries.isEmpty()) {
            String blockCode = requestedUnit.Floor__r != null && requestedUnit.Floor__r.Block__r != null ? requestedUnit.Floor__r.Block__r.Block_Code__c: null;
            String entry = buildUnitEntry(requestedUnit.Unit_Name_Code__c, blockCode);
            if (entry != null) {
                unitEntries.add(entry);
            }
        }

        List<String> sortedEntries = new List<String>(unitEntries);
        sortedEntries.sort();
        return sortedEntries;
    }

    private static String buildUnitEntry(String unitNameCode, String blockCode) {
        if (String.isBlank(unitNameCode)) {
            return null;
        }
        return String.isBlank(blockCode) ? unitNameCode.trim() : unitNameCode.trim() + ',' + blockCode.trim();
    }

    private static Id getCustomerAccountId(String userId) {
        if (String.isBlank(userId)) {
            return null;
        }
        List<User> users = [SELECT Id, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty() || users[0].Contact == null) {
            return null;
        }
        return users[0].Contact.AccountId;
    }

    private static String getFileExtension(String fileName) {
        if (String.isBlank(fileName) || !fileName.contains('.')) {
            return '';
        }
        List<String> nameParts = fileName.split('\\.');
        return nameParts[nameParts.size() - 1].trim().toLowerCase();
    }

    private static ConstructionStatusDetailsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ConstructionStatusDetailsData data) {
        ConstructionStatusDetailsResponse apiResponse = new ConstructionStatusDetailsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ConstructionStatusDetailsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ConstructionStatusDetailsData data;
    }

    public class ConstructionStatusDetailsData {
        public String id;
        public String propertyName;
        public List<String> units;
        public Decimal progressPercentage;
        public Datetime lastUpdated;
        public List<ConstructionUpdateWrapper> updates;
    }

    public class ConstructionUpdateWrapper {
        public String id;
        public String title;
        public Boolean isExpandedDefault;
        public ImagesWrapper images;
        public VideosWrapper videos;
    }

    public class ImagesWrapper {
        public Integer totalCount;
        public List<ImageWrapper> previewImages;
    }

    public class ImageWrapper {
        public String id;
        public String fullUrl;
    }

    public class VideosWrapper {
        public Integer totalCount;
        public List<VideoWrapper> items;
    }

    public class VideoWrapper {
        public String id;
        public String videoUrl;
    }
}