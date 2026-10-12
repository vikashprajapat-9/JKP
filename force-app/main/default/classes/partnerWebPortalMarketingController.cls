// Without sharing: partners have no record access to projects or their files (their sharing is Private), so the
// Active__c filters, PORTAL_FOLDERS and isPortalFile below are what decide what the portal shows. An executive sees
// only the projects their channel head gave them (PartnerPortalAccess).
public without sharing class partnerWebPortalMarketingController {

    // Same OneDrive account the project folders are created in (see CreateOneDriveFoldersQueueable)
    private static final String DRIVE_USER = 'isha.raj@utilitarianlabs.com';
    // Document folders (from the "Project" Document Master) that feed the Marketing screen
    private static final String IMAGES_FOLDER = 'Project Images';
    private static final String MARKETING_FOLDER = 'Marketing';
    private static final String DOCUMENTS_FOLDER = 'Project Documents';
    // Project folders whose files the portal may open (lower case)
    private static final Set<String> PORTAL_FOLDERS = new Set<String>{ 'marketing', 'project images', 'project documents' };
    private static final Set<String> IMAGE_TYPES = new Set<String>{ 'jpg', 'jpeg', 'png', 'gif', 'webp' };
    private static final Set<String> VIDEO_TYPES = new Set<String>{ 'mp4', 'mov', 'webm' };
    // Microsoft Graph accepts at most 20 requests per $batch call
    private static final Integer GRAPH_BATCH_LIMIT = 20;

    @TestVisible
    private static String accessToken;

    public class ProjectCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String location;
        @AuraEnabled public List<MediaFile> images = new List<MediaFile>();
    }

    public class MediaFile {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        // image | video | pdf | file
        @AuraEnabled public String fileType;
        // Shareable OneDrive link (opens the OneDrive viewer)
        @AuraEnabled public String previewUrl;
        // Short-lived direct link for <img>/<video>; blank if OneDrive could not be reached
        @AuraEnabled public String mediaUrl;
        @AuraEnabled public Datetime uploadedOn;
    }

    // Active projects (an executive's own only) with the images uploaded to each project's "Project Images" folder.
    @AuraEnabled
    public static List<ProjectCard> getMarketingProjects() {
        Map<String, Object> binds = new Map<String, Object>();
        String visible = PartnerPortalAccess.current().projects(binds);
        return cardsFor((List<Project__c>) Database.queryWithBinds(
            'SELECT Id, Name, Project_Location__c FROM Project__c WHERE Active__c = true AND ' + visible + ' ORDER BY Name LIMIT 50',
            binds, AccessLevel.SYSTEM_MODE
        ));
    }

    // The cards of the given projects (Id, Name, Project_Location__c), each with the photos of its "Project Images"
    // folder. No access check: the caller decides which projects its user may see (the Customer Portal shows every
    // active project, see CustomerPortalProjectController).
    public static List<ProjectCard> cardsFor(List<Project__c> projects) {
        List<ProjectCard> cards = new List<ProjectCard>();
        Map<Id, ProjectCard> cardByProject = new Map<Id, ProjectCard>();
        for (Project__c project : projects) {
            ProjectCard card = new ProjectCard();
            card.id = project.Id;
            card.name = project.Name;
            card.location = buildLocation(project.Project_Location__c);
            cards.add(card);
            cardByProject.put(project.Id, card);
        }
        if (cards.isEmpty()) {
            return cards;
        }

        List<Document__c> imageFolders = [
            SELECT Id, Project__c, Document_Id__c
            FROM Document__c
            WHERE Project__c IN :cardByProject.keySet() AND Name = :IMAGES_FOLDER
            WITH SYSTEM_MODE
        ];
        Map<Id, List<MediaFile>> filesByFolder = loadFiles(imageFolders);
        for (Document__c folder : imageFolders) {
            for (MediaFile file : filesByFolder.get(folder.Id)) {
                if (file.fileType == 'image') {
                    cardByProject.get(folder.Project__c).images.add(file);
                }
            }
        }
        return cards;
    }

    // Everything uploaded to an active project's "Marketing" folder (PDFs, images, videos, ...); nothing for a project
    // the partner may not see.
    @AuraEnabled
    public static List<MediaFile> getMarketingFiles(Id projectId) {
        if (!PartnerPortalAccess.current().canSeeProject(projectId)) {
            return new List<MediaFile>();
        }
        List<Document__c> marketingFolders = [
            SELECT Id, Project__c, Document_Id__c
            FROM Document__c
            WHERE Project__c = :projectId AND Name = :MARKETING_FOLDER AND Project__r.Active__c = true
            WITH SYSTEM_MODE
        ];
        Map<Id, List<MediaFile>> filesByFolder = loadFiles(marketingFolders);
        List<MediaFile> files = new List<MediaFile>();
        for (Document__c folder : marketingFolders) {
            files.addAll(filesByFolder.get(folder.Id));
        }
        return files;
    }

    // Short-lived embeddable preview (OneDrive viewer) for PDFs and other documents, shown inside the portal.
    // Only files the portal shows can be previewed (see isPortalFile).
    @AuraEnabled
    public static String getFilePreviewUrl(Id subDocumentId) {
        Sub_Document__c file = portalFile(subDocumentId);
        if (file == null || !PartnerPortalAccess.current().canSeeProject(projectOf(file))) {
            throw userError('This file cannot be previewed.');
        }
        return previewUrlOf(file);
    }

    // The file when it is one the portals show (see isPortalFile) and its folder exists in OneDrive, else null. No
    // access check: the caller decides whether its user may see the file's project.
    public static Sub_Document__c portalFile(Id subDocumentId) {
        List<Sub_Document__c> subs = [
            SELECT Id, Name, File_URL__c, Document__r.Name, Document__r.Document_Id__c, Document__r.Project__c, Document__r.Project__r.Active__c,
                Document__r.Project_Configuration__r.Sub_Document__c, Document__r.Project_Configuration__r.Project__c,
                Document__r.Project_Configuration__r.Project__r.Active__c
            FROM Sub_Document__c
            WHERE Id = :subDocumentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return subs.isEmpty() || subs[0].Document__r == null || String.isBlank(subs[0].Document__r.Document_Id__c) || !isPortalFile(subs[0])
            ? null : subs[0];
    }

    // Whether a file returned by portalFile is one the project page shows: a photo, a project document or a file of
    // a configuration. The Marketing folder is not; only the Partner Portal's Marketing page shows it.
    public static Boolean isProjectPageFile(Sub_Document__c file) {
        Document__c folder = file.Document__r;
        return folder.Project_Configuration__r != null || folder.Name.equalsIgnoreCase(IMAGES_FOLDER) || folder.Name.equalsIgnoreCase(DOCUMENTS_FOLDER);
    }

    // OneDrive's embeddable preview of a file returned by portalFile
    public static String previewUrlOf(Sub_Document__c file) {
        String items = 'https://graph.microsoft.com/v1.0/users/' + DRIVE_USER + '/drive/items/';

        // Find the file in OneDrive, then ask for an embeddable preview link
        String itemId = findItemInFolder(file, items);
        HttpRequest previewReq = graphRequest('POST', items + EncodingUtil.urlEncode(itemId, 'UTF-8') + '/preview');
        previewReq.setBody('{}');
        HttpResponse previewRes = new Http().send(previewReq);
        if (previewRes.getStatusCode() != 200) {
            throw userError('OneDrive could not create a preview (HTTP ' + previewRes.getStatusCode() + ').');
        }
        return (String) ((Map<String, Object>) JSON.deserializeUntyped(previewRes.getBody())).get('getUrl');
    }

    // The file's OneDrive item. Its share link finds that exact file even when OneDrive's name differs from the record's
    // (renamed, or longer than a record name holds); a file without a link is looked up by name. It must still be in
    // its folder.
    private static String findItemInFolder(Sub_Document__c sub, String items) {
        String folderId = sub.Document__r.Document_Id__c;
        String fields = '?$select=id,parentReference';
        HttpRequest findReq = OneDriveDocumentManagerController.isDriveUrl(sub.File_URL__c)
            ? graphRequest('GET', 'https://graph.microsoft.com/v1.0/shares/' + OneDriveDocumentManagerController.shareId(sub.File_URL__c) + '/driveItem' + fields)
            : graphRequest('GET', items + folderId + ':/' + EncodingUtil.urlEncode(sub.Name, 'UTF-8').replace('+', '%20') + fields);
        HttpResponse findRes = new Http().send(findReq);
        if (findRes.getStatusCode() != 200) {
            throw userError('The file could not be found in OneDrive (HTTP ' + findRes.getStatusCode() + ').');
        }
        Map<String, Object> item = (Map<String, Object>) JSON.deserializeUntyped(findRes.getBody());
        Map<String, Object> parentRef = (Map<String, Object>) item.get('parentReference');
        if (parentRef == null || !folderId.equals((String) parentRef.get('id'))) {
            throw userError('This file is no longer in its folder in OneDrive.');
        }
        return (String) item.get('id');
    }

    // Everything the portal's project page shows
    public class ProjectDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String location;
        // Project Status, shown as the badge on the photo
        @AuraEnabled public String status;
        @AuraEnabled public Date possession;
        @AuraEnabled public String landParcel;
        // Photos from the project's Project Images folder
        @AuraEnabled public List<MediaFile> images = new List<MediaFile>();
        @AuraEnabled public List<Amenity> amenities = new List<Amenity>();
        @AuraEnabled public List<ConfigurationCard> configurations = new List<ConfigurationCard>();
        // Every file in the project's Project Documents folder
        @AuraEnabled public List<MediaFile> documents = new List<MediaFile>();
    }

    public class ConfigurationCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String unitType;
        @AuraEnabled public Decimal squareFt;
        @AuraEnabled public Decimal startingPrice;
        // The latest file in the configuration's folder (its price sheet); null when the configuration has no file
        @AuraEnabled public MediaFile priceSheet;
    }

    // The project of a file: its folder's project, or its configuration's project
    private static Id projectOf(Sub_Document__c sub) {
        return sub.Document__r.Project__c != null ? sub.Document__r.Project__c
            : (sub.Document__r.Project_Configuration__r == null ? null : sub.Document__r.Project_Configuration__r.Project__c);
    }

    // The whole project page of an active project, read from Salesforce and OneDrive in one call; refused for a project
    // the partner may not see.
    @AuraEnabled
    public static ProjectDetail getProjectDetails(Id projectId) {
        if (!PartnerPortalAccess.current().canSeeProject(projectId)) {
            throw userError('This project is not available.');
        }
        return detailsOf(projectId);
    }

    // The page of an active project. No access check: the caller decides whether its user may see the project.
    public static ProjectDetail detailsOf(Id projectId) {
        List<Project__c> projects = [
            SELECT Id, Name, Project_Location__c, toLabel(Project_Status__c), Possession__c, Land_Parcel__c
            FROM Project__c
            WHERE Id = :projectId AND Active__c = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (projects.isEmpty()) {
            throw userError('This project is not available.');
        }
        Project__c project = projects[0];
        ProjectDetail detail = new ProjectDetail();
        detail.id = project.Id;
        detail.name = project.Name;
        detail.location = buildLocation(project.Project_Location__c);
        detail.status = project.Project_Status__c;
        detail.possession = project.Possession__c;
        detail.landParcel = project.Land_Parcel__c;
        detail.amenities = amenitiesOf(project.Id);

        // Configurations that have a file; one whose file was removed shows no price sheet
        Set<Id> withFile = new Set<Id>();
        for (Project_Configuration__c config : [
            SELECT Id, toLabel(Unit_Type__c), Square_FT__c, Starting_Price__c, Sub_Document__c
            FROM Project_Configuration__c
            WHERE Project__c = :project.Id
            WITH SYSTEM_MODE
            ORDER BY Unit_Type__c ASC NULLS LAST, Starting_Price__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 50
        ]) {
            ConfigurationCard card = new ConfigurationCard();
            card.id = config.Id;
            card.unitType = config.Unit_Type__c;
            card.squareFt = config.Square_FT__c;
            card.startingPrice = config.Starting_Price__c;
            detail.configurations.add(card);
            if (config.Sub_Document__c != null) {
                withFile.add(config.Id);
            }
        }

        // The photo and document folders plus each configuration's own folder; their direct links come in one batch
        Set<Id> configurationIds = new Set<Id>();
        for (ConfigurationCard card : detail.configurations) {
            configurationIds.add(card.id);
        }
        Set<String> projectFolders = new Set<String>{ IMAGES_FOLDER, DOCUMENTS_FOLDER };
        List<Document__c> folders = [
            SELECT Id, Name, Project__c, Project_Configuration__c, Document_Id__c
            FROM Document__c
            WHERE (Project__c = :project.Id AND Name IN :projectFolders) OR Project_Configuration__c IN :configurationIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
        Map<Id, List<MediaFile>> filesByFolder = loadFiles(folders);
        Map<Id, MediaFile> priceSheetByConfiguration = new Map<Id, MediaFile>();
        for (Document__c folder : folders) {
            List<MediaFile> files = filesByFolder.get(folder.Id);
            if (folder.Project_Configuration__c != null) {
                // Files come oldest first, so the last one is the latest upload
                if (withFile.contains(folder.Project_Configuration__c)) {
                    for (MediaFile file : files) {
                        MediaFile latest = priceSheetByConfiguration.get(folder.Project_Configuration__c);
                        if (latest == null || file.uploadedOn >= latest.uploadedOn) {
                            priceSheetByConfiguration.put(folder.Project_Configuration__c, file);
                        }
                    }
                }
            } else if (folder.Name.equalsIgnoreCase(IMAGES_FOLDER)) {
                for (MediaFile file : files) {
                    if (file.fileType == 'image') {
                        detail.images.add(file);
                    }
                }
            } else {
                detail.documents.addAll(files);
            }
        }

        for (ConfigurationCard card : detail.configurations) {
            card.priceSheet = priceSheetByConfiguration.get(card.id);
        }
        return detail;
    }

    // Files the portal shows: a project's Marketing, Project Images and Project Documents folders, and the folders of
    // its configurations that have a file (price sheets). Active projects only.
    private static Boolean isPortalFile(Sub_Document__c sub) {
        Document__c folder = sub.Document__r;
        if (folder.Project_Configuration__r != null) {
            return folder.Project_Configuration__r.Sub_Document__c != null
                && folder.Project_Configuration__r.Project__r != null && folder.Project_Configuration__r.Project__r.Active__c;
        }
        return folder.Project__r != null && folder.Project__r.Active__c && PORTAL_FOLDERS.contains(folder.Name.toLowerCase());
    }

    public class Amenity {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        // Icon name from Amenties__c.Icon__c (picked from the Type); the portal draws it with c/amenityIcons
        @AuraEnabled public String icon;
    }

    // The amenities of an active project for its Key Amenities section, in the order they were added. Amenities
    // without a Type are left out, since their name is only an auto number. None for a project the partner may not see.
    @AuraEnabled
    public static List<Amenity> getProjectAmenities(Id projectId) {
        return PartnerPortalAccess.current().canSeeProject(projectId) ? amenitiesOf(projectId) : new List<Amenity>();
    }

    private static List<Amenity> amenitiesOf(Id projectId) {
        List<Amenity> amenities = new List<Amenity>();
        for (Amenties__c record : [
            SELECT Id, toLabel(Type__c), Icon__c
            FROM Amenties__c
            WHERE Project__c = :projectId AND Project__r.Active__c = true AND Type__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate, Name
            LIMIT 50
        ]) {
            Amenity amenity = new Amenity();
            amenity.id = record.Id;
            amenity.label = record.Type__c;
            amenity.icon = record.Icon__c;
            amenities.add(amenity);
        }
        return amenities;
    }

    private static HttpRequest graphRequest(String method, String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(endpoint);
        req.setHeader('Authorization', 'Bearer ' + token());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        return req;
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    private static Map<Id, List<MediaFile>> loadFiles(List<Document__c> folders) {
        Map<Id, List<MediaFile>> filesByFolder = new Map<Id, List<MediaFile>>();
        for (Document__c folder : folders) {
            filesByFolder.put(folder.Id, new List<MediaFile>());
        }
        if (folders.isEmpty()) {
            return filesByFolder;
        }
        for (Sub_Document__c sub : [
            SELECT Id, Name, File_URL__c, CreatedDate, Document__c
            FROM Sub_Document__c
            WHERE Document__c IN :filesByFolder.keySet() AND File_URL__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            filesByFolder.get(sub.Document__c).add(toMediaFile(sub));
        }
        attachDirectLinks(folders, filesByFolder);
        return filesByFolder;
    }

    // Share links only serve the file after setting a cookie, which browsers block for images embedded in the
    // portal, so the direct (pre-authenticated) download URLs are read from the OneDrive folders in one $batch call.
    private static void attachDirectLinks(List<Document__c> folders, Map<Id, List<MediaFile>> filesByFolder) {
        List<Document__c> withFiles = new List<Document__c>();
        for (Document__c folder : folders) {
            if (String.isNotBlank(folder.Document_Id__c) && !filesByFolder.get(folder.Id).isEmpty()) {
                withFiles.add(folder);
            }
        }
        try {
            for (Integer start = 0; start < withFiles.size(); start += GRAPH_BATCH_LIMIT) {
                List<Document__c> chunk = new List<Document__c>();
                List<Object> requests = new List<Object>();
                for (Integer i = start; i < Math.min(start + GRAPH_BATCH_LIMIT, withFiles.size()); i++) {
                    chunk.add(withFiles[i]);
                    requests.add(new Map<String, Object>{
                        'id' => String.valueOf(chunk.size() - 1),
                        'method' => 'GET',
                        'url' => '/users/' + DRIVE_USER + '/drive/items/' + withFiles[i].Document_Id__c + '/children?$top=200'
                    });
                }

                HttpRequest req = new HttpRequest();
                req.setMethod('POST');
                req.setEndpoint('https://graph.microsoft.com/v1.0/$batch');
                req.setHeader('Authorization', 'Bearer ' + token());
                req.setHeader('Content-Type', 'application/json');
                req.setBody(JSON.serialize(new Map<String, Object>{ 'requests' => requests }));
                req.setTimeout(60000);
                HttpResponse res = new Http().send(req);
                if (res.getStatusCode() != 200) {
                    System.debug(LoggingLevel.WARN, 'OneDrive batch failed: HTTP ' + res.getStatusCode());
                    continue;
                }

                Map<String, Object> batch = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                for (Object entry : (List<Object>) batch.get('responses')) {
                    Map<String, Object> response = (Map<String, Object>) entry;
                    if ((Integer) response.get('status') != 200) {
                        continue;
                    }
                    Document__c folder = chunk[Integer.valueOf((String) response.get('id'))];
                    Map<String, String> downloadUrlByName = new Map<String, String>();
                    for (Object child : (List<Object>) ((Map<String, Object>) response.get('body')).get('value')) {
                        Map<String, Object> item = (Map<String, Object>) child;
                        String downloadUrl = (String) item.get('@microsoft.graph.downloadUrl');
                        if (downloadUrl != null) {
                            downloadUrlByName.put(((String) item.get('name')).toLowerCase(), downloadUrl);
                        }
                    }
                    for (MediaFile file : filesByFolder.get(folder.Id)) {
                        file.mediaUrl = downloadUrlByName.get(file.name.toLowerCase());
                    }
                }
            }
        } catch (Exception e) {
            // The files are still listed with their share links; only inline previews are skipped
            System.debug(LoggingLevel.WARN, 'OneDrive direct links unavailable: ' + e.getMessage());
        }
    }

    private static String token() {
        if (accessToken == null) {
            accessToken = new OneDriveService().getAccessToken();
        }
        return accessToken;
    }

    private static MediaFile toMediaFile(Sub_Document__c sub) {
        MediaFile file = new MediaFile();
        file.id = sub.Id;
        file.name = sub.Name;
        file.fileType = fileTypeOf(sub.Name);
        file.previewUrl = sub.File_URL__c;
        file.uploadedOn = sub.CreatedDate;
        return file;
    }

    private static String fileTypeOf(String fileName) {
        String ext = String.isBlank(fileName) ? '' : fileName.substringAfterLast('.').toLowerCase();
        if (IMAGE_TYPES.contains(ext)) return 'image';
        if (VIDEO_TYPES.contains(ext)) return 'video';
        if (ext == 'pdf') return 'pdf';
        return 'file';
    }

    private static String buildLocation(Address addr) {
        if (addr == null) {
            return '';
        }
        List<String> parts = new List<String>();
        for (String part : new List<String>{ addr.getStreet(), addr.getCity(), addr.getState(), addr.getPostalCode(), addr.getCountry() }) {
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return String.join(parts, ', ');
    }
}