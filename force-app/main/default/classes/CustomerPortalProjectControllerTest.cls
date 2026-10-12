// The Customer Portal's Projects page (CustomerPortalProjectController): a customer, who has no record access to
// projects, sees every active project with its OneDrive photos, its page and the previews of the files that page
// shows; inactive projects, other folders and the partners' Marketing folder are refused, and a guest gets nothing.
@isTest
private class CustomerPortalProjectControllerTest {

    private static final String SHARE_LINK = 'https://utillabs-my.sharepoint.com/:i:/g/personal/test/abc';
    private static final String PREVIEW_URL = 'https://utillabs-my.sharepoint.com/_layouts/15/embed.aspx?x=1';
    private static final String CUSTOMER_NAME = 'Portal Customer Projects';
    private static final String ACTIVE = 'Customer View Towers';
    private static final String INACTIVE = 'Customer View Old Block';

    // Answers the Graph $batch call with each folder's files and their direct download URLs, the file lookup (as if
    // the file were in the given OneDrive folder) and the preview action
    private class GraphMock implements HttpCalloutMock {
        private String parentId;

        GraphMock(String parentId) {
            this.parentId = parentId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String url = req.getEndpoint();
            if (url.contains('$batch')) {
                List<Object> responses = new List<Object>();
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
                for (Object r : (List<Object>) body.get('requests')) {
                    responses.add(new Map<String, Object>{
                        'id' => ((Map<String, Object>) r).get('id'),
                        'status' => 200,
                        'body' => new Map<String, Object>{ 'value' => new List<Object>{
                            child('front.jpg'), child('brochure.pdf'), child('price-sheet.pdf')
                        } }
                    });
                }
                res.setBody(JSON.serialize(new Map<String, Object>{ 'responses' => responses }));
            } else if (url.endsWith('/preview')) {
                res.setBody('{"getUrl":"' + PREVIEW_URL + '"}');
            } else {
                res.setBody('{"id":"ITEM-1","parentReference":{"id":"' + parentId + '"}}');
            }
            return res;
        }

        private Map<String, Object> child(String name) {
            return new Map<String, Object>{
                'name' => name,
                '@microsoft.graph.downloadUrl' => 'https://utillabs-my.sharepoint.com/download/' + name
            };
        }
    }

    @testSetup
    static void setup() {
        Project__c active = TestRecordDefaults.project(ACTIVE, true);
        Project__c inactive = TestRecordDefaults.project(INACTIVE, false);
        insert new List<Project__c>{ active, inactive };

        insert new Amenties__c(Project__c = active.Id, Type__c = 'Swimming Pool');
        Project_Configuration__c twoBr = new Project_Configuration__c(Project__c = active.Id, Unit_Type__c = '2 BR', Starting_Price__c = 9800000, Square_FT__c = 1100);
        insert twoBr;

        Document__c images = new Document__c(Name = 'Project Images', Project__c = active.Id, Document_Id__c = 'IMAGES-FOLDER');
        Document__c documents = new Document__c(Name = 'Project Documents', Project__c = active.Id, Document_Id__c = 'DOCUMENTS-FOLDER');
        Document__c marketing = new Document__c(Name = 'Marketing', Project__c = active.Id, Document_Id__c = 'MARKETING-FOLDER');
        Document__c legal = new Document__c(Name = 'Legal', Project__c = active.Id, Document_Id__c = 'LEGAL-FOLDER');
        Document__c priceSheets = new Document__c(Name = 'PC-2BR', Project_Configuration__c = twoBr.Id, Document_Id__c = 'CONFIG-FOLDER');
        Document__c oldDocuments = new Document__c(Name = 'Project Documents', Project__c = inactive.Id, Document_Id__c = 'OLD-FOLDER');
        insert new List<Document__c>{ images, documents, marketing, legal, priceSheets, oldDocuments };

        Sub_Document__c priceSheet = new Sub_Document__c(Name = 'price-sheet.pdf', Document__c = priceSheets.Id, File_URL__c = SHARE_LINK);
        insert new List<Sub_Document__c>{
            new Sub_Document__c(Name = 'front.jpg', Document__c = images.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'brochure.pdf', Document__c = documents.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'partner-deck.pdf', Document__c = marketing.Id, File_URL__c = SHARE_LINK),
            new Sub_Document__c(Name = 'title-deed.pdf', Document__c = legal.Id, File_URL__c = SHARE_LINK),
            priceSheet,
            new Sub_Document__c(Name = 'brochure.pdf', Document__c = oldDocuments.Id, File_URL__c = SHARE_LINK)
        };
        twoBr.Sub_Document__c = priceSheet.Id;
        update twoBr;

        // A user with no access to projects, like a portal customer. Created here, because a test may not call
        // OneDrive after it has saved a record; runAs keeps the user apart from the records above.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile profile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
            String unique = 'customer.projects.' + Crypto.getRandomInteger() + '@example.com';
            insert new User(LastName = CUSTOMER_NAME, Alias = 'pcust', Email = unique, Username = unique, ProfileId = profile.Id,
                TimeZoneSidKey = 'Asia/Colombo', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        }
    }

    private static Id projectId(String name) {
        return [SELECT Id FROM Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static Id fileId(String name, String folder, String projectName) {
        return [SELECT Id FROM Sub_Document__c
            WHERE Name = :name AND Document__r.Name = :folder
                AND (Document__r.Project__r.Name = :projectName OR Document__r.Project_Configuration__r.Project__r.Name = :projectName)
            WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static User customer() {
        return [SELECT Id FROM User WHERE LastName = :CUSTOMER_NAME AND Email LIKE 'customer.projects.%' LIMIT 1];
    }

    // The message a call is refused with: the project page when projectId is given, else the file preview
    private static String refusal(Id projectId, Id subDocumentId) {
        try {
            if (projectId != null) {
                CustomerPortalProjectController.getProjectDetails(projectId);
            } else {
                CustomerPortalProjectController.getFilePreviewUrl(subDocumentId);
            }
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void aCustomerSeesEveryActiveProjectWithItsPhotos() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphMock('IMAGES-FOLDER'));
        List<partnerWebPortalMarketingController.ProjectCard> cards;

        Test.startTest();
        System.runAs(customer()) {
            cards = CustomerPortalProjectController.getProjects();
        }
        Test.stopTest();

        partnerWebPortalMarketingController.ProjectCard card;
        for (partnerWebPortalMarketingController.ProjectCard each : cards) {
            System.assertNotEquals(INACTIVE, each.name, 'Inactive projects are not listed');
            if (each.name == ACTIVE) {
                card = each;
            }
        }
        System.assertNotEquals(null, card, 'Listed without any record access to the project');
        System.assertEquals(1, card.images.size(), 'The photos of the Project Images folder');
        System.assertEquals('https://utillabs-my.sharepoint.com/download/front.jpg', card.images[0].mediaUrl,
            'A direct OneDrive link, which needs no Microsoft sign-in');
    }

    @isTest
    static void aCustomerOpensAProjectPage() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphMock('IMAGES-FOLDER'));
        partnerWebPortalMarketingController.ProjectDetail detail;

        Test.startTest();
        System.runAs(customer()) {
            detail = CustomerPortalProjectController.getProjectDetails(projectId(ACTIVE));
        }
        Test.stopTest();

        System.assertEquals(ACTIVE, detail.name);
        System.assertEquals(1, detail.images.size());
        System.assertEquals(1, detail.amenities.size());
        System.assertEquals('Swimming Pool', detail.amenities[0].label);
        System.assertEquals(1, detail.configurations.size());
        System.assertEquals('price-sheet.pdf', detail.configurations[0].priceSheet.name);
        System.assertEquals(1, detail.documents.size(), 'Only the Project Documents folder: no Marketing or Legal files');
        System.assertEquals('brochure.pdf', detail.documents[0].name);
    }

    @isTest
    static void aCustomerPreviewsProjectDocumentsAndPriceSheets() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Id brochure = fileId('brochure.pdf', 'Project Documents', ACTIVE);
        Id priceSheet = fileId('price-sheet.pdf', 'PC-2BR', ACTIVE);
        String brochureUrl;
        String priceSheetUrl;

        Test.startTest();
        System.runAs(customer()) {
            Test.setMock(HttpCalloutMock.class, new GraphMock('DOCUMENTS-FOLDER'));
            brochureUrl = CustomerPortalProjectController.getFilePreviewUrl(brochure);
            Test.setMock(HttpCalloutMock.class, new GraphMock('CONFIG-FOLDER'));
            priceSheetUrl = CustomerPortalProjectController.getFilePreviewUrl(priceSheet);
        }
        Test.stopTest();

        System.assertEquals(PREVIEW_URL, brochureUrl);
        System.assertEquals(PREVIEW_URL, priceSheetUrl);
    }

    @isTest
    static void inactiveProjectsOtherFoldersAndMarketingFilesAreRefused() {
        partnerWebPortalMarketingController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphMock('MARKETING-FOLDER'));
        Id inactiveProjectId = projectId(INACTIVE);
        Id inactiveFileId = fileId('brochure.pdf', 'Project Documents', INACTIVE);
        Id legalFileId = fileId('title-deed.pdf', 'Legal', ACTIVE);
        Id marketingFileId = fileId('partner-deck.pdf', 'Marketing', ACTIVE);
        String inactiveProject;
        String inactiveFile;
        String legalFile;
        String marketingFile;

        Test.startTest();
        System.runAs(customer()) {
            inactiveProject = refusal(inactiveProjectId, null);
            inactiveFile = refusal(null, inactiveFileId);
            legalFile = refusal(null, legalFileId);
            marketingFile = refusal(null, marketingFileId);
        }
        Test.stopTest();

        System.assertEquals('This project is not available.', inactiveProject);
        System.assertEquals(Label.Customer_Portal_File_Not_Available, inactiveFile);
        System.assertEquals(Label.Customer_Portal_File_Not_Available, legalFile, 'Only folders the portals show');
        System.assertEquals(Label.Customer_Portal_File_Not_Available, marketingFile, 'The Marketing folder is for partners only');
    }

    @isTest
    static void aGuestGetsNothing() {
        CustomerPortalProjectController.guestOverride = true;
        String projects;
        try {
            CustomerPortalProjectController.getProjects();
        } catch (AuraHandledException e) {
            projects = e.getMessage();
        }

        System.assertEquals(Label.Customer_Portal_Login_Required, projects);
        System.assertEquals(Label.Customer_Portal_Login_Required, refusal(projectId(ACTIVE), null));
        System.assertEquals(Label.Customer_Portal_Login_Required, refusal(null, fileId('brochure.pdf', 'Project Documents', ACTIVE)));
    }
}