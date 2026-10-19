@isTest
private class CreateSharePointFoldersQueueableTest {

    private static final String LIBRARY = 'callout:SharePoint_Graph/v1.0/drives/DRIVE-1';

    // Graph's folder creation in the SharePoint library, as the job calls it; remembers the folder names and addresses it got
    private class GraphMock implements HttpCalloutMock {
        Integer folderStatus = 201;
        Integer created = 0;
        List<String> names = new List<String>();
        List<String> urls = new List<String>();

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            urls.add(req.getMethod() + ' ' + req.getEndpoint());
            names.add((String) ((Map<String, Object>) JSON.deserializeUntyped(req.getBody())).get('name'));
            res.setStatusCode(folderStatus);
            res.setBody(folderStatus >= 200 && folderStatus < 300
                ? JSON.serialize(new Map<String, Object>{ 'id' => 'folder-' + (++created) })
                : '{"error":{"code":"invalidRequest"}}');
            return res;
        }
    }

    // A test library id, so the job never looks up the library
    private static GraphMock mockGraph() {
        SharePointService.testDriveId = 'DRIVE-1';
        GraphMock graph = new GraphMock();
        Test.setMock(HttpCalloutMock.class, graph);
        return graph;
    }

    private static void createChannelPartnerMaster() {
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id),
            new Document_category__c(Name = 'NIC, TIN and passport', Document_Master__c = master.Id)
        };
    }

    // The account's folder at the top of the library (its name made SharePoint-safe), then a Document per category; the
    // follow-up job gives the first Document its own sub-folder inside the account's folder
    @isTest
    static void givesAChannelPartnerAccountItsFolderAndDocuments() {
        createChannelPartnerMaster();
        // A placeholder folder id keeps the account trigger from queueing a job of its own
        Account partner = new Account(Name = 'M/s Harbour Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'pending');
        insert partner;
        GraphMock graph = mockGraph();

        Test.startTest();
        CreateSharePointFoldersQueueable.processData(partner.Id);
        Test.stopTest();

        System.assertEquals('folder-1', [SELECT Document_Id__c FROM Account WHERE Id = :partner.Id].Document_Id__c);
        System.assertEquals('M_s Harbour Realty', graph.names[0], 'A name SharePoint refuses is cleaned first');
        System.assertEquals('POST ' + LIBRARY + '/root/children', graph.urls[0], 'The account folder is at the top of the library');
        List<Document__c> documents = [SELECT Name, Document_Id__c FROM Document__c WHERE Account__c = :partner.Id ORDER BY Name];
        System.assertEquals(2, documents.size());
        System.assertEquals('BR, VAT Certificate', documents[0].Name);
        System.assertNotEquals(null, documents[0].Document_Id__c, 'The queued follow-up job made the Document its sub-folder');
        System.assertEquals('POST ' + LIBRARY + '/items/folder-1/children', graph.urls[1], 'Inside the account folder');
    }

    @isTest
    static void givesAProjectItsFolder() {
        Project__c project = new Project__c(Name = 'Skyline Towers', Active__c = true, Email__c = 'projects@example.com', Location__Latitude__s = 6.9271, Location__Longitude__s = 79.8612);
        insert project;
        GraphMock graph = mockGraph();

        Test.startTest();
        CreateSharePointFoldersQueueable.processData(project.Id);
        Test.stopTest();

        // (the job the project insert queued runs at stopTest too, so which mock folder the project ends with varies)
        System.assertNotEquals(null, [SELECT Document_Id__c FROM Project__c WHERE Id = :project.Id].Document_Id__c);
        System.assert([SELECT COUNT() FROM Document__c WHERE Project__c = :project.Id] > 0);
        System.assert(graph.urls.contains('POST ' + LIBRARY + '/root/children'), 'Project folders are at the top of the library: ' + graph.urls);
    }

    @isTest
    static void leavesTheRecordAloneWhenSharePointRefusesTheFolder() {
        createChannelPartnerMaster();
        Account partner = new Account(Name = 'Harbour Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'pending');
        insert partner;
        GraphMock graph = mockGraph();
        graph.folderStatus = 400;

        Test.startTest();
        CreateSharePointFoldersQueueable.processData(partner.Id);
        Test.stopTest();

        System.assertEquals(1, graph.urls.size(), 'SharePoint was asked once');
        System.assertEquals('pending', [SELECT Document_Id__c FROM Account WHERE Id = :partner.Id].Document_Id__c, 'Nothing is saved');
        System.assertEquals(0, [SELECT COUNT() FROM Document__c WHERE Account__c = :partner.Id]);
    }

    @isTest
    static void runsAsAQueuedJob() {
        createChannelPartnerMaster();
        Account partner = new Account(Name = 'Harbour Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = 'folder-root');
        insert partner;
        Document__c document = new Document__c(Name = 'BR, VAT Certificate', Account__c = partner.Id);
        insert document;
        GraphMock graph = mockGraph();

        Test.startTest();
        System.enqueueJob(new CreateSharePointFoldersQueueable(new List<Id>{ document.Id }));
        Test.stopTest();

        System.assertEquals('folder-1', [SELECT Document_Id__c FROM Document__c WHERE Id = :document.Id].Document_Id__c,
            'A Document gets its sub-folder inside its account\'s folder');
        System.assertEquals(new List<String>{ 'POST ' + LIBRARY + '/items/folder-root/children' }, graph.urls);
    }

    // A Document whose account has no folder yet, and a missing id, are skipped without calling SharePoint
    @isTest
    static void skipsADocumentWhoseParentHasNoFolderYet() {
        Account customer = new Account(Name = 'Harbour Realty');
        insert customer;
        Document__c document = new Document__c(Name = 'Legal', Account__c = customer.Id);
        insert document;
        GraphMock graph = mockGraph();

        Test.startTest();
        CreateSharePointFoldersQueueable.processData(document.Id);
        CreateSharePointFoldersQueueable.processData(null);
        Test.stopTest();

        System.assertEquals(0, graph.urls.size());
        System.assertEquals(null, [SELECT Document_Id__c FROM Document__c WHERE Id = :document.Id].Document_Id__c);
    }
}