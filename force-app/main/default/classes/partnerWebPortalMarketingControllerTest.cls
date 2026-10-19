// The portal's Marketing and project pages (partnerWebPortalMarketingController). Each file comes with its Sub Document
// link (previewUrl) and that link's direct form (mediaUrl), read from the record: no test needs SharePoint, because
// showing a file never calls it.
@isTest
private class partnerWebPortalMarketingControllerTest {

    private static final String SHARE_LINK = 'https://keells.sharepoint.com/:i:/s/JKPConnectDataHub/abc';
    // The direct form of SHARE_LINK (SharePointService.directUrl): the file itself, for <img>, <video> and downloads
    private static final String DIRECT_LINK = 'https://keells.sharepoint.com/sites/JKPConnectDataHub/_layouts/15/download.aspx?share=abc';

    @testSetup
    static void setup() {
        Project__c active = TestRecordDefaults.project('Victoria Golf Resort', true);
        Project__c inactive = TestRecordDefaults.project('Old Tower', false);
        insert new List<Project__c>{ active, inactive };

        Document__c images = new Document__c(Name = 'Project Images', Project__c = active.Id, Document_Id__c = 'IMAGES-FOLDER');
        Document__c marketing = new Document__c(Name = 'Marketing', Project__c = active.Id, Document_Id__c = 'MARKETING-FOLDER');
        Document__c legal = new Document__c(Name = 'Legal', Project__c = active.Id, Document_Id__c = 'LEGAL-FOLDER');
        insert new List<Document__c>{ images, marketing, legal };

        insert new List<Sub_Document__c>{
            new Sub_Document__c(Name = 'A1.JPG', Document__c = images.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'brochure.pdf', Document__c = images.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'brochure.pdf', Document__c = marketing.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'walkthrough.mp4', Document__c = marketing.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'contract.pdf', Document__c = legal.Id, File_URL__c = SHARE_LINK)
        };
    }

    private static Id projectId(String name) {
        return [SELECT Id FROM Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    @isTest
    static void projectCardsShowOnlyImagesFromTheProjectImagesFolder() {
        Test.startTest();
        List<partnerWebPortalMarketingController.ProjectCard> cards = partnerWebPortalMarketingController.getMarketingProjects();
        Integer callouts = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(0, callouts, 'The links come from the Sub Documents: SharePoint is not called');
        System.assertEquals(1, cards.size(), 'Only active projects are listed');
        System.assertEquals('Victoria Golf Resort', cards[0].name);
        System.assertEquals(1, cards[0].images.size(), 'PDFs in Project Images and files in other folders are not card images');
        System.assertEquals('A1.JPG', cards[0].images[0].name);
        System.assertEquals('image', cards[0].images[0].fileType);
        System.assertEquals(SHARE_LINK, cards[0].images[0].previewUrl);
        System.assertEquals(DIRECT_LINK, cards[0].images[0].mediaUrl, 'The photo is shown from the direct form of its link');
    }

    @isTest
    static void marketingFolderReturnsEveryFileWithItsType() {
        // A Sub Document without a link has nothing to show
        insert new Sub_Document__c(Name = 'no-link.pdf', Document__c = [SELECT Id FROM Document__c WHERE Document_Id__c = 'MARKETING-FOLDER' WITH SYSTEM_MODE].Id);

        Test.startTest();
        List<partnerWebPortalMarketingController.MediaFile> files = partnerWebPortalMarketingController.getMarketingFiles(projectId('Victoria Golf Resort'));
        Integer callouts = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(0, callouts, 'SharePoint is not called');
        System.assertEquals(2, files.size(), 'Only the Marketing folder is read, and only files with a link');
        Map<String, partnerWebPortalMarketingController.MediaFile> byName = new Map<String, partnerWebPortalMarketingController.MediaFile>();
        for (partnerWebPortalMarketingController.MediaFile file : files) {
            byName.put(file.name, file);
        }
        System.assertEquals('pdf', byName.get('brochure.pdf').fileType);
        System.assertEquals('video', byName.get('walkthrough.mp4').fileType);
        System.assertEquals(DIRECT_LINK, byName.get('walkthrough.mp4').mediaUrl, 'A video plays from the direct form of its link');
        System.assertEquals(DIRECT_LINK, byName.get('brochure.pdf').mediaUrl, 'A document downloads from it');
        System.assertEquals(SHARE_LINK, byName.get('brochure.pdf').previewUrl, 'and opens in SharePoint from its own link');
    }

    // A file saved with an ordinary web address, not a SharePoint sharing link, is shown from that address
    @isTest
    static void aWebLinkIsShownAsItIs() {
        String webImage = 'https://images.unsplash.com/photo-1?w=900';
        insert new Sub_Document__c(Name = 'skyline.png', File_URL__c = webImage,
            Document__c = [SELECT Id FROM Document__c WHERE Document_Id__c = 'IMAGES-FOLDER' WITH SYSTEM_MODE].Id);

        Test.startTest();
        List<partnerWebPortalMarketingController.ProjectCard> cards = partnerWebPortalMarketingController.getMarketingProjects();
        Test.stopTest();

        Map<String, partnerWebPortalMarketingController.MediaFile> byName = new Map<String, partnerWebPortalMarketingController.MediaFile>();
        for (partnerWebPortalMarketingController.MediaFile file : cards[0].images) {
            byName.put(file.name, file);
        }
        System.assertEquals(2, byName.size());
        System.assertEquals(webImage, byName.get('skyline.png').mediaUrl, 'A web image is shown from its own address');
        System.assertEquals(webImage, byName.get('skyline.png').previewUrl);
        System.assertEquals(DIRECT_LINK, byName.get('A1.JPG').mediaUrl);
    }

    private static Id subDocumentId(String name, String folder) {
        return [SELECT Id FROM Sub_Document__c WHERE Name = :name AND Document__r.Name = :folder WITH SYSTEM_MODE LIMIT 1].Id;
    }

    @isTest
    static void inactiveProjectsShowNoMarketingFiles() {
        Document__c oldMarketing = new Document__c(Name = 'Marketing', Project__c = projectId('Old Tower'), Document_Id__c = 'OLD-MARKETING');
        Document__c noProject = new Document__c(Name = 'Marketing', Document_Id__c = 'ORPHAN-MARKETING');
        insert new List<Document__c>{ oldMarketing, noProject };
        insert new List<Sub_Document__c>{
            new Sub_Document__c(Name = 'old-brochure.pdf', Document__c = oldMarketing.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'brochure.pdf', Document__c = noProject.Id, File_URL__c = SHARE_LINK)
        };

        Test.startTest();
        List<partnerWebPortalMarketingController.MediaFile> ofInactive = partnerWebPortalMarketingController.getMarketingFiles(projectId('Old Tower'));
        List<partnerWebPortalMarketingController.MediaFile> ofNoProject = partnerWebPortalMarketingController.getMarketingFiles(null);
        Test.stopTest();

        System.assertEquals(0, ofInactive.size(), 'A project taken off the portal shows nothing');
        System.assertEquals(0, ofNoProject.size(), 'Neither does a folder without a project');
    }

    @isTest
    static void projectsWithoutFoldersReturnEmptyLists() {
        Test.startTest();
        List<partnerWebPortalMarketingController.MediaFile> files = partnerWebPortalMarketingController.getMarketingFiles(projectId('Old Tower'));
        Test.stopTest();

        System.assertEquals(0, files.size());
    }

    @isTest
    static void listsTheAmenitiesOfAnActiveProjectWithTheirIcons() {
        Id active = projectId('Victoria Golf Resort');
        Id inactive = projectId('Old Tower');
        insert new List<Amenties__c>{
            new Amenties__c(Project__c = active, Type__c = 'Swimming Pool'),
            new Amenties__c(Project__c = active, Type__c = 'Sky Gym'),
            // No Type: its name is only an auto number, so it is not shown
            new Amenties__c(Project__c = active),
            new Amenties__c(Project__c = inactive, Type__c = 'BBQ Area')
        };

        Test.startTest();
        List<partnerWebPortalMarketingController.Amenity> amenities = partnerWebPortalMarketingController.getProjectAmenities(active);
        List<partnerWebPortalMarketingController.Amenity> ofInactive = partnerWebPortalMarketingController.getProjectAmenities(inactive);
        List<partnerWebPortalMarketingController.Amenity> none = partnerWebPortalMarketingController.getProjectAmenities(null);
        Test.stopTest();

        System.assertEquals(2, amenities.size(), 'Amenities without a Type are left out');
        Map<String, String> iconByLabel = new Map<String, String>();
        for (partnerWebPortalMarketingController.Amenity amenity : amenities) {
            iconByLabel.put(amenity.label, amenity.icon);
        }
        System.assertEquals('waves', iconByLabel.get('Swimming Pool'), 'The icon comes from the Icon formula');
        System.assertEquals('dumbbell', iconByLabel.get('Sky Gym'));
        System.assertEquals(0, ofInactive.size(), 'Inactive projects show nothing');
        System.assertEquals(0, none.size());
    }

    // The page and every file link on it come from Salesforce alone: photos are shown from the direct form of their
    // link, documents and price sheets open in SharePoint from their own link and download from the direct form
    @isTest
    static void buildsTheWholeProjectPageFromSalesforceAlone() {
        Project__c project = [SELECT Id FROM Project__c WHERE Name = 'Victoria Golf Resort' WITH SYSTEM_MODE];
        project.Project_Status__c = 'In Progress';
        project.Possession__c = Date.newInstance(2026, 7, 1);
        project.Land_Parcel__c = '4.5 Acres';
        update project;

        Document__c documents = new Document__c(Name = 'Project Documents', Project__c = project.Id, Document_Id__c = 'DOCUMENTS-FOLDER');
        insert documents;
        insert new Sub_Document__c(Name = 'site-plan.pdf', Document__c = documents.Id, File_URL__c = SHARE_LINK);

        Project_Configuration__c threeBr = new Project_Configuration__c(Project__c = project.Id, Unit_Type__c = '3 BR', Starting_Price__c = 16400000, Square_FT__c = 1560);
        Project_Configuration__c twoBr = new Project_Configuration__c(Project__c = project.Id, Unit_Type__c = '2 BR', Starting_Price__c = 9800000, Square_FT__c = 1100);
        insert new List<Project_Configuration__c>{ threeBr, twoBr };
        Document__c threeBrFolder = new Document__c(Name = 'PC-3BR', Project_Configuration__c = threeBr.Id, Document_Id__c = 'CONFIG-FOLDER');
        Document__c twoBrFolder = new Document__c(Name = 'PC-2BR', Project_Configuration__c = twoBr.Id, Document_Id__c = 'CONFIG-FOLDER-2');
        insert new List<Document__c>{ threeBrFolder, twoBrFolder };
        Sub_Document__c older = new Sub_Document__c(Name = 'price-sheet-v1.pdf', Document__c = threeBrFolder.Id, File_URL__c = SHARE_LINK);
        Sub_Document__c newer = new Sub_Document__c(Name = 'price-sheet-v2.pdf', Document__c = threeBrFolder.Id,
            File_URL__c = 'https://keells.sharepoint.com/:b:/s/JKPConnectDataHub/sheet2?e=Xy1');
        // The 2 BR's file was removed from it in Salesforce; the file stays in its folder
        Sub_Document__c removed = new Sub_Document__c(Name = 'old-2br-prices.pdf', Document__c = twoBrFolder.Id, File_URL__c = SHARE_LINK);
        insert new List<Sub_Document__c>{ older, newer, removed };
        Test.setCreatedDate(older.Id, System.now().addDays(-2));
        // The 3 BR still points at its first sheet; the newer upload in its folder is what the portal shows
        threeBr.Sub_Document__c = older.Id;
        update threeBr;
        insert new Amenties__c(Project__c = project.Id, Type__c = 'Swimming Pool');

        Test.startTest();
        partnerWebPortalMarketingController.ProjectDetail detail = partnerWebPortalMarketingController.getProjectDetails(project.Id);
        Integer callouts = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(0, callouts, 'SharePoint is not called');
        System.assertEquals('Victoria Golf Resort', detail.name);
        System.assertEquals('In Progress', detail.status);
        System.assertEquals(Date.newInstance(2026, 7, 1), detail.possession);
        System.assertEquals('4.5 Acres', detail.landParcel);
        System.assertEquals(1, detail.images.size(), 'Only photos from the Project Images folder');
        System.assertEquals('A1.JPG', detail.images[0].name);
        System.assertEquals(DIRECT_LINK, detail.images[0].mediaUrl, 'The slideshow shows the photo from the direct form of its link');
        System.assertEquals(1, detail.amenities.size());
        System.assertEquals('waves', detail.amenities[0].icon);
        System.assertEquals(2, detail.configurations.size());
        System.assertEquals('2 BR', detail.configurations[0].unitType, 'In unit type order');
        System.assertEquals(null, detail.configurations[0].priceSheet, 'A configuration without a file shows none, even with files left in its folder');
        System.assertEquals(16400000, detail.configurations[1].startingPrice);
        System.assertEquals(1560, detail.configurations[1].squareFt);
        System.assertEquals('price-sheet-v2.pdf', detail.configurations[1].priceSheet.name, 'The latest upload is the price sheet');
        System.assertEquals('https://keells.sharepoint.com/:b:/s/JKPConnectDataHub/sheet2?e=Xy1', detail.configurations[1].priceSheet.previewUrl);
        System.assertEquals('https://keells.sharepoint.com/sites/JKPConnectDataHub/_layouts/15/download.aspx?share=sheet2',
            detail.configurations[1].priceSheet.mediaUrl, 'Each file gets the direct form of its own link');
        System.assertEquals(1, detail.documents.size(), 'Only files from the Project Documents folder, not those of configurations');
        System.assertEquals('site-plan.pdf', detail.documents[0].name);
        System.assertEquals(SHARE_LINK, detail.documents[0].previewUrl, 'A document opens in SharePoint from its own link');
        System.assertEquals(DIRECT_LINK, detail.documents[0].mediaUrl, 'and downloads from the direct form');
    }

    @isTest
    static void onlyFilesInTheConfigurationsOwnFolderArePriceSheets() {
        Id active = projectId('Victoria Golf Resort');
        // Linked by hand to a file from another folder; its own folder is empty
        insert new Project_Configuration__c(Project__c = active, Unit_Type__c = '4 BR', Sub_Document__c = subDocumentId('contract.pdf', 'Legal'));

        Test.startTest();
        partnerWebPortalMarketingController.ProjectDetail detail = partnerWebPortalMarketingController.getProjectDetails(active);
        Test.stopTest();

        System.assertEquals(1, detail.configurations.size());
        System.assertEquals(null, detail.configurations[0].priceSheet, 'A Legal file never reaches the portal as a price sheet');
    }

    @isTest
    static void refusesProjectsThatAreNotActive() {
        String message;

        Test.startTest();
        try {
            partnerWebPortalMarketingController.getProjectDetails(projectId('Old Tower'));
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(message != null && message.contains('not available'), message);
    }

    @isTest
    static void partnersSeeThePortalWithoutRecordAccessToTheProjects() {
        Id active = projectId('Victoria Golf Resort');
        Project_Configuration__c config = new Project_Configuration__c(Project__c = active, Unit_Type__c = '3 BR', Starting_Price__c = 16400000);
        insert config;
        Document__c configFolder = new Document__c(Name = 'PC-3BR', Project_Configuration__c = config.Id, Document_Id__c = 'CONFIG-FOLDER');
        insert configFolder;
        Sub_Document__c priceSheet = new Sub_Document__c(Name = 'price-sheet.pdf', Document__c = configFolder.Id, File_URL__c = SHARE_LINK);
        insert priceSheet;
        config.Sub_Document__c = priceSheet.Id;
        update config;
        insert new Amenties__c(Project__c = active, Type__c = 'Sky Gym');
        User partner = PartnerPortalTestUser.create();
        List<partnerWebPortalMarketingController.ProjectCard> cards;
        List<partnerWebPortalMarketingController.MediaFile> marketing;
        partnerWebPortalMarketingController.ProjectDetail detail;
        Integer callouts;

        Test.startTest();
        System.runAs(partner) {
            cards = partnerWebPortalMarketingController.getMarketingProjects();
            marketing = partnerWebPortalMarketingController.getMarketingFiles(active);
            detail = partnerWebPortalMarketingController.getProjectDetails(active);
            callouts = Limits.getCallouts();
        }
        Test.stopTest();

        System.assertEquals(0, callouts, 'SharePoint is not called for a partner either');
        System.assertEquals(1, cards.size(), 'The active project is listed for partners');
        System.assertEquals(1, cards[0].images.size());
        System.assertEquals(DIRECT_LINK, cards[0].images[0].mediaUrl);
        System.assertEquals(2, marketing.size());
        System.assertEquals('Victoria Golf Resort', detail.name);
        System.assertEquals(1, detail.amenities.size());
        System.assertEquals('price-sheet.pdf', detail.configurations[0].priceSheet.name);
        System.assertEquals(SHARE_LINK, detail.configurations[0].priceSheet.previewUrl);
        System.assertEquals(DIRECT_LINK, detail.configurations[0].priceSheet.mediaUrl);
    }

    // An executive sees only the projects their channel head gave them: the others' pages and files are refused
    @isTest
    static void anExecutiveSeesOnlyTheProjectsTheirChannelHeadGaveThem() {
        Project__c viman = TestRecordDefaults.project('Viman Ja-Ela', true);
        insert viman;
        Document__c vimanMarketing = new Document__c(Name = 'Marketing', Project__c = viman.Id, Document_Id__c = 'VIMAN-MARKETING');
        insert vimanMarketing;
        Sub_Document__c vimanFile = new Sub_Document__c(Name = 'viman.pdf', Document__c = vimanMarketing.Id, File_URL__c = SHARE_LINK);
        insert vimanFile;
        insert new Amenties__c(Project__c = viman.Id, Type__c = 'Swimming Pool');
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ projectId('Victoria Golf Resort') });

        List<partnerWebPortalMarketingController.ProjectCard> cards;
        List<partnerWebPortalMarketingController.MediaFile> vimanFiles;
        List<partnerWebPortalMarketingController.Amenity> vimanAmenities;
        String detailError;
        Test.startTest();
        System.runAs(executive) {
            cards = partnerWebPortalMarketingController.getMarketingProjects();
            vimanFiles = partnerWebPortalMarketingController.getMarketingFiles(viman.Id);
            vimanAmenities = partnerWebPortalMarketingController.getProjectAmenities(viman.Id);
            try {
                partnerWebPortalMarketingController.getProjectDetails(viman.Id);
            } catch (AuraHandledException e) {
                detailError = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(1, cards.size(), 'Only their project: ' + cards);
        System.assertEquals('Victoria Golf Resort', cards[0].name);
        System.assertEquals(0, vimanFiles.size(), 'Not the files of a project they were not given, nor their links');
        System.assertEquals(1, partnerWebPortalMarketingController.getMarketingFiles(viman.Id).size(), 'A channel head or JKP user sees them');
        System.assertEquals(0, vimanAmenities.size(), 'Not the amenities of a project they were not given');
        System.assertEquals(1, partnerWebPortalMarketingController.getProjectAmenities(viman.Id).size(), 'A channel head or JKP user sees them');
        System.assertEquals('This project is not available.', detailError);
    }
}