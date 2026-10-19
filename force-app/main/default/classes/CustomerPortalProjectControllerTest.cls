// The Customer Portal's Projects page (CustomerPortalProjectController): a customer, who has no record access to
// projects, sees every active project with its photos and its page, each file with its Sub Document link and that
// link's direct form, without SharePoint being called; inactive projects are refused, other folders and the partners'
// Marketing folder are not on the page, and a guest gets nothing.
@isTest
private class CustomerPortalProjectControllerTest {

    private static final String SHARE_LINK = 'https://keells.sharepoint.com/:i:/s/JKPConnectDataHub/abc';
    // The direct form of SHARE_LINK (SharePointService.directUrl): the file itself, for <img>, <video> and downloads
    private static final String DIRECT_LINK = 'https://keells.sharepoint.com/sites/JKPConnectDataHub/_layouts/15/download.aspx?share=abc';
    private static final String CUSTOMER_NAME = 'Portal Customer Projects';
    private static final String ACTIVE = 'Customer View Towers';
    private static final String INACTIVE = 'Customer View Old Block';

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

        // A user with no access to projects, like a portal customer; runAs keeps the user apart from the records above
        // (a user and other records cannot be saved together).
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

    private static User customer() {
        return [SELECT Id FROM User WHERE LastName = :CUSTOMER_NAME AND Email LIKE 'customer.projects.%' LIMIT 1];
    }

    // The message the project page is refused with, or null when it opens
    private static String refusal(Id projectId) {
        try {
            CustomerPortalController.getProjectDetails(projectId);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void aCustomerSeesEveryActiveProjectWithItsPhotos() {
        List<partnerWebPortalMarketingController.ProjectCard> cards;
        Integer callouts;

        Test.startTest();
        System.runAs(customer()) {
            cards = CustomerPortalController.getProjects();
            callouts = Limits.getCallouts();
        }
        Test.stopTest();

        partnerWebPortalMarketingController.ProjectCard card;
        for (partnerWebPortalMarketingController.ProjectCard each : cards) {
            System.assertNotEquals(INACTIVE, each.name, 'Inactive projects are not listed');
            if (each.name == ACTIVE) {
                card = each;
            }
        }
        System.assertEquals(0, callouts, 'The links come from the Sub Documents: SharePoint is not called');
        System.assertNotEquals(null, card, 'Listed without any record access to the project');
        System.assertEquals(1, card.images.size(), 'The photos of the Project Images folder');
        System.assertEquals(DIRECT_LINK, card.images[0].mediaUrl, 'The photo is shown from the direct form of its link');
        System.assertEquals(SHARE_LINK, card.images[0].previewUrl);
    }

    // The page's documents and price sheets open in SharePoint from their own link and download from its direct form
    @isTest
    static void aCustomerOpensAProjectPage() {
        partnerWebPortalMarketingController.ProjectDetail detail;
        Integer callouts;

        Test.startTest();
        System.runAs(customer()) {
            detail = CustomerPortalController.getProjectDetails(projectId(ACTIVE));
            callouts = Limits.getCallouts();
        }
        Test.stopTest();

        System.assertEquals(0, callouts, 'SharePoint is not called');
        System.assertEquals(ACTIVE, detail.name);
        System.assertEquals(1, detail.images.size());
        System.assertEquals(DIRECT_LINK, detail.images[0].mediaUrl);
        System.assertEquals(1, detail.amenities.size());
        System.assertEquals('Swimming Pool', detail.amenities[0].label);
        System.assertEquals(1, detail.configurations.size());
        System.assertEquals('price-sheet.pdf', detail.configurations[0].priceSheet.name);
        System.assertEquals(SHARE_LINK, detail.configurations[0].priceSheet.previewUrl);
        System.assertEquals(DIRECT_LINK, detail.configurations[0].priceSheet.mediaUrl);
        System.assertEquals(1, detail.documents.size(), 'Only the Project Documents folder: no Marketing or Legal files');
        System.assertEquals('brochure.pdf', detail.documents[0].name);
        System.assertEquals(SHARE_LINK, detail.documents[0].previewUrl);
        System.assertEquals(DIRECT_LINK, detail.documents[0].mediaUrl);
    }

    @isTest
    static void anInactiveProjectIsRefused() {
        Id inactiveProjectId = projectId(INACTIVE);
        String inactiveProject;

        Test.startTest();
        System.runAs(customer()) {
            inactiveProject = refusal(inactiveProjectId);
        }
        Test.stopTest();

        System.assertEquals('This project is not available.', inactiveProject);
    }

    @isTest
    static void aGuestGetsNothing() {
        CustomerPortalController.guestOverride = true;
        String projects;
        try {
            CustomerPortalController.getProjects();
        } catch (AuraHandledException e) {
            projects = e.getMessage();
        }

        System.assertEquals(CustomerPortalController.CUSTOMER_PORTAL_LOGIN_REQUIRED, projects);
        System.assertEquals(CustomerPortalController.CUSTOMER_PORTAL_LOGIN_REQUIRED, refusal(projectId(ACTIVE)));
    }
}