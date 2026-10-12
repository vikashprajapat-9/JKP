@isTest
private class CreateOneDriveFoldersQueueableTest {

    // Microsoft's token endpoint and Graph's folder creation, as the job calls them; remembers the folder names it got
    private class GraphMock implements HttpCalloutMock {
        Integer folderStatus = 201;
        Integer created = 0;
        List<String> names = new List<String>();

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/oauth2/')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"test-token"}');
                return res;
            }
            names.add((String) ((Map<String, Object>) JSON.deserializeUntyped(req.getBody())).get('name'));
            res.setStatusCode(folderStatus);
            res.setBody(folderStatus >= 200 && folderStatus < 300
                ? JSON.serialize(new Map<String, Object>{ 'id' => 'folder-' + (++created) })
                : '{"error":{"code":"invalidRequest"}}');
            return res;
        }
    }

    private static Boolean hasOneDriveSetup() {
        return [SELECT COUNT() FROM OneDriveAuthSetting__mdt] > 0;
    }

    private static void createChannelPartnerMaster() {
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id),
            new Document_category__c(Name = 'NIC, TIN and passport', Document_Master__c = master.Id)
        };
    }

    // The account's folder (its name made OneDrive-safe), then a Document per category; the follow-up job gives the
    // first Document its own sub-folder
    @isTest
    static void givesAChannelPartnerAccountItsFolderAndDocuments() {
        System.assert(hasOneDriveSetup(), 'The OneDrive credentials record must exist in the org');
        createChannelPartnerMaster();
        // A placeholder folder id keeps the account trigger from queueing a job of its own
        Account partner = new Account(Name = 'M/s Harbour Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'pending');
        insert partner;
        GraphMock graph = new GraphMock();
        Test.setMock(HttpCalloutMock.class, graph);

        Test.startTest();
        CreateOneDriveFoldersQueueable.processData(partner.Id);
        Test.stopTest();

        System.assertEquals('folder-1', [SELECT Document_Id__c FROM Account WHERE Id = :partner.Id].Document_Id__c);
        System.assertEquals('M_s Harbour Realty', graph.names[0], 'A name OneDrive refuses is cleaned first');
        List<Document__c> documents = [SELECT Name, Document_Id__c FROM Document__c WHERE Account__c = :partner.Id ORDER BY Name];
        System.assertEquals(2, documents.size());
        System.assertEquals('BR, VAT Certificate', documents[0].Name);
        System.assertNotEquals(null, documents[0].Document_Id__c, 'The queued follow-up job made the Document its sub-folder');
    }

    @isTest
    static void givesAProjectItsFolder() {
        System.assert(hasOneDriveSetup(), 'The OneDrive credentials record must exist in the org');
        Project__c project = new Project__c(Name = 'Skyline Towers', Active__c = true);
        insert project;
        Test.setMock(HttpCalloutMock.class, new GraphMock());

        Test.startTest();
        CreateOneDriveFoldersQueueable.processData(project.Id);
        Test.stopTest();

        // (the job the project insert queued runs at stopTest too, so which mock folder the project ends with varies)
        System.assertNotEquals(null, [SELECT Document_Id__c FROM Project__c WHERE Id = :project.Id].Document_Id__c);
        System.assert([SELECT COUNT() FROM Document__c WHERE Project__c = :project.Id] > 0);
    }

    @isTest
    static void leavesTheRecordAloneWhenOneDriveRefusesTheFolder() {
        System.assert(hasOneDriveSetup(), 'The OneDrive credentials record must exist in the org');
        createChannelPartnerMaster();
        Account partner = new Account(Name = 'Harbour Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'pending');
        insert partner;
        GraphMock graph = new GraphMock();
        graph.folderStatus = 400;
        Test.setMock(HttpCalloutMock.class, graph);

        Test.startTest();
        CreateOneDriveFoldersQueueable.processData(partner.Id);
        Test.stopTest();

        System.assertEquals('pending', [SELECT Document_Id__c FROM Account WHERE Id = :partner.Id].Document_Id__c, 'Nothing is saved');
        System.assertEquals(0, [SELECT COUNT() FROM Document__c WHERE Account__c = :partner.Id]);
    }

    @isTest
    static void runsAsAQueuedJob() {
        System.assert(hasOneDriveSetup(), 'The OneDrive credentials record must exist in the org');
        createChannelPartnerMaster();
        Account partner = new Account(Name = 'Harbour Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'folder-root');
        insert partner;
        Document__c document = new Document__c(Name = 'BR, VAT Certificate', Account__c = partner.Id);
        insert document;
        Test.setMock(HttpCalloutMock.class, new GraphMock());

        Test.startTest();
        System.enqueueJob(new CreateOneDriveFoldersQueueable(new List<Id>{ document.Id }));
        Test.stopTest();

        System.assertEquals('folder-1', [SELECT Document_Id__c FROM Document__c WHERE Id = :document.Id].Document_Id__c,
            'A Document gets its sub-folder inside its account\'s folder');
    }
}