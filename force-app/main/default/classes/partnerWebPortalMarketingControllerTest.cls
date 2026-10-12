@isTest
private class partnerWebPortalMarketingControllerTest {

    private static final String SHARE_LINK = 'https://utillabs-my.sharepoint.com/:i:/g/personal/test/abc';

    // Answers the Graph $batch call with each folder's children and their direct download URLs
    private class GraphBatchMock implements HttpCalloutMock {
        private Integer status;

        GraphBatchMock(Integer status) {
            this.status = status;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(status);
            if (status != 200) {
                res.setBody('{"error":{"code":"serviceNotAvailable"}}');
                return res;
            }
            List<Object> responses = new List<Object>();
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            for (Object r : (List<Object>) body.get('requests')) {
                Map<String, Object> request = (Map<String, Object>) r;
                responses.add(new Map<String, Object>{
                    'id' => request.get('id'),
                    'status' => 200,
                    'body' => new Map<String, Object>{ 'value' => new List<Object>{
                        child('A1.JPG'), child('brochure.pdf'), child('walkthrough.mp4')
                    } }
                });
            }
            res.setBody(JSON.serialize(new Map<String, Object>{ 'responses' => responses }));
            return res;
        }

        private Map<String, Object> child(String name) {
            return new Map<String, Object>{
                'name' => name,
                '@microsoft.graph.downloadUrl' => 'https://utillabs-my.sharepoint.com/download/' + name
            };
        }
    }

    // For a test that adds accounts and a project: their OneDrive folder jobs end quietly (503) after the token, and the
    // Graph $batch call answers as above
    private class FolderJobsAndBatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            if (req.getEndpoint().contains('$batch')) {
                return new GraphBatchMock(200).respond(req);
            }
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/oauth2/')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"test-token"}');
            } else {
                res.setStatusCode(503);
                res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            }
            return res;
        }
    }

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
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphBatchMock(200));

        Test.startTest();
        List<partnerWebPortalMarketingController.ProjectCard> cards = partnerWebPortalMarketingController.getMarketingProjects();
        Test.stopTest();

        System.assertEquals(1, cards.size(), 'Only active projects are listed');
        System.assertEquals('Victoria Golf Resort', cards[0].name);
        System.assertEquals(1, cards[0].images.size(), 'PDFs in Project Images and files in other folders are not card images');
        System.assertEquals('A1.JPG', cards[0].images[0].name);
        System.assertEquals('image', cards[0].images[0].fileType);
        System.assertEquals(SHARE_LINK, cards[0].images[0].previewUrl);
        System.assertEquals('https://utillabs-my.sharepoint.com/download/A1.JPG', cards[0].images[0].mediaUrl);
    }

    @isTest
    static void marketingFolderReturnsEveryFileWithItsType() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphBatchMock(200));

        Test.startTest();
        List<partnerWebPortalMarketingController.MediaFile> files = partnerWebPortalMarketingController.getMarketingFiles(projectId('Victoria Golf Resort'));
        Test.stopTest();

        System.assertEquals(2, files.size(), 'Only the Marketing folder is read');
        Map<String, partnerWebPortalMarketingController.MediaFile> byName = new Map<String, partnerWebPortalMarketingController.MediaFile>();
        for (partnerWebPortalMarketingController.MediaFile file : files) {
            byName.put(file.name, file);
        }
        System.assertEquals('pdf', byName.get('brochure.pdf').fileType);
        System.assertEquals('video', byName.get('walkthrough.mp4').fileType);
        System.assertEquals('https://utillabs-my.sharepoint.com/download/walkthrough.mp4', byName.get('walkthrough.mp4').mediaUrl);
    }

    @isTest
    static void filesAreStillListedWhenOneDriveIsUnavailable() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphBatchMock(503));

        Test.startTest();
        List<partnerWebPortalMarketingController.MediaFile> files = partnerWebPortalMarketingController.getMarketingFiles(projectId('Victoria Golf Resort'));
        Test.stopTest();

        System.assertEquals(2, files.size());
        for (partnerWebPortalMarketingController.MediaFile file : files) {
            System.assertEquals(null, file.mediaUrl, 'No inline preview without OneDrive');
            System.assertEquals(SHARE_LINK, file.previewUrl, 'The share link is still available');
        }
    }

    private static final String PREVIEW_URL = 'https://utillabs-my.sharepoint.com/_layouts/15/embed.aspx?x=1';

    // Answers the file lookup, as if the file were in the given OneDrive folder, and the preview action; records how
    // the file was found
    private class PreviewMock implements HttpCalloutMock {
        private String parentId;
        public List<String> calls = new List<String>();

        PreviewMock(String parentId) {
            this.parentId = parentId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String url = req.getEndpoint();
            if (url.endsWith('/preview')) {
                calls.add('POST preview');
                res.setBody('{"getUrl":"' + PREVIEW_URL + '"}');
            } else {
                calls.add(url.contains('/shares/') ? 'GET share' : 'GET name');
                res.setBody('{"id":"ITEM-1","parentReference":{"id":"' + parentId + '"}}');
            }
            return res;
        }
    }

    private static Id subDocumentId(String name, String folder) {
        return [SELECT Id FROM Sub_Document__c WHERE Name = :name AND Document__r.Name = :folder WITH SYSTEM_MODE LIMIT 1].Id;
    }

    @isTest
    static void previewsMarketingDocumentsInsideThePortal() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        PreviewMock graph = new PreviewMock('MARKETING-FOLDER');
        Test.setMock(HttpCalloutMock.class, graph);

        Test.startTest();
        String url = partnerWebPortalMarketingController.getFilePreviewUrl(subDocumentId('brochure.pdf', 'Marketing'));
        Test.stopTest();

        System.assertEquals(PREVIEW_URL, url);
        System.assertEquals(new List<String>{ 'GET share', 'POST preview' }, graph.calls,
            'Found through its share link, which still works when OneDrive has a longer or changed name');
    }

    @isTest
    static void looksUpAFileWithoutALinkByNameAndRefusesOneThatLeftItsFolder() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Id marketing = [SELECT Id FROM Document__c WHERE Document_Id__c = 'MARKETING-FOLDER' WITH SYSTEM_MODE].Id;
        Sub_Document__c noLink = new Sub_Document__c(Name = 'price list.pdf', Document__c = marketing);
        insert noLink;
        PreviewMock inFolder = new PreviewMock('MARKETING-FOLDER');
        String moved;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, inFolder);
        String url = partnerWebPortalMarketingController.getFilePreviewUrl(noLink.Id);
        Test.setMock(HttpCalloutMock.class, new PreviewMock('SOME-OTHER-FOLDER'));
        try {
            partnerWebPortalMarketingController.getFilePreviewUrl(subDocumentId('brochure.pdf', 'Marketing'));
        } catch (AuraHandledException e) {
            moved = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(PREVIEW_URL, url);
        System.assertEquals(new List<String>{ 'GET name', 'POST preview' }, inFolder.calls);
        System.assert(moved != null && moved.contains('no longer in its folder'), moved);
    }

    @isTest
    static void refusesPreviewsOutsideTheMarketingFolders() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new PreviewMock('LEGAL-FOLDER'));
        Boolean refused = false;

        Test.startTest();
        try {
            partnerWebPortalMarketingController.getFilePreviewUrl(subDocumentId('contract.pdf', 'Legal'));
        } catch (AuraHandledException e) {
            refused = e.getMessage().contains('cannot be previewed');
        }
        Test.stopTest();

        System.assert(refused, 'Files outside Marketing / Project Images must not be previewed');
    }

    @isTest
    static void inactiveProjectsShowNoMarketingFiles() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphBatchMock(200));
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

    @isTest
    static void buildsTheWholeProjectPageFromSalesforceAndOneDrive() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphBatchMock(200));
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
        Sub_Document__c newer = new Sub_Document__c(Name = 'price-sheet-v2.pdf', Document__c = threeBrFolder.Id, File_URL__c = SHARE_LINK);
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
        Test.stopTest();

        System.assertEquals('Victoria Golf Resort', detail.name);
        System.assertEquals('In Progress', detail.status);
        System.assertEquals(Date.newInstance(2026, 7, 1), detail.possession);
        System.assertEquals('4.5 Acres', detail.landParcel);
        System.assertEquals(1, detail.images.size(), 'Only photos from the Project Images folder');
        System.assertEquals('A1.JPG', detail.images[0].name);
        System.assertNotEquals(null, detail.images[0].mediaUrl, 'Photos get a direct link for the slideshow');
        System.assertEquals(1, detail.amenities.size());
        System.assertEquals('waves', detail.amenities[0].icon);
        System.assertEquals(2, detail.configurations.size());
        System.assertEquals('2 BR', detail.configurations[0].unitType, 'In unit type order');
        System.assertEquals(null, detail.configurations[0].priceSheet, 'A configuration without a file shows none, even with files left in its folder');
        System.assertEquals(16400000, detail.configurations[1].startingPrice);
        System.assertEquals(1560, detail.configurations[1].squareFt);
        System.assertEquals('price-sheet-v2.pdf', detail.configurations[1].priceSheet.name, 'The latest upload is the price sheet');
        System.assertEquals(1, detail.documents.size(), 'Only files from the Project Documents folder, not those of configurations');
        System.assertEquals('site-plan.pdf', detail.documents[0].name);
    }

    @isTest
    static void onlyFilesInTheConfigurationsOwnFolderArePriceSheets() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphBatchMock(200));
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
    static void previewsProjectDocumentsAndPriceSheets() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Id active = projectId('Victoria Golf Resort');
        Document__c documents = new Document__c(Name = 'Project Documents', Project__c = active, Document_Id__c = 'DOCUMENTS-FOLDER');
        insert documents;
        Sub_Document__c sitePlan = new Sub_Document__c(Name = 'site-plan.pdf', Document__c = documents.Id, File_URL__c = SHARE_LINK);
        insert sitePlan;
        Project_Configuration__c config = new Project_Configuration__c(Project__c = active, Unit_Type__c = '2 BR');
        insert config;
        Document__c configFolder = new Document__c(Name = 'PC-2BR', Project_Configuration__c = config.Id, Document_Id__c = 'CONFIG-FOLDER');
        insert configFolder;
        Sub_Document__c priceSheet = new Sub_Document__c(Name = 'price-sheet.pdf', Document__c = configFolder.Id, File_URL__c = SHARE_LINK);
        insert priceSheet;
        config.Sub_Document__c = priceSheet.Id;
        update config;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PreviewMock('DOCUMENTS-FOLDER'));
        String sitePlanUrl = partnerWebPortalMarketingController.getFilePreviewUrl(sitePlan.Id);
        Test.setMock(HttpCalloutMock.class, new PreviewMock('CONFIG-FOLDER'));
        String priceSheetUrl = partnerWebPortalMarketingController.getFilePreviewUrl(priceSheet.Id);
        Test.stopTest();

        System.assertEquals(PREVIEW_URL, sitePlanUrl);
        System.assertEquals(PREVIEW_URL, priceSheetUrl);
    }

    @isTest
    static void refusesPreviewsOfFilesThePortalDoesNotShow() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new PreviewMock('CONFIG-FOLDER'));
        Id active = projectId('Victoria Golf Resort');
        // A Legal file linked to a configuration by hand
        Id contract = subDocumentId('contract.pdf', 'Legal');
        insert new Project_Configuration__c(Project__c = active, Unit_Type__c = '3 BR', Sub_Document__c = contract);
        // A file left in the folder of a configuration whose file was removed
        Project_Configuration__c withoutFile = new Project_Configuration__c(Project__c = active, Unit_Type__c = '2 BR');
        insert withoutFile;
        Document__c folder = new Document__c(Name = 'PC-2BR', Project_Configuration__c = withoutFile.Id, Document_Id__c = 'CONFIG-FOLDER');
        insert folder;
        Sub_Document__c oldSheet = new Sub_Document__c(Name = 'old-prices.pdf', Document__c = folder.Id, File_URL__c = SHARE_LINK);
        insert oldSheet;
        List<String> messages = new List<String>();

        Test.startTest();
        for (Id fileId : new List<Id>{ contract, oldSheet.Id }) {
            try {
                partnerWebPortalMarketingController.getFilePreviewUrl(fileId);
                messages.add('previewed');
            } catch (AuraHandledException e) {
                messages.add(e.getMessage());
            }
        }
        Test.stopTest();

        System.assertEquals(new List<String>{ 'This file cannot be previewed.', 'This file cannot be previewed.' }, messages);
    }

    @isTest
    static void refusesPreviewsOfInactiveProjects() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new PreviewMock('OLD-MARKETING'));
        Document__c oldMarketing = new Document__c(Name = 'Marketing', Project__c = projectId('Old Tower'), Document_Id__c = 'OLD-MARKETING');
        insert oldMarketing;
        Sub_Document__c oldBrochure = new Sub_Document__c(Name = 'old-brochure.pdf', Document__c = oldMarketing.Id, File_URL__c = SHARE_LINK);
        insert oldBrochure;
        String message;

        Test.startTest();
        try {
            partnerWebPortalMarketingController.getFilePreviewUrl(oldBrochure.Id);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assert(message != null && message.contains('cannot be previewed'), message);
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
        partnerWebPortalMarketingController.accessToken = 'test-token';
        List<partnerWebPortalMarketingController.ProjectCard> cards;
        List<partnerWebPortalMarketingController.MediaFile> marketing;
        partnerWebPortalMarketingController.ProjectDetail detail;
        String preview;

        Test.startTest();
        System.runAs(partner) {
            Test.setMock(HttpCalloutMock.class, new GraphBatchMock(200));
            cards = partnerWebPortalMarketingController.getMarketingProjects();
            marketing = partnerWebPortalMarketingController.getMarketingFiles(active);
            detail = partnerWebPortalMarketingController.getProjectDetails(active);
            Test.setMock(HttpCalloutMock.class, new PreviewMock('CONFIG-FOLDER'));
            preview = partnerWebPortalMarketingController.getFilePreviewUrl(priceSheet.Id);
        }
        Test.stopTest();

        System.assertEquals(1, cards.size(), 'The active project is listed for partners');
        System.assertEquals(1, cards[0].images.size());
        System.assertEquals(2, marketing.size());
        System.assertEquals('Victoria Golf Resort', detail.name);
        System.assertEquals(1, detail.amenities.size());
        System.assertEquals('price-sheet.pdf', detail.configurations[0].priceSheet.name);
        System.assertEquals(PREVIEW_URL, preview);
    }

    // An executive sees only the projects their channel head gave them: the others' pages, files and previews are refused
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
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new FolderJobsAndBatchMock());

        List<partnerWebPortalMarketingController.ProjectCard> cards;
        List<partnerWebPortalMarketingController.MediaFile> vimanFiles;
        List<partnerWebPortalMarketingController.Amenity> vimanAmenities;
        String detailError;
        String previewError;
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
            try {
                partnerWebPortalMarketingController.getFilePreviewUrl(vimanFile.Id);
            } catch (AuraHandledException e) {
                previewError = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(1, cards.size(), 'Only their project: ' + cards);
        System.assertEquals('Victoria Golf Resort', cards[0].name);
        System.assertEquals(0, vimanFiles.size());
        System.assertEquals(0, vimanAmenities.size(), 'Not the amenities of a project they were not given');
        System.assertEquals(1, partnerWebPortalMarketingController.getProjectAmenities(viman.Id).size(), 'A channel head or JKP user sees them');
        System.assertEquals('This project is not available.', detailError);
        System.assertEquals('This file cannot be previewed.', previewError);
    }
}