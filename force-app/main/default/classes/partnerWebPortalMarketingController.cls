// Without sharing: partners have no record access to projects or their files (their sharing is Private), so the
// Active__c filters and the folders named below are what decide what the portal shows. An executive sees only the
// projects their channel head gave them (PartnerPortalAccess). Every file comes with its Sub Document link and that
// link's direct form (SharePointService.directUrl), read from the record: showing a file never calls SharePoint.
public without sharing class partnerWebPortalMarketingController {

    // Document folders (from the "Project" Document Master) that feed the Marketing screen
    private static final String IMAGES_FOLDER = 'Project Images';
    private static final String MARKETING_FOLDER = 'Marketing';
    private static final String DOCUMENTS_FOLDER = 'Project Documents';
    private static final Set<String> IMAGE_TYPES = new Set<String>{ 'jpg', 'jpeg', 'png', 'gif', 'webp' };
    private static final Set<String> VIDEO_TYPES = new Set<String>{ 'mp4', 'mov', 'webm' };

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
        // The Sub Document link, as saved: opened in a new tab, a SharePoint link shows the file in SharePoint's viewer
        @AuraEnabled public String previewUrl;
        // The file itself, for every file: the link's direct form (SharePointService.directUrl), which <img> and <video>
        // show and which saves a document, as SharePoint sends it as a download. A web link stays as it is.
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
    // active project, see CustomerPortalController).
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
            SELECT Id, Project__c
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
            SELECT Id, Project__c
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

    // The whole project page of an active project in one call, read from Salesforce alone (the files' links are on their
    // Sub Documents); refused for a project the partner may not see.
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

        // The photo and document folders plus each configuration's own folder
        Set<Id> configurationIds = new Set<Id>();
        for (ConfigurationCard card : detail.configurations) {
            configurationIds.add(card.id);
        }
        Set<String> projectFolders = new Set<String>{ IMAGES_FOLDER, DOCUMENTS_FOLDER };
        List<Document__c> folders = [
            SELECT Id, Name, Project__c, Project_Configuration__c
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
        return filesByFolder;
    }

    // A file with both of its links, read from the record alone: SharePoint is not called
    private static MediaFile toMediaFile(Sub_Document__c sub) {
        MediaFile file = new MediaFile();
        file.id = sub.Id;
        file.name = sub.Name;
        file.fileType = fileTypeOf(sub.Name);
        file.previewUrl = sub.File_URL__c;
        file.mediaUrl = SharePointService.directUrl(sub.File_URL__c);
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